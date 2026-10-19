import CutawayWire
import Foundation

// The attribute list the probe checks a server against, copied by hand.
extension AttributeChecks {
    struct Entry: Equatable {
        /// The part of the id after the group's id and the dot.
        var name: String
        var kind: AttributeValueKind
        /// May read as nil.
        var nullable: Bool
        var editable: Bool
        /// May be set to nil.
        var acceptsNil: Bool
        /// Protocol 1.1: the title, the section, the cluster and slot, and the unit.
        var title: String
        var section: AttributeSection
        var cluster: String?
        var slot: String?
        var unit: AttributeUnit
        /// The layer's side of a pair (P-ATTR-11): only on a layer that backs no view.
        var onlyWithoutView: Bool
    }

    /// The expected attributes and which of them can be changed, copied by hand: the probe
    /// checks the server against it and does not share code with the server.
    static let list: [String: [Entry]] = {
        func entry(
            _ name: String,
            _ kind: AttributeValueKind,
            _ title: String,
            _ section: AttributeSection,
            _ cluster: (String, String)? = nil,
            unit: AttributeUnit = .unspecified,
            nullable: Bool = false,
            editable: Bool = true,
            acceptsNil: Bool = false,
            onlyWithoutView: Bool = false
        ) -> Entry {
            Entry(
                name: name,
                kind: kind,
                nullable: nullable,
                editable: editable,
                acceptsNil: acceptsNil,
                title: title,
                section: section,
                cluster: cluster?.0,
                slot: cluster?.1,
                unit: unit,
                onlyWithoutView: onlyWithoutView
            )
        }
        // Protocol 1.2: shared by several groups (S-ATTR-19 to 21).
        func fonts(nullable: Bool) -> [Entry] {
            [
                entry("fontDescription", .string, "Font Description", .content, nullable: nullable, editable: false),
                entry(
                    "fontTextStyle",
                    .string,
                    "Text Style",
                    .content,
                    ("font", "textStyle"),
                    nullable: true,
                    editable: false
                ),
                entry(
                    "adjustsFontForContentSizeCategory",
                    .bool,
                    "Adjusts to Text Size",
                    .content,
                    ("font", "scalable")
                )
            ]
        }
        let image = [
            entry("imageName", .string, "Image", .content, ("image", "name"), nullable: true, editable: false),
            entry(
                "imageSize",
                .size,
                "Image Size",
                .content,
                ("image", "size"),
                unit: .points,
                nullable: true,
                editable: false
            ),
            entry("imageScale", .double, "Image Scale", .content, ("image", "scale"), nullable: true, editable: false),
            entry(
                "imageRenderingMode",
                .enumeration,
                "Rendering Mode",
                .content,
                ("image", "renderingMode"),
                nullable: true,
                editable: false
            ),
            entry(
                "symbolConfiguration",
                .string,
                "Symbol Configuration",
                .content,
                ("image", "symbolConfiguration"),
                nullable: true,
                editable: false
            )
        ]
        // A collection view's counts are nil while it needs layout.
        func list(items: String, title: String, perSection: String, countsMayBeNil: Bool) -> [Entry] {
            [
                entry("dataSource", .layerReference, "Data Source", .content, nullable: true, editable: false),
                entry(
                    "numberOfSections",
                    .int,
                    "Sections",
                    .content,
                    ("listCounts", "sections"),
                    nullable: countsMayBeNil,
                    editable: false
                ),
                entry(items, .int, title, .content, ("listCounts", "items"), nullable: countsMayBeNil, editable: false),
                entry(perSection, .string, "\(title) per Section", .content, nullable: countsMayBeNil, editable: false),
                entry("visibleIndexPaths", .string, "Visible \(title)", .content, editable: false)
            ]
        }
        func cell(item: String, title: String) -> [Entry] {
            [
                entry("section", .int, "Section", .content, ("indexPath", "section"), nullable: true, editable: false),
                entry(item, .int, title, .content, ("indexPath", "item"), nullable: true, editable: false),
                entry("reuseIdentifier", .string, "Reuse Identifier", .identity, nullable: true, editable: false)
            ]
        }
        return [
            "layer": [
                entry("frame", .rect, "Frame", .layout, ("geometry", "frame"), unit: .points, editable: false),
                entry("bounds", .rect, "Bounds", .layout, ("geometry", "bounds"), unit: .points),
                entry("position", .point, "Position", .layout, ("geometry", "position"), unit: .points),
                entry("anchorPoint", .point, "Anchor Point", .layout, ("geometry", "anchor")),
                entry("zPosition", .double, "Z Position", .layout, ("geometry", "zPosition")),
                entry("transform", .transform, "Transform", .layout, ("geometry", "transform")),
                entry("hidden", .bool, "Hidden", .appearance, ("visibility", "hidden"), onlyWithoutView: true),
                entry(
                    "opacity",
                    .double,
                    "Opacity",
                    .appearance,
                    ("visibility", "opacity"),
                    unit: .fraction,
                    onlyWithoutView: true
                ),
                entry(
                    "masksToBounds",
                    .bool,
                    "Clips to Bounds",
                    .appearance,
                    ("corners", "clip"),
                    onlyWithoutView: true
                ),
                entry("cornerRadius", .double, "Corner Radius", .appearance, ("corners", "radius"), unit: .points),
                entry(
                    "backgroundColor",
                    .color,
                    "Background",
                    .appearance,
                    nullable: true,
                    acceptsNil: true,
                    onlyWithoutView: true
                ),
                entry("borderWidth", .double, "Border Width", .appearance, ("border", "width"), unit: .points),
                entry(
                    "borderColor",
                    .color,
                    "Border Color",
                    .appearance,
                    ("border", "color"),
                    nullable: true,
                    acceptsNil: true
                ),
                entry(
                    "shadowColor",
                    .color,
                    "Shadow Color",
                    .appearance,
                    ("shadow", "color"),
                    nullable: true,
                    acceptsNil: true
                ),
                entry("shadowOpacity", .double, "Shadow Opacity", .appearance, ("shadow", "opacity"), unit: .fraction),
                entry("shadowRadius", .double, "Shadow Radius", .appearance, ("shadow", "radius"), unit: .points),
                entry("shadowOffset", .size, "Shadow Offset", .appearance, ("shadow", "offset"), unit: .points)
            ],
            "view": [
                entry("alpha", .double, "Opacity", .appearance, ("visibility", "opacity"), unit: .fraction),
                entry("isHidden", .bool, "Hidden", .appearance, ("visibility", "hidden")),
                entry("isOpaque", .bool, "Opaque", .appearance),
                entry("clipsToBounds", .bool, "Clips to Bounds", .appearance, ("corners", "clip")),
                entry("isUserInteractionEnabled", .bool, "User Interaction", .behavior),
                entry("tag", .int, "Tag", .identity),
                entry("contentMode", .enumeration, "Content Mode", .appearance),
                entry("backgroundColor", .color, "Background", .appearance, nullable: true, acceptsNil: true),
                entry("tintColor", .color, "Tint", .appearance, nullable: true, acceptsNil: true),
                entry("layoutMargins", .insets, "Layout Margins", .layout, unit: .points),
                entry(
                    "contentHuggingPriority.horizontal",
                    .double,
                    "Hugging (Horizontal)",
                    .layout,
                    ("sizing", "hugging.horizontal")
                ),
                entry(
                    "contentHuggingPriority.vertical",
                    .double,
                    "Hugging (Vertical)",
                    .layout,
                    ("sizing", "hugging.vertical")
                ),
                entry(
                    "contentCompressionResistancePriority.horizontal",
                    .double,
                    "Compression Resistance (Horizontal)",
                    .layout,
                    ("sizing", "compression.horizontal")
                ),
                entry(
                    "contentCompressionResistancePriority.vertical",
                    .double,
                    "Compression Resistance (Vertical)",
                    .layout,
                    ("sizing", "compression.vertical")
                ),
                entry(
                    "intrinsicContentSize.width",
                    .double,
                    "Intrinsic Width",
                    .layout,
                    ("sizing", "intrinsic.width"),
                    unit: .points,
                    nullable: true,
                    editable: false
                ),
                entry(
                    "intrinsicContentSize.height",
                    .double,
                    "Intrinsic Height",
                    .layout,
                    ("sizing", "intrinsic.height"),
                    unit: .points,
                    nullable: true,
                    editable: false
                ),
                entry(
                    "translatesAutoresizingMaskIntoConstraints",
                    .bool,
                    "Autoresizing Mask to Constraints",
                    .layout,
                    ("autoLayout", "autoresizing")
                ),
                entry(
                    "hasAmbiguousLayout",
                    .bool,
                    "Ambiguous Layout",
                    .layout,
                    ("autoLayout", "ambiguous"),
                    editable: false
                ),
                entry("accessibilityLabel", .string, "Label", .accessibility, nullable: true, acceptsNil: true),
                entry("accessibilityHint", .string, "Hint", .accessibility, nullable: true, acceptsNil: true),
                entry("accessibilityValue", .string, "Value", .accessibility, nullable: true, acceptsNil: true),
                entry(
                    "accessibilityIdentifier",
                    .string,
                    "Identifier",
                    .accessibility,
                    nullable: true,
                    acceptsNil: true
                ),
                entry("isAccessibilityElement", .bool, "Accessibility Element", .accessibility),
                entry("accessibilityTraits", .string, "Traits", .accessibility, editable: false)
            ],
            "label": [
                entry("text", .string, "Text", .content, nullable: true, acceptsNil: true),
                entry("fontName", .string, "Font", .content, ("font", "name")),
                entry("fontSize", .double, "Font Size", .content, ("font", "size"), unit: .points)
            ] + fonts(nullable: false) + [
                entry("textColor", .color, "Text Color", .content, nullable: true, acceptsNil: true),
                entry("textAlignment", .enumeration, "Text Alignment", .content),
                entry("numberOfLines", .int, "Lines", .content, ("lines", "count")),
                entry("lineBreakMode", .enumeration, "Line Break Mode", .content, ("lines", "lineBreak")),
                entry(
                    "drawnLineCount",
                    .int,
                    "Drawn Lines",
                    .content,
                    ("lines", "drawn"),
                    nullable: true,
                    editable: false
                ),
                entry(
                    "isTruncated",
                    .bool,
                    "Truncated",
                    .content,
                    ("lines", "truncated"),
                    nullable: true,
                    editable: false
                )
            ],
            "imageView": image + [
                entry("isHighlighted", .bool, "Highlighted", .content, ("state", "highlighted"))
            ],
            "control": [
                entry("isEnabled", .bool, "Enabled", .content, ("state", "enabled")),
                entry("isSelected", .bool, "Selected", .content, ("state", "selected")),
                entry("isHighlighted", .bool, "Highlighted", .content, ("state", "highlighted"))
            ],
            "button": [
                entry("currentTitle", .string, "Title", .content, nullable: true, acceptsNil: true),
                entry("currentTitleColor", .color, "Title Color", .content, nullable: true, acceptsNil: true)
            ] + image,
            "scrollView": [
                entry("contentOffset", .point, "Content Offset", .content, unit: .points),
                entry("contentSize", .size, "Content Size", .content, unit: .points),
                entry("contentInset", .insets, "Content Inset", .content, unit: .points),
                entry(
                    "adjustedContentInset",
                    .insets,
                    "Adjusted Content Inset",
                    .content,
                    unit: .points,
                    editable: false
                ),
                entry("isScrollEnabled", .bool, "Scrolling", .content, ("scrolling", "enabled")),
                entry("isPagingEnabled", .bool, "Paging", .content, ("scrolling", "paging")),
                entry("delegate", .layerReference, "Delegate", .content, nullable: true, editable: false)
            ],
            "tableView": list(
                items: "numberOfRows",
                title: "Rows",
                perSection: "rowsPerSection",
                countsMayBeNil: false
            ),
            "collectionView": list(
                items: "numberOfItems",
                title: "Items",
                perSection: "itemsPerSection",
                countsMayBeNil: true
            ),
            "tableViewCell": cell(item: "row", title: "Row"),
            "collectionViewCell": cell(item: "item", title: "Item"),
            "stackView": [
                entry("axis", .enumeration, "Axis", .content),
                entry("alignment", .enumeration, "Alignment", .content),
                entry("distribution", .enumeration, "Distribution", .content),
                entry("spacing", .double, "Spacing", .content, unit: .points),
                entry("arrangedSubviews", .layerReference, "Arranged Subviews", .content, editable: false),
                entry("customSpacing", .string, "Custom Spacing", .content, nullable: true, editable: false)
            ],
            "textField": [
                entry("text", .string, "Text", .content, nullable: true, acceptsNil: true),
                entry("placeholder", .string, "Placeholder", .content, nullable: true, acceptsNil: true),
                entry("fontName", .string, "Font", .content, ("font", "name"), nullable: true),
                entry("fontSize", .double, "Font Size", .content, ("font", "size"), unit: .points, nullable: true)
            ] + fonts(nullable: true) + [
                entry("textColor", .color, "Text Color", .content, nullable: true, acceptsNil: true)
            ],
            "textView": [
                entry("text", .string, "Text", .content),
                entry("fontName", .string, "Font", .content, ("font", "name"), nullable: true),
                entry("fontSize", .double, "Font Size", .content, ("font", "size"), unit: .points, nullable: true)
            ] + fonts(nullable: true) + [
                entry("textColor", .color, "Text Color", .content, nullable: true, acceptsNil: true),
                entry("isEditable", .bool, "Editable", .content)
            ]
        ]
    }()

    /// The class that declares each group's properties (P-ATTR-16), copied by hand like `list`.
    static let classNames: [String: String] = [
        "layer": "CALayer",
        "view": "UIView",
        "label": "UILabel",
        "imageView": "UIImageView",
        "control": "UIControl",
        "button": "UIButton",
        "scrollView": "UIScrollView",
        "tableView": "UITableView",
        "collectionView": "UICollectionView",
        "tableViewCell": "UITableViewCell",
        "collectionViewCell": "UICollectionViewCell",
        "stackView": "UIStackView",
        "textField": "UITextField",
        "textView": "UITextView"
    ]

    /// The limits, copied by hand like `list` (protocol 1.1, P-ATTR-09); none for every other
    /// attribute.
    static let limits: [String: [NumberLimit]] = {
        let atLeastZero = [NumberLimit(minimum: 0)]
        let unit = [NumberLimit(minimum: 0, maximum: 1)]
        let priority = [NumberLimit(minimum: 1, maximum: 1000)]
        let positive = [NumberLimit(minimum: 0, minimumIsExclusive: true)]
        var limits: [String: [NumberLimit]] = [
            "layer.bounds": [.free, .free, NumberLimit(minimum: 0), NumberLimit(minimum: 0)],
            "label.numberOfLines": atLeastZero,
            "scrollView.contentSize": atLeastZero
        ]
        for id in ["layer.opacity", "layer.shadowOpacity", "view.alpha"] { limits[id] = unit }
        for id in ["layer.cornerRadius", "layer.borderWidth", "layer.shadowRadius"] { limits[id] = atLeastZero }
        for id in ["label.fontSize", "textField.fontSize", "textView.fontSize"] { limits[id] = positive }
        for axis in ["horizontal", "vertical"] {
            limits["view.contentHuggingPriority.\(axis)"] = priority
            limits["view.contentCompressionResistancePriority.\(axis)"] = priority
        }
        return limits
    }()
}
