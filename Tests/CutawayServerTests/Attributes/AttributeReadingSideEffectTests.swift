import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// A table's data source whose view is never loaded by the test.
private final class UnloadedController: UIViewController, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 2 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
    }
}

/// S-ATTR-23: reading every attribute of every layer changes nothing: no layout, no call to a
/// data source, no view controller's view loaded.
final class AttributeReadingSideEffectTests: CaptureTestCase {
    private var retained: [AnyObject] = []

    private func allLayers(under layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap(allLayers(under:))
    }

    private struct Scene {
        let window: UIWindow
        let tables: [CountingTableView]
        let collections: [CountingCollectionView]
        let sources: [CountingDataSource]
    }

    /// Lists laid out, lists reloaded and not laid out again, and everything else the attributes
    /// of 1.2 read.
    private func makeScene() throws -> Scene {
        let window = try makeWindow()
        var tables: [CountingTableView] = []
        var collections: [CountingCollectionView] = []
        var sources: [CountingDataSource] = []
        for index in 0..<2 {
            let source = CountingDataSource()
            sources.append(source)
            let table = CountingTableView(frame: CGRect(x: 0, y: CGFloat(index) * 100, width: 160, height: 100))
            table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
            table.dataSource = source
            tables.append(table)
            let layout = UICollectionViewFlowLayout()
            layout.itemSize = CGSize(width: 40, height: 40)
            let collection = CountingCollectionView(
                frame: CGRect(x: 160, y: CGFloat(index) * 100, width: 160, height: 100),
                collectionViewLayout: layout
            )
            collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "item")
            collection.dataSource = source
            collections.append(collection)
            window.addSubview(table)
            window.addSubview(collection)
        }
        let controller = UnloadedController()
        let unloaded = CountingTableView(frame: CGRect(x: 0, y: 200, width: 160, height: 100))
        unloaded.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        unloaded.dataSource = controller
        window.addSubview(unloaded)
        tables.append(unloaded)
        retained += sources + [controller]

        let stack = UIStackView(arrangedSubviews: [
            UILabel(),
            UIImageView(image: UIImage(systemName: "star")),
            UIView()
        ])
        stack.frame = CGRect(x: 0, y: 300, width: 300, height: 40)
        stack.setCustomSpacing(8, after: stack.arrangedSubviews[0])
        let label = UILabel(frame: CGRect(x: 0, y: 340, width: 200, height: 40))
        label.numberOfLines = 2
        label.text = TextAttributeTests.longText
        label.font = .preferredFont(forTextStyle: .body)
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "heart"), for: .normal)
        button.frame = CGRect(x: 200, y: 340, width: 100, height: 40)
        for view in [stack, label, button] as [UIView] { window.addSubview(view) }
        window.layoutIfNeeded()

        // The second of each kind is reloaded and waits for its next layout.
        sources[1].rows = [4, 2, 1]
        tables[1].reloadData()
        collections[1].reloadData()
        return Scene(window: window, tables: tables, collections: collections, sources: sources)
    }

    func test_S_ATTR_23_readingEveryLayerChangesNothing() throws {
        let scene = try makeScene()
        let (window, tables, collections, sources) = (scene.window, scene.tables, scene.collections, scene.sources)
        let controller = try XCTUnwrap(tables[2].dataSource as? UnloadedController)
        let layers = allLayers(under: window.layer)
        let layouts = (tables.map(\.layouts), collections.map(\.layouts))
        let calls = sources.map(\.calls)
        let needsLayout = layers.map { $0.needsLayout() }

        let reading = AttributeReading(registry: LayerRegistry(), windows: [window])
        var read = 0
        for layer in layers {
            read += AttributeCatalog.standard.read(layer, reading: reading).count
        }
        XCTAssertGreaterThan(read, layers.count)

        XCTAssertEqual(tables.map(\.layouts), layouts.0, "reading laid a table out")
        XCTAssertEqual(collections.map(\.layouts), layouts.1, "reading laid a collection view out")
        XCTAssertEqual(sources.map(\.calls), calls, "reading asked a data source")
        XCTAssertEqual(layers.map { $0.needsLayout() }, needsLayout, "reading changed what needs layout")
        XCTAssertFalse(controller.isViewLoaded, "reading loaded a view controller's view")
        XCTAssertTrue(collections[1].layer.needsLayout(), "the reloaded collection view still waits")
    }
}
