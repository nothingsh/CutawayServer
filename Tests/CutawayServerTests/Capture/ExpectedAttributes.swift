import CutawayWire

/// The expected attributes and which of them can be changed,
/// copied by hand for the tests. It does not use AttributeCatalog: the tests compare the
/// catalog against it.
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
    }

    struct Group: Equatable {
        var id: String
        var title: String
        var attributes: [Entry]
    }

    private static func entry(
        _ id: String,
        _ title: String,
        _ kind: AttributeValueKind,
        nullable: Bool = false,
        editable: Bool = true,
        acceptsNil: Bool = false
    ) -> Entry {
        Entry(
            id: id,
            title: title,
            kind: kind,
            nullable: nullable,
            editable: editable,
            acceptsNil: acceptsNil
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
        attributes: [
            entry("layer.frame", "Frame", .rect, editable: false),
            entry("layer.bounds", "Bounds", .rect),
            entry("layer.position", "Position", .point),
            entry("layer.anchorPoint", "Anchor Point", .point),
            entry("layer.zPosition", "Z Position", .double),
            entry("layer.transform", "Transform", .transform),
            entry("layer.hidden", "Hidden", .bool),
            entry("layer.opacity", "Opacity", .double),
            entry("layer.masksToBounds", "Masks To Bounds", .bool),
            entry("layer.cornerRadius", "Corner Radius", .double),
            entry("layer.backgroundColor", "Background Color", .color, nullable: true, acceptsNil: true),
            entry("layer.borderWidth", "Border Width", .double),
            entry("layer.borderColor", "Border Color", .color, nullable: true, acceptsNil: true),
            entry("layer.shadowColor", "Shadow Color", .color, nullable: true, acceptsNil: true),
            entry("layer.shadowOpacity", "Shadow Opacity", .double),
            entry("layer.shadowRadius", "Shadow Radius", .double),
            entry("layer.shadowOffset", "Shadow Offset", .size)
        ]
    )

    static let view = Group(
        id: "view",
        title: "View",
        attributes: [
            entry("view.alpha", "Alpha", .double),
            entry("view.isHidden", "Is Hidden", .bool),
            entry("view.isOpaque", "Is Opaque", .bool),
            entry("view.clipsToBounds", "Clips To Bounds", .bool),
            entry("view.isUserInteractionEnabled", "Is User Interaction Enabled", .bool),
            entry("view.tag", "Tag", .int),
            entry("view.contentMode", "Content Mode", .enumeration),
            entry("view.tintColor", "Tint Color", .color, nullable: true, acceptsNil: true),
            entry("view.layoutMargins", "Layout Margins", .insets),
            // v0.4 (S-ATTR-07).
            entry("view.contentHuggingPriority.horizontal", "Content Hugging Priority Horizontal", .double),
            entry("view.contentHuggingPriority.vertical", "Content Hugging Priority Vertical", .double),
            entry(
                "view.contentCompressionResistancePriority.horizontal",
                "Content Compression Resistance Priority Horizontal",
                .double
            ),
            entry(
                "view.contentCompressionResistancePriority.vertical",
                "Content Compression Resistance Priority Vertical",
                .double
            ),
            entry(
                "view.intrinsicContentSize.width",
                "Intrinsic Content Size Width",
                .double,
                nullable: true,
                editable: false
            ),
            entry(
                "view.intrinsicContentSize.height",
                "Intrinsic Content Size Height",
                .double,
                nullable: true,
                editable: false
            ),
            entry(
                "view.translatesAutoresizingMaskIntoConstraints",
                "Translates Autoresizing Mask Into Constraints",
                .bool
            ),
            entry("view.hasAmbiguousLayout", "Has Ambiguous Layout", .bool, editable: false)
        ]
    )

    static let label = Group(
        id: "label",
        title: "Label",
        attributes: [
            entry("label.text", "Text", .string, nullable: true, acceptsNil: true),
            entry("label.fontName", "Font Name", .string),
            entry("label.fontSize", "Font Size", .double),
            entry("label.textColor", "Text Color", .color, nullable: true, acceptsNil: true),
            entry("label.textAlignment", "Text Alignment", .enumeration),
            entry("label.numberOfLines", "Number Of Lines", .int),
            entry("label.lineBreakMode", "Line Break Mode", .enumeration)
        ]
    )

    static let imageView = Group(
        id: "imageView",
        title: "Image View",
        attributes: [
            entry("imageView.imageSize", "Image Size", .size, nullable: true, editable: false),
            entry("imageView.isHighlighted", "Is Highlighted", .bool)
        ]
    )

    static let control = Group(
        id: "control",
        title: "Control",
        attributes: [
            entry("control.isEnabled", "Is Enabled", .bool),
            entry("control.isSelected", "Is Selected", .bool),
            entry("control.isHighlighted", "Is Highlighted", .bool)
        ]
    )

    static let button = Group(
        id: "button",
        title: "Button",
        attributes: [
            entry("button.currentTitle", "Current Title", .string, nullable: true, acceptsNil: true),
            entry("button.currentTitleColor", "Current Title Color", .color, nullable: true, acceptsNil: true)
        ]
    )

    static let scrollView = Group(
        id: "scrollView",
        title: "Scroll View",
        attributes: [
            entry("scrollView.contentOffset", "Content Offset", .point),
            entry("scrollView.contentSize", "Content Size", .size),
            entry("scrollView.contentInset", "Content Inset", .insets),
            entry("scrollView.adjustedContentInset", "Adjusted Content Inset", .insets, editable: false),
            entry("scrollView.isScrollEnabled", "Is Scroll Enabled", .bool),
            entry("scrollView.isPagingEnabled", "Is Paging Enabled", .bool)
        ]
    )

    static let stackView = Group(
        id: "stackView",
        title: "Stack View",
        attributes: [
            entry("stackView.axis", "Axis", .enumeration),
            entry("stackView.alignment", "Alignment", .enumeration),
            entry("stackView.distribution", "Distribution", .enumeration),
            entry("stackView.spacing", "Spacing", .double)
        ]
    )

    static let textField = Group(
        id: "textField",
        title: "Text Field",
        attributes: [
            entry("textField.text", "Text", .string, nullable: true, acceptsNil: true),
            entry("textField.placeholder", "Placeholder", .string, nullable: true, acceptsNil: true),
            entry("textField.fontName", "Font Name", .string, nullable: true),
            entry("textField.fontSize", "Font Size", .double, nullable: true),
            entry("textField.textColor", "Text Color", .color, nullable: true, acceptsNil: true)
        ]
    )

    static let textView = Group(
        id: "textView",
        title: "Text View",
        attributes: [
            entry("textView.text", "Text", .string),
            entry("textView.fontName", "Font Name", .string, nullable: true),
            entry("textView.fontSize", "Font Size", .double, nullable: true),
            entry("textView.textColor", "Text Color", .color, nullable: true, acceptsNil: true),
            entry("textView.isEditable", "Is Editable", .bool)
        ]
    )

    // MARK: - Protocol 1.1

    /// The sections other than `general`, copied by hand (S-ATTR-08). Every attribute not
    /// named here is `general`.
    static let sections: [String: AttributeSection] = {
        var sections: [String: AttributeSection] = ["view.tag": .identity]
        for id in [
            "layer.frame",
            "layer.bounds",
            "layer.position",
            "layer.anchorPoint",
            "layer.zPosition",
            "layer.transform",
            "view.layoutMargins",
            "view.contentHuggingPriority.horizontal",
            "view.contentHuggingPriority.vertical",
            "view.contentCompressionResistancePriority.horizontal",
            "view.contentCompressionResistancePriority.vertical",
            "view.intrinsicContentSize.width",
            "view.intrinsicContentSize.height",
            "view.translatesAutoresizingMaskIntoConstraints",
            "view.hasAmbiguousLayout",
            "scrollView.contentOffset",
            "scrollView.contentSize",
            "scrollView.contentInset",
            "scrollView.adjustedContentInset",
            "stackView.axis",
            "stackView.alignment",
            "stackView.distribution",
            "stackView.spacing"
        ] {
            sections[id] = .layout
        }
        return sections
    }()

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
