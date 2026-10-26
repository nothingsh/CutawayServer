import CutawayWire
import Foundation

/// What hierarchy change notifications have to look like (protocol 1.3; P-WATCH-01 to 03,
/// P-WATCH-08). Every function throws a `ProbeFailure` naming the first thing that is wrong.
enum WatchChecks {
    /// P-WATCH-08: two events at least this far apart, less what the network may add.
    static let shortestInterval: TimeInterval = 0.95

    /// The answer to `WatchHierarchy`: `WatchHierarchyResult` with the state asked for.
    static func answer(_ frame: Frame, to requestID: UInt32, enabled: Bool) throws {
        guard frame.requestID == requestID, case .watchHierarchyResult(let state)? = frame.body else {
            throw ProbeFailure(
                "expected WatchHierarchyResult for request \(requestID), got \(HelloChecks.describe(frame)) (P-WATCH-01)"
            )
        }
        guard state == enabled else {
            throw ProbeFailure(
                "WatchHierarchyResult says \(state), but the request turned notifications \(enabled ? "on" : "off") (P-WATCH-01)"
            )
        }
    }

    /// An event at `time` seconds, the one before it at `previous`: its roots or the whole.
    static func event(_ frame: Frame, at time: TimeInterval, previous: TimeInterval?) throws -> HierarchyChanged {
        guard frame.requestID == 0, case .hierarchyChanged(let changed)? = frame.body else {
            throw ProbeFailure(
                "expected HierarchyChanged with request_id 0, got \(HelloChecks.describe(frame)) (P-WATCH-02)"
            )
        }
        guard changed.whole == changed.roots.isEmpty else {
            throw ProbeFailure(
                changed.whole
                    ? "HierarchyChanged is whole, but has roots \(changed.roots) (P-WATCH-03)"
                    : "HierarchyChanged has no roots and is not whole (P-WATCH-03)"
            )
        }
        if let previous, time - previous < shortestInterval {
            throw ProbeFailure(
                String(format: "two HierarchyChanged %.2f s apart, less than 1 s (P-WATCH-08)", time - previous)
            )
        }
        return changed
    }

    /// One line for the probe's report.
    static func describe(_ changed: HierarchyChanged, at time: TimeInterval) -> String {
        let what = changed.whole ? "the whole hierarchy" : "roots \(changed.roots.map(String.init).joined(separator: ", "))"
        return String(format: "watch: +%.2f s: ", time) + what
    }
}
