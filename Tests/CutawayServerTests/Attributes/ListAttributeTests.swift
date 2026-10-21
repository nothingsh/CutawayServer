import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// The counts and positions of lists, and the custom spacing of stack views (S-ATTR-19). No
/// server, no connection.
final class ListAttributeTests: AttributeValueTestCase {
    private func makeTable(in window: UIWindow) -> (UITableView, SourceController) {
        let controller = SourceController()
        retained.append(controller)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), style: .plain)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.rowHeight = 44
        table.dataSource = controller
        window.addSubview(table)
        window.layoutIfNeeded()
        return (table, controller)
    }

    func test_S_ATTR_19_tableCountsAndVisibleRows() throws {
        let window = try makeWindow()
        let (table, _) = makeTable(in: window)
        XCTAssertEqual(try int("tableView.numberOfSections", of: table), 2)
        XCTAssertEqual(try int("tableView.numberOfRows", of: table), 8)
        XCTAssertEqual(try string("tableView.rowsPerSection", of: table), "3, 5")
        let visible = (table.indexPathsForVisibleRows ?? []).sorted()
        XCTAssertFalse(visible.isEmpty)
        XCTAssertEqual(
            try string("tableView.visibleIndexPaths", of: table),
            visible.map { "\($0.section).\($0.row)" }.joined(separator: ", ")
        )
    }

    func test_S_ATTR_19_cellsKnowWhereTheyAre() throws {
        let window = try makeWindow()
        let (table, _) = makeTable(in: window)
        let paths = try XCTUnwrap(table.indexPathsForVisibleRows)
        for path in paths {
            let cell = try XCTUnwrap(table.cellForRow(at: path))
            XCTAssertEqual(try int("tableViewCell.section", of: cell), Int64(path.section))
            XCTAssertEqual(try int("tableViewCell.row", of: cell), Int64(path.row))
            XCTAssertEqual(try string("tableViewCell.reuseIdentifier", of: cell), "row")
        }
        let loose = UITableViewCell(style: .default, reuseIdentifier: nil)
        window.addSubview(loose)
        XCTAssertNil(try int("tableViewCell.section", of: loose))
        XCTAssertNil(try int("tableViewCell.row", of: loose))
        XCTAssertNil(try string("tableViewCell.reuseIdentifier", of: loose))
    }

    private func makeCollection(in window: UIWindow) -> (UICollectionView, CountingDataSource) {
        let source = CountingDataSource()
        retained.append(source)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 60, height: 40)
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "item")
        collection.dataSource = source
        window.addSubview(collection)
        window.layoutIfNeeded()
        return (collection, source)
    }

    func test_S_ATTR_19_collectionCountsVisibleItemsAndCells() throws {
        let window = try makeWindow()
        let (collection, _) = makeCollection(in: window)
        XCTAssertEqual(try int("collectionView.numberOfSections", of: collection), 2)
        XCTAssertEqual(try int("collectionView.numberOfItems", of: collection), 8)
        XCTAssertEqual(try string("collectionView.itemsPerSection", of: collection), "3, 5")
        let visible = collection.indexPathsForVisibleItems.sorted()
        XCTAssertFalse(visible.isEmpty)
        XCTAssertEqual(
            try string("collectionView.visibleIndexPaths", of: collection),
            visible.map { "\($0.section).\($0.item)" }.joined(separator: ", ")
        )
        for path in visible {
            let cell = try XCTUnwrap(collection.cellForItem(at: path))
            XCTAssertEqual(try int("collectionViewCell.section", of: cell), Int64(path.section))
            XCTAssertEqual(try int("collectionViewCell.item", of: cell), Int64(path.item))
            XCTAssertEqual(try string("collectionViewCell.reuseIdentifier", of: cell), "item")
        }
    }

    /// Between `reloadData()` and the next layout the counts would ask the data source, so they
    /// are not read.
    func test_S_ATTR_19_reloadedCollectionGivesNoCounts() throws {
        let window = try makeWindow()
        let (collection, source) = makeCollection(in: window)
        source.items = [1, 2]
        collection.reloadData()
        let calls = source.calls
        XCTAssertNil(try int("collectionView.numberOfSections", of: collection))
        XCTAssertNil(try int("collectionView.numberOfItems", of: collection))
        XCTAssertNil(try string("collectionView.itemsPerSection", of: collection))
        XCTAssertNotNil(try string("collectionView.visibleIndexPaths", of: collection))
        XCTAssertEqual(source.calls, calls)
        window.layoutIfNeeded()
        XCTAssertEqual(try string("collectionView.itemsPerSection", of: collection), "1, 2")
    }

    func test_S_ATTR_19_longListsAreCut() {
        XCTAssertEqual(AttributeTexts.list([]), "None")
        XCTAssertEqual(AttributeTexts.list(["a", "b"]), "a, b")
        let long = (0..<150).map(String.init)
        let text = AttributeTexts.list(long)
        XCTAssertTrue(text.hasPrefix("0, 1, 2, "), text)
        XCTAssertTrue(text.hasSuffix(", 99, … (50 more)"), text)
        XCTAssertEqual(AttributeTexts.list(Array(long.prefix(100))).components(separatedBy: ", ").count, 100)
    }

    func test_S_ATTR_19_customSpacingListsWhatWasSet() throws {
        let window = try makeWindow()
        let views = [UIView(), UIView(), UIView()]
        let stack = UIStackView(arrangedSubviews: views)
        window.addSubview(stack)
        XCTAssertNil(try string("stackView.customSpacing", of: stack))
        stack.setCustomSpacing(12, after: views[0])
        stack.setCustomSpacing(UIStackView.spacingUseSystem, after: views[2])
        XCTAssertEqual(try string("stackView.customSpacing", of: stack), "after 0: 12, after 2: system")
        stack.setCustomSpacing(4.5, after: views[1])
        XCTAssertEqual(try string("stackView.customSpacing", of: stack), "after 0: 12, after 1: 4.5, after 2: system")
    }
}
