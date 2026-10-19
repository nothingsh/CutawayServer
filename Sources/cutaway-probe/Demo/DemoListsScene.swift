import CutawayWire
import Foundation

/// The demo app's Lists page as the hierarchy shows it
/// (Demo/CutawayDemo/DemoListsViewController.swift): what the page's code holds in a variable,
/// found by that variable (P-HIER-08). `--expect-demo` checks it instead of the main screen
/// when it is open.
struct DemoListsScene {
    static let controller = "DemoListsViewController"

    /// The root view of DemoListsViewController.
    let page: LayerNode
    let closeButton: LayerNode
    let table: LayerNode
    let collection: LayerNode
    let stack: LayerNode
    /// The arranged subviews of `stack`, in order.
    let arranged: [LayerNode]
    let symbol: LayerNode
    let dynamicLabel: LayerNode
    let truncatedLabel: LayerNode

    /// Whether the page is open: its controller's root view is in the hierarchy.
    static func isShown(in hierarchy: Hierarchy) -> Bool {
        hierarchy.nodes.contains { $0.viewControllerClassName == "\(DemoScene.module).\(controller)" }
    }

    init(_ hierarchy: Hierarchy) throws {
        let nodes = hierarchy.nodes
        page = try DemoScene.one("the root view of \(DemoScene.module).\(Self.controller)", in: nodes) {
            $0.viewControllerClassName == "\(DemoScene.module).\(Self.controller)"
        }
        func held(_ name: String) throws -> LayerNode {
            try DemoScene.held(name, by: Self.controller, in: nodes)
        }
        closeButton = try held("closeButton")
        table = try held("listsTable")
        collection = try held("listsCollection")
        stack = try held("spacedStack")
        symbol = try held("symbolView")
        dynamicLabel = try held("dynamicLabel")
        truncatedLabel = try held("truncatedLabel")
        arranged = DemoScene.children(of: stack, in: nodes)
        for (what, node) in [
            ("closeButton", closeButton),
            ("listsTable", table),
            ("listsCollection", collection),
            ("spacedStack", stack),
            ("symbolView", symbol),
            ("dynamicLabel", dynamicLabel),
            ("truncatedLabel", truncatedLabel)
        ] where node.parentID != page.id {
            throw ProbeFailure("demo: \(what) is not on the Lists page's view")
        }
    }
}
