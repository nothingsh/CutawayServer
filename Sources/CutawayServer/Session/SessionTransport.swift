#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation

/// Told about one transport's input and output, on the server queue, while it is open.
protocol SessionTransportDelegate: AnyObject {
    /// One complete frame payload.
    func transportDidReceive(_ payload: Data)
    /// The byte stream cannot be cut into frames. Once.
    func transportCannotSplitFrames()
    /// The peer or the network ended the transport. Once; not after `finish(with:)` or
    /// `close()`.
    func transportDidClose()
    /// A send completed, so that work held back for room can go on.
    func transportDidSend()
}

/// What a session needs from its connection. Everything is used on the server queue.
/// `Connection` is the real one; tests put a recording one in its place.
protocol SessionTransport: AnyObject {
    /// Told about input and output until the transport is closed. Held weakly.
    var delegate: SessionTransportDelegate? { get set }
    /// Bytes handed to `send(_:)` whose sending has not completed; 0 once closed.
    var unsentByteCount: Int { get }

    func start()
    func send(_ frame: Frame)
    /// Sends a last frame and closes without losing it.
    func finish(with frame: Frame)
    func close()
    /// No more frames are delivered until `resumeReceiving()`, and no more input is read:
    /// once the socket's buffers are full, the peer cannot send.
    func pauseReceiving()
    func resumeReceiving()
}
#endif
