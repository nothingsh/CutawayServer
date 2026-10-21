#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation

/// How a session reaches the host app: UIKit on the main thread, compression on
/// `encodeQueue`, every answer back on `queue`, a moment later. Tests replace the app
/// (`TestHostApp`) and, for a stream, the pipeline (`DetailPipeline`).
struct HostAccess: Sendable {
    let app: any HostApp
    /// What the connection keeps: its registry (P-HIER-03) and its overrides of the app's
    /// environment (P-ENV-01). Main thread only.
    let connection: ConnectionContext
    let queue: DispatchQueue
    let encodeQueue: DispatchQueue

    /// The host of a new connection, with a new `ConnectionContext`.
    init(app: any HostApp, queue: DispatchQueue, encodeQueue: DispatchQueue) {
        self.init(app: app, connection: ConnectionContext(for: app), queue: queue, encodeQueue: encodeQueue)
    }

    init(app: any HostApp, connection: ConnectionContext, queue: DispatchQueue, encodeQueue: DispatchQueue) {
        self.app = app
        self.connection = connection
        self.queue = queue
        self.encodeQueue = encodeQueue
    }

    /// Works out a value from the app on the main thread and hands it to `answer` on `queue`.
    func perform<Value: Sendable>(
        _ work: @escaping @MainActor @Sendable (any HostApp, ConnectionContext) -> Value,
        then answer: @escaping @Sendable (Value) -> Void
    ) {
        onMain(answeringOn: queue, to: answer) { [app, connection] in work(app, connection) }
    }

    /// The same for one request that reads the app's layers: `work` gets the request's
    /// `RequestContext`, made on the main thread when it begins, for a client at `version`.
    ///
    /// - Parameter memo: What the request keeps until it ends: a details stream gives the same
    ///   one for each of its layers and discards it on the main thread. Without one, a new memo
    ///   is made and released on the main thread, so what the host app gave never ends on the
    ///   server queue.
    func perform<Value: Sendable>(
        version: ProtocolVersion,
        memo: RequestMemo? = nil,
        _ work: @escaping @MainActor @Sendable (any HostApp, RequestContext) -> Value,
        then answer: @escaping @Sendable (Value) -> Void
    ) {
        perform(
            { app, connection in
                work(app, app.makeRequestContext(for: connection, version: version, memo: memo ?? RequestMemo()))
            },
            then: answer
        )
    }

    /// The same for one request that changes the app: refused, and nothing changed, unless the
    /// app is active (P-APP-01).
    func performChange<Value: Sendable>(
        version: ProtocolVersion,
        _ change: @escaping @MainActor @Sendable (any HostApp, RequestContext) -> Result<Value, WireError>,
        then answer: @escaping @Sendable (Result<Value, WireError>) -> Void
    ) {
        perform(
            { app, connection in
                Self.whileActive(app) {
                    change(app, app.makeRequestContext(for: connection, version: version, memo: RequestMemo()))
                }
            },
            then: answer
        )
    }

    /// P-ENV-02: replaces the connection's overrides on the main thread. Unless refused, it then
    /// lets the main run loop go round `EnvironmentOverrides.responseTurns` times, so that what
    /// the app queued there in response has run, and settles the windows before the answer. The
    /// session starts no other request meanwhile (P-REQ-06), and nothing runs the run loop here.
    func setEnvironment(
        _ traits: Traits,
        then answer: @escaping @Sendable (Result<Environment, WireError>) -> Void
    ) {
        let queue = self.queue
        onMain { [app, connection] in
            // P-APP-01 before P-ENV-04.
            if case .failure(let refusal) = Self.whileActive(app, { connection.environment.apply(traits) }) {
                queue.async { answer(.failure(refusal)) }
                return
            }
            // Queued from this block of the main queue, so that the turns are counted from here.
            onMain(afterTurns: EnvironmentOverrides.responseTurns) {
                let settled = connection.environment.settle()
                queue.async { answer(.success(settled)) }
            }
        }
    }

    /// P-ENV-03: removes the connection's overrides on the main thread. Work the connection
    /// queued there before runs first, and a later connection's after.
    func removeOverrides() {
        onMain { [connection] in connection.environment.removeAll() }
    }

    /// P-APP-01: the session refuses a change while the app is not active, but the app may have
    /// left the active state after the session last heard of it; so the state is checked again on
    /// the main thread, right before the change.
    @MainActor
    private static func whileActive<Value>(
        _ app: any HostApp,
        _ change: () -> Result<Value, WireError>
    ) -> Result<Value, WireError> {
        guard app.currentAppState() == .active else { return .failure(.appNotActive) }
        return change()
    }

    /// Finds the icon on the main thread and compresses it on `encodeQueue`, like a detail.
    func loadAppIcon(then answer: @escaping @Sendable (WireImage?) -> Void) {
        let queue = self.queue
        let encodeQueue = self.encodeQueue
        perform(
            { app, _ in app.iconImage().flatMap { icon in icon.cgImage.map { ($0, Float(icon.scale)) } } },
            then: { found in
                guard let found else { return answer(nil) }
                // Drawing and compressing stay off the main thread.
                encodeQueue.async {
                    let image = ImageEncoder.encode(found.0, scale: found.1)
                    queue.async { answer(image) }
                }
            }
        )
    }
}

extension HostAccess: DetailPipeline {
    func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        version: ProtocolVersion,
        memo: RequestMemo,
        stopFlag: StopFlag,
        then answer: @escaping @Sendable (CapturedDetail?) -> Void
    ) {
        perform(
            version: version,
            memo: memo,
            { app, context in
                app.captureDetail(request, maxTextureDimension: maxTextureDimension, in: context, stopFlag: stopFlag)
            },
            then: answer
        )
    }

    func encodeDetail(
        _ detail: CapturedDetail,
        stopFlag: StopFlag,
        then answer: @escaping @Sendable (LayerDetail) -> Void
    ) {
        let queue = self.queue
        // Taken out of the block when it runs, so that the pixels are held by the compression
        // alone and each image's go as soon as it is compressed.
        let handed = HandedOver(detail)
        encodeQueue.async {
            // A stopped stream drops its details: compressing them would only cost time and
            // memory.
            guard !stopFlag.isSet, let detail = handed.take() else { return }
            let encoded = (consume detail).compressed()
            queue.async { answer(encoded) }
        }
    }
}

/// A value handed to another queue, which takes it out once, so that the block that carried
/// it no longer holds it.
private final class HandedOver<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    init(_ value: Value) {
        self.value = value
    }

    func take() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        let taken = value
        value = nil
        return taken
    }
}
#endif
