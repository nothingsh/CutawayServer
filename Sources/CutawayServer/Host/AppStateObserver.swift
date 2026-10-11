#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Follows the app's activation state through its notifications.
///
/// The state comes from which notification arrived, not from `applicationState`: while a
/// `will…` notification is delivered, that property still holds the old value.
@MainActor
final class AppStateObserver {
    private let center: NotificationCenter
    private let onChange: @Sendable (AppState) -> Void
    private var last: AppState
    private var tokens: [NSObjectProtocol] = []

    /// - Parameter onChange: called on the main thread with every state that differs from
    ///   the one before it.
    init(center: NotificationCenter, initial: AppState, onChange: @escaping @Sendable (AppState) -> Void) {
        self.center = center
        self.last = initial
        self.onChange = onChange
    }

    static func currentState() -> AppState {
        switch UIApplication.shared.applicationState {
        case .active: return .active
        case .inactive: return .inactive
        case .background: return .background
        @unknown default: return .inactive
        }
    }

    func start() {
        let states: [(Notification.Name, AppState)] = [
            (UIApplication.didBecomeActiveNotification, .active),
            (UIApplication.willResignActiveNotification, .inactive),
            (UIApplication.didEnterBackgroundNotification, .background),
            (UIApplication.willEnterForegroundNotification, .inactive)
        ]
        for (name, state) in states {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.report(state)
                }
            }
            tokens.append(token)
        }
    }

    func stop() {
        tokens.forEach(center.removeObserver)
        tokens.removeAll()
    }

    private func report(_ state: AppState) {
        guard state != last else { return }
        last = state
        onChange(state)
    }
}
#endif
