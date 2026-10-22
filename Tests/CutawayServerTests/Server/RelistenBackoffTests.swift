import Foundation
import XCTest

@testable import CutawayServer

/// The delays between attempts to listen again. No server, no connection.
final class RelistenBackoffTests: XCTestCase {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    func test_S_CONN_10_delaysDoubleUpToTheMaximumUntilReset() {
        // The first retry comes within one second.
        var backoff = RelistenBackoff(ServerConfiguration().relisten)
        let delays = (0..<9).map { _ in backoff.nextDelay(now: start) }
        XCTAssertEqual(delays, [0.5, 1, 2, 4, 8, 16, 30, 30, 30])

        // A configuration of its own, and a reset that starts over.
        var custom = RelistenBackoff(.init(initialDelay: 0.05, maximumDelay: 0.4))
        XCTAssertEqual((0..<5).map { _ in custom.nextDelay(now: start) }, [0.05, 0.1, 0.2, 0.4, 0.4])
        custom.reset()
        XCTAssertEqual(custom.nextDelay(now: start), 0.05)
    }

    func test_S_CONN_10_aListenerThatRanLongEnoughStartsOver() {
        var backoff = RelistenBackoff(ServerConfiguration().relisten)
        XCTAssertEqual(backoff.nextDelay(now: start), 0.5)
        XCTAssertEqual(backoff.nextDelay(now: start), 1)

        // Ready, and failed again a moment later: one more of the same series.
        backoff.recordListening(since: start)
        XCTAssertEqual(backoff.nextDelay(now: start.addingTimeInterval(29.9)), 2)

        // Ready for the maximum delay before it failed: a new series.
        backoff.recordListening(since: start)
        XCTAssertEqual(backoff.nextDelay(now: start.addingTimeInterval(30)), 0.5)
        XCTAssertEqual(backoff.nextDelay(now: start.addingTimeInterval(30)), 1)
    }
}
