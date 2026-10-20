#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation

/// The protocol state machine of one connection: handshake, requests, streams, events.
/// The only part that knows both the protocol and the host's data.
/// Confined to the server queue.
final class Session: @unchecked Sendable {
    /// What the session may hold back from the connection.
    struct Limits {
        /// No request begins, and no layer is rendered, while more bytes than this are
        /// outstanding (S-CONN-13).
        var outstandingByteLimit: Int
        /// Reading stops while this many requests wait (S-CONN-14).
        var waitingRequestLimit: Int
    }

    private enum State {
        case awaitingHello
        /// The client's hello arrived; the app's information is being read on the main thread.
        case handshaking
        case ready
        case ended
    }

    /// The stream of the request in hand.
    struct ActiveStream {
        var requestID: UInt32
        var stream: LayerDetailsStream
        /// How many chunks were sent; also the next chunk's sequence number.
        var chunkCount: UInt32 = 0
    }

    /// Read by the tests.
    let transport: SessionTransport
    private let host: HostAccess
    /// Captures and compresses the layers of a stream; the host itself unless a test scripts it.
    private let pipeline: any DetailPipeline
    private let queue: DispatchQueue
    private let limits: Limits
    private var state = State.awaitingHello
    /// The app's state as the server reported it last (P-EVT-02), whether or not the
    /// handshake is complete.
    private var appState: AppState
    /// P-HELLO-04: the lower of the two minor versions. Set once by the handshake, the same for
    /// the whole connection.
    private var version = ProtocolVersion.current
    private var handshakeTimeout: DispatchWorkItem?
    /// Requests wait here and are handled one at a time, in order (PROTOCOL.md, P-REQ-06).
    /// Frames that arrive while the handshake is being completed wait here too.
    private var pending = RequestQueue()
    /// The transport was asked to stop reading (S-CONN-14).
    private var isReceivingPaused = false
    private var isHandlingRequest = false
    private var isDraining = false
    /// Read by the tests.
    private(set) var activeStream: ActiveStream?

    /// Told once when the session is over, whoever ended it. Held weakly.
    weak var delegate: SessionDelegate?

    /// - Parameters:
    ///   - pipeline: What a stream captures and compresses with; `nil` uses the host.
    ///   - appState: The app's state now; the session is told of every change after.
    init(
        transport: SessionTransport,
        host: HostAccess,
        pipeline: (any DetailPipeline)? = nil,
        queue: DispatchQueue,
        appState: AppState,
        limits: Limits
    ) {
        self.transport = transport
        self.host = host
        self.pipeline = pipeline ?? host
        self.queue = queue
        self.appState = appState
        self.limits = limits
    }

    func start(handshakeTimeout seconds: TimeInterval) {
        dispatchPrecondition(condition: .onQueue(queue))
        transport.delegate = self
        transport.start()

        // P-HELLO-06: no hello in time, no session. Nothing is sent.
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state == .awaitingHello else { return }
            self.transport.close()
            self.end()
        }
        handshakeTimeout = timeout
        queue.asyncAfter(deadline: .now() + seconds, execute: timeout)
    }

    /// Ends the session from the server's side.
    func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        transport.close()
        end()
    }

    /// P-EVT-02: every change is reported to a client that completed the handshake.
    func appStateDidChange(_ appState: AppState) {
        dispatchPrecondition(condition: .onQueue(queue))
        self.appState = appState
        guard state == .ready else { return }
        transport.send(Frame(requestID: 0, body: .appStateChanged(appState)))
        // P-APP-01: no screenshots unless the app is active. The event went out first, so the
        // client gets no chunk after it has been told.
        if appState != .active {
            endStream(.failed, error: .leftActiveState)
        }
    }

    // MARK: - Incoming frames

    private func receive(_ payload: Data) {
        let frame: Frame
        do {
            frame = try FrameCodec.decode(payload)
        } catch {
            rejectMalformedFrame()
            return
        }
        switch state {
        case .awaitingHello:
            beginHandshake(with: frame)
        case .handshaking, .ready:
            accept(frame)
        case .ended:
            break
        }
    }

    /// P-FRAME-03: an error may be sent before the connection is closed. It is, so that the
    /// client's developer can see why.
    private func rejectMalformedFrame() {
        guard state != .ended else { return }
        transport.finish(with: Frame(requestID: 0, body: .error(.malformedFrame)))
        end()
    }

    // MARK: - Handshake

    private func beginHandshake(with frame: Frame) {
        // P-HELLO-05. A hello that is not a client's, or that has no version, is not a
        // handshake either.
        guard case .hello(let hello)? = frame.body,
              hello.role == .client,
              let version = hello.version else {
            transport.finish(with: Frame(requestID: frame.requestID, body: .error(.expectedClientHello)))
            end()
            return
        }
        handshakeTimeout?.cancel()
        state = .handshaking
        host.perform({ app, _ in app.appInfo() }, then: { [weak self] app in
            self?.completeHandshake(clientVersion: version, app: app)
        })
    }

    private func completeHandshake(clientVersion: ProtocolVersion, app: AppInfo) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .handshaking else { return }
        let reply = Frame(
            requestID: 0,
            body: .hello(Hello(version: .current, role: .server, app: app))
        )
        guard clientVersion.major == ProtocolVersion.current.major else {
            // P-HELLO-03: our hello, then nothing else.
            transport.finish(with: reply)
            end()
            return
        }
        version = ProtocolVersion.current.negotiated(with: clientVersion)
        transport.send(reply)
        transport.send(Frame(requestID: 0, body: .appStateChanged(appState)))
        state = .ready
        // What arrived in the meantime waits in the queue and goes the way of every later frame.
        handlePending()
        updateReceiving()
    }

    // MARK: - Requests

    /// Where every frame after the client's hello goes. Nothing is handled before the
    /// handshake is complete; a cancel marks its waiting stream either way.
    private func accept(_ frame: Frame) {
        // P-REQ-06: a cancel does not wait behind the request in hand.
        if case .cancel(let targetRequestID)? = frame.body {
            cancel(targetRequestID)
            return
        }
        pending.append(frame)
        updateReceiving()
        handlePending()
    }

    private func handlePending() {
        // A request that is answered at once comes back here through `endRequest()`; the loop
        // below then takes the next one, without growing the stack.
        guard !isDraining else { return }
        isDraining = true
        defer { isDraining = false }
        // S-CONN-13: no request begins while the connection is behind. Its answer would only
        // add to what waits to be sent.
        while state == .ready, !isHandlingRequest, !pending.isEmpty, hasRoomToSend,
              let request = pending.next() {
            updateReceiving()
            handle(request)
        }
    }

    // MARK: - Room

    /// S-CONN-13: what the connection has not sent yet is within the limit.
    private var hasRoomToSend: Bool {
        transport.unsentByteCount <= limits.outstandingByteLimit
    }

    /// The connection sent some: the stream and the waiting requests may go on.
    private func sendDidComplete() {
        guard state == .ready else { return }
        activeStream?.stream.resume()
        handlePending()
    }

    /// S-CONN-14: reading stops while too many requests wait and goes on once fewer do. A
    /// `Cancel` sent meanwhile is read late.
    private func updateReceiving() {
        guard state != .ended else { return }
        let shouldPause = pending.count >= limits.waitingRequestLimit
        guard shouldPause != isReceivingPaused else { return }
        isReceivingPaused = shouldPause
        if shouldPause {
            transport.pauseReceiving()
        } else {
            transport.resumeReceiving()
        }
    }

    /// Marks the request in hand: nothing else is handled until `endRequest()`.
    private func beginRequest() {
        isHandlingRequest = true
    }

    private func endRequest() {
        isHandlingRequest = false
        handlePending()
    }

    private func handle(_ request: RequestQueue.Request) {
        let requestID = request.frame.requestID
        switch request.frame.body {
        case .getAppIcon:
            answer(requestID, requiresActiveApp: false, perform: host.loadAppIcon(then:)) { _, image in
                .appIcon(AppIcon(image: image))
            }
        case .getHierarchy:
            // P-APP-01: no hierarchy unless the app is active.
            answer(
                requestID,
                requiresActiveApp: true,
                onMain: { [version] app, registry in app.captureHierarchy(registry: registry, version: version) },
                reply: { session, hierarchy in
                    // The app may have left the active state while the layers were being read. The
                    // client has been told by now, and must not get a hierarchy after that event.
                    session.appState == .active
                        ? .hierarchy(hierarchy) : .error(.appNotActive)
                }
            )
        case .getSubtree(let rootID):
            // P-APP-01: no subtree unless the app is active.
            answer(
                requestID,
                requiresActiveApp: true,
                onMain: { [version] app, registry in
                    app.captureSubtree(of: rootID, registry: registry, version: version)
                },
                reply: { session, hierarchy in
                    // As for the whole hierarchy: nothing read after the client was told the app
                    // left the active state.
                    if session.appState != .active {
                        return .error(.appNotActive)
                    } else if let hierarchy {
                        return .hierarchy(hierarchy)
                    } else {
                        return .error(.layerNotFound(rootID))
                    }
                }
            )
        case .setAttribute(let change):
            // P-APP-01: nothing is changed unless the app is active.
            answer(
                requestID,
                requiresActiveApp: true,
                onMain: { app, registry in app.setAttribute(change, registry: registry) },
                reply: { session, result in
                    // Unlike a hierarchy, the answer is sent whatever the state is now: the change
                    // may have been made, and the main thread checked the state before making it.
                    switch result {
                    // P-ATTR-08: only the sections the negotiated version has.
                    case .success(let answer): return .setAttributeResult(answer.adapted(to: session.version))
                    case .failure(let error): return .error(error)
                    }
                }
            )
        case .getEnvironment:
            // P-APP-01: answered whatever the app's state.
            answer(
                requestID,
                requiresActiveApp: false,
                perform: { [host] in host.performOnEnvironment(
                    { app, overrides in app.environment(overrides: overrides) },
                    then: $0
                ) },
                reply: { _, environment in .environment(environment) }
            )
        case .setEnvironment(let overrides):
            // P-APP-01, then P-ENV-04 on the main thread.
            answer(
                requestID,
                requiresActiveApp: true,
                perform: { [host] in
                    host.performOnEnvironment(
                        { app, environment in app.setEnvironment(overrides ?? .none, overrides: environment) },
                        then: $0
                    )
                },
                reply: { _, result in
                    // As for `SetAttribute`: the overrides may have been applied, so the answer
                    // goes out whatever the state is now.
                    switch result {
                    case .success(let environment): return .environment(environment)
                    case .failure(let error): return .error(error)
                    }
                }
            )
        case .getLayerDetails(let details):
            beginStream(details, requestID: requestID, isCancelled: request.isCancelled)
        case .cancel:
            // Never queued: `accept(_:)` handles it on arrival.
            break
        case nil, .hello, .appIcon, .hierarchy, .layerDetailsChunk, .streamEnd, .error,
             .appStateChanged, .setAttributeResult, .environment:
            // P-REQ-08: answer and keep the connection.
            transport.send(Frame(requestID: requestID, body: .error(.unexpectedMessage)))
        }
    }

    /// A request with one answer. When it needs the app active and the app is not, it is
    /// refused at once (P-APP-01). Otherwise nothing else is handled until `perform` completes
    /// and the answer that `reply` makes on the server queue is sent.
    private func answer<Value>(
        _ requestID: UInt32,
        requiresActiveApp: Bool,
        perform: (@escaping @Sendable (Value) -> Void) -> Void,
        reply: @escaping @Sendable (Session, Value) -> Message
    ) {
        if requiresActiveApp, appState != .active {
            transport.send(Frame(requestID: requestID, body: .error(.appNotActive)))
            return
        }
        beginRequest()
        perform { [weak self] value in
            guard let self, self.state == .ready else { return }
            self.transport.send(Frame(requestID: requestID, body: reply(self, value)))
            self.endRequest()
        }
    }

    /// A request answered by what the host app says on the main thread (`HostAccess.perform`).
    private func answer<Value: Sendable>(
        _ requestID: UInt32,
        requiresActiveApp: Bool,
        onMain work: @escaping @MainActor @Sendable (any HostApp, LayerRegistry) -> Value,
        reply: @escaping @Sendable (Session, Value) -> Message
    ) {
        answer(requestID, requiresActiveApp: requiresActiveApp, perform: { host.perform(work, then: $0) }, reply: reply)
    }

    // MARK: - Streams

    private func beginStream(_ details: GetLayerDetails, requestID: UInt32, isCancelled: Bool) {
        // P-REQ-04: cancelled before it began.
        guard !isCancelled else {
            transport.send(
                Frame(requestID: requestID, body: .streamEnd(StreamEnd(status: .cancelled, chunkCount: 0)))
            )
            return
        }
        // P-APP-01: no screenshots unless the app is active.
        guard appState == .active else {
            transport.send(
                Frame(
                    requestID: requestID,
                    body: .streamEnd(StreamEnd(status: .failed, chunkCount: 0, error: .appNotActive))
                )
            )
            return
        }
        beginRequest()
        let stream = LayerDetailsStream(
            request: details,
            pipeline: pipeline,
            outstandingByteLimit: limits.outstandingByteLimit,
            delegate: self
        )
        activeStream = ActiveStream(requestID: requestID, stream: stream)
        stream.start()
    }

    /// One detail per chunk: the client sees each layer as soon as it is ready, and no chunk
    /// holds more than P-DET-06 allows unless a single detail does. Only what the negotiated
    /// version names is sent (P-HELLO-04, P-LAYOUT-08, P-DET-10).
    private func sendChunk(with detail: LayerDetail, for item: LayerDetailRequest) {
        guard state == .ready, let active = activeStream else { return }
        transport.send(
            Frame(
                requestID: active.requestID,
                body: .layerDetailsChunk(
                    LayerDetailsChunk(sequence: active.chunkCount, details: [detail.adapted(to: version, for: item)])
                )
            )
        )
        activeStream?.chunkCount += 1
    }

    /// P-REQ-03: ends the stream in hand, if there is one, with its `StreamEnd`.
    private func endStream(_ status: StreamStatus, error: WireError? = nil) {
        guard state == .ready, let active = activeStream else { return }
        activeStream = nil
        active.stream.stop()
        transport.send(
            Frame(
                requestID: active.requestID,
                body: .streamEnd(StreamEnd(status: status, chunkCount: active.chunkCount, error: error))
            )
        )
        endRequest()
    }

    /// P-REQ-04: a cancel ends the stream it names: the one in hand now, a waiting one when
    /// its turn comes. Anything else it names is ignored.
    private func cancel(_ targetRequestID: UInt32) {
        if activeStream?.requestID == targetRequestID {
            endStream(.cancelled)
            return
        }
        pending.cancelWaitingStream(targetRequestID)
    }

    private func end() {
        guard state != .ended else { return }
        state = .ended
        handshakeTimeout?.cancel()
        handshakeTimeout = nil
        pending.removeAll()
        activeStream?.stream.stop()
        activeStream = nil
        // P-ENV-03: whoever ended the connection, and however.
        host.removeOverrides()
        let delegate = self.delegate
        self.delegate = nil
        delegate?.sessionDidEnd(self)
    }
}

/// Told when a session is over, on the server queue.
protocol SessionDelegate: AnyObject {
    /// The session is over, whoever ended it. Once.
    func sessionDidEnd(_ session: Session)
}

extension Session: SessionTransportDelegate {
    func transportDidReceive(_ payload: Data) {
        receive(payload)
    }

    func transportCannotSplitFrames() {
        rejectMalformedFrame()
    }

    func transportDidClose() {
        end()
    }

    func transportDidSend() {
        sendDidComplete()
    }
}

extension Session: LayerDetailsStreamDelegate {
    var unsentByteCount: Int { transport.unsentByteCount }

    func streamDidProduce(_ detail: LayerDetail, for item: LayerDetailRequest) {
        sendChunk(with: detail, for: item)
    }

    func streamDidComplete() {
        endStream(.completed)
    }
}
#endif
