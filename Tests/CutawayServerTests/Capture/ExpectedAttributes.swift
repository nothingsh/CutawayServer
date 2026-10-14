import CutawayWire

/// The expected attributes and which of them can be changed, with where an inspector shows
/// them, their clusters and units (protocol 1.1), copied by hand for the tests. It does not
/// use AttributeCatalog: the tests compare the catalog against it.
enum ExpectedAttributes {
    struct Entry: Equatable {
        var id: String
        var title: String
        var kind: AttributeValueKind
        /// May read as nil.
        var nullable: Bool
        var editable: Bool
        /// May be set to nil.
        var acceptsNil: Bool
        var section: AttributeSection
        var cluster: String?
        var slot: String?
        var unit: AttributeUnit
        /// The layer's side of a pair (P-ATTR-11): only on a layer that backs no view.
        var onlyWithoutView: Bool
    }

    struct Group: Equatable {
        var id: String
        var title: String
        /// P-ATTR-16.
        var className: String
        var attributes: [Entry]

        /// The attributes a layer has: without the layer's side of the pairs when it backs a
        /// view.
        func attributes(backingView: Bool) -> [Entry] {
            backingView ? attributes.filter { !$0.onlyWithoutView } : attributes
        }
    }

    private static func entry(
        _ id: String,
        _ title: String,
        _ kind: AttributeValueKind,
        _ section: AttributeSection,
        _ cluster: (String, String)? = nil,
        unit: AttributeUnit = .unspecified,
        nullable: Bool = false,
        editable: Bool = true,
        acceptsNil: Bool = false,
        onlyWithoutView: Bool = false
    ) -> Entry {
        Entry(
            id: id,
            title: title,
            kind: kind,
            nullable: nullable,
            editable: editable,
            acceptsNil: acceptsNil,
            section: section,
            cluster: cluster?.0,
            slot: cluster?.1,
            unit: unit,
            onlyWithoutView: onlyWithoutView
        )
    }

    static let groups: [String: Group] = Dictionary(
        uniqueKeysWithValues: [
            layer,
            view,
            label,
            imageView,
            control,
            button,
            scrollView,
            stackView,
            textField,
            textView
        ]
        .map { ($0.id, $0) }
    )

    static let layer = Group(
        id: "layer",
        title: "Layer",
        className: "CALayer",
        attributes: [
            entry("layer.frame", "Frame", .rect, .layout, ("geometry", "frame"), unit: .points, editable: false),
            entry("layer.bounds", "Bounds", .rect, .layout, ("geometry", "bounds"), unit: .points),
            entry("layer.position", "Position", .point, .layout, ("geometry", "position"), unit: .points),
            entry("layer.anchorPoint", "Anchor Point", .point, .layout, ("geometry", "anchor")),
            entry("layer.zPosition", "Z Position", .double, .layout, ("geometry", "zPosition")),
            entry("layer.transform", "Transform", .transform, .layout, ("geometry", "transform")),
            entry("layer.hidden", "Hidden", .bool, .appearance, ("visibility", "hidden"), onlyWithoutView: true),
            entry(
                "layer.opacity",
                "Opacity",
                .double,
                .appearance,
                ("visibility", "opacity"),
                unit: .fraction,
                onlyWithoutView: true
            ),
            entry(
                "layer.masksToBounds",
                "Clips to Bounds",
                .bool,
                .appearance,
                ("corners", "clip"),
                onlyWithoutView: true
            ),
            entry("layer.cornerRadius", "Corner Radius", .double, .appearance, ("corners", "radius"), unit: .points),
            entry(
                "layer.backgroundColor",
                "Background",
                .color,
                .appearance,
                nullable: true,
                acceptsNil: true,
                onlyWithoutView: true
            ),
            entry("layer.borderWidth", "Border Width", .double, .appearance, ("border", "width"), unit: .points),
            entry(
                "layer.borderColor",
                "Border Color",
                .color,
                .appearance,
                ("border", "color"),
                nullable: true,
                acceptsNil: true
            ),
            entry(
                "layer.shadowColor",
                "Shadow Color",
                .color,
                .appearance,
                ("shadow", "color"),
                nullable: true,
                acceptsNil: true
            ),
            entry(
                "layer.shadowOpacity",
                "Shadow Opacity",
                .double,
                .appearance,
                ("shadow", "opacity"),
                unit: .fraction
            ),
            entry("layer.shadowRadius", "Shadow Radius", .double, .appearance, ("shadow", "radius"), unit: .points),
            entry("layer.shadowOffset", "Shadow Offset", .size, .appearance, ("shadow", "offset"), unit: .points)
        ]
    )

    static let view = Group(
        id: "view",
        title: "View",
        className: "UIView",
        attributes: [
            entry("view.alpha", "Opacity", .double, .appearance, ("visibility", "opacity"), unit: .fraction),
            entry("view.isHidden", "Hidden", .bool, .appearance, ("visibility", "hidden")),
            entry("view.isOpaque", "Opaque", .bool, .appearance),
            entry("view.clipsToBounds", "Clips to Bounds", .bool, .appearance, ("corners", "clip")),
            entry("view.isUserInteractionEnabled", "User Interaction", .bool, .behavior),
            entry("view.tag", "Tag", .int, .identity),
            entry("view.contentMode", "Content Mode", .enumeration, .appearance),
            entry("view.backgroundColor", "Background", .color, .appearance, nullable: true, acceptsNil: true),
            entry("view.tintColor", "Tint", .color, .appearance, nullable: true, acceptsNil: true),
            entry("view.layoutMargins", "Layout Margins", .insets, .layout, unit: .points),
            // v0.4 (S-ATTR-07).
            entry(
                "view.contentHuggingPriority.horizontal",
                "Hugging (Horizontal)",
                .double,
                .layout,
                ("sizing", "hugging.horizontal")
            ),
            entry(
                "view.contentHuggingPriority.vertical",
                "Hugging (Vertical)",
                .double,
                .layout,
                ("sizing", "hugging.vertical")
            ),
            entry(
                "view.contentCompressionResistancePriority.horizontal",
                "Compression Resistance (Horizontal)",
                .double,
                .layout,
                ("sizing", "compression.horizontal")
            ),
            entry(
                "view.contentCompressionResistancePriority.vertical",
                "Compression Resistance (Vertical)",
                .double,
                .layout,
                ("sizing", "compression.vertical")
            ),
            entry(
                "view.intrinsicContentSize.width",
                "Intrinsic Width",
                .double,
                .layout,
                ("sizing", "intrinsic.width"),
                unit: .points,
                nullable: true,
                editable: false
            ),
            entry(
                "view.intrinsicContentSize.height",
                "Intrinsic Height",
                .double,
                .layout,
                ("sizing", "intrinsic.height"),
                unit: .points,
                nullable: true,
                editable: false
            ),
            entry(
                "view.translatesAutoresizingMaskIntoConstraints",
                "Autoresizing Mask to Constraints",
                .bool,
                .layout,
                ("autoLayout", "autoresizing")
            ),
            entry(
                "view.hasAmbiguousLayout",
                "Ambiguous Layout",
                .bool,
                .layout,
                ("autoLayout", "ambiguous"),
                editable: false
            )
        ]
    )

    static let label = Group(
        id: "label",
        title: "Label",
        className: "UILabel",
        attributes: [
            entry("label.text", "Text", .string, .content, nullable: true, acceptsNil: true),
            entry("label.fontName", "Font", .string, .content, ("font", "name")),
            entry("label.fontSize", "Font Size", .double, .content, ("font", "size"), unit: .points),
            entry("label.textColor", "Text Color", .color, .content, nullable: true, acceptsNil: true),
            entry("label.textAlignment", "Text Alignment", .enumeration, .content),
            entry("label.numberOfLines", "Lines", .int, .content, ("lines", "count")),
            entry("label.lineBreakMode", "Line Break Mode", .enumeration, .content, ("lines", "lineBreak"))
        ]
    )

    static let imageView = Group(
        id: "imageView",
        title: "Image View",
        className: "UIImageView",
        attributes: [
            entry("imageView.imageSize", "Image Size", .size, .content, unit: .points, nullable: true, editable: false),
            entry("imageView.isHighlighted", "Highlighted", .bool, .content, ("state", "highlighted"))
        ]
    )

    static let control = Group(
        id: "control",
        title: "Control",
        className: "UIControl",
        attributes: [
            entry("control.isEnabled", "Enabled", .bool, .content, ("state", "enabled")),
            entry("control.isSelected", "Selected", .bool, .content, ("state", "selected")),
            entry("control.isHighlighted", "Highlighted", .bool, .content, ("state", "highlighted"))
        ]
    )

    static let button = Group(
        id: "button",
        title: "Button",
        className: "UIButton",
        attributes: [
            entry("button.currentTitle", "Title", .string, .content, nullable: true, acceptsNil: true),
            entry("button.currentTitleColor", "Title Color", .color, .content, nullable: true, acceptsNil: true)
        ]
    )

    static let scrollView = Group(
        id: "scrollView",
        title: "Scroll View",
        className: "UIScrollView",
        attributes: [
            entry("scrollView.contentOffset", "Content Offset", .point, .content, unit: .points),
            entry("scrollView.contentSize", "Content Size", .size, .content, unit: .points),
            entry("scrollView.contentInset", "Content Inset", .insets, .content, unit: .points),
            entry(
                "scrollView.adjustedContentInset",
                "Adjusted Content Inset",
                .insets,
                .content,
                unit: .points,
                editable: false
            ),
            entry("scrollView.isScrollEnabled", "Scrolling", .bool, .content, ("scrolling", "enabled")),
            entry("scrollView.isPagingEnabled", "Paging", .bool, .content, ("scrolling", "paging"))
        ]
    )

    static let stackView = Group(
        id: "stackView",
        title: "Stack View",
        className: "UIStackView",
        attributes: [
            entry("stackView.axis", "Axis", .enumeration, .content),
            entry("stackView.alignment", "Alignment", .enumeration, .content),
            entry("stackView.distribution", "Distribution", .enumeration, .content),
            entry("stackView.spacing", "Spacing", .double, .content, unit: .points)
        ]
    )

    static let textField = Group(
        id: "textField",
        title: "Text Field",
        className: "UITextField",
        attributes: [
            entry("textField.text", "Text", .string, .content, nullable: true, acceptsNil: true),
            entry("textField.placeholder", "Placeholder", .string, .content, nullable: true, acceptsNil: true),
            entry("textField.fontName", "Font", .string, .content, ("font", "name"), nullable: true),
            entry(
                "textField.fontSize",
                "Font Size",
                .double,
                .content,
                ("font", "size"),
                unit: .points,
                nullable: true
            ),
            entry("textField.textColor", "Text Color", .color, .content, nullable: true, acceptsNil: true)
        ]
    )

    static let textView = Group(
        id: "textView",
        title: "Text View",
        className: "UITextView",
        attributes: [
            entry("textView.text", "Text", .string, .content),
            entry("textView.fontName", "Font", .string, .content, ("font", "name"), nullable: true),
            entry("textView.fontSize", "Font Size", .double, .content, ("font", "size"), unit: .points, nullable: true),
            entry("textView.textColor", "Text Color", .color, .content, nullable: true, acceptsNil: true),
            entry("textView.isEditable", "Editable", .bool, .content)
        ]
    )

    // MARK: - Protocol 1.1

    /// The limits, copied by hand (S-ATTR-09): the rules that refuse numbers. Every attribute
    /// not named here has none.
    static let limits: [String: [NumberLimit]] = {
        let atLeastZero = [NumberLimit(minimum: 0)]
        let unit = [NumberLimit(minimum: 0, maximum: 1)]
        let priority = [NumberLimit(minimum: 1, maximum: 1000)]
        let positive = [NumberLimit(minimum: 0, minimumIsExclusive: true)]
        return [
            "layer.bounds": [.free, .free, NumberLimit(minimum: 0), NumberLimit(minimum: 0)],
            "layer.opacity": unit,
            "layer.shadowOpacity": unit,
            "view.alpha": unit,
            "layer.cornerRadius": atLeastZero,
            "layer.borderWidth": atLeastZero,
            "layer.shadowRadius": atLeastZero,
            "view.contentHuggingPriority.horizontal": priority,
            "view.contentHuggingPriority.vertical": priority,
            "view.contentCompressionResistancePriority.horizontal": priority,
            "view.contentCompressionResistancePriority.vertical": priority,
            "label.fontSize": positive,
            "textField.fontSize": positive,
            "textView.fontSize": positive,
            "label.numberOfLines": atLeastZero,
            "scrollView.contentSize": atLeastZero
        ]
    }()
}
