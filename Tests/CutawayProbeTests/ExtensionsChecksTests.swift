import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's checks of the demo app's Extensions page (S-PROBE-08): they accept the page as a
/// correct server reports it and name what is wrong with anything else.
final class ExtensionsChecksTests: XCTestCase {
    private func node(
        _ id: UInt64,
        in parentID: UInt64,
        _ viewClass: String,
        held name: String? = nil,
        excluded: Bool = false
    ) -> LayerNode {
        var node = LayerNode(
            id: id,
            parentID: parentID,
            className: "CALayer",
            displayClassName: "CALayer",
            viewClassName: viewClass,
            viewDisplayClassName: viewClass,
            bounds: WireRect(x: 0, y: 0, width: 100, height: 40),
            position: WirePoint(x: 50, y: 50),
            isCaptureExcluded: excluded
        )
        if let name {
            node.memberReferences = [DemoScene.reference(name, owner: DemoExtensionsScene.controller)]
        }
        return node
    }

    private func virtual(
        _ id: UInt64,
        in parentID: UInt64,
        _ name: String,
        className: String,
        height: Double,
        center: WirePoint,
        collapsed: Bool = false
    ) -> LayerNode {
        LayerNode(
            id: id,
            parentID: parentID,
            className: className,
            displayClassName: String(className.split(separator: ".").last ?? ""),
            bounds: WireRect(x: 0, y: 0, width: 60, height: height),
            position: center,
            layerClassOrigin: .app,
            nodeKind: .virtual,
            name: name,
            isCollapsedByDefault: collapsed
        )
    }

    private func color(named name: String?) -> AttributeValue {
        .color(WireColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), name: name)
    }

    private func group(
        _ id: String,
        className: String,
        fromApp: Bool = true,
        _ values: [(String, AttributeValue)]
    ) -> AttributeGroup {
        AttributeGroup(
            id: id,
            title: id,
            attributes: values.map { Attribute(id: "\(id).\($0.0)", title: $0.0, value: $0.1, valueKind: $0.1.kind) },
            className: className,
            fromApp: fromApp
        )
    }

    /// The page as a correct server reports it: window 1, page 2, Close 3, the chart 4 with
    /// its bars 10, 13, 14 and their segments 11, 12, 15, the card number 5 with its label 6,
    /// the swatch 7.
    private func hierarchy() -> Hierarchy {
        var root = node(2, in: 1, "UIView")
        root.viewControllerClassName = "CutawayDemo.DemoExtensionsViewController"
        root.viewControllerDisplayClassName = "DemoExtensionsViewController"
        let bar = ExtensionsChecks.barClass
        let segment = ExtensionsChecks.segmentClass
        return Hierarchy(
            nodes: [
                node(1, in: 0, "UIWindow"),
                root,
                node(3, in: 2, "UIButton", held: "closeButton"),
                node(4, in: 2, "CutawayDemo.SalesChartView", held: "salesChart"),
                virtual(10, in: 4, "North", className: bar, height: 120, center: WirePoint(x: 60, y: 140)),
                virtual(11, in: 10, "Online", className: segment, height: 30, center: WirePoint(x: 30, y: 105)),
                virtual(12, in: 10, "Retail", className: segment, height: 90, center: WirePoint(x: 30, y: 45)),
                virtual(13, in: 4, "South", className: bar, height: 80, center: WirePoint(x: 150, y: 160)),
                virtual(
                    14,
                    in: 4,
                    "East",
                    className: bar,
                    height: 160,
                    center: WirePoint(x: 240, y: 120),
                    collapsed: true
                ),
                virtual(15, in: 14, "Export", className: segment, height: 160, center: WirePoint(x: 30, y: 80)),
                node(5, in: 2, "CutawayDemo.CardNumberView", held: "cardNumber", excluded: true),
                node(6, in: 5, "UILabel", excluded: true),
                node(7, in: 2, "UIView", held: "brandSwatch")
            ],
            keyWindowID: 1
        )
    }

    private func details() -> [LayerDetail] {
        func detail(_ id: UInt64, status: DetailStatus = .ok, _ groups: [AttributeGroup]) -> LayerDetail {
            LayerDetail(layerID: id, status: status, solo: nil, group: nil, attributeGroups: groups)
        }
        return [
            detail(4, [
                group("layer", className: "CALayer", fromApp: false, []),
                group(
                    "app.chart",
                    className: "CutawayDemo.SalesChartView",
                    [("barCount", .int(3)), ("barColor", color(named: "brandBlue"))]
                )
            ]),
            detail(
                7,
                [group("view", className: "UIView", fromApp: false, [("backgroundColor", color(named: "brandBlue"))])]
            ),
            detail(
                10,
                [
                    group(
                        "app.bar",
                        className: ExtensionsChecks.barClass,
                        [("label", .string("North")), ("value", .double(120))]
                    )
                ]
            ),
            detail(5, status: .excluded, [])
        ]
    }

    private func assertRejects(_ expected: String, line: UInt = #line, _ check: () throws -> Void) {
        XCTAssertThrowsError(try check(), line: line) { error in
            XCTAssertTrue("\(error)".contains(expected), "\"\(error)\" does not mention \"\(expected)\"", line: line)
        }
    }

    private func assertHierarchyRejects(_ expected: String, line: UInt = #line, _ change: (inout Hierarchy) -> Void) {
        var hierarchy = hierarchy()
        change(&hierarchy)
        assertRejects(expected, line: line) {
            try ExtensionsChecks.hierarchy(try DemoExtensionsScene(hierarchy), hierarchy: hierarchy)
        }
    }

    private func assertDetailsRejects(
        _ expected: String,
        line: UInt = #line,
        _ change: (inout [LayerDetail]) -> Void
    ) throws {
        var details = details()
        change(&details)
        let scene = try DemoExtensionsScene(hierarchy())
        assertRejects(expected, line: line) { try ExtensionsChecks.details(details, scene: scene) }
    }

    func test_S_PROBE_08_demoChecksAcceptTheExtensionsPage() throws {
        let hierarchy = hierarchy()
        XCTAssertTrue(DemoExtensionsScene.isShown(in: hierarchy))
        XCTAssertFalse(DemoListsScene.isShown(in: hierarchy))
        let scene = try DemoExtensionsScene(hierarchy)
        XCTAssertEqual(scene.bars.map(\.id), [10, 13, 14])
        XCTAssertEqual(scene.segments.map { $0.map(\.id) }, [[11, 12], [], [15]])
        XCTAssertNoThrow(try ExtensionsChecks.hierarchy(scene, hierarchy: hierarchy))
        XCTAssertNoThrow(try ExtensionsChecks.details(details(), scene: scene))
    }

    func test_S_PROBE_08_demoChecksRejectAnotherHierarchy() {
        assertHierarchyRejects("the chart's virtual nodes are [\"North\", \"East\"]") {
            $0.nodes.removeAll { $0.id == 13 }
        }
        assertHierarchyRejects("the bar South has bounds") { $0.nodes[7].bounds.size.height = 90 }
        assertHierarchyRejects("the bar East is at x 250.0") { $0.nodes[8].position.x = 250 }
        assertHierarchyRejects("the bar East is not collapsed by default") { $0.nodes[8].isCollapsedByDefault = false }
        assertHierarchyRejects("the bar North holds [\"Retail\"]") { $0.nodes.removeAll { $0.id == 11 } }
        assertHierarchyRejects("the segment Online has bounds") { $0.nodes[5].position.y = 45 }
        assertHierarchyRejects("expected a virtual node of CutawayDemo.SalesChartView.Bar.Segment") {
            $0.nodes[9].className = "CutawayDemo.Export"
        }
        assertHierarchyRejects("node 6 (UILabel) is not excluded from images") { $0.nodes[11].isCaptureExcluded = false
        }
        assertHierarchyRejects("node 7 (UIView) is excluded from images") { $0.nodes[12].isCaptureExcluded = true }
        assertHierarchyRejects("salesChart") { $0.nodes[3].memberReferences = [] }
    }

    func test_S_PROBE_08_demoChecksRejectOtherDetails() throws {
        try assertDetailsRejects("the chart has the groups [\"layer\"]") { $0[0].attributeGroups.removeLast() }
        try assertDetailsRejects("app.chart.barCount of the chart is int(2)") {
            $0[0].attributeGroups[1].attributes[0].value = .int(2)
        }
        try assertDetailsRejects("app.chart.barColor of the chart") {
            $0[0].attributeGroups[1].attributes[1].value = self.color(named: nil)
        }
        try assertDetailsRejects("view.backgroundColor of the swatch") {
            $0[1].attributeGroups[0].attributes[0].value = self.color(named: "brand")
        }
        try assertDetailsRejects("the bar North is captureFailed") { $0[2].status = .captureFailed }
        try assertDetailsRejects("expected app.bar of CutawayDemo.SalesChartView.Bar") {
            $0[2].attributeGroups.insert(self.group("layer", className: "CALayer", fromApp: false, []), at: 0)
        }
        try assertDetailsRejects("app.bar.value of the bar North is double(150.0)") {
            $0[2].attributeGroups[0].attributes[1].value = .double(150)
        }
        try assertDetailsRejects("the card number is ok") { $0[3].status = .ok }
    }

    func test_S_PROBE_08_raisedBarChecksItsSubtree() throws {
        let scene = try DemoExtensionsScene(hierarchy())
        var raised = hierarchy().nodes.filter { [10, 11, 12].contains($0.id) }
        raised[0].bounds.size.height = 150
        raised[0].position.y = 125
        let frame = Frame(requestID: 22, body: .hierarchy(Hierarchy(nodes: raised, keyWindowID: 1)))
        XCTAssertNoThrow(try ExtensionsChecks.raised(frame, scene: scene, height: 150))
        assertRejects("North has bounds") { try ExtensionsChecks.raised(frame, scene: scene, height: 120) }
        let short = Frame(requestID: 22, body: .hierarchy(Hierarchy(nodes: [raised[0]], keyWindowID: 1)))
        assertRejects("the subtree of the bar North holds [10]") { try ExtensionsChecks.raised(
            short,
            scene: scene,
            height: 150
        ) }
    }
}
