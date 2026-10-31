#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CryptoKit
import Foundation

/// What identifies an image's content on a connection (PROTOCOL.md, P-IMG-04): the algorithm
/// the protocol suggests, so that the fixtures' digests are this one's. SHA-256 over the width
/// and the height (4 bytes each, little-endian), the scale (the `Float`'s 4 bytes,
/// little-endian) and the encoding (1 byte), one byte `01` when the image is composited and
/// nothing when it is not, then the first `pixelWidth × 4` bytes of each row; the first 16
/// bytes of the result. Any thread.
enum ImageDigest {
    static let byteCount = 16
    /// `Bgra8PremultipliedLzfse` in the schema: the only encoding (P-IMG-01).
    private static let encoding: UInt8 = 0

    static func of(_ image: RawImage) -> Data {
        var hash = SHA256()
        var header = Data(capacity: 14)
        for value in [UInt32(image.pixelWidth), UInt32(image.pixelHeight), image.scale.bitPattern] {
            withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
        }
        header.append(encoding)
        if image.isComposited { header.append(1) }
        hash.update(data: header)
        let rowBytes = image.pixelWidth * 4
        image.pixels.withUnsafeBytes { buffer in
            if image.bytesPerRow == rowBytes {
                // No padding: the rows are one run of bytes.
                let rows = buffer.prefix(rowBytes * image.pixelHeight)
                hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: rows))
            } else {
                for row in 0..<image.pixelHeight {
                    let start = row * image.bytesPerRow
                    hash.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[start..<start + rowBytes]))
                }
            }
        }
        return Data(hash.finalize().prefix(byteCount))
    }
}
#endif
