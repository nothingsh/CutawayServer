import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

private final class SpecialBarChartView: UIView {}

/// Virtual nodes, nodes collapsed by default and excluded subtrees in the hierarchy and its
/// subtrees (S-HIER-17, S-HIER-18, S-SHOT-13). No server, no connection.
final class VirtualNodeCaptureTests: CaptureTestCase {
    private let v11 = ProtocolVersion(major: 1, minor: 1)

    /// A window with a chart of two bars, the first with two parts, and a subview of the
    /// chart; the store describes charts.
    private struct Chart {
        let window: UIWindow
        let chart: BarChartView
        let sub: UIView
        let store: ExtensionStore
    }

    private func makeChart() throws -> Chart {
        let window = try makeWindow()
        let chart = BarChartView(frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        chart.bars = [
            BarChartView.Bar(id: "march", value: 40, parts: ["low", "high"]),
            BarChartView.Bar(id: "april", value: 60)
        ]
        let sub = UIView(frame: CGRect(x: 0, y: 80, width: 100, height: 20))
        chart.addSubview(sub)
        window.addSubview(chart)
        let store = ExtensionStore()
        store.describe(BarChartView.self, BarChartView.description, isView: true)
        return Chart(window: window, chart: chart, sub: sub, store: store)
    }

    private func nodes(
        after layer: CALayer,
        in hierarchy: Hierarchy,
        registry: LayerRegistry
    ) -> ArraySlice<LayerNode> {
        let id = registry.register(layer)
        let index = hierarchy.nodes.firstIndex { $0.id == id } ?? hierarchy.nodes.endIndex
        return hierarchy.nodes[(index + 1)...]
    }

    // MARK: - S-HIER-17

    func test_S_HIER_17_virtualNodesComeAfterTheirLayerAndBeforeItsSublayers() throws {
        let made = try makeChart()
        let window = made.window
        let chart = made.chart
        let sub = made.sub
        let store = made.store
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let chartID = registry.register(chart.layer)
        let following = Array(nodes(after: chart.layer, in: hierarchy, registry: registry).prefix(5))
        XCTAssertEqual(following.map(\.nodeKind), [.virtual, .virtual, .virtual, .virtual, .layer])
        XCTAssertEqual(following.map(\.name), ["March", "low", "high", "April", nil])
        XCTAssertEqual(following.map(\.className), [
            String(reflecting: BarChartView.Bar.self),
            "Part",
            "Part",
            String(reflecting: BarChartView.Bar.self),
            "CALayer"
        ])
        XCTAssertEqual(following[0].displayClassName, "Bar")
        XCTAssertEqual(following[4].id, registry.register(sub.layer))
        // Parents: the bars are the chart's, the parts the first bar's; the subview the chart's.
        XCTAssertEqual(following.map(\.parentID), [chartID, following[0].id, following[0].id, chartID, chartID])
    }

    func test_S_HIER_17_virtualNodesHaveTheFieldsOfP_HIER_20() throws {
        let made = try makeChart()
        let window = made.window
        let chart = made.chart
        let store = made.store
        chart.bars[1].value = 50
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let virtual = nodes(after: chart.layer, in: hierarchy, registry: registry).filter { $0.nodeKind == .virtual }
        let april = try XCTUnwrap(virtual.first { $0.name == "April" })
        XCTAssertEqual(april.bounds, WireRect(x: 0, y: 0, width: 20, height: 50))
        XCTAssertEqual(april.position, WirePoint(x: 30, y: 25))
        XCTAssertEqual(april.anchorPoint, WirePoint(x: 0.5, y: 0.5))
        XCTAssertEqual(april.transform, .identity)
        XCTAssertEqual(april.zPosition, 0)
        XCTAssertFalse(april.masksToBounds)
        XCTAssertFalse(april.isHidden)
        XCTAssertEqual(april.opacity, 1)
        XCTAssertEqual(april.layerClassOrigin, .app)
        XCTAssertEqual(april.layerAddress, 0)
        XCTAssertNil(april.viewClassName)
        XCTAssertNil(april.viewAddress)
        XCTAssertNil(april.viewControllerClassName)
        XCTAssertNil(april.layerBaseClassName)
        XCTAssertEqual(april.viewClassOrigin, .unknown)
        XCTAssertEqual(april.memberReferences, [])
        XCTAssertFalse(april.isCollapsedByDefault)
        XCTAssertFalse(april.isCaptureExcluded)
        // A part is in its bar's coordinate space.
        let high = try XCTUnwrap(virtual.first { $0.name == "high" })
        XCTAssertEqual(high.position, WirePoint(x: 10, y: 7.5))
    }

    func test_S_HIER_17_theHostAppsTransformHiddenAndOpacity() throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        window.addSubview(view)
        let store = ExtensionStore()
        let rotation = CGAffineTransform(rotationAngle: .pi / 6)
        store.describe(UIView.self, CutawayServer.Description(virtualChildren: { _ in
            [
                CutawayServer.VirtualNode(
                    id: 1,
                    typeName: "Dial",
                    frame: CGRect(x: 10, y: 10, width: 30, height: 30),
                    transform: rotation,
                    isHidden: true,
                    opacity: 0.25,
                    isCollapsedByDefault: true
                ),
                // A negative size is the same rectangle.
                CutawayServer.VirtualNode(id: 2, typeName: "Dial", frame: CGRect(x: 50, y: 50, width: -10, height: -20))
            ]
        }), isView: true)
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let dials = nodes(after: view.layer, in: hierarchy, registry: registry).prefix(2)
        XCTAssertEqual(dials.first?.transform, WireGeometry.transform(CATransform3DMakeAffineTransform(rotation)))
        XCTAssertEqual(dials.first?.isHidden, true)
        XCTAssertEqual(dials.first?.opacity, 0.25)
        XCTAssertEqual(dials.first?.isCollapsedByDefault, true)
        XCTAssertEqual(dials.last?.bounds, WireRect(x: 0, y: 0, width: 10, height: 20))
        XCTAssertEqual(dials.last?.position, WirePoint(x: 45, y: 40))
    }

    func test_S_HIER_17_idsStayWithTheIdentity() throws {
        let made = try makeChart()
        let window = made.window
        let chart = made.chart
        let store = made.store
        let registry = LayerRegistry()
        func ids() -> [String: UInt64] {
            let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
            let virtual = hierarchy.nodes.filter { $0.nodeKind == .virtual }
            return Dictionary(uniqueKeysWithValues: virtual.map { ($0.name ?? "", $0.id) })
        }
        let first = ids()
        // Reordered, and with the part moved to the other bar: every node keeps its ID.
        chart.bars = [
            BarChartView.Bar(id: "april", value: 60, parts: ["low"]),
            BarChartView.Bar(id: "march", value: 40, parts: ["high"])
        ]
        let second = ids()
        XCTAssertEqual(second, first)
        // A new identity gets a new ID, never one given out before.
        chart.bars.append(BarChartView.Bar(id: "may", value: 10))
        let third = ids()
        XCTAssertGreaterThan(try XCTUnwrap(third["May"]), first.values.max() ?? 0)
    }

    func test_S_HIER_17_aRepeatedIdentityIsLeftOutWithItsSubtree() throws {
        let made = try makeChart()
        let window = made.window
        let chart = made.chart
        let store = made.store
        chart.bars = [
            BarChartView.Bar(id: "march", value: 40),
            BarChartView.Bar(id: "march", value: 60, parts: ["unique"]),
            // A part that repeats a bar's identity is left out too.
            BarChartView.Bar(id: "april", value: 30, parts: ["march"])
        ]
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let virtual = hierarchy.nodes.filter { $0.nodeKind == .virtual }
        XCTAssertEqual(virtual.map(\.name), ["March", "April"])
        XCTAssertFalse(virtual.contains { $0.name == "unique" })
        XCTAssertEqual(virtual.first?.bounds.size.height, 40)
    }

    func test_S_HIER_17_aClientBefore1_2GetsNoVirtualNodes() throws {
        let made = try makeChart()
        let window = made.window
        let chart = made.chart
        let store = made.store
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(
            windows: [window],
            registry: registry,
            version: v11,
            extensions: store
        ))
        XCTAssertFalse(hierarchy.nodes.contains { $0.nodeKind == .virtual })
        XCTAssertEqual(registry.virtualIDs.count, 0)
        let subtree = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: registry.register(chart.layer),
                in: .testing(windows: [window], registry: registry, version: v11, extensions: store)
            )
        )
        XCTAssertFalse(subtree.nodes.contains { $0.nodeKind == .virtual })
    }

    func test_S_HIER_17_withNothingRegisteredTheHierarchyIsAsBefore() throws {
        let made = try makeChart()
        let window = made.window
        let registry = LayerRegistry()
        let before = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(
            HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: ExtensionStore())),
            before
        )
        // A description of another class, or only a color, changes nothing either.
        let other = ExtensionStore()
        other.describe(SpecialBarChartView.self, CutawayServer.Description(isExcludedFromCapture: true), isView: true)
        other.registerColor(.red, named: "brand")
        XCTAssertEqual(
            HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: other)),
            before
        )
        XCTAssertFalse(before.nodes.contains { $0.isCollapsedByDefault || $0.isCaptureExcluded })
    }

    // MARK: - Subtrees

    func test_S_HIER_17_aLayersSubtreeHasItsVirtualNodes() throws {
        let made = try makeChart()
        let window = made.window
        let chart = made.chart
        let store = made.store
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let chartID = registry.register(chart.layer)
        let subtree = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: chartID,
                in: .testing(windows: [window], registry: registry, extensions: store)
            )
        )
        let start = try XCTUnwrap(hierarchy.nodes.firstIndex { $0.id == chartID })
        XCTAssertEqual(subtree.nodes, Array(hierarchy.nodes[start..<(start + subtree.nodes.count)]))
        XCTAssertEqual(subtree.nodes.count, 6)
    }

    func test_S_HIER_17_aVirtualNodesSubtree() throws {
        let made = try makeChart()
        let window = made.window
        let chart = made.chart
        let store = made.store
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let virtual = hierarchy.nodes.filter { $0.nodeKind == .virtual }
        let march = try XCTUnwrap(virtual.first { $0.name == "March" })
        let subtree = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: march.id,
                in: .testing(windows: [window], registry: registry, extensions: store)
            )
        )
        // The bar and its two parts, exactly as in the hierarchy; the bar keeps its parent.
        XCTAssertEqual(subtree.nodes, Array(virtual.prefix(3)))
        XCTAssertEqual(subtree.nodes.first?.parentID, registry.register(chart.layer))
        XCTAssertEqual(subtree.keyWindowID, hierarchy.keyWindowID)
        // A part's subtree is the part; its parent is the bar.
        let part = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: virtual[1].id,
                in: .testing(windows: [window], registry: registry, extensions: store)
            )
        )
        XCTAssertEqual(part.nodes, [virtual[1]])
        XCTAssertEqual(part.nodes.first?.parentID, march.id)
    }

    func test_S_HIER_17_aVirtualNodeStopsExisting() throws {
        let made = try makeChart()
        let window = made.window
        let chart = made.chart
        let store = made.store
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let virtual = hierarchy.nodes.filter { $0.nodeKind == .virtual }
        func subtree(_ id: UInt64) -> Hierarchy? {
            HierarchyCapture.captureSubtree(
                rootID: id,
                in: .testing(windows: [window], registry: registry, extensions: store)
            )
        }
        // The host app no longer gives April.
        chart.bars.removeLast()
        XCTAssertNil(subtree(try XCTUnwrap(virtual.last?.id)))
        XCTAssertNotNil(subtree(try XCTUnwrap(virtual.first?.id)))
        // Its layer left the window.
        chart.removeFromSuperview()
        XCTAssertNil(subtree(try XCTUnwrap(virtual.first?.id)))
        // An ID that is no node at all.
        XCTAssertNil(subtree(9999))
    }

    // MARK: - S-HIER-18

    func test_S_HIER_18_collapsedByDefault() throws {
        let window = try makeWindow()
        let chart = BarChartView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        let special = SpecialChart(frame: CGRect(x: 0, y: 60, width: 50, height: 50))
        let plain = UIView(frame: CGRect(x: 60, y: 0, width: 50, height: 50))
        chart.bars = [BarChartView.Bar(id: "march", value: 10)]
        window.addSubview(chart)
        window.addSubview(special)
        window.addSubview(plain)
        let store = ExtensionStore()
        var description = BarChartView.description
        description.isCollapsedByDefault = true
        store.describe(BarChartView.self, description, isView: true)
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        XCTAssertTrue(try node(of: chart.layer, in: hierarchy, registry: registry).isCollapsedByDefault)
        XCTAssertTrue(try node(of: special.layer, in: hierarchy, registry: registry).isCollapsedByDefault)
        XCTAssertFalse(try node(of: plain.layer, in: hierarchy, registry: registry).isCollapsedByDefault)
        // Not inherited by the children; a virtual node has its own.
        XCTAssertEqual(hierarchy.nodes.filter(\.isCollapsedByDefault).count, 2)
    }

    // MARK: - S-SHOT-13

    func test_S_SHOT_13_anExcludedViewMarksItsWholeSubtree() throws {
        let made = try makeChart()
        let window = made.window
        let chart = made.chart
        let sub = made.sub
        let store = made.store
        let grandchild = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: 5))
        sub.addSubview(grandchild)
        let sibling = UIView(frame: CGRect(x: 200, y: 0, width: 5, height: 5))
        window.addSubview(sibling)
        var description = BarChartView.description
        description.isExcludedFromCapture = true
        store.describe(BarChartView.self, description, isView: true)
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let chartID = registry.register(chart.layer)
        let excluded = hierarchy.nodes.filter(\.isCaptureExcluded)
        // The chart, its four virtual nodes, its subview and the subview's child.
        XCTAssertEqual(excluded.count, 7)
        XCTAssertEqual(excluded.first?.id, chartID)
        XCTAssertFalse(try node(of: sibling.layer, in: hierarchy, registry: registry).isCaptureExcluded)
        XCTAssertFalse(try node(of: window.layer, in: hierarchy, registry: registry).isCaptureExcluded)

        // A subtree inside it says so too, as does a virtual node's.
        let inside = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: registry.register(sub.layer),
                in: .testing(windows: [window], registry: registry, extensions: store)
            )
        )
        XCTAssertTrue(inside.nodes.allSatisfy(\.isCaptureExcluded))
        let bar = try XCTUnwrap(hierarchy.nodes.first { $0.nodeKind == .virtual })
        let barSubtree = try XCTUnwrap(
            HierarchyCapture.captureSubtree(
                rootID: bar.id,
                in: .testing(windows: [window], registry: registry, extensions: store)
            )
        )
        XCTAssertTrue(barSubtree.nodes.allSatisfy(\.isCaptureExcluded))
    }

    // MARK: - S-HIER-17: attributes on demand

    func test_S_HIER_17_theHierarchyDoesNotWorkOutAVirtualNodesAttributes() throws {
        let window = try makeWindow()
        let chart = BarChartView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        chart.bars = [BarChartView.Bar(id: "march", value: 40)]
        window.addSubview(chart)
        let count = CallCount()
        func groups() -> [CutawayServer.AttributeGroup] {
            count.calls += 1
            return [CutawayServer.AttributeGroup("bar", [.int("value", 40)])]
        }
        let store = ExtensionStore()
        let description = CutawayServer.Description<BarChartView>(virtualChildren: { chart in
            chart.bars.map { bar in
                CutawayServer.VirtualNode(id: bar.id, typeName: "Bar", frame: .zero, attributes: groups())
            }
        })
        store.describe(BarChartView.self, description, isView: true)
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry, extensions: store))
        let node = try XCTUnwrap(hierarchy.nodes.first { $0.nodeKind == .virtual })
        XCTAssertEqual(count.calls, 0)
        // Reading the node's attributes works them out, once.
        let context = RequestContext.testing(windows: [window], registry: registry, extensions: store)
        let found = try XCTUnwrap(VirtualNodes.find(node.id, in: context))
        XCTAssertEqual(NodeAttributes(context: context).read(found).map(\.id), ["app.bar"])
        XCTAssertEqual(count.calls, 1)
    }
}

/// A subclass of a described class.
private final class SpecialChart: BarChartView {}

/// How often a closure of the host app was called.
@MainActor
private final class CallCount {
    var calls = 0
}
