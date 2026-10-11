#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import Foundation
import Network

/// Told about a listener, on the server queue.
protocol ListenerDelegate: AnyObject {
    /// An accepted connection; the delegate starts it.
    func listenerDidAccept(_ connection: NWConnection)
    /// An attempt to listen ended: on `port`, or `nil` when every port of the range was taken.
    func listenerDidSettle(on port: UInt16?)
    /// A listener that had been running failed; it is down now.
    func listenerDidFail()
}

/// TCP keepalive of every accepted connection (S-CONN-11): a peer that stops answering is
/// dropped after `idle + interval * count` seconds.
struct TCPKeepalive: Sendable, Equatable {
    /// Seconds without traffic before the first probe.
    var idle = 10
    /// Seconds between probes.
    var interval = 5
    /// Unanswered probes before the connection is dropped.
    var count = 3
}

/// Listens on the IPv4 loopback address, on the first free port of a range
/// (PROTOCOL.md, P-TRANS-01 and P-TRANS-02). Confined to the server queue.
final class Listener: @unchecked Sendable {
    private let queue: DispatchQueue
    private let ports: ClosedRange<UInt16>
    private let keepalive: TCPKeepalive
    private var nwListener: NWListener?
    /// Callbacks of a listener that was replaced or cancelled carry an old number.
    private var generation = 0

    /// The port in use, or `nil` while no port is bound.
    private(set) var port: UInt16?
    /// Told about connections, attempts and failures. Held weakly.
    weak var delegate: ListenerDelegate?

    init(
        queue: DispatchQueue,
        ports: ClosedRange<UInt16>,
        keepalive: TCPKeepalive = .init()
    ) {
        self.queue = queue
        self.ports = ports
        self.keepalive = keepalive
    }

    /// TCP on the IPv4 loopback address and `port`, with keepalive. Accepted connections
    /// take their parameters from these.
    static func parameters(port: UInt16, keepalive: TCPKeepalive) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = keepalive.idle
        tcp.keepaliveInterval = keepalive.interval
        tcp.keepaliveCount = keepalive.count
        let parameters = NWParameters(tls: nil, tcp: tcp)
        // The only place that names the address: loopback, IPv4.
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port) ?? .any
        )
        return parameters
    }

    /// True from `start` until the listener fails or is cancelled.
    var isRunning: Bool { nwListener != nil }

    /// Tries `preferred` first, then every port of the range in order. Does nothing while a
    /// listener is running.
    func start(preferring preferred: UInt16?) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard nwListener == nil else { return }
        var candidates = Array(ports)
        if let preferred, let index = candidates.firstIndex(of: preferred) {
            candidates.remove(at: index)
            candidates.insert(preferred, at: 0)
        }
        attempt(candidates[...])
    }

    /// Stops listening. `completion` runs on the server queue once the port is released,
    /// which happens a moment after this call returns.
    func cancel(completion: (@Sendable () -> Void)? = nil) {
        dispatchPrecondition(condition: .onQueue(queue))
        generation += 1
        port = nil
        guard let nwListener else {
            completion?()
            return
        }
        self.nwListener = nil
        nwListener.stateUpdateHandler = { state in
            if case .cancelled = state { completion?() }
        }
        nwListener.cancel()
    }

    private func attempt(_ candidates: ArraySlice<UInt16>) {
        guard let candidate = candidates.first else {
            nwListener = nil
            delegate?.listenerDidSettle(on: nil)
            return
        }
        let remaining = candidates.dropFirst()
        let parameters = Self.parameters(port: candidate, keepalive: keepalive)
        guard candidate != 0, let nwListener = try? NWListener(using: parameters) else {
            attempt(remaining)
            return
        }
        generation += 1
        let generation = self.generation
        self.nwListener = nwListener
        nwListener.newConnectionHandler = { [weak self] connection in
            guard let self, self.generation == generation else {
                connection.cancel()
                return
            }
            self.delegate?.listenerDidAccept(connection)
        }
        // Weak: the listener holds this handler until it is cancelled.
        nwListener.stateUpdateHandler = { [weak self, weak nwListener] state in
            guard let self, self.generation == generation else { return }
            switch state {
            case .ready:
                self.port = candidate
                self.delegate?.listenerDidSettle(on: candidate)
            case .failed, .waiting:
                // A taken port ends here with EADDRINUSE.
                if self.port == nil {
                    nwListener?.cancel()
                    self.attempt(remaining)
                } else {
                    self.runningListenerFailed()
                }
            default:
                break
            }
        }
        nwListener.start(queue: queue)
    }

    /// A listener that had been running is gone: release it and tell the owner, who decides
    /// when to listen again. The tests call it to fail the listener the way the system would.
    func runningListenerFailed() {
        generation += 1
        nwListener?.cancel()
        nwListener = nil
        port = nil
        delegate?.listenerDidFail()
    }
}
#endif
