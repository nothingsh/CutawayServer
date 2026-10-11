#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

public enum ImageEncoding: Sendable, Equatable {
    case bgra8PremultipliedLZFSE
}

public struct WireImage: Sendable, Equatable {
    public var encoding: ImageEncoding
    public var pixelWidth: UInt32
    public var pixelHeight: UInt32
    /// Of the decompressed pixel data.
    public var bytesPerRow: UInt32
    /// Pixels per point.
    public var scale: Float
    public var data: Data

    public init(
        encoding: ImageEncoding = .bgra8PremultipliedLZFSE,
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        bytesPerRow: UInt32,
        scale: Float,
        data: Data
    ) {
        self.encoding = encoding
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytesPerRow = bytesPerRow
        self.scale = scale
        self.data = data
    }
}

public struct AppIcon: Sendable, Equatable {
    /// `nil` when the app has no icon.
    public var image: WireImage?

    public init(image: WireImage?) {
        self.image = image
    }
}
#endif
