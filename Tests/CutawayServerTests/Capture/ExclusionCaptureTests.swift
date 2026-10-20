import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// A view the host app excludes from images, for example because it shows a card number.
final class PaymentCardView: UIView {}

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
        _ = HierarchyCapture.capture(windows: [window], registry: registry, extensions: store)
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
                windows: [scene.window],
                registry: registry,
                stopFlag: StopFlag(),
                screenScale: 1,
                extensions: scene.store,
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
                windows: [scene.window],
                registry: registry,
                stopFlag: StopFlag(),
                screenScale: 1,
                extensions: plain,
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

    func test_S_SHOT_13_excludedLayersAreFoundWithoutLookingBelowThem() throws {
        let scene = try makeScene()
        let lookup = ExtensionLookup(store: scene.store)
        XCTAssertEqual(
            DetailCapture.excludedLayers(below: scene.window.layer, lookup: lookup).map(ObjectIdentifier.init),
            [ObjectIdentifier(scene.card.layer)]
        )
    }
}
