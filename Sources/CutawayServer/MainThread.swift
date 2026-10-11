#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import Foundation

/// Runs `work` on the main thread, where UIKit may be used.
func onMain(_ work: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async {
        MainActor.assumeIsolated(work)
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
