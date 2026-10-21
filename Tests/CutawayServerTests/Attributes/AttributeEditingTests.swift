import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Changing attributes (PROTOCOL.md, P-SET-01 to P-SET-06). No server, no
/// connection: the tests call `AttributeEditing.apply` on the main thread, or, for the app's
/// state, the host as a session does.
final class AttributeEditingTests: CaptureTestCase {
    /// One instance of every kind of layer the attribute list tells apart, in a window of the
    /// test's own.
    private struct Specimens {
        let window: UIWindow
        let layer: CALayer
        let view: UIView
        let label: UILabel
        let imageView: UIImageView
        let control: UIControl
        let button: UIButton
        let scrollView: UIScrollView
        let stackView: UIStackView
        let textField: UITextField
        let textView: UITextView

        /// The layer the attribute `id` is written on: the bare layer for the `layer` group, the
        /// view of the attribute's group for the others.
        func target(of id: String) -> CALayer {
            switch String(id.prefix { $0 != "." }) {
            case "layer": return layer
            case "view": return view.layer
            case "label": return label.layer
            case "imageView": return imageView.layer
            case "control": return control.layer
            case "button": return button.layer
            case "scrollView": return scrollView.layer
            case "stackView": return stackView.layer
            case "textField": return textField.layer
            case "textView": return textView.layer
            default: preconditionFailure("no specimen for \(id)")
            }
        }
    }

    private func makeSpecimens() throws -> Specimens {
        let window = try makeWindow()
        window.backgroundColor = .white
        let layer = CALayer()
        layer.frame = CGRect(x: 10, y: 10, width: 100, height: 50)
        window.layer.addSublayer(layer)
        let view = UIView(frame: CGRect(x: 10, y: 70, width: 100, height: 50))
        let label = UILabel(frame: CGRect(x: 10, y: 130, width: 200, height: 30))
        label.text = "Label"
        let imageView = UIImageView(frame: CGRect(x: 10, y: 170, width: 40, height: 40))
        let control = UIControl(frame: CGRect(x: 60, y: 170, width: 40, height: 40))
        let button = UIButton(type: .custom)
        button.frame = CGRect(x: 110, y: 170, width: 100, height: 40)
        button.setTitle("Title", for: .normal)
        let scrollView = UIScrollView(frame: CGRect(x: 10, y: 220, width: 200, height: 100))
        scrollView.contentSize = CGSize(width: 200, height: 400)
        let stackView = UIStackView(frame: CGRect(x: 10, y: 330, width: 200, height: 40))
        let textField = UITextField(frame: CGRect(x: 10, y: 380, width: 200, height: 30))
        textField.text = "Field"
        let textView = UITextView(frame: CGRect(x: 10, y: 420, width: 300, height: 50))
        textView.text = "Text"
        textView.font = UIFont.systemFont(ofSize: 14)
        for subview in [view, label, imageView, control, button, scrollView, stackView, textField, textView] {
            window.addSubview(subview)
        }
        window.layoutIfNeeded()
        return Specimens(
            window: window,
            layer: layer,
            view: view,
            label: label,
            imageView: imageView,
            control: control,
            button: button,
            scrollView: scrollView,
            stackView: stackView,
            textField: textField,
            textView: textView
        )
    }

    /// Writes through `AttributeEditing.apply`, with the layer's ID from `registry`.
    private func apply(
        _ id: String,
        _ value: AttributeValue?,
        on layer: CALayer,
        in window: UIWindow,
        registry: LayerRegistry = LayerRegistry()
    ) -> Result<SetAttributeResult, WireError> {
        AttributeEditing.apply(
            SetAttribute(layerID: registry.register(layer), attributeID: id, value: value),
            in: .testing(windows: [window], registry: registry)
        )
    }

    /// The layer's attributes by ID.
    private func attributes(of layer: CALayer) -> [String: Attribute] {
        Dictionary(uniqueKeysWithValues: AttributeCatalog.standard.read(layer).flatMap(\.attributes)
            .map { ($0.id, $0) })
    }

    /// An enumeration as a client may send it: only the value (P-SET-02).
    private func enumeration(_ raw: Int64) -> AttributeValue {
        .enumeration(value: raw, cases: [], caseName: "", caseValues: [])
    }

    private func color(_ red: Float, _ green: Float, _ blue: Float, _ alpha: Float = 1) -> AttributeValue {
        .color(WireColor(red: red, green: green, blue: blue, alpha: alpha))
    }

    /// Whether a value read back is the one written: colours went through a colour space,
    /// `Float` properties lose digits, enumerations come back with their cases.
    private func matches(_ actual: AttributeValue?, _ written: AttributeValue?) -> Bool {
        switch (actual, written) {
        case let (.color(actualColor, _, _, _, _), .color(writtenColor, _, _, _, _)):
            return zip(
                [actualColor.red, actualColor.green, actualColor.blue, actualColor.alpha],
                [writtenColor.red, writtenColor.green, writtenColor.blue, writtenColor.alpha]
            )
            .allSatisfy { abs($0 - $1) <= 1 / 255 }
        case let (.double(actualDouble), .double(writtenDouble)):
            return abs(actualDouble - writtenDouble) <= 1e-6 * max(1, abs(writtenDouble))
        case let (.enumeration(actualValue, _, _, _), .enumeration(writtenValue, _, _, _)):
            return actualValue == writtenValue
        default:
            return actual == written
        }
    }

    // MARK: - S-SET-01

    /// One value for every attribute of the list that can be changed, different from the
    /// specimen's, and what else may change with it.
    private static let writes: [(id: String, value: AttributeValue, alsoChanges: Set<String>)] = {
        func color(_ red: Float, _ green: Float, _ blue: Float) -> AttributeValue {
            .color(WireColor(red: red, green: green, blue: blue, alpha: 1))
        }
        func enumeration(_ raw: Int64) -> AttributeValue {
            .enumeration(value: raw, cases: [], caseName: "", caseValues: [])
        }
        var scaled = WireTransform.identity
        scaled.m11 = 2
        scaled.m22 = 0.5
        let frame: Set<String> = ["layer.frame"]
        // A text view's content size follows the layout of its text.
        let contentSize: Set<String> = ["scrollView.contentSize"]
        // A view's intrinsic size follows its content: text, title and font.
        let intrinsic: Set<String> = ["view.intrinsicContentSize.width", "view.intrinsicContentSize.height"]
        return [
            ("layer.bounds", .rect(WireRect(x: 0, y: 0, width: 80, height: 40)), frame),
            ("layer.position", .point(WirePoint(x: 70, y: 60)), frame),
            ("layer.anchorPoint", .point(WirePoint(x: 0.25, y: 0.75)), frame),
            ("layer.zPosition", .double(3), []),
            ("layer.transform", .transform(scaled), frame),
            ("layer.hidden", .bool(true), []),
            ("layer.opacity", .double(0.25), []),
            ("layer.masksToBounds", .bool(true), []),
            ("layer.cornerRadius", .double(6), []),
            ("layer.backgroundColor", color(0.2, 0.4, 0.6), []),
            // P-ATTR-13: the border now shows its color.
            ("layer.borderWidth", .double(2), ["layer.borderColor"]),
            ("layer.borderColor", color(1, 0, 0), []),
            ("layer.shadowColor", color(0, 0, 1), []),
            ("layer.shadowOpacity", .double(0.5), ["layer.shadowColor", "layer.shadowRadius", "layer.shadowOffset"]),
            ("layer.shadowRadius", .double(9), []),
            ("layer.shadowOffset", .size(WireSize(width: 4, height: 5)), []),
            // The layer's side of each pair is not among a view's attributes (P-ATTR-11).
            ("view.alpha", .double(0.5), []),
            ("view.isHidden", .bool(true), []),
            ("view.isOpaque", .bool(false), []),
            ("view.clipsToBounds", .bool(true), []),
            ("view.isUserInteractionEnabled", .bool(false), []),
            ("view.tag", .int(42), []),
            ("view.contentMode", enumeration(4), []),
            ("view.backgroundColor", color(1, 0.5, 0), []),
            ("view.tintColor", color(0, 1, 0), []),
            ("view.layoutMargins", .insets(WireInsets(top: 1, left: 2, bottom: 3, right: 4)), []),
            ("view.contentHuggingPriority.horizontal", .double(300), []),
            ("view.contentHuggingPriority.vertical", .double(260), []),
            ("view.contentCompressionResistancePriority.horizontal", .double(700), []),
            ("view.contentCompressionResistancePriority.vertical", .double(999.5), []),
            ("view.translatesAutoresizingMaskIntoConstraints", .bool(false), []),
            // v1.2 (S-SET-07).
            ("view.accessibilityLabel", .string("Save"), []),
            ("view.accessibilityHint", .string("Saves the page"), []),
            ("view.accessibilityValue", .string("3"), []),
            ("view.accessibilityIdentifier", .string("save"), []),
            ("view.isAccessibilityElement", .bool(true), []),
            ("label.adjustsFontForContentSizeCategory", .bool(true), []),
            ("textField.adjustsFontForContentSizeCategory", .bool(true), []),
            ("textView.adjustsFontForContentSizeCategory", .bool(true), []),
            ("label.text", .string("Changed"), intrinsic),
            ("label.fontName", .string("Courier"), intrinsic.union(["label.fontDescription"])),
            ("label.fontSize", .double(21), intrinsic.union(["label.fontDescription"])),
            ("label.textColor", color(0.5, 0, 0.5), []),
            ("label.textAlignment", enumeration(2), []),
            ("label.numberOfLines", .int(3), []),
            ("label.lineBreakMode", enumeration(2), []),
            ("imageView.isHighlighted", .bool(true), []),
            ("control.isEnabled", .bool(false), []),
            ("control.isSelected", .bool(true), []),
            ("control.isHighlighted", .bool(true), []),
            ("button.currentTitle", .string("Other"), intrinsic),
            ("button.currentTitleColor", color(0, 0.5, 0), []),
            ("scrollView.contentOffset", .point(WirePoint(x: 0, y: 50)), ["layer.bounds"]),
            ("scrollView.contentSize", .size(WireSize(width: 300, height: 600)), []),
            (
                "scrollView.contentInset",
                .insets(WireInsets(top: 5, left: 0, bottom: 5, right: 0)),
                ["scrollView.adjustedContentInset"]
            ),
            ("scrollView.isScrollEnabled", .bool(false), []),
            ("scrollView.isPagingEnabled", .bool(true), []),
            ("stackView.axis", enumeration(1), ["stackView.alignment"]),
            ("stackView.alignment", enumeration(3), []),
            ("stackView.distribution", enumeration(1), []),
            ("stackView.spacing", .double(12), []),
            ("textField.text", .string("Typed"), intrinsic),
            ("textField.placeholder", .string("Hint"), []),
            ("textField.fontName", .string("Courier"), intrinsic.union(["textField.fontDescription"])),
            ("textField.fontSize", .double(22), intrinsic.union(["textField.fontDescription"])),
            ("textField.textColor", color(0, 0, 1), []),
            ("textView.text", .string("Changed text"), contentSize),
            ("textView.fontName", .string("Courier"), contentSize.union(["textView.fontDescription"])),
            ("textView.fontSize", .double(19), contentSize.union(["textView.fontDescription"])),
            ("textView.textColor", color(1, 0, 0), []),
            ("textView.isEditable", .bool(false), [])
        ]
    }()

    func test_S_SET_01_everyEditableAttributeIsWritten() throws {
        // The table has every attribute the list lets a client change, and no other.
        let editable = ExpectedAttributes.groups.values.flatMap(\.attributes).filter(\.editable).map(\.id)
        XCTAssertEqual(Set(Self.writes.map(\.id)), Set(editable))
        XCTAssertEqual(Self.writes.count, 71)

        for (id, value, alsoChanges) in Self.writes {
            let specimens = try makeSpecimens()
            let layer = specimens.target(of: id)
            let before = attributes(of: layer)
            XCTAssertFalse(matches(before[id]?.value, value), "\(id): the new value is the old one")

            let answer = try XCTUnwrap(try? apply(id, value, on: layer, in: specimens.window).get(), id)
            let after = attributes(of: layer)
            // P-SET-01: the whole layer, as it reads after the change.
            XCTAssertEqual(answer.attributeGroups, AttributeCatalog.standard.read(layer), id)
            XCTAssertTrue(matches(after[id]?.value, value), "\(id) reads \(String(describing: after[id]?.value))")
            for (other, attribute) in after where other != id && !alsoChanges.contains(other) {
                XCTAssertEqual(attribute, before[other], "\(id) changed \(other)")
            }
        }
    }

    func test_S_SET_01_valuesReachUIKit() throws {
        // A few, read straight from UIKit rather than through the catalog.
        let specimens = try makeSpecimens()
        let window = specimens.window
        _ = try apply("layer.cornerRadius", .double(6), on: specimens.layer, in: window).get()
        XCTAssertEqual(specimens.layer.cornerRadius, 6)
        _ = try apply("view.tag", .int(42), on: specimens.view.layer, in: window).get()
        XCTAssertEqual(specimens.view.tag, 42)
        _ = try apply("label.text", .string("Changed"), on: specimens.label.layer, in: window).get()
        XCTAssertEqual(specimens.label.text, "Changed")
        _ = try apply("label.textAlignment", enumeration(2), on: specimens.label.layer, in: window).get()
        XCTAssertEqual(specimens.label.textAlignment, .right)
        _ = try apply("button.currentTitle", .string("Other"), on: specimens.button.layer, in: window).get()
        XCTAssertEqual(specimens.button.title(for: .normal), "Other")
        _ = try apply(
            "scrollView.contentOffset",
            .point(WirePoint(x: 0, y: 50)),
            on: specimens.scrollView.layer,
            in: window
        ).get()
        XCTAssertEqual(specimens.scrollView.contentOffset, CGPoint(x: 0, y: 50))
        _ = try apply("textField.fontName", .string("Courier"), on: specimens.textField.layer, in: window).get()
        XCTAssertEqual(specimens.textField.font?.fontName, "Courier")
    }

    func test_S_SET_01_nilIsWrittenWhereAccepted() throws {
        // What UIKit itself gives after nil is set in code, on a twin of the specimen.
        let setNil: [(String, (Specimens) -> Void)] = [
            ("layer.backgroundColor", { $0.layer.backgroundColor = nil }),
            ("layer.borderColor", { $0.layer.borderColor = nil }),
            ("layer.shadowColor", { $0.layer.shadowColor = nil }),
            ("view.backgroundColor", { $0.view.backgroundColor = nil }),
            ("view.tintColor", { $0.view.tintColor = nil }),
            ("view.accessibilityLabel", { $0.view.accessibilityLabel = nil }),
            ("view.accessibilityHint", { $0.view.accessibilityHint = nil }),
            ("view.accessibilityValue", { $0.view.accessibilityValue = nil }),
            ("view.accessibilityIdentifier", { $0.view.accessibilityIdentifier = nil }),
            ("label.text", { $0.label.text = nil }),
            ("label.textColor", { $0.label.textColor = nil }),
            ("button.currentTitle", { $0.button.setTitle(nil, for: $0.button.state) }),
            ("button.currentTitleColor", { $0.button.setTitleColor(nil, for: $0.button.state) }),
            ("textField.text", { $0.textField.text = nil }),
            ("textField.placeholder", { $0.textField.placeholder = nil }),
            ("textField.textColor", { $0.textField.textColor = nil }),
            ("textView.textColor", { $0.textView.textColor = nil })
        ]
        let acceptsNil = ExpectedAttributes.groups.values.flatMap(\.attributes).filter(\.acceptsNil).map(\.id)
        XCTAssertEqual(Set(setNil.map(\.0)), Set(acceptsNil))

        for (id, clear) in setNil {
            let specimens = try makeSpecimens()
            // Give each a value first, so that nil is a change.
            let first: AttributeValue? = id.hasSuffix("Color")
                ? color(0.3, 0.6, 0.9)
                : id.hasPrefix("view.accessibility") ? .string("Before") : nil
            if let first {
                _ = try apply(id, first, on: specimens.target(of: id), in: specimens.window).get()
            }
            let twin = try makeSpecimens()
            if let first {
                _ = try apply(id, first, on: twin.target(of: id), in: twin.window).get()
            }
            clear(twin)
            twin.window.layoutIfNeeded()

            let answer = try XCTUnwrap(
                try? apply(id, nil, on: specimens.target(of: id), in: specimens.window).get(),
                id
            )
            XCTAssertEqual(
                attributes(of: specimens.target(of: id))[id],
                attributes(of: twin.target(of: id))[id],
                id
            )
            XCTAssertEqual(answer.attributeGroups, AttributeCatalog.standard.read(specimens.target(of: id)), id)
        }
    }

    func test_S_SET_01_enumerationsTakeOnlyTheirValue() throws {
        let specimens = try makeSpecimens()
        // With or without the cases: only the value counts (P-SET-02).
        let full = AttributeOutputs.enumeration(1, names: AttributeOutputs.textAlignmentNames)
        _ = try apply("label.textAlignment", full, on: specimens.label.layer, in: specimens.window).get()
        XCTAssertEqual(specimens.label.textAlignment, .center)
        let wrongNames = AttributeValue.enumeration(value: 2, cases: ["x"], caseName: "x", caseValues: [7])
        _ = try apply("label.textAlignment", wrongNames, on: specimens.label.layer, in: specimens.window).get()
        XCTAssertEqual(specimens.label.textAlignment, .right)
    }

    func test_S_SET_01_fontNamesAreTakenExactly() throws {
        let specimens = try makeSpecimens()
        let window = specimens.window
        let label = specimens.label
        let system = label.font.fontName
        // The name of the font the label has keeps that font.
        _ = try apply("label.fontName", .string(system), on: label.layer, in: window).get()
        XCTAssertEqual(label.font.fontName, system)
        _ = try apply("label.fontName", .string("Courier"), on: label.layer, in: window).get()
        XCTAssertEqual(label.font.fontName, "Courier")
        // The system font's name brings it back, at the same size.
        _ = try apply("label.fontSize", .double(21), on: label.layer, in: window).get()
        _ = try apply("label.fontName", .string(system), on: label.layer, in: window).get()
        XCTAssertEqual(label.font.fontName, system)
        XCTAssertEqual(label.font.pointSize, 21)
        // Writing the size keeps the name, and the other way round.
        _ = try apply("label.fontName", .string("Courier"), on: label.layer, in: window).get()
        _ = try apply("label.fontSize", .double(30), on: label.layer, in: window).get()
        XCTAssertEqual(label.font.fontName, "Courier")
        XCTAssertEqual(label.font.pointSize, 30)
        // A text view without a font gets the system's size, or the system font. (A text field
        // reads a default font after nil is set: it never has none.)
        let textView = specimens.textView
        textView.font = nil
        XCTAssertNil(textView.font)
        _ = try apply("textView.fontSize", .double(25), on: textView.layer, in: window).get()
        XCTAssertEqual(textView.font?.fontName, UIFont.systemFont(ofSize: 25).fontName)
        XCTAssertEqual(textView.font?.pointSize, 25)
        textView.font = nil
        _ = try apply("textView.fontName", .string("Courier"), on: textView.layer, in: window).get()
        XCTAssertEqual(textView.font?.fontName, "Courier")
        XCTAssertEqual(textView.font?.pointSize, UIFont.systemFontSize)
    }

    func test_S_SET_01_extremeValuesDoNotCrash() throws {
        // Finite but extreme values within each attribute's rules: nothing raises.
        func extremes(_ value: AttributeValue, id: String) -> [AttributeValue] {
            let big = 1e300
            let refusesNegative: Set<String> = [
                "layer.bounds",
                "layer.cornerRadius",
                "layer.borderWidth",
                "layer.shadowRadius",
                "label.numberOfLines",
                "label.fontSize",
                "textField.fontSize",
                "textView.fontSize",
                "scrollView.contentSize"
            ]
            let signs: [Double] = refusesNegative.contains(id) ? [1] : [1, -1]
            // Priorities are refused outside 1...1000, fractions outside 0...1 (S-SET-06): the
            // extremes are the ends of the range.
            if id.contains("Priority") { return [.double(1), .double(1000)] }
            if ["layer.opacity", "layer.shadowOpacity", "view.alpha"].contains(id) { return [.double(0), .double(1)] }
            switch value {
            case .double: return signs.map { .double($0 * big) }
            case .int: return signs.map { .int($0 > 0 ? .max : .min) }
            // A font's name must be one of a font: a long one is refused, as it should be.
            case .string: return id.hasSuffix("fontName") ? [] : [.string(String(repeating: "x", count: 100_000))]
            case .point: return signs.map { .point(WirePoint(x: $0 * big, y: -$0 * big)) }
            case .size: return signs.map { .size(WireSize(width: $0 * big, height: $0 * big)) }
            case .rect: return signs.map { .rect(WireRect(x: -$0 * big, y: $0 * big, width: big, height: big)) }
            case .insets: return signs.map { .insets(WireInsets(
                    top: $0 * big,
                    left: -$0 * big,
                    bottom: big,
                    right: -big
                )) }
            case .transform:
                return signs.map { sign in
                    var transform = WireTransform.identity
                    transform.m11 = sign * big
                    transform.m34 = big
                    transform.m41 = -big
                    return .transform(transform)
                }
            case .color: return [color(100, -100, 1e30, 2)]
            case .bool, .enumeration, .layerReference: return []
            }
        }
        for (id, value, _) in Self.writes {
            for extreme in extremes(value, id: id) {
                let specimens = try makeSpecimens()
                let result = apply(id, extreme, on: specimens.target(of: id), in: specimens.window)
                XCTAssertNotNil(try? result.get(), "\(id) refused \(extreme)")
                _ = try render(specimens.window)
            }
        }
    }

    func test_S_SET_01_otherLayersDoNotChange() throws {
        let specimens = try makeSpecimens()
        let layers = [specimens.window.layer] + (specimens.window.layer.sublayers ?? [])
        func everything() -> [[String: Attribute]] {
            layers.filter { $0 !== specimens.label.layer }.map(attributes(of:))
        }
        let before = everything()
        _ = try apply("label.text", .string("Changed"), on: specimens.label.layer, in: specimens.window).get()
        _ = try apply("label.textColor", color(1, 0, 0), on: specimens.label.layer, in: specimens.window).get()
        XCTAssertEqual(everything(), before)
    }

    func test_S_SET_01_doesNotKeepLayersAlive() throws {
        let window = try makeWindow()
        let registry = LayerRegistry()
        weak var view: UIView?
        autoreleasepool {
            let label = UILabel()
            window.addSubview(label)
            view = label
            XCTAssertNotNil(try? apply("label.text", .string("x"), on: label.layer, in: window, registry: registry)
                .get())
            label.removeFromSuperview()
        }
        // Core Animation's open transaction holds on to removed layers until it is committed.
        CATransaction.flush()
        XCTAssertNil(view, "the change kept the view alive")
    }

    func test_S_SET_01_changesOutliveTheRequest() throws {
        // P-SET-06: the change stays; nothing is recorded to undo it.
        let specimens = try makeSpecimens()
        let registry = LayerRegistry()
        _ = try apply("view.tag", .int(7), on: specimens.view.layer, in: specimens.window, registry: registry).get()
        let count = registry.count
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(specimens.view.tag, 7)
        XCTAssertEqual(registry.count, count, "a change gives no layer a new ID")
    }

    // MARK: - S-SET-02

    /// Asserts the error and that neither the layer's attributes nor the window's pixels changed.
    private func assertRejected(
        _ id: String,
        _ value: AttributeValue?,
        on layer: CALayer,
        in specimens: Specimens,
        registry: LayerRegistry = LayerRegistry(),
        layerID: UInt64? = nil,
        code: ErrorCode,
        message: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let before = attributes(of: layer)
        let pixels = try render(specimens.window)
        let result = AttributeEditing.apply(
            SetAttribute(layerID: layerID ?? registry.register(layer), attributeID: id, value: value),
            in: .testing(windows: [specimens.window], registry: registry)
        )
        guard case .failure(let error) = result else {
            return XCTFail("\(id) = \(String(describing: value)) was accepted", file: file, line: line)
        }
        XCTAssertEqual(error.code, code, "\(id): \(error.message)", file: file, line: line)
        if let message { XCTAssertEqual(error.message, message, file: file, line: line) }
        XCTAssertEqual(attributes(of: layer), before, "\(id) changed the layer", file: file, line: line)
        XCTAssertEqual(try render(specimens.window), pixels, "\(id) changed the window", file: file, line: line)
    }

    func test_S_SET_02_rejectionsFollowTheProtocolOrder() throws {
        let specimens = try makeSpecimens()
        let layer = specimens.layer
        // The words of the `set-attribute-rejected` fixture.
        try assertRejected(
            "label.text",
            .string("Hi"),
            on: specimens.label.layer,
            in: specimens,
            layerID: 99,
            code: .layerNotFound,
            message: "no layer with id 99"
        )
        try assertRejected(
            "layer.frame",
            .rect(WireRect(x: 0, y: 0, width: 1, height: 1)),
            on: layer,
            in: specimens,
            code: .attributeNotEditable,
            message: "layer.frame is read-only"
        )
        try assertRejected(
            "layer.opacity",
            .string("half"),
            on: layer,
            in: specimens,
            code: .invalidAttributeValue,
            message: "layer.opacity takes a DoubleValue"
        )
        try assertRejected(
            "label.numberOfLines",
            nil,
            on: specimens.label.layer,
            in: specimens,
            code: .invalidAttributeValue,
            message: "label.numberOfLines cannot be nil"
        )
        // When more than one holds, the first in the order of P-SET-03.
        try assertRejected(
            "layer.opacity",
            .double(.nan),
            on: layer,
            in: specimens,
            layerID: 12_345,
            code: .layerNotFound
        )
        try assertRejected("layer.frame", .string("x"), on: layer, in: specimens, code: .attributeNotEditable)
        try assertRejected("label.text", nil, on: layer, in: specimens, code: .attributeNotEditable)
        try assertRejected(
            "layer.opacity",
            .string("x"),
            on: layer,
            in: specimens,
            code: .invalidAttributeValue,
            message: "layer.opacity takes a DoubleValue"
        )
    }

    func test_S_SET_02_rejectedRequestsChangeNothing() throws {
        let specimens = try makeSpecimens()
        let window = specimens.window
        let registry = LayerRegistry()

        // The layer does not exist: released, out of every window, never given out.
        var releasedID: UInt64 = 0
        autoreleasepool {
            let gone = CALayer()
            window.layer.addSublayer(gone)
            releasedID = registry.register(gone)
            gone.removeFromSuperlayer()
        }
        CATransaction.flush()
        let removed = UIView()
        window.addSubview(removed)
        let removedID = registry.register(removed.layer)
        removed.removeFromSuperview()
        for id in [releasedID, removedID, 12_345, 0] {
            try assertRejected(
                "view.tag",
                .int(1),
                on: specimens.view.layer,
                in: specimens,
                registry: registry,
                layerID: id,
                code: .layerNotFound,
                message: "no layer with id \(id)"
            )
        }

        // The attribute is not the layer's, or cannot be changed.
        let notEditable: [(String, CALayer, AttributeValue)] = [
            ("label.text", specimens.view.layer, .string("x")),
            ("layer.nothing", specimens.layer, .bool(true)),
            ("view.alpha", specimens.layer, .double(0.5)),
            ("layer.frame", specimens.layer, .rect(WireRect(x: 0, y: 0, width: 1, height: 1))),
            ("imageView.imageSize", specimens.imageView.layer, .size(WireSize(width: 1, height: 1))),
            (
                "scrollView.adjustedContentInset",
                specimens.scrollView.layer,
                .insets(WireInsets(top: 1, left: 1, bottom: 1, right: 1))
            )
        ]
        for (id, layer, value) in notEditable {
            try assertRejected(id, value, on: layer, in: specimens, code: .attributeNotEditable)
        }

        // The value does not fit (P-SET-02, P-SET-03) or breaks a rule of the list.
        var nanTransform = WireTransform.identity
        nanTransform.m34 = .nan
        let invalid: [(String, CALayer, AttributeValue?)] = [
            ("label.numberOfLines", specimens.label.layer, nil),
            ("layer.opacity", specimens.layer, nil),
            ("layer.opacity", specimens.layer, .int(1)),
            ("label.text", specimens.label.layer, .double(1)),
            ("layer.opacity", specimens.layer, .double(.nan)),
            ("layer.zPosition", specimens.layer, .double(.infinity)),
            ("layer.bounds", specimens.layer, .rect(WireRect(x: 0, y: 0, width: .infinity, height: 1))),
            ("layer.position", specimens.layer, .point(WirePoint(x: .nan, y: 0))),
            ("layer.shadowOffset", specimens.layer, .size(WireSize(width: 0, height: -.infinity))),
            ("layer.transform", specimens.layer, .transform(nanTransform)),
            ("layer.backgroundColor", specimens.layer, color(.nan, 0, 0)),
            ("view.layoutMargins", specimens.view.layer, .insets(WireInsets(top: 0, left: .nan, bottom: 0, right: 0))),
            ("view.contentMode", specimens.view.layer, enumeration(99)),
            ("view.contentMode", specimens.view.layer, enumeration(-1)),
            ("layer.bounds", specimens.layer, .rect(WireRect(x: 0, y: 0, width: -1, height: 1))),
            ("layer.cornerRadius", specimens.layer, .double(-1)),
            ("layer.borderWidth", specimens.layer, .double(-0.5)),
            ("layer.shadowRadius", specimens.layer, .double(-2)),
            ("label.numberOfLines", specimens.label.layer, .int(-1)),
            ("label.fontSize", specimens.label.layer, .double(0)),
            ("textField.fontSize", specimens.textField.layer, .double(-3)),
            ("textView.fontSize", specimens.textView.layer, .double(0)),
            ("label.fontName", specimens.label.layer, .string("NoSuchFontAtAll")),
            ("textField.fontName", specimens.textField.layer, .string("courier")),
            ("textView.fontName", specimens.textView.layer, .string(".NoSuchSystemFont")),
            ("scrollView.contentSize", specimens.scrollView.layer, .size(WireSize(width: 10, height: -10)))
        ]
        for (id, layer, value) in invalid {
            try assertRejected(id, value, on: layer, in: specimens, code: .invalidAttributeValue)
        }
    }

    func test_S_SET_02_fallbackValuesAreNotEditable() throws {
        let specimens = try makeSpecimens()
        let tile = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        specimens.layer.backgroundColor = UIColor(patternImage: tile).cgColor
        // P-SET-03: the attribute as it reads now is read-only (P-ATTR-06).
        try assertRejected(
            "layer.backgroundColor",
            color(1, 0, 0),
            on: specimens.layer,
            in: specimens,
            code: .attributeNotEditable,
            message: "layer.backgroundColor is read-only"
        )
    }

    // MARK: - Protocol 1.1

    func test_S_ATTR_10_theLayersSideOfAPairIsNotEditableOnAView() throws {
        let specimens = try makeSpecimens()
        let registry = LayerRegistry()
        for pair in AttributeTables.pairs {
            try assertRejected(
                pair.layer,
                pair.layer == "layer.opacity" ? .double(0.5) : .bool(true),
                on: specimens.view.layer,
                in: specimens,
                registry: registry,
                code: .attributeNotEditable,
                message: "layer \(registry.register(specimens.view.layer)) backs a view; set \(pair.view) instead of \(pair.layer)"
            )
        }
        // The view's side is written, and the answer holds it alone (P-SET-01, P-ATTR-11).
        let answer = try apply("view.alpha", .double(0.5), on: specimens.view.layer, in: specimens.window).get()
        let ids = Set(answer.attributeGroups.flatMap(\.attributes).map(\.id))
        for pair in AttributeTables.pairs {
            XCTAssertTrue(ids.contains(pair.view), pair.view)
            XCTAssertFalse(ids.contains(pair.layer), pair.layer)
        }
        XCTAssertEqual(specimens.view.layer.opacity, 0.5)
        // On a layer of its own, the layer's side is there to be written.
        _ = try apply("layer.opacity", .double(0.25), on: specimens.layer, in: specimens.window).get()
        XCTAssertEqual(specimens.layer.opacity, 0.25)
    }

    func test_S_ATTR_10_aViewsBackgroundIsTheOneItDraws() throws {
        // A label draws its view's background into its contents, over the layer's; the layer's
        // stays nil. Its background is the view's, read and written as such.
        let specimens = try makeSpecimens()
        let label = specimens.label
        label.backgroundColor = .white
        let before = attributes(of: label.layer)
        XCTAssertNil(before["layer.backgroundColor"])
        XCTAssertTrue(matches(before["view.backgroundColor"]?.value, color(1, 1, 1)))

        _ = try apply("view.backgroundColor", color(1, 0.5, 0), on: label.layer, in: specimens.window).get()
        XCTAssertTrue(matches(attributes(of: label.layer)["view.backgroundColor"]?.value, color(1, 0.5, 0)))
        XCTAssertNil(label.layer.backgroundColor)
        let registry = LayerRegistry()
        try assertRejected(
            "layer.backgroundColor",
            color(1, 0.5, 0),
            on: label.layer,
            in: specimens,
            registry: registry,
            code: .attributeNotEditable,
            message: "layer \(registry.register(label.layer)) backs a view; set view.backgroundColor instead of "
                + "layer.backgroundColor"
        )
    }

    func test_S_ATTR_12_theAnswerToAChangeSaysWhatHasNoEffectNow() throws {
        let specimens = try makeSpecimens()
        func cause(of id: String, in answer: SetAttributeResult) -> String? {
            answer.attributeGroups.flatMap(\.attributes).first { $0.id == id }?.inactiveCause
        }
        specimens.layer.borderWidth = 0
        specimens.layer.shadowOpacity = 0
        let border = try apply("layer.borderWidth", .double(2), on: specimens.layer, in: specimens.window).get()
        XCTAssertNil(cause(of: "layer.borderColor", in: border))
        XCTAssertEqual(cause(of: "layer.shadowColor", in: border), "layer.shadowOpacity")
        let noBorder = try apply("layer.borderWidth", .double(0), on: specimens.layer, in: specimens.window).get()
        XCTAssertEqual(cause(of: "layer.borderColor", in: noBorder), "layer.borderWidth")
        let shadow = try apply("layer.shadowOpacity", .double(0.4), on: specimens.layer, in: specimens.window).get()
        for id in ["layer.shadowColor", "layer.shadowRadius", "layer.shadowOffset"] {
            XCTAssertNil(cause(of: id, in: shadow), id)
        }
    }

    func test_S_ATTR_14_aSystemColorsNameIsIgnoredWhenWritten() throws {
        let plain = try makeSpecimens()
        let named = try makeSpecimens()
        let blue = WireColor(red: 0, green: 0.5, blue: 1, alpha: 1)
        let withoutName = try apply("label.textColor", .color(blue), on: plain.label.layer, in: plain.window).get()
        let withName = try apply(
            "label.textColor",
            .color(blue, systemName: "systemRed"),
            on: named.label.layer,
            in: named.window
        ).get()
        let read = { (answer: SetAttributeResult) in
            answer.attributeGroups.flatMap(\.attributes).first { $0.id == "label.textColor" }
        }
        XCTAssertEqual(read(withName), read(withoutName))
        // A fixed colour, as written: no name.
        guard case .color(_, let name, _, _, _)? = read(withName)?.value else { return XCTFail("not a color") }
        XCTAssertNil(name)
    }

    // MARK: - S-SET-03

    func test_S_SET_03_fractionsAreRejectedAndChannelsClamped() throws {
        let specimens = try makeSpecimens()
        // Since 1.1 a fraction outside 0...1 is outside its limits, and refused (S-SET-06).
        for (id, layer) in [
            ("layer.opacity", specimens.layer),
            ("view.alpha", specimens.view.layer),
            ("layer.shadowOpacity", specimens.layer)
        ] {
            for written in [1.5, -0.5] {
                try assertRejected(
                    id,
                    .double(written),
                    on: layer,
                    in: specimens,
                    code: .invalidAttributeValue,
                    message: "\(id) must be between 0 and 1"
                )
            }
        }
        // A colour has no limits: its channels are still clamped (P-ATTR-04, P-SET-04).
        let answer = try apply(
            "layer.backgroundColor",
            color(1.5, -0.5, 0.25, 2),
            on: specimens.layer,
            in: specimens.window
        ).get()
        let background = answer.attributeGroups.flatMap(\.attributes).first { $0.id == "layer.backgroundColor" }
        XCTAssertTrue(matches(background?.value, color(1, 0, 0.25, 1)), "\(String(describing: background?.value))")
        // Clamped when written, not only when read. Core Graphics clamps too, so the clamp of
        // the server's own is checked on its own.
        XCTAssertEqual(AttributeInputs.channel(1.5), 1)
        XCTAssertEqual(AttributeInputs.channel(-0.5), 0)
        XCTAssertEqual(AttributeInputs.channel(0.25), 0.25)
    }

    // MARK: - S-SET-06

    /// For every attribute with limits: values on the bounds, which are accepted, and values just
    /// past them, which are refused.
    private static let limitCases: [(id: String, accepted: [AttributeValue], refused: [AttributeValue])] = {
        let step = 0.001
        func numbers(_ accepted: [Double], _ refused: [Double]) -> ([AttributeValue], [AttributeValue]) {
            (accepted.map { .double($0) }, refused.map { .double($0) })
        }
        let atLeastZero = numbers([0, 1e6], [-step])
        let unit = numbers([0, 1], [-step, 1 + step])
        let priority = numbers([1, 1000], [1 - step, 1000 + step])
        // The bound itself is outside an exclusive limit.
        let positive = numbers([step, 1e3], [0, -step])
        var cases: [(String, [AttributeValue], [AttributeValue])] = []
        for id in ["layer.cornerRadius", "layer.borderWidth", "layer.shadowRadius"] {
            cases.append((id, atLeastZero.0, atLeastZero.1))
        }
        for id in ["layer.opacity", "layer.shadowOpacity", "view.alpha"] { cases.append((id, unit.0, unit.1)) }
        for id in [
            "view.contentHuggingPriority.horizontal",
            "view.contentHuggingPriority.vertical",
            "view.contentCompressionResistancePriority.horizontal",
            "view.contentCompressionResistancePriority.vertical"
        ] {
            cases.append((id, priority.0, priority.1))
        }
        for id in ["label.fontSize", "textField.fontSize", "textView.fontSize"] {
            cases.append((id, positive.0, positive.1))
        }
        cases.append(("label.numberOfLines", [.int(0), .int(3)], [.int(-1)]))
        // x and y are free; width and height are not.
        cases.append((
            "layer.bounds",
            [
                .rect(WireRect(x: -20, y: -20, width: 0, height: 0)),
                .rect(WireRect(x: 5, y: -1e6, width: 10, height: 0))
            ],
            [
                .rect(WireRect(x: 0, y: 0, width: -step, height: 10)),
                .rect(WireRect(x: 0, y: 0, width: 10, height: -step))
            ]
        ))
        cases.append((
            "scrollView.contentSize",
            [.size(WireSize(width: 0, height: 0))],
            [.size(WireSize(width: -step, height: 0)), .size(WireSize(width: 0, height: -step))]
        ))
        return cases
    }()

    func test_S_SET_06_limitsAcceptTheirBoundsAndRefuseWhatLiesPast() throws {
        // Every attribute that has limits is here.
        var limited = Set<String>()
        let specimens = try makeSpecimens()
        for layer in [specimens.layer] + specimens.window.subviews.map(\.layer) {
            for attribute in AttributeCatalog.standard.read(layer).flatMap(\.attributes)
                where !attribute.limits.isEmpty {
                limited.insert(attribute.id)
            }
        }
        XCTAssertEqual(Set(Self.limitCases.map(\.id)), limited)

        for (id, accepted, refused) in Self.limitCases {
            for value in refused {
                let specimens = try makeSpecimens()
                try assertRejected(id, value, on: specimens.target(of: id), in: specimens, code: .invalidAttributeValue)
            }
            for value in accepted {
                let specimens = try makeSpecimens()
                let layer = specimens.target(of: id)
                XCTAssertNoThrow(try apply(id, value, on: layer, in: specimens.window).get(), "\(id) = \(value)")
            }
        }
    }

    func test_S_SET_06_refusalsNameTheBoundAndTheComponent() throws {
        let specimens = try makeSpecimens()
        try assertRejected(
            "layer.cornerRadius",
            .double(-1),
            on: specimens.layer,
            in: specimens,
            code: .invalidAttributeValue,
            message: "layer.cornerRadius cannot be negative"
        )
        try assertRejected(
            "label.fontSize",
            .double(0),
            on: specimens.label.layer,
            in: specimens,
            code: .invalidAttributeValue,
            message: "label.fontSize must be greater than 0"
        )
        try assertRejected(
            "view.contentHuggingPriority.vertical",
            .double(1001),
            on: specimens.view.layer,
            in: specimens,
            code: .invalidAttributeValue,
            message: "view.contentHuggingPriority.vertical must be between 1 and 1000"
        )
        try assertRejected(
            "layer.bounds",
            .rect(WireRect(x: -20, y: 0, width: -20, height: 24)),
            on: specimens.layer,
            in: specimens,
            code: .invalidAttributeValue,
            message: "layer.bounds width cannot be negative"
        )
        try assertRejected(
            "scrollView.contentSize",
            .size(WireSize(width: 1, height: -1)),
            on: specimens.scrollView.layer,
            in: specimens,
            code: .invalidAttributeValue,
            message: "scrollView.contentSize height cannot be negative"
        )
    }

    func test_S_SET_06_aValueTheAppSetOutsideTheLimitsCannotBeKept() throws {
        let specimens = try makeSpecimens()
        let scrollView = specimens.scrollView
        // The app may set what a client may not (P-SET-07): it is shown as it is. (A layer's
        // bounds cannot be set so: Core Animation makes the size positive.)
        scrollView.contentSize = CGSize(width: -10, height: 20)
        XCTAssertEqual(
            attributes(of: scrollView.layer)["scrollView.contentSize"]?.value,
            .size(WireSize(width: -10, height: 20))
        )
        // A change that keeps the width is refused like any other value outside the limits.
        try assertRejected(
            "scrollView.contentSize",
            .size(WireSize(width: -10, height: 40)),
            on: scrollView.layer,
            in: specimens,
            code: .invalidAttributeValue,
            message: "scrollView.contentSize width cannot be negative"
        )
        // One that brings it back within them is accepted.
        XCTAssertNoThrow(
            try apply(
                "scrollView.contentSize",
                .size(WireSize(width: 10, height: 40)),
                on: scrollView.layer,
                in: specimens.window
            ).get()
        )
    }

    // MARK: - S-SET-04

    func test_S_SET_04_noAnimationIsAdded() throws {
        let specimens = try makeSpecimens()
        CATransaction.flush()
        let changes: [(String, CALayer, AttributeValue)] = [
            ("layer.opacity", specimens.layer, .double(0.3)),
            ("layer.position", specimens.layer, .point(WirePoint(x: 80, y: 80))),
            ("layer.backgroundColor", specimens.layer, color(0, 1, 0)),
            ("layer.bounds", specimens.layer, .rect(WireRect(x: 0, y: 0, width: 30, height: 30))),
            ("view.alpha", specimens.view.layer, .double(0.3)),
            ("layer.cornerRadius", specimens.view.layer, .double(4))
        ]
        for (id, layer, value) in changes {
            _ = try apply(id, value, on: layer, in: specimens.window).get()
            XCTAssertNil(layer.animationKeys(), "\(id) added an animation")
        }
        // Also when the change lands in an animation block of the host's.
        UIView.animate(withDuration: 1) {
            _ = self.apply("view.alpha", .double(0.8), on: specimens.view.layer, in: specimens.window)
            _ = self.apply("layer.opacity", .double(0.8), on: specimens.layer, in: specimens.window)
        }
        XCTAssertNil(specimens.view.layer.animationKeys())
        XCTAssertNil(specimens.layer.animationKeys())
        // What the test would see without the transaction (the check above is not blind).
        specimens.layer.opacity = 0.1
        XCTAssertEqual(specimens.layer.animationKeys(), ["opacity"])
    }

    func test_S_SET_04_layoutIsDoneBeforeTheReply() throws {
        let window = try makeWindow()
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = "a"
        let sibling = UIView()
        sibling.widthAnchor.constraint(equalToConstant: 20).isActive = true
        stack.addArrangedSubview(label)
        stack.addArrangedSubview(sibling)
        window.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 10),
            stack.topAnchor.constraint(equalTo: window.topAnchor, constant: 100)
        ])
        window.layoutIfNeeded()
        let before = sibling.frame

        let registry = LayerRegistry()
        _ = try apply("label.text", .string("a much longer text"), on: label.layer, in: window, registry: registry)
            .get()
        // Within the same run of the main thread: the sibling has moved already.
        XCTAssertGreaterThan(sibling.frame.minX, before.minX + 50)
        let rootID = registry.register(stack.layer)
        let now = HierarchyCapture.captureSubtree(rootID: rootID, in: .testing(windows: [window], registry: registry))
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let later = HierarchyCapture.captureSubtree(rootID: rootID, in: .testing(windows: [window], registry: registry))
        XCTAssertNotNil(now)
        XCTAssertEqual(now, later, "the geometry changed after the answer")
    }

    // MARK: - S-SET-05

    private final class Answer: @unchecked Sendable {
        // Written on the host's queue before the expectation is fulfilled, read after.
        var result: Result<SetAttributeResult, WireError>?
    }

    /// Writes through `HostAccess`, as a session does, while the app is in `state`.
    private func applyThroughTheHost(
        _ id: String,
        _ value: AttributeValue?,
        on layer: CALayer,
        appState state: AppState
    ) throws -> Result<SetAttributeResult, WireError> {
        var app = TestHostApp()
        app.appState = { state }
        let registry = LayerRegistry()
        let host = HostAccess(
            app: app,
            registry: registry,
            queue: DispatchQueue(label: "dev.cutaway.tests.editing"),
            encodeQueue: DispatchQueue(label: "dev.cutaway.tests.editing.encode")
        )
        let change = SetAttribute(layerID: registry.register(layer), attributeID: id, value: value)
        let answer = Answer()
        let answered = expectation(description: "SetAttribute answered")
        host.performChange(
            version: .current,
            { app, context in app.setAttribute(change, in: context) },
            then: { result in
                answer.result = result
                answered.fulfill()
            }
        )
        wait(for: [answered], timeout: 5)
        return try XCTUnwrap(answer.result)
    }

    func test_S_SET_05_nothingIsChangedWhileNotActive() throws {
        let specimens = try makeSpecimens()
        for state in [AppState.inactive, .background] {
            let result = try applyThroughTheHost("view.tag", .int(9), on: specimens.view.layer, appState: state)
            XCTAssertEqual(result, .failure(WireError(code: .appNotActive, message: "the app is not active")))
            XCTAssertEqual(specimens.view.tag, 0)
        }
        // The same change goes through once the app is active.
        _ = try applyThroughTheHost("view.tag", .int(9), on: specimens.view.layer, appState: .active).get()
        XCTAssertEqual(specimens.view.tag, 9)
    }

    // MARK: - S-SET-07

    // The attributes of protocol 1.2, written to a view whose ID comes from one registry.

    private let registry = LayerRegistry()
    /// Data sources are held weakly.
    private var retained: [AnyObject] = []

    private func apply(
        _ id: String,
        _ value: AttributeValue?,
        on view: UIView,
        in window: UIWindow
    ) -> Result<SetAttributeResult, WireError> {
        AttributeEditing.apply(
            SetAttribute(layerID: registry.register(view.layer), attributeID: id, value: value),
            in: .testing(windows: [window], registry: registry)
        )
    }

    private func readBack(
        _ id: String,
        in result: Result<SetAttributeResult, WireError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AttributeValue? {
        let answer = try result.get()
        return try XCTUnwrap(
            answer.attributeGroups.flatMap(\.attributes).first { $0.id == id },
            "no \(id) in the answer",
            file: file,
            line: line
        ).value
    }

    func test_S_SET_07_accessibilityIsWrittenAndReadBack() throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        window.addSubview(view)
        for (id, text) in [
            ("view.accessibilityLabel", "Save"),
            ("view.accessibilityHint", "Saves the page"),
            ("view.accessibilityValue", "3"),
            ("view.accessibilityIdentifier", "save")
        ] {
            XCTAssertEqual(try readBack(id, in: apply(id, .string(text), on: view, in: window)), .string(text), id)
            XCTAssertNil(try readBack(id, in: apply(id, nil, on: view, in: window)), id)
        }
        XCTAssertEqual(
            try readBack(
                "view.isAccessibilityElement",
                in: apply("view.isAccessibilityElement", .bool(true), on: view, in: window)
            ),
            .bool(true)
        )
        XCTAssertTrue(view.isAccessibilityElement)
        view.accessibilityLabel = nil
        _ = try apply("view.accessibilityLabel", .string("Save"), on: view, in: window).get()
        XCTAssertEqual(view.accessibilityLabel, "Save")
    }

    func test_S_SET_07_textSizeFollowingIsWrittenAndReadBack() throws {
        let window = try makeWindow()
        let label = UILabel()
        let field = UITextField()
        let text = UITextView()
        for view in [label, field, text] as [UIView] {
            view.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
            window.addSubview(view)
        }
        for (group, view) in [("label", label), ("textField", field), ("textView", text)] as [(String, UIView)] {
            let id = "\(group).adjustsFontForContentSizeCategory"
            XCTAssertEqual(try readBack(id, in: apply(id, .bool(true), on: view, in: window)), .bool(true), id)
            XCTAssertEqual(try readBack(id, in: apply(id, .bool(false), on: view, in: window)), .bool(false), id)
        }
        _ = try apply("label.adjustsFontForContentSizeCategory", .bool(true), on: label, in: window).get()
        XCTAssertTrue(label.adjustsFontForContentSizeCategory)
    }

    func test_S_SET_07_theOtherAttributesOfProtocol12AreNotEditable() throws {
        let window = try makeWindow()
        let view = UIView()
        let scroll = UIScrollView()
        let source = CountingDataSource()
        retained.append(source)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.dataSource = source
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 40, height: 40)
        let collection = UICollectionView(
            frame: CGRect(x: 0, y: 200, width: 320, height: 200),
            collectionViewLayout: layout
        )
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "item")
        collection.dataSource = source
        let tableCell = UITableViewCell(style: .default, reuseIdentifier: "cell")
        let collectionCell = UICollectionViewCell()
        let stack = UIStackView(arrangedSubviews: [UIView()])
        let image = UIImageView(image: UIImage(systemName: "star.fill"))
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "star.fill"), for: .normal)
        let label = UILabel()
        label.text = "Label"
        let field = UITextField()
        let text = UITextView()
        let views: [String: UIView] = [
            "view": view,
            "scrollView": scroll,
            "tableView": table,
            "collectionView": collection,
            "tableViewCell": tableCell,
            "collectionViewCell": collectionCell,
            "stackView": stack,
            "imageView": image,
            "button": button,
            "label": label,
            "textField": field,
            "textView": text
        ]
        for subview in views.values {
            if subview.frame.isEmpty { subview.frame = CGRect(x: 0, y: 0, width: 200, height: 40) }
            window.addSubview(subview)
        }
        window.layoutIfNeeded()

        let readOnly = [
            "view.accessibilityTraits",
            "scrollView.delegate",
            "stackView.arrangedSubviews",
            "stackView.customSpacing",
            "label.fontDescription",
            "label.fontTextStyle",
            "label.drawnLineCount",
            "label.isTruncated",
            "textField.fontDescription",
            "textField.fontTextStyle",
            "textView.fontDescription",
            "textView.fontTextStyle"
        ]
            + ["dataSource", "numberOfSections", "numberOfRows", "rowsPerSection", "visibleIndexPaths"]
            .map { "tableView.\($0)" }
            + ["dataSource", "numberOfSections", "numberOfItems", "itemsPerSection", "visibleIndexPaths"]
            .map { "collectionView.\($0)" }
            + ["section", "row", "reuseIdentifier"].map { "tableViewCell.\($0)" }
            + ["section", "item", "reuseIdentifier"].map { "collectionViewCell.\($0)" }
            + ["imageView", "button"].flatMap { group in
                ["imageName", "imageSize", "imageScale", "imageRenderingMode", "symbolConfiguration"]
                    .map { "\(group).\($0)" }
            }
        let entries = ExpectedAttributes.groups.values.flatMap(\.attributes)
        for id in readOnly {
            let entry = try XCTUnwrap(entries.first { $0.id == id }, id)
            XCTAssertFalse(entry.editable, id)
            let value: AttributeValue = switch entry.kind {
            case .string: .string("x")
            case .int: .int(1)
            case .bool: .bool(true)
            case .double: .double(1)
            case .size: .size(WireSize(width: 1, height: 1))
            case .enumeration: .enumeration(value: 0, cases: [], caseName: "", caseValues: [])
            case .layerReference: .layerReference([])
            default: .string("x")
            }
            let target = try XCTUnwrap(views[String(id.prefix { $0 != "." })], id)
            guard case .failure(let error) = apply(id, value, on: target, in: window) else {
                XCTFail("\(id) was written")
                continue
            }
            XCTAssertEqual(error.code, .attributeNotEditable, id)
        }
    }

    /// S-ATTR-17, P-SET-02: the light and dark of a colour are ignored when it is written.
    func test_S_ATTR_17_lightAndDarkAreIgnoredWhenWritten() throws {
        let window = try makeWindow()
        let plain = UIView()
        let styled = UIView()
        window.addSubview(plain)
        window.addSubview(styled)
        let color = WireColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let other = WireColor(red: 1, green: 0, blue: 0, alpha: 1)
        let written = try readBack(
            "view.backgroundColor",
            in: apply("view.backgroundColor", .color(color), on: plain, in: window)
        )
        let withBoth = try readBack(
            "view.backgroundColor",
            in: apply("view.backgroundColor", .color(color, light: other, dark: other), on: styled, in: window)
        )
        XCTAssertEqual(written, withBoth)
        guard case let .color(_, _, light, dark, _)? = withBoth else { return XCTFail("not a colour") }
        XCTAssertNil(light)
        XCTAssertNil(dark)
    }
}
