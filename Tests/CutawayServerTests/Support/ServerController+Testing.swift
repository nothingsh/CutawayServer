import CutawayWire
import Foundation
import Network

@testable import CutawayServer

// What the tests observe and simulate on the server, its listener and its connection. The
// state read here is `private(set)` in the production types for this purpose.

extension ServerController {
    /// What tests ask about the listener.
    struct ListeningStatus: Sendable, Equatable {
        /// The port being listened on, or `nil`.
        var port: UInt16?
        /// How many attempts to listen have ended, successfully or not.
        var settledAttempts: Int
        /// The app's state as the server knows it; `nil` until the first reading arrived.
        var appState: AppState?
        /// The delay of the attempt to listen again that is waiting, or `nil` (S-CONN-10).
        var pendingRelistenDelay: TimeInterval?
    }

    func listeningStatus() async -> ListeningStatus {
        await onQueue {
            ListeningStatus(
                port: self.listener.port,
                settledAttempts: self.settledAttempts,
                appState: self.appState,
                pendingRelistenDelay: self.pendingRelistenDelay
            )
        }
    }

    /// Fails the running listener the way the system would.
    func simulateListenerFailure() async {
        await onQueue { self.listener.simulateFailure() }
    }

    /// The keepalive settings of the session's connection, or `nil` without one.
    func connectionKeepalive() async -> TCPKeepalive? {
        await onQueue { self.connection?.keepalive }
    }

    /// The bytes the session's connection has not sent yet, or `nil` without one (S-CONN-13).
    func connectionUnsentByteCount() async -> Int? {
        await onQueue { self.connection?.unsentByteCount }
    }

    /// The session, or `nil` without one. Tests hold it weakly (S-STAB-02).
    func currentSession() async -> Session? {
        await onQueue { self.session }
    }

    /// Fails the session's connection the way unanswered keepalive probes would.
    func simulateConnectionFailure() async {
        await onQueue { self.connection?.simulateFailure() }
    }

    /// The session's connection, or `nil` without one. Call on the server queue.
    private var connection: Connection? {
        session?.transport as? Connection
    }

    /// Runs `body` on the server queue and returns what it gives.
    private func onQueue<Value: Sendable>(_ body: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: body()) }
        }
    }
}

extension Listener {
    /// Handles the running listener as if the system had failed it. Does nothing while no
    /// listener is running. Call on the server queue.
    func simulateFailure() {
        guard isRunning, port != nil else { return }
        runningListenerFailed()
    }
}

extension Connection {
    /// Handles the connection as if keepalive had given up on the peer. Call on the server
    /// queue.
    func simulateFailure() {
        handle(.failed(.posix(.ETIMEDOUT)))
    }

    /// The keepalive settings the connection was accepted with.
    var keepalive: TCPKeepalive? {
        guard let tcp = nwConnection.parameters.defaultProtocolStack.transportProtocol
            as? NWProtocolTCP.Options, tcp.enableKeepalive
        else { return nil }
        return .init(idle: tcp.keepaliveIdle, interval: tcp.keepaliveInterval, count: tcp.keepaliveCount)
    }
}
