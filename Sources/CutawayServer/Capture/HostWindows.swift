#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import UIKit

/// Lists the app's windows.
@MainActor
enum HostWindows {
    /// Every window of every connected scene, back to front (PROTOCOL.md, P-HIER-02).
    /// Hidden windows are included; windows the system keeps to itself are not.
    static func all() -> [UIWindow] {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .sorted { first, second in
                let ranks = (rank(of: first.activationState), rank(of: second.activationState))
                if ranks.0 != ranks.1 { return ranks.0 < ranks.1 }
                // Scenes come as a set; the identifier makes the order the same every time.
                return first.session.persistentIdentifier < second.session.persistentIdentifier
            }
        return scenes.flatMap { backToFront($0.windows) }
    }

    /// Orders the windows of one scene by level. Windows of the same level keep their order.
    static func backToFront(_ windows: [UIWindow]) -> [UIWindow] {
        windows.enumerated()
            .sorted { first, second in
                let levels = (first.element.windowLevel.rawValue, second.element.windowLevel.rawValue)
                return levels.0 != levels.1 ? levels.0 < levels.1 : first.offset < second.offset
            }
            .map(\.element)
    }

    /// The scene in front of the user comes last.
    private static func rank(of state: UIScene.ActivationState) -> Int {
        switch state {
        case .foregroundActive: return 3
        case .foregroundInactive: return 2
        case .background: return 1
        case .unattached: return 0
        @unknown default: return 0
        }
    }
}
#endif
