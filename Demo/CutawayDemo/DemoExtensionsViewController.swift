import CutawayServer
import UIKit

/// The page of the host app's extensions, opened with "Extensions" on the detail page and
/// closed with "Close": a chart that draws its bars itself, shown as virtual nodes with
/// attributes of their own; a card number left out of every image; a registered color.
/// `cutaway-probe --expect-demo` checks it when it is open (Sources/cutaway-probe/Demo/).
///
/// As on the main screen, everything the probe looks at is held in a property and has a fixed
/// frame. What Cutaway shows of it is registered once, by `DemoExtensions.register()`.
final class DemoExtensionsViewController: UIViewController {
    private let closeButton = UIButton(type: .system)
    private let salesChart = SalesChartView(frame: CGRect(x: 16, y: 100, width: 300, height: 200))
    private let cardNumber = CardNumberView(frame: CGRect(x: 16, y: 320, width: 300, height: 60))
    private let brandSwatch = UIView(frame: CGRect(x: 16, y: 400, width: 60, height: 60))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        closeButton.setTitle("Close", for: .normal)
        closeButton.frame = CGRect(x: 16, y: 50, width: 80, height: 30)
        closeButton.addTarget(self, action: #selector(closePage), for: .touchUpInside)
        view.addSubview(closeButton)

        view.addSubview(salesChart)
        view.addSubview(cardNumber)

        brandSwatch.backgroundColor = DemoExtensions.brandBlue
        view.addSubview(brandSwatch)
    }

    @objc private func closePage() {
        dismiss(animated: true)
    }
}

/// What the demo registers with Cutaway. Called before the server starts; it compiles, and
/// does nothing, in a Release build without the server.
enum DemoExtensions {
    /// Registered as "brandBlue"; the chart's bars and the page's swatch have it.
    static let brandBlue = UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)

    @MainActor
    static func register() {
        CutawayServer.registerColor(brandBlue, named: "brandBlue")
        CutawayServer.describe(SalesChartView.self, SalesChartView.description)
        CutawayServer.describe(CardNumberView.self, CutawayServer.Description(isExcludedFromCapture: true))
    }
}

/// A bar chart that draws its bars itself, bottom up. Cutaway shows each bar as a virtual node,
/// and each segment of a bar inside it.
final class SalesChartView: UIView {
    struct Bar {
        struct Segment {
            var id: String
            /// Its part of the bar, from the bottom.
            var share: Double
        }

        var id: String
        var label: String
        var value: Double
        var segments: [Segment] = []
    }

    /// The bar would not fit in the chart.
    struct TooTall: LocalizedError {
        let height: Double

        var errorDescription: String? { "a bar can be at most \(Int(height)) points tall" }
    }

    static let barWidth = 60.0

    var bars = [
        Bar(
            id: "north",
            label: "North",
            value: 120,
            segments: [Bar.Segment(id: "online", share: 0.25), Bar.Segment(id: "retail", share: 0.75)]
        ),
        Bar(id: "south", label: "South", value: 80),
        Bar(id: "east", label: "East", value: 160, segments: [Bar.Segment(id: "export", share: 1)])
    ] {
        didSet { setNeedsDisplay() }
    }

    var barColor = DemoExtensions.brandBlue {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.95, alpha: 1)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Bar `index`, in the chart's coordinates: 30 points apart, standing on the bottom edge.
    func frameOfBar(at index: Int) -> CGRect {
        let value = bars[index].value
        return CGRect(x: 30 + Double(index) * 90, y: bounds.height - value, width: Self.barWidth, height: value)
    }

    /// Segment `index` of a bar, in the bar's coordinates, stacked from the bottom.
    static func frameOfSegment(at index: Int, of bar: Bar) -> CGRect {
        let below = bar.segments[..<index].reduce(0) { $0 + $1.share } * bar.value
        let height = bar.segments[index].share * bar.value
        return CGRect(x: 0, y: bar.value - below - height, width: barWidth, height: height)
    }

    override func draw(_ rect: CGRect) {
        barColor.setFill()
        for index in bars.indices {
            UIRectFill(frameOfBar(at: index))
        }
        // A white line between segments.
        UIColor.white.setFill()
        for (index, bar) in bars.enumerated() {
            let origin = frameOfBar(at: index).origin
            for segment in bar.segments.indices.dropFirst() {
                let frame = Self.frameOfSegment(at: segment, of: bar)
                UIRectFill(CGRect(x: origin.x, y: origin.y + frame.maxY - 1, width: Self.barWidth, height: 2))
            }
        }
    }

    /// The chart's own attributes, and a virtual node for each bar: "East" is collapsed by
    /// default.
    static let description = CutawayServer.Description<SalesChartView>(
        attributes: { chart in
            [
                CutawayServer.AttributeGroup("chart", [
                    .int("barCount", chart.bars.count, section: .content),
                    .color("barColor", chart.barColor, section: .appearance, set: { color in
                        chart.barColor = color ?? DemoExtensions.brandBlue
                    })
                ])
            ]
        },
        virtualChildren: { chart in
            chart.bars.indices.map { node(forBar: $0, of: chart) }
        }
    )

    private static func node(forBar index: Int, of chart: SalesChartView) -> CutawayServer.VirtualNode {
        let bar = chart.bars[index]
        return CutawayServer.VirtualNode(
            id: bar.id,
            type: Bar.self,
            name: bar.label,
            frame: chart.frameOfBar(at: index),
            isCollapsedByDefault: bar.id == "east",
            attributes: [
                CutawayServer.AttributeGroup("bar", [
                    .string("label", bar.label, section: .identity),
                    .double(
                        "value",
                        bar.value,
                        section: .content,
                        unit: .points,
                        limits: [.atLeast(0)],
                        set: { value in
                            guard let value, value <= chart.bounds.height else {
                                throw TooTall(height: chart.bounds.height)
                            }
                            chart.bars[index].value = value
                        }
                    )
                ])
            ],
            children: bar.segments.indices.map { segment in
                CutawayServer.VirtualNode(
                    id: bar.segments[segment].id,
                    type: Bar.Segment.self,
                    name: bar.segments[segment].id.capitalized,
                    frame: frameOfSegment(at: segment, of: bar),
                    attributes: [
                        CutawayServer.AttributeGroup("segment", [
                            .double("share", bar.segments[segment].share, section: .content, unit: .fraction)
                        ])
                    ]
                )
            }
        )
    }
}

/// Shows a card number: Cutaway leaves it out of every image.
final class CardNumberView: UIView {
    private let number = UILabel(frame: CGRect(x: 12, y: 18, width: 276, height: 24))

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.2, alpha: 1)
        number.text = "4242 4242 4242 4242"
        number.textColor = .white
        number.font = .monospacedDigitSystemFont(ofSize: 17, weight: .regular)
        addSubview(number)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }
}
