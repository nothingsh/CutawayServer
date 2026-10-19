import CutawayWire
import Foundation
import UIKit

@testable import CutawayServer

/// A session over a fake transport, on a queue of its own.
final class SessionHarness: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.cutaway.tests.session")
    let transport = FakeTransport()
    let capture: ScriptedCapture
    /// The host app's environment; main thread only.
    let environment = ScriptedEnvironment()
    /// Dropped by `releaseSession()`, so that a test can see what the session kept alive.
    private var session: Session!
    private let state = StateBox()

    private final class StateBox: SessionDelegate, @unchecked Sendable {
        // Touched on the session's queue only.
        var endedCount = 0
        var subtreeRoots: [UInt64] = []
        /// The version each hierarchy and subtree was read for.
        var captureVersions: [ProtocolVersion] = []
        var changes: [SetAttribute] = []
        var leavesActiveStateWhileReading = false
        weak var session: Session?

        func sessionDidEnd(_ session: Session) {
            endedCount += 1
        }
    }

    /// The host app as the harness plays it: what the real one reads from UIKit comes from
    /// the values below, and the subtree and change steps are recorded. On the main thread,
    /// like the real one; `HostAccess` brings every answer back to the queue.
    /// The environment as the harness plays it, on the main thread: no window is touched.
    @MainActor
    final class ScriptedEnvironment {
        var overrides = Traits.none
        var overridable: [TraitKind] = TraitKind.allCases
        /// How many times the session asked for its overrides to be removed.
        var removals = 0
        /// The traits each accepted `SetEnvironment` asked for, in order.
        var applied: [Traits] = []

        nonisolated init() {}
    }

    private struct ScriptedApp: HostApp {
        let queue: DispatchQueue
        let state: StateBox
        let environment: ScriptedEnvironment

        @MainActor
        func appInfo() -> AppInfo {
            SessionHarness.app
        }

        @MainActor
        func iconImage() -> UIImage? {
            nil
        }

        @MainActor
        func captureHierarchy(registry: LayerRegistry, version: ProtocolVersion) -> Hierarchy {
            let state = self.state
            queue.async { state.captureVersions.append(version) }
            return SessionHarness.hierarchy
        }

        @MainActor
        func captureSubtree(of rootID: UInt64, registry: LayerRegistry, version: ProtocolVersion) -> Hierarchy? {
            let state = self.state
            queue.async {
                state.subtreeRoots.append(rootID)
                state.captureVersions.append(version)
                if state.leavesActiveStateWhileReading {
                    // As the server controller does: the session is told the state changed before
                    // the subtree that was being read arrives.
                    state.session?.appStateDidChange(.background)
                }
            }
            return SessionHarness.subtree(of: rootID)
        }

        @MainActor
        func setAttribute(_ change: SetAttribute, registry: LayerRegistry)
            -> Result<SetAttributeResult, WireError> {
            let state = self.state
            queue.async { state.changes.append(change) }
            return SessionHarness.result(of: change)
        }

        @MainActor
        func environment(overrides: EnvironmentOverrides) -> Environment {
            Environment(
                overrides: environment.overrides,
                current: SessionHarness.current,
                overridable: environment.overridable
            )
        }

        @MainActor
        func setEnvironment(_ traits: Traits, overrides: EnvironmentOverrides) -> Result<Environment, WireError> {
            if let refusal = EnvironmentOverrides.refusal(of: traits, overridable: environment.overridable) {
                return .failure(refusal)
            }
            environment.overrides = traits
            environment.applied.append(traits)
            return .success(self.environment(overrides: overrides))
        }

        @MainActor
        func removeOverrides(_ overrides: EnvironmentOverrides) {
            environment.overrides = .none
            environment.removals += 1
        }

        // The stream never gets here: the harness scripts its pipeline.

        @MainActor
        func captureDetail(
            _ request: LayerDetailRequest,
            maxTextureDimension: UInt32,
            registry: LayerRegistry,
            stopFlag: StopFlag
        ) -> CapturedDetail? {
            nil
        }
    }

    /// The stream's pipeline as the harness plays it: the scripted capture, on the queue.
    private struct ScriptedPipeline: DetailPipeline {
        let capture: ScriptedCapture
        let queue: DispatchQueue

        func captureDetail(
            _ request: LayerDetailRequest,
            maxTextureDimension: UInt32,
            stopFlag: StopFlag,
            then answer: @escaping @Sendable (CapturedDetail?) -> Void
        ) {
            capture.capture(request, stopFlag: stopFlag, on: queue, then: answer)
        }

        func encodeDetail(
            _ detail: CapturedDetail,
            stopFlag: StopFlag,
            then answer: @escaping @Sendable (LayerDetail) -> Void
        ) {
            capture.encode(detail, stopFlag: stopFlag, on: queue, then: answer)
        }
    }

    static let app = AppInfo(
        name: "Harness",
        bundleID: "dev.cutaway.harness",
        appVersion: "1",
        deviceName: "Test",
        deviceKind: .phone,
        isSimulator: true,
        osName: "iOS",
        osVersion: "1",
        screenSize: WireSize(width: 1, height: 1),
        screenScale: 1,
        serverVersion: "0"
    )
    static let hierarchy = Hierarchy(nodes: [], keyWindowID: 0)
    /// The key window's traits as the harness plays them.
    static let current = Traits(
        userInterfaceStyle: .light,
        contentSizeCategory: .large,
        layoutDirection: .leftToRight,
        horizontalSizeClass: .compact,
        verticalSizeClass: .regular
    )
    static let clientHello = clientHello(version: .current)

    static func clientHello(version: ProtocolVersion) -> Frame {
        Frame(
            requestID: 0,
            body: .hello(
                Hello(version: version, role: .client, client: ClientInfo(name: "test", version: "1"))
            )
        )
    }

    /// The subtree the harness reads for a root: one node with the root's ID, or none for the
    /// IDs from 90 on.
    static func subtree(of rootID: UInt64) -> Hierarchy? {
        guard rootID < 90 else { return nil }
        return Hierarchy(
            nodes: [
                LayerNode(
                    id: rootID,
                    parentID: 1,
                    className: "CALayer",
                    displayClassName: "CALayer",
                    bounds: WireRect(x: 0, y: 0, width: 10, height: 10),
                    position: WirePoint(x: 5, y: 5)
                )
            ],
            keyWindowID: 1
        )
    }

    /// The answer the harness gives a change: the layer's attributes, or `LayerNotFound` for the
    /// IDs from 90 on. The attribute has a section and limits, as of protocol 1.1.
    static func result(of change: SetAttribute) -> Result<SetAttributeResult, WireError> {
        guard change.layerID < 90 else {
            return .failure(WireError(code: .layerNotFound, message: "no layer with id \(change.layerID)"))
        }
        let attribute = Attribute(
            id: change.attributeID,
            title: "Changed",
            value: change.value,
            editable: true,
            valueKind: change.value?.kind ?? .string,
            section: .layout,
            limits: [NumberLimit(minimum: 0)]
        )
        return .success(
            SetAttributeResult(
                layerID: change.layerID,
                attributeGroups: [AttributeGroup(id: "layer", title: "Layer", attributes: [attribute])]
            )
        )
    }

    init(
        capture: ScriptedCapture = ScriptedCapture(),
        outstandingByteLimit: Int = .max,
        waitingRequestLimit: Int = 64
    ) {
        self.capture = capture
        let state = self.state
        session = Session(
            transport: transport,
            host: HostAccess(
                app: ScriptedApp(queue: queue, state: state, environment: environment),
                registry: LayerRegistry(),
                queue: queue,
                encodeQueue: queue
            ),
            pipeline: ScriptedPipeline(capture: capture, queue: queue),
            queue: queue,
            appState: .active,
            limits: Session.Limits(
                outstandingByteLimit: outstandingByteLimit,
                waitingRequestLimit: waitingRequestLimit
            )
        )
        session.delegate = state
        state.session = session
        queue.sync { session.start(handshakeTimeout: 60) }
    }

    /// Hands the session these frames as one piece of input.
    func receive(_ frames: Frame...) {
        receive(frames)
    }

    func receive(_ frames: [Frame]) {
        queue.async {
            for frame in frames {
                self.transport.deliver(FrameCodec.encode(frame))
            }
        }
    }

    /// Changes the app's state the way the server controller reports it.
    func setAppState(_ appState: AppState) {
        queue.async {
            self.session?.appStateDidChange(appState)
        }
    }

    /// Completes the oldest `count` sends that wait, on the session's queue.
    func completeSends(_ count: Int = .max) {
        queue.async { self.transport.completeSends(count) }
    }

    /// The server ends the session, as when it stops.
    func stop() {
        queue.async { self.session?.stop() }
    }

    /// The peer goes away.
    func closeFromThePeer() {
        queue.async { self.transport.closeFromThePeer() }
    }

    var endedCount: Int { queue.sync { state.endedCount } }

    /// The stream of the request in hand, read on the session's queue.
    var currentStream: LayerDetailsStream? { queue.sync { session?.currentStream } }

    /// Lets go of the session and returns a weak reference to it.
    func releaseSession() -> WeakBox<Session> {
        queue.sync {
            let box = WeakBox(session)
            session = nil
            return box
        }
    }

    /// The changes the session asked the host to make, in order.
    var changes: [SetAttribute] { queue.sync { state.changes } }

    /// The roots of the subtrees the session asked the host for, in order.
    var subtreeRoots: [UInt64] { queue.sync { state.subtreeRoots } }

    /// The versions the hierarchies and subtrees were read for, in order.
    var captureVersions: [ProtocolVersion] { queue.sync { state.captureVersions } }

    /// From now on the app leaves the active state while a subtree is being read.
    func leaveActiveStateWhileReadingSubtrees() {
        queue.sync { state.leavesActiveStateWhileReading = true }
    }

    /// Completes the handshake and returns once its two frames were sent.
    func handshake(version: ProtocolVersion = .current) async throws {
        receive(Self.clientHello(version: version))
        _ = try await frames(2)
    }

    /// Waits until `count` frames were sent and returns all of them.
    func frames(_ count: Int) async throws -> [Frame] {
        let transport = self.transport
        try await waitUntil("\(count) frames; so far: \(transport.sent)") { transport.sent.count >= count }
        return transport.sent
    }

    /// Lets everything that is under way come to rest: the scripted capture and compressor
    /// each take one turn of the queue, the host app one of the main queue.
    func settle() async {
        for _ in 0..<8 {
            await drain(queue)
            await drain(DispatchQueue.main)
        }
    }
}
