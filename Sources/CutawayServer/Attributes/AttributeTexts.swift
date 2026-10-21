#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import UIKit

/// The attributes of protocol 1.2 that are sent as text, and what they are worked out from.
/// Everything here only reads.
enum AttributeTexts {
    // MARK: - Lists

    /// The most items a list of text names; the rest are counted, so that a long list costs
    /// little to read and to send.
    static let listLimit = 100

    /// "a, b, c"; "None" when empty; past `listLimit` items, "… (N more)".
    static func list(_ items: [String]) -> String {
        list(items) { $0 }
    }

    /// The same for items that `text` writes; only the items named are written.
    static func list<Item>(_ items: [Item], _ text: (Item) -> String) -> String {
        guard !items.isEmpty else { return "None" }
        let named = items.prefix(listLimit).map(text)
        guard items.count > listLimit else { return named.joined(separator: ", ") }
        return (named + ["… (\(items.count - listLimit) more)"]).joined(separator: ", ")
    }

    /// "0.0, 0.1, 1.0", by section and then item.
    static func indexPaths(_ paths: [IndexPath]) -> String {
        list(paths.sorted()) { "\($0.section).\($0.item)" }
    }

    /// A number as a person writes it: "17", "12.5", at most two decimals.
    static func number(_ value: CGFloat) -> String {
        let rounded = (Double(value) * 100).rounded() / 100
        guard rounded.isFinite else { return "0" }
        if rounded == rounded.rounded(), abs(rounded) < 1e15 { return String(Int64(rounded)) }
        return String(rounded)
    }

    // MARK: - Accessibility

    private static let traitNames: [(UIAccessibilityTraits, String)] = {
        var names: [(UIAccessibilityTraits, String)] = [
            (.button, "Button"),
            (.link, "Link"),
            (.image, "Image"),
            (.selected, "Selected"),
            (.playsSound, "Plays Sound"),
            (.keyboardKey, "Keyboard Key"),
            (.staticText, "Static Text"),
            (.summaryElement, "Summary Element"),
            (.notEnabled, "Not Enabled"),
            (.updatesFrequently, "Updates Frequently"),
            (.searchField, "Search Field"),
            (.startsMediaSession, "Starts Media Session"),
            (.adjustable, "Adjustable"),
            (.allowsDirectInteraction, "Allows Direct Interaction"),
            (.causesPageTurn, "Causes Page Turn"),
            (.tabBar, "Tab Bar"),
            (.header, "Header")
        ]
        if #available(iOS 17, *) {
            names += [(.toggleButton, "Toggle Button"), (.supportsZoom, "Supports Zoom")]
        }
        return names.sorted { $0.0.rawValue < $1.0.rawValue }
    }()

    /// "Button, Selected", by bit; "None" for none; the bits without a name together in hex.
    static func traits(_ traits: UIAccessibilityTraits) -> String {
        var names: [String] = []
        var rest = traits.rawValue
        for (trait, name) in traitNames where traits.contains(trait) {
            names.append(name)
            rest &= ~trait.rawValue
        }
        if rest != 0 { names.append("0x" + String(rest, radix: 16)) }
        return names.isEmpty ? "None" : names.joined(separator: ", ")
    }

    // MARK: - Stack views

    /// "after 0: 12, after 2: system": the spacings set after arranged subviews, by index; `nil`
    /// when none is.
    @MainActor static func customSpacing(of stack: UIStackView) -> String? {
        let spacings = stack.arrangedSubviews.enumerated().compactMap { index, view -> String? in
            let spacing = stack.customSpacing(after: view)
            if spacing == UIStackView.spacingUseDefault { return nil }
            let text = spacing == UIStackView.spacingUseSystem ? "system" : number(spacing)
            return "after \(index): \(text)"
        }
        return spacings.isEmpty ? nil : list(spacings)
    }

    // MARK: - Images

    /// The name in an image's description: `named(main: Swatch)` gives "Swatch",
    /// `symbol(system: star.fill)` "star.fill". UIKit has no API for it; the description is
    /// written so on every system version the tests run on. `nil` when the description is not
    /// of that form, as for an image made in code (`anonymous`).
    static func imageName(inDescription description: String) -> String? {
        for marker in [" named(", " symbol("] {
            guard let start = description.range(of: marker) else { continue }
            let rest = description[start.upperBound...]
            guard let colon = rest.range(of: ": "),
                  let end = rest.range(of: ") {", range: colon.upperBound..<rest.endIndex) else {
                return nil
            }
            let name = rest[colon.upperBound..<end.lowerBound]
            return name.isEmpty ? nil : String(name)
        }
        return nil
    }

    /// A symbol configuration's description without the traits it was resolved with and
    /// without empty parts: "pointSize=24, weight=Bold, scale=Large". The words are the
    /// system's and differ between versions. `nil` when nothing is left.
    static func symbolConfiguration(inDescription description: String) -> String? {
        var parts: [String] = []
        var part = ""
        var depth = 0
        for character in description {
            switch character {
            case "(": depth += 1
            case ")": depth -= 1
            default: break
            }
            part.append(character)
            if depth == 0, part.hasSuffix(", ") {
                parts.append(String(part.dropLast(2)))
                part = ""
            }
        }
        parts.append(part)
        let kept = parts.filter { !$0.isEmpty && $0 != "(null)" && !$0.hasPrefix("traits=") }
        return kept.isEmpty ? nil : kept.joined(separator: ", ")
    }

    // MARK: - Fonts

    private static let weights: [(UIFont.Weight, String)] = [
        (.ultraLight, "Ultralight"),
        (.thin, "Thin"),
        (.light, "Light"),
        (.regular, "Regular"),
        (.medium, "Medium"),
        (.semibold, "Semibold"),
        (.bold, "Bold"),
        (.heavy, "Heavy"),
        (.black, "Black")
    ]

    /// "System, Semibold, 17 pt", "Helvetica, Bold, Italic, 14 pt": the family, the weight,
    /// italic and monospaced when they are, and the size. Not `UIFont.description`, which has
    /// the font's address. The system font's family has a private name; it is called System.
    static func font(_ font: UIFont) -> String {
        let descriptor = font.fontDescriptor
        let symbolic = descriptor.symbolicTraits
        let family = font.familyName.hasPrefix(".") ? "System" : font.familyName
        var parts = [family]
        let traits = descriptor.object(forKey: .traits) as? [UIFontDescriptor.TraitKey: Any]
        if let weight = (traits?[.weight] as? NSNumber).map({ CGFloat($0.doubleValue) }),
           let nearest = weights.min(by: { abs($0.0.rawValue - weight) < abs($1.0.rawValue - weight) }) {
            parts.append(nearest.1)
        } else {
            parts.append(symbolic.contains(.traitBold) ? "Bold" : "Regular")
        }
        if symbolic.contains(.traitItalic) { parts.append("Italic") }
        if symbolic.contains(.traitMonoSpace) { parts.append("Monospaced") }
        parts.append("\(number(font.pointSize)) pt")
        return parts.joined(separator: ", ")
    }

    private static let textStyleNames: [UIFont.TextStyle: String] = {
        var names: [UIFont.TextStyle: String] = [
            .largeTitle: "largeTitle",
            .title1: "title1",
            .title2: "title2",
            .title3: "title3",
            .headline: "headline",
            .subheadline: "subheadline",
            .body: "body",
            .callout: "callout",
            .footnote: "footnote",
            .caption1: "caption1",
            .caption2: "caption2"
        ]
        if #available(iOS 17, *) {
            names[.extraLargeTitle] = "extraLargeTitle"
            names[.extraLargeTitle2] = "extraLargeTitle2"
        }
        return names
    }()

    /// The text style a font was made for, by its short name ("body"); `nil` for a font made
    /// for none. The system font's descriptor names a usage there ("CTFontRegularUsage"), which
    /// is not a text style.
    static func textStyle(of font: UIFont) -> String? {
        guard let raw = font.fontDescriptor.object(forKey: .textStyle) as? String,
              !raw.hasPrefix("CTFont") else {
            return nil
        }
        return textStyleName(UIFont.TextStyle(rawValue: raw))
    }

    /// The short name of a text style; one this table does not know keeps its own.
    static func textStyleName(_ style: UIFont.TextStyle) -> String {
        textStyleNames[style] ?? style.rawValue
    }

    // MARK: - Lines

    /// The lines a label draws its text in, and whether some of it is left out; measured with
    /// TextKit in the label's bounds with its line limit, which gives the lines UILabel draws.
    /// Lines wrap as UILabel wraps all but its last one: in TextKit 1 a truncating line break
    /// mode would cut every line. Some text is left out when glyphs did not fit. `nil` when the
    /// label shrinks its text to fit, as the shrunk size is not known. Each call lays the text
    /// out anew; `AttributeReading.lines(of:)` does it once in a read.
    @MainActor static func lines(of label: UILabel) -> (count: Int, truncated: Bool)? {
        guard !label.adjustsFontSizeToFitWidth else { return nil }
        guard let text = label.attributedText, text.length > 0 else { return (0, false) }
        let storage = NSTextStorage(attributedString: text)
        let wrapping: NSLineBreakMode = label.lineBreakMode == .byCharWrapping ? .byCharWrapping : .byWordWrapping
        let whole = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.paragraphStyle, in: whole) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            style.lineBreakMode = wrapping
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: label.bounds.size)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = label.numberOfLines
        container.lineBreakMode = wrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let glyphs = manager.glyphRange(for: container)
        var count = 0
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in count += 1 }
        return (count, NSMaxRange(glyphs) < manager.numberOfGlyphs)
    }
}
#endif
