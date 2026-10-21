#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

// The groups of lists and their cells (protocol 1.2). Counts are read from what a list has
// loaded; they never ask its data source. A table answers them from what it loaded, also between
// `reloadData()` and its next layout; a collection view does too once laid out.
extension AttributeCatalog {
    static let tableViewGroup = GroupDefinition(
        "tableView",
        className: "UITableView",
        subject: { (_: CALayer, view: UIView?) in view as? UITableView },
        [
            .references("dataSource", title: "Data Source", section: .content) {
                $0.dataSource.map { [$0 as AnyObject] }
            },
            .init(
                "numberOfSections",
                .int,
                title: "Sections",
                section: .content,
                cluster: ("listCounts", "sections"),
                write: nil
            ) { .int(Int64($0.numberOfSections)) },
            .init(
                "numberOfRows",
                .int,
                title: "Rows",
                section: .content,
                cluster: ("listCounts", "items"),
                write: nil,
                readWith: { .int(Int64($1.rowCounts(of: $0).reduce(0, +))) }
            ),
            .init("rowsPerSection", .string, title: "Rows per Section", section: .content, write: nil) {
                .string(AttributeTexts.list($1.rowCounts(of: $0), String.init))
            },
            .init("visibleIndexPaths", .string, title: "Visible Rows", section: .content, write: nil) {
                .string(AttributeTexts.indexPaths($0.indexPathsForVisibleRows ?? []))
            }
        ] as [AttributeDefinition<UITableView>]
    )

    /// Between `reloadData()` and the next layout a collection view's counts would ask its data
    /// source; it needs layout then, and they are nil (`AttributeReading.itemCounts(of:)`).
    static let collectionViewGroup = GroupDefinition(
        "collectionView",
        className: "UICollectionView",
        subject: { (_: CALayer, view: UIView?) in view as? UICollectionView },
        [
            .references("dataSource", title: "Data Source", section: .content) {
                $0.dataSource.map { [$0 as AnyObject] }
            },
            .init(
                "numberOfSections",
                .int,
                title: "Sections",
                section: .content,
                cluster: ("listCounts", "sections"),
                write: nil,
                readWith: { $1.itemCounts(of: $0).map { .int(Int64($0.count)) } }
            ),
            .init(
                "numberOfItems",
                .int,
                title: "Items",
                section: .content,
                cluster: ("listCounts", "items"),
                write: nil,
                readWith: { $1.itemCounts(of: $0).map { .int(Int64($0.reduce(0, +))) } }
            ),
            .init("itemsPerSection", .string, title: "Items per Section", section: .content, write: nil) {
                $1.itemCounts(of: $0).map { .string(AttributeTexts.list($0, String.init)) }
            },
            .init("visibleIndexPaths", .string, title: "Visible Items", section: .content, write: nil) {
                .string(AttributeTexts.indexPaths($0.indexPathsForVisibleItems))
            }
        ] as [AttributeDefinition<UICollectionView>]
    )

    static let tableViewCellGroup = GroupDefinition(
        "tableViewCell",
        className: "UITableViewCell",
        subject: { (_: CALayer, view: UIView?) in view as? UITableViewCell },
        [
            .init("section", .int, section: .content, cluster: ("indexPath", "section"), write: nil) {
                indexPath(of: $0).map { .int(Int64($0.section)) }
            },
            .init("row", .int, section: .content, cluster: ("indexPath", "item"), write: nil) {
                indexPath(of: $0).map { .int(Int64($0.row)) }
            },
            .init("reuseIdentifier", .string, section: .identity, write: nil) {
                $0.reuseIdentifier.map { .string($0) }
            }
        ] as [AttributeDefinition<UITableViewCell>]
    )

    static let collectionViewCellGroup = GroupDefinition(
        "collectionViewCell",
        className: "UICollectionViewCell",
        subject: { (_: CALayer, view: UIView?) in view as? UICollectionViewCell },
        [
            .init("section", .int, section: .content, cluster: ("indexPath", "section"), write: nil) {
                indexPath(of: $0).map { .int(Int64($0.section)) }
            },
            .init("item", .int, section: .content, cluster: ("indexPath", "item"), write: nil) {
                indexPath(of: $0).map { .int(Int64($0.item)) }
            },
            .init("reuseIdentifier", .string, section: .identity, write: nil) {
                $0.reuseIdentifier.map { .string($0) }
            }
        ] as [AttributeDefinition<UICollectionViewCell>]
    )

    /// Where the nearest table above the cell has it; `nil` outside a table, or when the table
    /// cannot tell.
    private static func indexPath(of cell: UITableViewCell) -> IndexPath? {
        enclosing(UITableView.self, of: cell)?.indexPath(for: cell)
    }

    private static func indexPath(of cell: UICollectionViewCell) -> IndexPath? {
        enclosing(UICollectionView.self, of: cell)?.indexPath(for: cell)
    }

    private static func enclosing<List: UIView>(_: List.Type, of view: UIView) -> List? {
        var current = view.superview
        while let ancestor = current {
            if let list = ancestor as? List { return list }
            current = ancestor.superview
        }
        return nil
    }
}
#endif
