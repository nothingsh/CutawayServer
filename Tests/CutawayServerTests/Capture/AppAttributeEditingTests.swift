import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// A chart that draws its bars itself, bottom up, each 20 points wide; the host app describes
/// each bar as a virtual node whose value can be changed.
final class DrawnChartView: UIView {
    struct Bar {
        var id: String
        var value: Double
    }

    struct TooTall: LocalizedError {
        var errorDescription: String? { "the bar would be taller than the chart" }
    }

    var bars: [Bar] = [] {
        didSet { setNeedsDisplay() }
    }

    var barColor = UIColor.blue {
        didSet { setNeedsDisplay() }
    }

    /// The values `set` received, in order.
    var written: [String] = []

    override func draw(_ rect: CGRect) {
        UIColor.white.setFill()
        UIRectFill(bounds)
        barColor.setFill()
        for (index, bar) in bars.enumerated() {
            UIRectFill(CGRect(x: Double(index) * 20, y: bounds.height - bar.value, width: 20, height: bar.value))
        }
    }

    static let description = CutawayServer.Description<DrawnChartView>(
        attributes: { chart in
            [
                CutawayServer.AttributeGroup("chart", [
                    .int("barCount", chart.bars.count),
                    .color("barColor", chart.barColor, section: .appearance, set: { color in
                        chart.written.append("barColor")
                        chart.barColor = color ?? .blue
                    })
                ])
            ]
        },
        virtualChildren: { chart in
            chart.bars.indices.map { index in
                CutawayServer.VirtualNode(
                    id: chart.bars[index].id,
                    typeName: "Bar",
                    frame: CGRect(
                        x: Double(index) * 20,
                        y: chart.bounds.height - chart.bars[index].value,
                        width: 20,
                        height: chart.bars[index].value
                    ),
                    attributes: [
                        CutawayServer.AttributeGroup("bar", [
                            .double(
                                "value",
                                chart.bars[index].value,
                                section: .content,
                                unit: .points,
                                limits: [.atLeast(0)],
                                set: { value in
                                    chart.written.append("value \(value ?? .nan)")
                                    guard let value, value <= chart.bounds.height else { throw TooTall() }
                                    chart.bars[index].value = value
                                }
                            )
                        ])
                    ]
                )
            }
        }
    )
}

/// Changing the host app's attributes (S-SET-08). No server, no connection: every test calls
/// `AttributeEditing.apply` on the main thread.
final class AppAttributeEditingTests: CaptureTestCase {
    private let registry = LayerRegistry()
    private let white = pixelBytes(red: 1, green: 1, blue: 1)
    private let blue = pixelBytes(red: 0, green: 0, blue: 1)
    private let red = pixelBytes(red: 1, green: 0, blue: 0)

    private struct Scene {
        let window: UIWindow
        let chart: DrawnChartView
        let store: ExtensionStore
    }

    /// A drawn 100 x 100 chart of two bars, 40 and 60 tall, in a window; its virtual nodes have
    /// their IDs.
    private func makeScene() throws -> Scene {
        let window = try makeWindow()
        let chart = DrawnChartView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        chart.bars = [DrawnChartView.Bar(id: "march", value: 40), DrawnChartView.Bar(id: "april", value: 60)]
        window.addSubview(chart)
        window.layoutIfNeeded()
        chart.layer.displayIfNeeded()
        CATransaction.flush()
        let store = ExtensionStore()
        store.describe(DrawnChartView.self, DrawnChartView.description, isView: true)
        _ = HierarchyCapture.capture(windows: [window], registry: registry, extensions: store)
        return Scene(window: window, chart: chart, store: store)
    }

    private func barID(_ identity: String, in scene: Scene) throws -> UInt64 {
        try XCTUnwrap(
            registry.virtualIDs[LayerRegistry.VirtualKey(
                layerID: registry.register(scene.chart.layer),
                identity: identity
            )]
        )
    }

    private func apply(_ id: String, _ value: AttributeValue?, on layerID: UInt64, in scene: Scene)
        -> Result<SetAttributeResult, WireError> {
        AttributeEditing.apply(
            SetAttribute(layerID: layerID, attributeID: id, value: value),
            windows: [scene.window],
            registry: registry,
            appState: .active,
            extensions: scene.store
        )
    }

    private func value(_ id: String, in result: Result<SetAttributeResult, WireError>) throws -> AttributeValue? {
        let answer = try result.get()
        return try XCTUnwrap(answer.attributeGroups.flatMap(\.attributes).first { $0.id == id }, "no \(id)").value
    }

    private func assertRefused(
        _ result: Result<SetAttributeResult, WireError>,
        _ code: ErrorCode,
        message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .failure(let error) = result else { return XCTFail("accepted", file: file, line: line) }
        XCTAssertEqual(error.code, code, error.message, file: file, line: line)
        if let message { XCTAssertEqual(error.message, message, file: file, line: line) }
    }

    private func group(of layer: CALayer) throws -> RawImage {
        let plan = try XCTUnwrap(ImageSizing.plan(bounds: layer.bounds, screenScale: 1, maxTextureDimension: 0))
        return try XCTUnwrap(LayerRenderer.render(layer, mode: .group, plan: plan))
    }

    // MARK: - A view's attributes

    func test_S_SET_08_theAppsSetGetsTheValueAndTheAnswerHasIt() throws {
        let scene = try makeScene()
        let chartID = registry.register(scene.chart.layer)
        let result = apply(
            "app.chart.barColor",
            .color(WireColor(red: 1, green: 0, blue: 0, alpha: 1)),
            on: chartID,
            in: scene
        )
        XCTAssertEqual(scene.chart.written, ["barColor"])
        guard case .color(let color, _, _, _, _)? = try value("app.chart.barColor", in: result) else {
            return XCTFail("no color")
        }
        XCTAssertEqual(color, WireColor(red: 1, green: 0, blue: 0, alpha: 1))
        // The answer holds every group of the layer, the server's first.
        XCTAssertEqual(try result.get().attributeGroups.first?.id, "layer")
        // Redrawn before the answer, without an animation.
        assertPixel(try group(of: scene.chart.layer).pixel(atPoint: 10, 90), red)
        XCTAssertEqual(scene.chart.layer.animationKeys() ?? [], [])
    }

    func test_S_SET_08_unknownAndReadOnlyAttributesAreNotEditable() throws {
        let scene = try makeScene()
        let chartID = registry.register(scene.chart.layer)
        assertRefused(apply("app.chart.missing", .int(1), on: chartID, in: scene), .attributeNotEditable)
        assertRefused(apply("app.chart.barCount", .int(1), on: chartID, in: scene), .attributeNotEditable)
        // Without the description the group is not there.
        let plain = AttributeEditing.apply(
            SetAttribute(layerID: chartID, attributeID: "app.chart.barColor", value: nil),
            windows: [scene.window],
            registry: registry,
            appState: .active
        )
        assertRefused(plain, .attributeNotEditable)
        XCTAssertEqual(scene.chart.written, [])
    }

    // MARK: - A virtual node's attributes

    func test_S_SET_08_writingAVirtualNodeRedrawsItsLayer() throws {
        let scene = try makeScene()
        let march = try barID("march", in: scene)
        // The first bar is 40 tall: white at 70 points from the top.
        assertPixel(try group(of: scene.chart.layer).pixel(atPoint: 10, 30), white)
        let result = apply("app.bar.value", .double(90), on: march, in: scene)
        XCTAssertEqual(try value("app.bar.value", in: result), .double(90))
        XCTAssertEqual(try result.get().attributeGroups.map(\.id), ["app.bar"])
        XCTAssertEqual(scene.chart.written, ["value 90.0"])
        XCTAssertEqual(scene.chart.bars[0].value, 90)
        // Before anything is committed: the image of the chart and of the window show it.
        assertPixel(try group(of: scene.chart.layer).pixel(atPoint: 10, 30), blue)
        assertPixel(try group(of: scene.window.layer).pixel(atPoint: 10, 30), blue)
        XCTAssertFalse(scene.chart.layer.needsDisplay())
        XCTAssertEqual(scene.chart.layer.animationKeys() ?? [], [])
    }

    func test_S_SET_08_theAppsRefusalIsInvalidWithItsDescription() throws {
        let scene = try makeScene()
        let march = try barID("march", in: scene)
        assertRefused(
            apply("app.bar.value", .double(500), on: march, in: scene),
            .invalidAttributeValue,
            message: "the bar would be taller than the chart"
        )
        XCTAssertEqual(scene.chart.written, ["value 500.0"])
        XCTAssertEqual(scene.chart.bars[0].value, 40)
    }

    func test_S_SET_08_theServersChecksComeBeforeTheApps() throws {
        let scene = try makeScene()
        let march = try barID("march", in: scene)
        // Below the limit, of another kind, nil, not finite.
        for value: AttributeValue? in [.double(-1), .string("tall"), nil, .double(.infinity)] {
            assertRefused(apply("app.bar.value", value, on: march, in: scene), .invalidAttributeValue)
        }
        XCTAssertEqual(scene.chart.written, [])
    }

    func test_S_SET_08_aVirtualNodeHasNoAttributesOfTheServer() throws {
        let scene = try makeScene()
        let march = try barID("march", in: scene)
        assertRefused(apply("view.alpha", .double(0.5), on: march, in: scene), .attributeNotEditable)
        assertRefused(apply("app.chart.barColor", nil, on: march, in: scene), .attributeNotEditable)
        XCTAssertEqual(scene.chart.alpha, 1)
    }

    func test_S_SET_08_aVirtualNodeThatIsGoneIsNotFound() throws {
        let scene = try makeScene()
        let april = try barID("april", in: scene)
        scene.chart.bars.removeLast()
        assertRefused(apply("app.bar.value", .double(10), on: april, in: scene), .layerNotFound)
        // Without the description, no virtual node exists.
        let march = try barID("march", in: scene)
        let plain = AttributeEditing.apply(
            SetAttribute(layerID: march, attributeID: "app.bar.value", value: .double(10)),
            windows: [scene.window],
            registry: registry,
            appState: .active
        )
        assertRefused(plain, .layerNotFound)
        XCTAssertEqual(scene.chart.written, [])
    }
}
