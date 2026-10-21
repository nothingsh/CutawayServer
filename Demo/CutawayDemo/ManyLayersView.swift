import UIKit

/// Rows of small cells, each cell a view with a layer of its own, all placed by
/// constraints: a large hierarchy for the demo's "Many layers" page and for the stability
/// tests (the large hierarchy and the long use). The test bundle compiles this file too, so that the page
/// shows the tree the tests measure.
final class ManyLayersView: UIView {
    let rows: Int
    let columns: Int
    /// The size of one cell, in points.
    let cellSize: CGSize
    /// The rows, top to bottom; also their order among the subviews.
    private(set) var rowViews: [UIView] = []
    /// Picks the rows `replaceRows` replaces, the same ones on every run.
    private var randomState: UInt64

    init(rows: Int, columns: Int, cellSize: CGSize = CGSize(width: 7, height: 8), seed: UInt64 = 18) {
        self.rows = rows
        self.columns = columns
        self.cellSize = cellSize
        randomState = seed
        super.init(
            frame: CGRect(
                x: 0,
                y: 0,
                width: CGFloat(columns) * cellSize.width,
                height: CGFloat(rows) * cellSize.height
            )
        )
        backgroundColor = .white
        rowViews = (0..<rows).map(insertRow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: CGFloat(columns) * cellSize.width, height: CGFloat(rows) * cellSize.height)
    }

    /// This view, its rows, its cells and a layer in each cell.
    var layerCount: Int { 1 + rows + 2 * rows * columns }
    /// This view, its rows and its cells.
    var viewCount: Int { 1 + rows + rows * columns }
    /// Four for each row and four for each cell.
    var constraintCount: Int { 4 * rows + 4 * rows * columns }

    /// Takes `count` rows out, picked at random, and puts new ones with new cells in their
    /// places. Returns the rows that were taken out.
    @discardableResult
    func replaceRows(_ count: Int) -> [UIView] {
        var removed: [UIView] = []
        for _ in 0..<count {
            let index = nextIndex(below: rows)
            let old = rowViews[index]
            old.removeFromSuperview()
            removed.append(old)
            rowViews[index] = insertRow(index)
        }
        return removed
    }

    /// A new row with its cells, at `row` among the subviews.
    private func insertRow(_ row: Int) -> UIView {
        let rowView = UIView()
        rowView.translatesAutoresizingMaskIntoConstraints = false
        rowView.backgroundColor = UIColor(white: row % 2 == 0 ? 0.95 : 0.85, alpha: 1)
        insertSubview(rowView, at: row)
        NSLayoutConstraint.activate([
            rowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: trailingAnchor),
            rowView.topAnchor.constraint(equalTo: topAnchor, constant: CGFloat(row) * cellSize.height),
            rowView.heightAnchor.constraint(equalToConstant: cellSize.height)
        ])
        for column in 0..<columns {
            let cell = UIView()
            cell.translatesAutoresizingMaskIntoConstraints = false
            cell.backgroundColor = UIColor(
                hue: CGFloat((row * 7 + column * 3) % 36) / 36,
                saturation: 0.6,
                brightness: 0.9,
                alpha: 1
            )
            let dot = CALayer()
            dot.frame = CGRect(x: 1, y: 1, width: cellSize.width / 2, height: cellSize.height / 2)
            dot.backgroundColor = UIColor.white.cgColor
            cell.layer.addSublayer(dot)
            rowView.addSubview(cell)
            NSLayoutConstraint.activate([
                cell.leadingAnchor.constraint(
                    equalTo: rowView.leadingAnchor,
                    constant: CGFloat(column) * cellSize.width
                ),
                cell.topAnchor.constraint(equalTo: rowView.topAnchor),
                cell.widthAnchor.constraint(equalToConstant: cellSize.width),
                cell.heightAnchor.constraint(equalToConstant: cellSize.height)
            ])
        }
        return rowView
    }

    /// A linear congruential generator: the same rows on every run.
    private func nextIndex(below bound: Int) -> Int {
        randomState = randomState &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((randomState >> 33) % UInt64(bound))
    }
}
