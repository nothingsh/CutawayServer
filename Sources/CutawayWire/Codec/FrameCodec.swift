#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

internal import CutawayFlatBuffers

/// Converts between `Frame` values and the bytes of PROTOCOL.md's P-FRAME-01.
public enum FrameCodec {
    /// P-FRAME-03: the largest N a frame may announce (256 MiB).
    public static let maximumFrameLength: UInt32 = 268_435_456

    /// P-FRAME-06: a frame within the length limit is never rejected for its table count.
    /// Every table takes at least 4 bytes, so 2^26 tables fill 256 MiB. The runtime's
    /// default of 1,000,000 is reached by a chunk of tens of thousands of details without
    /// images. The default depth (64) and apparent size (2^31) already suffice.
    static let maximumTableCount: UInt32 = 67_108_864

    /// Encodes a frame as a plain FlatBuffer with the file identifier `CTWY`.
    /// This is the payload, without the length field.
    public static func encode(_ frame: Frame) -> Data {
        var builder = FlatBufferBuilder(initialSize: 256)
        build(frame, in: &builder)
        return Data(builder.sizedByteArray)
    }

    /// The frame as it goes on the wire: the length of P-FRAME-01, then the plain buffer.
    /// The same bytes as `framed(encode(frame))` with fewer copies on the way: the builder
    /// starts big enough for the images, so it never holds two buffers while growing, and
    /// the result is copied out of it once.
    public static func encodeFramed(_ frame: Frame) -> Data {
        let initialSize = min(imageByteCount(of: frame) + 65536, Int(Int32.max))
        var builder = FlatBufferBuilder(initialSize: Int32(initialSize))
        build(frame, in: &builder)
        // The builder writes from the end of its storage towards the front.
        let size = Int(builder.size)
        var bytes = Data(capacity: size + FrameLength.byteCount)
        FrameLength.append(UInt32(size), to: &bytes)
        builder.buffer.withUnsafeBytes { storage in
            bytes.append(contentsOf: storage[(storage.count - size)...])
        }
        return bytes
    }

    /// Packs through the object API. Not size-prefixed: FlatBuffers aligns a prefixed buffer
    /// as a whole, so the buffer behind the prefix would not be aligned on its own.
    private static func build(_ frame: Frame, in builder: inout FlatBufferBuilder) {
        var object = Cutaway_Wire_FrameT()
        object.requestId = frame.requestID
        object.body = frame.body.map(union(for:))
        let root = Cutaway_Wire_Frame.pack(&builder, obj: &object)
        Cutaway_Wire_Frame.finish(&builder, end: root)
    }

    /// The compressed image bytes a frame carries; they make up nearly all of a large frame.
    private static func imageByteCount(of frame: Frame) -> Int {
        switch frame.body {
        case .layerDetailsChunk(let chunk):
            return chunk.details.reduce(0) {
                $0 + ($1.solo?.data.count ?? 0) + ($1.group?.data.count ?? 0)
            }
        case .appIcon(let icon):
            return icon.image?.data.count ?? 0
        default:
            return 0
        }
    }

    /// Verifies the whole buffer, then reads it. Nothing is read from a buffer that fails.
    public static func decode(_ payload: Data) throws -> Frame {
        // The verifier checks the alignment of real addresses, and a `Data` may start anywhere
        // (a slice, for example). An array's storage is always aligned.
        var buffer = ByteBuffer(bytes: [UInt8](payload))
        let frame: Cutaway_Wire_Frame
        do {
            frame = try getCheckedRoot(
                byteBuffer: &buffer,
                fileId: Cutaway_Wire_Frame.id,
                options: VerifierOptions(maxTableCount: maximumTableCount)
            )
        } catch {
            throw WireFailure.malformed
        }
        return Frame(requestID: frame.requestId, body: try message(of: frame))
    }

    /// Puts the 4-byte little-endian length in front of a payload. This is not FlatBuffers'
    /// own size-prefixed format.
    public static func framed(_ payload: Data) -> Data {
        var bytes = Data(capacity: payload.count + FrameLength.byteCount)
        FrameLength.append(UInt32(payload.count), to: &bytes)
        bytes.append(payload)
        return bytes
    }
}
#endif
