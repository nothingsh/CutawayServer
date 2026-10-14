#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import UIKit

/// UIKit's system colors by the names of their class properties (PROTOCOL.md, P-ATTR-15).
///
/// A colour is named when it is the very object a class property returns, never by its components:
/// a fixed `#007AFF` is not `systemBlue`. Only the dynamic colours of the Standard Colors and UI
/// Element Colors: UIKit hands out cached objects for fixed colours such as `black`, which an
/// app's own colour of the same value may be.
@MainActor
enum SystemColors {
    /// In table order: when two properties gave the same object, the first name would win.
    static let table: [(name: String, color: UIColor)] = {
        var table: [(String, UIColor)] = [
            ("systemRed", .systemRed),
            ("systemGreen", .systemGreen),
            ("systemBlue", .systemBlue),
            ("systemOrange", .systemOrange),
            ("systemYellow", .systemYellow),
            ("systemPink", .systemPink),
            ("systemPurple", .systemPurple),
            ("systemTeal", .systemTeal),
            ("systemIndigo", .systemIndigo),
            ("systemBrown", .systemBrown),
            ("systemGray", .systemGray),
            ("systemGray2", .systemGray2),
            ("systemGray3", .systemGray3),
            ("systemGray4", .systemGray4),
            ("systemGray5", .systemGray5),
            ("systemGray6", .systemGray6),
            ("label", .label),
            ("secondaryLabel", .secondaryLabel),
            ("tertiaryLabel", .tertiaryLabel),
            ("quaternaryLabel", .quaternaryLabel),
            ("link", .link),
            ("placeholderText", .placeholderText),
            ("separator", .separator),
            ("opaqueSeparator", .opaqueSeparator),
            ("systemBackground", .systemBackground),
            ("secondarySystemBackground", .secondarySystemBackground),
            ("tertiarySystemBackground", .tertiarySystemBackground),
            ("systemGroupedBackground", .systemGroupedBackground),
            ("secondarySystemGroupedBackground", .secondarySystemGroupedBackground),
            ("tertiarySystemGroupedBackground", .tertiarySystemGroupedBackground),
            ("systemFill", .systemFill),
            ("secondarySystemFill", .secondarySystemFill),
            ("tertiarySystemFill", .tertiarySystemFill),
            ("quaternarySystemFill", .quaternarySystemFill)
        ]
        if #available(iOS 15, *) {
            table += [("systemMint", .systemMint), ("systemCyan", .systemCyan), ("tintColor", .tintColor)]
        }
        return table
    }()

    /// The table by object: "is the object the property returns" is identity, and a lookup by
    /// it costs one hash per colour read.
    private static let namesByObject: [ObjectIdentifier: String] = {
        var names: [ObjectIdentifier: String] = [:]
        for (name, color) in table.reversed() { names[ObjectIdentifier(color)] = name }
        return names
    }()

    static func name(of color: UIColor) -> String? {
        namesByObject[ObjectIdentifier(color)]
    }
}
#endif
