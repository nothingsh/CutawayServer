import CutawayWire
import Foundation

// Requests on an open connection, and their answers.

/// Sends a request and returns its response. Events may arrive in between; they are skipped.
func request(_ body: Message, id requestID: UInt32, on connection: ProbeConnection) throws -> Frame {
    try connection.send(Frame(requestID: requestID, body: body))
    while true {
        guard let frame = try connection.nextFrame() else {
            throw ProbeFailure("the server closed the connection before answering request \(requestID)")
        }
        if frame.requestID == 0, case .appStateChanged? = frame.body { continue }
        guard frame.requestID == requestID else {
            throw ProbeFailure(
                "expected the response to request \(requestID), got \(HelloChecks.describe(frame)) (P-REQ-02)"
            )
        }
        return frame
    }
}

/// Sends a stream request and returns its frames, the `StreamEnd` last. Events may arrive in
/// between; they are skipped. A frame that does not belong to a stream ends the reading too:
/// the checks then say what is wrong with it. With a `pause`, the probe waits that long
/// after each chunk, as a slow client would.
func stream(
    _ body: Message,
    id requestID: UInt32,
    on connection: ProbeConnection,
    pause: TimeInterval = 0
) throws -> [Frame] {
    try connection.send(Frame(requestID: requestID, body: body))
    var frames: [Frame] = []
    while true {
        if pause > 0, !frames.isEmpty { Thread.sleep(forTimeInterval: pause) }
        guard let frame = try connection.nextFrame() else {
            throw ProbeFailure(
                "the server closed the connection before the end of stream \(requestID), after \(frames.count) frames"
            )
        }
        if frame.requestID == 0, case .appStateChanged? = frame.body { continue }
        frames.append(frame)
        guard frame.requestID == requestID, case .layerDetailsChunk? = frame.body else { return frames }
    }
}
