#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
/// The version of this SDK, as sent in `AppInfo.server_version`. The same as the tag of the
/// release that ships it.
enum ServerVersion {
    static let string = "1.1.0"
}
#endif
