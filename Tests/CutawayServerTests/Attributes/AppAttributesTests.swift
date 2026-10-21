import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

private typealias AppGroup = CutawayServer.AttributeGroup
private typealias AppAttribute = CutawayServer.Attribute

private enum Mode: Int, CaseIterable {
    case bars
    case lines
}

/// The host app's groups as they are sent: IDs, values and the checks that leave out what
/// breaks the protocol (S-ATTR-24). No server, no connection.
final class AppAttributesTests: CaptureTestCase {
    private let registry = LayerRegistry()

    private func reading(_ window: UIWindow? = nil) -> AttributeReading {
        AttributeReading(registry: registry, windows: window.map { [$0] } ?? [])
    }

    private func context(_ window: UIWindow, _ extensions: ExtensionStore?) -> RequestContext {
        .testing(windows: [window], registry: registry, extensions: extensions)
    }

    private func app(
        _ groups: [AppGroup],
        className: String = "Demo.ChartView",
        alongside own: [CutawayWire.AttributeGroup] = [],
        view: UIView? = nil
    ) -> AppAttributes {
        AppAttributes(
            [AppAttributes.Source(groups: groups, className: className)],
            alongside: own,
            view: view,
            reading: reading()
        )
    }

    private func ids(_ app: AppAttributes) -> [String] {
        app.groups.flatMap(\.attributes).map(\.id)
    }

    private func attribute(_ id: String, in app: AppAttributes) throws -> CutawayWire.Attribute {
        try XCTUnwrap(app.groups.flatMap(\.attributes).first { $0.id == id }, "no \(id)")
    }

    // MARK: - IDs, titles, class names

    func test_S_ATTR_24_groupsArePrefixedAndFromTheApp() throws {
        let sent = app([
            AppGroup("chart", [.int("barCount", 3)]),
            AppGroup("legend", title: "Key", typeName: "Demo.Legend", [.bool("isShown", true, title: "Shown")])
        ])
        XCTAssertEqual(sent.groups.map(\.id), ["app.chart", "app.legend"])
        XCTAssertEqual(sent.groups.map(\.title), ["Chart", "Key"])
        XCTAssertEqual(sent.groups.map(\.fromApp), [true, true])
        // The registered class unless the group names its type.
        XCTAssertEqual(sent.groups.map(\.className), ["Demo.ChartView", "Demo.Legend"])
        XCTAssertEqual(ids(sent), ["app.chart.barCount", "app.legend.isShown"])
        XCTAssertEqual(sent.groups.flatMap(\.attributes).map(\.title), ["Bar Count", "Shown"])
    }

    func test_S_ATTR_24_aGroupOfATypeNamesItsType() {
        let sent = app([AppGroup("chart", type: BarChartView.Bar.self, [])])
        XCTAssertEqual(sent.groups.first?.className, String(reflecting: BarChartView.Bar.self))
    }

    // MARK: - Values

    func test_S_ATTR_24_everyKindOfValue() throws {
        let window = try makeWindow()
        let target = UIView()
        window.addSubview(target)
        window.layoutIfNeeded()
        let sent = AppAttributes(
            [
                AppAttributes.Source(
                    groups: [
                        AppGroup("values", [
                            .bool("bool", true),
                            .int("int", -4),
                            .double("double", 2.5),
                            .double("infinite", .infinity),
                            .string("string", "text"),
                            .color("color", .systemBlue),
                            .point("point", CGPoint(x: 1, y: 2)),
                            .size("size", CGSize(width: 3, height: 4)),
                            .rect("rect", CGRect(x: 1, y: 2, width: 3, height: 4)),
                            .insets("insets", UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)),
                            .transform("transform", CATransform3DMakeScale(2, 2, 1)),
                            .enumeration("mode", Mode.lines),
                            .enumeration("raw", 7, cases: [("seven", 7), ("nine", 9)]),
                            .enumeration("unknown", 8, cases: [("seven", 7)]),
                            .references("targets", [target]),
                            .double("none", nil)
                        ])
                    ],
                    className: "Demo.ChartView"
                )
            ],
            alongside: [],
            view: target,
            reading: reading(window)
        )
        func value(_ name: String) throws -> AttributeValue? {
            try attribute("app.values.\(name)", in: sent).value
        }
        XCTAssertEqual(try value("bool"), .bool(true))
        XCTAssertEqual(try value("int"), .int(-4))
        XCTAssertEqual(try value("double"), .double(2.5))
        XCTAssertEqual(try value("infinite"), .double(0))
        XCTAssertEqual(try value("string"), .string("text"))
        XCTAssertEqual(try value("color"), AttributeOutputs.color(.systemBlue, in: target))
        guard case .color(_, "systemBlue", _?, _?, nil)? = try value("color") else {
            return XCTFail(
                "the color is not named systemBlue with light and dark: \(String(describing: try value("color")))"
            )
        }
        XCTAssertEqual(try value("point"), .point(WirePoint(x: 1, y: 2)))
        XCTAssertEqual(try value("size"), .size(WireSize(width: 3, height: 4)))
        XCTAssertEqual(try value("rect"), .rect(WireRect(x: 1, y: 2, width: 3, height: 4)))
        XCTAssertEqual(try value("insets"), .insets(WireInsets(top: 1, left: 2, bottom: 3, right: 4)))
        XCTAssertEqual(try value("transform"), AttributeOutputs.transform(CATransform3DMakeScale(2, 2, 1)))
        XCTAssertEqual(
            try value("mode"),
            .enumeration(value: 1, cases: ["bars", "lines"], caseName: "lines", caseValues: [0, 1])
        )
        XCTAssertEqual(
            try value("raw"),
            .enumeration(value: 7, cases: ["seven", "nine"], caseName: "seven", caseValues: [7, 9])
        )
        XCTAssertEqual(try value("unknown"), .string("8"))
        XCTAssertEqual(try attribute("app.values.unknown", in: sent).valueKind, .string)
        XCTAssertEqual(
            try value("targets"),
            .layerReference([
                ObjectReference(
                    layerID: registry.register(target.layer),
                    className: "UIView",
                    displayClassName: "UIView"
                )
            ])
        )
        XCTAssertNil(try value("none"))
        XCTAssertEqual(try attribute("app.values.none", in: sent).valueKind, .double)
    }

    func test_S_ATTR_24_whatAWriterMakesEditable() throws {
        let sent = app([
            AppGroup("chart", [
                .double(
                    "value",
                    1,
                    section: .content,
                    unit: .points,
                    limits: [.atLeast(0)],
                    acceptsNil: true,
                    set: { _ in }
                ),
                .double("fixed", 1, limits: [.atLeast(0)], acceptsNil: true),
                .references("targets", []),
                .enumeration("unknown", 8, cases: [("seven", 7)], set: { _ in })
            ])
        ])
        let value = try attribute("app.chart.value", in: sent)
        XCTAssertTrue(value.editable)
        XCTAssertTrue(value.acceptsNil)
        XCTAssertEqual(value.section, .content)
        XCTAssertEqual(value.unit, .points)
        XCTAssertEqual(value.limits, [NumberLimit(minimum: 0)])
        // Without a writer: read-only, no nil, no limits.
        let fixed = try attribute("app.chart.fixed", in: sent)
        XCTAssertFalse(fixed.editable)
        XCTAssertFalse(fixed.acceptsNil)
        XCTAssertEqual(fixed.limits, [])
        XCTAssertFalse(try attribute("app.chart.targets", in: sent).editable)
        // A value that fell back to text is read-only.
        XCTAssertFalse(try attribute("app.chart.unknown", in: sent).editable)
    }

    // MARK: - Checks

    func test_S_ATTR_24_aGroupWithAnEmptyOrRepeatedIDIsLeftOut() {
        let sent = app([
            AppGroup("", [.int("count", 1)]),
            AppGroup("chart", [.int("count", 1)]),
            AppGroup("chart", [.int("other", 1)]),
            AppGroup("legend", [.int("", 1), .int("count", 1)]),
            AppGroup("axis", [.int("count", 1)])
        ])
        XCTAssertEqual(sent.groups.map(\.id), ["app.chart", "app.axis"])
        XCTAssertEqual(ids(sent), ["app.chart.count", "app.axis.count"])
    }

    func test_S_ATTR_24_aRepeatedAttributeIDIsLeftOut() {
        let sent = app([AppGroup("chart", [.int("count", 1), .string("count", "two"), .int("total", 3)])])
        XCTAssertEqual(ids(sent), ["app.chart.count", "app.chart.total"])
        XCTAssertEqual(sent.groups.first?.attributes.first?.value, .int(1))
    }

    func test_S_ATTR_24_limitsThatBreakTheRulesAreLeftOut() throws {
        let set: (@MainActor (Double?) throws -> Void) = { _ in }
        let setInt: (@MainActor (Int?) throws -> Void) = { _ in }
        let setPoint: (@MainActor (CGPoint?) throws -> Void) = { _ in }
        let sent = app([
            AppGroup("limits", [
                .double("valid", 0, limits: [.between(0, 1)], set: set),
                .double("reversed", 0, limits: [.between(1, 0)], set: set),
                .double("infinite", 0, limits: [.atMost(.infinity)], set: set),
                .double("notANumber", 0, limits: [.atLeast(.nan)], set: set),
                .double("single", 0, limits: [.between(1, 1)], set: set),
                .double("free", 0, limits: [.free], set: set),
                .int("fractional", 0, limits: [.atLeast(0.5)], set: setInt),
                .int("integers", 0, limits: [.between(0, 1)], set: setInt),
                .int("twoForOne", 0, limits: [.atLeast(0), .atMost(1)], set: setInt),
                .point("perComponent", .zero, limits: [.atLeast(0), .free], set: setPoint),
                .point("tooMany", .zero, limits: [.atLeast(0), .free, .free], set: setPoint)
            ])
        ])
        func limits(_ name: String) throws -> [NumberLimit] {
            try attribute("app.limits.\(name)", in: sent).limits
        }
        XCTAssertEqual(try limits("valid"), [NumberLimit(minimum: 0, maximum: 1)])
        XCTAssertEqual(try limits("reversed"), [])
        XCTAssertEqual(try limits("infinite"), [])
        XCTAssertEqual(try limits("notANumber"), [])
        // Between 1 and 1 inclusive holds 1; a free entry leaves the component free.
        XCTAssertEqual(try limits("single"), [NumberLimit(minimum: 1, maximum: 1)])
        XCTAssertEqual(try limits("free"), [.free])
        XCTAssertEqual(try limits("fractional"), [])
        XCTAssertEqual(try limits("integers"), [NumberLimit(minimum: 0, maximum: 1)])
        // Two entries for a single number: not one per component.
        XCTAssertEqual(try limits("twoForOne"), [])
        XCTAssertEqual(try limits("perComponent"), [NumberLimit(minimum: 0), .free])
        XCTAssertEqual(try limits("tooMany"), [])
    }

    func test_S_ATTR_24_limitsWithNoValueBetweenAreLeftOut() throws {
        // P-ATTR-10: exclusive on both sides of one number, and an integer between 0 and 1
        // exclusive, hold no value.
        XCTAssertFalse(NumberLimit(minimum: 1, minimumIsExclusive: true, maximum: 1)
            .isSatisfiable(byIntegersOnly: false))
        XCTAssertTrue(NumberLimit(minimum: 0, minimumIsExclusive: true, maximum: 1)
            .isSatisfiable(byIntegersOnly: false))
        XCTAssertFalse(
            NumberLimit(minimum: 0, minimumIsExclusive: true, maximum: 1, maximumIsExclusive: true)
                .isSatisfiable(byIntegersOnly: true)
        )
        XCTAssertTrue(NumberLimit(minimum: 0, maximum: 1, maximumIsExclusive: true).isSatisfiable(byIntegersOnly: true))
        let sent = app([AppGroup("limits", [.double("open", 0, limits: [.greaterThan(1)], set: { _ in })])])
        XCTAssertEqual(
            try attribute("app.limits.open", in: sent).limits,
            [NumberLimit(minimum: 1, minimumIsExclusive: true)]
        )
    }

    func test_S_ATTR_24_clustersThatBreakTheRulesAreLeftOut() throws {
        // The server's own attribute already holds geometry/frame in the layout section.
        let own = CutawayWire.AttributeGroup(
            id: "layer",
            title: "Layer",
            attributes: [
                Attribute(
                    id: "layer.frame",
                    title: "Frame",
                    value: nil,
                    valueKind: .rect,
                    section: .layout,
                    cluster: "geometry",
                    slot: "frame"
                )
            ]
        )
        let sent = app(
            [
                AppGroup("chart", [
                    .bool(
                        "hidden",
                        false,
                        section: .appearance,
                        cluster: CutawayServer.Attribute.Cluster("visibility", slot: "hidden")
                    ),
                    .double(
                        "opacity",
                        1,
                        section: .appearance,
                        cluster: CutawayServer.Attribute.Cluster("visibility", slot: "opacity")
                    ),
                    .bool(
                        "again",
                        false,
                        section: .appearance,
                        cluster: CutawayServer.Attribute.Cluster("visibility", slot: "hidden")
                    ),
                    .rect(
                        "frame",
                        .zero,
                        section: .layout,
                        cluster: CutawayServer.Attribute.Cluster("geometry", slot: "frame")
                    ),
                    .rect(
                        "bounds",
                        .zero,
                        section: .content,
                        cluster: CutawayServer.Attribute.Cluster("geometry", slot: "bounds")
                    ),
                    .double("unknownCluster", 0, cluster: CutawayServer.Attribute.Cluster("chart", slot: "value")),
                    .double("unknownSlot", 0, cluster: CutawayServer.Attribute.Cluster("visibility", slot: "value"))
                ])
            ],
            alongside: [own]
        )
        func cluster(_ name: String) throws -> [String?] {
            let attribute = try attribute("app.chart.\(name)", in: sent)
            return [attribute.cluster, attribute.slot]
        }
        XCTAssertEqual(try cluster("hidden"), ["visibility", "hidden"])
        XCTAssertEqual(try cluster("opacity"), ["visibility", "opacity"])
        XCTAssertEqual(try cluster("again"), [nil, nil])
        // The server's attribute has the slot.
        XCTAssertEqual(try cluster("frame"), [nil, nil])
        // The cluster is in the layout section.
        XCTAssertEqual(try cluster("bounds"), [nil, nil])
        XCTAssertEqual(try cluster("unknownCluster"), [nil, nil])
        XCTAssertEqual(try cluster("unknownSlot"), [nil, nil])
    }

    func test_S_ATTR_24_anInactiveCauseMustNameAnAttributeOfTheNode() throws {
        let sent = app([
            AppGroup("chart", [
                .bool("showsLine", false),
                .color("lineColor", .red, inactiveBecauseOf: "chart.showsLine"),
                .double("lineWidth", 1, inactiveBecauseOf: "chart.missing"),
                .double("legendWidth", 1, inactiveBecauseOf: "legend.isShown")
            ]),
            AppGroup("legend", [.bool("isShown", false)])
        ])
        XCTAssertEqual(try attribute("app.chart.lineColor", in: sent).inactiveCause, "app.chart.showsLine")
        XCTAssertNil(try attribute("app.chart.lineWidth", in: sent).inactiveCause)
        // In a later group of the same node.
        XCTAssertEqual(try attribute("app.chart.legendWidth", in: sent).inactiveCause, "app.legend.isShown")
    }

    // MARK: - Reading a node

    func test_S_ATTR_24_aLayersGroupsFollowTheServersOwn() throws {
        let window = try makeWindow()
        let chart = BarChartView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.addSubview(chart)
        let store = ExtensionStore()
        store.describe(
            UIView.self,
            CutawayServer.Description(attributes: { _ in [AppGroup("anyView", [.int("tag", 1)])] }),
            isView: true
        )
        store.describe(
            BarChartView.self,
            CutawayServer
                .Description(attributes: { chart in [AppGroup("chart", [.int("barCount", chart.bars.count)])] }),
            isView: true
        )
        store.describe(
            CALayer.self,
            CutawayServer.Description(attributes: { _ in [AppGroup("anyLayer", [.int("depth", 0)])] }),
            isView: false
        )
        let groups = NodeAttributes(context: context(window, store)).read(chart.layer)
        let own = AttributeCatalog.standard.read(chart.layer, reading: reading(window)).map(\.id)
        XCTAssertEqual(groups.map(\.id), own + ["app.anyLayer", "app.anyView", "app.chart"])
        XCTAssertEqual(
            groups.suffix(3).map(\.className),
            ["CALayer", "UIView", NSStringFromClass(BarChartView.self)]
        )
        // Nothing registered: the server's own, as before.
        XCTAssertEqual(
            NodeAttributes(context: context(window, ExtensionStore())).read(chart.layer).map(\.id),
            own
        )
        XCTAssertEqual(NodeAttributes(context: context(window, nil)).read(chart.layer).map(\.id), own)
    }

    func test_S_ATTR_24_aVirtualNodesDetailHasOnlyItsOwnGroups() throws {
        let window = try makeWindow()
        let chart = DrawnChartView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        chart.bars = [DrawnChartView.Bar(id: "march", value: 40)]
        window.addSubview(chart)
        let store = ExtensionStore()
        store.describe(DrawnChartView.self, DrawnChartView.description, isView: true)
        _ = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let march = try XCTUnwrap(
            registry.virtualIDs[LayerRegistry.VirtualKey(layerID: registry.register(chart.layer), identity: "march")]
        )
        let attributes = NodeAttributes(context: context(window, store))
        let detail = try XCTUnwrap(
            DetailCapture.capture(
                LayerDetailRequest(layerID: march, wantSolo: true, wantGroup: true, wantAttributes: true),
                maxTextureDimension: 0,
                in: .testing(windows: [window], registry: registry, extensions: store),
                stopFlag: StopFlag(),
                screenScale: 1,
                readAttributes: { attributes.read($0) },
                readVirtualAttributes: { attributes.read($0) }
            )
        )
        XCTAssertEqual(detail.status, .ok)
        XCTAssertNil(detail.group)
        XCTAssertEqual(detail.attributeGroups.map(\.id), ["app.bar"])
        // A virtual node's groups name its type unless they name one.
        XCTAssertEqual(detail.attributeGroups.map(\.className), ["Bar"])
        XCTAssertEqual(detail.attributeGroups.first?.attributes.map(\.value), [.double(40)])
    }

    // MARK: - The interface

    func test_S_API_04_theClusterConstantsAreTheProtocolsTable() {
        typealias Cluster = CutawayServer.Attribute.Cluster
        let clusters: [Any] = [
            Cluster.visibility,
            Cluster.corners,
            Cluster.border,
            Cluster.shadow,
            Cluster.geometry,
            Cluster.sizing,
            Cluster.autoLayout,
            Cluster.font,
            Cluster.lines,
            Cluster.state,
            Cluster.scrolling,
            Cluster.image,
            Cluster.indexPath,
            Cluster.listCounts
        ]
        var constants: [String: Set<String>] = [:]
        for cluster in clusters {
            let slots = Mirror(reflecting: cluster).children.compactMap { $0.value as? Cluster }
            // Each value holds the slots of one cluster.
            XCTAssertEqual(Set(slots.map(\.name)).count, 1, "\(cluster)")
            for slot in slots {
                XCTAssertTrue(constants[slot.name, default: []].insert(slot.slot).inserted, "\(slot)")
            }
        }
        XCTAssertEqual(constants, AttributeTables.clusterSlots.mapValues { Set($0.keys) })
        XCTAssertEqual(Cluster.font.size.name, "font")
        XCTAssertEqual(Cluster.font.size.slot, "size")
        XCTAssertEqual(Cluster.sizing.huggingHorizontal.slot, "hugging.horizontal")
    }

    func test_S_API_04_aClusterConstantIsSentAsItsNames() throws {
        let sent = app([
            AppGroup("chart", [
                .double("radius", 4, section: .appearance, cluster: .corners.radius),
                .double(
                    "offset",
                    2,
                    section: .appearance,
                    cluster: CutawayServer.Attribute.Cluster("shadow", slot: "offset")
                )
            ])
        ])
        XCTAssertEqual(try attribute("app.chart.radius", in: sent).cluster, "corners")
        XCTAssertEqual(try attribute("app.chart.radius", in: sent).slot, "radius")
        XCTAssertEqual(try attribute("app.chart.offset", in: sent).cluster, "shadow")
        XCTAssertEqual(try attribute("app.chart.offset", in: sent).slot, "offset")
    }
}
