#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

/// Cuts a TCP byte stream into frame payloads (PROTOCOL.md, P-FRAME-01).
public struct FrameSplitter: Sendable {
    private var buffer = Data()
    /// How many bytes at the front of `buffer` were taken already. They are dropped from time
    /// to time, not with every frame: dropping copies what is left, and a read full of small
    /// frames would copy it once per frame.
    private var taken = 0

    public init() {}

    public mutating func append(_ bytes: Data) {
        buffer.append(bytes)
    }

    /// The next complete payload, or `nil` when more bytes are needed.
    /// Throws as soon as a length above the limit is read, without waiting for the payload.
    /// After it throws, the stream is lost: close the connection.
    public mutating func next() throws -> Data? {
        let available = buffer.count - taken
        guard available >= FrameLength.byteCount else {
            dropTaken()
            return nil
        }
        let start = buffer.startIndex + taken
        let length = FrameLength.read(from: buffer, at: start)
        guard length <= FrameCodec.maximumFrameLength else {
            throw WireFailure.lengthExceedsLimit(length)
        }
        let end = FrameLength.byteCount + Int(length)
        guard available >= end else {
            dropTaken()
            return nil
        }
        let payload = Data(buffer[(start + FrameLength.byteCount)..<(start + end)])
        taken += end
        if taken * 2 >= buffer.count { dropTaken() }
        return payload
    }

    /// Lets go of the bytes that were taken.
    private mutating func dropTaken() {
        guard taken > 0 else { return }
        buffer = Data(buffer[(buffer.startIndex + taken)...])
        taken = 0
    }
}
#endif
