import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// The session holds back while the connection is behind (S-CONN-13) and
/// stops reading while too many requests wait (S-CONN-14). Over a fake transport whose
/// sends wait for the test: no listener and no socket.
final class SessionBackpressureTests: XCTestCase {
    private static let mebibyte = 1_048_576

    private func details(_ requestID: UInt32, _ layerIDs: [UInt64]) -> Frame {
        Frame(
            requestID: requestID,
            body: .getLayerDetails(
                GetLayerDetails(
                    requests: layerIDs.map {
                        LayerDetailRequest(layerID: $0, wantSolo: false, wantGroup: true, wantAttributes: false)
                    },
                    maxTextureDimension: 0
                )
            )
        )
    }

    private func end(
        _ requestID: UInt32,
        _ status: StreamStatus,
        _ chunkCount: UInt32,
        error: WireError? = nil
    ) -> Frame {
        Frame(
            requestID: requestID,
            body: .streamEnd(StreamEnd(status: status, chunkCount: chunkCount, error: error))
        )
    }

    /// The layers of the chunks among `frames`, in order.
    private func chunkLayers(_ frames: [Frame]) -> [UInt64] {
        frames.flatMap { frame -> [UInt64] in
            guard case .layerDetailsChunk(let chunk)? = frame.body else { return [] }
            return chunk.details.map(\.layerID)
        }
    }

    /// A harness whose sends wait from after the handshake on.
    private func backedUpHarness(
        capture: ScriptedCapture,
        limit: Int
    ) async throws -> SessionHarness {
        let harness = SessionHarness(capture: capture, outstandingByteLimit: limit)
        try await harness.handshake()
        harness.transport.holdsSends = true
        return harness
    }

    /// Lets the session run until nothing more happens without a completed send.
    private func settleWhileBackedUp(_ harness: SessionHarness) async {
        for _ in 0..<4 { await harness.settle() }
    }

    // MARK: - S-CONN-13

    func test_S_CONN_13_unsentBytesStayWithinTheLimitPlusOneFrame() async throws {
        // 200 images of 256 KiB that LZFSE cannot shrink: 50 MiB in all, the budget is 1 MiB.
        let capture = ScriptedCapture(side: { _ in 256 }, incompressible: true)
        let limit = Self.mebibyte
        let harness = try await backedUpHarness(capture: capture, limit: limit)
        let layers = (1...200).map(UInt64.init)

        harness.receive(details(1, layers))
        await settleWhileBackedUp(harness)
        let stalled = capture.captured.count
        XCTAssertGreaterThan(stalled, 0)
        XCTAssertLessThan(stalled, 10, "the stream did not stop at the budget")
        await settleWhileBackedUp(harness)
        XCTAssertEqual(capture.captured.count, stalled, "a layer was rendered while nothing was sent")

        // The connection sends a little at a time; the stream follows.
        var rounds = 0
        while !harness.transport.sent.contains(end(1, .completed, 200)) {
            rounds += 1
            XCTAssertLessThan(rounds, 1000, "the stream did not complete")
            guard rounds < 1000 else { break }
            harness.completeSends(2)
            await harness.settle()
        }
        harness.completeSends()
        await harness.settle()

        let sent = harness.transport.sent
        XCTAssertEqual(chunkLayers(sent), layers, "details were lost, repeated or reordered")
        let largest = sent.map { FrameCodec.encodeFramed($0).count }.max() ?? 0
        XCTAssertGreaterThan(largest, 256 * 1024)
        XCTAssertLessThanOrEqual(
            harness.transport.peakUnsentByteCount,
            limit + largest,
            "more than the limit and one frame was unsent at once"
        )
    }

    func test_S_CONN_13_nextRequestWaitsForRoom() async throws {
        // Three images of about 600 KiB with a budget of 1 MiB: two go out, the third waits
        // for the first to be sent, and once it is out the connection is behind again.
        let capture = ScriptedCapture(side: { _ in 390 }, incompressible: true)
        let harness = try await backedUpHarness(capture: capture, limit: Self.mebibyte)

        harness.receive(
            details(1, [1, 2, 3]),
            Frame(requestID: 2, body: .getAppIcon),
            Frame(requestID: 3, body: .getHierarchy)
        )
        await settleWhileBackedUp(harness)
        XCTAssertEqual(capture.captured, [1, 2])

        harness.completeSends(1)
        await settleWhileBackedUp(harness)
        var sent = harness.transport.sent
        XCTAssertEqual(sent.last, end(1, .completed, 3))
        XCTAssertGreaterThan(harness.transport.unsentByteCount, Self.mebibyte)
        XCTAssertFalse(
            sent.contains { $0.requestID == 2 || $0.requestID == 3 },
            "a request began while the connection was behind"
        )

        harness.completeSends(1)
        await settleWhileBackedUp(harness)
        sent = harness.transport.sent
        XCTAssertEqual(
            Array(sent.suffix(2)),
            [
                Frame(requestID: 2, body: .appIcon(AppIcon(image: nil))),
                Frame(requestID: 3, body: .hierarchy(SessionHarness.hierarchy))
            ]
        )
    }

    func test_S_CONN_13_cancelWorksWhileBackedUp() async throws {
        let capture = ScriptedCapture(side: { _ in 390 }, incompressible: true)
        let harness = try await backedUpHarness(capture: capture, limit: Self.mebibyte)

        harness.receive(details(1, Array(1...10)))
        await settleWhileBackedUp(harness)
        XCTAssertEqual(capture.captured, [1, 2])

        // P-REQ-04, P-REQ-06: handled now, though nothing can be sent.
        harness.receive(Frame(requestID: 2, body: .cancel(targetRequestID: 1)))
        await settleWhileBackedUp(harness)
        XCTAssertEqual(harness.transport.sent.last, end(1, .cancelled, 2))

        harness.completeSends()
        await settleWhileBackedUp(harness)
        XCTAssertEqual(capture.captured, [1, 2], "a layer was rendered after the cancel")
        XCTAssertEqual(harness.transport.sent.last, end(1, .cancelled, 2))
    }

    func test_S_CONN_13_appStateEventsAreNotHeldBack() async throws {
        let capture = ScriptedCapture(side: { _ in 390 }, incompressible: true)
        let harness = try await backedUpHarness(capture: capture, limit: Self.mebibyte)

        harness.receive(details(1, Array(1...10)))
        await settleWhileBackedUp(harness)
        let unsentFrames = harness.transport.unsentSendCount

        // The client is told at once, behind what waits already: its stream ends as failed.
        harness.setAppState(.background)
        await settleWhileBackedUp(harness)
        let sent = harness.transport.sent
        XCTAssertEqual(
            Array(sent.suffix(2)),
            [
                Frame(requestID: 0, body: .appStateChanged(.background)),
                end(
                    1,
                    .failed,
                    2,
                    error: WireError(
                        code: .appNotActive,
                        message: "the app left the active state during capture"
                    )
                )
            ]
        )
        XCTAssertEqual(harness.transport.unsentSendCount, unsentFrames + 2)
    }

    func test_S_CONN_13_closingReleasesEverything() async throws {
        let capture = ScriptedCapture(side: { _ in 390 }, incompressible: true)
        let harness = try await backedUpHarness(capture: capture, limit: Self.mebibyte)

        harness.receive(details(1, Array(1...10)))
        await settleWhileBackedUp(harness)
        let stream = WeakBox(harness.currentStream)
        XCTAssertNotNil(stream.object)

        harness.closeFromThePeer()
        await settleWhileBackedUp(harness)
        let session = harness.releaseSession()
        await settleWhileBackedUp(harness)

        XCTAssertEqual(harness.endedCount, 1)
        XCTAssertEqual(harness.transport.unsentByteCount, 0)
        XCTAssertNil(session.object, "the session outlived its connection")
        XCTAssertNil(stream.object, "the stream outlived its connection")
    }

    // MARK: - S-CONN-14

    func test_S_CONN_14_readingPausesAtTheLimit() async throws {
        let capture = ScriptedCapture()
        capture.hold(1)
        let harness = SessionHarness(capture: capture)
        try await harness.handshake()

        // The stream is in hand; 100 requests come behind it.
        harness.receive([details(1, [1])] + (2...101).map { Frame(requestID: UInt32($0), body: .getAppIcon) })
        await harness.settle()
        XCTAssertTrue(harness.transport.isReceivingPaused)
        XCTAssertEqual(harness.transport.pauseCount, 1)
        XCTAssertEqual(harness.transport.waitingInputCount, 100 - 64, "more than 64 requests were taken in")

        capture.release(1)
        let frames = try await harness.frames(2 + 2 + 100)
        await harness.settle()
        XCTAssertFalse(harness.transport.isReceivingPaused)
        XCTAssertGreaterThanOrEqual(harness.transport.resumeCount, 1)
        XCTAssertEqual(frames[3], end(1, .completed, 1))
        XCTAssertEqual(frames[4...].map(\.requestID), (2...101).map(UInt32.init))
    }

    func test_S_CONN_14_aThousandRequestsAreAllAnsweredInOrder() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        let requests = (1...1000).map { index in
            Frame(requestID: UInt32(index), body: index.isMultiple(of: 2) ? .getHierarchy : .getAppIcon)
        }
        harness.receive(requests)
        let frames = try await harness.frames(2 + 1000)

        XCTAssertEqual(frames[2...].map(\.requestID), (1...1000).map(UInt32.init))
        // The waiting ones, the one in hand, and the client's hello, which gets no answer with
        // its request ID.
        XCTAssertLessThanOrEqual(harness.transport.peakUnansweredCount, 64 + 1 + 1)
        XCTAssertGreaterThanOrEqual(harness.transport.pauseCount, 1)
        XCTAssertFalse(harness.transport.isReceivingPaused)
    }

    func test_S_CONN_14_handshakeFramesCount() async throws {
        let harness = SessionHarness()
        // Requests that come with the hello wait for the handshake, and count while they do.
        harness.receive(
            [SessionHarness.clientHello] + (1...100).map { Frame(requestID: UInt32($0), body: .getAppIcon) }
        )
        let frames = try await harness.frames(2 + 100)

        XCTAssertEqual(frames[2...].map(\.requestID), (1...100).map(UInt32.init))
        XCTAssertGreaterThanOrEqual(harness.transport.pauseCount, 1)
        XCTAssertLessThanOrEqual(harness.transport.peakUnansweredCount, 64 + 1 + 1)
    }
}
