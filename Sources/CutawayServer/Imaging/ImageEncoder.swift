#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CoreGraphics
import CutawayWire
import Foundation

/// Turns bitmaps into the wire's image encoding (PROTOCOL.md, P-IMG-01):
/// 8-bit BGRA, premultiplied alpha, sRGB, rows top to bottom, LZFSE-compressed.
/// Safe to call on any thread.
enum ImageEncoder {
    static func encode(_ image: CGImage, scale: Float) -> WireImage? {
        let width = image.width
        let height = image.height
        // Creating a bitmap context of size zero crashes.
        guard width > 0, height > 0 else { return nil }
        let bytesPerRow = width * 4
        var pixels = Data(count: bytesPerRow * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = BitmapContext.bgra(
                width: width,
                height: height,
                bytesPerRow: bytesPerRow,
                data: buffer.baseAddress
            ) else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        return compress(
            RawImage(
                pixelWidth: width,
                pixelHeight: height,
                bytesPerRow: bytesPerRow,
                scale: scale,
                pixels: pixels
            )
        )
    }

    /// Compresses pixels that already have the wire's layout.
    static func compress(_ image: RawImage) -> WireImage? {
        guard image.pixelWidth > 0, image.pixelHeight > 0,
              image.pixels.count == image.bytesPerRow * image.pixelHeight,
              let compressed = compressedPixels(image.pixels) else {
            return nil
        }
        return WireImage(
            encoding: .bgra8PremultipliedLZFSE,
            pixelWidth: UInt32(image.pixelWidth),
            pixelHeight: UInt32(image.pixelHeight),
            bytesPerRow: UInt32(image.bytesPerRow),
            scale: image.scale,
            data: compressed
        )
    }

    /// Fully transparent images are common (a container without a background, alone) and
    /// compress slower than most. LZFSE gives the same bytes for the same input, so the
    /// output for zeros is kept by length.
    private static let zeros = ZeroCompressionCache()

    private static func compressedPixels(_ pixels: Data) -> Data? {
        guard isZero(pixels) else {
            return try? (pixels as NSData).compressed(using: .lzfse) as Data
        }
        if let cached = zeros.data(forLength: pixels.count) { return cached }
        guard let compressed = try? (pixels as NSData).compressed(using: .lzfse) as Data else { return nil }
        zeros.store(compressed, forLength: pixels.count)
        return compressed
    }

    static func isZero(_ bytes: Data) -> Bool {
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress, !buffer.isEmpty,
                  buffer[0] == 0 else { return false }
            // Every byte equals the one after it, and the first is zero.
            return memcmp(base, base + 1, buffer.count - 1) == 0
        }
    }
}

/// The compressed form of zeros, by length. Any thread.
private final class ZeroCompressionCache: @unchecked Sendable {
    /// Lengths vary from layer to layer; past this many, the oldest are let go.
    private static let capacity = 32

    private let lock = NSLock()
    private var entries: [(length: Int, data: Data)] = []

    func data(forLength length: Int) -> Data? {
        lock.lock()
        defer { lock.unlock() }
        return entries.first { $0.length == length }?.data
    }

    func store(_ data: Data, forLength length: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard !entries.contains(where: { $0.length == length }) else { return }
        if entries.count == Self.capacity { entries.removeFirst() }
        entries.append((length, data))
    }
}
#endif
