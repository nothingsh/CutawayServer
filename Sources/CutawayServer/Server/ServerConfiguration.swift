#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation

/// Everything the server takes from its surroundings. Tests replace parts of it.
struct ServerConfiguration: Sendable {
    // MARK: - Tuning

    /// PROTOCOL.md, P-TRANS-02.
    var ports = ProtocolLimits.portRange
    /// PROTOCOL.md, P-HELLO-06.
    var handshakeTimeout: TimeInterval = 5
    /// How long a connection that sent its last frame waits for the peer to close.
    var lingerTimeout: TimeInterval = 1
    /// When a running listener fails while the app is active: how soon to listen again.
    var relisten = Relisten()
    /// TCP keepalive of every accepted connection, so that a peer that went away is dropped.
    var keepalive = TCPKeepalive()
    /// The bytes that may be outstanding: handed to the connection and not yet sent, plus
    /// rendered and not yet compressed. No layer is rendered and no request is begun beyond
    /// it, so that a slow client cannot make the app hold more.
    var outstandingByteLimit = 32 * 1024 * 1024
    /// Reading stops while this many requests wait to be handled, so that a client cannot queue
    /// requests without end.
    var waitingRequestLimit = 64

    /// The two limits above, as each session gets them.
    var sessionLimits: Session.Limits {
        Session.Limits(
            outstandingByteLimit: outstandingByteLimit,
            waitingRequestLimit: waitingRequestLimit
        )
    }

    // MARK: - The host app, as seen by the server

    /// Where the app's activation notifications are observed.
    var notificationCenter: NotificationCenter = .default
    /// The app's state when the server starts; `nil` reads it from UIKit on the main thread.
    var initialAppState: AppState?
    /// What the server reads from the app and does to it.
    var hostApp: any HostApp = LiveHostApp()

    // MARK: - Settings

    /// The delays between attempts to listen again after a running listener failed.
    struct Relisten: Sendable {
        /// The delay before the first attempt.
        var initialDelay: TimeInterval = 0.5
        /// Each further attempt waits twice as long as the one before, up to this.
        var maximumDelay: TimeInterval = 30
    }
}
#endif
