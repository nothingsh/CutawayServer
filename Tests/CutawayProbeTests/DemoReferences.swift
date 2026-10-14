import CutawayWire

/// The member references a correct server reports first for the demo app's screen
/// (Demo/CutawayDemo/DemoViewController.swift, P-HIER-08).
enum DemoReferences {
    static func reference(_ name: String, owner: String = "DemoViewController") -> MemberReference {
        MemberReference(
            ownerClassName: "CutawayDemo.\(owner)",
            ownerDisplayClassName: owner,
            name: name
        )
    }

    /// The IDs of the nodes the demo's code holds a reference to.
    struct NodeIDs {
        var label: UInt64
        var card: UInt64
        var shape: UInt64
        var scrollView: UInt64
        var bareLayer: UInt64
        var emptyView: UInt64
        var depth: UInt64
        var pushStack: UInt64
        var pushLabel: UInt64
        var pushedView: UInt64
        var plainView: UInt64
        var layoutLabel: UInt64?
        var autoresizingBox: UInt64?
        var autoresizedDot: UInt64?
    }

    /// Gives the nodes with these IDs the references the demo's code holds them with.
    static func add(to hierarchy: inout Hierarchy, ids: NodeIDs) {
        var references: [UInt64: MemberReference] = [
            ids.label: reference("titleLabel"),
            ids.card: reference("cardView"),
            ids.shape: reference("badge", owner: "CardView"),
            ids.scrollView: reference("scrollView"),
            ids.bareLayer: reference("bareLayer"),
            ids.emptyView: reference("emptyView"),
            ids.depth: reference("depthView"),
            ids.pushStack: reference("pushStack"),
            ids.pushLabel: reference("pushLabel"),
            ids.pushedView: reference("pushedView"),
            ids.plainView: reference("plainView")
        ]
        // The layout corner.
        for (id, name) in [
            (ids.layoutLabel, "layoutLabel"),
            (ids.autoresizingBox, "autoresizingBox"),
            (ids.autoresizedDot, "autoresizedDot")
        ] {
            if let id { references[id] = reference(name) }
        }
        for index in hierarchy.nodes.indices {
            if let reference = references[hierarchy.nodes[index].id] {
                hierarchy.nodes[index].memberReferences = [reference]
            }
        }
    }
}

/// What a server of protocol 1.1 adds to the hierarchies the tests make up: addresses, and
/// the facts about classes.
enum Addresses {
    /// Gives every node a layer address, and a view's and a view controller's address exactly
    /// where it names their classes (P-HIER-14). Call it again after changing a hierarchy.
    static func add(to hierarchy: inout Hierarchy) {
        for index in hierarchy.nodes.indices {
            let id = hierarchy.nodes[index].id
            hierarchy.nodes[index].layerAddress = 0x6000_0000_0000 + 0x40 * id
            hierarchy.nodes[index].viewAddress = hierarchy.nodes[index].viewClassName.map { _ in
                0x1_0000_0000 + 0x200 * id
            }
            hierarchy.nodes[index].viewControllerAddress = hierarchy.nodes[index].viewControllerClassName.map { _ in
                0x1_1000_0000 + 0x200 * id
            }
            addClassFacts(to: &hierarchy.nodes[index])
        }
    }

    /// The origins (P-HIER-16), the base classes of the classes the tables name themselves
    /// (P-HIER-17), and the view controllers shown (P-HIER-18), exactly where the class names
    /// are given. The demo app's own classes are in its module.
    private static func addClassFacts(to node: inout LayerNode) {
        func origin(_ name: String) -> Origin {
            name.hasPrefix("CutawayDemo.") || name.hasPrefix("Demo.") ? .app : .system
        }
        let views = KnownClasses.names(of: KnownClasses.views, at: .current)
        let layers = KnownClasses.names(of: KnownClasses.layers, at: .current)
        node.layerClassOrigin = origin(node.className)
        node.viewClassOrigin = node.viewClassName.map(origin) ?? .unknown
        node.viewControllerClassOrigin = node.viewControllerClassName.map(origin) ?? .unknown
        node.viewControllerVisibility = node.viewControllerClassName == nil ? .unknown : .shown
        node.layerBaseClassName = layers.contains(node.className) ? node.className : nil
        node.viewBaseClassName = node.viewClassName.flatMap { views.contains($0) ? $0 : nil }
    }
}
