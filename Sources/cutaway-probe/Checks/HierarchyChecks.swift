import CutawayWire
import Foundation

/// What a `Hierarchy` has to look like. Every function throws a `ProbeFailure` naming the
/// first thing that is wrong.
enum HierarchyChecks {
    /// The response to `GetHierarchy`, from a server working at `version`.
    static func hierarchy(_ frame: Frame, version: ProtocolVersion = .current) throws -> Hierarchy {
        guard case .hierarchy(let hierarchy)? = frame.body else {
            throw ProbeFailure("expected Hierarchy, got \(Checks.describe(frame)) (P-HIER-01)")
        }
        try structure(hierarchy, version: version)
        return hierarchy
    }

    /// The response to `GetSubtree` for `rootID`, compared with a hierarchy read before it
    /// (P-HIER-10). Use it on a screen that did not change in between: it requires the
    /// subtree to be exactly that part of the hierarchy.
    static func subtree(_ frame: Frame, rootID: UInt64, hierarchy: Hierarchy) throws -> Hierarchy {
        guard case .hierarchy(let subtree)? = frame.body else {
            throw ProbeFailure("expected Hierarchy for GetSubtree, got \(Checks.describe(frame)) (P-HIER-10)")
        }
        guard let first = subtree.nodes.first, first.id == rootID else {
            throw ProbeFailure(
                "the subtree of \(rootID) begins with \(subtree.nodes.first.map { "node \($0.id)" } ?? "no node") (P-HIER-10)"
            )
        }
        guard let start = hierarchy.nodes.firstIndex(where: { $0.id == rootID }) else {
            throw ProbeFailure("the subtree's root \(rootID) is not in the hierarchy")
        }
        // The root and every following node whose parent is already in the part.
        var ids: Set<UInt64> = [rootID]
        var expected = [hierarchy.nodes[start]]
        for node in hierarchy.nodes[(start + 1)...] {
            guard ids.contains(node.parentID) else { break }
            ids.insert(node.id)
            expected.append(node)
        }
        for (index, (actual, wanted)) in zip(subtree.nodes, expected).enumerated() where actual != wanted {
            throw ProbeFailure(
                "the subtree of \(rootID) differs from the hierarchy at node \(index) (id \(actual.id), expected \(wanted.id)) (P-HIER-10)"
            )
        }
        guard subtree.nodes.count == expected.count else {
            throw ProbeFailure(
                "the subtree of \(rootID) has \(subtree.nodes.count) nodes, the hierarchy \(expected.count) (P-HIER-10)"
            )
        }
        guard subtree.keyWindowID == hierarchy.keyWindowID else {
            throw ProbeFailure(
                "the subtree's key_window_id is \(subtree.keyWindowID), the hierarchy's \(hierarchy.keyWindowID) (P-HIER-10)"
            )
        }
        return subtree
    }

    /// The checks that hold for every app, from a server working at `version`.
    static func structure(_ hierarchy: Hierarchy, version: ProtocolVersion = .current) throws {
        guard !hierarchy.nodes.isEmpty else {
            throw ProbeFailure("Hierarchy has no nodes: an active app shows at least one window")
        }
        var seen = Set<UInt64>()
        var roots = Set<UInt64>()
        // The IDs from the current root down to the node before this one.
        var ancestors: [UInt64] = []
        // The z_position of the last child seen of each parent.
        var lastZPosition: [UInt64: Double] = [:]
        for (index, node) in hierarchy.nodes.enumerated() {
            let name = "Hierarchy.nodes[\(index)]"
            guard node.id != 0 else { throw ProbeFailure("\(name) has id 0 (P-HIER-03)") }
            guard seen.insert(node.id).inserted else {
                throw ProbeFailure("\(name) repeats id \(node.id) (P-HIER-03)")
            }
            if node.parentID == 0 {
                roots.insert(node.id)
                ancestors = []
            } else {
                guard seen.contains(node.parentID), node.parentID != node.id else {
                    throw ProbeFailure(
                        "\(name) (id \(node.id)) comes before its parent \(node.parentID) (P-HIER-01)"
                    )
                }
                while let last = ancestors.last, last != node.parentID { ancestors.removeLast() }
                guard !ancestors.isEmpty else {
                    throw ProbeFailure(
                        "\(name) (id \(node.id)) is not in pre-order: its parent \(node.parentID) is not "
                            + "an ancestor of the node before it (P-HIER-01)"
                    )
                }
            }
            ancestors.append(node.id)

            try checkClassNames(of: node, name: name)
            try checkAddresses(of: node, name: name, version: version)
            try checkClassFacts(of: node, name: name, version: version)
            try checkMemberReferences(of: node, name: name)
            guard numbers(of: node).allSatisfy(\.isFinite) else {
                throw ProbeFailure("\(name) (id \(node.id)) has a number that is not finite (P-HIER-05)")
            }
            // Siblings back to front: z_position never goes down (P-HIER-01). Windows are ordered
            // by the window list instead (P-HIER-02).
            if node.parentID != 0 {
                if let previous = lastZPosition[node.parentID], node.zPosition < previous {
                    throw ProbeFailure(
                        "\(name) (id \(node.id)) has z_position \(node.zPosition), less than the \(previous) "
                            + "of the sibling before it: siblings must be in drawing order (P-HIER-01)"
                    )
                }
                lastZPosition[node.parentID] = node.zPosition
            }
        }
        guard hierarchy.keyWindowID == 0 || roots.contains(hierarchy.keyWindowID) else {
            throw ProbeFailure(
                "Hierarchy.key_window_id \(hierarchy.keyWindowID) is not the id of a root node"
            )
        }
    }

    /// P-HIER-14 (protocol 1.1): the layer's address always; the view's and the view
    /// controller's exactly when their class names are given. A 1.0 server sends none.
    private static func checkAddresses(of node: LayerNode, name: String, version: ProtocolVersion) throws {
        guard version.minor >= 1 else { return }
        let label = "\(name) (id \(node.id))"
        guard node.layerAddress != 0 else { throw ProbeFailure("\(label) has no layer_address (P-HIER-14)") }
        guard (node.viewAddress != nil) == (node.viewClassName != nil) else {
            throw ProbeFailure(
                "\(label) has \(node.viewAddress == nil ? "no " : "a ")view_address but "
                    + "\(node.viewClassName == nil ? "no " : "a ")view_class_name (P-HIER-14)"
            )
        }
        guard (node.viewControllerAddress != nil) == (node.viewControllerClassName != nil) else {
            throw ProbeFailure(
                "\(label) has \(node.viewControllerAddress == nil ? "no " : "a ")view_controller_address but "
                    + "\(node.viewControllerClassName == nil ? "no " : "a ")view_controller_class_name (P-HIER-14)"
            )
        }
    }

    /// P-HIER-16 to 18 (protocol 1.1): each origin, and the view controller's visibility, given
    /// exactly when its class name is, and then not `Unknown`; base classes only from the tables
    /// of the negotiated version, a view's only where there is a view.
    private static func checkClassFacts(of node: LayerNode, name: String, version: ProtocolVersion) throws {
        let label = "\(name) (id \(node.id))"
        let views = KnownClasses.names(of: KnownClasses.views, at: version)
        let layers = KnownClasses.names(of: KnownClasses.layers, at: version)
        if let base = node.viewBaseClassName {
            guard node.viewClassName != nil else {
                throw ProbeFailure("\(label) has view_base_class_name \(base) but backs no view (P-HIER-17)")
            }
            guard views.contains(base) else {
                throw ProbeFailure(
                    "\(label) has view_base_class_name \(base), which the view table of protocol 1.\(version.minor) does not have (P-HIER-17)"
                )
            }
        }
        if let base = node.layerBaseClassName, !layers.contains(base) {
            throw ProbeFailure(
                "\(label) has layer_base_class_name \(base), which the layer table of protocol 1.\(version.minor) does not have (P-HIER-17)"
            )
        }
        guard version.minor >= 1 else { return }
        let given: [(String, Bool, Bool)] = [
            ("layer_class_origin", node.layerClassOrigin != .unknown, true),
            ("view_class_origin", node.viewClassOrigin != .unknown, node.viewClassName != nil),
            (
                "view_controller_class_origin",
                node.viewControllerClassOrigin != .unknown,
                node.viewControllerClassName != nil
            ),
            (
                "view_controller_visibility",
                node.viewControllerVisibility != .unknown,
                node.viewControllerClassName != nil
            )
        ]
        for (field, isGiven, hasName) in given where isGiven != hasName {
            throw ProbeFailure(
                "\(label) has \(isGiven ? "a" : "no") \(field), but \(hasName ? "a" : "no") class name for it (P-HIER-16, 18)"
            )
        }
    }

    /// P-HIER-04, P-HIER-07: the class names of a node, of the view it backs, and of the view
    /// controller whose root view that is.
    private static func checkClassNames(of node: LayerNode, name: String) throws {
        guard !node.className.isEmpty, !node.displayClassName.isEmpty else {
            throw ProbeFailure("\(name) (id \(node.id)) has an empty class name")
        }
        switch (node.viewClassName, node.viewDisplayClassName) {
        case (nil, nil):
            break
        case let (runtimeName?, displayName?) where !runtimeName.isEmpty && !displayName.isEmpty:
            break
        default:
            throw ProbeFailure(
                "\(name) (id \(node.id)) must have both view class names, not empty, or neither (P-HIER-04)"
            )
        }
        switch (node.viewControllerClassName, node.viewControllerDisplayClassName) {
        case (nil, nil):
            break
        case let (runtimeName?, displayName?) where !runtimeName.isEmpty && !displayName.isEmpty:
            guard node.viewClassName != nil else {
                throw ProbeFailure(
                    "\(name) (id \(node.id)) names a view controller but backs no view (P-HIER-07)"
                )
            }
        default:
            throw ProbeFailure(
                "\(name) (id \(node.id)) must have both view controller class names, not empty, or neither (P-HIER-07)"
            )
        }
    }

    /// P-HIER-09: the names of the variables that hold a node.
    private static func checkMemberReferences(of node: LayerNode, name: String) throws {
        for (referenceIndex, reference) in node.memberReferences.enumerated()
            where reference.ownerClassName.isEmpty || reference.ownerDisplayClassName.isEmpty
            || reference.name.isEmpty {
            throw ProbeFailure(
                "\(name) (id \(node.id)) member_references[\(referenceIndex)] has an empty field (P-HIER-09)"
            )
        }
        for (referenceIndex, reference) in node.memberReferences.enumerated()
            where reference.name.contains("$__lazy_storage_$_") {
            throw ProbeFailure(
                "\(name) (id \(node.id)) member_references[\(referenceIndex)] is named \(reference.name): "
                    + "the prefix of a lazy property's storage must be left out (P-HIER-09)"
            )
        }
    }

    private static func numbers(of node: LayerNode) -> [Double] {
        node.transform.components + [
            node.bounds.origin.x,
            node.bounds.origin.y,
            node.bounds.size.width,
            node.bounds.size.height,
            node.position.x,
            node.position.y,
            node.anchorPoint.x,
            node.anchorPoint.y,
            node.zPosition,
            Double(node.opacity)
        ]
    }
}
