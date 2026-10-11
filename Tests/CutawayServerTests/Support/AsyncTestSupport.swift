import Foundation

/// Polls until `condition` holds.
func waitUntil(
    _ what: String,
    timeout: TimeInterval = 10,
    _ condition: @Sendable () -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        guard Date() < deadline else {
            throw TestClientError(description: "timed out waiting for \(what)")
        }
        try await Task.sleep(nanoseconds: 2_000_000)
    }
}

/// Returns once everything that was on `queue` before the call has run.
func drain(_ queue: DispatchQueue) async {
    await withCheckedContinuation { continuation in
        queue.async { continuation.resume() }
    }
}
