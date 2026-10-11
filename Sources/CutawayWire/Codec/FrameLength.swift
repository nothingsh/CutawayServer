#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

/// The 4-byte little-endian length in front of each frame (PROTOCOL.md, P-FRAME-01). This is
/// not FlatBuffers' own size prefix.
enum FrameLength {
    static let byteCount = 4

    static func append(_ length: UInt32, to bytes: inout Data) {
        withUnsafeBytes(of: length.littleEndian) { bytes.append(contentsOf: $0) }
    }

    /// The length that starts at `start`; `bytes` holds at least four bytes from there.
    static func read(from bytes: Data, at start: Data.Index) -> UInt32 {
        var length: UInt32 = 0
        for index in 0..<byteCount {
            length |= UInt32(bytes[start + index]) << UInt32(8 * index)
        }
        return length
    }
}
#endif
