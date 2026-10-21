import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// The names of registered colors on color values (S-ATTR-25). No server, no connection.
final class ColorNameTests: CaptureTestCase {
    private let registry = LayerRegistry()
    private let brand = UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    /// Light: `brand`; dark: another color.
    private lazy var dynamicBrand = UIColor { [brand] traits in
        traits.userInterfaceStyle == .dark ? UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1) : brand
    }

    private struct Scene {
        let window: UIWindow
        let view: UIView
        let layer: CALayer
    }

    /// A light window with a view, and a bare layer inside the view.
    private func makeScene() throws -> Scene {
        let window = try makeWindow()
        window.overrideUserInterfaceStyle = .light
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        let layer = CALayer()
        layer.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        view.layer.addSublayer(layer)
        window.addSubview(view)
        window.layoutIfNeeded()
        return Scene(window: window, view: view, layer: layer)
    }

    private func groups(of layer: CALayer, in scene: Scene, store: ExtensionStore) -> [CutawayWire.AttributeGroup] {
        NodeAttributes(context: .testing(windows: [scene.window], registry: registry, extensions: store)).read(layer)
    }

    private func name(_ id: String, in groups: [CutawayWire.AttributeGroup]) -> String? {
        guard case .color(_, _, _, _, let name)? = groups.flatMap(\.attributes).first(where: { $0.id == id })?.value
        else {
            return nil
        }
        return name
    }

    private func colors(in groups: [CutawayWire.AttributeGroup]) -> [String] {
        groups.flatMap(\.attributes).compactMap { attribute in
            guard case .color? = attribute.value else { return nil }
            return attribute.id
        }
    }

    func test_S_ATTR_25_aViewsColorEqualToARegisteredOneIsNamed() throws {
        let scene = try makeScene()
        let store = ExtensionStore()
        store.registerColor(.green, named: "go")
        store.registerColor(dynamicBrand, named: "brand")
        // The same color, another object.
        scene.view.backgroundColor = UIColor { [brand] traits in
            traits.userInterfaceStyle == .dark ? UIColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1) : brand
        }
        let groups = groups(of: scene.view.layer, in: scene, store: store)
        XCTAssertEqual(name("view.backgroundColor", in: groups), "brand")
        // Other colors of the view are not.
        for id in colors(in: groups) where id != "view.backgroundColor" {
            XCTAssertNil(name(id, in: groups), id)
        }
    }

    func test_S_ATTR_25_aLayersCGColorIsNamedByAColorThatDoesNotChange() throws {
        let scene = try makeScene()
        let store = ExtensionStore()
        store.registerColor(brand, named: "brand")
        scene.layer.borderColor = brand.cgColor
        XCTAssertEqual(name("layer.borderColor", in: groups(of: scene.layer, in: scene, store: store)), "brand")
    }

    func test_S_ATTR_25_aFixedColorIsNotADynamicOne() throws {
        let scene = try makeScene()
        let store = ExtensionStore()
        store.registerColor(dynamicBrand, named: "brand")
        // Equal in light, the appearance the window has, but without a dark side.
        scene.view.backgroundColor = brand
        scene.layer.borderColor = brand.cgColor
        XCTAssertNil(name("view.backgroundColor", in: groups(of: scene.view.layer, in: scene, store: store)))
        XCTAssertNil(name("layer.borderColor", in: groups(of: scene.layer, in: scene, store: store)))
    }

    func test_S_ATTR_25_ofSeveralEqualColorsTheFirstRegistered() throws {
        let scene = try makeScene()
        let store = ExtensionStore()
        store.registerColor(.red, named: "alert")
        store.registerColor(brand, named: "primary")
        store.registerColor(UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1), named: "accent")
        scene.view.backgroundColor = brand
        XCTAssertEqual(
            name("view.backgroundColor", in: groups(of: scene.view.layer, in: scene, store: store)),
            "primary"
        )
    }

    func test_S_ATTR_25_withoutRegisteredColorsNoNames() throws {
        let scene = try makeScene()
        scene.view.backgroundColor = brand
        let store = ExtensionStore()
        store.describe(UIView.self, CutawayServer.Description(isCollapsedByDefault: true), isView: true)
        for groups in [
            groups(of: scene.view.layer, in: scene, store: store),
            groups(of: scene.view.layer, in: scene, store: ExtensionStore())
        ] {
            for id in colors(in: groups) {
                XCTAssertNil(name(id, in: groups), id)
            }
        }
    }

    func test_S_ATTR_25_theAppsColorsAreNamedToo() throws {
        let scene = try makeScene()
        let store = ExtensionStore()
        store.registerColor(dynamicBrand, named: "brand")
        store.describe(
            UIView.self,
            CutawayServer.Description(attributes: { [dynamicBrand] _ in
                [CutawayServer.AttributeGroup("chart", [.color("barColor", dynamicBrand), .color("lineColor", .black)])]
            }),
            isView: true
        )
        let groups = groups(of: scene.view.layer, in: scene, store: store)
        XCTAssertEqual(name("app.chart.barColor", in: groups), "brand")
        XCTAssertNil(name("app.chart.lineColor", in: groups))
        // The registered color resolves with the view's traits: in dark it is still equal.
        scene.window.overrideUserInterfaceStyle = .dark
        XCTAssertEqual(
            name("app.chart.barColor", in: self.groups(of: scene.view.layer, in: scene, store: store)),
            "brand"
        )
    }

    // MARK: - Resolving the registered colors

    func test_S_ATTR_25_aRequestResolvesARegisteredColorOnceForEachTraitCollection() throws {
        let scene = try makeScene()
        let store = ExtensionStore()
        let count = ResolveCount()
        store.registerColor(UIColor { [brand] _ in
            count.increment()
            return brand
        }, named: "brand")
        scene.view.backgroundColor = brand
        // The layers of one request for details share its memo; each has a context of its own.
        let memo = RequestMemo()
        func read(in memo: RequestMemo) -> [CutawayWire.AttributeGroup] {
            let context = RequestContext(
                windows: [scene.window],
                registry: registry,
                version: .current,
                extensions: store,
                memo: memo
            )
            return NodeAttributes(context: context).read(scene.view.layer)
        }
        XCTAssertEqual(name("view.backgroundColor", in: read(in: memo)), "brand")
        let first = count.value
        XCTAssertGreaterThan(first, 0)
        // Another layer of the same request resolves nothing again.
        XCTAssertEqual(name("view.backgroundColor", in: read(in: memo)), "brand")
        XCTAssertEqual(count.value, first)
        // Other traits: resolved for them.
        scene.window.overrideUserInterfaceStyle = .dark
        scene.window.layoutIfNeeded()
        XCTAssertEqual(name("view.backgroundColor", in: read(in: memo)), "brand")
        let second = count.value
        XCTAssertGreaterThan(second, first)
        // Once something is registered again, resolved anew.
        store.registerColor(.green, named: "go")
        XCTAssertEqual(name("view.backgroundColor", in: read(in: memo)), "brand")
        let third = count.value
        XCTAssertGreaterThan(third, second)
        // The next request resolves it again, though nothing changed: the color may depend on
        // more than the traits.
        XCTAssertEqual(name("view.backgroundColor", in: read(in: RequestMemo())), "brand")
        XCTAssertGreaterThan(count.value, third)
    }

    func test_S_ATTR_25_groupsWithoutColorsResolveNothing() throws {
        let scene = try makeScene()
        let store = ExtensionStore()
        let count = ResolveCount()
        store.registerColor(UIColor { [brand] _ in
            count.increment()
            return brand
        }, named: "brand")
        let groups = [
            CutawayWire.AttributeGroup(
                id: "app.chart",
                title: "Chart",
                attributes: [
                    CutawayWire.Attribute(id: "app.chart.count", title: "Count", value: .int(3), valueKind: .int)
                ],
                className: "Chart",
                fromApp: true
            )
        ]
        let named = ColorNames.named(
            groups,
            registered: ColorNames.Registered(store),
            cache: ColorNames.Cache(),
            in: scene.view
        )
        XCTAssertEqual(named, groups)
        XCTAssertEqual(count.value, 0)
    }
}

/// How often a registered color was resolved. UIKit may call a color's provider on any thread.
private final class ResolveCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }
}
