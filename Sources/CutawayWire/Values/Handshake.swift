#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

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
    public static let current = Self(major: 1, minor: 0)

    /// P-HELLO-04: the lower of the two minor versions. Only meaningful for the same major.
    public func negotiated(with peer: Self) -> Self {
        Self(major: major, minor: min(minor, peer.minor))
    }
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
