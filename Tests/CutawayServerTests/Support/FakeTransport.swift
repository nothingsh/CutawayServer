import CutawayWire
import Foundation

@testable import CutawayServer

/// Stands in for a connection: it records what the session sends and hands the session
/// what a client would send. No socket is involved.
///
/// Sends complete at once unless `holdsSends` is set; then they wait for `completeSends`,
/// like a connection whose peer does not read. Input waits while the session paused
/// reading, like bytes left in a socket.
final class FakeTransport: SessionTransport, @unchecked Sendable {
    // Used on the session's queue only, as the protocol asks.
    weak var delegate: SessionTransportDelegate?

    private let lock = NSLock()
    private var frames: [Frame] = []
    private var closed = false
    private var usedMainThread = false
    private var holding = false
    /// The sizes on the wire of the sends that have not completed, oldest first.
    private var unsent: [Int] = []
    private var unsentTotal = 0
    private var unsentPeak = 0
    private var paused = false
    private var pauses = 0
    private var resumes = 0
    /// Payloads that arrived while reading was paused.
    private var inbox: [Data] = []
    /// Payloads handed to the session, and frames sent with a request ID other than 0.
    private var delivered = 0
    private var answers = 0
    private var aheadPeak = 0

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func start() {}

    func send(_ frame: Frame) {
        record(frame)
    }

    /// From now on sends wait for `completeSends`.
    var holdsSends: Bool {
        get { locked { holding } }
        set { locked { holding = newValue } }
    }

    var unsentByteCount: Int { locked { unsentTotal } }

    /// The most that was ever unsent at once.
    var peakUnsentByteCount: Int { locked { unsentPeak } }

    /// How many sends wait.
    var unsentSendCount: Int { locked { unsent.count } }

    /// Completes the oldest `count` waiting sends, then tells the session, as the connection
    /// does. Call on the session's queue.
    func completeSends(_ count: Int) {
        let completed = locked { () -> Int in
            let taken = min(count, unsent.count)
            unsentTotal -= unsent.prefix(taken).reduce(0, +)
            unsent.removeFirst(taken)
            return taken
        }
        if completed > 0 { delegate?.transportDidSend() }
    }

    func pauseReceiving() {
        locked {
            if !paused { pauses += 1 }
            paused = true
        }
    }

    func resumeReceiving() {
        let wasPaused = locked { () -> Bool in
            guard paused else { return false }
            paused = false
            resumes += 1
            return true
        }
        guard wasPaused else { return }
        deliverWaiting()
    }

    var isReceivingPaused: Bool { locked { paused } }
    /// Payloads that wait because reading is paused.
    var waitingInputCount: Int { locked { inbox.count } }
    /// The most payloads ever handed to the session and not yet answered with a frame that
    /// carries a request ID: the waiting requests, the one in hand, and any hello.
    var peakUnansweredCount: Int { locked { aheadPeak } }
    var pauseCount: Int { locked { pauses } }
    var resumeCount: Int { locked { resumes } }

    /// The peer goes away: closed as `Connection` closes, then the session is told. Call on
    /// the session's queue.
    func closeFromThePeer() {
        let delegate = self.delegate
        close()
        delegate?.transportDidClose()
    }

    /// Hands a payload to the session, or keeps it while reading is paused. Call on the
    /// session's queue.
    func deliver(_ payload: Data) {
        locked { inbox.append(payload) }
        deliverWaiting()
    }

    private func deliverWaiting() {
        while true {
            let next = locked { () -> Data? in
                guard !paused, !closed, !inbox.isEmpty else { return nil }
                delivered += 1
                aheadPeak = max(aheadPeak, delivered - answers)
                return inbox.removeFirst()
            }
            guard let next else { return }
            delegate?.transportDidReceive(next)
        }
    }

    func finish(with frame: Frame) {
        record(frame)
        close()
    }

    func close() {
        lock.lock()
        closed = true
        unsent.removeAll()
        unsentTotal = 0
        inbox.removeAll()
        lock.unlock()
        delegate = nil
    }

    /// Every frame goes through the codec, as it would on its way to a client.
    private func record(_ frame: Frame) {
        let bytes = FrameCodec.encodeFramed(frame)
        let decoded = try? FrameCodec.decode(bytes.dropFirst(4))
        lock.lock()
        defer { lock.unlock() }
        guard !closed else { return }
        if Thread.isMainThread { usedMainThread = true }
        frames.append(decoded ?? Frame(requestID: .max, body: nil))
        if frame.requestID != 0 { answers += 1 }
        if holding {
            unsent.append(bytes.count)
            unsentTotal += bytes.count
            unsentPeak = max(unsentPeak, unsentTotal)
        }
    }

    /// What the session sent so far, in order.
    var sent: [Frame] {
        lock.lock()
        defer { lock.unlock() }
        return frames
    }

    /// What the session sent since the last call, in order; forgotten here. Long tests would
    /// otherwise keep every frame, images and all.
    func takeSent() -> [Frame] {
        lock.lock()
        defer { lock.unlock() }
        let taken = frames
        frames = []
        return taken
    }

    /// The request ID of the last frame sent, without copying the frames.
    var lastSentRequestID: UInt32? {
        lock.lock()
        defer { lock.unlock() }
        return frames.last?.requestID
    }

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    /// Whether a frame was ever encoded and sent on the main thread.
    var sentOnMainThread: Bool {
        lock.lock()
        defer { lock.unlock() }
        return usedMainThread
    }
}
