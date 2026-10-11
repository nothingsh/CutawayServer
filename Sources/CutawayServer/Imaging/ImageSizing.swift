#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CoreGraphics
import CutawayWire

/// Decides how many pixels the image of a layer gets (PROTOCOL.md, P-DET-05, P-DET-08).
enum ImageSizing {
    /// P-DET-08: the uncompressed pixels of one image.
    static let maximumImageBytes = ProtocolLimits.maximumImageByteCount

    /// `nil` when the layer cannot be captured: a size that is zero, negative or not finite.
    ///
    /// The image has `screenScale` pixels per point, each side rounded up. When that exceeds
    /// `maxTextureDimension` (0: no limit) or `maximumImageBytes`, both sides shrink by the
    /// same factor, rounded down, and the scale shrinks with them.
    static func plan(bounds: CGRect, screenScale: CGFloat, maxTextureDimension: UInt32) -> ImagePlan? {
        let numbers = [
            bounds.origin.x,
            bounds.origin.y,
            bounds.size.width,
            bounds.size.height,
            screenScale
        ]
        guard numbers.allSatisfy(\.isFinite),
              bounds.size.width > 0,
              bounds.size.height > 0,
              screenScale > 0 else {
            return nil
        }
        let fullWidth = Double(bounds.size.width) * Double(screenScale)
        let fullHeight = Double(bounds.size.height) * Double(screenScale)
        guard (fullWidth * fullHeight).isFinite else { return nil }

        let maximumPixels = Double(maximumImageBytes / 4)
        let sideLimit = maxTextureDimension == 0 ? Double.infinity : Double(maxTextureDimension)
        var width = max(1, fullWidth.rounded(.up))
        var height = max(1, fullHeight.rounded(.up))
        var factor = 1.0
        if max(width, height) > sideLimit || width * height > maximumPixels {
            factor = min(
                1,
                sideLimit / max(fullWidth, fullHeight),
                (maximumPixels / (fullWidth * fullHeight)).squareRoot()
            )
            // The factor was divided out of these very numbers, and multiplying it back can land
            // a hair under a whole number: the side that decided would lose a pixel it may have.
            // The nudge is far above that error and far below a pixel.
            let nudge = 1e-6
            width = min(sideLimit, max(1, (fullWidth * factor + nudge).rounded(.down)))
            height = min(sideLimit, max(1, (fullHeight * factor + nudge).rounded(.down)))
            // A side cannot go below one pixel. With an extreme aspect ratio the other side may
            // then still be too long: it is cut, and only here the image is not proportional.
            if width * height > maximumPixels {
                if width >= height {
                    width = (maximumPixels / height).rounded(.down)
                } else {
                    height = (maximumPixels / width).rounded(.down)
                }
            }
        }
        let scale = Float(Double(screenScale) * factor)
        guard scale.isFinite, scale > 0 else { return nil }
        return ImagePlan(pixelWidth: Int(width), pixelHeight: Int(height), scale: scale)
    }
}
#endif
