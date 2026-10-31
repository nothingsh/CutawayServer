#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import Foundation

// What rendering hands on: sizes decided, pixels rendered. Nothing here refers to a layer,
// so all of it may leave the main thread.

/// The size of the image of one layer, decided before any memory is allocated.
struct ImagePlan: Sendable, Equatable {
    var pixelWidth: Int
    var pixelHeight: Int
    /// Pixels per point, after any reduction.
    var scale: Float
}

/// Pixels in the wire's layout (PROTOCOL.md, P-IMG-01), not compressed yet: 8-bit BGRA,
/// premultiplied alpha, sRGB, rows top to bottom.
struct RawImage: Sendable, Equatable {
    var pixelWidth: Int
    var pixelHeight: Int
    var bytesPerRow: Int
    /// Pixels per point.
    var scale: Float
    var pixels: Data
    /// Taken from what the app composited, not drawn layer by layer (P-IMG-07).
    var isComposited = false
    /// See `clearShadowRemnants()`.
    var mayHaveCutOffShadow = false

    /// Liquid Glass casts a soft shadow from the render server that reaches well past the view.
    /// Cut off at the bounds, what is left shows as a grey rectangle behind the shape as soon as
    /// the image stands apart from what lies around it. Nothing marks it, so what looks like it
    /// goes: pure black, and fainter than the shadow gets, about 8%. Not for the main thread: it
    /// looks at every pixel.
    mutating func clearShadowRemnants() {
        guard mayHaveCutOffShadow else { return }
        mayHaveCutOffShadow = false
        pixels.withUnsafeMutableBytes { buffer in
            // Little-endian BGRA, so alpha is the top byte; a composited image has no padding.
            // A plain pointer: a debug build runs this unoptimized, where subscripts cost 30 times
            // as much on a whole screen.
            let pixels = buffer.bindMemory(to: UInt32.self)
            guard var pixel = pixels.baseAddress else { return }
            let end = pixel + pixels.count
            while pixel < end {
                let value = pixel.pointee
                // An alpha below 32, and no colour.
                if value < 0x2000_0000, value & 0x00FF_FFFF == 0 { pixel.pointee = 0 }
                pixel += 1
            }
        }
    }
}
#endif
