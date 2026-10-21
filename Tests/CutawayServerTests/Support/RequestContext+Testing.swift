import CutawayWire
import UIKit

@testable import CutawayServer

// Requests without a session: the tests make the context a session's host would, with the
// windows and the registry they choose.

@MainActor
extension RequestContext {
    /// A request's context, by default for a client of the current version and with nothing
    /// registered by the host app.
    static func testing(
        windows: [UIWindow],
        registry: LayerRegistry,
        version: ProtocolVersion = .current,
        extensions: ExtensionStore? = nil
    ) -> RequestContext {
        RequestContext(
            windows: windows,
            registry: registry,
            version: version,
            extensions: extensions ?? ExtensionStore()
        )
    }
}
