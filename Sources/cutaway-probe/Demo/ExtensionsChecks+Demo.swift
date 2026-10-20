import CutawayWire
import Foundation

// The checks of `--expect-demo` on the demo app's Extensions page: the host app's extensions
// of protocol 1.2 (S-PROBE-08).

/// What the Extensions page has to look like (Demo/CutawayDemo/DemoExtensionsViewController.swift).
/// Every function throws a `ProbeFailure` naming the first thing that is wrong.
enum ExtensionsChecks {
    /// One bar of the chart as the page draws it.
    struct Bar {
        let name: String
        let height: Double
        let isCollapsedByDefault: Bool
        /// The segments' names and heights, bottom up as the host app gives them.
        let segments: [(name: String, height: Double)]
    }

    static let chartHeight = 200.0
    static let bars = [
        Bar(name: "North", height: 120, isCollapsedByDefault: false, segments: [("Online", 30), ("Retail", 90)]),
        Bar(name: "South", height: 80, isCollapsedByDefault: false, segments: []),
        Bar(name: "East", height: 160, isCollapsedByDefault: true, segments: [("Export", 160)])
    ]
    static let barClass = "\(DemoScene.module).SalesChartView.Bar"
    static let segmentClass = "\(DemoScene.module).SalesChartView.Bar.Segment"

    /// The chart's virtual nodes and the excluded card number (P-HIER-19 to 23, P-DET-10).
    static func hierarchy(_ scene: DemoExtensionsScene, hierarchy: Hierarchy) throws {
        let names = scene.bars.map { $0.name ?? "nil" }
        guard names == bars.map(\.name) else {
            throw ProbeFailure(
                "demo: the chart's virtual nodes are \(names), expected \(bars.map(\.name)) (P-HIER-19, 21)"
            )
        }
        for (index, (node, bar)) in zip(scene.bars, bars).enumerated() {
            try check(
                node,
                "the bar \(bar.name)",
                className: barClass,
                height: bar.height,
                centerY: chartHeight - bar.height / 2
            )
            guard node.position.x == 60 + 90 * Double(index) else {
                throw ProbeFailure(
                    "demo: the bar \(bar.name) is at x \(node.position.x), expected \(60 + 90 * Double(index)) (P-HIER-20)"
                )
            }
            guard node.isCollapsedByDefault == bar.isCollapsedByDefault else {
                throw ProbeFailure(
                    "demo: the bar \(bar.name) is \(node.isCollapsedByDefault ? "" : "not ")collapsed by default (P-HIER-23)"
                )
            }
            let segments = scene.segments[index]
            guard segments.map({ $0.name ?? "nil" }) == bar.segments.map(\.name) else {
                throw ProbeFailure(
                    "demo: the bar \(bar.name) holds \(segments.map { $0.name ?? "nil" }), expected \(bar.segments.map(\.name)) (P-HIER-19)"
                )
            }
            var top = 0.0
            for (segment, expected) in zip(segments, bar.segments).reversed() {
                try check(
                    segment,
                    "the segment \(expected.name)",
                    className: segmentClass,
                    height: expected.height,
                    centerY: top + expected.height / 2
                )
                top += expected.height
            }
        }
        // The card number and everything in it, and nothing else of the page.
        let excluded = Set(([scene.cardNumber] + DemoScene.descendants(of: scene.cardNumber, in: hierarchy.nodes))
            .map(\.id))
        for node in [scene.page] + DemoScene.descendants(of: scene.page, in: hierarchy.nodes)
            where node.isCaptureExcluded != excluded.contains(node.id) {
            throw ProbeFailure(
                "demo: node \(node.id) (\(node.viewClassName ?? node.className)) is \(node.isCaptureExcluded ? "" : "not ")excluded from images (P-DET-10)"
            )
        }
    }

    private static func check(
        _ node: LayerNode,
        _ name: String,
        className: String,
        height: Double,
        centerY: Double
    ) throws {
        guard node.nodeKind == .virtual, node.className == className else {
            throw ProbeFailure(
                "demo: \(name) is a \(node.nodeKind) node of \(node.className), expected a virtual node of \(className) (P-HIER-20)"
            )
        }
        guard node.bounds == WireRect(x: 0, y: 0, width: 60, height: height), node.position.y == centerY else {
            throw ProbeFailure(
                "demo: \(name) has bounds \(node.bounds) at \(node.position), expected 60 x \(height) centered at y \(centerY) (P-HIER-20)"
            )
        }
    }

    /// The details of the page: the host app's groups after the server's, the registered
    /// color's name, a virtual node's own groups, the excluded card number
    /// (P-ATTR-19, 20, P-DET-09, 10). Call it after `DetailChecks.stream`.
    static func details(_ details: [LayerDetail], scene: DemoExtensionsScene) throws {
        var byID: [UInt64: LayerDetail] = [:]
        for detail in details { byID[detail.layerID] = detail }
        let chart = byID[scene.chart.id]?.attributeGroups ?? []
        guard chart.map(\.id).suffix(1) == ["app.chart"], chart.filter(\.fromApp).count == 1 else {
            throw ProbeFailure(
                "demo: the chart has the groups \(chart.map(\.id)), expected the app's app.chart last (P-ATTR-19)"
            )
        }
        try expect("the chart", "app.chart.barCount", in: chart, .int(3))
        try expectName("the chart", "app.chart.barColor", in: chart)
        try expectName("the swatch", "view.backgroundColor", in: byID[scene.brandSwatch.id]?.attributeGroups ?? [])

        let north = byID[scene.bars[0].id]
        guard north?.status == .ok, north?.solo == nil, north?.group == nil else {
            throw ProbeFailure(
                "demo: the bar North is \(north.map { "\($0.status)" } ?? "missing"), expected Ok without images (P-DET-09)"
            )
        }
        let groups = north?.attributeGroups ?? []
        guard groups.map(\.id) == ["app.bar"], groups.first?.className == barClass else {
            throw ProbeFailure(
                "demo: the bar North has the groups \(groups.map(\.id)) of \(groups.first?.className ?? "nil"), expected app.bar of \(barClass) (P-ATTR-19)"
            )
        }
        try expect("the bar North", "app.bar.label", in: groups, .string("North"))
        try expect("the bar North", "app.bar.value", in: groups, .double(120))

        let card = byID[scene.cardNumber.id]
        guard card?.status == .excluded, card?.solo == nil, card?.group == nil else {
            throw ProbeFailure(
                "demo: the card number is \(card.map { "\($0.status)" } ?? "missing"), expected Excluded without images (P-DET-10)"
            )
        }
    }

    private static func expect(
        _ what: String,
        _ id: String,
        in groups: [AttributeGroup],
        _ expected: AttributeValue
    ) throws {
        let actual = AttributeChecks.value(id, in: groups)
        guard actual == expected else {
            throw ProbeFailure("demo: \(id) of \(what) is \(AttributeChecks.describe(actual)), expected \(expected)")
        }
    }

    private static func expectName(_ what: String, _ id: String, in groups: [AttributeGroup]) throws {
        let actual = AttributeChecks.value(id, in: groups)
        guard case .color(_, _, _, _, DemoExtensionsScene.brandBlue)? = actual else {
            throw ProbeFailure(
                "demo: \(id) of \(what) is \(AttributeChecks.describe(actual)), expected the registered color \(DemoExtensionsScene.brandBlue) (P-ATTR-20)"
            )
        }
    }

    /// The subtree of the bar North after its value became `height`: the bar and its segments
    /// in their new geometry (P-SET-05, P-HIER-22).
    static func raised(_ frame: Frame, scene: DemoExtensionsScene, height: Double) throws {
        guard case .hierarchy(let subtree)? = frame.body else {
            throw ProbeFailure("expected Hierarchy for GetSubtree, got \(Checks.describe(frame)) (P-HIER-10)")
        }
        let north = scene.bars[0]
        guard subtree.nodes.map(\.id) == [north.id] + scene.segments[0].map(\.id) else {
            throw ProbeFailure("the subtree of the bar North holds \(subtree.nodes.map(\.id)) (P-HIER-10, 22)")
        }
        try check(
            subtree.nodes[0],
            "the bar North",
            className: barClass,
            height: height,
            centerY: chartHeight - height / 2
        )
    }
}

/// Changes the bar North's value and changes it back, reading its subtree in between; a value
/// the host app refuses and an attribute of the server's are refused (S-PROBE-08; PROTOCOL.md,
/// P-ATTR-19, P-SET-03, P-SET-05, P-HIER-10, 22). The value is changed back before the end, also
/// when a check fails on the way.
func checkDemoExtensions(scene: DemoExtensionsScene, hierarchy: Hierarchy, on connection: ProbeConnection) throws {
    let east = scene.bars[2]
    _ = try HierarchyChecks.subtree(
        try request(.getSubtree(rootID: east.id), id: ProbeRequestID.eastSubtree, on: connection),
        rootID: east.id,
        hierarchy: hierarchy
    )
    print("subtree: the virtual node East and its segment match the hierarchy")

    let north = scene.bars[0]
    let original = AttributeValue.double(120)
    let raised = AttributeValue.double(150)
    func change(to value: AttributeValue, id: UInt32) throws -> Frame {
        try request(
            .setAttribute(SetAttribute(layerID: north.id, attributeID: "app.bar.value", value: value)),
            id: id,
            on: connection
        )
    }
    var changed = true
    defer {
        // Best effort: the check that failed has already been reported.
        if changed { _ = try? change(to: original, id: ProbeRequestID.restoreBarAfterFailure) }
    }
    _ = try EditChecks.result(
        try change(to: raised, id: ProbeRequestID.raiseBar),
        layerID: north.id,
        attributeID: "app.bar.value",
        value: raised
    )
    try ExtensionsChecks.raised(
        try request(.getSubtree(rootID: north.id), id: ProbeRequestID.barAfterRaising, on: connection),
        scene: scene,
        height: 150
    )
    _ = try EditChecks.result(
        try change(to: original, id: ProbeRequestID.restoreBar),
        layerID: north.id,
        attributeID: "app.bar.value",
        value: original
    )
    changed = false
    _ = try HierarchyChecks.subtree(
        try request(.getSubtree(rootID: north.id), id: ProbeRequestID.barAfterRestoring, on: connection),
        rootID: north.id,
        hierarchy: hierarchy
    )
    print("set attribute: the bar North's value changed, moved the bar, and changed back")

    try EditChecks.refusal(try change(to: .double(500), id: ProbeRequestID.barTooTall), code: .invalidAttributeValue)
    try EditChecks.refusal(
        try request(
            .setAttribute(SetAttribute(layerID: north.id, attributeID: "view.alpha", value: .double(0.5))),
            id: ProbeRequestID.viewAttributeOnBar,
            on: connection
        ),
        code: .attributeNotEditable
    )
    print("set attribute: a value the app refused, and view.alpha on a virtual node, were refused")
}
