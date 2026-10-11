#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The attributes of a layer, by group, with what a client may change.
///
/// Reading only reads: no layout is forced and nothing is changed. Writing is
/// `AttributeEditing`'s, with the writers declared here. Group and attribute IDs are stable
/// (PROTOCOL.md, P-ATTR-01); titles are for display.
///
/// A catalog is a value made of groups: `standard` holds the built-in groups, and another
/// catalog can be made of more.
@MainActor
struct AttributeCatalog {
    /// From the most general to the most specific.
    let groups: [GroupDefinition]

    /// The layer's groups, from the most general to the most specific: `layer` always, `view`
    /// when the layer backs a view, then one group for each kind of view it is.
    func read(_ layer: CALayer) -> [AttributeGroup] {
        let view = LayerTopology.backingView(of: layer)
        return groups.compactMap { $0.read(layer, view) }
    }

    /// The attribute `id` of the layer as it reads now, and how to change it; `nil` when none
    /// of the layer's groups has it. An attribute that reads as read-only now is returned too,
    /// with no `prepare`.
    func attributeForEditing(_ id: String, of layer: CALayer) -> AttributeEdit? {
        let view = LayerTopology.backingView(of: layer)
        return groups.lazy.compactMap { $0.attributeForEditing(id, layer, view) }.first
    }

    /// The standard groups, from the most general to the most specific. Within
    /// UIKit the specific kinds are related only along one line of inheritance (UIControl
    /// before UIButton and UITextField, UIScrollView before UITextView), so this order holds
    /// for every class.
    static let standard = Self(groups: [
        layerGroup,
        viewGroup,
        controlGroup,
        scrollViewGroup,
        labelGroup,
        imageViewGroup,
        buttonGroup,
        stackViewGroup,
        textFieldGroup,
        textViewGroup
    ])

    private typealias Outputs = AttributeOutputs

    private static let layerGroup = GroupDefinition(
        "layer",
        subject: { (layer: CALayer, _: UIView?) in layer },
        [
            // Worked out from bounds, position, anchorPoint and transform.
            .init("frame", .rect, write: nil) { Outputs.rect($0.frame) },
            .init("bounds", .rect, write: .rect(\.bounds, nonNegative: true)) { Outputs.rect($0.bounds) },
            .init("position", .point, write: .point(\.position)) { Outputs.point($0.position) },
            .init("anchorPoint", .point, write: .point(\.anchorPoint)) { Outputs.point($0.anchorPoint) },
            .init("zPosition", .double, write: .number(\.zPosition)) { Outputs.double($0.zPosition) },
            .init("transform", .transform, write: .transform(\.transform)) { Outputs.transform($0.transform) },
            .init("hidden", .bool, write: .bool(\.isHidden)) { .bool($0.isHidden) },
            .init("opacity", .double, write: .number(\.opacity, rule: .unit)) { Outputs.double($0.opacity) },
            .init("masksToBounds", .bool, write: .bool(\.masksToBounds)) { .bool($0.masksToBounds) },
            .init("cornerRadius", .double, write: .number(\.cornerRadius, rule: .nonNegative)) {
                Outputs.double($0.cornerRadius)
            },
            .init("backgroundColor", .color, acceptsNil: true, write: .cgColor(\.backgroundColor)) {
                Outputs.color($0.backgroundColor)
            },
            .init("borderWidth", .double, write: .number(\.borderWidth, rule: .nonNegative)) {
                Outputs.double($0.borderWidth)
            },
            .init("borderColor", .color, acceptsNil: true, write: .cgColor(\.borderColor)) {
                Outputs.color($0.borderColor)
            },
            .init("shadowColor", .color, acceptsNil: true, write: .cgColor(\.shadowColor)) {
                Outputs.color($0.shadowColor)
            },
            .init("shadowOpacity", .double, write: .number(\.shadowOpacity, rule: .unit)) {
                Outputs.double($0.shadowOpacity)
            },
            .init("shadowRadius", .double, write: .number(\.shadowRadius, rule: .nonNegative)) {
                Outputs.double($0.shadowRadius)
            },
            .init("shadowOffset", .size, write: .size(\.shadowOffset)) { Outputs.size($0.shadowOffset) }
        ] as [AttributeDefinition<CALayer>]
    )

    private static let viewGroup = GroupDefinition(
        "view",
        subject: { (_: CALayer, view: UIView?) in view },
        [
            .init("alpha", .double, write: .number(\.alpha, rule: .unit)) { Outputs.double($0.alpha) },
            .init("isHidden", .bool, write: .bool(\.isHidden)) { .bool($0.isHidden) },
            .init("isOpaque", .bool, write: .bool(\.isOpaque)) { .bool($0.isOpaque) },
            .init("clipsToBounds", .bool, write: .bool(\.clipsToBounds)) { .bool($0.clipsToBounds) },
            .init("isUserInteractionEnabled", .bool, write: .bool(\.isUserInteractionEnabled)) {
                .bool($0.isUserInteractionEnabled)
            },
            .init("tag", .int, write: .int(\.tag)) { .int(Int64($0.tag)) },
            .init("contentMode", .enumeration, write: .enumeration(\.contentMode)) {
                Outputs.enumeration($0.contentMode.rawValue, names: Outputs.contentModeNames)
            },
            .init("tintColor", .color, acceptsNil: true, write: .uiColor(\.tintColor)) { Outputs.color(
                $0.tintColor,
                in: $0
            ) },
            .init("layoutMargins", .insets, write: .insets(\.layoutMargins)) { Outputs.insets($0.layoutMargins) },
            // Protocol 0.4 (S-ATTR-07).
            .init(
                "contentHuggingPriority.horizontal",
                .double,
                write: .priority { $0.setContentHuggingPriority($1, for: .horizontal) }
            ) { Outputs.double($0.contentHuggingPriority(for: .horizontal).rawValue) },
            .init(
                "contentHuggingPriority.vertical",
                .double,
                write: .priority { $0.setContentHuggingPriority($1, for: .vertical) }
            ) { Outputs.double($0.contentHuggingPriority(for: .vertical).rawValue) },
            .init(
                "contentCompressionResistancePriority.horizontal",
                .double,
                write: .priority { $0.setContentCompressionResistancePriority($1, for: .horizontal) }
            ) { Outputs.double($0.contentCompressionResistancePriority(for: .horizontal).rawValue) },
            .init(
                "contentCompressionResistancePriority.vertical",
                .double,
                write: .priority { $0.setContentCompressionResistancePriority($1, for: .vertical) }
            ) { Outputs.double($0.contentCompressionResistancePriority(for: .vertical).rawValue) },
            // Worked out by the view from its content.
            .init("intrinsicContentSize.width", .double, write: nil) {
                Outputs.intrinsicDimension($0.intrinsicContentSize.width)
            },
            .init("intrinsicContentSize.height", .double, write: nil) {
                Outputs.intrinsicDimension($0.intrinsicContentSize.height)
            },
            .init(
                "translatesAutoresizingMaskIntoConstraints",
                .bool,
                write: .bool(\.translatesAutoresizingMaskIntoConstraints)
            ) { .bool($0.translatesAutoresizingMaskIntoConstraints) },
            // Worked out by Auto Layout.
            .init("hasAmbiguousLayout", .bool, write: nil) { .bool($0.hasAmbiguousLayout) }
        ] as [AttributeDefinition<UIView>]
    )

    private static let controlGroup = GroupDefinition(
        "control",
        subject: { (_: CALayer, view: UIView?) in view as? UIControl },
        [
            .init("isEnabled", .bool, write: .bool(\.isEnabled)) { .bool($0.isEnabled) },
            .init("isSelected", .bool, write: .bool(\.isSelected)) { .bool($0.isSelected) },
            .init("isHighlighted", .bool, write: .bool(\.isHighlighted)) { .bool($0.isHighlighted) }
        ] as [AttributeDefinition<UIControl>]
    )

    private static let scrollViewGroup = GroupDefinition(
        "scrollView",
        subject: { (_: CALayer, view: UIView?) in view as? UIScrollView },
        [
            .init("contentOffset", .point, write: AttributeWriter { view, value in
                guard case .point(let point)? = value else { return .failure(.otherKind) }
                return .success { view.setContentOffset(CGPoint(point), animated: false) }
            }) { Outputs.point($0.contentOffset) },
            .init("contentSize", .size, write: .size(\.contentSize, nonNegative: true)) { Outputs.size($0.contentSize)
            },
            .init("contentInset", .insets, write: .insets(\.contentInset)) { Outputs.insets($0.contentInset) },
            // contentInset plus the safe area.
            .init("adjustedContentInset", .insets, write: nil) {
                Outputs.insets($0.adjustedContentInset)
            },
            .init("isScrollEnabled", .bool, write: .bool(\.isScrollEnabled)) { .bool($0.isScrollEnabled) },
            .init("isPagingEnabled", .bool, write: .bool(\.isPagingEnabled)) { .bool($0.isPagingEnabled) }
        ] as [AttributeDefinition<UIScrollView>]
    )

    private static let labelGroup = GroupDefinition(
        "label",
        subject: { (_: CALayer, view: UIView?) in view as? UILabel },
        [
            .init("text", .string, acceptsNil: true, write: .string(\.text)) { $0.text.map { .string($0) } },
            .init("fontName", .string, write: .fontName(\.font)) { $0.font.map { .string($0.fontName) } },
            .init("fontSize", .double, write: .fontSize(\.font)) { $0.font.map { Outputs.double($0.pointSize) } },
            .init("textColor", .color, acceptsNil: true, write: .uiColor(\.textColor)) { Outputs.color(
                $0.textColor,
                in: $0
            ) },
            .init("textAlignment", .enumeration, write: .enumeration(\.textAlignment)) {
                Outputs.enumeration($0.textAlignment.rawValue, names: Outputs.textAlignmentNames)
            },
            .init("numberOfLines", .int, write: .int(\.numberOfLines, nonNegative: true)) {
                .int(Int64($0.numberOfLines))
            },
            .init("lineBreakMode", .enumeration, write: .enumeration(\.lineBreakMode)) {
                Outputs.enumeration($0.lineBreakMode.rawValue, names: Outputs.lineBreakModeNames)
            }
        ] as [AttributeDefinition<UILabel>]
    )

    private static let imageViewGroup = GroupDefinition(
        "imageView",
        subject: { (_: CALayer, view: UIView?) in view as? UIImageView },
        [
            // The image's own size.
            .init("imageSize", .size, write: nil) { $0.image.map { Outputs.size($0.size) } },
            .init("isHighlighted", .bool, write: .bool(\.isHighlighted)) { .bool($0.isHighlighted) }
        ] as [AttributeDefinition<UIImageView>]
    )

    private static let buttonGroup = GroupDefinition(
        "button",
        subject: { (_: CALayer, view: UIView?) in view as? UIButton },
        [
            .init("currentTitle", .string, acceptsNil: true, write: AttributeWriter { button, value in
                AttributeInputs.string(value).map { title in { button.setTitle(title, for: button.state) } }
            }) { $0.currentTitle.map { .string($0) } },
            .init("currentTitleColor", .color, acceptsNil: true, write: AttributeWriter { button, value in
                AttributeInputs.color(value).map { color in
                    { button.setTitleColor(color.map(UIColor.init(cgColor:)), for: button.state) }
                }
            }) {
                Outputs.color($0.currentTitleColor, in: $0)
            }
        ] as [AttributeDefinition<UIButton>]
    )

    private static let stackViewGroup = GroupDefinition(
        "stackView",
        subject: { (_: CALayer, view: UIView?) in view as? UIStackView },
        [
            .init("axis", .enumeration, write: .enumeration(\.axis)) { Outputs.enumeration(
                $0.axis.rawValue,
                names: Outputs.axisNames
            ) },
            .init("alignment", .enumeration, write: .enumeration(\.alignment)) {
                Outputs.enumeration($0.alignment.rawValue, names: Outputs.stackAlignmentNames(axis: $0.axis))
            },
            .init("distribution", .enumeration, write: .enumeration(\.distribution)) {
                Outputs.enumeration($0.distribution.rawValue, names: Outputs.distributionNames)
            },
            .init("spacing", .double, write: .number(\.spacing)) { Outputs.double($0.spacing) }
        ] as [AttributeDefinition<UIStackView>]
    )

    private static let textFieldGroup = GroupDefinition(
        "textField",
        subject: { (_: CALayer, view: UIView?) in view as? UITextField },
        [
            .init("text", .string, acceptsNil: true, write: .string(\.text)) { $0.text.map { .string($0) } },
            .init("placeholder", .string, acceptsNil: true, write: .string(\.placeholder)) {
                $0.placeholder.map { .string($0) }
            },
            .init("fontName", .string, write: .fontName(\.font)) { $0.font.map { .string($0.fontName) } },
            .init("fontSize", .double, write: .fontSize(\.font)) { $0.font.map { Outputs.double($0.pointSize) } },
            .init("textColor", .color, acceptsNil: true, write: .uiColor(\.textColor)) { Outputs.color(
                $0.textColor,
                in: $0
            ) }
        ] as [AttributeDefinition<UITextField>]
    )

    private static let textViewGroup = GroupDefinition(
        "textView",
        subject: { (_: CALayer, view: UIView?) in view as? UITextView },
        [
            .init("text", .string, write: .string(\.text)) { $0.text.map { .string($0) } },
            .init("fontName", .string, write: .fontName(\.font)) { $0.font.map { .string($0.fontName) } },
            .init("fontSize", .double, write: .fontSize(\.font)) { $0.font.map { Outputs.double($0.pointSize) } },
            .init("textColor", .color, acceptsNil: true, write: .uiColor(\.textColor)) { Outputs.color(
                $0.textColor,
                in: $0
            ) },
            .init("isEditable", .bool, write: .bool(\.isEditable)) { .bool($0.isEditable) }
        ] as [AttributeDefinition<UITextView>]
    )
}
#endif
