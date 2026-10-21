import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

// Swift classes of every kind that gets a different runtime name.
class PlainCardView: UIView {}
private class PrivateBadgeView: UIView {}
enum Screen {
    final class HeaderView: UIView {}
}

final class Cell<Content>: UIView {}
final class RingLayer: CALayer {}
final class RingView: UIView {
    override static var layerClass: AnyClass { RingLayer.self }
}

// View controllers of the tests' own, for P-HIER-07.
final class ScreenController: UIViewController {}
final class DetailController: UIViewController {}

/// Reading the layer hierarchy. No server, no connection: every test calls
/// the capture on the main thread.
final class HierarchyCaptureTests: CaptureTestCase {
    // MARK: - S-HIER-01

    func test_S_HIER_01_nodesFollowTheLayerTree() throws {
        let window = try makeWindow()
        let viewA = UIView(frame: CGRect(x: 10, y: 20, width: 100, height: 200))
        let viewA1 = UIView(frame: CGRect(x: 1, y: 2, width: 3, height: 4))
        let viewA2 = UIView()
        let viewA2a = UIView()
        let viewB = UIView()
        window.addSubview(viewA)
        viewA.addSubview(viewA1)
        viewA.addSubview(viewA2)
        viewA2.addSubview(viewA2a)
        window.addSubview(viewB)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))

        // Pre-order: every parent before its children, siblings in the order they were added.
        let layers = [window.layer, viewA.layer, viewA1.layer, viewA2.layer, viewA2a.layer, viewB.layer]
        XCTAssertEqual(hierarchy.nodes.map(\.id), layers.map { registry.register($0) })
        XCTAssertEqual(hierarchy.nodes.map(\.id), [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(hierarchy.nodes.map(\.parentID), [0, 1, 2, 2, 4, 1])

        // P-HIER-06: bounds in the layer's own coordinates, position in its parent's.
        XCTAssertEqual(hierarchy.nodes[1].bounds, WireRect(x: 0, y: 0, width: 100, height: 200))
        XCTAssertEqual(hierarchy.nodes[1].position, WirePoint(x: 60, y: 120))
        XCTAssertEqual(hierarchy.nodes[2].position, WirePoint(x: 2.5, y: 4))
        XCTAssertEqual(hierarchy.nodes[0].bounds, WireRect(x: 0, y: 0, width: 320, height: 480))
        XCTAssertEqual(hierarchy.nodes[0].position, WirePoint(x: 160, y: 240))

        // The order follows the tree when it changes.
        window.bringSubviewToFront(viewA)
        viewA.sendSubviewToBack(viewA2)
        let reordered = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(reordered.nodes.map(\.id), [1, 6, 2, 4, 5, 3])
        XCTAssertEqual(reordered.nodes.map(\.parentID), [0, 1, 1, 2, 4, 2])
    }

    func test_S_HIER_01_includesEveryWindowBackToFront() throws {
        let hostWindows = HostWindows.all()
        XCTAssertFalse(hostWindows.isEmpty, "the test host shows a window")

        let low = try makeWindow(level: UIWindow.Level(rawValue: UIWindow.Level.normal.rawValue - 1))
        let high = try makeWindow(level: .alert)
        let hidden = try makeWindow(hidden: true)

        let windows = HostWindows.all()
        XCTAssertEqual(windows.count, hostWindows.count + 3)
        for window in hostWindows + [low, high, hidden] {
            XCTAssertTrue(windows.contains { $0 === window }, "\(window) is missing")
        }
        // Back to front: by level.
        let levels = windows.map(\.windowLevel.rawValue)
        XCTAssertEqual(levels, levels.sorted())
        XCTAssertTrue(windows.first === low)
        XCTAssertTrue(windows.last === high)

        // One root per window, in the same order, each followed by its own layers.
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: windows, registry: registry))
        let roots = hierarchy.nodes.filter { $0.parentID == 0 }
        XCTAssertEqual(roots.map(\.id), windows.map { registry.register($0.layer) })
        XCTAssertEqual(roots.map(\.viewClassName), windows.map { NSStringFromClass(type(of: $0)) })
        XCTAssertTrue(try node(of: hidden.layer, in: hierarchy, registry: registry).isHidden)
        XCTAssertFalse(try node(of: high.layer, in: hierarchy, registry: registry).isHidden)
    }

    func test_S_HIER_01_windowsOfOneLevelKeepTheirOrder() throws {
        let first = try makeWindow()
        let second = try makeWindow(level: .statusBar)
        let third = try makeWindow()
        let fourth = try makeWindow(level: .statusBar)
        let ordered = HostWindows.backToFront([second, first, fourth, third])
        XCTAssertTrue(ordered[0] === first)
        XCTAssertTrue(ordered[1] === third)
        XCTAssertTrue(ordered[2] === second)
        XCTAssertTrue(ordered[3] === fourth)
    }

    func test_S_HIER_01_keyWindowIDIsTheKeyWindowsRootLayer() throws {
        let windows = HostWindows.all()
        let key = try XCTUnwrap(windows.first(where: \.isKeyWindow), "the test host has a key window")
        let other = try makeWindow()

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: HostWindows.all(), registry: registry))
        XCTAssertNotEqual(hierarchy.keyWindowID, 0)
        XCTAssertEqual(hierarchy.keyWindowID, registry.register(key.layer))
        XCTAssertEqual(
            try node(of: key.layer, in: hierarchy, registry: registry).parentID,
            0
        )

        // No key window among them: 0.
        XCTAssertFalse(other.isKeyWindow)
        XCTAssertEqual(HierarchyCapture.capture(.testing(windows: [other], registry: registry)).keyWindowID, 0)
    }

    func test_S_HIER_01_anAppWithoutWindowsHasAnEmptyHierarchy() throws {
        let hierarchy = HierarchyCapture.capture(.testing(windows: [], registry: LayerRegistry()))
        XCTAssertEqual(hierarchy, Hierarchy(nodes: [], keyWindowID: 0))
        let frame = Frame(requestID: 1, body: .hierarchy(hierarchy))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
    }

    func test_S_HIER_01_deepTreesAreReadWithoutRecursion() throws {
        // 2,000 layers, each inside the one before: far deeper than a real screen.
        let depth = 2_000
        let window = makeDetachedWindow()
        var chain: [CALayer] = []
        var parent: CALayer = window.layer
        for _ in 0..<depth {
            let layer = CALayer()
            parent.addSublayer(layer)
            chain.append(layer)
            parent = layer
        }

        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: LayerRegistry()))
        XCTAssertEqual(hierarchy.nodes.count, depth + 1)
        XCTAssertEqual(hierarchy.nodes.map(\.id), (1...UInt64(depth + 1)).map { $0 })
        XCTAssertEqual(hierarchy.nodes.map(\.parentID), (0...UInt64(depth)).map { $0 })

        // Take the chain apart from the bottom, so that releasing it does not recurse either.
        for layer in chain.reversed() { layer.removeFromSuperlayer() }
    }

    // MARK: - S-HIER-02

    func test_S_HIER_02_idsAreStableAcrossCaptures() throws {
        let window = try makeWindow()
        let first = UIView()
        let second = UIView()
        window.addSubview(first)
        window.addSubview(second)

        let registry = LayerRegistry()
        let before = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(HierarchyCapture.capture(.testing(windows: [window], registry: registry)), before)
        XCTAssertFalse(before.nodes.contains { $0.id == 0 })

        // A new layer between the old ones: they keep their IDs, it gets one never seen before.
        let added = UIView()
        window.insertSubview(added, aboveSubview: first)
        let after = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(after.nodes.map(\.id), [1, 2, 4, 3])
        XCTAssertEqual(try node(of: first.layer, in: after, registry: registry).id, 2)
        XCTAssertEqual(try node(of: second.layer, in: after, registry: registry).id, 3)

        // The whole app, twice: the same nodes.
        let appRegistry = LayerRegistry()
        let app = HierarchyCapture.capture(.testing(windows: HostWindows.all(), registry: appRegistry))
        XCTAssertEqual(
            HierarchyCapture.capture(.testing(windows: HostWindows.all(), registry: appRegistry)).nodes.map(\.id),
            app.nodes.map(\.id)
        )
    }

    func test_S_HIER_02_releasedLayersIDIsNeverReused() throws {
        let window = try makeWindow()
        let registry = LayerRegistry()
        var doomedID: UInt64 = 0
        weak var doomedLayer: CALayer?
        var before = Hierarchy(nodes: [], keyWindowID: 0)
        autoreleasepool {
            let doomed = UIView()
            window.addSubview(doomed)
            before = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
            doomedID = registry.register(doomed.layer)
            doomedLayer = doomed.layer
            doomed.removeFromSuperview()
        }
        // Core Animation's open transaction holds on to removed layers until it is committed.
        CATransaction.flush()
        XCTAssertEqual(before.nodes.map(\.id), [1, 2])
        XCTAssertEqual(doomedID, 2)
        XCTAssertNil(doomedLayer, "the view's layer should be gone once the view is")

        // Many new layers: some of them land on the address the released one had.
        let views = (0..<2_000).map { _ in UIView() }
        views.forEach(window.addSubview)
        let after = HierarchyCapture.capture(.testing(windows: [window], registry: registry))

        XCTAssertEqual(after.nodes.count, 2_001)
        XCTAssertFalse(after.nodes.contains { $0.id == doomedID })
        XCTAssertNil(registry.layer(for: doomedID))
        XCTAssertEqual(after.nodes[0].id, 1)
        XCTAssertEqual(after.nodes.dropFirst().map(\.id), (3...2_002).map { UInt64($0) })
        // The capture dropped the released entry.
        XCTAssertEqual(registry.count, 2_001)
    }

    func test_S_HIER_02_captureDoesNotExtendLifetimes() throws {
        let window = try makeWindow()
        let registry = LayerRegistry()
        weak var view: UIView?
        weak var backingLayer: CALayer?
        weak var sublayer: CALayer?
        autoreleasepool {
            let strongView = UIView()
            let strongSublayer = CALayer()
            strongView.layer.addSublayer(strongSublayer)
            window.addSubview(strongView)
            view = strongView
            backingLayer = strongView.layer
            sublayer = strongSublayer
            let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
            XCTAssertEqual(hierarchy.nodes.count, 3)
            strongView.removeFromSuperview()
        }
        // Core Animation's open transaction holds on to removed layers until it is committed.
        CATransaction.flush()
        XCTAssertNil(view, "the capture kept the view alive")
        XCTAssertNil(backingLayer, "the capture kept the view's layer alive")
        XCTAssertNil(sublayer, "the capture kept the sublayer alive")
        // The registry is still in use. It no longer shows them, and the capture made it forget
        // them: its size follows the layers that are alive.
        XCTAssertEqual(registry.count, 3)
        XCTAssertEqual(HierarchyCapture.capture(.testing(windows: [window], registry: registry)).nodes.count, 1)
        XCTAssertEqual(registry.count, 1)
    }

    // MARK: - S-HIER-03

    func test_S_HIER_03_onlyBackingLayersCarryTheViewClass() throws {
        let window = try makeWindow()
        let label = UILabel()
        window.addSubview(label)
        // A layer added by hand.
        let shape = CAShapeLayer()
        label.layer.addSublayer(shape)
        // A layer whose delegate is a view, but which is not that view's layer.
        let borrowed = CALayer()
        borrowed.delegate = label
        window.layer.addSublayer(borrowed)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))

        let windowNode = try node(of: window.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(windowNode.viewClassName, "UIWindow")
        XCTAssertEqual(windowNode.viewDisplayClassName, "UIWindow")
        let labelNode = try node(of: label.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(labelNode.viewClassName, "UILabel")
        XCTAssertEqual(labelNode.viewDisplayClassName, "UILabel")

        let shapeNode = try node(of: shape, in: hierarchy, registry: registry)
        XCTAssertEqual(shapeNode.className, "CAShapeLayer")
        XCTAssertNil(shapeNode.viewClassName)
        XCTAssertNil(shapeNode.viewDisplayClassName)
        let borrowedNode = try node(of: borrowed, in: hierarchy, registry: registry)
        XCTAssertNil(borrowedNode.viewClassName)
        XCTAssertNil(borrowedNode.viewDisplayClassName)
    }

    // MARK: - S-HIER-04

    func test_S_HIER_04_swiftClassNamesAreReadable() throws {
        let window = try makeWindow()
        let views: [(view: UIView, displayName: String)] = [
            (PlainCardView(), "PlainCardView"),
            (PrivateBadgeView(), "PrivateBadgeView"),
            (Screen.HeaderView(), "HeaderView"),
            (Cell<Int>(), "Cell<Int>"),
            (RingView(), "RingView")
        ]
        views.forEach { window.addSubview($0.view) }

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        for (view, displayName) in views {
            let node = try node(of: view.layer, in: hierarchy, registry: registry)
            let runtimeName = NSStringFromClass(type(of: view))
            XCTAssertEqual(node.viewClassName, runtimeName)
            XCTAssertEqual(node.viewDisplayClassName, displayName)
            // The runtime name is the one that needs reading: a module prefix or a mangled name.
            XCTAssertNotEqual(runtimeName, displayName)
            XCTAssertTrue(runtimeName.contains(".") || runtimeName.hasPrefix("_Tt"), runtimeName)
        }
        XCTAssertEqual(
            try node(of: views[0].view.layer, in: hierarchy, registry: registry).viewClassName,
            "CutawayServerTests.PlainCardView"
        )

        // A Swift layer class is treated the same way.
        let ring = try node(of: views[4].view.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(ring.className, "CutawayServerTests.RingLayer")
        XCTAssertEqual(ring.displayClassName, "RingLayer")

        // UIKit's own classes read the same both ways.
        let plain = try node(of: views[0].view.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(plain.className, "CALayer")
        XCTAssertEqual(plain.displayClassName, "CALayer")
    }

    func test_S_HIER_04_observedObjectsKeepTheirClassNames() throws {
        // Key-value observing swaps the object's class for a generated subclass. Its name must
        // not show up.
        let window = try makeWindow()
        let view = PlainCardView()
        window.addSubview(view)
        let registry = LayerRegistry()
        let before = try node(
            of: view.layer,
            in: HierarchyCapture.capture(.testing(windows: [window], registry: registry)),
            registry: registry
        )

        let observations = [
            view.observe(\.isHidden) { _, _ in },
            view.layer.observe(\.opacity) { _, _ in }
        ]
        XCTAssertTrue(
            NSStringFromClass(object_getClass(view)!).contains("NSKVONotifying"),
            "the test relies on observing changing the view's class"
        )
        let after = try node(
            of: view.layer,
            in: HierarchyCapture.capture(.testing(windows: [window], registry: registry)),
            registry: registry
        )
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.viewDisplayClassName, "PlainCardView")
        XCTAssertEqual(after.className, "CALayer")
        observations.forEach { $0.invalidate() }
    }

    // MARK: - S-HIER-05

    func test_S_HIER_05_transformMatchesTheRotation() throws {
        let window = try makeWindow()
        let rotated = UIView(frame: CGRect(x: 20, y: 40, width: 100, height: 60))
        rotated.transform = CGAffineTransform(rotationAngle: .pi / 6)
        window.addSubview(rotated)
        // A transform that uses the third dimension.
        let tilted = CALayer()
        var perspective = CATransform3DIdentity
        perspective.m34 = -1.0 / 500
        tilted.transform = CATransform3DTranslate(CATransform3DRotate(perspective, 0.7, 1, 0, 0), 3, 4, 5)
        window.layer.addSublayer(tilted)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))

        let node = try node(of: rotated.layer, in: hierarchy, registry: registry)
        let expected: [Double] = [
            cos(.pi / 6),
            sin(.pi / 6),
            0,
            0,
            -sin(.pi / 6),
            cos(.pi / 6),
            0,
            0,
            0,
            0,
            1,
            0,
            0,
            0,
            0,
            1
        ]
        for (index, pair) in zip(node.transform.components, expected).enumerated() {
            XCTAssertEqual(pair.0, pair.1, accuracy: 1e-12, "component \(index)")
        }
        // The transform does not change the layer's own rectangle or where it is anchored.
        XCTAssertEqual(node.bounds, WireRect(x: 0, y: 0, width: 100, height: 60))
        XCTAssertEqual(node.position, WirePoint(x: 70, y: 70))

        let transform = tilted.transform
        XCTAssertEqual(
            try self.node(of: tilted, in: hierarchy, registry: registry).transform.components,
            [
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
            ].map { Double($0) }
        )
        XCTAssertNotEqual(transform.m34, 0, "the transform has perspective")
    }

    func test_S_HIER_05_scrollOffsetIsTheBoundsOrigin() throws {
        let window = try makeWindow()
        let scrollView = UIScrollView(frame: CGRect(x: 10, y: 20, width: 200, height: 300))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 400, height: 900)
        let content = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        scrollView.addSubview(content)
        window.addSubview(scrollView)
        scrollView.contentOffset = CGPoint(x: 30, y: 100)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        let node = try node(of: scrollView.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(node.bounds, WireRect(x: 30, y: 100, width: 200, height: 300))
        XCTAssertEqual(node.position, WirePoint(x: 110, y: 170))
        XCTAssertTrue(node.masksToBounds)
        // The content does not move in the scroll view's coordinates.
        XCTAssertEqual(
            try self.node(of: content.layer, in: hierarchy, registry: registry).position,
            WirePoint(x: 25, y: 25)
        )
    }

    func test_S_HIER_05_modelValuesAreReadAsTheyAre() throws {
        let window = try makeWindow()
        let layer = CALayer()
        layer.bounds = CGRect(x: 5, y: 6, width: 70, height: 80)
        layer.position = CGPoint(x: 11, y: 12)
        layer.anchorPoint = CGPoint(x: 0.25, y: 1)
        layer.zPosition = -3
        layer.isHidden = true
        layer.opacity = 0.25
        layer.masksToBounds = true
        window.layer.addSublayer(layer)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(
            try node(of: layer, in: hierarchy, registry: registry),
            LayerNode(
                id: 2,
                parentID: 1,
                className: "CALayer",
                displayClassName: "CALayer",
                bounds: WireRect(x: 5, y: 6, width: 70, height: 80),
                position: WirePoint(x: 11, y: 12),
                anchorPoint: WirePoint(x: 0.25, y: 1),
                transform: .identity,
                zPosition: -3,
                isHidden: true,
                opacity: 0.25,
                masksToBounds: true,
                layerAddress: address(of: layer),
                layerClassOrigin: .system
            )
        )
    }

    func test_S_HIER_05_nonFiniteValuesAreSentAsZero() throws {
        // These layers stay out of every scene: values like these should not reach the screen.
        let window = makeDetachedWindow()
        let broken = CALayer()
        var transform = CATransform3DIdentity
        transform.m11 = .nan
        transform.m22 = .infinity
        transform.m41 = -.infinity
        transform.m42 = 7
        broken.transform = transform
        broken.anchorPoint = CGPoint(x: CGFloat.nan, y: CGFloat.infinity)
        broken.opacity = .nan
        broken.zPosition = .infinity
        window.layer.addSublayer(broken)
        let endless = CALayer()
        endless.bounds = CGRect(x: -CGFloat.infinity, y: 2, width: CGFloat.infinity, height: 10)
        endless.position = CGPoint(x: CGFloat.infinity, y: -CGFloat.infinity)
        window.layer.addSublayer(endless)
        // The layers do hold these values; the capture is what has to deal with them.
        XCTAssertTrue(broken.transform.m11.isNaN)
        XCTAssertTrue(broken.anchorPoint.x.isNaN)
        XCTAssertTrue(broken.opacity.isNaN)
        XCTAssertEqual(endless.bounds.size.width, .infinity)
        XCTAssertEqual(endless.position.x, .infinity)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))

        let brokenNode = try node(of: broken, in: hierarchy, registry: registry)
        var expected = WireTransform.identity
        expected.m11 = 0
        expected.m22 = 0
        expected.m41 = 0
        expected.m42 = 7
        XCTAssertEqual(brokenNode.transform, expected)
        XCTAssertEqual(brokenNode.anchorPoint, WirePoint(x: 0, y: 0))
        XCTAssertEqual(brokenNode.opacity, 0)
        XCTAssertTrue(brokenNode.zPosition.isFinite)
        let endlessNode = try node(of: endless, in: hierarchy, registry: registry)
        XCTAssertEqual(endlessNode.bounds, WireRect(x: 0, y: 2, width: 0, height: 10))
        XCTAssertEqual(endlessNode.position, WirePoint(x: 0, y: 0))

        // Every number of every node is finite, and the frame passes verification.
        for node in hierarchy.nodes {
            let numbers =
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
            XCTAssertTrue(numbers.allSatisfy(\.isFinite), "\(node)")
        }
        let frame = Frame(requestID: 1, body: .hierarchy(hierarchy))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
    }

    func test_S_HIER_05_conversionsReplaceEveryNonFiniteNumber() {
        // Values no layer accepts (it raises on a NaN position or bounds) still convert safely.
        XCTAssertEqual(WireGeometry.finite(CGFloat.nan), 0)
        XCTAssertEqual(WireGeometry.finite(CGFloat.infinity), 0)
        XCTAssertEqual(WireGeometry.finite(-CGFloat.infinity), 0)
        XCTAssertEqual(WireGeometry.finite(CGFloat(-2.5)), -2.5)
        XCTAssertEqual(WireGeometry.finite(Float.nan), 0)
        XCTAssertEqual(WireGeometry.finite(-Float.infinity), 0)
        XCTAssertEqual(WireGeometry.finite(Float(0.5)), 0.5)
        XCTAssertEqual(
            WireGeometry.point(CGPoint(x: CGFloat.nan, y: 3)),
            WirePoint(x: 0, y: 3)
        )
        XCTAssertEqual(
            WireGeometry.rect(CGRect(x: CGFloat.nan, y: 1, width: CGFloat.nan, height: 4)),
            WireRect(x: 0, y: 1, width: 0, height: 4)
        )
        // A negative size is a value like any other.
        XCTAssertEqual(
            WireGeometry.rect(CGRect(x: 1, y: 2, width: -3, height: -4)),
            WireRect(x: 1, y: 2, width: -3, height: -4)
        )
        var transform = CATransform3DIdentity
        transform.m44 = .nan
        transform.m13 = 9
        var expected = WireTransform.identity
        expected.m44 = 0
        expected.m13 = 9
        XCTAssertEqual(WireGeometry.transform(transform), expected)
    }

    // MARK: - S-HIER-06

    func test_S_HIER_06_captureLeavesTheWindowUntouched() throws {
        let window = try makeWindow()
        window.backgroundColor = .white
        let red = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 100))
        red.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        red.transform = CGAffineTransform(rotationAngle: 0.3)
        window.addSubview(red)
        let label = UILabel(frame: CGRect(x: 20, y: 200, width: 200, height: 40))
        label.text = "Cutaway"
        window.addSubview(label)
        let scrollView = UIScrollView(frame: CGRect(x: 20, y: 260, width: 200, height: 100))
        scrollView.contentSize = CGSize(width: 200, height: 400)
        scrollView.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        scrollView.contentOffset = CGPoint(x: 0, y: 50)
        window.addSubview(scrollView)
        window.layoutIfNeeded()

        let before = try render(window)
        // The rendering shows the views: the comparison below is not between two blank images.
        let center = (70 * 320 + 70) * 4
        XCTAssertEqual(Array(before[center..<center + 4]), [0, 0, 255, 255], "BGRA of the red view")

        let registry = LayerRegistry()
        let first = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        let second = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(first, second)

        XCTAssertEqual(try render(window), before)
        XCTAssertEqual(scrollView.contentOffset, CGPoint(x: 0, y: 50))
    }

    func test_S_HIER_06_captureDoesNotTriggerLayoutOrDisplay() throws {
        let window = try makeWindow()
        let view = CountingView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.addSubview(view)
        window.layoutIfNeeded()
        view.layer.displayIfNeeded()
        let layoutCount = view.layoutCount
        let drawCount = view.drawCount
        XCTAssertGreaterThan(layoutCount, 0)
        XCTAssertGreaterThan(drawCount, 0)

        // Work is pending. Reading the hierarchy must neither do it nor cancel it.
        view.setNeedsLayout()
        view.setNeedsDisplay()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: LayerRegistry()))
        XCTAssertEqual(hierarchy.nodes.count, 2)
        XCTAssertEqual(view.layoutCount, layoutCount, "the capture laid the view out")
        XCTAssertEqual(view.drawCount, drawCount, "the capture drew the view")
        XCTAssertTrue(view.layer.needsLayout())
        XCTAssertTrue(view.layer.needsDisplay())

        window.layoutIfNeeded()
        view.layer.displayIfNeeded()
        XCTAssertEqual(view.layoutCount, layoutCount + 1)
        XCTAssertEqual(view.drawCount, drawCount + 1)
    }

    // MARK: - S-HIER-08

    func test_S_HIER_08_rootViewsOfViewControllersAreMarked() throws {
        let window = try makeWindow()
        let root = ScreenController()
        window.rootViewController = root
        // A child of UIKit's own class, and a navigation controller with a child of its own.
        let child = UIViewController()
        root.addChild(child)
        root.view.addSubview(child.view)
        child.didMove(toParent: root)
        let top = DetailController()
        let navigation = UINavigationController(rootViewController: top)
        root.addChild(navigation)
        navigation.view.frame = CGRect(x: 0, y: 200, width: 320, height: 200)
        root.view.addSubview(navigation.view)
        navigation.didMove(toParent: root)
        let plain = UIView()
        root.view.addSubview(plain)
        window.layoutIfNeeded()
        XCTAssertNotNil(top.viewIfLoaded?.window, "the navigation controller shows its child")

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        var marked: [UInt64: [String]] = [:]
        for node in hierarchy.nodes {
            guard let name = node.viewControllerClassName else {
                XCTAssertNil(node.viewControllerDisplayClassName)
                continue
            }
            marked[node.id] = [name, node.viewControllerDisplayClassName ?? "none"]
        }
        // Exactly the four root views: not the window, not the plain view, not the navigation
        // controller's own containers and bar.
        XCTAssertEqual(
            marked,
            [
                registry.register(root.view.layer): ["CutawayServerTests.ScreenController", "ScreenController"],
                registry.register(child.view.layer): ["UIViewController", "UIViewController"],
                registry.register(navigation.view.layer): ["UINavigationController", "UINavigationController"],
                registry.register(top.view.layer): ["CutawayServerTests.DetailController", "DetailController"]
            ]
        )
        XCTAssertNil(try node(of: plain.layer, in: hierarchy, registry: registry).viewControllerClassName)
    }

    func test_S_HIER_08_presentedViewControllersAreMarked() throws {
        let window = try makeWindow()
        let root = ScreenController()
        window.rootViewController = root
        let presented = DetailController()
        presented.modalPresentationStyle = .overFullScreen
        let shown = expectation(description: "presented")
        root.present(presented, animated: false) { shown.fulfill() }
        wait(for: [shown], timeout: 5)
        defer { root.dismiss(animated: false) }

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        let node = try node(of: presented.view.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(node.viewControllerClassName, "CutawayServerTests.DetailController")
        XCTAssertEqual(node.viewControllerDisplayClassName, "DetailController")
        // The presenting controller's view is still there, and still marked.
        let rootNode = try self.node(of: root.view.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(rootNode.viewControllerClassName, "CutawayServerTests.ScreenController")
    }

    func test_S_HIER_08_viewsAreNotLoaded() throws {
        let window = try makeWindow()
        let root = ScreenController()
        window.rootViewController = root
        let unloaded = DetailController()
        root.addChild(unloaded)
        unloaded.didMove(toParent: root)
        XCTAssertFalse(unloaded.isViewLoaded)

        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: LayerRegistry()))
        XCTAssertFalse(unloaded.isViewLoaded, "the capture loaded a view")
        XCTAssertEqual(hierarchy.nodes.compactMap(\.viewControllerClassName), ["CutawayServerTests.ScreenController"])
    }

    func test_S_HIER_08_doesNotKeepViewControllersAlive() throws {
        let window = try makeWindow()
        weak var controller: UIViewController?
        autoreleasepool {
            let strongController = DetailController()
            controller = strongController
            window.rootViewController = strongController
            let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: LayerRegistry()))
            XCTAssertEqual(
                hierarchy.nodes.compactMap(\.viewControllerClassName),
                ["CutawayServerTests.DetailController"]
            )
            window.rootViewController = nil
        }
        // Core Animation's open transaction holds on to removed layers until it is committed,
        // and UIKit lets go of a replaced root view controller only when the run loop turns:
        // without the capture, the controller is gone after both.
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertNil(controller, "the capture kept the view controller alive")
    }

    // MARK: - S-HIER-10

    func test_S_HIER_10_siblingsAreInDrawingOrder() throws {
        // A window that is never shown: a NaN zPosition must not reach the render server.
        let window = makeDetachedWindow()
        let parent = CALayer()
        window.layer.addSublayer(parent)
        let layers = ([1, -1, 0, 1, .nan, 0] as [CGFloat]).map { zPosition -> CALayer in
            let layer = CALayer()
            layer.zPosition = zPosition
            layer.addSublayer(CALayer())
            parent.addSublayer(layer)
            return layer
        }

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        let parentID = registry.register(parent)
        let siblings = hierarchy.nodes.filter { $0.parentID == parentID }
        // Back to front by zPosition, NaN as 0; equal ones in the order of sublayers.
        let expected = [1, 2, 4, 5, 0, 3].map { layers[$0] }
        XCTAssertEqual(siblings.map(\.id), expected.map { registry.register($0) })
        XCTAssertEqual(siblings.map(\.zPosition), [-1, 0, 0, 0, 1, 1])
        // Still pre-order: each one's own sublayer comes right after it.
        let ids = hierarchy.nodes.map(\.id)
        for layer in expected {
            let index = try XCTUnwrap(ids.firstIndex(of: registry.register(layer)))
            XCTAssertEqual(hierarchy.nodes[index + 1].id, registry.register(layer.sublayers![0]))
            XCTAssertEqual(hierarchy.nodes[index + 1].parentID, registry.register(layer))
        }
    }

    func test_S_HIER_10_equalSiblingsKeepTheirOrder() throws {
        let window = try makeWindow()
        let views = [UIView(), UIView(), UIView()]
        views.forEach(window.addSubview)
        // All drawn at the same depth: the order is that of the subviews, as in protocol 0.1.
        views.forEach { $0.layer.zPosition = 2 }
        window.bringSubviewToFront(views[0])

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(
            hierarchy.nodes.dropFirst().map(\.id),
            [views[1], views[2], views[0]].map { registry.register($0.layer) }
        )
    }

    func test_S_HIER_10_drawingOrderIsStable() {
        // Many equal values: an unstable sort would mix them up.
        let layers = (0..<200).map { index -> CALayer in
            let layer = CALayer()
            layer.zPosition = CGFloat(index % 3)
            return layer
        }
        let ordered = HierarchyCapture.drawingOrder(layers)
        let expected = [0, 1, 2].flatMap { zPosition in layers.filter { $0.zPosition == CGFloat(zPosition) } }
        XCTAssertTrue(zip(ordered, expected).allSatisfy { $0 === $1 })
        XCTAssertEqual(ordered.count, layers.count)
    }

    // MARK: - S-HIER-13

    /// Where the object lies in memory, worked out without the server's code.
    private func address(of object: AnyObject) -> UInt64 {
        UInt64(UInt(bitPattern: Unmanaged.passUnretained(object).toOpaque()))
    }

    func test_S_HIER_13_nodesCarryTheAddressesOfTheirObjects() throws {
        let window = try makeWindow()
        let root = ScreenController()
        window.rootViewController = root
        let plain = UIView()
        root.view.addSubview(plain)
        let bare = CALayer()
        plain.layer.addSublayer(bare)
        window.layoutIfNeeded()

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))

        // A controller's root view: all three.
        let rootNode = try node(of: root.view.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(rootNode.layerAddress, address(of: root.view.layer))
        XCTAssertEqual(rootNode.viewAddress, address(of: root.view))
        XCTAssertEqual(rootNode.viewControllerAddress, address(of: root))
        // A plain view: no controller.
        let plainNode = try node(of: plain.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(plainNode.layerAddress, address(of: plain.layer))
        XCTAssertEqual(plainNode.viewAddress, address(of: plain))
        XCTAssertNil(plainNode.viewControllerAddress)
        // A layer of its own: only the layer.
        let bareNode = try node(of: bare, in: hierarchy, registry: registry)
        XCTAssertEqual(bareNode.layerAddress, address(of: bare))
        XCTAssertNil(bareNode.viewAddress)
        XCTAssertNil(bareNode.viewControllerAddress)

        // P-HIER-14: exactly when the class names are given; the layer's always.
        for node in hierarchy.nodes {
            XCTAssertNotEqual(node.layerAddress, 0, "\(node.id)")
            XCTAssertEqual(node.viewAddress != nil, node.viewClassName != nil, "\(node.id)")
            XCTAssertEqual(node.viewControllerAddress != nil, node.viewControllerClassName != nil, "\(node.id)")
        }

        // P-HIER-10: a subtree gives the same addresses.
        let subtree = try XCTUnwrap(
            HierarchyCapture.captureSubtree(rootID: rootNode.id, in: .testing(windows: [window], registry: registry))
        )
        XCTAssertEqual(subtree.nodes.first, rootNode)
        XCTAssertEqual(
            try node(of: bare, in: subtree, registry: registry).layerAddress,
            address(of: bare)
        )
    }

    func test_S_HIER_13_addressesDoNotKeepObjectsAliveOrLoadViews() throws {
        let window = try makeWindow()
        let root = ScreenController()
        window.rootViewController = root
        let unloaded = DetailController()
        root.addChild(unloaded)
        unloaded.didMove(toParent: root)
        weak var view: UIView?
        weak var layer: CALayer?
        autoreleasepool {
            let strongView = UIView()
            let strongLayer = CALayer()
            strongView.layer.addSublayer(strongLayer)
            root.view.addSubview(strongView)
            view = strongView
            layer = strongLayer
            let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: LayerRegistry()))
            XCTAssertTrue(hierarchy.nodes.contains { $0.viewAddress == address(of: strongView) })
            XCTAssertTrue(hierarchy.nodes.contains { $0.layerAddress == address(of: strongLayer) })
            strongView.removeFromSuperview()
        }
        CATransaction.flush()
        XCTAssertNil(view, "the capture kept the view alive")
        XCTAssertNil(layer, "the capture kept the layer alive")
        XCTAssertFalse(unloaded.isViewLoaded, "the capture loaded a view")
    }
}
