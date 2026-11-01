#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The state of the windows' layer trees as hierarchy change notifications compare it
/// (PROTOCOL.md, P-WATCH-03, P-WATCH-06, P-WATCH-07). Each layer has three signatures: its own
/// fields, its list of children, and its whole subtree; a comparison goes from each window's
/// root down and skips every subtree whose signature is the same. Only layers are read: the
/// host app is not asked for its virtual nodes, which a check would call at times it does not
/// expect (the explanation after P-WATCH-09). Main thread only.
@MainActor
enum HierarchySignature {
    struct Entry: Equatable, Sendable {
        var own: Int
        var children: Int
        var subtree: Int
        /// The children's IDs, back to front (P-HIER-01).
        var childIDs: [UInt64]
    }

    /// What one walk read, by layer ID; a baseline is pieced together from several
    /// (P-WATCH-06).
    struct Snapshot: Equatable, Sendable {
        var entries: [UInt64: Entry] = [:]
        /// The windows' root layers, back to front (P-HIER-02).
        var windowIDs: [UInt64] = []
        /// The root layer of the frontmost key window; 0 when none is.
        var keyWindowID: UInt64 = 0
    }

    /// Walks the windows' trees once. Layers that were never sent get their IDs here, so that a
    /// change under one can be reported (P-HIER-03: an ID is never given out again).
    static func snapshot(of windows: [UIWindow], registry: LayerRegistry) -> Snapshot {
        var snapshot = Snapshot()
        snapshot.entries = entries(below: windows.map(\.layer), registry: registry)
        snapshot.windowIDs = windows.map { registry.register($0.layer) }
        snapshot.keyWindowID = windows.last(where: \.isKeyWindow).map { registry.register($0.layer) } ?? 0
        return snapshot
    }

    /// The entries of `layer` and its descendants, as a `GetSubtree` that listed them told the
    /// client (P-WATCH-06).
    static func entries(ofSubtree layer: CALayer, registry: LayerRegistry) -> [UInt64: Entry] {
        entries(below: [layer], registry: registry)
    }

    /// Pre-order on the way down, without recursion; then backwards over the visited layers, so
    /// that every child is done before its parent.
    private static func entries(below roots: [CALayer], registry: LayerRegistry) -> [UInt64: Entry] {
        var visited: [(id: UInt64, own: Int, children: [CALayer])] = []
        var stack: [CALayer] = roots.reversed()
        while let layer = stack.popLast() {
            let children = layer.sublayers.map(HierarchyCapture.drawingOrder) ?? []
            visited.append((registry.register(layer), ownSignature(of: layer), children))
            stack.append(contentsOf: children.reversed())
        }
        var entries: [UInt64: Entry] = [:]
        entries.reserveCapacity(visited.count)
        for (id, own, children) in visited.reversed() {
            var childList = Hasher()
            var subtree = Hasher()
            var childIDs: [UInt64] = []
            childIDs.reserveCapacity(children.count)
            for child in children {
                let childID = registry.register(child)
                childIDs.append(childID)
                childList.combine(childID)
                childList.combine(WireGeometry.finite(child.zPosition))
                subtree.combine(entries[childID]?.subtree ?? 0)
            }
            let childSignature = childList.finalize()
            subtree.combine(own)
            subtree.combine(childSignature)
            entries[id] = Entry(own: own, children: childSignature, subtree: subtree.finalize(), childIDs: childIDs)
        }
        return entries
    }

    /// The class, the fields of P-WATCH-07 as they are sent (P-HIER-05), and what the layer's
    /// contents are: redrawing usually keeps the object, but another image is another one.
    private static func ownSignature(of layer: CALayer) -> Int {
        var hasher = Hasher()
        hasher.combine(ObjectIdentifier(type(of: layer)))
        let bounds = layer.bounds
        let position = layer.position
        let anchorPoint = layer.anchorPoint
        for value in [
            bounds.origin.x,
            bounds.origin.y,
            bounds.size.width,
            bounds.size.height,
            position.x,
            position.y,
            anchorPoint.x,
            anchorPoint.y
        ] {
            hasher.combine(WireGeometry.finite(value))
        }
        let transform = layer.transform
        for value in [
            transform.m11,
            transform.m12,
            transform.m13,
            transform.m14,
            transform.m21,
            transform.m22,
            transform.m23,
            transform.m24,
            transform.m31,
            transform.m32,
            transform.m33,
            transform.m34,
            transform.m41,
            transform.m42,
            transform.m43,
            transform.m44
        ] {
            hasher.combine(WireGeometry.finite(value))
        }
        hasher.combine(WireGeometry.finite(layer.zPosition))
        hasher.combine(layer.isHidden)
        hasher.combine(WireGeometry.finite(layer.opacity))
        hasher.combine(layer.masksToBounds)
        hasher.combine(layer.contents.map { ObjectIdentifier($0 as AnyObject) })
        return hasher.finalize()
    }

    /// What changed from `baseline` to `now`; `nil` when nothing did. The windows in
    /// `absorbing` are taken as told (P-WATCH-09) and not compared.
    ///
    /// A node whose own fields or list of children changed is a root and is not gone into
    /// further, so no root lies in another's subtree; a change of the list is so reported on
    /// the parent, and a change below a new node on the nearest node of the baseline above it
    /// (P-WATCH-03). Whatever the baseline cannot place is the whole.
    static func changes(from baseline: Snapshot, to now: Snapshot, absorbing: Set<UInt64> = []) -> HierarchyChanged? {
        guard baseline.windowIDs == now.windowIDs, baseline.keyWindowID == now.keyWindowID else {
            return .everything
        }
        var roots: [UInt64] = []
        var stack: [UInt64] = now.windowIDs.filter { !absorbing.contains($0) }.reversed()
        while let id = stack.popLast() {
            guard let old = baseline.entries[id], let new = now.entries[id] else { return .everything }
            if old.subtree == new.subtree { continue }
            if old.own != new.own || old.children != new.children || old.childIDs != new.childIDs {
                roots.append(id)
                continue
            }
            // Only the subtree signature is stale, as above the root of a `GetSubtree`: further
            // down.
            stack.append(contentsOf: new.childIDs.reversed())
        }
        return roots.isEmpty ? nil : HierarchyChanged(roots: roots, whole: false)
    }
}
#endif
