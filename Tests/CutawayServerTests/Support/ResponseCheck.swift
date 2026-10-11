import CutawayWire
import Foundation
import XCTest

/// Pairs what a server sent with the requests it was sent, the way P-REQ-02 to P-REQ-06
/// allow: in the order of the requests, so that request IDs need not be unique. Events are
/// left out. A `Cancel` has no answer and is not among the requests.
enum ResponseCheck {
    enum Response: Equatable {
        /// The one frame that answers an ordinary request.
        case single(Frame)
        /// The details of every chunk, in order, and the end of the stream.
        case stream(details: [LayerDetail], end: StreamEnd)

        var frame: Frame? {
            if case .single(let frame) = self { return frame }
            return nil
        }

        var details: [LayerDetail] {
            if case .stream(let details, _) = self { return details }
            return []
        }

        var end: StreamEnd? {
            if case .stream(_, let end) = self { return end }
            return nil
        }
    }

    /// The answers of `requests`, one each, after the handshake's two frames unless they were
    /// taken before. Fails the test when the frames break one of the rules, or when frames are
    /// left over.
    static func responses(
        to requests: [Frame],
        in sent: [Frame],
        handshakeFrames: Int = 2,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> [Response] {
        var frames = sent.dropFirst(handshakeFrames).filter { frame in
            if case .appStateChanged? = frame.body { return false }
            return true
        }[...]
        var responses: [Response] = []
        for request in requests {
            guard case .getLayerDetails(let details)? = request.body else {
                // P-REQ-02: one frame with the request's ID.
                guard let frame = frames.popFirst() else {
                    XCTFail("no answer to \(request)", file: file, line: line)
                    return responses
                }
                XCTAssertEqual(frame.requestID, request.requestID, "the answer to \(request)", file: file, line: line)
                if case .layerDetailsChunk? = frame.body {
                    XCTFail("a chunk answers an ordinary request: \(frame)", file: file, line: line)
                }
                if case .streamEnd? = frame.body {
                    XCTFail("a StreamEnd answers an ordinary request: \(frame)", file: file, line: line)
                }
                responses.append(.single(frame))
                continue
            }
            // P-REQ-03: chunks numbered from 0, then one StreamEnd that counts them.
            var reported: [LayerDetail] = []
            var chunkCount: UInt32 = 0
            while let frame = frames.first, case .layerDetailsChunk(let chunk)? = frame.body {
                frames.removeFirst()
                XCTAssertEqual(frame.requestID, request.requestID, file: file, line: line)
                if chunk.sequence != chunkCount {
                    XCTFail("chunk \(chunkCount) has the sequence \(chunk.sequence)", file: file, line: line)
                }
                chunkCount += 1
                reported += chunk.details
            }
            guard let frame = frames.popFirst(), case .streamEnd(let end)? = frame.body else {
                XCTFail("the stream of request \(request.requestID) has no StreamEnd", file: file, line: line)
                return responses
            }
            XCTAssertEqual(frame.requestID, request.requestID, file: file, line: line)
            XCTAssertEqual(end.chunkCount, chunkCount, "P-REQ-03", file: file, line: line)
            if end.status == .completed {
                // P-DET-01, P-DET-06: every layer once, in the order of the request.
                XCTAssertTrue(
                    reported.map(\.layerID) == details.requests.map(\.layerID),
                    "the details of request \(request.requestID) are not the layers it asked for",
                    file: file,
                    line: line
                )
            }
            responses.append(.stream(details: reported, end: end))
        }
        XCTAssertEqual(Array(frames), [], "frames that answer no request", file: file, line: line)
        return responses
    }
}
