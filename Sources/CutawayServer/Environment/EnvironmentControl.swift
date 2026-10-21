#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire

/// One connection's hold on the app's trait environment (PROTOCOL.md, P-ENV-01 to 05): what it
/// overrides, and how to give the app its own values back. Made for the connection when it is
/// accepted, used on the main thread. `EnvironmentOverrides` is the real one; tests script one
/// that touches no window.
@MainActor
protocol EnvironmentControl: AnyObject, Sendable {
    /// P-ENV-01: the connection's overrides, the traits the app has now, and what can be
    /// overridden here.
    func read() -> Environment
    /// P-ENV-02, P-ENV-04: replaces every override with `traits`, or refuses them and changes
    /// nothing.
    func apply(_ traits: Traits) -> Result<Void, WireError>
    /// P-ENV-02: once the app has responded to what `apply` changed, makes the change show in
    /// what is captured next, and reads the environment for the answer.
    func settle() -> Environment
    /// P-ENV-03: gives the app its own values back; nothing is overridden any more.
    func removeAll()
}
#endif
