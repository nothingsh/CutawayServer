import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Reading the subtree of one layer (P-HIER-10, P-HIER-11). No server, no
/// connection: every test calls the capture on the main thread.
final class SubtreeCaptureTests: CaptureTestCase {
    /// A screen whose deepest view is held by every view and the controller above it:
    /// window → controller's root → outer → inner → leaf → a sublayer of the leaf.
    private struct Screen {
        let window: UIWindow
        let controller: OrderController
        let root: OrderRootView
        let outer: OrderOuterView
        let inner: OrderInnerView
        let leaf: UIView
        let sublayer: CALayer
    }

    private func makeScreen() throws -> Screen {
        let window = try makeWindow()
        let controller = OrderController()
        window.rootViewController = controller
        let root = controller.view as! OrderRootView
        let outer = OrderOuterView(frame: CGRect(x: 10, y: 10, width: 200, height: 200))
        let inner = OrderInnerView(frame: CGRect(x: 5, y: 5, width: 100, height: 100))
        let leaf = UIView(frame: CGRect(x: 1, y: 2, width: 30, height: 40))
        let sublayer = CALayer()
        root.addSubview(outer)
        outer.addSubview(inner)
        inner.addSubview(leaf)
        leaf.layer.addSublayer(sublayer)
        root.target = leaf
        outer.target = inner
        inner.target = leaf
        controller.first = outer
        controller.baseTarget = leaf
        window.layoutIfNeeded()
        return Screen(
            window: window,
            controller: controller,
            root: root,
            outer: outer,
            inner: inner,
            leaf: leaf,
            sublayer: sublayer
        )
    }

    /// The part of `hierarchy` that is the subtree of `layer`: its node and every node after it
    /// whose parent is already in the part.
    private func part(of layer: CALayer, in hierarchy: Hierarchy, registry: LayerRegistry) throws -> [LayerNode] {
        let id = registry.register(layer)
        let start = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == id })
        var ids: Set<UInt64> = [id]
        var nodes = [hierarchy.nodes[start]]
        for node in hierarchy.nodes[(start + 1)...] {
            guard ids.contains(node.parentID) else { break }
            ids.insert(node.id)
            nodes.append(node)
        }
        return nodes
    }

    // MARK: - S-HIER-11

    func test_S_HIER_11_subtreeMatchesTheHierarchy() throws {
        let screen = try makeScreen()
        let windows = HostWindows.all()
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: windows, registry: registry))

        for (name, layer) in [
            ("the window", screen.window.layer),
            ("the outer view", screen.outer.layer),
            ("the leaf", screen.leaf.layer),
            ("the leaf's sublayer", screen.sublayer)
        ] {
            let subtree = try XCTUnwrap(
                HierarchyCapture.captureSubtree(
                    rootID: registry.register(layer),
                    in: .testing(windows: windows, registry: registry)
                ),
                name
            )
            XCTAssertEqual(subtree.nodes, try part(of: layer, in: hierarchy, registry: registry), name)
            XCTAssertEqual(subtree.keyWindowID, hierarchy.keyWindowID, name)
        }

        // The holders lie above the subtree of the leaf, and are still found (P-HIER-08).
        let leaf = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: registry.register(screen.leaf.layer),
                in: .testing(windows: windows, registry: registry)
            )
        )
        XCTAssertEqual(
            leaf.nodes[0].memberReferences.map(\.name),
            ["target", "target", "baseTarget"],
            "inner.target, root.target, then the controller's"
        )
        XCTAssertEqual(leaf.nodes.count, 2)
        // The root keeps its real parent; the controller's root view is still marked.
        XCTAssertEqual(leaf.nodes[0].parentID, registry.register(screen.inner.layer))
        let outer = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: registry.register(screen.root.layer),
                in: .testing(windows: windows, registry: registry)
            )
        )
        XCTAssertEqual(outer.nodes[0].viewControllerDisplayClassName, "OrderController")
    }

    func test_S_HIER_11_rootOfAWindowHasNoParent() throws {
        let screen = try makeScreen()
        let registry = LayerRegistry()
        let subtree = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: registry.register(screen.window.layer),
                in: .testing(windows: HostWindows.all(), registry: registry)
            )
        )
        XCTAssertEqual(subtree.nodes[0].parentID, 0)
        XCTAssertEqual(subtree.nodes[0].id, registry.register(screen.window.layer))
        // The whole window: what reading that one window gives.
        XCTAssertEqual(
            subtree.nodes,
            HierarchyCapture.capture(.testing(windows: [screen.window], registry: registry)).nodes
        )
    }

    func test_S_HIER_11_keyWindowIDIsTheKeyWindowsRootLayer() throws {
        let screen = try makeScreen()
        let windows = HostWindows.all()
        let key = try XCTUnwrap(windows.last(where: \.isKeyWindow), "the test host has a key window")
        let registry = LayerRegistry()
        // A subtree in a window that is not key still names the key window.
        let subtree = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: registry.register(screen.leaf.layer),
                in: .testing(windows: windows, registry: registry)
            )
        )
        XCTAssertFalse(screen.window.isKeyWindow)
        XCTAssertEqual(subtree.keyWindowID, registry.register(key.layer))
    }

    func test_S_HIER_11_doesNotKeepLayersAlive() throws {
        let window = try makeWindow()
        let registry = LayerRegistry()
        weak var view: UIView?
        weak var sublayer: CALayer?
        autoreleasepool {
            let strongView = UIView()
            let strongSublayer = CALayer()
            strongView.layer.addSublayer(strongSublayer)
            window.addSubview(strongView)
            view = strongView
            sublayer = strongSublayer
            let id = registry.register(strongView.layer)
            let subtree = HierarchyCapture.captureSubtree(
                rootID: id,
                in: .testing(windows: [window], registry: registry)
            )
            XCTAssertEqual(subtree?.nodes.count, 2)
            strongView.removeFromSuperview()
        }
        // Core Animation's open transaction holds on to removed layers until it is committed.
        CATransaction.flush()
        XCTAssertNil(view, "the capture kept the view alive")
        XCTAssertNil(sublayer, "the capture kept the sublayer alive")
    }

    func test_S_HIER_11_doesNotChangeTheScreen() throws {
        let window = try makeWindow()
        window.backgroundColor = .white
        let view = CountingView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        view.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        view.transform = CGAffineTransform(rotationAngle: 0.3)
        window.addSubview(view)
        window.layoutIfNeeded()
        view.layer.displayIfNeeded()
        let before = try render(window)
        let layoutCount = view.layoutCount
        let drawCount = view.drawCount

        // Work is pending. Reading the subtree must neither do it nor cancel it.
        view.setNeedsLayout()
        view.setNeedsDisplay()
        let registry = LayerRegistry()
        let id = registry.register(view.layer)
        let first = HierarchyCapture.captureSubtree(rootID: id, in: .testing(windows: [window], registry: registry))
        let second = HierarchyCapture.captureSubtree(rootID: id, in: .testing(windows: [window], registry: registry))
        XCTAssertNotNil(first)
        XCTAssertEqual(first, second)
        XCTAssertEqual(view.layoutCount, layoutCount, "the capture laid the view out")
        XCTAssertEqual(view.drawCount, drawCount, "the capture drew the view")
        XCTAssertTrue(view.layer.needsLayout())
        XCTAssertTrue(view.layer.needsDisplay())
        XCTAssertEqual(try render(window), before)
    }

    // MARK: - S-HIER-12

    func test_S_HIER_12_missingLayersAreNotFound() throws {
        let window = try makeWindow()
        let windows = HostWindows.all()
        let registry = LayerRegistry()

        // Released.
        var releasedID: UInt64 = 0
        autoreleasepool {
            let layer = CALayer()
            window.layer.addSublayer(layer)
            releasedID = registry.register(layer)
            layer.removeFromSuperlayer()
        }
        CATransaction.flush()
        XCTAssertNil(registry.layer(for: releasedID), "the layer was released")

        // Alive, but in no window any more.
        let removed = UIView()
        window.addSubview(removed)
        let removedID = registry.register(removed.layer)
        removed.removeFromSuperview()

        // Alive, in a window that is not one of the app's.
        let detached = makeDetachedWindow()
        let elsewhere = UIView()
        detached.addSubview(elsewhere)
        let elsewhereID = registry.register(elsewhere.layer)

        for (name, id) in [
            ("released", releasedID),
            ("removed from its window", removedID),
            ("in a window that is not the app's", elsewhereID),
            ("never given out", 12_345),
            ("zero", 0)
        ] {
            XCTAssertNil(
                HierarchyCapture.captureSubtree(rootID: id, in: .testing(windows: windows, registry: registry)),
                name
            )
        }
        // The layer that is still in a window is found with the same registry.
        XCTAssertNotNil(
            HierarchyCapture.captureSubtree(
                rootID: registry.register(window.layer),
                in: .testing(windows: windows, registry: registry)
            )
        )
    }

    func test_S_HIER_12_ancestorsEndAtAWindow() throws {
        let window = try makeWindow()
        let view = UIView()
        let sublayer = CALayer()
        window.addSubview(view)
        view.layer.addSublayer(sublayer)
        XCTAssertEqual(
            LayerTopology.ancestors(of: sublayer, in: [window])?.map(ObjectIdentifier.init),
            [window.layer, view.layer].map(ObjectIdentifier.init)
        )
        XCTAssertEqual(LayerTopology.ancestors(of: window.layer, in: [window])?.count, 0)
        XCTAssertNil(LayerTopology.ancestors(of: sublayer, in: []))
        XCTAssertNil(LayerTopology.ancestors(of: CALayer(), in: [window]))
    }
}
