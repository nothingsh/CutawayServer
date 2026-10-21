#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The attributes of a layer, by group, with what a client may change, where an inspector
/// shows them (P-ATTR-08), the values a change may have (P-ATTR-09), and the clusters, units
/// and inactive causes of protocol 1.1 (P-ATTR-12 to 14). Of a pair of attributes that read the
/// same state, a layer has one (P-ATTR-11).
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
    func read(_ layer: CALayer, reading: AttributeReading) -> [AttributeGroup] {
        let view = LayerTopology.backingView(of: layer)
        let reading = reading.anew()
        return groups.compactMap { $0.read(layer, view, reading) }
    }

    /// The attribute `id` of the layer as it reads now, and how to change it; `nil` when none
    /// of the layer's groups has it. An attribute that reads as read-only now is returned too,
    /// with no `prepare`.
    func attributeForEditing(_ id: String, of layer: CALayer, reading: AttributeReading) -> AttributeEdit? {
        let view = LayerTopology.backingView(of: layer)
        let reading = reading.anew()
        return groups.lazy.compactMap { $0.attributeForEditing(id, layer, view, reading) }.first
    }

    /// The standard groups, from the most general to the most specific. Within
    /// UIKit the specific kinds are related only along one line of inheritance (UIControl
    /// before UIButton and UITextField, UIScrollView before UITextView), so this order holds
    /// for every class. Cells are views of their own and relate to none of these.
    static let standard = Self(groups: [
        layerGroup,
        viewGroup,
        controlGroup,
        scrollViewGroup,
        tableViewGroup,
        collectionViewGroup,
        tableViewCellGroup,
        collectionViewCellGroup,
        labelGroup,
        imageViewGroup,
        buttonGroup,
        stackViewGroup,
        textFieldGroup,
        textViewGroup
    ])

    typealias Outputs = AttributeOutputs

    /// The limits of the catalog's attributes (P-ATTR-09, 10): what a change may be, and so what
    /// `AttributeEditing` refuses (P-SET-07).
    enum Limits {
        static let nonNegative = [NumberLimit(minimum: 0)]
        static let positive = [NumberLimit(minimum: 0, minimumIsExclusive: true)]
        static let unit = [NumberLimit(minimum: 0, maximum: 1)]
        static let priority = [NumberLimit(minimum: 1, maximum: 1000)]
        /// A rectangle anywhere, of no negative size.
        static let nonNegativeSize = [.free, .free, NumberLimit(minimum: 0), NumberLimit(minimum: 0)]
    }

    private static let layerGroup = GroupDefinition(
        "layer",
        className: "CALayer",
        subject: { (layer: CALayer, _: UIView?) in layer },
        [
            // Worked out from bounds, position, anchorPoint and transform.
            .init("frame", .rect, section: .layout, cluster: ("geometry", "frame"), unit: .points, write: nil) {
                Outputs.rect($0.frame)
            },
            .init(
                "bounds",
                .rect,
                section: .layout,
                cluster: ("geometry", "bounds"),
                unit: .points,
                limits: Limits.nonNegativeSize,
                write: .rect(\.bounds)
            ) { Outputs.rect($0.bounds) },
            .init(
                "position",
                .point,
                section: .layout,
                cluster: ("geometry", "position"),
                unit: .points,
                write: .point(\.position)
            ) { Outputs.point($0.position) },
            .init(
                "anchorPoint",
                .point,
                section: .layout,
                cluster: ("geometry", "anchor"),
                write: .point(\.anchorPoint)
            ) {
                Outputs.point($0.anchorPoint)
            },
            // Mostly decides what is in front, so not a length to show in points.
            .init(
                "zPosition",
                .double,
                title: "Z Position",
                section: .layout,
                cluster: ("geometry", "zPosition"),
                write: .number(\.zPosition)
            ) { Outputs.double($0.zPosition) },
            .init(
                "transform",
                .transform,
                section: .layout,
                cluster: ("geometry", "transform"),
                write: .transform(\.transform)
            ) { Outputs.transform($0.transform) },
            // P-ATTR-11: the three a view's attributes stand for.
            .init(
                "hidden",
                .bool,
                title: "Hidden",
                section: .appearance,
                cluster: ("visibility", "hidden"),
                onlyWithoutView: true,
                write: .bool(\.isHidden)
            ) { .bool($0.isHidden) },
            .init(
                "opacity",
                .double,
                title: "Opacity",
                section: .appearance,
                cluster: ("visibility", "opacity"),
                unit: .fraction,
                limits: Limits.unit,
                onlyWithoutView: true,
                write: .number(\.opacity)
            ) { Outputs.double($0.opacity) },
            .init(
                "masksToBounds",
                .bool,
                title: "Clips to Bounds",
                section: .appearance,
                cluster: ("corners", "clip"),
                onlyWithoutView: true,
                write: .bool(\.masksToBounds)
            ) { .bool($0.masksToBounds) },
            .init(
                "cornerRadius",
                .double,
                section: .appearance,
                cluster: ("corners", "radius"),
                unit: .points,
                limits: Limits.nonNegative,
                write: .number(\.cornerRadius)
            ) { Outputs.double($0.cornerRadius) },
            .init(
                "backgroundColor",
                .color,
                title: "Background",
                acceptsNil: true,
                section: .appearance,
                // A view's background can be drawn apart from its layer's (a UILabel draws it
                // into its contents), so a layer that backs a view gives `view.backgroundColor`.
                onlyWithoutView: true,
                write: .cgColor(\.backgroundColor)
            ) { Outputs.color($0.backgroundColor) },
            .init(
                "borderWidth",
                .double,
                section: .appearance,
                cluster: ("border", "width"),
                unit: .points,
                limits: Limits.nonNegative,
                write: .number(\.borderWidth)
            ) { Outputs.double($0.borderWidth) },
            .init(
                "borderColor",
                .color,
                acceptsNil: true,
                section: .appearance,
                cluster: ("border", "color"),
                inactiveCause: Inactive.withoutBorder,
                write: .cgColor(\.borderColor)
            ) { Outputs.color($0.borderColor) },
            .init(
                "shadowColor",
                .color,
                acceptsNil: true,
                section: .appearance,
                cluster: ("shadow", "color"),
                inactiveCause: Inactive.withoutShadow,
                write: .cgColor(\.shadowColor)
            ) { Outputs.color($0.shadowColor) },
            .init(
                "shadowOpacity",
                .double,
                section: .appearance,
                cluster: ("shadow", "opacity"),
                unit: .fraction,
                limits: Limits.unit,
                write: .number(\.shadowOpacity)
            ) { Outputs.double($0.shadowOpacity) },
            .init(
                "shadowRadius",
                .double,
                section: .appearance,
                cluster: ("shadow", "radius"),
                unit: .points,
                limits: Limits.nonNegative,
                inactiveCause: Inactive.withoutShadow,
                write: .number(\.shadowRadius)
            ) { Outputs.double($0.shadowRadius) },
            .init(
                "shadowOffset",
                .size,
                section: .appearance,
                cluster: ("shadow", "offset"),
                unit: .points,
                inactiveCause: Inactive.withoutShadow,
                write: .size(\.shadowOffset)
            ) { Outputs.size($0.shadowOffset) }
        ] as [AttributeDefinition<CALayer>]
    )

    /// P-ATTR-13: what makes an attribute of a layer have no effect now.
    private enum Inactive {
        static func withoutBorder(_ layer: CALayer) -> String? {
            layer.borderWidth == 0 ? "layer.borderWidth" : nil
        }

        static func withoutShadow(_ layer: CALayer) -> String? {
            layer.shadowOpacity == 0 ? "layer.shadowOpacity" : nil
        }
    }

    private static let viewGroup = GroupDefinition(
        "view",
        className: "UIView",
        subject: { (_: CALayer, view: UIView?) in view },
        [
            .init(
                "alpha",
                .double,
                title: "Opacity",
                section: .appearance,
                cluster: ("visibility", "opacity"),
                unit: .fraction,
                limits: Limits.unit,
                write: .number(\.alpha)
            ) { Outputs.double($0.alpha) },
            .init(
                "isHidden",
                .bool,
                title: "Hidden",
                section: .appearance,
                cluster: ("visibility", "hidden"),
                write: .bool(\.isHidden)
            ) { .bool($0.isHidden) },
            .init("isOpaque", .bool, title: "Opaque", section: .appearance, write: .bool(\.isOpaque)) {
                .bool($0.isOpaque)
            },
            .init(
                "clipsToBounds",
                .bool,
                title: "Clips to Bounds",
                section: .appearance,
                cluster: ("corners", "clip"),
                write: .bool(\.clipsToBounds)
            ) { .bool($0.clipsToBounds) },
            .init(
                "isUserInteractionEnabled",
                .bool,
                title: "User Interaction",
                section: .behavior,
                write: .bool(\.isUserInteractionEnabled)
            ) { .bool($0.isUserInteractionEnabled) },
            .init("tag", .int, section: .identity, write: .int(\.tag)) { .int(Int64($0.tag)) },
            .init("contentMode", .enumeration, section: .appearance, write: .enumeration(\.contentMode)) {
                Outputs.enumeration($0.contentMode.rawValue, names: Outputs.contentModeNames)
            },
            .init(
                "backgroundColor",
                .color,
                title: "Background",
                acceptsNil: true,
                section: .appearance,
                write: .uiColor(\.backgroundColor)
            ) { Outputs.color($0.backgroundColor, in: $0) },
            .init(
                "tintColor",
                .color,
                title: "Tint",
                acceptsNil: true,
                section: .appearance,
                write: .uiColor(\.tintColor)
            ) { Outputs.color($0.tintColor, in: $0) },
            .init("layoutMargins", .insets, section: .layout, unit: .points, write: .insets(\.layoutMargins)) {
                Outputs.insets($0.layoutMargins)
            },
            // The eight attributes of Auto Layout from protocol 0.4: priorities, intrinsic size, flags.
            .init(
                "contentHuggingPriority.horizontal",
                .double,
                title: "Hugging (Horizontal)",
                section: .layout,
                cluster: ("sizing", "hugging.horizontal"),
                limits: Limits.priority,
                write: .priority { $0.setContentHuggingPriority($1, for: .horizontal) }
            ) { Outputs.double($0.contentHuggingPriority(for: .horizontal).rawValue) },
            .init(
                "contentHuggingPriority.vertical",
                .double,
                title: "Hugging (Vertical)",
                section: .layout,
                cluster: ("sizing", "hugging.vertical"),
                limits: Limits.priority,
                write: .priority { $0.setContentHuggingPriority($1, for: .vertical) }
            ) { Outputs.double($0.contentHuggingPriority(for: .vertical).rawValue) },
            .init(
                "contentCompressionResistancePriority.horizontal",
                .double,
                title: "Compression Resistance (Horizontal)",
                section: .layout,
                cluster: ("sizing", "compression.horizontal"),
                limits: Limits.priority,
                write: .priority { $0.setContentCompressionResistancePriority($1, for: .horizontal) }
            ) { Outputs.double($0.contentCompressionResistancePriority(for: .horizontal).rawValue) },
            .init(
                "contentCompressionResistancePriority.vertical",
                .double,
                title: "Compression Resistance (Vertical)",
                section: .layout,
                cluster: ("sizing", "compression.vertical"),
                limits: Limits.priority,
                write: .priority { $0.setContentCompressionResistancePriority($1, for: .vertical) }
            ) { Outputs.double($0.contentCompressionResistancePriority(for: .vertical).rawValue) },
            // Worked out by the view from its content.
            .init(
                "intrinsicContentSize.width",
                .double,
                title: "Intrinsic Width",
                section: .layout,
                cluster: ("sizing", "intrinsic.width"),
                unit: .points,
                write: nil
            ) { Outputs.intrinsicDimension($0.intrinsicContentSize.width) },
            .init(
                "intrinsicContentSize.height",
                .double,
                title: "Intrinsic Height",
                section: .layout,
                cluster: ("sizing", "intrinsic.height"),
                unit: .points,
                write: nil
            ) { Outputs.intrinsicDimension($0.intrinsicContentSize.height) },
            .init(
                "translatesAutoresizingMaskIntoConstraints",
                .bool,
                title: "Autoresizing Mask to Constraints",
                section: .layout,
                cluster: ("autoLayout", "autoresizing"),
                write: .bool(\.translatesAutoresizingMaskIntoConstraints)
            ) { .bool($0.translatesAutoresizingMaskIntoConstraints) },
            // Worked out by Auto Layout.
            .init(
                "hasAmbiguousLayout",
                .bool,
                title: "Ambiguous Layout",
                section: .layout,
                cluster: ("autoLayout", "ambiguous"),
                write: nil
            ) { .bool($0.hasAmbiguousLayout) },
            // Accessibility: protocol 1.2.
            .init(
                "accessibilityLabel",
                .string,
                title: "Label",
                acceptsNil: true,
                section: .accessibility,
                write: .string(\.accessibilityLabel)
            ) { $0.accessibilityLabel.map { .string($0) } },
            .init(
                "accessibilityHint",
                .string,
                title: "Hint",
                acceptsNil: true,
                section: .accessibility,
                write: .string(\.accessibilityHint)
            ) { $0.accessibilityHint.map { .string($0) } },
            .init(
                "accessibilityValue",
                .string,
                title: "Value",
                acceptsNil: true,
                section: .accessibility,
                write: .string(\.accessibilityValue)
            ) { $0.accessibilityValue.map { .string($0) } },
            .init(
                "accessibilityIdentifier",
                .string,
                title: "Identifier",
                acceptsNil: true,
                section: .accessibility,
                write: .string(\.accessibilityIdentifier)
            ) { $0.accessibilityIdentifier.map { .string($0) } },
            .init(
                "isAccessibilityElement",
                .bool,
                title: "Accessibility Element",
                section: .accessibility,
                write: .bool(\.isAccessibilityElement)
            ) { .bool($0.isAccessibilityElement) },
            .init("accessibilityTraits", .string, title: "Traits", section: .accessibility, write: nil) {
                .string(AttributeTexts.traits($0.accessibilityTraits))
            }
        ] as [AttributeDefinition<UIView>]
    )
}
#endif
