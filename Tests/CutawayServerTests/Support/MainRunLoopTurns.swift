import Foundation

/// Counts the turns of the main run loop: each turn begins by telling its observers that it is
/// about to handle timers. Counts until `stop()`.
@MainActor
final class MainRunLoopTurns {
    private(set) var count = 0
    private var observer: CFRunLoopObserver?

    init() {
        let observer = CFRunLoopObserverCreateWithHandler(
            nil,
            CFRunLoopActivity.beforeTimers.rawValue,
            true,
            0
        ) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.count += 1 }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        self.observer = observer
    }

    func stop() {
        if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) }
        observer = nil
    }
}
