#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Answers one `LayerDetailRequest` (PROTOCOL.md, P-DET-02 to P-DET-04).
@MainActor
enum DetailCapture {
    /// `nil` when `stopFlag` was set: the stream is over and nothing more is rendered.
    ///
    /// - Parameters:
    ///   - windows: The app's windows; a layer in none of them does not exist (P-HIER-12).
    ///   - readAttributes: Reads the layer's attribute groups; called only when the request
    ///     wants them.
    ///   - render: Renders one image; tests time it apart from the rest (S-STAB-01).
    static func capture(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        windows: [UIWindow],
        registry: LayerRegistry,
        stopFlag: StopFlag,
        screenScale: CGFloat = UIScreen.main.scale,
        readAttributes: (CALayer) -> [AttributeGroup],
        render: (CALayer, LayerRenderer.Mode, ImagePlan) -> RawImage? = {
            LayerRenderer.render($0, mode: $1, plan: $2)
        }
    ) -> CapturedDetail? {
        guard !stopFlag.isSet else { return nil }
        var detail = CapturedDetail(
            layerID: request.layerID,
            status: .layerNotFound,
            solo: nil,
            group: nil,
            attributeGroups: []
        )
        // P-DET-02, P-HIER-12: the ID was never given out, its layer was released, or the layer
        // is in none of the app's windows.
        guard let layer = registry.layer(for: request.layerID),
              LayerTopology.ancestors(of: layer, in: windows) != nil else {
            return detail
        }
        detail.status = .ok
        if request.wantAttributes { detail.attributeGroups = readAttributes(layer) }
        if request.wantConstraints, let view = LayerTopology.backingView(of: layer) {
            detail.constraints = ConstraintCapture.constraints(
                of: view,
                registry: registry,
                screenScale: screenScale
            )
        }
        guard request.wantSolo || request.wantGroup else { return detail }

        // P-DET-03: no image, but the attributes and the constraints stay.
        detail.status = .captureFailed
        guard let plan = ImageSizing.plan(
            bounds: layer.bounds,
            screenScale: screenScale,
            maxTextureDimension: maxTextureDimension
        ) else {
            return detail
        }

        // P-DET-04: without sublayers the two images are the same; the group stands for both.
        let hasSublayers = !(layer.sublayers ?? []).isEmpty
        var solo: RawImage?
        var group: RawImage?
        if request.wantSolo, !(request.wantGroup && !hasSublayers) {
            guard let image = render(layer, .solo, plan) else { return detail }
            solo = image
        }
        if request.wantGroup {
            // Between two screenshots: a cancelled stream renders nothing more.
            guard !stopFlag.isSet else { return nil }
            guard let image = render(layer, .group, plan) else { return detail }
            group = image
        }
        detail.status = .ok
        detail.solo = solo
        detail.group = group
        return detail
    }
}
#endif
