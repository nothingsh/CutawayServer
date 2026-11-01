import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// Digests and unchanged images through a session, by the negotiated version (P-IMG-04,
/// P-IMG-05, P-HELLO-04).
final class ImageDigestSessionTests: XCTestCase {
    /// The group of layer 4, with the digest the client holds for it.
    private func request(_ requestID: UInt32, known: Data?) -> Frame {
        Frame(
            requestID: requestID,
            body: .getLayerDetails(
                GetLayerDetails(
                    requests: [
                        LayerDetailRequest(
                            layerID: 4,
                            wantSolo: false,
                            wantGroup: true,
                            wantAttributes: false,
                            knownGroupDigest: known
                        )
                    ],
                    maxTextureDimension: 0
                )
            )
        )
    }

    /// The group of the one detail of a stream's chunk, and the frames it took.
    private func group(
        of request: Frame,
        in harness: SessionHarness,
        after count: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> WireImage {
        harness.receive(request)
        let frames = try await harness.frames(count + 2)
        guard case .layerDetailsChunk(let chunk)? = frames[count].body, let group = chunk.details.first?.group else {
            XCTFail("expected a chunk with a group, got \(frames[count])", file: file, line: line)
            throw CancellationError()
        }
        return group
    }

    func test_S_SHOT_15_aClientOf1_3GetsUnchangedImages() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        let first = try await group(of: request(1, known: nil), in: harness, after: 2)
        let digest = try XCTUnwrap(first.digest)
        XCTAssertEqual(digest.count, 16)
        XCTAssertFalse(first.isUnchanged)

        let again = try await group(of: request(2, known: digest), in: harness, after: 4)
        XCTAssertEqual(again, .unchanged(digest: digest))

        // Another digest: the image in full.
        let other = try await group(of: request(3, known: Data([1, 2, 3])), in: harness, after: 6)
        XCTAssertEqual(other, first)
    }

    func test_S_CONN_12_aClientOf1_2GetsNoDigests() async throws {
        let harness = SessionHarness()
        try await harness.handshake(version: ProtocolVersion(major: 1, minor: 2))
        let first = try await group(of: request(1, known: nil), in: harness, after: 2)
        XCTAssertNil(first.digest)
        let again = try await group(of: request(2, known: Data(repeating: 0, count: 16)), in: harness, after: 4)
        XCTAssertFalse(again.isUnchanged)
        XCTAssertEqual(again, first)
    }
}
