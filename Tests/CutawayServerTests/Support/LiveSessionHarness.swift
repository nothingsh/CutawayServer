import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// A session with the real host behind it — capture, registry, screenshots, compression,
/// changes to attributes — over a fake transport. No listener and no socket.
final class LiveSessionHarness: @unchecked Sendable {
    let queue = DispatchQueue(label: "dev.cutaway.tests.live-session")
    let transport = FakeTransport()
    /// The connection's registry. Main thread only.
    let registry = LayerRegistry()
    let encodeQueue = DispatchQueue(label: "dev.cutaway.tests.live-session.encode")
    /// Touched on `queue` only.
    let session: Session
    private let ended = EndedBox()
    /// The request ID of the next `exchange`'s `GetAppIcon`.
    private var nextSentinelID: UInt32 = 4_000_000_000
    /// The handshake's frames were taken from the transport.
    private var tookHandshake = false

    private final class EndedBox: SessionDelegate, @unchecked Sendable {
        // Touched on the session's queue only.
        var count = 0

        func sessionDidEnd(_ session: Session) {
            count += 1
        }
    }

    init(configuration: ServerConfiguration = ServerConfiguration()) {
        let host = HostAccess(
            app: configuration.hostApp,
            registry: registry,
            queue: queue,
            encodeQueue: encodeQueue
        )
        // The test host is active while tests run.
        session = Session(
            transport: transport,
            host: host,
            queue: queue,
            appState: .active,
            limits: configuration.sessionLimits
        )
        session.delegate = ended
        let session = self.session
        queue.sync { session.start(handshakeTimeout: 60) }
    }

    /// Hands the session these frames, encoded, as a client would send them.
    func receive(_ frames: [Frame]) {
        queue.async {
            for frame in frames {
                self.transport.deliver(FrameCodec.encode(frame))
            }
        }
    }

    func receive(_ frames: Frame...) {
        receive(frames)
    }

    /// Completes the handshake; returns once its two frames were sent.
    func handshake() async throws {
        receive(SessionHarness.clientHello)
        _ = try await frames(2)
    }

    /// Waits until `count` frames were sent and returns all of them.
    func frames(_ count: Int, timeout: TimeInterval = 10) async throws -> [Frame] {
        let transport = self.transport
        try await waitUntil("\(count) frames", timeout: timeout) { transport.sent.count >= count }
        return transport.sent
    }

    var endedCount: Int { queue.sync { ended.count } }

    /// Sends the frames and a `GetAppIcon` after them, waits for the icon, and returns the
    /// answers to the frames that are not cancels, checked by `ResponseCheck`. Answers come in
    /// the order of the requests (P-REQ-06), so once the icon is there, everything before it
    /// is too. The frames are taken from the transport, so that long tests keep none of them.
    func exchange(
        _ frames: [Frame],
        timeout: TimeInterval = 20,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> [ResponseCheck.Response] {
        nextSentinelID += 1
        let sentinel = nextSentinelID
        let all = frames + [Frame(requestID: sentinel, body: .getAppIcon)]
        receive(all)
        let transport = self.transport
        try await waitUntil("the answer to request \(sentinel)", timeout: timeout) {
            transport.lastSentRequestID == sentinel
        }
        let requests = all.filter { frame in
            if case .cancel? = frame.body { return false }
            return true
        }
        let responses = ResponseCheck.responses(
            to: requests,
            in: transport.takeSent(),
            handshakeFrames: tookHandshake ? 0 : 2,
            file: file,
            line: line
        )
        tookHandshake = true
        if case .appIcon? = responses.last?.frame?.body {
        } else {
            XCTFail("the last answer is not the icon: \(String(describing: responses.last))", file: file, line: line)
        }
        return Array(responses.dropLast())
    }

    /// Lets the queues come to rest: what was under way on them has run.
    func settle() async {
        for _ in 0..<8 {
            await drain(queue)
            await drain(encodeQueue)
            await drain(DispatchQueue.main)
        }
    }
}
