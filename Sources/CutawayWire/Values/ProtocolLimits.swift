#if !canImport(UIKit) || DEBUG || ReleaseEnabled
/// Numbers PROTOCOL.md fixes, for the server and its clients alike.
public enum ProtocolLimits {
    /// P-TRANS-02: a server listens on the first free port of this range.
    public static let portRange: ClosedRange<UInt16> = 48160...48167
    /// P-DET-08: the uncompressed pixels of one image, in bytes.
    public static let maximumImageByteCount = 67_108_864
    /// P-DET-06: the uncompressed pixels of all images of one chunk, in bytes.
    public static let chunkPixelBudget = 16_777_216
}
#endif
