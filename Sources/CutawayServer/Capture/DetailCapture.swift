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
    ///   - extensions: What the host app registered (S-API-04); `nil` for nothing.
    ///   - readAttributes: Reads the layer's attribute groups; called only when the request
    ///     wants them.
    ///   - readVirtualAttributes: The same for a virtual node.
    ///   - render: Renders one image; tests time it apart from the rest (S-STAB-01).
    static func capture(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        windows: [UIWindow],
        registry: LayerRegistry,
        stopFlag: StopFlag,
        screenScale: CGFloat = UIScreen.main.scale,
        extensions: ExtensionStore? = nil,
        readAttributes: (CALayer) -> [AttributeGroup],
        readVirtualAttributes: (VirtualNodes.Found) -> [AttributeGroup] = { _ in [] },
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
        let lookup = extensions.flatMap { $0.isEmpty ? nil : ExtensionLookup(store: $0) }
        // P-DET-02, P-HIER-12: the ID was never given out, its layer was released, or the layer
        // is in none of the app's windows.
        guard let layer = registry.layer(for: request.layerID) else {
            readVirtualNode(for: request, into: &detail, windows: windows, registry: registry, lookup: lookup) {
                readVirtualAttributes($0)
            }
            return detail
        }
        guard let ancestors = LayerTopology.ancestors(of: layer, in: windows) else { return detail }
        detail.status = .ok
        readContents(
            of: layer,
            for: request,
            into: &detail,
            registry: registry,
            screenScale: screenScale,
            readAttributes: readAttributes
        )
        // P-DET-10: excluded with an excluded ancestor, also when no image is wanted.
        if var lookup, VirtualNodes.isExcluded(ancestors + [layer], lookup: &lookup) {
            detail.status = .excluded
            return detail
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
            guard let image = groupImage(of: layer, plan: plan, lookup: lookup, render: render) else { return detail }
            group = image
        }
        detail.status = .ok
        detail.solo = solo
        detail.group = group
        return detail
    }

    /// The attributes and the constraints the request wants; they are given whatever happens to
    /// the images (P-DET-03, P-DET-10).
    private static func readContents(
        of layer: CALayer,
        for request: LayerDetailRequest,
        into detail: inout CapturedDetail,
        registry: LayerRegistry,
        screenScale: CGFloat,
        readAttributes: (CALayer) -> [AttributeGroup]
    ) {
        if request.wantAttributes { detail.attributeGroups = readAttributes(layer) }
        if request.wantConstraints, let view = LayerTopology.backingView(of: layer) {
            detail.constraints = ConstraintCapture.constraints(
                of: view,
                registry: registry,
                screenScale: screenScale
            )
        }
    }

    /// P-DET-09: a virtual node that exists is `ok`, or `excluded` below an excluded layer; it has
    /// no images of its own, no constraints, and only the host app's groups. One that does not
    /// exist leaves `detail` `layerNotFound`.
    private static func readVirtualNode(
        for request: LayerDetailRequest,
        into detail: inout CapturedDetail,
        windows: [UIWindow],
        registry: LayerRegistry,
        lookup: ExtensionLookup?,
        readAttributes: (VirtualNodes.Found) -> [AttributeGroup]
    ) {
        guard var lookup,
              let node = VirtualNodes.find(request.layerID, windows: windows, registry: registry, lookup: &lookup)
        else {
            return
        }
        detail.status = node.isExcluded ? .excluded : .ok
        if request.wantAttributes { detail.attributeGroups = readAttributes(node) }
    }

    /// P-DET-10: the group, with the excluded layers below left out as if they were hidden.
    private static func groupImage(
        of layer: CALayer,
        plan: ImagePlan,
        lookup: ExtensionLookup?,
        render: (CALayer, LayerRenderer.Mode, ImagePlan) -> RawImage?
    ) -> RawImage? {
        guard let lookup else { return render(layer, .group, plan) }
        return hiding(excludedLayers(below: layer, lookup: lookup)) { render(layer, .group, plan) }
    }

    /// The layers below `layer` the host app excludes from images and that are visible now; the
    /// layers below them need not be looked at.
    static func excludedLayers(below layer: CALayer, lookup: ExtensionLookup) -> [CALayer] {
        var lookup = lookup
        var excluded: [CALayer] = []
        var stack = layer.sublayers ?? []
        while let next = stack.popLast() {
            guard !next.isHidden else { continue }
            if lookup.resolve(next, view: LayerTopology.backingView(of: next)).isExcludedFromCapture {
                excluded.append(next)
            } else {
                stack += next.sublayers ?? []
            }
        }
        return excluded
    }

    /// Runs `body` with `layers` hidden, and shows them again before anything is committed, so
    /// that neither the render server nor an animation sees the change (as `LayerRenderer` does).
    private static func hiding<Result>(_ layers: [CALayer], while body: () -> Result) -> Result {
        guard !layers.isEmpty else { return body() }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            for layer in layers { layer.isHidden = false }
            CATransaction.commit()
        }
        for layer in layers { layer.isHidden = true }
        return body()
    }
}
#endif
