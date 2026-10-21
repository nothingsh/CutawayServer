#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import QuartzCore

/// The virtual nodes the host app gives for a layer (PROTOCOL.md, P-HIER-19 to 22), as the
/// hierarchy has them and as a request finds one again by its ID.
@MainActor
enum VirtualNodes {
    /// One node of a layer's virtual tree, in pre-order.
    struct Entry {
        let node: CutawayServer.VirtualNode
        /// The index of the parent entry; `nil` for a child of the layer.
        let parent: Int?
    }

    /// One virtual node found by its ID, with what its answers need.
    struct Found {
        /// Its nearest layer ancestor, and that layer's ID.
        let layer: CALayer
        let layerID: UInt64
        /// The layer's virtual tree, and the node's index in it.
        let entries: [Entry]
        let index: Int
        /// The layer or one of its ancestors is excluded from images (P-DET-10).
        let isExcluded: Bool

        var node: CutawayServer.VirtualNode { entries[index].node }

        /// The indices of the node and of its descendants, in pre-order.
        var subtree: [Int] {
            var indices = [index]
            var inside: Set<Int> = [index]
            for next in entries.indices.dropFirst(index + 1) {
                guard let parent = entries[next].parent, inside.contains(parent) else { break }
                inside.insert(next)
                indices.append(next)
            }
            return indices
        }
    }

    /// The tree in pre-order, each identity once: a node that repeats an identity seen before
    /// is left out with its subtree (P-HIER-19). Deep trees do not grow the call stack.
    static func entries(of roots: [CutawayServer.VirtualNode]) -> [Entry] {
        var entries: [Entry] = []
        var seen = Set<AnyHashable>()
        var stack: [(node: CutawayServer.VirtualNode, parent: Int?)] = roots.reversed().map { ($0, nil) }
        while let (node, parent) = stack.popLast() {
            guard seen.insert(node.identity).inserted else { continue }
            entries.append(Entry(node: node, parent: parent))
            let index = entries.count - 1
            stack += node.children.reversed().map { ($0, index) }
        }
        return entries
    }

    /// The hierarchy nodes of `entries`, which are the virtual tree of the layer `layerID`.
    static func nodes(
        of entries: [Entry],
        indices: [Int]? = nil,
        under layerID: UInt64,
        isExcluded: Bool,
        registry: LayerRegistry
    ) -> [LayerNode] {
        let ids = entries.map { registry.register(virtual: $0.node.identity, under: layerID) }
        return (indices ?? Array(entries.indices)).map { index in
            let entry = entries[index]
            return node(
                for: entry.node,
                id: ids[index],
                parentID: entry.parent.map { ids[$0] } ?? layerID,
                isExcluded: isExcluded
            )
        }
    }

    /// P-HIER-20: the rectangle's size at origin 0, centered on the rectangle; the rest as a
    /// plain layer has it, or as the host app gives it.
    static func node(
        for virtual: CutawayServer.VirtualNode,
        id: UInt64,
        parentID: UInt64,
        isExcluded: Bool
    ) -> LayerNode {
        let frame = virtual.frame.standardized
        return LayerNode(
            id: id,
            parentID: parentID,
            className: virtual.className,
            displayClassName: virtual.displayClassName,
            bounds: WireGeometry.rect(CGRect(origin: .zero, size: frame.size)),
            position: WireGeometry.point(CGPoint(x: frame.midX, y: frame.midY)),
            transform: WireGeometry.transform(CATransform3DMakeAffineTransform(virtual.transform)),
            isHidden: virtual.isHidden,
            opacity: WireGeometry.finite(virtual.opacity),
            layerClassOrigin: .app,
            nodeKind: .virtual,
            name: virtual.name,
            isCollapsedByDefault: virtual.isCollapsedByDefault,
            isCaptureExcluded: isExcluded
        )
    }

    /// The virtual trees one request found, by the ID of their layer, so that the host app is
    /// asked once for each layer however many of its nodes the request names. Something
    /// registered meanwhile makes them stale.
    @MainActor
    final class Trees {
        private var revision: Int?
        private var entries: [UInt64: [Entry]] = [:]

        /// The tree of the layer `layerID`, worked out with `make` the first time.
        func entries(of layerID: UInt64, revision: Int, _ make: () -> [Entry]) -> [Entry] {
            if self.revision != revision {
                self.revision = revision
                entries = [:]
            }
            if let known = entries[layerID] { return known }
            let made = make()
            entries[layerID] = made
            return made
        }
    }

    /// The virtual node with this ID, if the host app still gives it now under a layer that
    /// exists (P-HIER-22); the walk is the hierarchy's, so a node the hierarchy left out is not
    /// found either.
    ///
    /// - Parameter trees: Where a request that finds several nodes keeps the trees it found
    ///   them in, so that "now" is when it first asked for the layer's; `nil` asks the host app
    ///   again, as a change does to answer with what it changed.
    static func find(_ id: UInt64, in context: RequestContext, trees: Trees? = nil) -> Found? {
        let registry = context.registry
        guard let key = registry.virtualNode(for: id),
              let layer = registry.layer(for: key.layerID),
              let ancestors = LayerTopology.ancestors(of: layer, in: context.windows) else {
            return nil
        }
        let lookup = context.extensions
        let resolved = lookup.resolve(layer, view: LayerTopology.backingView(of: layer))
        func ask() -> [Entry] { entries(of: resolved.virtualChildren()) }
        let tree = trees?.entries(of: key.layerID, revision: lookup.store.revision, ask) ?? ask()
        guard let index = tree.firstIndex(where: { $0.node.identity == key.identity }) else { return nil }
        let isExcluded = resolved.isExcludedFromCapture || isExcluded(ancestors, lookup: lookup)
        return Found(layer: layer, layerID: key.layerID, entries: tree, index: index, isExcluded: isExcluded)
    }

    /// Whether the host app excludes any of `layers` from images.
    static func isExcluded(_ layers: [CALayer], lookup: ExtensionLookup) -> Bool {
        layers.contains { lookup.resolve($0, view: LayerTopology.backingView(of: $0)).isExcludedFromCapture }
    }
}
#endif
