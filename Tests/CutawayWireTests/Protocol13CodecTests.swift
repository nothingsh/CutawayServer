import CutawayWire
import Foundation
import XCTest

/// What protocol 1.3 adds: the digests of images and unchanged images (P-DET-11, P-IMG-04,
/// P-IMG-05), and the messages of hierarchy change notifications (P-WATCH-01 to 03). They
/// decode into the project's value types and encode back.
final class Protocol13CodecTests: XCTestCase {
    private func fixture(_ path: String) throws -> Frame {
        try FrameCodec.decode(RepositoryFiles.fixture(path))
    }

    private func chunk(_ path: String, file: StaticString = #filePath, line: UInt = #line) throws -> LayerDetailsChunk {
        guard case .layerDetailsChunk(let chunk)? = try fixture(path).body else {
            XCTFail("\(path) is not a LayerDetailsChunk", file: file, line: line)
            return LayerDetailsChunk(sequence: 0, details: [])
        }
        return chunk
    }

    private func requests(_ path: String) throws -> [LayerDetailRequest] {
        guard case .getLayerDetails(let get)? = try fixture(path).body else {
            XCTFail("\(path) is not a GetLayerDetails")
            return []
        }
        return get.requests
    }

    private let red = Data([9, 136, 181, 224, 100, 253, 207, 200, 219, 178, 16, 26, 42, 236, 171, 89])
    private let orange = Data([152, 60, 148, 35, 245, 62, 184, 98, 64, 130, 105, 173, 103, 185, 100, 119])

    func test_S_SHOT_14_decodesTheDigestsOfTheFixtures() throws {
        // Without digests, none is read.
        XCTAssertEqual(
            try requests("layer-details-digest/01-c2s-get-layer-details.bin").map(\.knownGroupDigest),
            [nil, nil]
        )
        let first = try chunk("layer-details-digest/02-s2c-chunk-0.bin")
        XCTAssertEqual(first.details.map(\.group?.digest), [red, orange])
        XCTAssertEqual(first.details.map(\.group?.isUnchanged), [false, false])
        XCTAssertEqual(first.details.map(\.solo), [nil, nil])

        let again = try requests("layer-details-digest/04-c2s-get-layer-details.bin")
        XCTAssertEqual(again.map(\.knownSoloDigest), [red, nil])
        XCTAssertEqual(again.map(\.knownGroupDigest), [red, orange])
    }

    /// P-IMG-05: the digest, `unchanged` and nothing else; one redrawn image beside an unchanged one.
    func test_S_SHOT_15_decodesTheUnchangedImagesOfTheFixtures() throws {
        let unchanged = try chunk("layer-details-digest/05-s2c-chunk-0.bin")
        XCTAssertEqual(unchanged.details.map(\.group), [.unchanged(digest: red), .unchanged(digest: orange)])

        let redrawn = try chunk("layer-details-digest/08-s2c-chunk-0.bin")
        XCTAssertEqual(redrawn.details[0].group, .unchanged(digest: red))
        let blue = try XCTUnwrap(redrawn.details[1].group)
        XCTAssertFalse(blue.isUnchanged)
        XCTAssertEqual([blue.pixelWidth, blue.pixelHeight, blue.bytesPerRow], [60, 30, 240])
        XCTAssertEqual(blue.digest?.count, 16)
        XCTAssertNotEqual(blue.digest, orange)
    }

    func test_S_WATCH_01_decodesTheWatchFixtures() throws {
        let expected: [(String, Frame)] = [
            ("watch-hierarchy/03-c2s-watch-hierarchy.bin", Frame(requestID: 2, body: .watchHierarchy(enabled: true))),
            (
                "watch-hierarchy/04-s2c-watch-hierarchy-result.bin",
                Frame(requestID: 2, body: .watchHierarchyResult(enabled: true))
            ),
            (
                "watch-hierarchy/05-s2c-hierarchy-changed.bin",
                Frame(requestID: 0, body: .hierarchyChanged(HierarchyChanged(roots: [3, 4], whole: false)))
            ),
            ("watch-hierarchy/12-s2c-hierarchy-changed.bin", Frame(requestID: 0, body: .hierarchyChanged(.everything))),
            ("watch-hierarchy/15-c2s-watch-hierarchy.bin", Frame(requestID: 6, body: .watchHierarchy(enabled: false))),
            (
                "watch-hierarchy/16-s2c-watch-hierarchy-result.bin",
                Frame(requestID: 6, body: .watchHierarchyResult(enabled: false))
            )
        ]
        for (path, frame) in expected {
            XCTAssertEqual(try fixture(path), frame, path)
        }
        let digests = try requests("watch-hierarchy/08-c2s-get-layer-details.bin")
        XCTAssertEqual(digests.map(\.layerID), [3, 4])
        XCTAssertEqual(digests[0].knownGroupDigest, red)
    }
}
