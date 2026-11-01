import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// The digests of images and unchanged images (PROTOCOL.md, P-DET-11, P-IMG-04, P-IMG-05),
/// without a session: the digest itself, and what compressing a detail gives with them.
final class ImageDigestTests: XCTestCase {
    /// The images of a fixture chunk, decompressed into what the renderer would have produced.
    private func rawImages(_ path: String) throws -> [(raw: RawImage, digest: Data?)] {
        guard case .layerDetailsChunk(let chunk)? = try Fixtures.frame(path).body else {
            throw TestClientError(description: "\(path) is not a chunk")
        }
        return try chunk.details.compactMap(\.group).filter { !$0.isUnchanged }.map { image in
            let pixels = try (image.data as NSData).decompressed(using: .lzfse) as Data
            let raw = RawImage(
                pixelWidth: Int(image.pixelWidth),
                pixelHeight: Int(image.pixelHeight),
                bytesPerRow: Int(image.bytesPerRow),
                scale: image.scale,
                pixels: pixels
            )
            return (raw, image.digest)
        }
    }

    private func image(width: Int = 4, height: Int = 2, scale: Float = 2, fill: UInt8 = 0x40) -> RawImage {
        RawImage(
            pixelWidth: width,
            pixelHeight: height,
            bytesPerRow: width * 4,
            scale: scale,
            pixels: Data(repeating: fill, count: width * height * 4)
        )
    }

    private func detail(solo: RawImage? = nil, group: RawImage?) -> CapturedDetail {
        CapturedDetail(layerID: 3, status: .ok, solo: solo, group: group, attributeGroups: [])
    }

    private func digests(solo: Data? = nil, group: Data? = nil) -> KnownDigests? {
        KnownDigests(
            LayerDetailRequest(
                layerID: 3,
                wantSolo: true,
                wantGroup: true,
                wantAttributes: false,
                knownSoloDigest: solo,
                knownGroupDigest: group
            ),
            version: .current
        )
    }

    /// The suggested algorithm, so the fixtures' digests: the red, the orange with 16 padding
    /// bytes at the end of each row, and the redrawn blue.
    func test_S_SHOT_14_digestsAreThoseOfTheFixtures() throws {
        let images = try rawImages("layer-details-digest/02-s2c-chunk-0.bin")
            + rawImages("layer-details-digest/08-s2c-chunk-0.bin")
        XCTAssertEqual(images.map(\.raw.bytesPerRow), [800, 256, 240])
        for (raw, digest) in images {
            XCTAssertEqual(ImageDigest.of(raw), digest)
        }
    }

    /// The same content, the same digest; any of the size, the scale or a pixel different, a
    /// different digest. Padding does not count.
    func test_S_SHOT_14_digestFollowsTheContent() {
        let base = ImageDigest.of(image())
        XCTAssertEqual(base.count, 16)
        XCTAssertEqual(ImageDigest.of(image()), base)
        XCTAssertNotEqual(ImageDigest.of(image(width: 2, height: 4)), base)
        XCTAssertNotEqual(ImageDigest.of(image(scale: 3)), base)
        var changed = image()
        changed.pixels[5] ^= 1
        XCTAssertNotEqual(ImageDigest.of(changed), base)

        var padded = image()
        padded.bytesPerRow = 20
        padded.pixels = Data((0..<2).flatMap { _ in [UInt8](repeating: 0x40, count: 16) + [1, 2, 3, 4] })
        XCTAssertEqual(ImageDigest.of(padded), base)
    }

    /// For a client of 1.3: every image carries its digest; a client of 1.2 gets none.
    func test_S_SHOT_14_imagesCarryTheirDigestFrom1_3() throws {
        let solo = image(fill: 1)
        let group = image(fill: 2)
        let encoded = detail(solo: solo, group: group).compressed(digests: digests())
        XCTAssertEqual(encoded.solo?.digest, ImageDigest.of(solo))
        XCTAssertEqual(encoded.group?.digest, ImageDigest.of(group))
        XCTAssertEqual(encoded.group?.isUnchanged, false)

        let request = LayerDetailRequest(layerID: 3, wantSolo: true, wantGroup: true, wantAttributes: false)
        XCTAssertNil(KnownDigests(request, version: ProtocolVersion(major: 1, minor: 2)))
        let old = detail(solo: solo, group: group).compressed(digests: nil)
        XCTAssertNil(old.solo?.digest)
        XCTAssertNil(old.group?.digest)
    }

    /// The image the client holds goes as an unchanged one: its digest, `unchanged`, nothing
    /// else. One redrawn goes in full with its new digest.
    func test_S_SHOT_15_heldImagesGoUnchanged() throws {
        let solo = image(fill: 1)
        let group = image(fill: 2)
        let encoded = detail(solo: solo, group: group)
            .compressed(digests: digests(solo: ImageDigest.of(solo), group: ImageDigest.of(image(fill: 9))))
        XCTAssertEqual(encoded.solo, .unchanged(digest: ImageDigest.of(solo)))
        XCTAssertEqual(encoded.solo?.data, Data())
        let redrawn = try XCTUnwrap(encoded.group)
        XCTAssertFalse(redrawn.isUnchanged)
        XCTAssertEqual(redrawn.digest, ImageDigest.of(group))
        XCTAssertEqual(redrawn.pixelWidth, 4)
        XCTAssertFalse(redrawn.data.isEmpty)
    }

    /// Each kind with its own digest only: a solo's digest does not answer for the group, which
    /// is what a leaf sent only its group gets compared with (P-DET-04).
    func test_S_SHOT_15_digestsAreComparedWithTheirOwnKind() {
        let group = image(fill: 2)
        let digest = ImageDigest.of(group)
        XCTAssertFalse(detail(group: group).compressed(digests: digests(solo: digest)).group?.isUnchanged ?? true)
        XCTAssertEqual(
            detail(group: group).compressed(digests: digests(solo: digest, group: digest)).group,
            .unchanged(digest: digest)
        )
    }

    /// P-DET-11: the digest of an image not requested is ignored.
    func test_S_SHOT_15_digestsOfImagesNotRequestedAreIgnored() throws {
        let request = LayerDetailRequest(
            layerID: 3,
            wantSolo: false,
            wantGroup: true,
            wantAttributes: false,
            knownSoloDigest: Data([1]),
            knownGroupDigest: Data([2])
        )
        let known = try XCTUnwrap(KnownDigests(request, version: .current))
        XCTAssertNil(known.solo)
        XCTAssertEqual(known.group, Data([2]))
    }
}
