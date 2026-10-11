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
    func compressed() -> LayerDetail {
        var encoded = LayerDetail(
            layerID: layerID,
            status: status,
            attributeGroups: attributeGroups,
            constraints: constraints
        )
        for (image, slot) in [(solo, \LayerDetail.solo), (group, \LayerDetail.group)] {
            guard let image else { continue }
            guard let compressed = ImageEncoder.compress(image) else {
                return LayerDetail(
                    layerID: layerID,
                    status: .captureFailed,
                    attributeGroups: attributeGroups,
                    constraints: constraints
                )
            }
            encoded[keyPath: slot] = compressed
        }
        return encoded
    }
}
#endif
