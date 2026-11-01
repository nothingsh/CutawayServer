#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation

/// What the main thread produces for one requested layer. The images are not compressed
/// yet, and nothing here refers to the layer, so it may leave the main thread.
struct CapturedDetail: Sendable, Equatable {
    var layerID: UInt64
    var status: DetailStatus
    var solo: RawImage?
    var group: RawImage?
    var attributeGroups: [AttributeGroup]
    /// P-LAYOUT-01; empty unless the request wants them and the layer backs a view.
    var constraints: [LayoutConstraint] = []

    /// The uncompressed pixels of both images.
    var pixelByteCount: Int { (solo?.pixels.count ?? 0) + (group?.pixels.count ?? 0) }

    /// The detail as it goes on the wire, with its images compressed; any thread, meant for
    /// one other than the main thread. An image that cannot be compressed makes it a failed
    /// capture: no image, the attributes stay (PROTOCOL.md, P-DET-03).
    ///
    /// With `digests` (a client of 1.3 or later), each image carries its digest (P-IMG-04), and
    /// one whose digest is the one the client holds for that kind of image goes as an unchanged
    /// image, not compressed (P-IMG-05).
    ///
    /// Each image's pixels are let go once it is compressed, so that with two large images the
    /// first one's are not held while the second is compressed; that takes a detail no one else
    /// holds (see `HostAccess.encodeDetail`).
    consuming func compressed(digests: KnownDigests? = nil) -> LayerDetail {
        let failed = LayerDetail(
            layerID: layerID,
            status: .captureFailed,
            attributeGroups: attributeGroups,
            constraints: constraints
        )
        var encoded = LayerDetail(
            layerID: layerID,
            status: status,
            attributeGroups: attributeGroups,
            constraints: constraints
        )
        if let image = solo {
            solo = nil
            guard let compressed = Self.encode(image, known: digests.map { $0.solo }) else { return failed }
            encoded.solo = compressed
        }
        if let image = group {
            group = nil
            guard let compressed = Self.encode(image, known: digests.map { $0.group }) else { return failed }
            encoded.group = compressed
        }
        return encoded
    }

    /// `known` is `nil` without digests, and holds the client's digest for this kind of image,
    /// if any, with them.
    private static func encode(_ image: RawImage, known: Data??) -> WireImage? {
        guard let known else { return ImageEncoder.compress(image) }
        let digest = ImageDigest.of(image)
        if let known, known == digest { return .unchanged(digest: digest) }
        guard var compressed = ImageEncoder.compress(image) else { return nil }
        compressed.digest = digest
        return compressed
    }
}

/// What a client of 1.3 or later holds for one layer (P-DET-11): the digests it gave, each
/// compared with the image of the same kind only (P-IMG-05).
struct KnownDigests: Sendable, Equatable {
    var solo: Data?
    var group: Data?

    /// The digests of an item, for a client that has them; `nil` for one that does not, which
    /// gets no digests (P-IMG-04) and no unchanged images (P-IMG-05).
    init?(_ item: LayerDetailRequest, version: ProtocolVersion) {
        guard version.supportsImageDigests else { return nil }
        // P-DET-11: the digest of an image not requested is ignored.
        solo = item.wantSolo ? item.knownSoloDigest : nil
        group = item.wantGroup ? item.knownGroupDigest : nil
    }
}
#endif
