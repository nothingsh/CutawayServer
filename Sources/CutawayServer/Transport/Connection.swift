#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation
import Network

/// One accepted TCP connection: bytes in, frame payloads out, frames sent.
/// Confined to the server queue.
final class Connection: SessionTransport, @unchecked Sendable {
    private enum State {
        case open
        /// The last frame was sent; input is read and thrown away until the peer closes.
        case draining
        case closed
    }

    /// Read by the tests.
    let nwConnection: NWConnection
    private let queue: DispatchQueue
    private let lingerTimeout: TimeInterval
    private var splitter = FrameSplitter()
    private var state = State.open
    /// A `receive` is outstanding.
    private var isReceiving = false
    private var isReceivingPaused = false
    /// Frames are being handed to the delegate; a nested call leaves it to the outer one.
    private var isDelivering = false
    /// Bytes handed to the network whose `.contentProcessed` has not come back. That
    /// callback comes once the kernel took the bytes, so this is the backlog in the process.
    private(set) var unsentByteCount = 0

    /// Told about input and output while the connection is open. A byte stream that cannot
    /// be cut into frames is one whose length is over the limit.
    weak var delegate: SessionTransportDelegate?

    init(_ nwConnection: NWConnection, queue: DispatchQueue, lingerTimeout: TimeInterval) {
        self.nwConnection = nwConnection
        self.queue = queue
        self.lingerTimeout = lingerTimeout
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(queue))
        nwConnection.stateUpdateHandler = { [weak self] state in self?.handle(state) }
        nwConnection.start(queue: queue)
        receive()
    }

    /// A connection the network gave up on, for example after unanswered keepalive probes
    /// (ETIMEDOUT), ends like one the peer closed. The tests call it with such a failure.
    func handle(_ state: NWConnection.State) {
        if case .failed = state { peerClosed() }
    }

    func send(_ frame: Frame) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .open else { return }
        let bytes = FrameCodec.encodeFramed(frame)
        let count = bytes.count
        unsentByteCount += count
        nwConnection.send(
            content: bytes,
            completion: .contentProcessed { [weak self] error in
                // After a close the count is 0, and cancelling hands back every pending send.
                guard let self, self.state == .open else { return }
                if error != nil {
                    self.peerClosed()
                    return
                }
                self.unsentByteCount -= count
                self.delegate?.transportDidSend()
            }
        )
    }

    /// Sends a last frame and then closes without losing it: the sending side is finished,
    /// input is discarded, and the connection is cancelled when the peer closes or after
    /// `lingerTimeout`. Cancelling right away could reset the connection while the peer's
    /// unread bytes are pending, and the peer would never see the frame.
    func finish(with frame: Frame) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .open else { return }
        state = .draining
        releaseHandlers()
        nwConnection.send(
            content: FrameCodec.encodeFramed(frame),
            contentContext: .finalMessage,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
        // Input is read and dropped until the peer closes, paused or not.
        isReceivingPaused = false
        if !isReceiving { receive() }
        // The closure keeps the connection alive until then.
        queue.asyncAfter(deadline: .now() + lingerTimeout) { self.close() }
    }

    func close() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state != .closed else { return }
        state = .closed
        releaseHandlers()
        nwConnection.cancel()
    }

    func pauseReceiving() {
        dispatchPrecondition(condition: .onQueue(queue))
        isReceivingPaused = true
    }

    /// Hands over the frames that were read before the pause, then reads again.
    func resumeReceiving() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard state == .open, isReceivingPaused else { return }
        isReceivingPaused = false
        deliverFrames()
        if state == .open, !isReceivingPaused, !isReceiving { receive() }
    }

    private func releaseHandlers() {
        delegate = nil
        unsentByteCount = 0
    }

    private func receive() {
        isReceiving = true
        // The closure holds the connection strongly: it lives until it is cancelled.
        nwConnection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            self.isReceiving = false
            guard self.state != .closed else { return }
            if let data, !data.isEmpty, self.state == .open {
                self.splitter.append(data)
                self.deliverFrames()
            }
            if isComplete || error != nil {
                self.peerClosed()
            } else if !self.isReceivingPaused, !self.isReceiving {
                // While paused nothing more is read: the socket's buffers fill and the peer stops.
                // A peer that resets is still noticed, through the state handler.
                self.receive()
            }
        }
    }

    /// Hands complete frames to the delegate until the input runs out or reading is paused.
    private func deliverFrames() {
        guard !isDelivering else { return }
        isDelivering = true
        defer { isDelivering = false }
        do {
            // A handler may finish, close or pause the connection; later frames then wait or are
            // dropped.
            while state == .open, !isReceivingPaused, let payload = try splitter.next() {
                delegate?.transportDidReceive(payload)
            }
        } catch {
            delegate?.transportCannotSplitFrames()
        }
    }

    private func peerClosed() {
        guard state != .closed else { return }
        let notify = state == .open ? delegate : nil
        state = .closed
        releaseHandlers()
        nwConnection.cancel()
        notify?.transportDidClose()
    }
}
#endif
