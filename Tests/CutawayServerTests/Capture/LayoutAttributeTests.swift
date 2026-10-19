import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Counts its layout passes and constraint updates.
private final class SpyLayoutView: UIView {
    var layouts = 0
    var constraintUpdates = 0

    override func layoutSubviews() {
        layouts += 1
        super.layoutSubviews()
    }

    override func updateConstraints() {
        constraintUpdates += 1
        super.updateConstraints()
    }
}

/// Counts its layout passes and constraint updates.
private final class SpyLayoutLabel: UILabel {
    var layouts = 0
    var constraintUpdates = 0

    override func layoutSubviews() {
        layouts += 1
        super.layoutSubviews()
    }

    override func updateConstraints() {
        constraintUpdates += 1
        super.updateConstraints()
    }
}

/// A view with an intrinsic height and no intrinsic width.
private final class TallView: UIView {
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 30) }
}

/// The layout attributes of protocol 0.4 (S-ATTR-07). No
/// server, no connection.
final class LayoutAttributeTests: CaptureTestCase {
    private static let ids = [
        "view.contentHuggingPriority.horizontal",
        "view.contentHuggingPriority.vertical",
        "view.contentCompressionResistancePriority.horizontal",
        "view.contentCompressionResistancePriority.vertical",
        "view.intrinsicContentSize.width",
        "view.intrinsicContentSize.height",
        "view.translatesAutoresizingMaskIntoConstraints",
        "view.hasAmbiguousLayout"
    ]

    /// The layer's attributes by ID.
    private func attributes(of layer: CALayer) -> [String: Attribute] {
        Dictionary(uniqueKeysWithValues: AttributeCatalog.standard.read(layer).flatMap(\.attributes)
            .map { ($0.id, $0) })
    }

    private func value(_ id: String, of view: UIView) throws -> AttributeValue? {
        try XCTUnwrap(attributes(of: view.layer)[id], "\(id) is missing").value
    }

    /// Writes through `AttributeEditing.apply`.
    private func apply(
        _ id: String,
        _ value: AttributeValue?,
        on view: UIView,
        in window: UIWindow
    ) -> Result<SetAttributeResult, WireError> {
        let registry = LayerRegistry()
        return AttributeEditing.apply(
            SetAttribute(layerID: registry.register(view.layer), attributeID: id, value: value),
            windows: [window],
            registry: registry,
            appState: .active
        )
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 17)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// They end what the view group had before the accessibility of protocol 1.2.
    func test_S_ATTR_07_theViewGroupEndsWithTheLayoutAttributes() throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        window.addSubview(view)
        var group = try XCTUnwrap(AttributeCatalog.standard.read(view.layer).first { $0.id == "view" })
        group.attributes = Array(group.attributes.prefix { $0.section != .accessibility })
        XCTAssertEqual(group.attributes.suffix(8).map(\.id), Self.ids)
        XCTAssertEqual(group.attributes[group.attributes.count - 9].id, "view.layoutMargins")
        XCTAssertEqual(
            group.attributes.suffix(8).map(\.title),
            [
                "Hugging (Horizontal)",
                "Hugging (Vertical)",
                "Compression Resistance (Horizontal)",
                "Compression Resistance (Vertical)",
                "Intrinsic Width",
                "Intrinsic Height",
                "Autoresizing Mask to Constraints",
                "Ambiguous Layout"
            ]
        )
        // P-ATTR-06, also for the nil intrinsic sizes of a plain view.
        XCTAssertEqual(
            group.attributes.suffix(8).map(\.valueKind),
            [.double, .double, .double, .double, .double, .double, .bool, .bool]
        )
        XCTAssertEqual(group.attributes.suffix(8).map(\.editable), [true, true, true, true, false, false, true, false])
        XCTAssertTrue(group.attributes.suffix(8).allSatisfy { !$0.acceptsNil })
    }

    func test_S_ATTR_07_titlesSplitAtDots() {
        XCTAssertEqual(
            AttributeCatalog.title(for: "contentHuggingPriority.horizontal"),
            "Content Hugging Priority Horizontal"
        )
        XCTAssertEqual(AttributeCatalog.title(for: "a.b.cD"), "A B C D")
        XCTAssertEqual(AttributeCatalog.title(for: "layoutMargins"), "Layout Margins")
    }

    func test_S_ATTR_07_layoutAttributesMatchUIKit() throws {
        let window = try makeWindow()
        let text = label("Intrinsic")
        text.setContentHuggingPriority(UILayoutPriority(251), for: .horizontal)
        text.setContentCompressionResistancePriority(UILayoutPriority(999.5), for: .vertical)
        window.addSubview(text)
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 10),
            text.topAnchor.constraint(equalTo: window.topAnchor, constant: 10)
        ])
        let plain = UIView(frame: CGRect(x: 0, y: 50, width: 20, height: 20))
        window.addSubview(plain)
        let tall = TallView()
        tall.translatesAutoresizingMaskIntoConstraints = false
        window.addSubview(tall)
        // Only a size: where it goes is not determined.
        NSLayoutConstraint.activate([tall.widthAnchor.constraint(equalToConstant: 40)])
        window.layoutIfNeeded()

        for view in [text, plain, tall] as [UIView] {
            let name = "\(type(of: view))"
            for (id, axis) in [
                ("view.contentHuggingPriority.horizontal", NSLayoutConstraint.Axis.horizontal),
                ("view.contentHuggingPriority.vertical", .vertical)
            ] {
                XCTAssertEqual(
                    try value(id, of: view),
                    .double(Double(view.contentHuggingPriority(for: axis).rawValue)),
                    name
                )
            }
            for (id, axis) in [
                ("view.contentCompressionResistancePriority.horizontal", NSLayoutConstraint.Axis.horizontal),
                ("view.contentCompressionResistancePriority.vertical", .vertical)
            ] {
                XCTAssertEqual(
                    try value(id, of: view),
                    .double(Double(view.contentCompressionResistancePriority(for: axis).rawValue)),
                    name
                )
            }
            XCTAssertEqual(
                try value("view.translatesAutoresizingMaskIntoConstraints", of: view),
                .bool(view.translatesAutoresizingMaskIntoConstraints),
                name
            )
            XCTAssertEqual(try value("view.hasAmbiguousLayout", of: view), .bool(view.hasAmbiguousLayout), name)
        }
        XCTAssertEqual(try value("view.contentHuggingPriority.horizontal", of: text), .double(251))
        XCTAssertEqual(try value("view.contentCompressionResistancePriority.vertical", of: text), .double(999.5))

        // The label's intrinsic size is its text's.
        let size = text.intrinsicContentSize
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertEqual(try value("view.intrinsicContentSize.width", of: text), .double(size.width))
        XCTAssertEqual(try value("view.intrinsicContentSize.height", of: text), .double(size.height))
        // No intrinsic size: nil, of the kind double.
        XCTAssertNil(try value("view.intrinsicContentSize.width", of: plain))
        XCTAssertNil(try value("view.intrinsicContentSize.height", of: plain))
        XCTAssertEqual(attributes(of: plain.layer)["view.intrinsicContentSize.width"]?.valueKind, .double)
        // One dimension only.
        XCTAssertNil(try value("view.intrinsicContentSize.width", of: tall))
        XCTAssertEqual(try value("view.intrinsicContentSize.height", of: tall), .double(30))

        XCTAssertEqual(try value("view.translatesAutoresizingMaskIntoConstraints", of: text), .bool(false))
        XCTAssertEqual(try value("view.translatesAutoresizingMaskIntoConstraints", of: plain), .bool(true))
        XCTAssertEqual(try value("view.hasAmbiguousLayout", of: text), .bool(false))
        XCTAssertEqual(try value("view.hasAmbiguousLayout", of: tall), .bool(true))
    }

    // MARK: - Writing

    /// Two labels in a row that is too narrow for both: the one with the higher compression
    /// resistance keeps its width.
    private func row() throws -> (window: UIWindow, first: UILabel, second: UILabel) {
        let window = try makeWindow()
        let first = label("A first label that is long")
        let second = label("A second label that is long")
        window.addSubview(first)
        window.addSubview(second)
        NSLayoutConstraint.activate([
            first.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 10),
            first.topAnchor.constraint(equalTo: window.topAnchor, constant: 10),
            second.leadingAnchor.constraint(equalTo: first.trailingAnchor),
            second.topAnchor.constraint(equalTo: first.topAnchor),
            second.trailingAnchor.constraint(equalTo: window.leadingAnchor, constant: 210)
        ])
        first.setContentCompressionResistancePriority(UILayoutPriority(751), for: .horizontal)
        second.setContentCompressionResistancePriority(UILayoutPriority(750), for: .horizontal)
        window.layoutIfNeeded()
        return (window, first, second)
    }

    func test_S_ATTR_07_prioritiesCanBeWritten() throws {
        let (window, first, second) = try row()
        XCTAssertEqual(first.frame.width, first.intrinsicContentSize.width, accuracy: 0.5)
        XCTAssertLessThan(second.frame.width, second.intrinsicContentSize.width - 1)

        // P-SET-05: laid out before the answer, in the same turn of the main thread.
        let answer = try apply(
            "view.contentCompressionResistancePriority.horizontal",
            .double(800),
            on: second,
            in: window
        ).get()
        XCTAssertEqual(second.contentCompressionResistancePriority(for: .horizontal).rawValue, 800)
        XCTAssertEqual(second.frame.width, second.intrinsicContentSize.width, accuracy: 0.5)
        XCTAssertLessThan(first.frame.width, first.intrinsicContentSize.width - 1)
        let written = answer.attributeGroups.flatMap(\.attributes).first {
            $0.id == "view.contentCompressionResistancePriority.horizontal"
        }
        XCTAssertEqual(written?.value, .double(800))

        // The other three reach UIKit too.
        _ = try apply("view.contentCompressionResistancePriority.vertical", .double(1), on: first, in: window).get()
        XCTAssertEqual(first.contentCompressionResistancePriority(for: .vertical).rawValue, 1)
        _ = try apply("view.contentHuggingPriority.horizontal", .double(1000), on: first, in: window).get()
        XCTAssertEqual(first.contentHuggingPriority(for: .horizontal).rawValue, 1000)
        _ = try apply("view.contentHuggingPriority.vertical", .double(999.5), on: first, in: window).get()
        XCTAssertEqual(first.contentHuggingPriority(for: .vertical).rawValue, 999.5)
        _ = try apply("view.translatesAutoresizingMaskIntoConstraints", .bool(true), on: first, in: window).get()
        XCTAssertTrue(first.translatesAutoresizingMaskIntoConstraints)
    }

    func test_S_ATTR_07_prioritiesOutOfRangeAreRefused() throws {
        let (window, first, _) = try row()
        for id in Self.ids.prefix(4) {
            let before = attributes(of: first.layer)
            for number in [0, 0.5, 1000.5, 1001, -1, .nan, .infinity, -.infinity] as [Double] {
                switch apply(id, .double(number), on: first, in: window) {
                case .success: XCTFail("\(id) took \(number)")
                case .failure(let error): XCTAssertEqual(error.code, .invalidAttributeValue, "\(id) \(number)")
                }
                XCTAssertEqual(attributes(of: first.layer), before, "\(id) \(number) changed the label")
            }
        }
        // The two ends of the range are allowed.
        _ = try apply(Self.ids[0], .double(1), on: first, in: window).get()
        XCTAssertEqual(first.contentHuggingPriority(for: .horizontal).rawValue, 1)
        _ = try apply(Self.ids[0], .double(1000), on: first, in: window).get()
        XCTAssertEqual(first.contentHuggingPriority(for: .horizontal).rawValue, 1000)
    }

    func test_S_ATTR_07_derivedLayoutAttributesAreReadOnly() throws {
        let (window, first, _) = try row()
        for id in ["view.intrinsicContentSize.width", "view.intrinsicContentSize.height"] {
            XCTAssertEqual(
                apply(id, .double(5), on: first, in: window).failure?.code,
                .attributeNotEditable,
                id
            )
        }
        XCTAssertEqual(
            apply("view.hasAmbiguousLayout", .bool(true), on: first, in: window).failure?.code,
            .attributeNotEditable
        )
    }

    // MARK: - Reading does not lay out

    func test_S_ATTR_07_readingDoesNotLayOut() throws {
        let window = try makeWindow()
        let container = SpyLayoutView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        window.addSubview(container)
        let text = SpyLayoutLabel()
        text.text = "Intrinsic"
        text.translatesAutoresizingMaskIntoConstraints = false
        let sized = SpyLayoutView()
        sized.translatesAutoresizingMaskIntoConstraints = false
        let ambiguous = SpyLayoutView()
        ambiguous.translatesAutoresizingMaskIntoConstraints = false
        let autoresizing = SpyLayoutView(frame: CGRect(x: 10, y: 200, width: 50, height: 20))
        for view in [text, sized, ambiguous, autoresizing] as [UIView] { container.addSubview(view) }
        NSLayoutConstraint.activate([
            text.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            text.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            sized.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            sized.topAnchor.constraint(equalTo: text.bottomAnchor, constant: 10),
            sized.widthAnchor.constraint(equalToConstant: 80),
            sized.heightAnchor.constraint(equalToConstant: 40),
            ambiguous.widthAnchor.constraint(equalToConstant: 30),
            ambiguous.heightAnchor.constraint(equalToConstant: 30)
        ])
        window.layoutIfNeeded()
        XCTAssertTrue(ambiguous.hasAmbiguousLayout, "the test needs a view whose layout is ambiguous")

        let views: [UIView] = [container, text, sized, ambiguous, autoresizing]
        func counts() -> [Int] {
            views.flatMap { view -> [Int] in
                if let spy = view as? SpyLayoutView { return [spy.layouts, spy.constraintUpdates] }
                let spy = view as! SpyLayoutLabel
                return [spy.layouts, spy.constraintUpdates]
            }
        }

        // (a) Nothing pending.
        var before = counts()
        var needsLayout = views.map { $0.layer.needsLayout() }
        for view in views { _ = AttributeCatalog.standard.read(view.layer) }
        XCTAssertEqual(counts(), before, "reading laid out or updated constraints")
        XCTAssertEqual(views.map { $0.layer.needsLayout() }, needsLayout)

        // (b) A layout pass and a constraint update pending on every view.
        for view in views {
            view.setNeedsLayout()
            view.setNeedsUpdateConstraints()
        }
        before = counts()
        needsLayout = views.map { $0.layer.needsLayout() }
        XCTAssertEqual(needsLayout, views.map { _ in true })
        for view in views { _ = AttributeCatalog.standard.read(view.layer) }
        XCTAssertEqual(counts(), before, "reading laid out or updated constraints")
        XCTAssertEqual(views.map { $0.layer.needsLayout() }, needsLayout, "a pending layout was carried out")
        XCTAssertEqual(
            views.map { $0.needsUpdateConstraints() },
            views.map { _ in true },
            "a pending constraint update was carried out"
        )
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
