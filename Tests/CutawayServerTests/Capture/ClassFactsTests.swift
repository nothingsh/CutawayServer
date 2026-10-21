import CutawayWire
import ObjectiveC
import SwiftUI
import UIKit
import XCTest

@testable import CutawayServer

private final class AppView: UIView {}
private final class AppGenericView<Element>: UIView {}
private final class AppLayer: CALayer {}
private final class Knob: UIControl {}
private final class Observed: UIView {
    @objc dynamic var level = 0
}

/// P-HIER-16, P-HIER-17: where classes come from, and their nearest known class.
@MainActor
final class ClassFactsTests: CaptureTestCase {
    private let version10 = ProtocolVersion(major: 1, minor: 0)

    // MARK: - Origins (P-HIER-16)

    func test_S_HIER_14_theAppsClassesAreTheApps() {
        // The test bundle lies in the test host's PlugIns, inside the .app.
        XCTAssertEqual(ClassOrigin.origin(of: AppView.self), .app)
        XCTAssertEqual(ClassOrigin.origin(of: AppLayer.self), .app)
        // A generic class's metadata is made at runtime; the Swift runtime still gives its image.
        XCTAssertEqual(ClassOrigin.origin(of: AppGenericView<Int>.self), .app)
        XCTAssertEqual(ClassOrigin.origin(of: AppGenericView<String>.self), .app)
    }

    func test_S_HIER_14_aClassMadeAtRuntimeTakesItsSuperclasssOrigin() throws {
        let observed = Observed()
        let token = observed.observe(\.level) { _, _ in }
        defer { token.invalidate() }
        let kvoClass: AnyClass = try XCTUnwrap(object_getClass(observed))
        XCTAssertNotIdentical(kvoClass, Observed.self, "observing did not change the class")
        XCTAssertNil(class_getImageName(kvoClass), "the KVO class has an image")
        XCTAssertEqual(ClassOrigin.origin(of: kvoClass), .app)

        // The same for a system class.
        let label = UILabel()
        let labelToken = label.observe(\.text) { _, _ in }
        defer { labelToken.invalidate() }
        XCTAssertEqual(ClassOrigin.origin(of: try XCTUnwrap(object_getClass(label))), .system)
    }

    func test_S_HIER_14_theSystemsClassesAreTheSystems() {
        let labelLayerClass: AnyClass = type(of: UILabel().layer)
        for type: AnyClass in [UILabel.self, UIView.self, CALayer.self, labelLayerClass, UIViewController.self] {
            XCTAssertEqual(ClassOrigin.origin(of: type), .system, NSStringFromClass(type))
        }
    }

    func test_S_HIER_14_theAppBundleIsTheAppThatContainsTheHost() {
        let app = URL(fileURLWithPath: "/data/Bundle/Application/X/Shop.app")
        XCTAssertEqual(ClassOrigin.appBundle(containing: app).path, app.path)
        // An extension: the app that contains it.
        XCTAssertEqual(
            ClassOrigin.appBundle(containing: app.appendingPathComponent("PlugIns/Share.appex")).path,
            app.path
        )
        // Not in an app at all: the directory itself.
        let elsewhere = URL(fileURLWithPath: "/usr/local/libexec/tool")
        XCTAssertEqual(ClassOrigin.appBundle(containing: elsewhere).path, elsewhere.path)

        // An image elsewhere is the system's, whatever its name.
        XCTAssertEqual(
            ClassOrigin.origin(of: AppView.self, appBundlePrefix: "/nowhere/Other.app/"),
            .system
        )
    }

    func test_S_HIER_14_nodesGiveTheOriginsOfTheirClasses() throws {
        let window = try makeWindow()
        let root = UIViewController()
        window.rootViewController = root
        let mine = AppView()
        let label = UILabel()
        let layer = AppLayer()
        root.view.addSubview(mine)
        root.view.addSubview(label)
        mine.layer.addSublayer(layer)
        window.layoutIfNeeded()

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        let mineNode = try node(of: mine.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(mineNode.layerClassOrigin, .system)
        XCTAssertEqual(mineNode.viewClassOrigin, .app)
        let labelNode = try node(of: label.layer, in: hierarchy, registry: registry)
        XCTAssertEqual([labelNode.layerClassOrigin, labelNode.viewClassOrigin], [.system, .system])
        let layerNode = try node(of: layer, in: hierarchy, registry: registry)
        XCTAssertEqual([layerNode.layerClassOrigin, layerNode.viewClassOrigin], [.app, .unknown])
        let rootNode = try node(of: root.view.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(rootNode.viewControllerClassOrigin, .system)

        // Given exactly when the class names are, and then never unknown.
        for node in hierarchy.nodes {
            XCTAssertNotEqual(node.layerClassOrigin, .unknown, "\(node.id)")
            XCTAssertEqual(node.viewClassOrigin != .unknown, node.viewClassName != nil, "\(node.id)")
            XCTAssertEqual(
                node.viewControllerClassOrigin != .unknown,
                node.viewControllerClassName != nil,
                "\(node.id)"
            )
        }

        // P-HIER-10: a subtree gives the same.
        let subtree = try XCTUnwrap(
            HierarchyCapture.captureSubtree(rootID: mineNode.id, in: .testing(windows: [window], registry: registry))
        )
        XCTAssertEqual(subtree.nodes.first, mineNode)
    }

    // MARK: - Known classes (P-HIER-17)

    func test_S_HIER_15_eachKnownClassAndItsSubclassesGetItsName() throws {
        let bases = KnownBaseClasses(version: .current)
        var checked = 0
        for (entries, name) in [(KnownClasses.views, "view"), (KnownClasses.layers, "layer")] {
            for entry in entries where entry.name != KnownClasses.hostingView {
                // WebKit and MapKit are not linked by the test host.
                guard let type = NSClassFromString(entry.name) else { continue }
                let subclassName = "CutawayTestSubclassOf\(entry.name)"
                let subclass: AnyClass
                if let made = objc_allocateClassPair(type, subclassName, 0) {
                    objc_registerClassPair(made)
                    subclass = made
                } else {
                    subclass = try XCTUnwrap(NSClassFromString(subclassName))
                }
                let lookup = name == "view" ? bases.viewName(of:) : bases.layerName(of:)
                XCTAssertEqual(lookup(type), entry.name, entry.name)
                XCTAssertEqual(lookup(subclass), entry.name, "a subclass of \(entry.name)")
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, KnownClasses.views.count + KnownClasses.layers.count - 3)
    }

    func test_S_HIER_15_theNearestKnownClassWins() {
        let bases = KnownBaseClasses(version: .current)
        // UIControl is in the table, and Knob is no more specific class of it.
        XCTAssertEqual(bases.viewName(of: Knob.self), "UIControl")
        XCTAssertEqual(bases.viewName(of: UIButton.self), "UIButton")
        XCTAssertEqual(bases.viewName(of: UITextView.self), "UITextView")
        XCTAssertEqual(bases.viewName(of: UITableView.self), "UITableView")
        // Neither table holds the roots.
        XCTAssertNil(bases.viewName(of: UIView.self))
        XCTAssertNil(bases.viewName(of: AppView.self))
        XCTAssertNil(bases.layerName(of: CALayer.self))
        XCTAssertNil(bases.layerName(of: AppLayer.self))
    }

    func test_S_HIER_15_viewsThatHostSwiftUIAreHostingViews() throws {
        let bases = KnownBaseClasses(version: .current)
        let controller = UIHostingController(rootView: Text("Hello"))
        XCTAssertEqual(bases.viewName(of: type(of: try XCTUnwrap(controller.view))), "UIHostingView")

        guard #available(iOS 16, *) else { return }
        let cell = UICollectionViewListCell()
        cell.contentConfiguration = UIHostingConfiguration { Text("Hello") }
        let content = try XCTUnwrap(
            cell.contentView as UIView?,
            "a hosting configuration replaces the content view"
        )
        XCTAssertEqual(bases.viewName(of: type(of: content)), "UIHostingView")
        // Not every view of SwiftUI's is a host.
        XCTAssertNil(bases.viewName(of: UIView.self))
    }

    func test_S_HIER_15_nodesGiveTheirNearestKnownClasses() throws {
        let window = try makeWindow()
        let label = UILabel()
        let mine = AppView()
        let shape = CAShapeLayer()
        window.addSubview(label)
        window.addSubview(mine)
        mine.layer.addSublayer(shape)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        let windowNode = try node(of: window.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(windowNode.viewBaseClassName, "UIWindow")
        let labelNode = try node(of: label.layer, in: hierarchy, registry: registry)
        XCTAssertEqual(labelNode.viewBaseClassName, "UILabel")
        XCTAssertNil(labelNode.layerBaseClassName)
        XCTAssertNil(try node(of: mine.layer, in: hierarchy, registry: registry).viewBaseClassName)
        let shapeNode = try node(of: shape, in: hierarchy, registry: registry)
        XCTAssertEqual(shapeNode.layerBaseClassName, "CAShapeLayer")
        // Only for a layer that backs a view.
        XCTAssertNil(shapeNode.viewBaseClassName)
        for node in hierarchy.nodes where node.viewClassName == nil {
            XCTAssertNil(node.viewBaseClassName, "\(node.id)")
        }

        // A 1.0 client knows no table: neither is given.
        let old = HierarchyCapture.capture(.testing(windows: [window], registry: registry, version: version10))
        for node in old.nodes {
            XCTAssertNil(node.viewBaseClassName, "\(node.id)")
            XCTAssertNil(node.layerBaseClassName, "\(node.id)")
        }
        let oldSubtree = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: labelNode.id,
                in: .testing(windows: [window], registry: registry, version: version10)
            )
        )
        XCTAssertNil(oldSubtree.nodes.first?.viewBaseClassName)
    }
}
