import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// A view that answers a change of appearance the way many apps do: it does not recolour
/// itself in the callback, but queues the work on the main queue, `hops` blocks deep. Red when
/// light, blue when dark. The work uses the appearance of its own callback, so that work still
/// queued from an earlier callback cannot show the new one.
private final class LateRecolouringView: UIView {
    private let hops: Int

    init(hops: Int) {
        self.hops = hops
        super.init(frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        backgroundColor = Self.color(for: .light)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    static func color(for style: UIUserInterfaceStyle) -> UIColor {
        style == .dark ? .blue : .red
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        queueRecolouring(hops, for: traitCollection.userInterfaceStyle)
    }

    private func queueRecolouring(_ remaining: Int, for style: UIUserInterfaceStyle) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if remaining > 1 {
                    self.queueRecolouring(remaining - 1, for: style)
                } else {
                    self.backgroundColor = Self.color(for: style)
                }
            }
        }
    }
}

/// `SetEnvironment` lets the app respond before it answers (protocol 1.2 dev.3; PROTOCOL.md,
/// P-ENV-02), on real windows of the test host, through `HostAccess` as a session uses it.
/// Every test removes its overrides before it ends.
final class EnvironmentResponseTests: CaptureTestCase {
    private let red = pixelBytes(red: 1, green: 0, blue: 0)
    private let blue = pixelBytes(red: 0, green: 0, blue: 1)

    override func setUp() async throws {
        try await super.setUp()
        // The live host refuses while the app is not active (P-APP-01), as a test host that has
        // just been launched may not be yet.
        let deadline = Date().addingTimeInterval(10)
        while UIApplication.shared.applicationState != .active {
            guard Date() < deadline else { return XCTFail("the test host did not become active") }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// What the test saw on the main thread while the server worked. Main thread only.
    @MainActor
    private final class Seen {
        var appliedTurn: Int?
        var settledTurn: Int?
        /// The pixel at the middle of the view, as `GetLayerDetails` would capture it, when
        /// `current` was read.
        var pixel: [UInt8]?
    }

    private final class Answer: @unchecked Sendable {
        // Written on the session queue before the expectation is fulfilled, read after.
        var result: Result<Environment, WireError>?
    }

    /// The live overrides, each step followed by `applied` or `settled`.
    @MainActor
    private final class ObservedEnvironment: EnvironmentControl {
        private let base = EnvironmentOverrides()
        private let applied: @MainActor @Sendable () -> Void
        private let settled: @MainActor @Sendable () -> Void

        nonisolated init(
            applied: @escaping @MainActor @Sendable () -> Void,
            settled: @escaping @MainActor @Sendable () -> Void
        ) {
            self.applied = applied
            self.settled = settled
        }

        func read() -> Environment {
            base.read()
        }

        func apply(_ traits: Traits) -> Result<Void, WireError> {
            let result = base.apply(traits)
            applied()
            return result
        }

        func settle() -> Environment {
            let environment = base.settle()
            settled()
            return environment
        }

        func removeAll() {
            base.removeAll()
        }
    }

    /// A live host whose connection's environment is an `ObservedEnvironment`.
    private func makeHost(
        applied: @escaping @MainActor @Sendable () -> Void = {},
        settled: @escaping @MainActor @Sendable () -> Void = {}
    ) -> HostAccess {
        var app = TestHostApp()
        app.environmentControl = { ObservedEnvironment(applied: applied, settled: settled) }
        return HostAccess(
            app: app,
            queue: DispatchQueue(label: "dev.cutaway.tests.environment-response"),
            encodeQueue: DispatchQueue(label: "dev.cutaway.tests.environment-response.encode")
        )
    }

    /// Sends `traits` as a session does and waits for the answer; then removes the overrides.
    private func setEnvironment(_ traits: Traits, on host: HostAccess) throws -> Result<Environment, WireError> {
        let answer = Answer()
        let answered = expectation(description: "SetEnvironment answered")
        host.setEnvironment(traits) { result in
            answer.result = result
            answered.fulfill()
        }
        wait(for: [answered], timeout: 5)
        host.connection.environment.removeAll()
        return try XCTUnwrap(answer.result)
    }

    private func image(of layer: CALayer) throws -> RawImage {
        let plan = try XCTUnwrap(ImageSizing.plan(bounds: layer.bounds, screenScale: 1, maxTextureDimension: 0))
        return try XCTUnwrap(LayerRenderer.render(layer, mode: .group, plan: plan))
    }

    /// A light window with a `LateRecolouringView`; dark is set, and when `current` is read
    /// the view is already blue.
    private func assertTheResponseHasRun(hops: Int, file: StaticString = #filePath, line: UInt = #line) throws {
        let window = try makeWindow()
        window.overrideUserInterfaceStyle = .light
        let view = LateRecolouringView(hops: hops)
        window.addSubview(view)
        window.layoutIfNeeded()
        assertPixel(try image(of: view.layer).pixel(atPoint: 20, 20), red, "before", file: file, line: line)

        let seen = Seen()
        let host = makeHost(settled: { seen.pixel = try? self.image(of: view.layer).pixel(atPoint: 20, 20) })
        let result = try setEnvironment(Traits(userInterfaceStyle: .dark), on: host)

        guard case .success(let environment) = result else {
            return XCTFail("SetEnvironment was refused: \(result)", file: file, line: line)
        }
        XCTAssertEqual(environment.current.userInterfaceStyle, .dark, file: file, line: line)
        assertPixel(
            try XCTUnwrap(seen.pixel, file: file, line: line),
            blue,
            "when current was read",
            file: file,
            line: line
        )
    }

    func test_S_ENV_05_workTheAppQueuesOnceHasRun() throws {
        try assertTheResponseHasRun(hops: 1)
    }

    func test_S_ENV_05_workTheAppQueuesTwiceHasRun() throws {
        try assertTheResponseHasRun(hops: 2)
    }

    /// At least two turns of the main run loop, one for each block the server queues, pass
    /// between applying the overrides and settling the windows.
    func test_S_ENV_05_atLeastTwoTurnsPassBeforeTheAnswer() throws {
        let turns = MainRunLoopTurns()
        defer { turns.stop() }
        let seen = Seen()
        let host = makeHost(
            applied: { seen.appliedTurn = turns.count },
            settled: { seen.settledTurn = turns.count }
        )
        _ = try setEnvironment(Traits(userInterfaceStyle: .dark), on: host)

        let applied = try XCTUnwrap(seen.appliedTurn)
        let settled = try XCTUnwrap(seen.settledTurn)
        XCTAssertGreaterThanOrEqual(EnvironmentOverrides.responseTurns, 2)
        // At least one turn for each block queued; other work of the run loop may add more.
        XCTAssertGreaterThanOrEqual(settled - applied, EnvironmentOverrides.responseTurns)
    }

    /// A refused request changes nothing, so there is nothing to wait for.
    func test_S_ENV_05_aRefusalIsAnsweredWithoutSettling() throws {
        let seen = Seen()
        let host = makeHost(settled: { seen.settledTurn = 0 })
        let result = try setEnvironment(Traits(unknownKinds: [.contentSizeCategory]), on: host)

        guard case .failure(let error) = result else { return XCTFail("expected a refusal, got \(result)") }
        XCTAssertEqual(error.code, .notSupported)
        XCTAssertNil(seen.settledTurn)
    }
}
