import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// A view the host app excludes from images, for example because it shows a card number.
private final class PaymentCardView: UIView {}

/// The details of virtual nodes, and of nodes excluded from images (S-SHOT-12, S-SHOT-13).
/// No server, no connection.
final class ExclusionCaptureTests: CaptureTestCase {
    private let registry = LayerRegistry()
    private let white = pixelBytes(red: 1, green: 1, blue: 1)
    private let red = pixelBytes(red: 1, green: 0, blue: 0)
    private let blue = pixelBytes(red: 0, green: 0, blue: 1)

    /// A white 200 x 100 container in a window: a red card at (10, 10) of 50 x 50 with a blue
    /// label at (5, 5) of 10 x 10 inside it, and a chart of two bars at (100, 10). The store
    /// excludes cards and describes charts.
    private struct Scene {
        let window: UIWindow
        let container: UIView
        let card: PaymentCardView
        let label: UIView
        let chart: BarChartView
        let store: ExtensionStore
    }

    private func makeScene() throws -> Scene {
        let window = try makeWindow()
        let container = colorView(CGRect(x: 0, y: 0, width: 200, height: 100), red: 1, green: 1, blue: 1)
        let card = PaymentCardView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        card.backgroundColor = .red
        let label = colorView(CGRect(x: 5, y: 5, width: 10, height: 10), red: 0, green: 0, blue: 1)
        card.addSubview(label)
        let chart = BarChartView(frame: CGRect(x: 100, y: 10, width: 60, height: 60))
        chart.bars = [
            BarChartView.Bar(id: "march", value: 40, parts: ["low"]),
            BarChartView.Bar(id: "april", value: 20)
        ]
        container.addSubview(card)
        container.addSubview(chart)
        window.addSubview(container)
        let store = ExtensionStore()
        store.describe(PaymentCardView.self, CutawayServer.Description(isExcludedFromCapture: true), isView: true)
        store.describe(BarChartView.self, BarChartView.description, isView: true)
        // The IDs of the virtual nodes are given out by a hierarchy.
        _ = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        return Scene(window: window, container: container, card: card, label: label, chart: chart, store: store)
    }

    private func capture(
        _ layerID: UInt64,
        in scene: Scene,
        solo: Bool = false,
        group: Bool = false,
        attributes: Bool = false,
        constraints: Bool = false
    ) throws -> CapturedDetail {
        try XCTUnwrap(
            DetailCapture.capture(
                LayerDetailRequest(
                    layerID: layerID,
                    wantSolo: solo,
                    wantGroup: group,
                    wantAttributes: attributes,
                    wantConstraints: constraints
                ),
                maxTextureDimension: 0,
                in: .testing(windows: [scene.window], registry: registry, extensions: scene.store),
                stopFlag: StopFlag(),
                screenScale: 1,
                readAttributes: { _ in [AttributeGroup(id: "layer", title: "Layer", attributes: [])] }
            )
        )
    }

    private func virtualID(_ identity: AnyHashable, under view: UIView) throws -> UInt64 {
        try XCTUnwrap(
            registry.virtualIDs[LayerRegistry.VirtualKey(layerID: registry.register(view.layer), identity: identity)]
        )
    }

    // MARK: - S-SHOT-12

    func test_S_SHOT_12_aVirtualNodeHasNoImagesConstraintsOrGroupsOfTheServer() throws {
        let scene = try makeScene()
        for id in [try virtualID("march", under: scene.chart), try virtualID("low", under: scene.chart)] {
            let detail = try capture(id, in: scene, solo: true, group: true, attributes: true, constraints: true)
            XCTAssertEqual(detail.status, .ok)
            XCTAssertNil(detail.solo)
            XCTAssertNil(detail.group)
            XCTAssertEqual(detail.constraints, [])
            // Never the server's own; the host app's are read by `readVirtualAttributes`
            // (AppAttributesTests).
            XCTAssertEqual(detail.attributeGroups.map(\.id), [])
        }
    }

    func test_S_SHOT_12_aVirtualNodeThatIsGoneIsNotFound() throws {
        let scene = try makeScene()
        let april = try virtualID("april", under: scene.chart)
        scene.chart.bars.removeLast()
        XCTAssertEqual(try capture(april, in: scene, attributes: true).status, .layerNotFound)
        let march = try virtualID("march", under: scene.chart)
        scene.chart.removeFromSuperview()
        XCTAssertEqual(try capture(march, in: scene).status, .layerNotFound)
    }

    // MARK: - S-SHOT-13

    func test_S_SHOT_13_anExcludedNodeIsExcludedWithItsAttributes() throws {
        let scene = try makeScene()
        for layer in [scene.card.layer, scene.label.layer] {
            let id = registry.register(layer)
            let detail = try capture(id, in: scene, solo: true, group: true, attributes: true)
            XCTAssertEqual(detail.status, .excluded, "\(layer)")
            XCTAssertNil(detail.solo)
            XCTAssertNil(detail.group)
            XCTAssertEqual(detail.attributeGroups.map(\.id), ["layer"])
            // Also when no image is requested.
            XCTAssertEqual(try capture(id, in: scene, attributes: true).status, .excluded)
            XCTAssertEqual(try capture(id, in: scene).status, .excluded)
        }
    }

    func test_S_SHOT_13_aVirtualNodeBelowAnExcludedLayerIsExcluded() throws {
        let scene = try makeScene()
        var description = BarChartView.description
        description.isExcludedFromCapture = true
        scene.store.describe(BarChartView.self, description, isView: true)
        let detail = try capture(try virtualID("march", under: scene.chart), in: scene, group: true)
        XCTAssertEqual(detail.status, .excluded)
        XCTAssertNil(detail.group)
    }

    func test_S_SHOT_13_otherImagesLeaveTheExcludedLayersOut() throws {
        let scene = try makeScene()
        let detail = try capture(registry.register(scene.container.layer), in: scene, group: true)
        XCTAssertEqual(detail.status, .ok)
        let image = try XCTUnwrap(detail.group)
        // Where the card and its label are, the container's white; the chart is still there.
        assertPixel(image.pixel(atPoint: 30, 30), white)
        assertPixel(image.pixel(atPoint: 17, 17), white)
        // Without the description the card is drawn.
        let plain = ExtensionStore()
        let unexcluded = try XCTUnwrap(
            DetailCapture.capture(
                LayerDetailRequest(
                    layerID: registry.register(scene.container.layer),
                    wantSolo: false,
                    wantGroup: true,
                    wantAttributes: false
                ),
                maxTextureDimension: 0,
                in: .testing(windows: [scene.window], registry: registry, extensions: plain),
                stopFlag: StopFlag(),
                screenScale: 1,
                readAttributes: { _ in [] }
            )?.group
        )
        assertPixel(unexcluded.pixel(atPoint: 30, 30), red)
        assertPixel(unexcluded.pixel(atPoint: 17, 17), blue)
        // The window's own group leaves it out too.
        let window = try XCTUnwrap(try capture(registry.register(scene.window.layer), in: scene, group: true).group)
        assertPixel(window.pixel(atPoint: 30, 30), white)
    }

    func test_S_SHOT_13_capturingLeavesTheExcludedLayersAsTheyWere() throws {
        let scene = try makeScene()
        let hiddenCard = PaymentCardView(frame: CGRect(x: 70, y: 70, width: 10, height: 10))
        hiddenCard.isHidden = true
        scene.container.addSubview(hiddenCard)
        scene.window.layoutIfNeeded()
        CATransaction.flush()
        let picture = try render(scene.window)
        _ = try capture(registry.register(scene.container.layer), in: scene, group: true)
        XCTAssertFalse(scene.card.isHidden)
        XCTAssertFalse(scene.card.layer.isHidden)
        XCTAssertTrue(hiddenCard.isHidden)
        for layer in [scene.card.layer, scene.label.layer, hiddenCard.layer, scene.container.layer] {
            XCTAssertEqual(layer.animationKeys() ?? [], [], "\(layer)")
        }
        XCTAssertEqual(try render(scene.window), picture)
    }

    /// Hiding excluded layers for the time of a capture, deep inside a stack view or as one of
    /// its arranged subviews, lays nothing out, then or later.
    func test_S_SHOT_13_hidingExcludedLayersInAStackViewLaysNothingOut() throws {
        let window = try makeWindow()
        // A white container with a horizontal stack of four views, each 75 points wide: the
        // second holds a red card at (10, 10), the third is a red card itself.
        let container = colorView(CGRect(x: 10, y: 10, width: 300, height: 100), red: 1, green: 1, blue: 1)
        let stack = UIStackView(frame: container.bounds)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        let counted = (0..<3).map { _ -> CountingView in
            let view = CountingView()
            view.backgroundColor = .white
            return view
        }
        let arrangedCard = PaymentCardView()
        arrangedCard.backgroundColor = .red
        for view in [counted[0], counted[1], arrangedCard, counted[2]] as [UIView] { stack.addArrangedSubview(view) }
        let deepCard = PaymentCardView(frame: CGRect(x: 10, y: 10, width: 20, height: 20))
        deepCard.backgroundColor = .red
        counted[1].addSubview(deepCard)
        container.addSubview(stack)
        window.addSubview(container)
        window.layoutIfNeeded()
        CATransaction.flush()
        let store = ExtensionStore()
        store.describe(PaymentCardView.self, CutawayServer.Description(isExcludedFromCapture: true), isView: true)
        func group(with store: ExtensionStore) throws -> RawImage {
            try XCTUnwrap(
                DetailCapture.capture(
                    LayerDetailRequest(
                        layerID: registry.register(container.layer),
                        wantSolo: false,
                        wantGroup: true,
                        wantAttributes: false
                    ),
                    maxTextureDimension: 0,
                    in: .testing(windows: [window], registry: registry, extensions: store),
                    stopFlag: StopFlag(),
                    screenScale: 1,
                    readAttributes: { _ in [] }
                )?.group
            )
        }
        // Without the description both cards are drawn.
        let plain = try group(with: ExtensionStore())
        assertPixel(plain.pixel(atPoint: 90, 15), red)
        assertPixel(plain.pixel(atPoint: 185, 50), red)

        let views: [UIView] = [container, stack, arrangedCard, deepCard] + counted.map { $0 as UIView }
        let frames = views.map(\.frame)
        let layouts = counted.map(\.layoutCount)
        let needsLayout = views.map { $0.layer.needsLayout() }
        let picture = try render(window)

        let image = try group(with: store)
        assertPixel(image.pixel(atPoint: 90, 15), white)
        assertPixel(image.pixel(atPoint: 185, 50), white)

        XCTAssertEqual(counted.map(\.layoutCount), layouts, "laid out")
        XCTAssertEqual(views.map { $0.layer.needsLayout() }, needsLayout, "needs layout")
        XCTAssertFalse(views.contains { $0.isHidden || $0.layer.isHidden })
        for view in views {
            XCTAssertEqual(view.layer.animationKeys() ?? [], [], "\(view)")
        }
        window.layoutIfNeeded()
        CATransaction.flush()
        XCTAssertEqual(counted.map(\.layoutCount), layouts, "laid out later")
        XCTAssertEqual(views.map(\.frame), frames)
        XCTAssertEqual(try render(window), picture)
    }

    func test_S_SHOT_13_excludedLayersAreFoundWithoutLookingBelowThem() throws {
        let scene = try makeScene()
        let lookup = ExtensionLookup(store: scene.store)
        XCTAssertEqual(
            DetailCapture.excludedLayers(below: scene.window.layer, lookup: lookup).map(ObjectIdentifier.init),
            [ObjectIdentifier(scene.card.layer)]
        )
    }

    func test_S_SHOT_13_withoutExclusionsTheSubtreeIsNotSearched() throws {
        let window = try makeWindow()
        let container = colorView(CGRect(x: 0, y: 0, width: 100, height: 100), red: 1, green: 1, blue: 1)
        let below = CountingLayer()
        below.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        container.layer.addSublayer(below)
        window.addSubview(container)
        let id = registry.register(container.layer)
        // How often the layer below was asked for its sublayers while the group was captured;
        // the rendering is left out, since it looks at every layer.
        func searches(with store: ExtensionStore) throws -> Int {
            below.sublayerReads = 0
            let detail = try XCTUnwrap(
                DetailCapture.capture(
                    LayerDetailRequest(layerID: id, wantSolo: false, wantGroup: true, wantAttributes: false),
                    maxTextureDimension: 0,
                    in: .testing(windows: [window], registry: registry, extensions: store),
                    stopFlag: StopFlag(),
                    screenScale: 1,
                    readAttributes: { _ in [] },
                    render: { _, _, plan in
                        RawImage(
                            pixelWidth: plan.pixelWidth,
                            pixelHeight: plan.pixelHeight,
                            bytesPerRow: plan.pixelWidth * 4,
                            scale: plan.scale,
                            pixels: Data(count: plan.pixelWidth * plan.pixelHeight * 4)
                        )
                    }
                )
            )
            XCTAssertEqual(detail.status, .ok)
            XCTAssertNotNil(detail.group)
            return below.sublayerReads
        }
        // Something registered, but nothing excluded: a color, a description that excludes
        // nothing, one that no longer excludes.
        let colorOnly = ExtensionStore()
        colorOnly.registerColor(.red, named: "red")
        XCTAssertEqual(try searches(with: colorOnly), 0)
        let collapsed = ExtensionStore()
        collapsed.describe(UIView.self, CutawayServer.Description(isCollapsedByDefault: true), isView: true)
        XCTAssertEqual(try searches(with: collapsed), 0)
        let replaced = ExtensionStore()
        replaced.describe(PaymentCardView.self, CutawayServer.Description(isExcludedFromCapture: true), isView: true)
        replaced.describe(PaymentCardView.self, CutawayServer.Description(), isView: true)
        XCTAssertEqual(try searches(with: replaced), 0)
        // Some class excluded, though none of these layers is of it: the subtree is searched.
        let excluding = ExtensionStore()
        excluding.describe(PaymentCardView.self, CutawayServer.Description(isExcludedFromCapture: true), isView: true)
        XCTAssertEqual(try searches(with: excluding), 1)
    }
}

/// A layer that counts how often it is asked for its sublayers.
private final class CountingLayer: CALayer {
    var sublayerReads = 0

    override var sublayers: [CALayer]? {
        get {
            sublayerReads += 1
            return super.sublayers
        }
        set { super.sublayers = newValue }
    }
}
