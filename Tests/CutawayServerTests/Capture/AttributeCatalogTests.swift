import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// A label class of the tests' own: subclasses get the groups of their UIKit class.
private final class TitleLabel: UILabel {}

/// An enumeration as the catalog reads it. The enumerations of the list have raw values from
/// 0 (`test_S_ATTR_06_caseValuesAreRawValues` checks that against UIKit).
private func enumeration(value: Int64, cases: [String], caseName: String) -> AttributeValue {
    .enumeration(
        value: value,
        cases: cases,
        caseName: caseName,
        caseValues: cases.indices.map(Int64.init)
    )
}

/// Reading the attributes of one layer. No server, no connection.
final class AttributeCatalogTests: CaptureTestCase {
    /// One instance of every kind of layer the list tells apart, in a window, with the groups
    /// it must have.
    private func specimens() throws -> [(name: String, layer: CALayer, groups: [String])] {
        let window = try makeWindow()
        let bare = CALayer()
        window.layer.addSublayer(bare)
        let plain = UIView()
        // A view is its delegate, but the layer is not the view's: it backs no view.
        let foreign = CALayer()
        foreign.delegate = plain
        window.layer.addSublayer(foreign)

        let views: [(String, UIView, [String])] = [
            ("UIView", plain, ["layer", "view"]),
            ("UILabel", UILabel(), ["layer", "view", "label"]),
            ("TitleLabel", TitleLabel(), ["layer", "view", "label"]),
            ("UIImageView", UIImageView(), ["layer", "view", "imageView"]),
            ("UISwitch", UISwitch(), ["layer", "view", "control"]),
            ("UIButton", UIButton(type: .system), ["layer", "view", "control", "button"]),
            ("UIScrollView", UIScrollView(), ["layer", "view", "scrollView"]),
            ("UITableView", UITableView(), ["layer", "view", "scrollView"]),
            ("UIStackView", UIStackView(), ["layer", "view", "stackView"]),
            ("UITextField", UITextField(), ["layer", "view", "control", "textField"]),
            ("UITextView", UITextView(), ["layer", "view", "scrollView", "textView"])
        ]
        for (_, view, _) in views {
            view.frame = CGRect(x: 10, y: 10, width: 200, height: 100)
            window.addSubview(view)
        }
        return [
            ("bare CALayer", bare, ["layer"]),
            ("a layer whose delegate is another view's", foreign, ["layer"]),
            ("UIWindow", window.layer, ["layer", "view"])
        ] + views.map { ($0.0, $0.1.layer, $0.2) }
    }

    private func attribute(
        _ id: String,
        of layer: CALayer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Attribute {
        let groupID = String(id.prefix { $0 != "." })
        let group = try XCTUnwrap(
            AttributeCatalog.standard.read(layer).first { $0.id == groupID },
            "no group \(groupID)",
            file: file,
            line: line
        )
        return try XCTUnwrap(
            group.attributes.first { $0.id == id },
            "no attribute \(id)",
            file: file,
            line: line
        )
    }

    private func value(
        _ id: String,
        of layer: CALayer,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AttributeValue? {
        try attribute(id, of: layer, file: file, line: line).value
    }

    private func assertColor(
        _ value: AttributeValue?,
        _ red: Float,
        _ green: Float,
        _ blue: Float,
        _ alpha: Float = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .color(let color, _)? = value else {
            return XCTFail("\(String(describing: value)) is not a colour", file: file, line: line)
        }
        for (actual, expected) in zip(
            [color.red, color.green, color.blue, color.alpha],
            [red, green, blue, alpha]
        ) {
            XCTAssertEqual(actual, expected, accuracy: 1e-4, "\(color)", file: file, line: line)
        }
    }

    // MARK: - S-ATTR-01

    func test_S_ATTR_01_groupsFollowTheClass() throws {
        for specimen in try specimens() {
            XCTAssertEqual(
                AttributeCatalog.standard.read(specimen.layer).map(\.id),
                specimen.groups,
                specimen.name
            )
        }
    }

    func test_S_ATTR_01_attributesMatchTheList() throws {
        var seen = Set<String>()
        for specimen in try specimens() {
            for group in AttributeCatalog.standard.read(specimen.layer) {
                seen.insert(group.id)
                let expected = try XCTUnwrap(ExpectedAttributes.groups[group.id], "unknown group \(group.id)")
                XCTAssertEqual(group.title, expected.title)
                XCTAssertEqual(group.attributes.map(\.id), expected.attributes.map(\.id), specimen.name)
                XCTAssertEqual(group.attributes.map(\.title), expected.attributes.map(\.title), specimen.name)
                for (attribute, entry) in zip(group.attributes, expected.attributes) {
                    if let value = attribute.value {
                        XCTAssertEqual(value.kind, entry.kind, "\(specimen.name): \(entry.id)")
                    } else {
                        XCTAssertTrue(entry.nullable, "\(specimen.name): \(entry.id) is nil")
                    }
                }
            }
        }
        // Every group of the list was looked at.
        XCTAssertEqual(seen, Set(ExpectedAttributes.groups.keys))
    }

    func test_S_ATTR_01_titlesFollowTheRule() {
        XCTAssertEqual(AttributeCatalog.title(for: "layer"), "Layer")
        XCTAssertEqual(AttributeCatalog.title(for: "hidden"), "Hidden")
        XCTAssertEqual(AttributeCatalog.title(for: "scrollView"), "Scroll View")
        XCTAssertEqual(AttributeCatalog.title(for: "zPosition"), "Z Position")
        XCTAssertEqual(
            AttributeCatalog.title(for: "isUserInteractionEnabled"),
            "Is User Interaction Enabled"
        )
    }

    func test_S_ATTR_01_layerValuesAreRead() throws {
        let window = try makeWindow()
        let layer = CALayer()
        layer.anchorPoint = .zero
        layer.bounds = CGRect(x: 5, y: 6, width: 60, height: 30)
        layer.position = CGPoint(x: 20, y: 65)
        layer.zPosition = 3
        layer.transform = CATransform3DMakeScale(2, 2, 1)
        layer.isHidden = true
        layer.opacity = 0.5
        layer.cornerRadius = 4
        layer.backgroundColor = UIColor(red: 1, green: 0.5, blue: 0, alpha: 1).cgColor
        layer.borderWidth = 2
        layer.borderColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1).cgColor
        layer.shadowColor = UIColor(red: 0, green: 1, blue: 0, alpha: 0.5).cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 7
        layer.shadowOffset = CGSize(width: 1, height: -2)
        window.layer.addSublayer(layer)
        // Two attributes of the same kind never share a value across the two layers, so a reader
        // that reads the wrong property shows.
        let clipping = CALayer()
        clipping.masksToBounds = true
        window.layer.addSublayer(clipping)

        XCTAssertEqual(try value("layer.frame", of: layer), .rect(WireRect(x: 20, y: 65, width: 120, height: 60)))
        XCTAssertEqual(try value("layer.bounds", of: layer), .rect(WireRect(x: 5, y: 6, width: 60, height: 30)))
        XCTAssertEqual(try value("layer.position", of: layer), .point(WirePoint(x: 20, y: 65)))
        XCTAssertEqual(try value("layer.anchorPoint", of: layer), .point(WirePoint(x: 0, y: 0)))
        XCTAssertEqual(try value("layer.zPosition", of: layer), .double(3))
        var scale = WireTransform.identity
        scale.m11 = 2
        scale.m22 = 2
        XCTAssertEqual(try value("layer.transform", of: layer), .transform(scale))
        XCTAssertEqual(try value("layer.hidden", of: layer), .bool(true))
        XCTAssertEqual(try value("layer.opacity", of: layer), .double(0.5))
        XCTAssertEqual(try value("layer.masksToBounds", of: layer), .bool(false))
        XCTAssertEqual(try value("layer.hidden", of: clipping), .bool(false))
        XCTAssertEqual(try value("layer.masksToBounds", of: clipping), .bool(true))
        XCTAssertEqual(try value("layer.cornerRadius", of: layer), .double(4))
        assertColor(try value("layer.backgroundColor", of: layer), 1, 0.5, 0)
        XCTAssertEqual(try value("layer.borderWidth", of: layer), .double(2))
        assertColor(try value("layer.borderColor", of: layer), 0, 0, 1)
        assertColor(try value("layer.shadowColor", of: layer), 0, 1, 0, 0.5)
        XCTAssertEqual(try value("layer.shadowOpacity", of: layer), .double(0.25))
        XCTAssertEqual(try value("layer.shadowRadius", of: layer), .double(7))
        XCTAssertEqual(try value("layer.shadowOffset", of: layer), .size(WireSize(width: 1, height: -2)))
    }

    func test_S_ATTR_01_viewValuesAreRead() throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 100, height: 100))
        view.alpha = 0.75
        view.isHidden = true
        view.isOpaque = true
        view.clipsToBounds = false
        view.isUserInteractionEnabled = false
        view.tag = 42
        view.contentMode = .bottomRight
        view.tintColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        view.insetsLayoutMarginsFromSafeArea = false
        view.layoutMargins = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        window.addSubview(view)
        let layer = view.layer
        // With `view`, every one of the four Booleans has a pattern of its own.
        let other = UIView()
        other.isHidden = true
        other.isOpaque = false
        other.clipsToBounds = true
        other.isUserInteractionEnabled = false
        window.addSubview(other)

        XCTAssertEqual(try value("view.alpha", of: layer), .double(0.75))
        XCTAssertEqual(try value("view.isHidden", of: layer), .bool(true))
        XCTAssertEqual(try value("view.isOpaque", of: layer), .bool(true))
        XCTAssertEqual(try value("view.clipsToBounds", of: layer), .bool(false))
        XCTAssertEqual(try value("view.isUserInteractionEnabled", of: layer), .bool(false))
        XCTAssertEqual(try value("view.isHidden", of: other.layer), .bool(true))
        XCTAssertEqual(try value("view.isOpaque", of: other.layer), .bool(false))
        XCTAssertEqual(try value("view.clipsToBounds", of: other.layer), .bool(true))
        XCTAssertEqual(try value("view.isUserInteractionEnabled", of: other.layer), .bool(false))
        XCTAssertEqual(try value("view.tag", of: layer), .int(42))
        XCTAssertEqual(
            try value("view.contentMode", of: layer),
            enumeration(value: 12, cases: AttributeOutputs.contentModeNames, caseName: "bottomRight")
        )
        assertColor(try value("view.tintColor", of: layer), 1, 0, 0)
        XCTAssertEqual(
            try value("view.layoutMargins", of: layer),
            .insets(WireInsets(top: 1, left: 2, bottom: 3, right: 4))
        )
    }

    func test_S_ATTR_01_labelImageAndControlValuesAreRead() throws {
        let window = try makeWindow()
        let label = UILabel()
        label.text = "Hello"
        label.font = UIFont.systemFont(ofSize: 21)
        label.textColor = UIColor(red: 0, green: 0.5, blue: 1, alpha: 1)
        label.textAlignment = .right
        label.numberOfLines = 3
        label.lineBreakMode = .byTruncatingMiddle
        let imageView = UIImageView(
            image: UIGraphicsImageRenderer(size: CGSize(width: 30, height: 20)).image { _ in }
        )
        imageView.isHighlighted = true
        let toggle = UISwitch()
        toggle.isEnabled = false
        toggle.isSelected = true
        // A disabled control is never highlighted. Across the three switches each of the three
        // Booleans has a pattern of its own.
        let pressed = UISwitch()
        pressed.isHighlighted = true
        let idle = UISwitch()
        let button = UIButton(type: .custom)
        button.setTitle("Go", for: .normal)
        button.setTitleColor(UIColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1), for: .normal)
        for view in [label, imageView, toggle, pressed, idle, button] { window.addSubview(view) }

        XCTAssertEqual(try value("label.text", of: label.layer), .string("Hello"))
        XCTAssertEqual(try value("label.fontName", of: label.layer), .string(label.font.fontName))
        XCTAssertEqual(try value("label.fontSize", of: label.layer), .double(21))
        assertColor(try value("label.textColor", of: label.layer), 0, 0.5, 1)
        XCTAssertEqual(
            try value("label.textAlignment", of: label.layer),
            enumeration(value: 2, cases: AttributeOutputs.textAlignmentNames, caseName: "right")
        )
        XCTAssertEqual(try value("label.numberOfLines", of: label.layer), .int(3))
        XCTAssertEqual(
            try value("label.lineBreakMode", of: label.layer),
            enumeration(value: 5, cases: AttributeOutputs.lineBreakModeNames, caseName: "byTruncatingMiddle")
        )

        XCTAssertEqual(try value("imageView.imageSize", of: imageView.layer), .size(WireSize(width: 30, height: 20)))
        XCTAssertEqual(try value("imageView.isHighlighted", of: imageView.layer), .bool(true))

        for (control, enabled, selected, highlighted) in [
            (toggle, false, true, false),
            (pressed, true, false, true),
            (idle, true, false, false)
        ] {
            XCTAssertEqual(try value("control.isEnabled", of: control.layer), .bool(enabled))
            XCTAssertEqual(try value("control.isSelected", of: control.layer), .bool(selected))
            XCTAssertEqual(try value("control.isHighlighted", of: control.layer), .bool(highlighted))
        }

        XCTAssertEqual(try value("button.currentTitle", of: button.layer), .string("Go"))
        assertColor(try value("button.currentTitleColor", of: button.layer), 0.2, 0.4, 0.6)
    }

    func test_S_ATTR_01_scrollStackAndTextValuesAreRead() throws {
        let window = try makeWindow()
        // At the top of the window the scroll view lies under the status bar: the adjusted inset
        // adds the safe area to the content inset.
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 200))
        scrollView.contentInsetAdjustmentBehavior = .always
        scrollView.contentSize = CGSize(width: 300, height: 600)
        scrollView.contentInset = UIEdgeInsets(top: 1, left: 2, bottom: 3, right: 4)
        scrollView.isScrollEnabled = false
        scrollView.isPagingEnabled = true
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .trailing
        stack.distribution = .equalSpacing
        stack.spacing = 8
        let field = UITextField()
        field.text = "abc"
        field.placeholder = "type"
        field.font = UIFont.systemFont(ofSize: 13)
        field.textColor = UIColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)
        let textView = UITextView()
        textView.text = "notes"
        textView.font = UIFont.systemFont(ofSize: 15)
        textView.textColor = UIColor(red: 0.3, green: 0.2, blue: 0.1, alpha: 1)
        textView.isEditable = false
        for view in [scrollView, stack, field, textView] { window.addSubview(view) }
        // Set once the safe area is known: UIKit moves the offset when the adjusted inset changes.
        scrollView.contentOffset = CGPoint(x: 0, y: 100)

        let scroll = scrollView.layer
        XCTAssertEqual(try value("scrollView.contentOffset", of: scroll), .point(WirePoint(x: 0, y: 100)))
        XCTAssertEqual(try value("scrollView.contentSize", of: scroll), .size(WireSize(width: 300, height: 600)))
        XCTAssertEqual(
            try value("scrollView.contentInset", of: scroll),
            .insets(WireInsets(top: 1, left: 2, bottom: 3, right: 4))
        )
        let adjusted = scrollView.adjustedContentInset
        XCTAssertNotEqual(adjusted, scrollView.contentInset, "the test needs a safe area at the top")
        XCTAssertEqual(
            try value("scrollView.adjustedContentInset", of: scroll),
            .insets(WireInsets(top: adjusted.top, left: adjusted.left, bottom: adjusted.bottom, right: adjusted.right))
        )
        XCTAssertEqual(try value("scrollView.isScrollEnabled", of: scroll), .bool(false))
        XCTAssertEqual(try value("scrollView.isPagingEnabled", of: scroll), .bool(true))

        XCTAssertEqual(
            try value("stackView.axis", of: stack.layer),
            enumeration(value: 1, cases: ["horizontal", "vertical"], caseName: "vertical")
        )
        XCTAssertEqual(
            try value("stackView.alignment", of: stack.layer),
            enumeration(
                value: 4,
                cases: ["fill", "leading", "firstBaseline", "center", "trailing", "lastBaseline"],
                caseName: "trailing"
            )
        )
        XCTAssertEqual(
            try value("stackView.distribution", of: stack.layer),
            enumeration(
                value: 3,
                cases: ["fill", "fillEqually", "fillProportionally", "equalSpacing", "equalCentering"],
                caseName: "equalSpacing"
            )
        )
        XCTAssertEqual(try value("stackView.spacing", of: stack.layer), .double(8))

        XCTAssertEqual(try value("textField.text", of: field.layer), .string("abc"))
        XCTAssertEqual(try value("textField.placeholder", of: field.layer), .string("type"))
        XCTAssertEqual(try value("textField.fontName", of: field.layer), .string(field.font!.fontName))
        XCTAssertEqual(try value("textField.fontSize", of: field.layer), .double(13))
        assertColor(try value("textField.textColor", of: field.layer), 0.1, 0.2, 0.3)

        XCTAssertEqual(try value("textView.text", of: textView.layer), .string("notes"))
        XCTAssertEqual(try value("textView.fontName", of: textView.layer), .string(textView.font!.fontName))
        XCTAssertEqual(try value("textView.fontSize", of: textView.layer), .double(15))
        assertColor(try value("textView.textColor", of: textView.layer), 0.3, 0.2, 0.1)
        XCTAssertEqual(try value("textView.isEditable", of: textView.layer), .bool(false))
    }

    // MARK: - S-ATTR-03

    func test_S_ATTR_03_nilValuesStayAsAttributes() throws {
        let window = try makeWindow()
        let layer = CALayer()
        // CALayer's border and shadow are opaque black unless told otherwise.
        layer.borderColor = nil
        layer.shadowColor = nil
        window.layer.addSublayer(layer)
        let label = UILabel()
        label.text = nil
        let imageView = UIImageView()
        let button = UIButton(type: .custom)
        let field = UITextField()
        let textView = UITextView()
        for view in [label, imageView, button, field, textView] { window.addSubview(view) }

        let nils: [(String, CALayer)] = [
            ("layer.backgroundColor", layer),
            ("layer.borderColor", layer),
            ("layer.shadowColor", layer),
            // A window inherits no tint colour.
            ("view.tintColor", window.layer),
            ("label.text", label.layer),
            ("imageView.imageSize", imageView.layer),
            ("button.currentTitle", button.layer),
            ("textField.placeholder", field.layer),
            // A text view has no font of its own until it is given one.
            ("textView.fontName", textView.layer),
            ("textView.fontSize", textView.layer)
        ]
        for (id, layer) in nils {
            let attribute = try attribute(id, of: layer)
            XCTAssertNil(attribute.value, id)
            XCTAssertFalse(attribute.title.isEmpty, id)
        }
    }

    func test_S_ATTR_03_enumsNameEveryCase() throws {
        let window = try makeWindow()
        let view = UIView()
        view.contentMode = .scaleAspectFill
        let label = UILabel()
        label.textAlignment = .natural
        label.lineBreakMode = .byWordWrapping
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .top
        row.distribution = .fillProportionally
        let column = UIStackView()
        column.axis = .vertical
        column.alignment = .leading
        for view in [view, label, row, column] { window.addSubview(view) }

        XCTAssertEqual(
            try value("view.contentMode", of: view.layer),
            enumeration(
                value: 2,
                cases: [
                    "scaleToFill",
                    "scaleAspectFit",
                    "scaleAspectFill",
                    "redraw",
                    "center",
                    "top",
                    "bottom",
                    "left",
                    "right",
                    "topLeft",
                    "topRight",
                    "bottomLeft",
                    "bottomRight"
                ],
                caseName: "scaleAspectFill"
            )
        )
        XCTAssertEqual(
            try value("label.textAlignment", of: label.layer),
            enumeration(
                value: 4,
                cases: ["left", "center", "right", "justified", "natural"],
                caseName: "natural"
            )
        )
        XCTAssertEqual(
            try value("label.lineBreakMode", of: label.layer),
            enumeration(
                value: 0,
                cases: [
                    "byWordWrapping",
                    "byCharWrapping",
                    "byClipping",
                    "byTruncatingHead",
                    "byTruncatingTail",
                    "byTruncatingMiddle"
                ],
                caseName: "byWordWrapping"
            )
        )
        XCTAssertEqual(
            try value("stackView.axis", of: row.layer),
            enumeration(value: 0, cases: ["horizontal", "vertical"], caseName: "horizontal")
        )
        XCTAssertEqual(
            try value("stackView.distribution", of: row.layer),
            enumeration(
                value: 2,
                cases: ["fill", "fillEqually", "fillProportionally", "equalSpacing", "equalCentering"],
                caseName: "fillProportionally"
            )
        )

        // The aliases are named after the axis.
        let across = ["fill", "top", "firstBaseline", "center", "bottom", "lastBaseline"]
        let along = ["fill", "leading", "firstBaseline", "center", "trailing", "lastBaseline"]
        XCTAssertEqual(
            try value("stackView.alignment", of: row.layer),
            enumeration(value: 1, cases: across, caseName: "top")
        )
        XCTAssertEqual(
            try value("stackView.alignment", of: column.layer),
            enumeration(value: 1, cases: along, caseName: "leading")
        )
        row.alignment = .bottom
        column.alignment = .trailing
        XCTAssertEqual(
            try value("stackView.alignment", of: row.layer),
            enumeration(value: 4, cases: across, caseName: "bottom")
        )
        XCTAssertEqual(
            try value("stackView.alignment", of: column.layer),
            enumeration(value: 4, cases: along, caseName: "trailing")
        )
    }

    // MARK: - S-ATTR-04

    func test_S_ATTR_04_unrepresentableValuesBecomeStrings() throws {
        let window = try makeWindow()
        let layer = CALayer()
        let tile = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        layer.backgroundColor = UIColor(patternImage: tile).cgColor
        window.layer.addSublayer(layer)
        XCTAssertEqual(try value("layer.backgroundColor", of: layer), .string("pattern"))

        // A raw value without a name: a case of a later system, or a value that is not valid.
        XCTAssertEqual(AttributeOutputs.enumeration(99, names: AttributeOutputs.contentModeNames), .string("99"))
        XCTAssertEqual(AttributeOutputs.enumeration(-1, names: AttributeOutputs.axisNames), .string("-1"))
        XCTAssertEqual(
            AttributeOutputs.enumeration(1, names: AttributeOutputs.axisNames),
            enumeration(value: 1, cases: ["horizontal", "vertical"], caseName: "vertical")
        )
    }

    func test_S_ATTR_04_valuesAreNormalized() throws {
        // P-HIER-05: what is not finite is sent as 0. A layer outside any window, never shown.
        let layer = CALayer()
        layer.anchorPoint = CGPoint(x: CGFloat.nan, y: CGFloat.infinity)
        layer.opacity = .nan
        var transform = CATransform3DIdentity
        transform.m11 = .nan
        layer.transform = transform
        XCTAssertEqual(try value("layer.anchorPoint", of: layer), .point(WirePoint(x: 0, y: 0)))
        XCTAssertEqual(try value("layer.opacity", of: layer), .double(0))
        guard case .transform(let wire)? = try value("layer.transform", of: layer) else {
            return XCTFail("layer.transform is not a transform")
        }
        XCTAssertEqual(wire.m11, 0)
        XCTAssertEqual(AttributeOutputs.double(CGFloat.infinity), .double(0))
        XCTAssertEqual(
            AttributeOutputs.size(CGSize(width: CGFloat.nan, height: 2)),
            .size(WireSize(width: 0, height: 2))
        )

        // sRGB: colours outside its gamut are clipped, by Core Graphics.
        let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
        assertColor(AttributeOutputs.color(CGColor(colorSpace: displayP3, components: [1, 0, 0, 1])), 1, 0, 0)
        guard case .color(let wide, _)? = AttributeOutputs
            .color(UIColor(red: 1.5, green: -0.5, blue: 0.5, alpha: 1).cgColor)
        else { return XCTFail("an extended sRGB colour is not a colour") }
        for component in [wide.red, wide.green, wide.blue, wide.alpha] {
            XCTAssertTrue((0...1).contains(component), "\(wide)")
        }
        XCTAssertEqual(wide.red, 1)
        XCTAssertEqual(wide.green, 0)
        // Grey is converted too.
        assertColor(AttributeOutputs.color(UIColor(white: 1, alpha: 1).cgColor), 1, 1, 1)

        // A dynamic colour is read as the view shows it. A new appearance reaches the view's
        // traits when UIKit next lays it out.
        let window = try makeWindow()
        let label = UILabel()
        label.textColor = .label
        window.addSubview(label)
        label.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        assertColor(try value("label.textColor", of: label.layer), 1, 1, 1)
        label.overrideUserInterfaceStyle = .light
        window.layoutIfNeeded()
        assertColor(try value("label.textColor", of: label.layer), 0, 0, 0)
    }

    // MARK: - S-ATTR-05

    func test_S_ATTR_05_flagsMatchTheList() throws {
        var seen = Set<String>()
        for specimen in try specimens() {
            for group in AttributeCatalog.standard.read(specimen.layer) {
                let expected = try XCTUnwrap(ExpectedAttributes.groups[group.id], "unknown group \(group.id)")
                for (attribute, entry) in zip(group.attributes, expected.attributes) {
                    seen.insert(entry.id)
                    let name = "\(specimen.name): \(entry.id)"
                    // Also for a value that is nil.
                    XCTAssertEqual(attribute.valueKind, entry.kind, name)
                    XCTAssertEqual(attribute.editable, entry.editable, name)
                    XCTAssertEqual(attribute.acceptsNil, entry.acceptsNil, name)
                }
            }
        }
        XCTAssertEqual(seen.count, 68, "every attribute of the list was looked at")
    }

    func test_S_ATTR_08_sectionsMatchTheList() throws {
        var seen = Set<String>()
        for specimen in try specimens() {
            for attribute in AttributeCatalog.standard.read(specimen.layer).flatMap(\.attributes) {
                seen.insert(attribute.id)
                XCTAssertEqual(
                    attribute.section,
                    ExpectedAttributes.sections[attribute.id] ?? .general,
                    "\(specimen.name): \(attribute.id)"
                )
            }
        }
        XCTAssertEqual(seen.count, 68, "every attribute of the list was looked at")
        XCTAssertTrue(Set(ExpectedAttributes.sections.keys).isSubset(of: seen))
    }

    func test_S_ATTR_09_limitsMatchTheList() throws {
        var seen = Set<String>()
        for specimen in try specimens() {
            for attribute in AttributeCatalog.standard.read(specimen.layer).flatMap(\.attributes) {
                seen.insert(attribute.id)
                XCTAssertEqual(
                    attribute.limits,
                    ExpectedAttributes.limits[attribute.id] ?? [],
                    "\(specimen.name): \(attribute.id)"
                )
            }
        }
        XCTAssertEqual(seen.count, 68, "every attribute of the list was looked at")
        XCTAssertTrue(Set(ExpectedAttributes.limits.keys).isSubset(of: seen))
    }

    func test_S_ATTR_09_limitsHaveTheShapeOfTheProtocol() throws {
        // P-ATTR-09, 10, for every attribute of every kind of layer.
        let componentCounts: [AttributeValueKind: Int] = [
            .int: 1,
            .double: 1,
            .point: 2,
            .size: 2,
            .rect: 4,
            .insets: 4,
            .transform: 16
        ]
        for specimen in try specimens() {
            for attribute in AttributeCatalog.standard.read(specimen.layer).flatMap(\.attributes)
                where !attribute.limits.isEmpty {
                let name = "\(specimen.name): \(attribute.id)"
                XCTAssertTrue(attribute.editable, name)
                XCTAssertTrue(attribute.valueKind.isNumeric, name)
                let count = try XCTUnwrap(componentCounts[attribute.valueKind], name)
                XCTAssertTrue([1, count].contains(attribute.limits.count), name)
                for limit in attribute.limits {
                    let bounds = [limit.minimum, limit.maximum].compactMap { $0 }
                    XCTAssertTrue(bounds.allSatisfy(\.isFinite), name)
                    if attribute.valueKind == .int {
                        XCTAssertTrue(bounds.allSatisfy { $0.rounded() == $0 }, name)
                    }
                    if let minimum = limit.minimum, let maximum = limit.maximum {
                        let open = limit.minimumIsExclusive || limit.maximumIsExclusive
                        XCTAssertTrue(open ? minimum < maximum : minimum <= maximum, name)
                    }
                    XCTAssertFalse(limit.minimum == nil && limit.minimumIsExclusive, name)
                    XCTAssertFalse(limit.maximum == nil && limit.maximumIsExclusive, name)
                }
            }
        }
    }

    func test_S_ATTR_09_fallbackValuesHaveNoLimitsButKeepTheirSection() {
        // A number that cannot be read as one falls back to text (P-ATTR-03): read-only, so no
        // limits; it is still the same attribute, so the same section.
        let definition = AttributeCatalog.AttributeDefinition<CALayer>(
            "opacity",
            .double,
            section: .layout,
            limits: [NumberLimit(minimum: 0, maximum: 1)],
            write: .number(\.opacity)
        ) { _ in .string("odd") }
        let fallback = AttributeCatalog.attribute(
            id: "layer.opacity",
            title: "Opacity",
            value: .string("odd"),
            definition: definition
        )
        XCTAssertEqual(
            fallback,
            Attribute(
                id: "layer.opacity",
                title: "Opacity",
                value: .string("odd"),
                valueKind: .string,
                section: .layout
            )
        )
        // With a value of its kind: editable, with its limits.
        let read = AttributeCatalog.attribute(
            id: "layer.opacity",
            title: "Opacity",
            value: .double(0.5),
            definition: definition
        )
        XCTAssertEqual(read.limits, [NumberLimit(minimum: 0, maximum: 1)])
        XCTAssertEqual(read.section, .layout)
    }

    func test_S_ATTR_05_nilValuesKeepTheirKind() throws {
        let window = try makeWindow()
        let layer = CALayer()
        window.layer.addSublayer(layer)
        let background = try attribute("layer.backgroundColor", of: layer)
        XCTAssertNil(background.value)
        XCTAssertEqual(background.valueKind, .color)
        XCTAssertTrue(background.editable)
        XCTAssertTrue(background.acceptsNil)
        // Nil when read, but not to be set to nil. The layer holds its view weakly.
        let imageView = UIImageView()
        let image = try attribute("imageView.imageSize", of: imageView.layer)
        XCTAssertNil(image.value)
        XCTAssertEqual(image.valueKind, .size)
        XCTAssertFalse(image.editable)
        XCTAssertFalse(image.acceptsNil)
    }

    func test_S_ATTR_05_fallbackValuesAreReadOnly() throws {
        let window = try makeWindow()
        let layer = CALayer()
        let tile = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        layer.backgroundColor = UIColor(patternImage: tile).cgColor
        window.layer.addSublayer(layer)
        XCTAssertEqual(
            try attribute("layer.backgroundColor", of: layer),
            Attribute(
                id: "layer.backgroundColor",
                title: "Background Color",
                value: .string("pattern"),
                valueKind: .string,
                section: .general
            )
        )

        // An enumeration with a raw value that has no name.
        let definition = AttributeCatalog.AttributeDefinition<UIView>(
            "contentMode",
            .enumeration,
            write: .enumeration(\.contentMode)
        ) { _ in
            AttributeOutputs.enumeration(99, names: AttributeOutputs.contentModeNames)
        }
        XCTAssertEqual(
            AttributeCatalog.attribute(
                id: "view.contentMode",
                title: "Content Mode",
                value: .string("99"),
                definition: definition
            ),
            Attribute(
                id: "view.contentMode",
                title: "Content Mode",
                value: .string("99"),
                valueKind: .string,
                section: .general
            )
        )
        // The same definition with a value of its kind keeps its flags.
        XCTAssertEqual(
            AttributeCatalog.attribute(
                id: "view.contentMode",
                title: "Content Mode",
                value: AttributeOutputs.enumeration(2, names: AttributeOutputs.contentModeNames),
                definition: definition
            ).editable,
            true
        )
    }

    func test_S_ATTR_05_readOnlyAttributesDoNotAcceptNil() {
        // P-ATTR-06: accepts_nil means something only for what can be changed; it is sent false.
        let definition = AttributeCatalog.AttributeDefinition<CALayer>(
            "odd",
            .color,
            acceptsNil: true,
            write: nil
        ) { _ in nil }
        let attribute = AttributeCatalog.attribute(
            id: "layer.odd",
            title: "Odd",
            value: nil,
            definition: definition
        )
        XCTAssertFalse(attribute.editable)
        XCTAssertFalse(attribute.acceptsNil)
        XCTAssertEqual(attribute.valueKind, .color)
    }

    // MARK: - S-ATTR-06

    func test_S_ATTR_06_caseValuesAreRawValues() throws {
        func assertCases<T: RawRepresentable>(
            _ names: [String],
            _ cases: [(T, String)],
            line: UInt = #line
        ) where T.RawValue == Int {
            guard case let .enumeration(_, sent, _, values) = AttributeOutputs.enumeration(0, names: names)
            else { return XCTFail("not an enumeration", line: line) }
            XCTAssertEqual(sent, names, line: line)
            XCTAssertEqual(values.count, names.count, line: line)
            for (value, name) in cases {
                let index = try? XCTUnwrap(names.firstIndex(of: name), "no case \(name)", line: line)
                XCTAssertEqual(index.map { values[$0] }, Int64(value.rawValue), name, line: line)
            }
            XCTAssertEqual(cases.count, names.count, "every case was checked", line: line)
        }
        assertCases(
            AttributeOutputs.contentModeNames,
            [
                (UIView.ContentMode.scaleToFill, "scaleToFill"),
                (.scaleAspectFit, "scaleAspectFit"),
                (.scaleAspectFill, "scaleAspectFill"),
                (.redraw, "redraw"),
                (.center, "center"),
                (.top, "top"),
                (.bottom, "bottom"),
                (.left, "left"),
                (.right, "right"),
                (.topLeft, "topLeft"),
                (.topRight, "topRight"),
                (.bottomLeft, "bottomLeft"),
                (.bottomRight, "bottomRight")
            ]
        )
        assertCases(
            AttributeOutputs.textAlignmentNames,
            [
                (NSTextAlignment.left, "left"),
                (.center, "center"),
                (.right, "right"),
                (.justified, "justified"),
                (.natural, "natural")
            ]
        )
        assertCases(
            AttributeOutputs.lineBreakModeNames,
            [
                (NSLineBreakMode.byWordWrapping, "byWordWrapping"),
                (.byCharWrapping, "byCharWrapping"),
                (.byClipping, "byClipping"),
                (.byTruncatingHead, "byTruncatingHead"),
                (.byTruncatingTail, "byTruncatingTail"),
                (.byTruncatingMiddle, "byTruncatingMiddle")
            ]
        )
        assertCases(
            AttributeOutputs.axisNames,
            [(NSLayoutConstraint.Axis.horizontal, "horizontal"), (.vertical, "vertical")]
        )
        assertCases(
            AttributeOutputs.distributionNames,
            [
                (UIStackView.Distribution.fill, "fill"),
                (.fillEqually, "fillEqually"),
                (.fillProportionally, "fillProportionally"),
                (.equalSpacing, "equalSpacing"),
                (.equalCentering, "equalCentering")
            ]
        )
        for (axis, names) in [
            (NSLayoutConstraint.Axis.horizontal, AttributeOutputs.stackAlignmentNames(axis: .horizontal)),
            (.vertical, AttributeOutputs.stackAlignmentNames(axis: .vertical))
        ] {
            let cases: [(UIStackView.Alignment, String)] =
                axis == .horizontal
                    ? [
                        (.fill, "fill"),
                        (.top, "top"),
                        (.firstBaseline, "firstBaseline"),
                        (.center, "center"),
                        (.bottom, "bottom"),
                        (.lastBaseline, "lastBaseline")
                    ]
                    : [
                        (.fill, "fill"),
                        (.leading, "leading"),
                        (.firstBaseline, "firstBaseline"),
                        (.center, "center"),
                        (.trailing, "trailing"),
                        (.lastBaseline, "lastBaseline")
                    ]
            assertCases(names, cases)
        }
    }

    func test_S_ATTR_06_everyEnumerationOfTheCatalogHasCaseValues() throws {
        var checked = Set<String>()
        for specimen in try specimens() {
            for attribute in AttributeCatalog.standard.read(specimen.layer).flatMap(\.attributes) {
                guard case .enumeration(let value, let cases, let caseName, let caseValues)? = attribute.value
                else { continue }
                checked.insert(attribute.id)
                XCTAssertEqual(caseValues.count, cases.count, attribute.id)
                let index = try XCTUnwrap(caseValues.firstIndex(of: value), attribute.id)
                XCTAssertEqual(cases[index], caseName, attribute.id)
            }
        }
        XCTAssertEqual(
            checked,
            [
                "view.contentMode",
                "label.textAlignment",
                "label.lineBreakMode",
                "stackView.axis",
                "stackView.alignment",
                "stackView.distribution"
            ]
        )
    }

    func test_S_ATTR_04_colorChannelsAreClampedToTheUnitRange() {
        // P-ATTR-04, P-ATTR-05: the clamp is the server's own, whatever Core Graphics does.
        XCTAssertEqual(AttributeOutputs.channel(1.5), 1)
        XCTAssertEqual(AttributeOutputs.channel(-0.5), 0)
        XCTAssertEqual(AttributeOutputs.channel(.nan), 0)
        XCTAssertEqual(AttributeOutputs.channel(.infinity), 0)
        XCTAssertEqual(AttributeOutputs.channel(-.infinity), 0)
        XCTAssertEqual(AttributeOutputs.channel(0.25), 0.25)
        XCTAssertEqual(AttributeOutputs.channel(1), 1)
    }

    func test_S_ATTR_04_everyValueSurvivesTheWire() throws {
        let details = try specimens().enumerated().map { index, specimen in
            LayerDetail(
                layerID: UInt64(index + 1),
                status: .ok,
                attributeGroups: AttributeCatalog.standard.read(specimen.layer)
            )
        }
        let frame = Frame(
            requestID: 1,
            body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: details))
        )
        // Decoding verifies the buffer first; a member the schema does not have would fail it.
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
    }
}
