#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import UIKit

/// How layers, views, view controllers and windows relate. Only reads.
@MainActor
enum LayerTopology {
    /// P-HIER-04: a layer backs a view when the view is its delegate and it is the view's layer.
    static func backingView(of layer: CALayer) -> UIView? {
        guard let view = layer.delegate as? UIView, view.layer === layer else { return nil }
        return view
    }

    /// The view `layer` backs, or else the view of its nearest ancestor that backs one: whose
    /// traits its colors resolve with (P-ATTR-20).
    static func nearestView(of layer: CALayer) -> UIView? {
        var current: CALayer? = layer
        while let next = current {
            if let view = backingView(of: next) { return view }
            current = next.superlayer
        }
        return nil
    }

    /// P-HIER-07: a view controller's root view has the controller as its next responder.
    /// `viewIfLoaded` never loads a view.
    static func controller(ofRootView view: UIView) -> UIViewController? {
        guard let controller = view.next as? UIViewController, controller.viewIfLoaded === view else { return nil }
        return controller
    }

    /// The layers above `layer`, from its window's layer down to its parent; `nil` when no
    /// layer on the way up is the layer of one of `windows`. Empty for a window's own layer.
    /// A window's layer is not the top: UIKit puts layers of its own above it.
    static func ancestors(of layer: CALayer, in windows: [UIWindow]) -> [CALayer]? {
        ancestors(of: layer, windowLayers: layers(of: windows))
    }

    /// The same, with the windows' layers as `layers(of:)` gives them, for a caller that looks
    /// up many layers in the same windows.
    static func ancestors(of layer: CALayer, windowLayers: Set<ObjectIdentifier>) -> [CALayer]? {
        var chain: [CALayer] = []
        var current = layer
        while !windowLayers.contains(ObjectIdentifier(current)) {
            guard let parent = current.superlayer else { return nil }
            chain.append(parent)
            current = parent
        }
        return chain.reversed()
    }

    /// The layers of `windows`, as `ancestors(of:windowLayers:)` takes them.
    static func layers(of windows: [UIWindow]) -> Set<ObjectIdentifier> {
        Set(windows.map { ObjectIdentifier($0.layer) })
    }
}
#endif
