#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
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
}
#endif
