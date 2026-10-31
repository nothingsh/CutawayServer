#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Answers one `LayerDetailRequest` (PROTOCOL.md, P-DET-02 to P-DET-04).
@MainActor
enum DetailCapture {
    /// `nil` when `stopFlag` was set: the stream is over and nothing more is rendered.
    ///
    /// - Parameters:
    ///   - context: The request's windows (a layer in none of them does not exist, P-HIER-12),
    ///     its registry, and what the host app registered.
    ///   - readAttributes: Reads the layer's attribute groups; called only when the request
    ///     wants them.
    ///   - readVirtualAttributes: The same for a virtual node.
    ///   - render: Renders one image; the stability tests time it apart from the rest.
    ///   - composite: Takes a group from what the app composited; timed the same way.
    static func capture(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        in context: RequestContext,
        stopFlag: StopFlag,
        screenScale: CGFloat = UIScreen.main.scale,
        readAttributes: (CALayer) -> [AttributeGroup],
        readVirtualAttributes: (VirtualNodes.Found) -> [AttributeGroup] = { _ in [] },
        render: (CALayer, LayerRenderer.Mode, ImagePlan) -> RawImage? = {
            LayerRenderer.render($0, mode: $1, plan: $2)
        },
        composite: (UIView, ImagePlan) -> RawImage? = { LayerRenderer.composited($0, plan: $1) }
    ) -> CapturedDetail? {
        guard !stopFlag.isSet else { return nil }
        var detail = CapturedDetail(
            layerID: request.layerID,
            status: .layerNotFound,
            solo: nil,
            group: nil,
            attributeGroups: []
        )
        // `nil` when the host app registered nothing.
        let lookup = context.extensions.isEmpty ? nil : context.extensions
        // `nil` too when nothing it registered excludes a layer from images (P-DET-10).
        let exclusions = lookup?.store.hasExclusions == true ? lookup : nil
        // P-DET-02, P-HIER-12: the ID was never given out, its layer was released, or the layer
        // is in none of the app's windows.
        guard let layer = context.registry.layer(for: request.layerID) else {
            if lookup != nil {
                readVirtualNode(for: request, into: &detail, in: context, readAttributes: readVirtualAttributes)
            }
            return detail
        }
        guard let ancestors = LayerTopology.ancestors(of: layer, in: context.windows) else { return detail }
        detail.status = .ok
        readContents(
            of: layer,
            for: request,
            into: &detail,
            registry: context.registry,
            screenScale: screenScale,
            readAttributes: readAttributes
        )
        // P-DET-10: excluded with an excluded ancestor, also when no image is wanted.
        if let exclusions, VirtualNodes.isExcluded(ancestors + [layer], lookup: exclusions) {
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
            let image = groupImage(
                of: layer,
                plan: plan,
                in: context,
                exclusions: exclusions,
                render: render,
                composite: composite
            )
            guard let image else { return detail }
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
        in context: RequestContext,
        readAttributes: (VirtualNodes.Found) -> [AttributeGroup]
    ) {
        // The request's trees: a stream that names several nodes of a layer asks the host app
        // for that layer's once.
        let trees = context.memo.entry(VirtualNodes.Trees.init)
        guard let node = VirtualNodes.find(request.layerID, in: context, trees: trees) else { return }
        detail.status = node.isExcluded ? .excluded : .ok
        if request.wantAttributes { detail.attributeGroups = readAttributes(node) }
    }

    /// The group: from what the app composited where that is possible and worth it (P-IMG-07),
    /// otherwise drawn, with the layers below left out that must not be in it.
    ///
    /// - Parameter exclusions: `nil` when the host app excludes no layer: nothing need be
    ///   searched for excluded layers.
    private static func groupImage(
        of layer: CALayer,
        plan: ImagePlan,
        in context: RequestContext,
        exclusions: ExtensionLookup?,
        render: (CALayer, LayerRenderer.Mode, ImagePlan) -> RawImage?,
        composite: (UIView, ImagePlan) -> RawImage?
    ) -> RawImage? {
        guard !(layer.sublayers ?? []).isEmpty else { return render(layer, .group, plan) }
        let effects = context.memo.entry { RenderEffects(windows: context.windows) }
        if let view = viewToComposite(of: layer, effects: effects, in: context, exclusions: exclusions),
           let image = composite(view, plan) {
            return image
        }
        let excluded = exclusions.map { excludedLayers(below: layer, lookup: $0) } ?? []
        return hiding(excluded + effects.erasers(below: layer)) { render(layer, .group, plan) }
    }

    /// The view whose composited image can stand for the group of `layer`, a layer with
    /// sublayers. A window always, so that it is the picture of the window, whatever is in it;
    /// another view when drawing would leave something out: it is slower than drawing on small
    /// images. Not one that is hidden or translucent itself, whose image would show that
    /// (P-DET-07), and none while an excluded layer shows: it cannot be hidden for this
    /// (P-DET-10), and an effect may sample it from outside the subtree. That is looked for
    /// each time, as an excluded layer that appears during a stream must not get through.
    private static func viewToComposite(
        of layer: CALayer,
        effects: RenderEffects,
        in context: RequestContext,
        exclusions: ExtensionLookup?
    ) -> UIView? {
        guard !layer.isHidden, layer.opacity == 1, let view = LayerTopology.backingView(of: layer) else { return nil }
        guard view is UIWindow || effects.hasEffect(in: layer) else { return nil }
        if let exclusions, context.windows.contains(where: { showsExcludedLayer($0, lookup: exclusions) }) {
            return nil
        }
        return view
    }

    private static func showsExcludedLayer(_ window: UIWindow, lookup: ExtensionLookup) -> Bool {
        guard !window.isHidden else { return false }
        return lookup.resolve(window.layer, view: window).isExcludedFromCapture
            || !excludedLayers(below: window.layer, lookup: lookup).isEmpty
    }

    /// The layers below `layer` the host app excludes from images and that are visible now; the
    /// layers below them need not be looked at.
    static func excludedLayers(below layer: CALayer, lookup: ExtensionLookup) -> [CALayer] {
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
