#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire

/// The requests of one session that wait for their turn, oldest first (PROTOCOL.md,
/// P-REQ-06). Taken requests are dropped from time to time, not one by one: dropping copies
/// what is left.
struct RequestQueue {
    /// A request that waits for its turn.
    struct Request {
        var frame: Frame
        /// A `Cancel` named it while it waited (PROTOCOL.md, P-REQ-04).
        var isCancelled = false
    }

    private var requests: [Request] = []
    /// The ones before this were taken.
    private var start = 0

    /// How many requests wait.
    var count: Int { requests.count - start }

    var isEmpty: Bool { start >= requests.count }

    mutating func append(_ frame: Frame) {
        requests.append(Request(frame: frame))
    }

    /// Takes the oldest waiting request.
    mutating func next() -> Request? {
        guard start < requests.count else { return nil }
        let request = requests[start]
        start += 1
        if start >= 64, start * 2 >= requests.count {
            requests.removeFirst(start)
            start = 0
        }
        return request
    }

    /// Marks the waiting `GetLayerDetails` with this request ID as cancelled. Anything else it
    /// names is left alone.
    mutating func cancelWaitingStream(_ requestID: UInt32) {
        let waiting = requests[start...].firstIndex { request in
            guard case .getLayerDetails? = request.frame.body else { return false }
            return request.frame.requestID == requestID && !request.isCancelled
        }
        if let waiting { requests[waiting].isCancelled = true }
    }

    mutating func removeAll() {
        requests.removeAll()
        start = 0
    }
}
#endif
