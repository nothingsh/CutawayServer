#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import UIKit

/// The two names the hierarchy gives for a class.
enum ClassNames {
    /// The name the runtime knows the class by: `Demo.CardView`, or a mangled name such as
    /// `_TtCC4Demo5Outer5Inner` for classes that are private, nested or generic.
    static func runtimeName(of type: AnyClass) -> String {
        NSStringFromClass(type)
    }

    /// The name as written in source, without the module and without mangling: `CardView`,
    /// `Inner`, `Cell<Int>`. For Objective-C classes it is the runtime name.
    static func displayName(of type: AnyClass) -> String {
        String(describing: type)
    }

    /// Both names of each class met in one capture, worked out once per class: a hierarchy
    /// has many layers of few classes.
    struct Cache {
        private var names: [ObjectIdentifier: (runtime: String, display: String)] = [:]

        mutating func names(of type: AnyClass) -> (runtime: String, display: String) {
            let key = ObjectIdentifier(type)
            if let known = names[key] { return known }
            let found = (ClassNames.runtimeName(of: type), ClassNames.displayName(of: type))
            names[key] = found
            return found
        }
    }
}

/// How layers, views, view controllers and windows relate. Only reads.
@MainActor
enum LayerTopology {
    /// P-HIER-04: a layer backs a view when the view is its delegate and it is the view's layer.
    static func backingView(of layer: CALayer) -> UIView? {
        guard let view = layer.delegate as? UIView, view.layer === layer else { return nil }
        return view
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
        let windowLayers = Set(windows.map { ObjectIdentifier($0.layer) })
        var chain: [CALayer] = []
        var current = layer
        while !windowLayers.contains(ObjectIdentifier(current)) {
            guard let parent = current.superlayer else { return nil }
            chain.append(parent)
            current = parent
        }
        return chain.reversed()
    }
}
#endif
