import CutawayWire
import Foundation

// The checks of `--expect-demo`: what the demo app's screen has to look like.
extension HierarchyChecks {
    /// What the demo app's screen has to contain (Demo/CutawayDemo/DemoViewController.swift).
    /// Call it after `structure`. The scene it returns is what the other demo checks work on.
    static func demoScene(_ hierarchy: Hierarchy) throws -> DemoScene {
        let scene = try DemoScene(hierarchy)
        try checkOneCard(in: hierarchy.nodes)
        for expected in expectations(of: scene) { try check(expected) }
        try checkCardRotation(scene.card)
        try checkContainers(of: scene, in: hierarchy.nodes)
        try checkDrawingOrder(of: scene.blocks)
        return scene
    }

    // MARK: - What each thing looks like

    /// The view a layer backs.
    private enum View {
        case unchecked
        /// The layer backs no view.
        case none
        /// The runtime name of the view's class.
        case named(String)
    }

    /// One thing of the demo's screen as its code makes it. A field that is `nil` is not checked.
    private struct Expected {
        var what: String
        var node: LayerNode
        var view: View = .unchecked
        var layerClass: String?
        var viewDisplayClass: String?
        var viewControllerClass: String?
        var viewControllerDisplayClass: String?
        var size: WireSize?
        var width: Double?
        var boundsOrigin: WirePoint?
        var anchorPoint: WirePoint?
        var masksToBounds: Bool?
        var isHidden: Bool?
        var opacity: Float?
    }

    private static func expectations(of scene: DemoScene) -> [Expected] {
        basics(of: scene) + corners(of: scene)
    }

    /// The window, the screen's view and the basic things on it.
    private static func basics(of scene: DemoScene) -> [Expected] {
        [
            Expected(what: "the key window", node: scene.window, view: .named("UIWindow")),
            Expected(
                what: "the screen's view",
                node: scene.screen,
                viewControllerClass: "\(DemoScene.module).\(DemoScene.controller)",
                viewControllerDisplayClass: DemoScene.controller
            ),
            Expected(
                what: "titleLabel",
                node: scene.titleLabel,
                view: .named("UILabel"),
                size: WireSize(width: 200, height: 24)
            ),
            Expected(
                what: "cardView",
                node: scene.card,
                view: .named("\(DemoScene.module).CardView"),
                viewDisplayClass: "CardView",
                size: WireSize(width: 300, height: 180),
                masksToBounds: true
            ),
            Expected(
                what: "badge",
                node: scene.badge,
                view: .none,
                layerClass: "CAShapeLayer",
                size: WireSize(width: 40, height: 40),
                isHidden: true,
                opacity: 0.5
            ),
            // Scrolled down by 100 points: the offset is the origin of the layer's bounds.
            Expected(
                what: "scrollView",
                node: scene.scrollView,
                view: .named("UIScrollView"),
                size: WireSize(width: 300, height: 200),
                boundsOrigin: WirePoint(x: 0, y: 100),
                masksToBounds: true
            ),
            Expected(
                what: "bareLayer",
                node: scene.bareLayer,
                view: .none,
                layerClass: "CALayer",
                size: WireSize(width: 60, height: 30),
                anchorPoint: WirePoint(x: 0, y: 0)
            ),
            Expected(
                what: "emptyView",
                node: scene.emptyView,
                view: .named("UIView"),
                size: WireSize(width: 0, height: 0)
            ),
            Expected(
                what: "depthView",
                node: scene.depthView,
                view: .named("UIView"),
                size: WireSize(width: 180, height: 40)
            )
        ]
    }

    /// The blocks, the child controllers, the editing corner and the layout corner.
    private static func corners(of scene: DemoScene) -> [Expected] {
        scene.blocks.enumerated().map { index, block in
            Expected(
                what: "block \(index) of depthView",
                node: block,
                view: .named("UIView"),
                size: WireSize(width: 80, height: 40)
            )
        } + [
            Expected(
                what: "the navigation controller's view",
                node: scene.navigation,
                viewControllerClass: "UINavigationController",
                viewControllerDisplayClass: "UINavigationController",
                size: WireSize(width: 260, height: 110)
            ),
            Expected(
                what: "the detail controller's view",
                node: scene.detail,
                viewControllerClass: "\(DemoScene.module).DemoDetailViewController",
                viewControllerDisplayClass: "DemoDetailViewController"
            ),
            Expected(what: "pushStack", node: scene.pushStack, view: .named("UIStackView"), width: 90),
            Expected(what: "pushLabel", node: scene.pushLabel, view: .named("UILabel")),
            Expected(
                what: "pushedView",
                node: scene.pushedView,
                view: .named("UIView"),
                size: WireSize(width: 90, height: 20)
            ),
            Expected(
                what: "plainView",
                node: scene.plainView,
                view: .named("UIView"),
                size: WireSize(width: 90, height: 30)
            ),
            Expected(what: "layoutLabel", node: scene.layoutLabel, view: .named("UILabel")),
            Expected(
                what: "autoresizingBox",
                node: scene.autoresizingBox,
                view: .named("UIView"),
                size: WireSize(width: 60, height: 24)
            ),
            Expected(
                what: "autoresizedDot",
                node: scene.autoresizedDot,
                view: .named("UIView"),
                size: WireSize(width: 12, height: 12)
            )
        ]
    }

    private static func check(_ expected: Expected) throws {
        try checkClasses(of: expected)
        try checkGeometry(of: expected)
    }

    private static func mismatch(
        _ expected: Expected,
        _ field: String,
        _ actual: String,
        _ wanted: String
    ) -> ProbeFailure {
        ProbeFailure("demo: \(expected.what) has \(field) \(actual), expected \(wanted)")
    }

    private static func checkClasses(of expected: Expected) throws {
        let node = expected.node
        func fail(_ field: String, _ actual: String, _ wanted: String) -> ProbeFailure {
            mismatch(expected, field, actual, wanted)
        }
        switch expected.view {
        case .unchecked:
            break
        case .none:
            if let viewClass = node.viewClassName {
                throw ProbeFailure("demo: \(expected.what) backs a view (\(viewClass)), expected none")
            }
        case .named(let viewClass):
            guard node.viewClassName == viewClass else {
                throw fail("view class", node.viewClassName ?? "none", viewClass)
            }
        }
        if let layerClass = expected.layerClass, node.className != layerClass {
            throw fail("layer class", node.className, layerClass)
        }
        if let name = expected.viewDisplayClass, node.viewDisplayClassName != name {
            throw fail("view display class", node.viewDisplayClassName ?? "none", name)
        }
        if let name = expected.viewControllerClass, node.viewControllerClassName != name {
            throw fail("view controller class", node.viewControllerClassName ?? "none", name)
        }
        if let name = expected.viewControllerDisplayClass, node.viewControllerDisplayClassName != name {
            throw fail("view controller display class", node.viewControllerDisplayClassName ?? "none", name)
        }
    }

    private static func checkGeometry(of expected: Expected) throws {
        let node = expected.node
        func fail(_ field: String, _ actual: String, _ wanted: String) -> ProbeFailure {
            mismatch(expected, field, actual, wanted)
        }
        if let size = expected.size, node.bounds.size != size {
            throw ProbeFailure(
                "demo: \(expected.what) is \(describe(node.bounds.size)) points, expected \(describe(size))"
            )
        }
        if let width = expected.width, node.bounds.size.width != width {
            throw ProbeFailure("demo: \(expected.what) is \(node.bounds.size.width) points wide, expected \(width)")
        }
        if let origin = expected.boundsOrigin, node.bounds.origin != origin {
            throw fail("bounds origin", describe(node.bounds.origin), describe(origin))
        }
        if let anchorPoint = expected.anchorPoint, node.anchorPoint != anchorPoint {
            throw fail("anchor point", describe(node.anchorPoint), describe(anchorPoint))
        }
        if let masksToBounds = expected.masksToBounds, node.masksToBounds != masksToBounds {
            throw fail("masksToBounds", "\(node.masksToBounds)", "\(masksToBounds)")
        }
        if let isHidden = expected.isHidden, node.isHidden != isHidden {
            throw fail("hidden", "\(node.isHidden)", "\(isHidden)")
        }
        if let opacity = expected.opacity, node.opacity != opacity {
            throw fail("opacity", "\(node.opacity)", "\(opacity)")
        }
    }

    private static func describe(_ size: WireSize) -> String { "\(size.width) x \(size.height)" }
    private static func describe(_ point: WirePoint) -> String { "(\(point.x), \(point.y))" }

    // MARK: - What holds what

    /// The card holds the badge alone; the stack view holds its label and then its block; the
    /// box holds its dot alone; the plain view holds nothing; the depth view holds three blocks.
    private static func checkContainers(of scene: DemoScene, in nodes: [LayerNode]) throws {
        func check(_ what: String, _ container: LayerNode, holds expected: [(String, LayerNode)]) throws {
            let actual = DemoScene.children(of: container, in: nodes).map(\.id)
            guard actual == expected.map(\.1.id) else {
                let names = expected.map(\.0).joined(separator: " then ")
                throw ProbeFailure(
                    "demo: \(what) must hold \(names.isEmpty ? "nothing" : names), found \(actual.count) sublayers"
                        + (actual.count == expected.count ? " in another order" : "")
                )
            }
        }
        try check("cardView", scene.card, holds: [("badge", scene.badge)])
        try check(
            "pushStack",
            scene.pushStack,
            holds: [("pushLabel", scene.pushLabel), ("pushedView", scene.pushedView)]
        )
        try check("autoresizingBox", scene.autoresizingBox, holds: [("autoresizedDot", scene.autoresizedDot)])
        try check("plainView", scene.plainView, holds: [])
        guard scene.blocks.count == 3 else {
            throw ProbeFailure("demo: depthView has \(scene.blocks.count) sublayers, expected the three blocks")
        }
    }

    /// The demo has one CardView, whatever holds it.
    private static func checkOneCard(in nodes: [LayerNode]) throws {
        let cards = nodes.filter { $0.viewClassName == "\(DemoScene.module).CardView" }.count
        guard cards == 1 else {
            throw ProbeFailure(
                "demo: expected one node with view_class_name \(DemoScene.module).CardView, found \(cards)"
            )
        }
    }

    /// Rotated by 30 degrees about z.
    private static func checkCardRotation(_ card: LayerNode) throws {
        var rotation = WireTransform.identity
        rotation.m11 = 0.75.squareRoot()
        rotation.m12 = 0.5
        rotation.m21 = -0.5
        rotation.m22 = 0.75.squareRoot()
        guard zip(card.transform.components, rotation.components).allSatisfy({ abs($0 - $1) <= 1e-9 }) else {
            throw ProbeFailure(
                "demo: cardView's transform is not a rotation by 30 degrees: \(card.transform.components)"
            )
        }
    }

    /// The blocks were added with zPosition 1, -1, 0 at x 0, 50, 100: listed back to front
    /// (P-HIER-01), they come as -1, 0, 1 at position.x 90, 140, 40.
    private static func checkDrawingOrder(of blocks: [LayerNode]) throws {
        guard blocks.map(\.zPosition) == [-1, 0, 1], blocks.map(\.position.x) == [90, 140, 40] else {
            throw ProbeFailure(
                "demo: the blocks of depthView must be listed in drawing order: z_position -1, 0, 1 at "
                    + "position.x 90, 140, 40; found z_position \(blocks.map(\.zPosition)) at "
                    + "position.x \(blocks.map(\.position.x)) (P-HIER-01)"
            )
        }
    }
}
