#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Reads the layer trees of windows into a `Hierarchy`.
///
/// It only reads: no layout is forced, nothing is marked for display, no presentation layer
/// is asked for. The whole tree is read in one go on the main thread, so that it is the tree
/// of one moment.
@MainActor
enum HierarchyCapture {
    /// - Parameter windows: back to front; each becomes a root node.
    static func capture(windows: [UIWindow], registry: LayerRegistry) -> Hierarchy {
        var walk = Walk()
        for window in windows {
            appendTree(of: window.layer, parentID: 0, registry: registry, to: &walk)
        }
        // P-HIER-08: with every tree read, so that each holder is seen with all it holds.
        return finish(walk, dropping: 0, windows: windows, registry: registry)
    }

    /// P-HIER-10: the layer with this ID and all its descendants, exactly as `capture` gives
    /// them; `nil` when there is no such layer in any of the windows (P-HIER-11).
    static func captureSubtree(
        rootID: UInt64,
        windows: [UIWindow],
        registry: LayerRegistry
    ) -> Hierarchy? {
        guard let root = registry.layer(for: rootID),
              let ancestors = LayerTopology.ancestors(of: root, in: windows) else {
            return nil
        }
        // P-HIER-08: the holders are the views of the ancestors, and some of those lie above the
        // root. The chain of ancestors goes in front as nodes, each the parent of the next, so
        // that every one of them sees the whole subtree below it; their entries are dropped.
        var walk = Walk()
        var parentID: UInt64 = 0
        for ancestor in ancestors {
            let id = registry.register(ancestor)
            walk.append(ancestor, id: id, parentID: parentID)
            parentID = id
        }
        appendTree(of: root, parentID: parentID, registry: registry, to: &walk)
        return finish(walk, dropping: ancestors.count, windows: windows, registry: registry)
    }

    /// What one capture gathers on its way through the trees.
    private struct Walk {
        var nodes: [LayerNode] = []
        /// For the member references: the layer of each node, the view it backs and that
        /// view's controller, at the same index.
        var layers: [CALayer] = []
        var views: [UIView?] = []
        var controllers: [UIViewController?] = []
        var classNames = ClassNames.Cache()

        @MainActor
        mutating func append(_ layer: CALayer, id: UInt64, parentID: UInt64) {
            let view = LayerTopology.backingView(of: layer)
            let controller = view.flatMap(LayerTopology.controller(ofRootView:))
            nodes.append(
                HierarchyCapture.node(
                    for: layer,
                    id: id,
                    parentID: parentID,
                    view: view,
                    controller: controller,
                    classNames: &classNames
                )
            )
            layers.append(layer)
            views.append(view)
            controllers.append(controller)
        }
    }

    /// Adds the member references, forgets released objects, and leaves out the first
    /// `dropping` nodes.
    private static func finish(
        _ walk: consuming Walk,
        dropping: Int,
        windows: [UIWindow],
        registry: LayerRegistry
    ) -> Hierarchy {
        let references = MemberScan.references(
            nodes: walk.nodes,
            layers: walk.layers,
            views: walk.views,
            controllers: walk.controllers,
            classNames: &walk.classNames
        )
        for index in walk.nodes.indices { walk.nodes[index].memberReferences = references[index] }
        registry.removeReleased()
        return Hierarchy(
            nodes: Array(walk.nodes.dropFirst(dropping)),
            keyWindowID: keyWindowID(windows: windows, registry: registry)
        )
    }

    /// Appends `layer` and its descendants in pre-order without recursion: the stack holds the
    /// layers still to visit, the next one on top. Deep trees do not grow the call stack.
    private static func appendTree(
        of layer: CALayer,
        parentID: UInt64,
        registry: LayerRegistry,
        to walk: inout Walk
    ) {
        var stack: [(layer: CALayer, parentID: UInt64)] = [(layer, parentID)]
        while let (layer, parentID) = stack.popLast() {
            let id = registry.register(layer)
            walk.append(layer, id: id, parentID: parentID)
            if let sublayers = layer.sublayers {
                // Reversed, so that the first in drawing order is popped first.
                for sublayer in drawingOrder(sublayers).reversed() {
                    stack.append((sublayer, id))
                }
            }
        }
    }

    /// The root node of the frontmost key window; 0 when no window is key.
    private static func keyWindowID(windows: [UIWindow], registry: LayerRegistry) -> UInt64 {
        guard let window = windows.last(where: \.isKeyWindow) else { return 0 }
        return registry.register(window.layer)
    }

    /// P-HIER-01: back to front, by `zPosition` as it is sent (P-HIER-05), then by the order
    /// in `sublayers`. The index takes part in the comparison, so the order does not depend on
    /// the sort being stable.
    static func drawingOrder(_ sublayers: [CALayer]) -> [CALayer] {
        // Most often every zPosition is 0: the order of `sublayers` already is the answer.
        if isInDrawingOrder(sublayers) { return sublayers }
        let zPositions = sublayers.map { WireGeometry.finite($0.zPosition) }
        let sorted = zPositions.indices.sorted { lhs, rhs in
            zPositions[lhs] != zPositions[rhs] ? zPositions[lhs] < zPositions[rhs] : lhs < rhs
        }
        return sorted.map { sublayers[$0] }
    }

    /// Whether no layer has a smaller `zPosition`, as sent, than the one before it. Allocates
    /// nothing.
    private static func isInDrawingOrder(_ sublayers: [CALayer]) -> Bool {
        guard var previous = sublayers.first.map({ WireGeometry.finite($0.zPosition) }) else { return true }
        for index in 1..<sublayers.count {
            let zPosition = WireGeometry.finite(sublayers[index].zPosition)
            if zPosition < previous { return false }
            previous = zPosition
        }
        return true
    }

    private static func node(
        for layer: CALayer,
        id: UInt64,
        parentID: UInt64,
        view: UIView?,
        controller: UIViewController?,
        classNames: inout ClassNames.Cache
    ) -> LayerNode {
        let layerNames = classNames.names(of: type(of: layer))
        let viewNames = view.map { classNames.names(of: type(of: $0)) }
        let controllerNames = controller.map { classNames.names(of: type(of: $0)) }
        return LayerNode(
            id: id,
            parentID: parentID,
            className: layerNames.runtime,
            displayClassName: layerNames.display,
            viewClassName: viewNames?.runtime,
            viewDisplayClassName: viewNames?.display,
            bounds: WireGeometry.rect(layer.bounds),
            position: WireGeometry.point(layer.position),
            anchorPoint: WireGeometry.point(layer.anchorPoint),
            transform: WireGeometry.transform(layer.transform),
            zPosition: WireGeometry.finite(layer.zPosition),
            isHidden: layer.isHidden,
            opacity: WireGeometry.finite(layer.opacity),
            masksToBounds: layer.masksToBounds,
            viewControllerClassName: controllerNames?.runtime,
            viewControllerDisplayClassName: controllerNames?.display
        )
    }
}
#endif
