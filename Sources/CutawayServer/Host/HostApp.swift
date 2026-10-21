#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The host app as the server sees it: what the handshake says about it, its icon, its
/// layers, and changes to them. Every method but `makeEnvironmentControl` uses UIKit on the
/// main thread and returns at once. `LiveHostApp` is the real one; tests replace parts of it.
protocol HostApp: Sendable {
    /// What the handshake says about the app and its device.
    @MainActor func appInfo() -> AppInfo
    /// The primary icon; `nil` when the app has none that can be drawn.
    @MainActor func iconImage() -> UIImage?
    /// The app's state now, which a change checks again on the main thread (P-APP-01).
    @MainActor func currentAppState() -> AppState
    /// A new hold on the app's environment, for one connection. Called on the server queue.
    func makeEnvironmentControl() -> any EnvironmentControl
    /// What one request works with: the windows now, what `connection` keeps, the negotiated
    /// `version`, what the host app registered, and the request's `memo`.
    @MainActor func makeRequestContext(
        for connection: ConnectionContext,
        version: ProtocolVersion,
        memo: RequestMemo
    ) -> RequestContext
    /// Reads the layer hierarchy for one `GetHierarchy` (PROTOCOL.md, P-HIER-01, P-HIER-17).
    @MainActor func captureHierarchy(in context: RequestContext) -> Hierarchy
    /// Reads the subtree for one `GetSubtree`, as `captureHierarchy` does; `nil` when the
    /// layer does not exist (PROTOCOL.md, P-HIER-11).
    @MainActor func captureSubtree(of rootID: UInt64, in context: RequestContext) -> Hierarchy?
    /// Carries out one `SetAttribute` (PROTOCOL.md, P-SET-01), once the app was found active.
    @MainActor func setAttribute(_ change: SetAttribute, in context: RequestContext)
        -> Result<SetAttributeResult, WireError>
    /// Captures one layer for a `GetLayerDetails`; `nil` when the stream's stop flag was set
    /// first.
    @MainActor func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        in context: RequestContext,
        stopFlag: StopFlag
    ) -> CapturedDetail?
}

/// The app the server runs in.
struct LiveHostApp: HostApp {
    /// What the server takes from the host app's Info.plist, read once at `init`.
    struct InfoPlist: Sendable, Equatable {
        var name: String
        var bundleID: String
        var appVersion: String
        /// The file names of the primary icon on a phone, best candidate first.
        var phoneIconNames: [String]
        /// The same on an iPad, which may have icons of its own.
        var padIconNames: [String]

        init(_ dictionary: [String: Any]) {
            func string(_ key: String) -> String? { dictionary[key] as? String }
            name = string("CFBundleDisplayName") ?? string("CFBundleName") ?? ""
            bundleID = string("CFBundleIdentifier") ?? ""
            appVersion = string("CFBundleShortVersionString") ?? ""
            phoneIconNames = LiveHostApp.iconNames(infoDictionary: dictionary, isPad: false)
            padIconNames = LiveHostApp.iconNames(infoDictionary: dictionary, isPad: true)
        }
    }

    private let plist: InfoPlist
    /// The process environment; the simulator puts the device name there.
    private let environment: [String: String]
    /// What the host app registered through the extension interface.
    private let extensions: ExtensionStore

    /// - Parameters:
    ///   - infoDictionary: The host app's Info.plist; `nil` reads the bundle's own.
    ///   - extensions: Where the host app's registrations are; the public methods write the
    ///     shared store.
    init(
        infoDictionary: [String: Any]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        extensions: ExtensionStore = .shared
    ) {
        plist = InfoPlist(infoDictionary ?? Bundle.main.infoDictionary ?? [:])
        self.environment = environment
        self.extensions = extensions
    }

    @MainActor
    func appInfo() -> AppInfo {
        Self.info(plist: plist, environment: environment)
    }

    @MainActor
    func iconImage() -> UIImage? {
        let names = UIDevice.current.userInterfaceIdiom == .pad ? plist.padIconNames : plist.phoneIconNames
        return names.lazy.compactMap { UIImage(named: $0) }.first { $0.cgImage != nil }
    }

    @MainActor
    func currentAppState() -> AppState {
        AppStateObserver.currentState()
    }

    func makeEnvironmentControl() -> any EnvironmentControl {
        EnvironmentOverrides()
    }

    @MainActor
    func makeRequestContext(
        for connection: ConnectionContext,
        version: ProtocolVersion,
        memo: RequestMemo
    ) -> RequestContext {
        RequestContext(
            windows: HostWindows.all(),
            registry: connection.registry,
            version: version,
            extensions: extensions,
            memo: memo
        )
    }

    @MainActor
    func captureHierarchy(in context: RequestContext) -> Hierarchy {
        HierarchyCapture.capture(context)
    }

    @MainActor
    func captureSubtree(of rootID: UInt64, in context: RequestContext) -> Hierarchy? {
        HierarchyCapture.captureSubtree(rootID: rootID, in: context)
    }

    @MainActor
    func setAttribute(_ change: SetAttribute, in context: RequestContext) -> Result<SetAttributeResult, WireError> {
        AttributeEditing.apply(change, in: context)
    }

    @MainActor
    func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        in context: RequestContext,
        stopFlag: StopFlag
    ) -> CapturedDetail? {
        let attributes = NodeAttributes(context: context)
        return DetailCapture.capture(
            request,
            maxTextureDimension: maxTextureDimension,
            in: context,
            stopFlag: stopFlag,
            readAttributes: { attributes.read($0) },
            readVirtualAttributes: { attributes.read($0) }
        )
    }

    // MARK: - Info

    @MainActor
    static func info(plist: InfoPlist, environment: [String: String]) -> AppInfo {
        let device = UIDevice.current
        let screen = UIScreen.main
        #if targetEnvironment(simulator)
        let isSimulator = true
        // UIDevice reports the Mac's model there; the simulator's own name is in the environment.
        let deviceName = environment["SIMULATOR_DEVICE_NAME"] ?? device.name
        #else
        let isSimulator = false
        let deviceName = device.name
        #endif
        return AppInfo(
            name: plist.name,
            bundleID: plist.bundleID,
            appVersion: plist.appVersion,
            deviceName: deviceName,
            deviceKind: deviceKind(for: device.userInterfaceIdiom),
            isSimulator: isSimulator,
            osName: device.systemName,
            osVersion: device.systemVersion,
            screenSize: WireSize(
                width: Double(screen.bounds.width),
                height: Double(screen.bounds.height)
            ),
            screenScale: Float(screen.scale),
            serverVersion: ServerVersion.string
        )
    }

    static func deviceKind(for idiom: UIUserInterfaceIdiom) -> DeviceKind {
        switch idiom {
        case .phone:
            return .phone
        case .pad:
            return .pad
        default:
            if #available(iOS 14.0, *), idiom == .mac { return .mac }
            return .unknown
        }
    }

    // MARK: - Icon

    /// The file names of the primary icon, best candidate first.
    ///
    /// Info.plist lists them under `CFBundleIcons` → `CFBundlePrimaryIcon` →
    /// `CFBundleIconFiles`, smallest first; an iPad build has its own `CFBundleIcons~ipad`.
    static func iconNames(infoDictionary: [String: Any], isPad: Bool) -> [String] {
        let keys = isPad ? ["CFBundleIcons~ipad", "CFBundleIcons"] : ["CFBundleIcons"]
        for key in keys {
            if let icons = infoDictionary[key] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
               let files = primary["CFBundleIconFiles"] as? [String], !files.isEmpty {
                return files.reversed()
            }
        }
        return []
    }
}
#endif
