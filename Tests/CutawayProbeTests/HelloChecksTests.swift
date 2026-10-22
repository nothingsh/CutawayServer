import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's check of the server's hello. The probe is a client: before the handshake
/// completes, any frame other than `Hello` fails the handshake, and the probe sends nothing
/// more (PROTOCOL.md, P-HELLO-07). `Busy` is told apart before this check (P-TRANS-03).
final class HelloChecksTests: XCTestCase {
    private func assertRejects(
        _ frame: Frame?,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try HelloChecks.serverHello(frame), file: file, line: line) { error in
            XCTAssertTrue(
                String(describing: error).contains(expected),
                "\"\(error)\" does not mention \"\(expected)\"",
                file: file,
                line: line
            )
        }
    }

    func test_S_PROBE_01_helloCheckWantsAProtocol1Hello() throws {
        let app = try HelloChecks.serverHello(try Fixtures.frame("handshake/02-s2c-hello.bin"))
        XCTAssertFalse(app.bundleID.isEmpty)

        // Anything else before the hello, or no frame at all.
        let others: [(Frame?, String)] = [ErrorCode.malformedFrame, .unexpectedMessage, .internalError].map {
            (Frame(requestID: 0, body: .error(WireError(code: $0, message: "no"))), "expected the server's Hello")
        } + [
            (Frame(requestID: 0, body: .appStateChanged(.active)), "expected the server's Hello"),
            (nil, "closed the connection before its Hello"),
            // The fixture's server is still at 0.5 (P-HELLO-03).
            (try Fixtures.frame("handshake-version-mismatch/02-s2c-hello.bin"), "P-HELLO-03")
        ]
        for (frame, expected) in others {
            assertRejects(frame, expected)
        }
    }
}
