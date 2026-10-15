#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
/// The version of this SDK, as sent in `AppInfo.server_version`. The same as the repository's
/// tag (S-REL-03).
enum ServerVersion {
    static let string = "1.1.0"
}
#endif
