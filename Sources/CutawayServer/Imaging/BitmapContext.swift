#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CoreGraphics

/// Bitmaps in the wire's layout (PROTOCOL.md, P-IMG-01): 8-bit BGRA, premultiplied alpha,
/// sRGB. Safe to call on any thread.
enum BitmapContext {
    /// A context that draws into `data`; `nil` when Core Graphics cannot make one.
    static func bgra(
        width: Int,
        height: Int,
        bytesPerRow: Int,
        data: UnsafeMutableRawPointer?
    ) -> CGContext? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        // BGRA in memory is "alpha first" in a little-endian 32-bit word.
        return CGContext(
            data: data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        )
    }
}
#endif
