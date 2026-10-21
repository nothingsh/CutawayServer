#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire

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
    /// Each image's pixels are let go once it is compressed, so that with two large images the
    /// first one's are not held while the second is compressed; that takes a detail no one else
    /// holds (see `HostAccess.encodeDetail`).
    consuming func compressed() -> LayerDetail {
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
            guard let compressed = ImageEncoder.compress(image) else { return failed }
            encoded.solo = compressed
        }
        if let image = group {
            group = nil
            guard let compressed = ImageEncoder.compress(image) else { return failed }
            encoded.group = compressed
        }
        return encoded
    }
}
#endif
