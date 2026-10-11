import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// `GetLayerDetails` and `Cancel` in the session, over a fake transport. No
/// listener and no socket: what arrives and what is sent are frames in memory.
final class SessionStreamTests: XCTestCase {
    private static let hello = Frame(
        requestID: 0,
        body: .hello(Hello(version: .current, role: .server, app: SessionHarness.app))
    )
    private static let active = Frame(requestID: 0, body: .appStateChanged(.active))
    private static let noIcon = Message.appIcon(AppIcon(image: nil))

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

    /// The chunk of a frame; fails the test when it is something else.
    private func chunk(_ frame: Frame, file: StaticString = #filePath, line: UInt = #line) -> LayerDetailsChunk {
        guard case .layerDetailsChunk(let chunk)? = frame.body else {
            XCTFail("expected a LayerDetailsChunk, got \(frame)", file: file, line: line)
            return LayerDetailsChunk(sequence: .max, details: [])
        }
        return chunk
    }

    /// Asserts that `frames` are the chunks of one stream, one layer each, numbered from 0.
    private func assertChunks(
        _ frames: ArraySlice<Frame>,
        of requestID: UInt32,
        layers: [UInt64],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(frames.map(\.requestID), layers.map { _ in requestID }, file: file, line: line)
        let chunks = frames.map { chunk($0, file: file, line: line) }
        XCTAssertEqual(chunks.map(\.sequence), Array(0..<UInt32(layers.count)), file: file, line: line)
        XCTAssertEqual(chunks.map { $0.details.map(\.layerID) }, layers.map { [$0] }, file: file, line: line)
    }

    // MARK: - S-CONN-15

    func test_S_CONN_15_aNilCaptureIsReportedAsCaptureFailed() async throws {
        // Only a capture that breaks its contract gives nil without being stopped. The stream
        // must not wait for it forever: the layer failed, the others go on (P-DET-01, P-DET-03).
        let harness = SessionHarness(capture: ScriptedCapture(givesNil: [2]))
        try await harness.handshake()

        harness.receive(details(7, [1, 2, 3]), Frame(requestID: 8, body: .getAppIcon))
        let frames = try await harness.frames(7)
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 7)

        assertChunks(frames[2..<5], of: 7, layers: [1, 2, 3])
        XCTAssertEqual(
            chunk(frames[3]).details,
            [LayerDetail(layerID: 2, status: .captureFailed)]
        )
        XCTAssertEqual(chunk(frames[4]).details.first?.status, .ok)
        XCTAssertEqual(frames[5], end(7, .completed, 3))
        XCTAssertEqual(frames[6], Frame(requestID: 8, body: Self.noIcon))
    }

    // MARK: - S-SHOT-06

    func test_S_SHOT_06_streamsOneDetailPerChunk() async throws {
        // Layer 2's image has 2100 x 2100 pixels: 17.6 MB, more than a chunk may hold unless
        // the detail is alone in it (P-DET-06).
        let harness = SessionHarness(capture: ScriptedCapture(side: { $0 == 2 ? 2100 : 2 }))
        try await harness.handshake()

        harness.receive(details(7, [1, 2, 3]))
        let frames = try await harness.frames(6)
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 6)

        XCTAssertEqual(Array(frames[0..<2]), [Self.hello, Self.active])
        assertChunks(frames[2..<5], of: 7, layers: [1, 2, 3])
        XCTAssertEqual(frames[5], end(7, .completed, 3))

        let images = frames[2..<5].map { chunk($0).details[0] }
        XCTAssertEqual(images.map(\.status), [.ok, .ok, .ok])
        XCTAssertEqual(images.map { $0.group?.pixelWidth }, [2, 2100, 2])
        let large = try XCTUnwrap(images[1].group)
        XCTAssertGreaterThan(Int(large.bytesPerRow) * Int(large.pixelHeight), 16 * 1024 * 1024)
        XCTAssertEqual(harness.capture.captured, [1, 2, 3])
        // S-SHOT-09: frames are encoded and sent on the server queue.
        XCTAssertFalse(harness.transport.sentOnMainThread)
    }

    func test_S_SHOT_06_anEmptyRequestCompletes() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        // P-REQ-03: zero chunks, then the end.
        harness.receive(details(1, []))
        var frames = try await harness.frames(3)
        XCTAssertEqual(frames[2], end(1, .completed, 0))

        // Such a request is answered on the spot. Twenty thousand of them pile up behind a
        // request that takes a moment; answering them must not nest twenty thousand calls deep.
        let count = 20_000
        harness.receive(
            [Frame(requestID: 2, body: .getAppIcon)] + (1...count).map { details(UInt32(2 + $0), []) }
                + [Frame(requestID: UInt32(count + 3), body: .getAppIcon)]
        )
        frames = try await harness.frames(count + 5)
        XCTAssertEqual(frames[3], Frame(requestID: 2, body: Self.noIcon))
        XCTAssertEqual(
            Array(frames[4..<count + 4]),
            (1...count).map { end(UInt32(2 + $0), .completed, 0) }
        )
        XCTAssertEqual(frames[count + 4], Frame(requestID: UInt32(count + 3), body: Self.noIcon))
        XCTAssertEqual(harness.capture.captured, [])
    }

    func test_S_SHOT_06_requestsAreStillAnsweredInOrder() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        // One piece of input: a stream between plain requests, and a message that only a
        // server sends. Each is answered in turn, and the stream's frames stay together.
        harness.receive(
            Frame(requestID: 1, body: .getAppIcon),
            details(2, [10, 11]),
            Frame(requestID: 3, body: .getHierarchy),
            Frame(requestID: 4, body: .appStateChanged(.active)),
            details(5, [12]),
            Frame(requestID: 6, body: .getAppIcon)
        )
        let frames = try await harness.frames(11)
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 11)

        XCTAssertEqual(frames[2], Frame(requestID: 1, body: Self.noIcon))
        assertChunks(frames[3..<5], of: 2, layers: [10, 11])
        XCTAssertEqual(frames[5], end(2, .completed, 2))
        XCTAssertEqual(frames[6], Frame(requestID: 3, body: .hierarchy(SessionHarness.hierarchy)))
        XCTAssertEqual(
            frames[7],
            Frame(
                requestID: 4,
                body: .error(
                    WireError(code: .unexpectedMessage, message: "this message is not expected here")
                )
            )
        )
        assertChunks(frames[8..<9], of: 5, layers: [12])
        XCTAssertEqual(frames[9], end(5, .completed, 1))
        XCTAssertEqual(frames[10], Frame(requestID: 6, body: Self.noIcon))
    }

    // MARK: - S-SHOT-07

    func test_S_SHOT_07_cancelEndsTheRunningStream() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        // The `layer-details-cancelled` scenario: three layers, the cancel after the first chunk.
        let request = try Fixtures.frame("layer-details-cancelled/01-c2s-get-layer-details.bin")
        guard case .getLayerDetails(let wanted)? = request.body else {
            return XCTFail("the fixture is not a GetLayerDetails")
        }
        XCTAssertEqual(request.requestID, 5)
        XCTAssertEqual(wanted.requests.map(\.layerID), [2, 3, 4])
        harness.capture.hold(3)

        harness.receive(request)
        var frames = try await harness.frames(3)
        assertChunks(frames[2..<3], of: 5, layers: [2])
        let capture = harness.capture
        try await waitUntil("the capture of layer 3 to be asked for") { capture.isWaiting(3) }

        harness.receive(try Fixtures.frame("layer-details-cancelled/03-c2s-cancel.bin"))
        frames = try await harness.frames(4)
        // The fixture's frame, byte for value: Cancelled, one chunk, the stream's request_id.
        XCTAssertEqual(frames[3], try Fixtures.frame("layer-details-cancelled/04-s2c-stream-end.bin"))
        XCTAssertEqual(frames[3], end(5, .cancelled, 1))

        // The main thread gets to layer 3 only now: it finds the stream stopped and renders
        // nothing. Layer 4 is never asked for.
        harness.capture.release(3)
        await harness.settle()
        XCTAssertEqual(harness.capture.captured, [2])
        XCTAssertEqual(harness.transport.sent.count, 4, "a frame of the cancelled stream was sent after its end")

        // The connection goes on: a request and a new stream are answered.
        harness.receive(Frame(requestID: 7, body: .getAppIcon), details(8, [4]))
        frames = try await harness.frames(7)
        XCTAssertEqual(frames[4], Frame(requestID: 7, body: Self.noIcon))
        assertChunks(frames[5..<6], of: 8, layers: [4])
        XCTAssertEqual(frames[6], end(8, .completed, 1))
    }

    func test_S_SHOT_07_cancelDropsWhatWasCapturedButNotSent() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        // The stream and its cancel in one piece of input: layer 1 is being captured when the
        // cancel is handled. Its detail arrives afterwards and is not sent.
        harness.receive(details(1, [1, 2]), Frame(requestID: 2, body: .cancel(targetRequestID: 1)))
        let frames = try await harness.frames(3)
        await harness.settle()
        XCTAssertEqual(Array(harness.transport.sent[2...]), [end(1, .cancelled, 0)])
        XCTAssertEqual(frames.count, 3)
        XCTAssertEqual(harness.capture.captured, [])
    }

    func test_S_SHOT_07_cancelOfAQueuedStreamEndsItInItsTurn() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        harness.capture.hold(2)

        // Stream 1 is in hand and stream 2 waits when the cancel names stream 2. A second
        // cancel of the same stream changes nothing.
        harness.receive(
            details(1, [1, 2]),
            details(2, [10, 11]),
            Frame(requestID: 3, body: .getAppIcon),
            Frame(requestID: 4, body: .cancel(targetRequestID: 2)),
            Frame(requestID: 5, body: .cancel(targetRequestID: 2))
        )
        var frames = try await harness.frames(3)
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 3, "the waiting stream must end in its turn, not before")

        harness.capture.release(2)
        frames = try await harness.frames(7)
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 7)
        // Responses in the order of the requests (P-REQ-06).
        assertChunks(frames[2..<4], of: 1, layers: [1, 2])
        XCTAssertEqual(frames[4], end(1, .completed, 2))
        XCTAssertEqual(frames[5], end(2, .cancelled, 0))
        XCTAssertEqual(frames[6], Frame(requestID: 3, body: Self.noIcon))
        XCTAssertEqual(harness.capture.captured, [1, 2], "a layer of the cancelled stream was captured")
    }

    func test_S_SHOT_07_cancelThatArrivesWithItsRequest() async throws {
        let harness = SessionHarness()

        // Before the handshake is complete: the hello, a stream and its cancel at once.
        harness.receive(
            SessionHarness.clientHello,
            details(1, [1, 2, 3]),
            Frame(requestID: 2, body: .cancel(targetRequestID: 1)),
            details(3, [4])
        )
        let frames = try await harness.frames(5)
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 5)

        XCTAssertEqual(Array(frames[0..<2]), [Self.hello, Self.active])
        XCTAssertEqual(frames[2], end(1, .cancelled, 0))
        assertChunks(frames[3..<4], of: 3, layers: [4])
        XCTAssertEqual(frames[4], end(3, .completed, 1))
        XCTAssertEqual(harness.capture.captured, [4])
    }

    func test_S_SHOT_07_otherCancelsAreIgnored() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        harness.receive(Frame(requestID: 1, body: .getAppIcon))
        _ = try await harness.frames(3)
        harness.capture.hold(2)

        harness.receive(details(5, [1, 2]), Frame(requestID: 6, body: .getAppIcon))
        _ = try await harness.frames(4)
        // P-REQ-04: none of these names a stream that is not over.
        harness.receive(
            Frame(requestID: 7, body: .cancel(targetRequestID: 1)),  // a plain request, answered
            Frame(requestID: 8, body: .cancel(targetRequestID: 6)),  // a plain request, waiting
            Frame(requestID: 9, body: .cancel(targetRequestID: 99)),  // no such request
            Frame(requestID: 10, body: .cancel(targetRequestID: 0)),
            Frame(requestID: 11, body: .cancel(targetRequestID: 11))
        )  // itself
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 4, "a cancel must not be answered")

        harness.capture.release(2)
        let frames = try await harness.frames(7)
        assertChunks(frames[3..<5], of: 5, layers: [1, 2])
        XCTAssertEqual(frames[5], end(5, .completed, 2))
        XCTAssertEqual(frames[6], Frame(requestID: 6, body: Self.noIcon))

        // The stream is over: a cancel that names it now is ignored too.
        harness.receive(Frame(requestID: 12, body: .cancel(targetRequestID: 5)))
        harness.receive(Frame(requestID: 13, body: .getAppIcon))
        let last = try await harness.frames(8)
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 8)
        XCTAssertEqual(last[7], Frame(requestID: 13, body: Self.noIcon))
        XCTAssertFalse(harness.transport.isClosed)
    }

    // MARK: - S-SHOT-08

    func test_S_SHOT_08_missingLayersDoNotEndTheStream() async throws {
        let harness = SessionHarness(capture: ScriptedCapture(missing: [99]))
        try await harness.handshake()

        // The request of the `layer-details` fixture: layers 3, 4 and 99.
        harness.receive(try Fixtures.frame("layer-details/01-c2s-get-layer-details.bin"))
        let frames = try await harness.frames(6)
        assertChunks(frames[2..<5], of: 3, layers: [3, 4, 99])
        XCTAssertEqual(frames[5], end(3, .completed, 3))

        // The fixture's detail of layer 99: the status and nothing else (P-DET-02).
        let fixture = chunk(try Fixtures.frame("layer-details/03-s2c-chunk-1.bin")).details[1]
        XCTAssertEqual(chunk(frames[4]).details, [fixture])
        XCTAssertEqual(fixture, LayerDetail(layerID: 99, status: .layerNotFound))
        XCTAssertEqual(chunk(frames[2]).details[0].status, .ok)
    }

    // MARK: - S-SHOT-10

    func test_S_SHOT_10_failsAtOnceWhenTheAppIsNotActive() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        let notActive = WireError(code: .appNotActive, message: "the app is not active")

        var count = 2
        for state in [AppState.inactive, .background] {
            harness.setAppState(state)
            harness.receive(details(UInt32(count), [1, 2]))
            count += 2
            let frames = try await harness.frames(count)
            XCTAssertEqual(frames[count - 2], Frame(requestID: 0, body: .appStateChanged(state)))
            XCTAssertEqual(frames[count - 1], end(UInt32(count - 2), .failed, 0, error: notActive))
        }
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 6)
        XCTAssertEqual(harness.capture.captured, [], "a layer was captured while the app was not active")

        // Active again: the same request is served.
        harness.setAppState(.active)
        harness.receive(details(9, [1, 2]))
        let frames = try await harness.frames(10)
        XCTAssertEqual(frames[6], Self.active)
        assertChunks(frames[7..<9], of: 9, layers: [1, 2])
        XCTAssertEqual(frames[9], end(9, .completed, 2))
    }

    func test_S_SHOT_10_failsWhenTheAppLeavesDuringTheStream() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        let capture = harness.capture

        // The `layer-details-failed` scenario: the app resigns while layer 2 is captured.
        capture.hold(2)
        harness.receive(try Fixtures.frame("layer-details-failed/01-c2s-get-layer-details.bin"))
        try await waitUntil("the capture of layer 2 to be asked for") { capture.isWaiting(2) }
        harness.setAppState(.inactive)
        var frames = try await harness.frames(4)
        // The event first, then the end of the stream: the fixture's two frames.
        XCTAssertEqual(frames[2], try Fixtures.frame("layer-details-failed/02-s2c-app-state.bin"))
        XCTAssertEqual(frames[3], try Fixtures.frame("layer-details-failed/03-s2c-stream-end.bin"))
        capture.release(2)
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 4, "a chunk was sent after the app left the active state")
        XCTAssertEqual(capture.captured, [])

        // With chunks already sent, the end counts them. Waiting requests are refused in turn.
        harness.setAppState(.active)
        capture.hold(13)
        harness.receive(details(20, [11, 12, 13, 14]), details(21, [15]))
        frames = try await harness.frames(7)
        try await waitUntil("the capture of layer 13 to be asked for") { capture.isWaiting(13) }
        harness.setAppState(.background)
        frames = try await harness.frames(10)
        capture.release(13)
        await harness.settle()
        XCTAssertEqual(harness.transport.sent.count, 10)
        XCTAssertEqual(frames[4], Self.active)
        assertChunks(frames[5..<7], of: 20, layers: [11, 12])
        XCTAssertEqual(frames[7], Frame(requestID: 0, body: .appStateChanged(.background)))
        XCTAssertEqual(
            frames[8],
            end(
                20,
                .failed,
                2,
                error: WireError(
                    code: .appNotActive,
                    message: "the app left the active state during capture"
                )
            )
        )
        XCTAssertEqual(
            frames[9],
            end(21, .failed, 0, error: WireError(code: .appNotActive, message: "the app is not active"))
        )
        XCTAssertEqual(capture.captured, [11, 12])

        // A change between two states that are not active ends nothing twice.
        harness.setAppState(.inactive)
        harness.setAppState(.active)
        harness.receive(details(30, [16]))
        frames = try await harness.frames(14)
        XCTAssertEqual(frames[10], Frame(requestID: 0, body: .appStateChanged(.inactive)))
        XCTAssertEqual(frames[11], Self.active)
        assertChunks(frames[12..<13], of: 30, layers: [16])
        XCTAssertEqual(frames[13], end(30, .completed, 1))
    }

    func test_S_SHOT_10_theStreamStopsWhenTheSessionEnds() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        let capture = harness.capture
        capture.hold(2)

        harness.receive(details(1, [1, 2, 3]), details(2, [4]))
        _ = try await harness.frames(3)
        try await waitUntil("the capture of layer 2 to be asked for") { capture.isWaiting(2) }
        harness.closeFromThePeer()
        capture.release(2)
        await harness.settle()

        XCTAssertEqual(harness.transport.sent.count, 3, "frames were sent after the client left")
        XCTAssertEqual(capture.captured, [1], "layers were captured after the client left")
        XCTAssertEqual(harness.endedCount, 1)
    }
}
