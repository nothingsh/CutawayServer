import CutawayWire
import Foundation

/// The demo app's screen as the hierarchy shows it (Demo/CutawayDemo/DemoViewController.swift),
/// each thing found once. What the demo's code holds in a variable is found by that variable,
/// the first member reference of its node (P-HIER-08); the rest is found by where it is. The
/// checks of `--expect-demo` take their nodes from here.
struct DemoScene {
    static let module = "CutawayDemo"
    static let controller = "DemoViewController"

    /// The root layer of the key window.
    let window: LayerNode
    /// The root view of DemoViewController.
    let screen: LayerNode
    let titleLabel: LayerNode
    let card: LayerNode
    /// The shape layer in the card.
    let badge: LayerNode
    let scrollView: LayerNode
    /// The label inside the scroll view.
    let scrolledLabel: LayerNode
    let bareLayer: LayerNode
    let emptyView: LayerNode
    let depthView: LayerNode
    /// The sublayers of `depthView`, in the hierarchy's order.
    let blocks: [LayerNode]
    /// The root view of the navigation controller, and of the controller inside it.
    let navigation: LayerNode
    let detail: LayerNode
    let pushStack: LayerNode
    let pushLabel: LayerNode
    let pushedView: LayerNode
    let plainView: LayerNode
    let layoutLabel: LayerNode
    let autoresizingBox: LayerNode
    let autoresizedDot: LayerNode

    init(_ hierarchy: Hierarchy) throws {
        let nodes = hierarchy.nodes
        guard hierarchy.keyWindowID != 0, let window = nodes.first(where: { $0.id == hierarchy.keyWindowID })
        else { throw ProbeFailure("demo: Hierarchy.key_window_id is 0; the demo app has a key window") }
        self.window = window
        let screen = try Self.one("the root view of \(Self.module).\(Self.controller)", in: nodes) {
            $0.viewControllerClassName == "\(Self.module).\(Self.controller)"
        }
        self.screen = screen
        titleLabel = try Self.held("titleLabel", in: nodes)
        card = try Self.held("cardView", in: nodes)
        badge = try Self.held("badge", by: "CardView", in: nodes)
        let scrollView = try Self.held("scrollView", in: nodes)
        self.scrollView = scrollView
        scrolledLabel = try Self.one("a UILabel in scrollView", in: Self.children(of: scrollView, in: nodes)) {
            $0.viewClassName == "UILabel"
        }
        bareLayer = try Self.held("bareLayer", in: nodes)
        emptyView = try Self.held("emptyView", in: nodes)
        let depthView = try Self.held("depthView", in: nodes)
        self.depthView = depthView
        blocks = Self.children(of: depthView, in: nodes)
        let navigation = try Self.one(
            "the root view of a UINavigationController on the screen's view",
            in: Self.children(of: screen, in: nodes)
        ) { $0.viewControllerClassName == "UINavigationController" }
        self.navigation = navigation
        detail = try Self.one(
            "the root view of \(Self.module).DemoDetailViewController inside the navigation controller",
            in: Self.descendants(of: navigation, in: nodes)
        ) { $0.viewControllerClassName == "\(Self.module).DemoDetailViewController" }
        pushStack = try Self.held("pushStack", in: nodes)
        pushLabel = try Self.held("pushLabel", in: nodes)
        pushedView = try Self.held("pushedView", in: nodes)
        plainView = try Self.held("plainView", in: nodes)
        layoutLabel = try Self.held("layoutLabel", in: nodes)
        autoresizingBox = try Self.held("autoresizingBox", in: nodes)
        autoresizedDot = try Self.held("autoresizedDot", in: nodes)
        try Self.checkOrder(of: screenSubviews, on: screen, in: nodes)
    }

    /// What the demo adds to the screen's view, in the order it adds them; the hierarchy lists
    /// them in that order (P-HIER-01).
    var screenSubviews: [(what: String, node: LayerNode)] {
        [
            ("titleLabel", titleLabel),
            ("cardView", card),
            ("scrollView", scrollView),
            ("bareLayer", bareLayer),
            ("emptyView", emptyView),
            ("depthView", depthView),
            ("the navigation controller's view", navigation),
            ("pushStack", pushStack),
            ("plainView", plainView),
            ("layoutLabel", layoutLabel),
            ("autoresizingBox", autoresizingBox)
        ]
    }

    // MARK: - Finding

    /// The reference the demo's code holds a node with: the variable `name` of `owner`.
    static func reference(_ name: String, owner: String = controller) -> MemberReference {
        MemberReference(ownerClassName: "\(module).\(owner)", ownerDisplayClassName: owner, name: name)
    }

    /// The one node whose first member reference is the variable `name` of `owner`
    /// (P-HIER-08). Only the first is looked at: UIKit's own variables may add references
    /// from holders further up.
    static func held(_ name: String, by owner: String = controller, in nodes: [LayerNode]) throws -> LayerNode {
        let reference = reference(name, owner: owner)
        let found = nodes.filter { $0.memberReferences.first == reference }
        guard found.count == 1, let node = found.first else {
            throw ProbeFailure(
                "demo: expected one node whose first member reference is \(reference.ownerClassName) / "
                    + "\(reference.ownerDisplayClassName) / \(reference.name), found \(found.count) (P-HIER-08)"
            )
        }
        return node
    }

    /// The one node of `nodes` that `matches`.
    static func one(_ what: String, in nodes: [LayerNode], matches: (LayerNode) -> Bool) throws -> LayerNode {
        let found = nodes.filter(matches)
        guard found.count == 1, let node = found.first else {
            throw ProbeFailure("demo: expected \(what), found \(found.count)")
        }
        return node
    }

    static func children(of node: LayerNode, in nodes: [LayerNode]) -> [LayerNode] {
        nodes.filter { $0.parentID == node.id }
    }

    static func descendants(of node: LayerNode, in nodes: [LayerNode]) -> [LayerNode] {
        children(of: node, in: nodes).flatMap { [$0] + descendants(of: $0, in: nodes) }
    }

    /// Every one of `subviews` lies on `screen`, in the order given.
    private static func checkOrder(
        of subviews: [(what: String, node: LayerNode)],
        on screen: LayerNode,
        in nodes: [LayerNode]
    ) throws {
        var indexOfID: [UInt64: Int] = [:]
        for (index, node) in nodes.enumerated() { indexOfID[node.id] = index }
        var previous: (what: String, index: Int)?
        for (what, node) in subviews {
            guard node.parentID == screen.id else {
                throw ProbeFailure("demo: \(what) is not on the screen's view")
            }
            let index = indexOfID[node.id] ?? -1
            if let previous, index < previous.index {
                throw ProbeFailure(
                    "demo: on the screen's view, \(what) comes before \(previous.what); the demo adds them in the "
                        + "other order, and the hierarchy lists subviews in that order (P-HIER-01)"
                )
            }
            previous = (what, index)
        }
    }
}
