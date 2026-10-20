import CutawayWire
import Foundation

/// The demo app's Extensions page as the hierarchy shows it
/// (Demo/CutawayDemo/DemoExtensionsViewController.swift): what the page's code holds in a
/// variable, found by that variable (P-HIER-08), and the chart's virtual nodes. `--expect-demo`
/// checks it instead of the main screen when it is open.
struct DemoExtensionsScene {
    static let controller = "DemoExtensionsViewController"
    /// The registered color the chart's bars and the swatch have.
    static let brandBlue = "brandBlue"

    /// The root view of DemoExtensionsViewController.
    let page: LayerNode
    let closeButton: LayerNode
    let chart: LayerNode
    let cardNumber: LayerNode
    let brandSwatch: LayerNode
    /// The chart's bars, in order: North, South, East.
    let bars: [LayerNode]
    /// The segments of each bar, in order.
    let segments: [[LayerNode]]

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
        chart = try held("salesChart")
        cardNumber = try held("cardNumber")
        brandSwatch = try held("brandSwatch")
        for (what, node) in [
            ("closeButton", closeButton),
            ("salesChart", chart),
            ("cardNumber", cardNumber),
            ("brandSwatch", brandSwatch)
        ] where node.parentID != page.id {
            throw ProbeFailure("demo: \(what) is not on the Extensions page's view")
        }
        bars = DemoScene.children(of: chart, in: nodes).filter { $0.nodeKind == .virtual }
        segments = bars.map { DemoScene.children(of: $0, in: nodes) }
    }
}
