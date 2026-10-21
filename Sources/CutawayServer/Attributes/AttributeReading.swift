#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// What reading attributes needs beyond the layer: the connection's IDs and the app's windows,
/// for the attributes that refer to other objects (PROTOCOL.md, P-ATTR-18). Reading gives the
/// layers it refers to their IDs and changes nothing else.
///
/// It also keeps what one read of a layer works out for several of its attributes, so that it
/// is worked out once: `anew()` starts the next read, which may come after a change.
@MainActor
struct AttributeReading {
    let registry: LayerRegistry
    /// The app's windows; a layer in none of them does not exist (P-HIER-12).
    let windows: [UIWindow]
    /// The layers of `windows`, looked up for every object an attribute refers to.
    private let windowLayers: Set<ObjectIdentifier>
    private let memo = Memo()

    init(registry: LayerRegistry, windows: [UIWindow]) {
        self.init(registry: registry, windows: windows, windowLayers: LayerTopology.layers(of: windows))
    }

    private init(registry: LayerRegistry, windows: [UIWindow], windowLayers: Set<ObjectIdentifier>) {
        self.registry = registry
        self.windows = windows
        self.windowLayers = windowLayers
    }

    /// The same, for another read: nothing worked out before is kept.
    func anew() -> Self {
        Self(registry: registry, windows: windows, windowLayers: windowLayers)
    }

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
        if let layer, LayerTopology.ancestors(of: layer, windowLayers: windowLayers) != nil {
            layerID = registry.register(layer)
        }
        return ObjectReference(
            layerID: layerID,
            className: ClassNames.runtimeName(of: type),
            displayClassName: ClassNames.displayName(of: type)
        )
    }

    // MARK: - Worked out once in a read

    /// `AttributeTexts.lines(of:)`: TextKit lays the text out for it.
    func lines(of label: UILabel) -> (count: Int, truncated: Bool)? {
        let key = ObjectIdentifier(label)
        if let known = memo.lines[key] { return known }
        let lines = AttributeTexts.lines(of: label)
        memo.lines[key] = .some(lines)
        return lines
    }

    /// The rows of each section of `table`.
    func rowCounts(of table: UITableView) -> [Int] {
        let key = ObjectIdentifier(table)
        if let known = memo.rowCounts[key] { return known }
        let counts = (0..<table.numberOfSections).map(table.numberOfRows(inSection:))
        memo.rowCounts[key] = counts
        return counts
    }

    /// The items of each section of `collection`; `nil` while it needs layout, when they would
    /// ask its data source.
    func itemCounts(of collection: UICollectionView) -> [Int]? {
        let key = ObjectIdentifier(collection)
        if let known = memo.itemCounts[key] { return known }
        let counts = collection.layer.needsLayout()
            ? nil
            : (0..<collection.numberOfSections).map(collection.numberOfItems(inSection:))
        memo.itemCounts[key] = .some(counts)
        return counts
    }

    /// What one read worked out, by object.
    private final class Memo {
        var lines: [ObjectIdentifier: (count: Int, truncated: Bool)?] = [:]
        var rowCounts: [ObjectIdentifier: [Int]] = [:]
        var itemCounts: [ObjectIdentifier: [Int]?] = [:]
    }
}
#endif
