#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The host app as the server sees it: what the handshake says about it, its icon, its
/// layers, and changes to them. Every method uses UIKit on the main thread and returns at
/// once. `LiveHostApp` is the real one; tests replace parts of it.
protocol HostApp: Sendable {
    /// What the handshake says about the app and its device.
    @MainActor func appInfo() -> AppInfo
    /// The primary icon; `nil` when the app has none that can be drawn.
    @MainActor func iconImage() -> UIImage?
    /// Reads the layer hierarchy for one `GetHierarchy`, with the connection's registry, for a
    /// client working at the negotiated `version` (PROTOCOL.md, P-HIER-17).
    @MainActor func captureHierarchy(registry: LayerRegistry, version: ProtocolVersion) -> Hierarchy
    /// Reads the subtree for one `GetSubtree`, as `captureHierarchy` does; `nil` when the
    /// layer does not exist (PROTOCOL.md, P-HIER-11).
    @MainActor func captureSubtree(of rootID: UInt64, registry: LayerRegistry, version: ProtocolVersion)
        -> Hierarchy?
    /// Carries out one `SetAttribute` with the connection's registry (PROTOCOL.md, P-SET-01).
    @MainActor func setAttribute(_ change: SetAttribute, registry: LayerRegistry)
        -> Result<SetAttributeResult, WireError>
    /// Captures one layer for a `GetLayerDetails`, with the connection's registry; `nil`
    /// when the stream's stop flag was set first.
    @MainActor func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        registry: LayerRegistry,
        stopFlag: StopFlag
    ) -> CapturedDetail?
    /// The environment for a `GetEnvironment`, with the connection's overrides (PROTOCOL.md,
    /// P-ENV-01).
    @MainActor func environment(overrides: EnvironmentOverrides) -> Environment
    /// Replaces the connection's overrides for a `SetEnvironment`, or refuses and changes
    /// nothing (PROTOCOL.md, P-ENV-02, P-ENV-04, P-APP-01).
    @MainActor func setEnvironment(_ traits: Traits, overrides: EnvironmentOverrides)
        -> Result<Environment, WireError>
    /// Removes the connection's overrides when it closes (PROTOCOL.md, P-ENV-03).
    @MainActor func removeOverrides(_ overrides: EnvironmentOverrides)
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

    /// - Parameter infoDictionary: The host app's Info.plist; `nil` reads the bundle's own.
    init(
        infoDictionary: [String: Any]? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        plist = InfoPlist(infoDictionary ?? Bundle.main.infoDictionary ?? [:])
        self.environment = environment
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
    func captureHierarchy(registry: LayerRegistry, version: ProtocolVersion) -> Hierarchy {
        HierarchyCapture.capture(windows: HostWindows.all(), registry: registry, version: version)
    }

    @MainActor
    func captureSubtree(of rootID: UInt64, registry: LayerRegistry, version: ProtocolVersion) -> Hierarchy? {
        HierarchyCapture.captureSubtree(
            rootID: rootID,
            windows: HostWindows.all(),
            registry: registry,
            version: version
        )
    }

    @MainActor
    func setAttribute(_ change: SetAttribute, registry: LayerRegistry)
        -> Result<SetAttributeResult, WireError> {
        AttributeEditing.apply(
            change,
            windows: HostWindows.all(),
            registry: registry,
            appState: AppStateObserver.currentState()
        )
    }

    @MainActor
    func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        registry: LayerRegistry,
        stopFlag: StopFlag
    ) -> CapturedDetail? {
        let windows = HostWindows.all()
        let reading = AttributeReading(registry: registry, windows: windows)
        return DetailCapture.capture(
            request,
            maxTextureDimension: maxTextureDimension,
            windows: windows,
            registry: registry,
            stopFlag: stopFlag,
            readAttributes: { AttributeCatalog.standard.read($0, reading: reading) }
        )
    }

    @MainActor
    func environment(overrides: EnvironmentOverrides) -> Environment {
        overrides.environment(windows: HostWindows.all())
    }

    @MainActor
    func setEnvironment(_ traits: Traits, overrides: EnvironmentOverrides) -> Result<Environment, WireError> {
        // P-APP-01 before P-ENV-04, as the state is checked again here (see `setAttribute`).
        guard AppStateObserver.currentState() == .active else { return .failure(.appNotActive) }
        if let refusal = EnvironmentOverrides.refusal(of: traits, overridable: overrides.overridable) {
            return .failure(refusal)
        }
        let windows = HostWindows.all()
        overrides.replace(with: traits, windows: windows)
        return .success(overrides.environment(windows: windows))
    }

    @MainActor
    func removeOverrides(_ overrides: EnvironmentOverrides) {
        overrides.removeAll()
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
