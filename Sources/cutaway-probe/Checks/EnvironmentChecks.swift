import CutawayWire
import Foundation

/// What the answers about the environment have to look like (PROTOCOL.md, P-ENV-01, 02).
enum EnvironmentChecks {
    /// P-ENV-01: the answer to `GetEnvironment` or `SetEnvironment` is an `Environment` whose
    /// `overridable` lists each kind once.
    static func environment(_ frame: Frame, answering what: String) throws -> Environment {
        guard case .environment(let environment)? = frame.body else {
            throw ProbeFailure("expected Environment in answer to \(what), got \(Checks.describe(frame)) (P-ENV-01)")
        }
        let kinds = environment.overridable
        if let twice = kinds.first(where: { kind in kinds.filter { $0 == kind }.count > 1 }) {
            throw ProbeFailure("the Environment answering \(what) lists \(twice) twice in overridable (P-ENV-01)")
        }
        return environment
    }

    /// P-ENV-02: after the appearance was overridden to dark, the override and the current
    /// appearance are dark.
    static func dark(_ environment: Environment) throws {
        guard environment.overrides.userInterfaceStyle == .dark else {
            throw ProbeFailure(
                "after SetEnvironment to dark, overrides has the appearance \(environment.overrides.userInterfaceStyle) (P-ENV-01)"
            )
        }
        guard environment.current.userInterfaceStyle == .dark else {
            throw ProbeFailure(
                "after SetEnvironment to dark, the current appearance is \(environment.current.userInterfaceStyle) (P-ENV-02)"
            )
        }
    }

    /// P-ENV-02: with every override removed there is none, and the traits are what they were
    /// before the probe changed them.
    static func restored(_ environment: Environment, before: Environment) throws {
        guard environment.overrides == Traits() else {
            throw ProbeFailure(
                "after SetEnvironment without overrides, overrides is \(environment.overrides) (P-ENV-02)"
            )
        }
        guard environment.current == before.current else {
            throw ProbeFailure(
                "after SetEnvironment without overrides, the traits are \(environment.current), "
                    + "but they were \(before.current) before the probe changed them (P-ENV-02)"
            )
        }
    }
}
