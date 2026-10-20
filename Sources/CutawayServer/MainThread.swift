#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import Foundation

/// Runs `work` on the main thread, where UIKit may be used.
func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated(work)
    }
}

/// Runs `work` on the main thread after the main run loop has gone round `turns` more times,
/// without running it from here: called from a block of the main queue, each block queued from
/// the one before runs in a later turn (assumption H9), and `work` runs in the last.
func onMain(afterTurns turns: Int, _ work: @escaping @MainActor @Sendable () -> Void) {
    onMain {
        if turns > 1 {
            onMain(afterTurns: turns - 1, work)
        } else {
            work()
        }
    }
}

/// Works out a value on the main thread and hands it to `completion` on `queue`.
func onMain<Value: Sendable>(
    answeringOn queue: DispatchQueue,
    to completion: @escaping @Sendable (Value) -> Void,
    _ work: @escaping @MainActor @Sendable () -> Value
) {
    onMain {
        let value = work()
        queue.async { completion(value) }
    }
}
#endif
