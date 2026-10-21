import CutawayWire
import Foundation

@testable import CutawayServer

// Connections without a session: the tests make the connection's context with the registry
// they choose, so that they can give layers their IDs before the connection asks for them.

@MainActor
extension HostApp {
    /// The context of a request on a new connection whose registry is `registry`.
    func makeRequestContext(registry: LayerRegistry, version: ProtocolVersion) -> RequestContext {
        makeRequestContext(
            for: ConnectionContext(registry: registry, environment: makeEnvironmentControl()),
            version: version,
            memo: RequestMemo()
        )
    }
}

extension HostAccess {
    /// The host of a connection whose registry is `registry`, so that a test can give layers
    /// their IDs before the connection asks for them.
    init(app: any HostApp, registry: LayerRegistry, queue: DispatchQueue, encodeQueue: DispatchQueue) {
        self.init(
            app: app,
            connection: ConnectionContext(registry: registry, environment: app.makeEnvironmentControl()),
            queue: queue,
            encodeQueue: encodeQueue
        )
    }
}
