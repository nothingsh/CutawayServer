#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import Foundation

/// The delays between attempts to listen again after the listener failed while the app was
/// active. Only arithmetic: the caller passes the time in.
struct RelistenBackoff {
    private let settings: ServerConfiguration.Relisten
    private var delay: TimeInterval
    private var listeningSince: Date?

    init(_ settings: ServerConfiguration.Relisten) {
        self.settings = settings
        delay = settings.initialDelay
    }

    /// The delay before the next attempt. Each call doubles the one after, up to the maximum.
    /// A listener that ran for at least the maximum delay before it failed counts as a new
    /// failure, not as one more of a series: the delays start over.
    mutating func nextDelay(now: Date) -> TimeInterval {
        if let since = listeningSince, now.timeIntervalSince(since) >= settings.maximumDelay {
            delay = settings.initialDelay
        }
        listeningSince = nil
        let next = delay
        delay = min(delay * 2, settings.maximumDelay)
        return next
    }

    /// A listener became ready at `now`.
    mutating func recordListening(since now: Date) {
        listeningSince = now
    }

    /// Back to the first delay.
    mutating func reset() {
        delay = settings.initialDelay
        listeningSince = nil
    }
}
#endif
