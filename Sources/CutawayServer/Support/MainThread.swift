#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import Dispatch

/// Runs `work` on the main thread, where UIKit may be used.
func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated(work)
    }
}

/// Runs `work` on the main thread after the main run loop has gone round `turns` more times,
/// without running it from here. Each step queues the next on the main queue from a block of the
/// main queue; the main run loop does not run a block queued during its turn until a later turn,
/// so every step takes a turn of its own and `work` runs in the last. Called from a block of the
/// main queue, so that the first step too waits for the next turn.
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
