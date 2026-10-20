import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// The demo app's Extensions page (Demo/CutawayDemo/DemoExtensionsViewController.swift) reads
/// as `cutaway-probe --expect-demo` expects it to (Sources/cutaway-probe/Demo/ExtensionsChecks+Demo.swift),
/// without running the demo app.
final class DemoExtensionsPageTests: CaptureTestCase {
    override func tearDown() async throws {
        ExtensionStore.shared.removeAll()
        try await super.tearDown()
    }

    func test_S_PROBE_08_theExtensionsPageReadsAsTheProbeExpects() throws {
        let window = try makeWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let page = DemoExtensionsViewController()
        window.rootViewController = page
        window.layoutIfNeeded()
        DemoExtensions.register()
        let registry = LayerRegistry()
        let subviews = page.view.subviews
        XCTAssertEqual(subviews.count, 4)
        let chart = try XCTUnwrap(subviews[1] as? SalesChartView)
        let card = try XCTUnwrap(subviews[2] as? CardNumberView)
        let swatch = subviews[3]

        // The hierarchy: the bars, their segments, the excluded card number.
        let hierarchy = HierarchyCapture.capture(windows: [window], registry: registry, extensions: .shared)
        let chartID = registry.register(chart.layer)
        let bars = hierarchy.nodes.filter { $0.parentID == chartID }
        XCTAssertEqual(bars.map(\.name), ["North", "South", "East"])
        XCTAssertEqual(bars.map(\.nodeKind), [.virtual, .virtual, .virtual])
        XCTAssertEqual(bars.map(\.displayClassName), ["Bar", "Bar", "Bar"])
        XCTAssertEqual(bars.map(\.className), Array(repeating: "CutawayServerTests.SalesChartView.Bar", count: 3))
        XCTAssertEqual(bars.map(\.bounds.size.height), [120, 80, 160])
        XCTAssertEqual(
            bars.map(\.position),
            [WirePoint(x: 60, y: 140), WirePoint(x: 150, y: 160), WirePoint(x: 240, y: 120)]
        )
        XCTAssertEqual(bars.map(\.isCollapsedByDefault), [false, false, true])
        let segments = bars.map { bar in hierarchy.nodes.filter { $0.parentID == bar.id } }
        XCTAssertEqual(segments.map { $0.map(\.name) }, [["Online", "Retail"], [], ["Export"]])
        XCTAssertEqual(segments[0].map(\.position), [WirePoint(x: 30, y: 105), WirePoint(x: 30, y: 45)])
        XCTAssertEqual(segments[0].map(\.bounds.size.height), [30, 90])
        XCTAssertEqual(segments[0].first?.displayClassName, "Segment")
        for node in hierarchy.nodes {
            let layer = registry.layer(for: node.id)
            let isCard = layer.map { $0 === card.layer || $0.superlayer === card.layer } ?? false
            XCTAssertEqual(node.isCaptureExcluded, isCard, "\(node.className) \(node.id)")
        }

        // The details: the app's group, the registered color, a bar's own group.
        let attributes = NodeAttributes(
            reading: AttributeReading(registry: registry, windows: [window]),
            extensions: .shared
        )
        func value(_ id: String, in groups: [AttributeGroup]) -> AttributeValue? {
            groups.flatMap(\.attributes).first { $0.id == id }?.value
        }
        let chartGroups = attributes.read(chart.layer)
        XCTAssertEqual(chartGroups.last?.id, "app.chart")
        XCTAssertEqual(value("app.chart.barCount", in: chartGroups), .int(3))
        guard case .color(_, _, _, _, "brandBlue")? = value("app.chart.barColor", in: chartGroups) else {
            return XCTFail("the bar color is not brandBlue")
        }
        guard case .color(_, _, _, _, "brandBlue")? = value("view.backgroundColor", in: attributes.read(swatch.layer))
        else {
            return XCTFail("the swatch is not brandBlue")
        }
        let north = try XCTUnwrap(attributes.virtualNode(bars[0].id))
        let northGroups = attributes.read(north)
        XCTAssertEqual(northGroups.map(\.id), ["app.bar"])
        XCTAssertEqual(northGroups.first?.className, "CutawayServerTests.SalesChartView.Bar")
        XCTAssertEqual(value("app.bar.label", in: northGroups), .string("North"))
        XCTAssertEqual(value("app.bar.value", in: northGroups), .double(120))

        // The probe's changes: raised and back, too tall, a view attribute.
        func set(_ id: String, _ value: AttributeValue) -> Result<SetAttributeResult, WireError> {
            AttributeEditing.apply(
                SetAttribute(layerID: bars[0].id, attributeID: id, value: value),
                windows: [window],
                registry: registry,
                appState: .active,
                extensions: .shared
            )
        }
        XCTAssertEqual(
            value("app.bar.value", in: try set("app.bar.value", .double(150)).get().attributeGroups),
            .double(150)
        )
        XCTAssertEqual(chart.bars[0].value, 150)
        let raised = try XCTUnwrap(HierarchyCapture.captureSubtree(
            rootID: bars[0].id,
            windows: [window],
            registry: registry,
            extensions: .shared
        ))
        XCTAssertEqual(raised.nodes.first?.position, WirePoint(x: 60, y: 125))
        XCTAssertEqual(
            value("app.bar.value", in: try set("app.bar.value", .double(120)).get().attributeGroups),
            .double(120)
        )
        guard case .failure(let tooTall) = set("app.bar.value", .double(500))
        else { return XCTFail("500 was accepted") }
        XCTAssertEqual(
            tooTall,
            WireError(code: .invalidAttributeValue, message: "a bar can be at most 200 points tall")
        )
        guard case .failure(let alpha) = set("view.alpha", .double(0.5))
        else { return XCTFail("view.alpha was accepted") }
        XCTAssertEqual(alpha.code, .attributeNotEditable)
    }
}
