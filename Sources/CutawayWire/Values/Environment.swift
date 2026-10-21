#if !canImport(UIKit) || DEBUG || ReleaseEnabled

// The value types of the environment (PROTOCOL.md, "Environment", protocol 1.2). The raw
// values are the protocol's.

/// `unspecified` means not overridden, or, in `Environment.current`, not readable (P-ENV-01).
public enum UserInterfaceStyle: UInt8, Sendable, Equatable, CaseIterable {
    case unspecified = 0
    case light
    case dark
}

public enum ContentSizeCategory: UInt8, Sendable, Equatable, CaseIterable {
    case unspecified = 0
    case extraSmall
    case small
    case medium
    case large
    case extraLarge
    case extraExtraLarge
    case extraExtraExtraLarge
    case accessibilityMedium
    case accessibilityLarge
    case accessibilityExtraLarge
    case accessibilityExtraExtraLarge
    case accessibilityExtraExtraExtraLarge
}

public enum LayoutDirection: UInt8, Sendable, Equatable, CaseIterable {
    case unspecified = 0
    case leftToRight
    case rightToLeft
}

public enum SizeClass: UInt8, Sendable, Equatable, CaseIterable {
    case unspecified = 0
    case compact
    case regular
}

/// The kinds of trait a client may override, in the order of the fields of `Traits`.
public enum TraitKind: UInt8, Sendable, Equatable, CaseIterable {
    case userInterfaceStyle = 0
    case contentSizeCategory
    case layoutDirection
    case horizontalSizeClass
    case verticalSizeClass
}

/// One value for each kind of trait.
public struct Traits: Sendable, Equatable {
    public var userInterfaceStyle: UserInterfaceStyle
    public var contentSizeCategory: ContentSizeCategory
    public var layoutDirection: LayoutDirection
    public var horizontalSizeClass: SizeClass
    public var verticalSizeClass: SizeClass
    /// The kinds whose value on the wire this build does not know; their field above reads
    /// `unspecified`. Only decoding sets it, and it is never encoded: a server refuses such a
    /// value (P-ENV-04) and so never sends one.
    public var unknownKinds: Set<TraitKind>

    public init(
        userInterfaceStyle: UserInterfaceStyle = .unspecified,
        contentSizeCategory: ContentSizeCategory = .unspecified,
        layoutDirection: LayoutDirection = .unspecified,
        horizontalSizeClass: SizeClass = .unspecified,
        verticalSizeClass: SizeClass = .unspecified,
        unknownKinds: Set<TraitKind> = []
    ) {
        self.userInterfaceStyle = userInterfaceStyle
        self.contentSizeCategory = contentSizeCategory
        self.layoutDirection = layoutDirection
        self.horizontalSizeClass = horizontalSizeClass
        self.verticalSizeClass = verticalSizeClass
        self.unknownKinds = unknownKinds
    }

    /// Every trait `unspecified`: nothing overridden.
    public static let none = Self()

    /// Some trait has a value this build knows, other than `unspecified`.
    public var hasKnownValues: Bool {
        !specifiedKinds.subtracting(unknownKinds).isEmpty
    }

    /// The kinds with a value other than `unspecified`, the unknown ones included.
    public var specifiedKinds: Set<TraitKind> {
        var kinds = unknownKinds
        if userInterfaceStyle != .unspecified { kinds.insert(.userInterfaceStyle) }
        if contentSizeCategory != .unspecified { kinds.insert(.contentSizeCategory) }
        if layoutDirection != .unspecified { kinds.insert(.layoutDirection) }
        if horizontalSizeClass != .unspecified { kinds.insert(.horizontalSizeClass) }
        if verticalSizeClass != .unspecified { kinds.insert(.verticalSizeClass) }
        return kinds
    }
}

/// The answer to `GetEnvironment` and `SetEnvironment` (P-ENV-01).
public struct Environment: Sendable, Equatable {
    /// What the client set on this connection.
    public var overrides: Traits
    /// The key window's effective traits, overrides included.
    public var current: Traits
    /// The kinds this server can override on this device, each once.
    public var overridable: [TraitKind]

    public init(overrides: Traits, current: Traits, overridable: [TraitKind]) {
        self.overrides = overrides
        self.current = current
        self.overridable = overridable
    }
}
#endif
