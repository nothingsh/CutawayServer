import UIKit
import XCTest

@testable import CutawayServer

private class ChartView: UIView {}
private final class SpecialChartView: ChartView {}
private class ChartLayer: CALayer {}
private final class LayeredChartView: UIView {
    override static var layerClass: AnyClass { ChartLayer.self }
}

/// What the host app registers, and how the descriptions of one layer are merged (S-API-04).
/// No server, no connection.
@MainActor
final class ExtensionLookupTests: XCTestCase {
    override func tearDown() async throws {
        ExtensionStore.shared.removeAll()
        try await super.tearDown()
    }

    /// A description whose group and virtual child are named `name`.
    private func description<Subject: AnyObject>(
        _ name: String,
        of _: Subject.Type,
        children: Bool = true,
        collapsed: Bool = false,
        excluded: Bool = false
    ) -> CutawayServer.Description<Subject> {
        var description = CutawayServer.Description<Subject>(
            isCollapsedByDefault: collapsed,
            isExcludedFromCapture: excluded
        )
        description.attributes = { _ in [CutawayServer.AttributeGroup(name, [])] }
        if children {
            description.virtualChildren = { _ in [CutawayServer.VirtualNode(id: name, typeName: name, frame: .zero)] }
        }
        return description
    }

    private func groups(_ resolved: ExtensionLookup.Resolved) -> [String] {
        resolved.attributeSources.flatMap { $0.description.attributes?($0.subject) ?? [] }.map(\.id)
    }

    private func children(_ resolved: ExtensionLookup.Resolved) -> [String] {
        resolved.virtualChildren().map(\.className)
    }

    private func resolve(_ view: UIView, in store: ExtensionStore) -> ExtensionLookup.Resolved {
        var lookup = ExtensionLookup(store: store)
        return lookup.resolve(view.layer, view: view)
    }

    func test_S_API_04_aDescriptionAppliesToSubclasses() {
        let store = ExtensionStore()
        store.describe(ChartView.self, description("chart", of: ChartView.self, collapsed: true), isView: true)
        let resolved = resolve(SpecialChartView(), in: store)
        XCTAssertEqual(groups(resolved), ["chart"])
        XCTAssertEqual(children(resolved), ["chart"])
        XCTAssertTrue(resolved.isCollapsedByDefault)
        XCTAssertFalse(resolved.isExcludedFromCapture)
        // Other views have nothing.
        let plain = resolve(UIView(), in: store)
        XCTAssertEqual(groups(plain), [])
        XCTAssertNil(plain.virtualSource)
        XCTAssertFalse(plain.isCollapsedByDefault)
    }

    func test_S_API_04_groupsComeFromEveryDescriptionAndChildrenFromTheMostSpecific() {
        let store = ExtensionStore()
        store.describe(SpecialChartView.self, description("special", of: SpecialChartView.self), isView: true)
        store.describe(ChartView.self, description("chart", of: ChartView.self, excluded: true), isView: true)
        let resolved = resolve(SpecialChartView(), in: store)
        XCTAssertEqual(groups(resolved), ["chart", "special"])
        XCTAssertEqual(children(resolved), ["special"])
        XCTAssertTrue(resolved.isExcludedFromCapture)

        // The most specific description that has children, not merely the most specific.
        store.describe(
            SpecialChartView.self,
            description("special", of: SpecialChartView.self, children: false),
            isView: true
        )
        XCTAssertEqual(children(resolve(SpecialChartView(), in: store)), ["chart"])
    }

    func test_S_API_04_theLayersDescriptionsComeBeforeTheViews() {
        let store = ExtensionStore()
        store.describe(LayeredChartView.self, description("view", of: LayeredChartView.self), isView: true)
        store.describe(ChartLayer.self, description("layer", of: ChartLayer.self, collapsed: true), isView: false)
        let resolved = resolve(LayeredChartView(), in: store)
        XCTAssertEqual(groups(resolved), ["layer", "view"])
        XCTAssertEqual(children(resolved), ["view"])
        XCTAssertTrue(resolved.isCollapsedByDefault)

        // A layer that backs no view has its own.
        var lookup = ExtensionLookup(store: store)
        let bare = lookup.resolve(ChartLayer(), view: nil)
        XCTAssertEqual(groups(bare), ["layer"])
        XCTAssertEqual(children(bare), ["layer"])
    }

    func test_S_API_04_registeringAgainReplaces() {
        let store = ExtensionStore()
        store.describe(ChartView.self, description("first", of: ChartView.self), isView: true)
        store.describe(ChartView.self, description("second", of: ChartView.self), isView: true)
        XCTAssertEqual(groups(resolve(ChartView(), in: store)), ["second"])

        store.registerColor(.red, named: "brand")
        store.registerColor(.blue, named: "accent")
        store.registerColor(.green, named: "brand")
        XCTAssertEqual(store.colors.map(\.name), ["brand", "accent"])
        XCTAssertEqual(store.colors.first?.color, .green)
    }

    func test_S_API_04_thePublicMethodsWriteTheSharedStore() {
        XCTAssertTrue(ExtensionStore.shared.isEmpty)
        CutawayServer.describe(ChartView.self, description("chart", of: ChartView.self))
        CutawayServer.describe(ChartLayer.self, description("layer", of: ChartLayer.self))
        CutawayServer.registerColor(.red, named: "brand")
        XCTAssertEqual(ExtensionStore.shared.viewDescriptions.count, 1)
        XCTAssertEqual(ExtensionStore.shared.layerDescriptions.count, 1)
        XCTAssertEqual(ExtensionStore.shared.colors.map(\.name), ["brand"])
        XCTAssertEqual(groups(resolve(ChartView(), in: .shared)), ["chart"])
    }

    func test_S_API_04_theDescriptionIsCalledWithItsOwnSubject() {
        let store = ExtensionStore()
        var seen: [UIView] = []
        store.describe(
            ChartView.self,
            CutawayServer.Description(attributes: { view in
                seen.append(view)
                return []
            }),
            isView: true
        )
        let view = SpecialChartView()
        _ = groups(resolve(view, in: store))
        XCTAssertEqual(seen.count, 1)
        XCTAssertTrue(seen.first === view)
    }
}
