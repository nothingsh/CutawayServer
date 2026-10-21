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
