#if !canImport(UIKit) || DEBUG || ReleaseEnabled

// The handshake (PROTOCOL.md, "Handshake and versions").

/// A protocol version (PROTOCOL.md, "Handshake and versions").
public struct ProtocolVersion: Sendable, Equatable {
    public var major: UInt16
    public var minor: UInt16

    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }

    /// The version this build speaks.
    public static let current = Self(major: 1, minor: 2)

    /// P-HELLO-04: the lower of the two minor versions. Only meaningful for the same major.
    public func negotiated(with peer: Self) -> Self {
        Self(major: major, minor: min(minor, peer.minor))
    }
}

// MARK: - Features

// What a peer working at a version has, named by feature, so that a check reads as what it is
// about rather than as a number. Values added to a table (sections, units, value kinds, guide
// kinds, clusters) are matched by their own `minorVersion` instead.
extension ProtocolVersion {
    /// Whether the version has what protocol 1.`added` added. A later major version is taken to
    /// have it, an earlier one not.
    private func includes(minor added: UInt16) -> Bool {
        major > 1 || (major == 1 && minor >= added)
    }

    // Protocol 1.1.

    /// The addresses of a node's layer, view and view controller (P-HIER-14).
    public var supportsAddresses: Bool { includes(minor: 1) }

    /// The origins of a node's classes and the visibility of its view controller (P-HIER-16,
    /// P-HIER-18).
    public var supportsClassOrigins: Bool { includes(minor: 1) }

    /// The section, limits, cluster, inactive cause and unit of an attribute (P-ATTR-08 to
    /// P-ATTR-14).
    public var supportsAttributeMetadata: Bool { includes(minor: 1) }

    /// The class that declares an attribute group's properties (P-ATTR-16).
    public var supportsGroupClassNames: Bool { includes(minor: 1) }

    /// The kind of a layout guide (P-LAYOUT-04).
    public var supportsGuideKinds: Bool { includes(minor: 1) }

    /// Whether UIKit created a constraint (P-LAYOUT-09).
    public var supportsConstraintOrigins: Bool { includes(minor: 1) }

    // Protocol 1.2.

    /// Virtual nodes in hierarchies and subtrees (P-HIER-19 to P-HIER-22).
    public var supportsVirtualNodes: Bool { includes(minor: 2) }

    /// The detail status `Excluded` (P-DET-10). Without it a node excluded from images is
    /// `CaptureFailed` or `Ok`.
    public var supportsExcludedStatus: Bool { includes(minor: 2) }
}

public enum Role: Sendable, Equatable {
    case client
    case server
}

public enum DeviceKind: Sendable, Equatable {
    case unknown
    case phone
    case pad
    case mac
}

/// Strings that are absent on the wire read as empty strings.
public struct ClientInfo: Sendable, Equatable {
    public var name: String
    public var version: String

    public init(name: String, version: String) {
        self.name = name
        self.version = version
    }
}

/// Strings that are absent on the wire read as empty strings.
public struct AppInfo: Sendable, Equatable {
    public var name: String
    public var bundleID: String
    public var appVersion: String
    public var deviceName: String
    public var deviceKind: DeviceKind
    public var isSimulator: Bool
    public var osName: String
    public var osVersion: String
    public var screenSize: WireSize
    public var screenScale: Float
    public var serverVersion: String

    public init(
        name: String,
        bundleID: String,
        appVersion: String,
        deviceName: String,
        deviceKind: DeviceKind,
        isSimulator: Bool,
        osName: String,
        osVersion: String,
        screenSize: WireSize,
        screenScale: Float,
        serverVersion: String
    ) {
        self.name = name
        self.bundleID = bundleID
        self.appVersion = appVersion
        self.deviceName = deviceName
        self.deviceKind = deviceKind
        self.isSimulator = isSimulator
        self.osName = osName
        self.osVersion = osVersion
        self.screenSize = screenSize
        self.screenScale = screenScale
        self.serverVersion = serverVersion
    }
}

public struct Hello: Sendable, Equatable {
    /// `nil` when the `protocol` field is absent on the wire.
    public var version: ProtocolVersion?
    public var role: Role
    public var client: ClientInfo?
    public var app: AppInfo?

    public init(version: ProtocolVersion?, role: Role, client: ClientInfo? = nil, app: AppInfo? = nil) {
        self.version = version
        self.role = role
        self.client = client
        self.app = app
    }
}

public enum AppState: Sendable, Equatable {
    case active
    case inactive
    case background
}
#endif
