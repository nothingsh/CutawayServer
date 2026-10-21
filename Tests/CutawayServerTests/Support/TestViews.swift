import UIKit

@testable import CutawayServer

// Views and data sources that tests in several files share. A fixture that one file uses
// stays in that file, private.

// MARK: - Counting

/// Counts how often UIKit lays it out and draws it.
final class CountingView: UIView {
    private(set) var layoutCount = 0
    private(set) var drawCount = 0

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCount += 1
    }

    override func draw(_ rect: CGRect) {
        drawCount += 1
    }
}

/// Counts its layouts.
final class CountingTableView: UITableView {
    private(set) var layouts = 0

    override func layoutSubviews() {
        layouts += 1
        super.layoutSubviews()
    }
}

/// Counts its layouts.
final class CountingCollectionView: UICollectionView {
    private(set) var layouts = 0

    override func layoutSubviews() {
        layouts += 1
        super.layoutSubviews()
    }
}

/// Two sections of 3 and 5 rows or items, for a table or a collection view; counts every call.
final class CountingDataSource: NSObject, UITableViewDataSource, UICollectionViewDataSource {
    var rows = [3, 5]
    var items: [Int] {
        get { rows }
        set { rows = newValue }
    }

    private(set) var calls = 0

    func numberOfSections(in tableView: UITableView) -> Int {
        calls += 1
        return rows.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        calls += 1
        return rows[section]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        calls += 1
        return tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        calls += 1
        return rows.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        calls += 1
        return rows[section]
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        calls += 1
        return collectionView.dequeueReusableCell(withReuseIdentifier: "item", for: indexPath)
    }
}

/// A view controller that is a table's data source, with two sections of 3 and 5 rows.
final class SourceController: UIViewController, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [3, 5][section] }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
    }
}

// MARK: - Described by the host app

/// A view that draws bars of its own: the host app describes each as a virtual node.
class BarChartView: UIView {
    struct Bar {
        var id: String
        var value: Double
        var parts: [String] = []
    }

    var bars: [Bar] = []

    /// The bars side by side, 20 points wide, as tall as their value; each part 5 points tall
    /// from the bar's top.
    static let description = CutawayServer.Description<BarChartView>(virtualChildren: { chart in
        chart.bars.enumerated().map { index, bar in
            CutawayServer.VirtualNode(
                id: bar.id,
                type: Bar.self,
                name: bar.id.capitalized,
                frame: CGRect(x: Double(index) * 20, y: 0, width: 20, height: bar.value),
                children: bar.parts.enumerated().map { partIndex, part in
                    CutawayServer.VirtualNode(
                        id: part,
                        typeName: "Part",
                        name: part,
                        frame: CGRect(x: 0, y: Double(partIndex) * 5, width: 20, height: 5)
                    )
                }
            )
        }
    })
}

/// A chart that draws its bars itself, bottom up, each 20 points wide; the host app describes
/// each bar as a virtual node whose value can be changed.
final class DrawnChartView: UIView {
    struct Bar {
        var id: String
        var value: Double
    }

    struct TooTall: LocalizedError {
        var errorDescription: String? { "the bar would be taller than the chart" }
    }

    var bars: [Bar] = [] {
        didSet { setNeedsDisplay() }
    }

    var barColor = UIColor.blue {
        didSet { setNeedsDisplay() }
    }

    /// The values `set` received, in order.
    var written: [String] = []

    override func draw(_ rect: CGRect) {
        UIColor.white.setFill()
        UIRectFill(bounds)
        barColor.setFill()
        for (index, bar) in bars.enumerated() {
            UIRectFill(CGRect(x: Double(index) * 20, y: bounds.height - bar.value, width: 20, height: bar.value))
        }
    }

    static let description = CutawayServer.Description<DrawnChartView>(
        attributes: { chart in
            [
                CutawayServer.AttributeGroup("chart", [
                    .int("barCount", chart.bars.count),
                    .color("barColor", chart.barColor, section: .appearance, set: { color in
                        chart.written.append("barColor")
                        chart.barColor = color ?? .blue
                    })
                ])
            ]
        },
        virtualChildren: { chart in
            chart.bars.indices.map { index in
                CutawayServer.VirtualNode(
                    id: chart.bars[index].id,
                    typeName: "Bar",
                    frame: CGRect(
                        x: Double(index) * 20,
                        y: chart.bounds.height - chart.bars[index].value,
                        width: 20,
                        height: chart.bars[index].value
                    ),
                    attributes: [
                        CutawayServer.AttributeGroup("bar", [
                            .double(
                                "value",
                                chart.bars[index].value,
                                section: .content,
                                unit: .points,
                                limits: [.atLeast(0)],
                                set: { value in
                                    chart.written.append("value \(value ?? .nan)")
                                    guard let value, value <= chart.bounds.height else { throw TooTall() }
                                    chart.bars[index].value = value
                                }
                            )
                        ])
                    ]
                )
            }
        }
    )
}

// MARK: - Holders of references

// For the order of the references a holder's variables give and of the nodes of a subtree. Their
// runtime names are part of what the tests expect, so they are not private.
class OrderBaseController: UIViewController {
    var baseTarget: UIView?
}

final class OrderController: OrderBaseController {
    var first: UIView?
    var second: UIView?
    override func loadView() { view = OrderRootView() }
}

final class OrderRootView: UIView { var target: UIView? }
final class OrderOuterView: UIView { var target: UIView? }
final class OrderInnerView: UIView { var target: UIView? }
