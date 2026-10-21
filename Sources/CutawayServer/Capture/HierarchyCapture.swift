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
    /// The hierarchy of `context`'s windows, back to front, each window a root node. The
    /// negotiated version decides the tables of known classes (P-HIER-17), and from 1.2 on
    /// whether virtual nodes are sent (P-HIER-22).
    static func capture(_ context: RequestContext) -> Hierarchy {
        var walk = Walk(context)
        for window in context.windows {
            appendTree(of: window.layer, parentID: 0, isExcluded: false, registry: context.registry, to: &walk)
        }
        // P-HIER-08: with every tree read, so that each holder is seen with all it holds.
        return finish(walk, dropping: 0, context: context)
    }

    /// P-HIER-10: the node with this ID and all its descendants, exactly as `capture` gives
    /// them; `nil` when there is no such node in any of the windows (P-HIER-11, P-HIER-22).
    static func captureSubtree(rootID: UInt64, in context: RequestContext) -> Hierarchy? {
        let registry = context.registry
        guard let root = registry.layer(for: rootID) else {
            return virtualSubtree(rootID: rootID, in: context)
        }
        guard let ancestors = LayerTopology.ancestors(of: root, in: context.windows) else { return nil }
        // P-HIER-08: the holders are the views of the ancestors, and some of those lie above the
        // root. The chain of ancestors goes in front as nodes, each the parent of the next, so
        // that every one of them sees the whole subtree below it; their entries are dropped.
        // P-DET-10: an excluded ancestor excludes the subtree.
        var walk = Walk(context)
        var parentID: UInt64 = 0
        var isExcluded = false
        for ancestor in ancestors {
            let id = registry.register(ancestor)
            isExcluded = walk.append(ancestor, id: id, parentID: parentID, isExcluded: isExcluded, registry: nil)
            parentID = id
        }
        appendTree(of: root, parentID: parentID, isExcluded: isExcluded, registry: registry, to: &walk)
        return finish(walk, dropping: ancestors.count, context: context)
    }

    /// P-HIER-10, P-HIER-22: a virtual node and its virtual descendants; the first one's parent
    /// is its actual parent node. Virtual nodes have no member references, and no layers below.
    private static func virtualSubtree(rootID: UInt64, in context: RequestContext) -> Hierarchy? {
        guard !context.extensions.isEmpty, let found = VirtualNodes.find(rootID, in: context) else { return nil }
        let nodes = VirtualNodes.nodes(
            of: found.entries,
            indices: found.subtree,
            under: found.layerID,
            isExcluded: found.isExcluded,
            registry: context.registry
        )
        context.registry.removeReleased()
        return Hierarchy(nodes: nodes, keyWindowID: keyWindowID(in: context))
    }

    /// What one capture gathers on its way through the trees.
    private struct Walk {
        /// The layers' nodes; the virtual nodes are apart, so that the arrays below stay parallel.
        var nodes: [LayerNode] = []
        /// The virtual nodes that follow the layer node at each index (P-HIER-21).
        var virtualNodes: [Int: [LayerNode]] = [:]
        /// For the member references: the layer of each node, the view it backs and that
        /// view's controller, at the same index.
        var layers: [CALayer] = []
        var views: [UIView?] = []
        var controllers: [UIViewController?] = []
        var classNames = ClassNames.Cache()
        var classFacts: ClassFactsCache
        var visibility = ControllerVisibility()
        /// `nil` when the host app registered nothing.
        let lookup: ExtensionLookup?
        /// P-HIER-22: virtual nodes only for a client of 1.2 or later.
        let sendsVirtualNodes: Bool

        @MainActor
        init(_ context: RequestContext) {
            let version = context.version
            classFacts = ClassFactsCache(version: version)
            sendsVirtualNodes = version.supportsVirtualNodes
            lookup = context.extensions.isEmpty ? nil : context.extensions
        }

        /// Appends the layer's node, and its virtual nodes with `registry`; returns whether the
        /// layer is excluded from images, which its subtree inherits (P-DET-10).
        @MainActor
        mutating func append(
            _ layer: CALayer,
            id: UInt64,
            parentID: UInt64,
            isExcluded inherited: Bool,
            registry: LayerRegistry?
        ) -> Bool {
            let view = LayerTopology.backingView(of: layer)
            let controller = view.flatMap(LayerTopology.controller(ofRootView:))
            var node = HierarchyCapture.node(
                for: layer,
                id: id,
                parentID: parentID,
                view: view,
                controller: controller,
                walk: &self
            )
            let resolved = lookup?.resolve(layer, view: view)
            let isExcluded = inherited || resolved?.isExcludedFromCapture == true
            node.isCaptureExcluded = isExcluded
            node.isCollapsedByDefault = resolved?.isCollapsedByDefault == true
            nodes.append(node)
            layers.append(layer)
            views.append(view)
            controllers.append(controller)
            if sendsVirtualNodes, let registry, let resolved, resolved.virtualSource != nil {
                let entries = VirtualNodes.entries(of: resolved.virtualChildren())
                if !entries.isEmpty {
                    virtualNodes[nodes.count - 1] = VirtualNodes.nodes(
                        of: entries,
                        under: id,
                        isExcluded: isExcluded,
                        registry: registry
                    )
                }
            }
            return isExcluded
        }
    }

    /// Adds the member references, forgets released objects, and leaves out the first
    /// `dropping` nodes.
    private static func finish(_ walk: consuming Walk, dropping: Int, context: RequestContext) -> Hierarchy {
        let registry = context.registry
        let references = MemberScan.references(
            nodes: walk.nodes,
            layers: walk.layers,
            views: walk.views,
            controllers: walk.controllers,
            classNames: &walk.classNames
        )
        for index in walk.nodes.indices { walk.nodes[index].memberReferences = references[index] }
        registry.removeReleased()
        let keyWindow = keyWindowID(in: context)
        // Most often the nodes are the answer as they are: taken over, not copied.
        guard dropping > 0 || !walk.virtualNodes.isEmpty else {
            return Hierarchy(nodes: walk.nodes, keyWindowID: keyWindow)
        }
        var nodes: [LayerNode] = []
        nodes.reserveCapacity(walk.nodes.count - dropping + walk.virtualNodes.values.reduce(0) { $0 + $1.count })
        for index in walk.nodes.indices.dropFirst(dropping) {
            nodes.append(walk.nodes[index])
            nodes += walk.virtualNodes[index] ?? []
        }
        return Hierarchy(nodes: nodes, keyWindowID: keyWindow)
    }

    /// Appends `layer` and its descendants in pre-order without recursion: the stack holds the
    /// layers still to visit, the next one on top. Deep trees do not grow the call stack.
    private static func appendTree(
        of layer: CALayer,
        parentID: UInt64,
        isExcluded: Bool,
        registry: LayerRegistry,
        to walk: inout Walk
    ) {
        var stack: [(layer: CALayer, parentID: UInt64, isExcluded: Bool)] = [(layer, parentID, isExcluded)]
        while let (layer, parentID, inherited) = stack.popLast() {
            let id = registry.register(layer)
            let isExcluded = walk.append(layer, id: id, parentID: parentID, isExcluded: inherited, registry: registry)
            if let sublayers = layer.sublayers {
                // Reversed, so that the first in drawing order is popped first.
                for sublayer in drawingOrder(sublayers).reversed() {
                    stack.append((sublayer, id, isExcluded))
                }
            }
        }
    }

    /// The root node of the frontmost key window; 0 when no window is key.
    private static func keyWindowID(in context: RequestContext) -> UInt64 {
        guard let window = context.windows.last(where: \.isKeyWindow) else { return 0 }
        return context.registry.register(window.layer)
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
        walk: inout Walk
    ) -> LayerNode {
        let layerType: AnyClass = type(of: layer)
        let viewType: AnyClass? = view.map { type(of: $0) }
        let controllerType: AnyClass? = controller.map { type(of: $0) }
        let layerNames = walk.classNames.names(of: layerType)
        let viewNames = viewType.map { walk.classNames.names(of: $0) }
        let controllerNames = controllerType.map { walk.classNames.names(of: $0) }
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
            viewControllerDisplayClassName: controllerNames?.display,
            // P-HIER-14: of the objects the names come from, so given exactly when they are.
            layerAddress: address(of: layer),
            viewAddress: view.map(address(of:)),
            viewControllerAddress: controller.map(address(of:)),
            // P-HIER-16 to 18: each given exactly when its class name is.
            layerClassOrigin: walk.classFacts.origin(of: layerType),
            viewClassOrigin: viewType.map { walk.classFacts.origin(of: $0) } ?? .unknown,
            viewControllerClassOrigin: controllerType.map { walk.classFacts.origin(of: $0) } ?? .unknown,
            layerBaseClassName: walk.classFacts.layerBaseName(of: layerType),
            viewBaseClassName: viewType.flatMap { walk.classFacts.viewBaseName(of: $0) },
            viewControllerVisibility: controller.map { walk.visibility.visibility(of: $0) } ?? .unknown
        )
    }

    /// Where the object lies in the app's memory, for display only (P-HIER-15). Neither retains
    /// the object nor reads anything of it.
    private static func address(of object: AnyObject) -> UInt64 {
        UInt64(UInt(bitPattern: ObjectIdentifier(object)))
    }
}
#endif
