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
            textView,
            tableView,
            collectionView,
            tableViewCell,
            collectionViewCell
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
            ),
            // v1.2 (S-ATTR-16).
            entry("view.accessibilityLabel", "Label", .string, .accessibility, nullable: true, acceptsNil: true),
            entry("view.accessibilityHint", "Hint", .string, .accessibility, nullable: true, acceptsNil: true),
            entry("view.accessibilityValue", "Value", .string, .accessibility, nullable: true, acceptsNil: true),
            entry(
                "view.accessibilityIdentifier",
                "Identifier",
                .string,
                .accessibility,
                nullable: true,
                acceptsNil: true
            ),
            entry("view.isAccessibilityElement", "Accessibility Element", .bool, .accessibility),
            entry("view.accessibilityTraits", "Traits", .string, .accessibility, editable: false)
        ]
    )

    static let label = Group(
        id: "label",
        title: "Label",
        className: "UILabel",
        attributes: [
            entry("label.text", "Text", .string, .content, nullable: true, acceptsNil: true),
            entry("label.fontName", "Font", .string, .content, ("font", "name")),
            entry("label.fontSize", "Font Size", .double, .content, ("font", "size"), unit: .points)
        ] + fontEntries("label", nullable: false) + [
            entry("label.textColor", "Text Color", .color, .content, nullable: true, acceptsNil: true),
            entry("label.textAlignment", "Text Alignment", .enumeration, .content),
            entry("label.numberOfLines", "Lines", .int, .content, ("lines", "count")),
            entry("label.lineBreakMode", "Line Break Mode", .enumeration, .content, ("lines", "lineBreak")),
            // v1.2 (S-ATTR-22).
            entry(
                "label.drawnLineCount",
                "Drawn Lines",
                .int,
                .content,
                ("lines", "drawn"),
                nullable: true,
                editable: false
            ),
            entry(
                "label.isTruncated",
                "Truncated",
                .bool,
                .content,
                ("lines", "truncated"),
                nullable: true,
                editable: false
            )
        ]
    )

    static let imageView = Group(
        id: "imageView",
        title: "Image View",
        className: "UIImageView",
        attributes: imageEntries("imageView") + [
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
        ] + imageEntries("button")
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
            entry("scrollView.isPagingEnabled", "Paging", .bool, .content, ("scrolling", "paging")),
            // v1.2 (S-ATTR-18).
            entry("scrollView.delegate", "Delegate", .layerReference, .content, nullable: true, editable: false)
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
            entry("stackView.spacing", "Spacing", .double, .content, unit: .points),
            // v1.2 (S-ATTR-18, 19).
            entry("stackView.arrangedSubviews", "Arranged Subviews", .layerReference, .content, editable: false),
            entry("stackView.customSpacing", "Custom Spacing", .string, .content, nullable: true, editable: false)
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
            )
        ] + fontEntries("textField", nullable: true) + [
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
            entry("textView.fontSize", "Font Size", .double, .content, ("font", "size"), unit: .points, nullable: true)
        ] + fontEntries("textView", nullable: true) + [
            entry("textView.textColor", "Text Color", .color, .content, nullable: true, acceptsNil: true),
            entry("textView.isEditable", "Editable", .bool, .content)
        ]
    )

    // MARK: - Protocol 1.2

    /// S-ATTR-21: the font of a label, a text field or a text view.
    private static func fontEntries(_ group: String, nullable: Bool) -> [Entry] {
        [
            entry(
                "\(group).fontDescription",
                "Font Description",
                .string,
                .content,
                nullable: nullable,
                editable: false
            ),
            entry(
                "\(group).fontTextStyle",
                "Text Style",
                .string,
                .content,
                ("font", "textStyle"),
                nullable: true,
                editable: false
            ),
            entry(
                "\(group).adjustsFontForContentSizeCategory",
                "Adjusts to Text Size",
                .bool,
                .content,
                ("font", "scalable")
            )
        ]
    }

    /// S-ATTR-20: the image of an image view, or the current image of a button.
    private static func imageEntries(_ group: String) -> [Entry] {
        [
            entry("\(group).imageName", "Image", .string, .content, ("image", "name"), nullable: true, editable: false),
            entry(
                "\(group).imageSize",
                "Image Size",
                .size,
                .content,
                ("image", "size"),
                unit: .points,
                nullable: true,
                editable: false
            ),
            entry(
                "\(group).imageScale",
                "Image Scale",
                .double,
                .content,
                ("image", "scale"),
                nullable: true,
                editable: false
            ),
            entry(
                "\(group).imageRenderingMode",
                "Rendering Mode",
                .enumeration,
                .content,
                ("image", "renderingMode"),
                nullable: true,
                editable: false
            ),
            entry(
                "\(group).symbolConfiguration",
                "Symbol Configuration",
                .string,
                .content,
                ("image", "symbolConfiguration"),
                nullable: true,
                editable: false
            )
        ]
    }

    /// S-ATTR-19. A table answers its counts from what it has; a collection view only once it
    /// is laid out (S-D-184), so they may be nil.
    static let tableView = Group(
        id: "tableView",
        title: "Table View",
        className: "UITableView",
        attributes: listEntries(
            "tableView",
            item: "Rows",
            items: "numberOfRows",
            perSection: "rowsPerSection",
            countsMayBeNil: false
        )
    )

    static let collectionView = Group(
        id: "collectionView",
        title: "Collection View",
        className: "UICollectionView",
        attributes: listEntries(
            "collectionView",
            item: "Items",
            items: "numberOfItems",
            perSection: "itemsPerSection",
            countsMayBeNil: true
        )
    )

    private static func listEntries(
        _ group: String,
        item: String,
        items: String,
        perSection: String,
        countsMayBeNil: Bool
    ) -> [Entry] {
        [
            entry("\(group).dataSource", "Data Source", .layerReference, .content, nullable: true, editable: false),
            entry(
                "\(group).numberOfSections",
                "Sections",
                .int,
                .content,
                ("listCounts", "sections"),
                nullable: countsMayBeNil,
                editable: false
            ),
            entry(
                "\(group).\(items)",
                item,
                .int,
                .content,
                ("listCounts", "items"),
                nullable: countsMayBeNil,
                editable: false
            ),
            entry(
                "\(group).\(perSection)",
                "\(item) per Section",
                .string,
                .content,
                nullable: countsMayBeNil,
                editable: false
            ),
            entry("\(group).visibleIndexPaths", "Visible \(item)", .string, .content, editable: false)
        ]
    }

    static let tableViewCell = Group(
        id: "tableViewCell",
        title: "Table View Cell",
        className: "UITableViewCell",
        attributes: cellEntries("tableViewCell", item: "row", title: "Row")
    )

    static let collectionViewCell = Group(
        id: "collectionViewCell",
        title: "Collection View Cell",
        className: "UICollectionViewCell",
        attributes: cellEntries("collectionViewCell", item: "item", title: "Item")
    )

    private static func cellEntries(_ group: String, item: String, title: String) -> [Entry] {
        [
            entry(
                "\(group).section",
                "Section",
                .int,
                .content,
                ("indexPath", "section"),
                nullable: true,
                editable: false
            ),
            entry("\(group).\(item)", title, .int, .content, ("indexPath", "item"), nullable: true, editable: false),
            entry("\(group).reuseIdentifier", "Reuse Identifier", .string, .identity, nullable: true, editable: false)
        ]
    }

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
