#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import Foundation

/// The main run loop's activity: an observer that is told each time the run loop is about to
/// wait, in every common mode, after Core Animation has committed. An app that holds still
/// does not turn its run loop, so nothing runs while it is idle. The observer only notes; the
/// watch decides.
@MainActor
final class RunLoopActivity: ActivitySource {
    private var observer: CFRunLoopObserver?

    func start(_ handler: @escaping @MainActor (_ tracking: Bool) -> Void) {
        stop()
        // Last of the observers of the turn: Core Animation commits at 2,000,000.
        let observer = CFRunLoopObserverCreateWithHandler(
            nil,
            CFRunLoopActivity.beforeWaiting.rawValue,
            true,
            CFIndex.max
        ) { _, _ in
            MainActor.assumeIsolated { handler(RunLoop.main.currentMode == .tracking) }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    func stop() {
        guard let observer else { return }
        CFRunLoopObserverInvalidate(observer)
        self.observer = nil
    }
}
#endif
