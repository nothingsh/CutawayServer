import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

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
        _ = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
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
            in: .testing(windows: [scene.window], registry: registry, extensions: scene.store)
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
            in: .testing(windows: [scene.window], registry: registry)
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
            in: .testing(windows: [scene.window], registry: registry)
        )
        assertRefused(plain, .layerNotFound)
        XCTAssertEqual(scene.chart.written, [])
    }

    // MARK: - The change

    /// P-SET-05: a change runs with implicit actions disabled, and nothing else held back: the
    /// app's `set` runs with UIView animations as it finds them.
    func test_S_SET_08_aChangeOnlyDisablesActions() throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        window.addSubview(view)
        let seen = ChangeConditions()
        let store = ExtensionStore()
        store.describe(UIView.self, CutawayServer.Description(attributes: { _ in
            [
                CutawayServer.AttributeGroup("probe", [
                    .bool("flag", false, set: { _ in
                        seen.actionsDisabled = CATransaction.disableActions()
                        seen.animationsEnabled = UIView.areAnimationsEnabled
                    })
                ])
            ]
        }), isView: true)
        let result = AttributeEditing.apply(
            SetAttribute(layerID: registry.register(view.layer), attributeID: "app.probe.flag", value: .bool(true)),
            in: .testing(windows: [window], registry: registry, extensions: store)
        )
        XCTAssertNoThrow(try result.get())
        XCTAssertEqual(seen.actionsDisabled, true)
        XCTAssertEqual(seen.animationsEnabled, true)
    }

    /// What one read of a layer works out once is worked out again after the change: the
    /// answer's lines are those of the text the app's `set` wrote.
    func test_S_SET_08_theAnswerMeasuresTheChangedText() throws {
        let window = try makeWindow()
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 400))
        label.numberOfLines = 0
        label.text = "One"
        window.addSubview(label)
        let store = ExtensionStore()
        store.describe(UILabel.self, CutawayServer.Description(attributes: { label in
            [CutawayServer.AttributeGroup("probe", [.string("text", label.text, set: { label.text = $0 })])]
        }), isView: true)
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        let result = AttributeEditing.apply(
            SetAttribute(layerID: registry.register(label.layer), attributeID: "app.probe.text", value: .string(long)),
            in: .testing(windows: [window], registry: registry, extensions: store)
        )
        let lines = try XCTUnwrap(AttributeTexts.lines(of: label))
        XCTAssertGreaterThan(lines.count, 1)
        let answer = try result.get().attributeGroups.flatMap(\.attributes)
        XCTAssertEqual(answer.first { $0.id == "label.drawnLineCount" }?.value, .int(Int64(lines.count)))
    }
}

/// What a change saw of UIKit while it ran.
@MainActor
private final class ChangeConditions {
    var actionsDisabled: Bool?
    var animationsEnabled: Bool?
}
