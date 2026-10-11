// Every file of this target is wrapped in a `canImport(UIKit)` check, so that the package
// still builds on macOS, where `swift test` builds all of its targets.
#if canImport(UIKit)
import Foundation

/// The entry point of the SDK.
public enum CutawayServer {
    /// Starts the server. It begins to listen on the loopback address once the app is active.
    ///
    /// Call it from any thread, as often as you like: only the first call has an effect.
    /// It does nothing in builds that define neither `DEBUG` nor the package trait
    /// `ReleaseEnabled`.
    public static func start() {
        #if DEBUG || ReleaseEnabled
        ServerController.shared.start()
        #endif
    }
}
#endif
