#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
/// What one connection keeps of the app for as long as it lasts, made when it is accepted.
/// Every request of the connection works with it; each makes its own `RequestContext` from it.
struct ConnectionContext: Sendable {
    /// The connection's IDs (P-HIER-03). Main thread only.
    let registry: LayerRegistry
    /// The connection's overrides of the app's environment (P-ENV-01). Main thread only.
    let environment: any EnvironmentControl

    init(registry: LayerRegistry, environment: any EnvironmentControl) {
        self.registry = registry
        self.environment = environment
    }

    /// A new registry, and a new hold on the environment of `app`.
    init(for app: any HostApp) {
        self.init(registry: LayerRegistry(), environment: app.makeEnvironmentControl())
    }
}
#endif
