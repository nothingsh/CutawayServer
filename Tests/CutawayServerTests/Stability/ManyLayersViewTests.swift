import UIKit
import XCTest

/// The tree the stability tests and the demo's "Many layers" page share.
final class ManyLayersViewTests: CaptureTestCase {
    private func allLayers(under layer: CALayer) -> [CALayer] {
        [layer] + (layer.sublayers ?? []).flatMap(allLayers(under:))
    }

    private func allViews(under view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(allViews(under:))
    }

    /// The constraints the tree made itself; UIKit's own are of other classes.
    private func ownConstraints(of tree: ManyLayersView) -> [NSLayoutConstraint] {
        allViews(under: tree).flatMap(\.constraints).filter { type(of: $0) == NSLayoutConstraint.self }
    }

    func test_S_STAB_01_theTreeHasTheLayersViewsAndConstraintsItPromises() throws {
        let window = try makeWindow()
        let tree = ManyLayersView(rows: 3, columns: 4)
        window.addSubview(tree)
        window.layoutIfNeeded()

        XCTAssertEqual(tree.layerCount, 1 + 3 + 2 * 12)
        XCTAssertEqual(allLayers(under: tree.layer).count, tree.layerCount)
        XCTAssertEqual(allViews(under: tree).count, tree.viewCount)
        XCTAssertEqual(ownConstraints(of: tree).count, tree.constraintCount)
        XCTAssertEqual(tree.bounds.size, CGSize(width: 28, height: 24))
        for (row, rowView) in tree.rowViews.enumerated() {
            XCTAssertEqual(rowView.frame, CGRect(x: 0, y: CGFloat(row) * 8, width: 28, height: 8))
            for (column, cell) in rowView.subviews.enumerated() {
                XCTAssertEqual(cell.frame, CGRect(x: CGFloat(column) * 7, y: 0, width: 7, height: 8))
                XCTAssertEqual(cell.layer.sublayers?.count, 1)
            }
        }
    }

    func test_S_STAB_02_replacingRowsKeepsTheCountsAndReleasesTheOldRows() async throws {
        let window = try makeWindow()
        let tree = ManyLayersView(rows: 4, columns: 3)
        window.addSubview(tree)
        window.layoutIfNeeded()
        let before = tree.rowViews.map(ObjectIdentifier.init)

        weak var oldRow: UIView?
        weak var oldCellLayer: CALayer?
        do {
            let removed = tree.replaceRows(2)
            XCTAssertEqual(removed.count, 2)
            oldRow = removed[0]
            oldCellLayer = removed[0].subviews[0].layer
            for row in removed {
                XCTAssertNil(row.superview)
                XCTAssertFalse(tree.rowViews.contains(row))
            }
        }
        window.layoutIfNeeded()

        XCTAssertEqual(tree.subviews, tree.rowViews, "the rows stay in their order")
        XCTAssertNotEqual(tree.rowViews.map(ObjectIdentifier.init), before)
        XCTAssertEqual(allLayers(under: tree.layer).count, tree.layerCount)
        XCTAssertEqual(ownConstraints(of: tree).count, tree.constraintCount)
        for (row, rowView) in tree.rowViews.enumerated() {
            XCTAssertEqual(rowView.frame, CGRect(x: 0, y: CGFloat(row) * 8, width: 21, height: 8))
        }

        // UIKit may hold a view it just took out for a little while.
        let deadline = Date().addingTimeInterval(5)
        while oldRow != nil || oldCellLayer != nil {
            guard Date() < deadline else {
                XCTFail("the replaced row was not released")
                return
            }
            CATransaction.flush()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func test_S_STAB_02_theSameRowsAreReplacedOnEveryRun() throws {
        let first = ManyLayersView(rows: 10, columns: 1)
        let second = ManyLayersView(rows: 10, columns: 1)
        // The places whose row changed.
        let picked = { (tree: ManyLayersView) -> [Int] in
            let before = tree.rowViews.map(ObjectIdentifier.init)
            tree.replaceRows(4)
            return tree.rowViews.indices.filter { before[$0] != ObjectIdentifier(tree.rowViews[$0]) }
        }
        let places = picked(first)
        XCTAssertFalse(places.isEmpty)
        XCTAssertEqual(places, picked(second))
    }
}
