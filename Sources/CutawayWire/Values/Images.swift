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
    /// Empty for an unchanged image (P-IMG-01, P-IMG-05).
    public var data: Data
    /// Identifies the content on this connection (P-IMG-04, protocol 1.3); `nil` when absent.
    public var digest: Data?
    /// The image whose digest the client sent; no pixels follow (P-IMG-05, protocol 1.3).
    public var isUnchanged: Bool
    /// A group taken from what the app composited, not drawn layer by layer (P-IMG-07,
    /// protocol 1.3).
    public var isComposited: Bool

    public init(
        encoding: ImageEncoding = .bgra8PremultipliedLZFSE,
        pixelWidth: UInt32,
        pixelHeight: UInt32,
        bytesPerRow: UInt32,
        scale: Float,
        data: Data,
        digest: Data? = nil,
        isUnchanged: Bool = false,
        isComposited: Bool = false
    ) {
        self.encoding = encoding
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.bytesPerRow = bytesPerRow
        self.scale = scale
        self.data = data
        self.digest = digest
        self.isUnchanged = isUnchanged
        self.isComposited = isComposited
    }

    /// P-IMG-05: the client's image with this digest, every other field at its default.
    public static func unchanged(digest: Data) -> Self {
        Self(pixelWidth: 0, pixelHeight: 0, bytesPerRow: 0, scale: 0, data: Data(), digest: digest, isUnchanged: true)
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
