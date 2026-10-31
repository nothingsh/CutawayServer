#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import UIKit

/// What `render(in:)` gets wrong in a request's windows, found once for a request: a stream
/// asks for many groups, and looking through each one's subtree would take quadratic time.
/// A layer that appears during a stream is missed until the next request.
@MainActor
final class RenderEffects {
    private let erasers: [CALayer]
    private let layersWithEffects: Set<ObjectIdentifier>

    init(windows: [UIWindow]) {
        var erasers: [CALayer] = []
        var withEffects = Set<ObjectIdentifier>()
        var stack = windows.map(\.layer)
        while let next = stack.popLast() {
            if Self.erases(next) { erasers.append(next) }
            if Self.hasEffect(next) {
                var current: CALayer? = next
                // Stops at the first one already marked: its ancestors are, too.
                while let layer = current, withEffects.insert(ObjectIdentifier(layer)).inserted {
                    current = layer.superlayer
                }
            }
            stack += next.sublayers ?? []
        }
        self.erasers = erasers
        layersWithEffects = withEffects
    }

    /// Whether drawing `layer` with its subtree leaves something out.
    func hasEffect(in layer: CALayer) -> Bool {
        layersWithEffects.contains(ObjectIdentifier(layer))
    }

    /// The layers below `layer` to hide while it is drawn, or they wipe out what is drawn
    /// before them. Only the visible ones: hiding gives way to showing afterwards, and the app
    /// may have hidden one since they were found.
    func erasers(below layer: CALayer) -> [CALayer] {
        erasers.filter { eraser in
            guard !eraser.isHidden else { return false }
            var current = eraser.superlayer
            while let ancestor = current {
                if ancestor === layer { return true }
                current = ancestor.superlayer
            }
            return false
        }
    }

    /// On screen, a layer with `destIn` keeps what lies behind it where it has content. Portals
    /// have theirs on the render server, as the scroll edge effect of iOS 26 does: `render(in:)`
    /// finds nothing in them, and applies the filter all the same, which erases everything drawn
    /// so far. A `destIn` layer with content of its own draws correctly and stays. `destOut`
    /// erases nothing when empty; UIKit's is a `CAFilter`, not a string, so it is not read.
    private static func erases(_ layer: CALayer) -> Bool {
        layer.compositingFilter as? String == "destIn"
            && layer.contents == nil
            && layer.backgroundColor == nil
            && (layer.sublayers ?? []).isEmpty
            // These draw without `contents`.
            && !(layer is CAShapeLayer || layer is CAGradientLayer || layer is CATextLayer)
    }

    /// What `render(in:)` does not process, as far as public API can tell. Masks are not among
    /// them. The render server's own layers go unnoticed, but they come with one of these.
    private static func hasEffect(_ layer: CALayer) -> Bool {
        layer.compositingFilter != nil
            || layer.filters?.isEmpty == false
            || layer.backgroundFilters?.isEmpty == false
            || layer.delegate is UIVisualEffectView
    }
}
#endif
