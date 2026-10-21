#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The overrides of the app's trait environment that one connection set, and the values of
/// the app's own they replaced (PROTOCOL.md, P-ENV-01 to 05). Overrides go on the app's
/// windows, so that they win over what the app sets on its windows and scenes, and lose to
/// what its view controllers and views set.
///
/// Created on the server queue with the session, used on the main thread. The windows are the
/// app's (`HostWindows`) unless a test gives its own.
@MainActor
final class EnvironmentOverrides: EnvironmentControl {
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

    /// One of the four kinds that go through `traitOverrides` (iOS 17 and later): where the
    /// window keeps it, where `Own` keeps the app's value, and the value a client asked for.
    @available(iOS 17, *)
    private struct TraitSlot {
        let kind: TraitKind
        /// Sets the override, or else the app's own value, or removes the trait when the app
        /// had none.
        let apply: (_ overrides: Traits, _ own: Own, _ traits: inout UITraitOverrides) -> Void
        /// Records the app's own value, when it has one.
        let record: (_ traits: UITraitOverrides, _ own: inout Own) -> Void

        /// - Parameters:
        ///   - read: Used only once `traits` is known to contain the trait: reading a trait that
        ///     is not overridden raises an exception.
        ///   - write: A setter of its own: writing through a key path would read the trait first.
        init<Value>(
            _ kind: TraitKind,
            _ trait: UITrait,
            read: KeyPath<UITraitOverrides, Value>,
            write: @escaping (inout UITraitOverrides, Value) -> Void,
            own ownPath: WritableKeyPath<Own, Value?>,
            requested: @escaping (Traits) -> Value?
        ) {
            self.kind = kind
            apply = { overrides, own, traits in
                if let value = requested(overrides) ?? own[keyPath: ownPath] {
                    write(&traits, value)
                } else {
                    traits.remove(trait)
                }
            }
            record = { traits, own in
                if traits.contains(trait) { own[keyPath: ownPath] = traits[keyPath: read] }
            }
        }

        @MainActor static let all: [Self] = {
            [
                Self(
                    .contentSizeCategory,
                    UITraitPreferredContentSizeCategory.self,
                    read: \.preferredContentSizeCategory,
                    write: { $0.preferredContentSizeCategory = $1 },
                    own: \.contentSizeCategory,
                    requested: { EnvironmentOverrides.uiContentSizeCategory($0.contentSizeCategory) }
                ),
                Self(
                    .layoutDirection,
                    UITraitLayoutDirection.self,
                    read: \.layoutDirection,
                    write: { $0.layoutDirection = $1 },
                    own: \.layoutDirection,
                    requested: { EnvironmentOverrides.uiLayoutDirection($0.layoutDirection) }
                ),
                Self(
                    .horizontalSizeClass,
                    UITraitHorizontalSizeClass.self,
                    read: \.horizontalSizeClass,
                    write: { $0.horizontalSizeClass = $1 },
                    own: \.horizontalSizeClass,
                    requested: { EnvironmentOverrides.uiSizeClass($0.horizontalSizeClass) }
                ),
                Self(
                    .verticalSizeClass,
                    UITraitVerticalSizeClass.self,
                    read: \.verticalSizeClass,
                    write: { $0.verticalSizeClass = $1 },
                    own: \.verticalSizeClass,
                    requested: { EnvironmentOverrides.uiSizeClass($0.verticalSizeClass) }
                )
            ]
        }()
    }

    /// P-ENV-02: the turns of the main run loop the app gets to respond to a `SetEnvironment`
    /// before the windows are settled: the two the protocol asks for, and one more for work
    /// that goes through the main queue three times (a block that posts a notification whose
    /// observer is on the main queue, for example).
    nonisolated static let responseTurns = 3

    let method: Method
    /// What the client set on this connection. Read by the tests.
    private(set) var overrides = Traits.none
    /// Keyed by the window's address; an entry counts only while its weak reference is still
    /// that window. The entries of released windows are dropped at each change.
    private var owns: [ObjectIdentifier: Own] = [:]
    private var windowObserver: NSObjectProtocol?
    /// The windows `EnvironmentControl` works on, back to front.
    private let windows: @MainActor @Sendable () -> [UIWindow]

    /// - Parameters:
    ///   - method: `nil` takes the one of the system the app runs on; tests choose.
    ///   - windows: The windows to override, read each time; the app's unless a test gives some.
    nonisolated init(
        method: Method? = nil,
        windows: @escaping @MainActor @Sendable () -> [UIWindow] = HostWindows.all
    ) {
        self.windows = windows
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
            if traits.unknownKinds.contains(kind) { return .unknownTraitValue(kind) }
            if !overridable.contains(kind) { return .traitNotOverridable(kind) }
        }
        return nil
    }

    // MARK: - EnvironmentControl

    func read() -> Environment {
        environment(windows: windows())
    }

    func apply(_ traits: Traits) -> Result<Void, WireError> {
        if let refusal = Self.refusal(of: traits, overridable: overridable) { return .failure(refusal) }
        replace(with: traits, windows: windows())
        return .success(())
    }

    func settle() -> Environment {
        // The app may have added windows while it responded.
        let windows = windows()
        finish(windows: windows)
        return environment(windows: windows)
    }

    // MARK: - Overriding

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
        forgetReleasedWindows()
        changeWithoutAnimation(.traits, layingOut: windows) {
            for window in windows { apply(to: window, kinds: touched) }
        }
        if overrides.specifiedKinds.isEmpty {
            forget()
        } else {
            observeWindows()
        }
    }

    /// P-ENV-02: after the app responded to the changed traits, `windows` are laid out and
    /// the changes committed, so that what is captured next shows them.
    func finish(windows: [UIWindow]) {
        changeWithoutAnimation(.traits, layingOut: windows) {}
        CATransaction.flush()
    }

    /// P-ENV-03: every window back to its own values; nothing is overridden any more.
    func removeAll() {
        guard !owns.isEmpty || !overrides.specifiedKinds.isEmpty else { return }
        let touched = overrides.specifiedKinds
        overrides = .none
        let windows = owns.values.compactMap(\.window)
        changeWithoutAnimation(.traits, layingOut: windows) {
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
        for slot in TraitSlot.all where kinds.contains(slot.kind) {
            slot.apply(overrides, own, &window.traitOverrides)
        }
    }

    private func own(of window: UIWindow) -> Own {
        var own = Own(window: window, style: window.overrideUserInterfaceStyle)
        if #available(iOS 17, *), method == .traitOverrides {
            let traits = window.traitOverrides
            for slot in TraitSlot.all { slot.record(traits, &own) }
        }
        return own
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
                self.forgetReleasedWindows()
                changeWithoutAnimation(.traits, layingOut: [window]) { self.apply(to: window, kinds: kinds) }
            }
        }
    }

    /// The windows whose own values are recorded, released ones included. Read by the tests.
    var recordedWindowCount: Int { owns.count } // swiftlint:disable:this unused_declaration

    /// Drops the entries of released windows: one is added for each window that appears while
    /// there are overrides, and nothing is put back on a released window.
    private func forgetReleasedWindows() {
        owns = owns.filter { $0.value.window != nil }
    }

    private func forget() {
        owns.removeAll()
        if let windowObserver { NotificationCenter.default.removeObserver(windowObserver) }
        windowObserver = nil
    }
}
#endif
