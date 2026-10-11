#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import QuartzCore

/// Renders one layer into a bitmap that covers exactly its bounds (PROTOCOL.md, P-DET-07).
@MainActor
enum LayerRenderer {
    enum Mode {
        /// The layer without its sublayers.
        case solo
        /// The layer with its whole subtree.
        case group
    }

    /// `nil` when the bitmap cannot be made or `draw` reports a failure.
    ///
    /// The image shows the layer as it is with an opacity of 1, visible and not transformed.
    /// Whatever is changed on the layers for that is put back before this returns.
    ///
    /// - Parameter draw: Draws the layer into the context; tests replace it to fail half way.
    static func render(
        _ layer: CALayer,
        mode: Mode,
        plan: ImagePlan,
        draw: (CALayer, CGContext) -> Bool = { layer, context in
            layer.render(in: context)
            return true
        }
    ) -> RawImage? {
        let bounds = layer.bounds
        let bytesPerRow = plan.pixelWidth * 4
        var pixels = Data(count: bytesPerRow * plan.pixelHeight)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = BitmapContext.bgra(
                width: plan.pixelWidth,
                height: plan.pixelHeight,
                bytesPerRow: bytesPerRow,
                data: buffer.baseAddress
            ) else {
                return false
            }
            // Core Graphics counts rows from the bottom; layers count from the top. After this the
            // image's top left corner is the origin of the bounds, and the image spans the bounds.
            context.translateBy(x: 0, y: CGFloat(plan.pixelHeight))
            context.scaleBy(
                x: CGFloat(plan.pixelWidth) / bounds.width,
                y: -CGFloat(plan.pixelHeight) / bounds.height
            )
            context.translateBy(x: -bounds.origin.x, y: -bounds.origin.y)
            return withoutOwnEffects(of: layer, mode: mode) { draw(layer, context) }
        }
        guard drawn else { return nil }
        return RawImage(
            pixelWidth: plan.pixelWidth,
            pixelHeight: plan.pixelHeight,
            bytesPerRow: bytesPerRow,
            scale: plan.scale,
            pixels: pixels
        )
    }

    /// `render(in:)` draws a layer with its own opacity and not at all when it is hidden, and
    /// it always draws the sublayers. For the time of `body` the layer is opaque and visible,
    /// and for a solo image its sublayers are hidden. Everything is put back on every path.
    private static func withoutOwnEffects(of layer: CALayer, mode: Mode, _ body: () -> Bool) -> Bool {
        CATransaction.begin()
        // No implicit animations: the values are back before anything is committed.
        CATransaction.setDisableActions(true)
        let opacity = layer.opacity
        let wasHidden = layer.isHidden
        var hiddenSublayers: [CALayer] = []
        defer {
            for sublayer in hiddenSublayers { sublayer.isHidden = false }
            if wasHidden { layer.isHidden = true }
            if opacity != 1 { layer.opacity = opacity }
            CATransaction.commit()
        }
        if opacity != 1 { layer.opacity = 1 }
        if wasHidden { layer.isHidden = false }
        if mode == .solo {
            for sublayer in layer.sublayers ?? [] where !sublayer.isHidden {
                sublayer.isHidden = true
                hiddenSublayers.append(sublayer)
            }
        }
        return body()
    }
}
#endif
