#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// What reading attributes needs beyond the layer: the connection's IDs and the app's windows,
/// for the attributes that refer to other objects (PROTOCOL.md, P-ATTR-18). Reading gives the
/// layers it refers to their IDs and changes nothing else.
@MainActor
struct AttributeReading {
    let registry: LayerRegistry
    /// The app's windows; a layer in none of them does not exist (P-HIER-12).
    let windows: [UIWindow]

    /// P-ATTR-18: a view by the layer that backs it, a view controller by its root view's layer
    /// when the view is loaded (`viewIfLoaded` never loads it); 0 when that layer is in none of
    /// the windows, and for any other object. The names are the object's own, by the rules of
    /// hierarchy nodes.
    func reference(to object: AnyObject) -> ObjectReference {
        let type: AnyClass = Swift.type(of: object)
        let layer: CALayer?
        if let view = object as? UIView {
            layer = view.layer
        } else if let controller = object as? UIViewController {
            layer = controller.viewIfLoaded?.layer
        } else {
            layer = nil
        }
        var layerID: UInt64 = 0
        if let layer, LayerTopology.ancestors(of: layer, in: windows) != nil {
            layerID = registry.register(layer)
        }
        return ObjectReference(
            layerID: layerID,
            className: ClassNames.runtimeName(of: type),
            displayClassName: ClassNames.displayName(of: type)
        )
    }
}
#endif
