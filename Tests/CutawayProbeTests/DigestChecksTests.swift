import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's checks of digests and unchanged images (S-PROBE-09): they accept the fixtures
/// of `layer-details-digest` and name what is wrong with anything else.
final class DigestChecksTests: XCTestCase {
    private func hierarchy() throws -> Hierarchy {
        try HierarchyChecks.hierarchy(try Fixtures.frame("hierarchy/02-s2c-hierarchy.bin"))
    }

    private func request(_ path: String) throws -> GetLayerDetails {
        guard case .getLayerDetails(let request)? = try Fixtures.frame(path).body else {
            throw ProbeFailure("\(path) is not a GetLayerDetails")
        }
        return request
    }

    /// The details of one exchange of the scenario: the request in `first`, then the chunk and
    /// the stream end.
    private func details(_ first: Int, request override: GetLayerDetails? = nil) throws -> [LayerDetail] {
        let name = { (index: Int, kind: String) in String(format: "layer-details-digest/%02d-%@.bin", index, kind) }
        let request = try override ?? request(name(first, "c2s-get-layer-details"))
        let frames = try [
            Fixtures.frame(name(first + 1, "s2c-chunk-0")),
            Fixtures.frame(name(first + 2, "s2c-stream-end"))
        ]
        return try DetailChecks.stream(frames, answering: frames[0].requestID, request: request, hierarchy: hierarchy())
    }

    func test_S_PROBE_09_digestChecksAcceptTheFixtures() throws {
        let first = try details(1)
        XCTAssertEqual(try DigestChecks.sameDigestsSamePixels(first), 2)
        // What the probe asks next is what the fixture's client asks.
        let again = DigestChecks.request(
            holding: first,
            of: try request("layer-details-digest/01-c2s-get-layer-details.bin")
        )
        XCTAssertEqual(
            again.requests.map(\.knownGroupDigest),
            try request("layer-details-digest/04-c2s-get-layer-details.bin").requests.map(\.knownGroupDigest)
        )
        XCTAssertEqual(try DigestChecks.allUnchanged(details(4), request: again), 2)
        // The redrawn image is not unchanged.
        XCTAssertThrowsError(try DigestChecks.allUnchanged(details(7), request: again)) { error in
            XCTAssertTrue("\(error)".contains("layer 8 came back in full"), "\(error)")
        }
    }

    func test_S_PROBE_09_digestChecksRejectBrokenImages() throws {
        let image = WireImage(pixelWidth: 1, pixelHeight: 1, bytesPerRow: 4, scale: 1, data: Data())
        func rejects(_ image: WireImage, known: Data? = nil, version: ProtocolVersion = .current, _ message: String) {
            XCTAssertThrowsError(try DigestChecks.digest(
                of: image,
                name: "it",
                known: known,
                version: version
            )) { error in
                XCTAssertTrue("\(error)".contains(message), "\(error)")
            }
        }
        rejects(image, "has no digest of 1 to 32 bytes (P-IMG-04)")
        var long = image
        long.digest = Data(count: 33)
        rejects(long, "has no digest of 1 to 32 bytes")
        rejects(.unchanged(digest: Data([1])), known: Data([2]), "not the one the request gave")
        rejects(.unchanged(digest: Data([1])), "not the one the request gave")
        rejects(
            .unchanged(digest: Data([1])),
            known: Data([1]),
            version: ProtocolVersion(major: 1, minor: 2),
            "below 1.3"
        )
        var full = WireImage.unchanged(digest: Data([1]))
        full.pixelWidth = 3
        rejects(full, known: Data([1]), "has fields other than its digest")
        // Before 1.3 a digest may be absent.
        XCTAssertTrue(try DigestChecks.digest(
            of: image,
            name: "it",
            known: nil,
            version: ProtocolVersion(major: 1, minor: 2)
        ))
    }

    /// Two images of different content under one digest.
    func test_S_PROBE_09_digestChecksRejectASharedDigest() throws {
        var first = try details(1)
        let shared = first[0].group?.digest
        first[1].group?.digest = shared
        XCTAssertThrowsError(try DigestChecks.sameDigestsSamePixels(first)) { error in
            XCTAssertTrue("\(error)".contains("has the digest of the group of layer 3, but other content"), "\(error)")
        }
    }
}
