#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import Foundation

/// Tells the main thread and the compressor that a stream was stopped. Set on the server
/// queue, read on the main thread between two screenshots and by the compressor before
/// each detail.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func set() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}
#endif
