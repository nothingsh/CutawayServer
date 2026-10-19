import CutawayWire
import Foundation

/// What each frame of the server has to look like. Every function throws a `ProbeFailure`
/// naming the first thing that is wrong.
enum Checks {
    /// P-HELLO-04: the lower of the two minor versions, for a hello `serverHello` accepted.
    static func negotiatedVersion(_ frame: Frame?) -> ProtocolVersion {
        guard case .hello(let hello)? = frame?.body, let version = hello.version else { return .current }
        return ProtocolVersion.current.negotiated(with: version)
    }

    static func serverHello(_ frame: Frame?) throws -> AppInfo {
        guard let frame else { throw ProbeFailure("the server closed the connection before its Hello") }
        guard case .hello(let hello)? = frame.body else {
            throw ProbeFailure("expected the server's Hello, got \(describe(frame))")
        }
        guard frame.requestID == 0 else {
            throw ProbeFailure("Hello has request_id \(frame.requestID), expected 0 (P-HELLO-02)")
        }
        guard hello.role == .server else {
            throw ProbeFailure("Hello has role Client, expected Server (P-HELLO-02)")
        }
        guard let version = hello.version else {
            throw ProbeFailure("Hello has no protocol version (P-HELLO-02)")
        }
        guard version.major == ProtocolVersion.current.major else {
            throw ProbeFailure(
                "the server speaks protocol \(version.major).\(version.minor); this probe speaks "
                    + "\(ProtocolVersion.current.major).\(ProtocolVersion.current.minor) (P-HELLO-03)"
            )
        }
        guard let app = hello.app else {
            throw ProbeFailure("Hello has no app field (P-HELLO-02)")
        }
        let required = [
            ("name", app.name),
            ("bundle_id", app.bundleID),
            ("os_name", app.osName),
            ("os_version", app.osVersion),
            ("server_version", app.serverVersion)
        ]
        for (field, value) in required where value.isEmpty {
            throw ProbeFailure("Hello.app.\(field) is empty")
        }
        guard app.screenSize.width > 0, app.screenSize.height > 0, app.screenScale > 0 else {
            throw ProbeFailure("Hello.app has a screen of size 0 or scale 0")
        }
        return app
    }

    static func initialState(_ frame: Frame?) throws -> AppState {
        guard let frame else {
            throw ProbeFailure("the server closed the connection after its Hello")
        }
        guard case .appStateChanged(let state)? = frame.body, frame.requestID == 0 else {
            throw ProbeFailure(
                "expected AppStateChanged with request_id 0 right after Hello, got \(describe(frame)) (P-EVT-02)"
            )
        }
        return state
    }

    /// Returns the icon, or `nil` when the app has none.
    static func appIcon(_ frame: Frame, requiresIcon: Bool) throws -> WireImage? {
        guard case .appIcon(let icon)? = frame.body else {
            throw ProbeFailure("expected AppIcon, got \(describe(frame)) (P-ICON-01)")
        }
        guard let image = icon.image else {
            if requiresIcon { throw ProbeFailure("AppIcon has no image, and --require-icon was given") }
            return nil
        }
        try Self.image(image, name: "AppIcon.image")
        return image
    }

    static func image(_ image: WireImage, name: String) throws {
        guard image.pixelWidth > 0, image.pixelHeight > 0 else {
            throw ProbeFailure("\(name) is \(image.pixelWidth)x\(image.pixelHeight) pixels")
        }
        guard UInt64(image.bytesPerRow) >= UInt64(image.pixelWidth) * 4 else {
            throw ProbeFailure(
                "\(name) has bytes_per_row \(image.bytesPerRow), below pixel_width x 4 (P-IMG-02)"
            )
        }
        guard image.scale > 0 else { throw ProbeFailure("\(name) has scale \(image.scale)") }
        guard let pixels = try? (image.data as NSData).decompressed(using: .lzfse) else {
            throw ProbeFailure("\(name): data is not LZFSE (P-IMG-01)")
        }
        let expected = Int(image.bytesPerRow) * Int(image.pixelHeight)
        guard pixels.length == expected else {
            throw ProbeFailure(
                "\(name): data decompresses to \(pixels.length) bytes, expected bytes_per_row x pixel_height = \(expected) (P-IMG-01)"
            )
        }
    }

    static func describe(_ frame: Frame) -> String {
        let kind: String
        switch frame.body {
        case nil: kind = "a frame without a body"
        case .hello: kind = "Hello"
        case .getAppIcon: kind = "GetAppIcon"
        case .appIcon: kind = "AppIcon"
        case .getHierarchy: kind = "GetHierarchy"
        case .hierarchy: kind = "Hierarchy"
        case .getLayerDetails: kind = "GetLayerDetails"
        case .layerDetailsChunk: kind = "LayerDetailsChunk"
        case .streamEnd: kind = "StreamEnd"
        case .cancel: kind = "Cancel"
        case .error(let error): kind = "Error(\(error.code): \(error.message))"
        case .appStateChanged(let state): kind = "AppStateChanged(\(state))"
        case .setAttribute: kind = "SetAttribute"
        case .setAttributeResult: kind = "SetAttributeResult"
        case .getSubtree: kind = "GetSubtree"
        case .getEnvironment: kind = "GetEnvironment"
        case .setEnvironment: kind = "SetEnvironment"
        case .environment: kind = "Environment"
        }
        return "\(kind) with request_id \(frame.requestID)"
    }
}
