#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// What one request reads and changes the app with, made on the main thread when the request's
/// work begins there and dropped when it ends. The captures, the attribute groups and the
/// changes of one request share it, so that the windows are listed once and what the host app
/// registered is looked up once for each class.
@MainActor
struct RequestContext {
    /// The app's windows, back to front; a layer in none of them does not exist (P-HIER-12).
    let windows: [UIWindow]
    /// The connection's IDs (P-HIER-03).
    let registry: LayerRegistry
    /// The version negotiated in the handshake (P-HELLO-04).
    let version: ProtocolVersion
    /// What the host app registered through the extension interface, as this request finds it.
    let extensions: ExtensionLookup
    /// What the request worked out once and keeps until it ends.
    let memo: RequestMemo

    /// - Parameter memo: The request's; a new one unless the request spans several contexts,
    ///   as a details stream does.
    init(
        windows: [UIWindow],
        registry: LayerRegistry,
        version: ProtocolVersion,
        extensions: ExtensionStore,
        memo: RequestMemo = RequestMemo()
    ) {
        self.windows = windows
        self.registry = registry
        self.version = version
        self.extensions = ExtensionLookup(store: extensions)
        self.memo = memo
    }
}
#endif
