#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The overrides of the app's trait environment that one connection set, and the values of
/// the app's own they replaced (PROTOCOL.md, P-ENV-01 to 05). Overrides go on the app's
/// windows, so that they win over what the app sets on its windows and scenes, and lose to
/// what its view controllers and views set.
///
/// Created on the server queue with the session, used on the main thread.
@MainActor
final class EnvironmentOverrides {
    /// How the overrides are applied.
    enum Method {
        /// iOS 17 and later: the appearance with `overrideUserInterfaceStyle`, the other four
        /// kinds with `traitOverrides`.
        case traitOverrides
        /// Before iOS 17: the appearance only.
        case styleOnly
    }

    /// What one window had of its own before it was first overridden. `nil` for a trait the
    /// app did not override on it.
    private struct Own {
        weak var window: UIWindow?
        var style: UIUserInterfaceStyle
        var contentSizeCategory: UIContentSizeCategory?
        var layoutDirection: UITraitEnvironmentLayoutDirection?
        var horizontalSizeClass: UIUserInterfaceSizeClass?
        var verticalSizeClass: UIUserInterfaceSizeClass?
    }

    let method: Method
    /// What the client set on this connection. Read by the tests.
    private(set) var overrides = Traits.none
    /// Keyed by the window's address; an entry counts only while its weak reference is still
    /// that window.
    private var owns: [ObjectIdentifier: Own] = [:]
    private var windowObserver: NSObjectProtocol?

    /// - Parameter method: `nil` takes the one of the system the app runs on; tests choose.
    nonisolated init(method: Method? = nil) {
        if let method {
            self.method = method
        } else if #available(iOS 17, *) {
            self.method = .traitOverrides
        } else {
            self.method = .styleOnly
        }
    }

    /// P-ENV-01: the kinds that can be overridden here.
    var overridable: [TraitKind] {
        switch method {
        case .traitOverrides: TraitKind.allCases
        case .styleOnly: [.userInterfaceStyle]
        }
    }

    /// P-ENV-04: why `traits` cannot be applied, or `nil` when it can.
    nonisolated static func refusal(of traits: Traits, overridable: [TraitKind]) -> WireError? {
        for kind in TraitKind.allCases where traits.specifiedKinds.contains(kind) {
            if traits.unknownKinds.contains(kind) {
                return WireError(
                    code: .notSupported,
                    message: "the \(kind.title) has a value this server does not know"
                )
            }
            if !overridable.contains(kind) {
                return WireError(code: .notSupported, message: "the \(kind.title) cannot be overridden on this device")
            }
        }
        return nil
    }

    /// P-ENV-01: this connection's overrides and the key window's traits, or the first window's.
    func environment(windows: [UIWindow]) -> Environment {
        let window = windows.last(where: \.isKeyWindow) ?? windows.first
        return Environment(
            overrides: overrides,
            current: window.map { Self.traits(of: $0.traitCollection) } ?? .none,
            overridable: overridable
        )
    }

    /// P-ENV-02: replaces every override with `traits`, which `refusal(of:overridable:)` let
    /// through, on `windows` and on the windows that appear later. A kind no longer overridden
    /// goes back to the app's own value. No implicit animations; the windows are laid out.
    func replace(with traits: Traits, windows: [UIWindow]) {
        let touched = overrides.specifiedKinds.union(traits.specifiedKinds)
        overrides = traits
        settle(windows) {
            for window in windows { apply(to: window, kinds: touched) }
        }
        if overrides.specifiedKinds.isEmpty {
            forget()
        } else {
            observeWindows()
        }
    }

    /// P-ENV-03: every window back to its own values; nothing is overridden any more.
    func removeAll() {
        let touched = overrides.specifiedKinds
        overrides = .none
        let windows = owns.values.compactMap(\.window)
        settle(windows) {
            for window in windows { apply(to: window, kinds: touched) }
        }
        forget()
    }

    // MARK: - Windows

    /// Sets each kind of `kinds` on `window`: the override, or else the app's own value.
    private func apply(to window: UIWindow, kinds: Set<TraitKind>) {
        let key = ObjectIdentifier(window)
        if owns[key]?.window !== window { owns[key] = own(of: window) }
        guard let own = owns[key] else { return }
        if kinds.contains(.userInterfaceStyle) {
            window.overrideUserInterfaceStyle = Self.uiStyle(overrides.userInterfaceStyle) ?? own.style
        }
        guard #available(iOS 17, *), method == .traitOverrides else { return }
        if kinds.contains(.contentSizeCategory) {
            if let value = Self.uiContentSizeCategory(overrides.contentSizeCategory) ?? own.contentSizeCategory {
                window.traitOverrides.preferredContentSizeCategory = value
            } else {
                window.traitOverrides.remove(UITraitPreferredContentSizeCategory.self)
            }
        }
        if kinds.contains(.layoutDirection) {
            if let value = Self.uiLayoutDirection(overrides.layoutDirection) ?? own.layoutDirection {
                window.traitOverrides.layoutDirection = value
            } else {
                window.traitOverrides.remove(UITraitLayoutDirection.self)
            }
        }
        if kinds.contains(.horizontalSizeClass) {
            if let value = Self.uiSizeClass(overrides.horizontalSizeClass) ?? own.horizontalSizeClass {
                window.traitOverrides.horizontalSizeClass = value
            } else {
                window.traitOverrides.remove(UITraitHorizontalSizeClass.self)
            }
        }
        if kinds.contains(.verticalSizeClass) {
            if let value = Self.uiSizeClass(overrides.verticalSizeClass) ?? own.verticalSizeClass {
                window.traitOverrides.verticalSizeClass = value
            } else {
                window.traitOverrides.remove(UITraitVerticalSizeClass.self)
            }
        }
    }

    private func own(of window: UIWindow) -> Own {
        var own = Own(window: window, style: window.overrideUserInterfaceStyle)
        if #available(iOS 17, *), method == .traitOverrides {
            let traits = window.traitOverrides
            if traits.contains(UITraitPreferredContentSizeCategory.self) {
                own.contentSizeCategory = traits.preferredContentSizeCategory
            }
            if traits.contains(UITraitLayoutDirection.self) { own.layoutDirection = traits.layoutDirection }
            if traits.contains(UITraitHorizontalSizeClass.self) { own.horizontalSizeClass = traits.horizontalSizeClass }
            if traits.contains(UITraitVerticalSizeClass.self) { own.verticalSizeClass = traits.verticalSizeClass }
        }
        return own
    }

    /// P-ENV-02: without implicit animations, and with the windows laid out after.
    private func settle(_ windows: [UIWindow], _ change: () -> Void) {
        UIView.performWithoutAnimation {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            change()
            for window in windows {
                if #available(iOS 17, *) { window.updateTraitsIfNeeded() }
                window.layoutIfNeeded()
            }
            CATransaction.commit()
        }
    }

    /// P-ENV-02: a window that appears while there are overrides gets them too.
    private func observeWindows() {
        guard windowObserver == nil else { return }
        windowObserver = NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeVisibleNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Posted and delivered on the main queue, so the window does not leave it.
            nonisolated(unsafe) let object = notification.object
            MainActor.assumeIsolated {
                guard let self, let window = object as? UIWindow else { return }
                let kinds = self.overrides.specifiedKinds
                self.settle([window]) { self.apply(to: window, kinds: kinds) }
            }
        }
    }

    private func forget() {
        owns.removeAll()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
    }

    // MARK: - Values

    private static let contentSizeCategories: [(ContentSizeCategory, UIContentSizeCategory)] = [
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

    /// `nil` for `unspecified`: not overridden.
    private static func uiStyle(_ style: UserInterfaceStyle) -> UIUserInterfaceStyle? {
        switch style {
        case .unspecified: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private static func uiContentSizeCategory(_ category: ContentSizeCategory) -> UIContentSizeCategory? {
        contentSizeCategories.first { $0.0 == category }?.1
    }

    private static func uiLayoutDirection(_ direction: LayoutDirection) -> UITraitEnvironmentLayoutDirection? {
        switch direction {
        case .unspecified: nil
        case .leftToRight: .leftToRight
        case .rightToLeft: .rightToLeft
        }
    }

    private static func uiSizeClass(_ sizeClass: SizeClass) -> UIUserInterfaceSizeClass? {
        switch sizeClass {
        case .unspecified: nil
        case .compact: .compact
        case .regular: .regular
        }
    }
}

extension TraitKind {
    /// For the messages of `NotSupported`.
    var title: String {
        switch self {
        case .userInterfaceStyle: "appearance"
        case .contentSizeCategory: "content size category"
        case .layoutDirection: "layout direction"
        case .horizontalSizeClass: "horizontal size class"
        case .verticalSizeClass: "vertical size class"
        }
    }
}
#endif
