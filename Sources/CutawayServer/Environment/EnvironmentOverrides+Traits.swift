#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

// The protocol's trait values and UIKit's, both ways (PROTOCOL.md, P-ENV-01).

extension EnvironmentOverrides {
    nonisolated private static let contentSizeCategories: [(ContentSizeCategory, UIContentSizeCategory)] = [
        (.extraSmall, .extraSmall),
        (.small, .small),
        (.medium, .medium),
        (.large, .large),
        (.extraLarge, .extraLarge),
        (.extraExtraLarge, .extraExtraLarge),
        (.extraExtraExtraLarge, .extraExtraExtraLarge),
        (.accessibilityMedium, .accessibilityMedium),
        (.accessibilityLarge, .accessibilityLarge),
        (.accessibilityExtraLarge, .accessibilityExtraLarge),
        (.accessibilityExtraExtraLarge, .accessibilityExtraExtraLarge),
        (.accessibilityExtraExtraExtraLarge, .accessibilityExtraExtraExtraLarge)
    ]

    /// The traits of a trait collection; what has no value in the protocol is `unspecified`.
    static func traits(of collection: UITraitCollection) -> Traits {
        Traits(
            userInterfaceStyle: {
                switch collection.userInterfaceStyle {
                case .light: .light
                case .dark: .dark
                default: .unspecified
                }
            }(),
            contentSizeCategory: contentSizeCategories
                .first { $0.1 == collection.preferredContentSizeCategory }?.0 ?? .unspecified,
            layoutDirection: {
                switch collection.layoutDirection {
                case .leftToRight: .leftToRight
                case .rightToLeft: .rightToLeft
                default: .unspecified
                }
            }(),
            horizontalSizeClass: sizeClass(collection.horizontalSizeClass),
            verticalSizeClass: sizeClass(collection.verticalSizeClass)
        )
    }

    private static func sizeClass(_ sizeClass: UIUserInterfaceSizeClass) -> SizeClass {
        switch sizeClass {
        case .compact: .compact
        case .regular: .regular
        default: .unspecified
        }
    }

    // Each of the following is `nil` for `unspecified`: not overridden.

    nonisolated static func uiStyle(_ style: UserInterfaceStyle) -> UIUserInterfaceStyle? {
        switch style {
        case .unspecified: nil
        case .light: .light
        case .dark: .dark
        }
    }

    nonisolated static func uiContentSizeCategory(_ category: ContentSizeCategory) -> UIContentSizeCategory? {
        contentSizeCategories.first { $0.0 == category }?.1
    }

    nonisolated static func uiLayoutDirection(_ direction: LayoutDirection) -> UITraitEnvironmentLayoutDirection? {
        switch direction {
        case .unspecified: nil
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        }
    }

    nonisolated static func uiSizeClass(_ sizeClass: SizeClass) -> UIUserInterfaceSizeClass? {
        switch sizeClass {
        case .unspecified: nil
        case .compact: .compact
        case .regular: .regular
        }
    }
}
#endif
