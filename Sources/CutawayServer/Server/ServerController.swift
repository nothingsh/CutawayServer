#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation
import Network

/// Owns the server queue, the listener and the one session. Decides when to listen and
/// what happens to a new connection.
final class ServerController: @unchecked Sendable {
    /// The server behind `CutawayServer.start()`.
    static let shared = ServerController(configuration: ServerConfiguration())

    private let configuration: ServerConfiguration
    /// The serial queue the state below is confined to. Read by the tests.
    let queue = DispatchQueue(label: "dev.cutaway.server", autoreleaseFrequency: .workItem)
    /// Compresses screenshots, one detail at a time and in order.
    private let encodeQueue = DispatchQueue(
        label: "dev.cutaway.server.encode",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )
    let listener: Listener
    // Everything below is confined to `queue`. The `private(set)` ones are read by the tests.
    private var isStarted = false
    /// Counts the calls to `start()` that had an effect, so that an observer made for an
    /// earlier one is not taken after a `stop()` and another `start()`.
    private var startCount = 0
    private var observer: AppStateObserver?
    private(set) var appState: AppState?
    private var lastPort: UInt16?
    /// How many attempts to listen have ended, successfully or not.
    private(set) var settledAttempts = 0
    private(set) var session: Session?
    private var backoff: RelistenBackoff
    /// True from the failure of a running listener until the server listens again or the
    /// app leaves the active state. Attempts that end without a port are then retried.
    private var isRecovering = false
    private var pendingRelisten: DispatchWorkItem?
    /// The delay of the attempt to listen again that is waiting, or `nil` (S-CONN-10).
    private(set) var pendingRelistenDelay: TimeInterval?

    init(configuration: ServerConfiguration) {
        self.configuration = configuration
        listener = Listener(
            queue: queue,
            ports: configuration.ports,
            keepalive: configuration.keepalive
        )
        backoff = RelistenBackoff(configuration.relisten)
        listener.delegate = self
    }

    /// Safe on any thread. Only the first call has an effect.
    func start() {
        queue.async {
            guard !self.isStarted else { return }
            self.isStarted = true
            self.startCount += 1
            self.observeAppState()
        }
    }

    // MARK: - App state

    private func observeAppState() {
        let configuration = self.configuration
        let queue = self.queue
        let startCount = self.startCount
        // Nothing of UIKit is read on the caller's thread: start() may run before the
        // application object exists, and the main queue only runs once it does.
        onMain {
            let initial = configuration.initialAppState ?? AppStateObserver.currentState()
            // The observer and the controller hold each other until stop() lets the observer go.
            let observer = AppStateObserver(center: configuration.notificationCenter, initial: initial) { state in
                queue.async { self.appStateDidChange(state, notifyingSession: true) }
            }
            observer.start()
            queue.async {
                guard self.isStarted, self.startCount == startCount else {
                    onMain { observer.stop() }
                    return
                }
                self.observer = observer
                self.appStateDidChange(initial, notifyingSession: false)
            }
        }
    }

    private func appStateDidChange(_ state: AppState, notifyingSession: Bool) {
        guard isStarted else { return }
        appState = state
        // Retries belong to one stretch of activity; a new one starts with the first delay.
        cancelRelisten()
        isRecovering = false
        // P-TRANS-02: every time the app becomes active, make sure the server listens.
        // It keeps listening when the app leaves the active state.
        if state == .active {
            backoff.reset()
            if !listener.isRunning {
                listener.start(preferring: lastPort)
            }
        }
        if notifyingSession {
            session?.appStateDidChange(state)
        }
    }

    // MARK: - Listening again

    private func scheduleRelisten() {
        cancelRelisten()
        let delay = backoff.nextDelay(now: Date())
        let work = DispatchWorkItem { [weak self] in self?.relisten() }
        pendingRelisten = work
        pendingRelistenDelay = delay
        queue.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelRelisten() {
        pendingRelisten?.cancel()
        pendingRelisten = nil
        pendingRelistenDelay = nil
    }

    private func relisten() {
        pendingRelisten = nil
        pendingRelistenDelay = nil
        guard isStarted, appState == .active, !listener.isRunning else { return }
        // P-TRANS-04: the previous port first.
        listener.start(preferring: lastPort)
    }

    // MARK: - Connections

    private func accept(_ nwConnection: NWConnection) {
        let connection = Connection(
            nwConnection,
            queue: queue,
            lingerTimeout: configuration.lingerTimeout
        )
        guard session == nil else {
            // P-TRANS-03: one client at a time.
            connection.start()
            connection.finish(with: Frame(requestID: 0, body: .error(.busy)))
            return
        }
        // P-HIER-03: layer IDs are stable within one connection, so each session has its own.
        let host = HostAccess(
            app: configuration.hostApp,
            registry: LayerRegistry(),
            queue: queue,
            encodeQueue: encodeQueue
        )
        let session = Session(
            transport: connection,
            host: host,
            queue: queue,
            appState: appState ?? .inactive,
            limits: configuration.sessionLimits
        )
        session.delegate = self
        self.session = session
        session.start(handshakeTimeout: configuration.handshakeTimeout)
    }
}

extension ServerController: ListenerDelegate {
    func listenerDidAccept(_ connection: NWConnection) {
        accept(connection)
    }

    func listenerDidSettle(on port: UInt16?) {
        settledAttempts += 1
        if let port {
            lastPort = port
            isRecovering = false
            backoff.recordListening(since: Date())
        } else if isRecovering {
            scheduleRelisten()
        }
    }

    func listenerDidFail() {
        // S-CONN-10: listen again while the app is active. Otherwise the next activation does.
        guard isStarted, appState == .active else { return }
        isRecovering = true
        scheduleRelisten()
    }
}

extension ServerController: SessionDelegate {
    func sessionDidEnd(_ session: Session) {
        guard self.session === session else { return }
        self.session = nil
    }
}

// MARK: - Stopping

extension ServerController {
    /// Stops listening and drops the session, so that `start()` works again. Returns once the
    /// port is released and the app's state is no longer observed.
    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.isStarted = false
                self.cancelRelisten()
                self.session?.stop()
                self.session = nil
                self.appState = nil
                let observer = self.observer
                self.observer = nil
                self.listener.cancel {
                    onMain {
                        observer?.stop()
                        continuation.resume()
                    }
                }
            }
        }
    }
}
#endif
