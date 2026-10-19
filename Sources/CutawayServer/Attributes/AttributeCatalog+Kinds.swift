#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

// The groups of the specific kinds of views. They hold what is particular to each kind: all of
// it is `content` (P-ATTR-08).
extension AttributeCatalog {
    static let controlGroup = GroupDefinition(
        "control",
        className: "UIControl",
        subject: { (_: CALayer, view: UIView?) in view as? UIControl },
        [
            .init(
                "isEnabled",
                .bool,
                title: "Enabled",
                section: .content,
                cluster: ("state", "enabled"),
                write: .bool(\.isEnabled)
            ) { .bool($0.isEnabled) },
            .init(
                "isSelected",
                .bool,
                title: "Selected",
                section: .content,
                cluster: ("state", "selected"),
                write: .bool(\.isSelected)
            ) { .bool($0.isSelected) },
            .init(
                "isHighlighted",
                .bool,
                title: "Highlighted",
                section: .content,
                cluster: ("state", "highlighted"),
                write: .bool(\.isHighlighted)
            ) { .bool($0.isHighlighted) }
        ] as [AttributeDefinition<UIControl>]
    )

    static let scrollViewGroup = GroupDefinition(
        "scrollView",
        className: "UIScrollView",
        subject: { (_: CALayer, view: UIView?) in view as? UIScrollView },
        [
            .init("contentOffset", .point, section: .content, unit: .points, write: AttributeWriter { view, value in
                guard case .point(let point)? = value else { return .failure(.otherKind) }
                return .success { view.setContentOffset(CGPoint(point), animated: false) }
            }) { Outputs.point($0.contentOffset) },
            .init(
                "contentSize",
                .size,
                section: .content,
                unit: .points,
                limits: Limits.nonNegative,
                write: .size(\.contentSize)
            ) { Outputs.size($0.contentSize) },
            .init("contentInset", .insets, section: .content, unit: .points, write: .insets(\.contentInset)) {
                Outputs.insets($0.contentInset)
            },
            // contentInset plus the safe area.
            .init("adjustedContentInset", .insets, section: .content, unit: .points, write: nil) {
                Outputs.insets($0.adjustedContentInset)
            },
            .init(
                "isScrollEnabled",
                .bool,
                title: "Scrolling",
                section: .content,
                cluster: ("scrolling", "enabled"),
                write: .bool(\.isScrollEnabled)
            ) { .bool($0.isScrollEnabled) },
            .init(
                "isPagingEnabled",
                .bool,
                title: "Paging",
                section: .content,
                cluster: ("scrolling", "paging"),
                write: .bool(\.isPagingEnabled)
            ) { .bool($0.isPagingEnabled) },
            // Protocol 1.2 (S-ATTR-18). Also a table's and a collection view's delegate.
            .references("delegate", section: .content) { $0.delegate.map { [$0 as AnyObject] } }
        ] as [AttributeDefinition<UIScrollView>]
    )

    static let labelGroup = GroupDefinition(
        "label",
        className: "UILabel",
        subject: { (_: CALayer, view: UIView?) in view as? UILabel },
        [
            .init("text", .string, acceptsNil: true, section: .content, write: .string(\.text)) {
                $0.text.map { .string($0) }
            },
            .init(
                "fontName",
                .string,
                title: "Font",
                section: .content,
                cluster: ("font", "name"),
                write: .fontName(\.font)
            ) { $0.font.map { .string($0.fontName) } },
            .init(
                "fontSize",
                .double,
                section: .content,
                cluster: ("font", "size"),
                unit: .points,
                limits: Limits.positive,
                write: .fontSize(\.font)
            ) { $0.font.map { Outputs.double($0.pointSize) } }
        ] + fontDefinitions(font: \.font, adjusts: \.adjustsFontForContentSizeCategory) + [
            .init("textColor", .color, acceptsNil: true, section: .content, write: .uiColor(\.textColor)) {
                Outputs.color($0.textColor, in: $0)
            },
            .init("textAlignment", .enumeration, section: .content, write: .enumeration(\.textAlignment)) {
                Outputs.enumeration($0.textAlignment.rawValue, names: Outputs.textAlignmentNames)
            },
            .init(
                "numberOfLines",
                .int,
                title: "Lines",
                section: .content,
                cluster: ("lines", "count"),
                limits: Limits.nonNegative,
                write: .int(\.numberOfLines)
            ) { .int(Int64($0.numberOfLines)) },
            .init(
                "lineBreakMode",
                .enumeration,
                section: .content,
                cluster: ("lines", "lineBreak"),
                write: .enumeration(\.lineBreakMode)
            ) { Outputs.enumeration($0.lineBreakMode.rawValue, names: Outputs.lineBreakModeNames) },
            // Protocol 1.2 (S-ATTR-22).
            .init(
                "drawnLineCount",
                .int,
                title: "Drawn Lines",
                section: .content,
                cluster: ("lines", "drawn"),
                write: nil
            ) {
                AttributeTexts.lines(of: $0).map { .int(Int64($0.count)) }
            },
            .init(
                "isTruncated",
                .bool,
                title: "Truncated",
                section: .content,
                cluster: ("lines", "truncated"),
                write: nil
            ) {
                AttributeTexts.lines(of: $0).map { .bool($0.truncated) }
            }
        ] as [AttributeDefinition<UILabel>]
    )

    static let imageViewGroup = GroupDefinition(
        "imageView",
        className: "UIImageView",
        subject: { (_: CALayer, view: UIView?) in view as? UIImageView },
        imageDefinitions { $0.image } + [
            .init(
                "isHighlighted",
                .bool,
                title: "Highlighted",
                section: .content,
                cluster: ("state", "highlighted"),
                write: .bool(\.isHighlighted)
            ) { .bool($0.isHighlighted) }
        ] as [AttributeDefinition<UIImageView>]
    )

    static let buttonGroup = GroupDefinition(
        "button",
        className: "UIButton",
        subject: { (_: CALayer, view: UIView?) in view as? UIButton },
        [
            .init(
                "currentTitle",
                .string,
                title: "Title",
                acceptsNil: true,
                section: .content,
                write: AttributeWriter { button, value in
                    AttributeInputs.string(value).map { title in { button.setTitle(title, for: button.state) } }
                }
            ) { $0.currentTitle.map { .string($0) } },
            .init(
                "currentTitleColor",
                .color,
                title: "Title Color",
                acceptsNil: true,
                section: .content,
                write: AttributeWriter { button, value in
                    AttributeInputs.color(value).map { color in
                        { button.setTitleColor(color.map(UIColor.init(cgColor:)), for: button.state) }
                    }
                }
            ) { Outputs.color($0.currentTitleColor, in: $0) }
        ] + imageDefinitions { $0.currentImage } as [AttributeDefinition<UIButton>]
    )

    static let stackViewGroup = GroupDefinition(
        "stackView",
        className: "UIStackView",
        subject: { (_: CALayer, view: UIView?) in view as? UIStackView },
        [
            .init("axis", .enumeration, section: .content, write: .enumeration(\.axis)) {
                Outputs.enumeration($0.axis.rawValue, names: Outputs.axisNames)
            },
            .init("alignment", .enumeration, section: .content, write: .enumeration(\.alignment)) {
                Outputs.enumeration($0.alignment.rawValue, names: Outputs.stackAlignmentNames(axis: $0.axis))
            },
            .init("distribution", .enumeration, section: .content, write: .enumeration(\.distribution)) {
                Outputs.enumeration($0.distribution.rawValue, names: Outputs.distributionNames)
            },
            .init("spacing", .double, section: .content, unit: .points, write: .number(\.spacing)) {
                Outputs.double($0.spacing)
            },
            // Protocol 1.2 (S-ATTR-18, 19).
            .references("arrangedSubviews", section: .content) { $0.arrangedSubviews },
            .init("customSpacing", .string, section: .content, write: nil) {
                AttributeTexts.customSpacing(of: $0).map { .string($0) }
            }
        ] as [AttributeDefinition<UIStackView>]
    )

    static let textFieldGroup = GroupDefinition(
        "textField",
        className: "UITextField",
        subject: { (_: CALayer, view: UIView?) in view as? UITextField },
        [
            .init("text", .string, acceptsNil: true, section: .content, write: .string(\.text)) {
                $0.text.map { .string($0) }
            },
            .init("placeholder", .string, acceptsNil: true, section: .content, write: .string(\.placeholder)) {
                $0.placeholder.map { .string($0) }
            },
            .init(
                "fontName",
                .string,
                title: "Font",
                section: .content,
                cluster: ("font", "name"),
                write: .fontName(\.font)
            ) { $0.font.map { .string($0.fontName) } },
            .init(
                "fontSize",
                .double,
                section: .content,
                cluster: ("font", "size"),
                unit: .points,
                limits: Limits.positive,
                write: .fontSize(\.font)
            ) { $0.font.map { Outputs.double($0.pointSize) } }
        ] + fontDefinitions(font: \.font, adjusts: \.adjustsFontForContentSizeCategory) + [
            .init("textColor", .color, acceptsNil: true, section: .content, write: .uiColor(\.textColor)) {
                Outputs.color($0.textColor, in: $0)
            }
        ] as [AttributeDefinition<UITextField>]
    )

    static let textViewGroup = GroupDefinition(
        "textView",
        className: "UITextView",
        subject: { (_: CALayer, view: UIView?) in view as? UITextView },
        [
            .init("text", .string, section: .content, write: .string(\.text)) { $0.text.map { .string($0) } },
            .init(
                "fontName",
                .string,
                title: "Font",
                section: .content,
                cluster: ("font", "name"),
                write: .fontName(\.font)
            ) { $0.font.map { .string($0.fontName) } },
            .init(
                "fontSize",
                .double,
                section: .content,
                cluster: ("font", "size"),
                unit: .points,
                limits: Limits.positive,
                write: .fontSize(\.font)
            ) { $0.font.map { Outputs.double($0.pointSize) } }
        ] + fontDefinitions(font: \.font, adjusts: \.adjustsFontForContentSizeCategory) + [
            .init("textColor", .color, acceptsNil: true, section: .content, write: .uiColor(\.textColor)) {
                Outputs.color($0.textColor, in: $0)
            },
            .init("isEditable", .bool, title: "Editable", section: .content, write: .bool(\.isEditable)) {
                .bool($0.isEditable)
            }
        ] as [AttributeDefinition<UITextView>]
    )

    // MARK: - Shared by several groups (protocol 1.2)

    /// S-ATTR-21: a font as text, the text style it was made for, and whether it follows the
    /// text size.
    private static func fontDefinitions<Subject: UIView>(
        font: KeyPath<Subject, UIFont?>,
        adjusts: ReferenceWritableKeyPath<Subject, Bool>
    ) -> [AttributeDefinition<Subject>] {
        [
            .init("fontDescription", .string, section: .content, write: nil) {
                $0[keyPath: font].map { .string(AttributeTexts.font($0)) }
            },
            .init(
                "fontTextStyle",
                .string,
                title: "Text Style",
                section: .content,
                cluster: ("font", "textStyle"),
                write: nil
            ) {
                $0[keyPath: font].flatMap(AttributeTexts.textStyle(of:)).map { .string($0) }
            },
            .init(
                "adjustsFontForContentSizeCategory",
                .bool,
                title: "Adjusts to Text Size",
                section: .content,
                cluster: ("font", "scalable"),
                write: .bool(adjusts)
            ) { .bool($0[keyPath: adjusts]) }
        ]
    }

    /// S-ATTR-20: an image's name, size, scale, rendering mode and symbol configuration; all
    /// nil without an image. The name and the configuration come from descriptions (H4).
    private static func imageDefinitions<Subject>(
        _ image: @escaping (Subject) -> UIImage?
    ) -> [AttributeDefinition<Subject>] {
        [
            .init("imageName", .string, title: "Image", section: .content, cluster: ("image", "name"), write: nil) {
                image($0).flatMap { AttributeTexts.imageName(inDescription: $0.description) }.map { .string($0) }
            },
            // The image's own size.
            .init("imageSize", .size, section: .content, cluster: ("image", "size"), unit: .points, write: nil) {
                image($0).map { Outputs.size($0.size) }
            },
            .init("imageScale", .double, section: .content, cluster: ("image", "scale"), write: nil) {
                image($0).map { Outputs.double($0.scale) }
            },
            .init(
                "imageRenderingMode",
                .enumeration,
                title: "Rendering Mode",
                section: .content,
                cluster: ("image", "renderingMode"),
                write: nil
            ) { image($0).map { Outputs.enumeration($0.renderingMode.rawValue, names: Outputs.renderingModeNames) } },
            .init(
                "symbolConfiguration",
                .string,
                section: .content,
                cluster: ("image", "symbolConfiguration"),
                write: nil
            ) {
                guard let image = image($0), image.isSymbolImage,
                      let configuration = image.symbolConfiguration else {
                    return nil
                }
                return AttributeTexts.symbolConfiguration(inDescription: configuration.description).map { .string($0) }
            }
        ]
    }
}
#endif
