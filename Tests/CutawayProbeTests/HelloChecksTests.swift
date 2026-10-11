import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's check of the server's hello. The probe is a client: before the handshake
/// completes, any frame other than `Hello` fails the handshake, and the probe sends nothing
/// more (PROTOCOL.md, P-HELLO-07). `Busy` is told apart before this check (P-TRANS-03).
final class HelloChecksTests: XCTestCase {
    /// Tests/CutawayProbeTests/HelloChecksTests.swift -> the repository root.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func fixtureFrame(_ path: String) throws -> Frame {
        try FrameCodec.decode(Data(contentsOf: Self.root.appendingPathComponent("Protocol/fixtures/bin/\(path)")))
    }

    private func assertRejects(
        _ frame: Frame?,
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try Checks.serverHello(frame), file: file, line: line) { error in
            XCTAssertTrue(
                String(describing: error).contains(expected),
                "\"\(error)\" does not mention \"\(expected)\"",
                file: file,
                line: line
            )
        }
    }

    func test_S_PROBE_01_helloCheckAcceptsTheProtocol1Hello() throws {
        let app = try Checks.serverHello(try fixtureFrame("handshake/02-s2c-hello.bin"))
        XCTAssertFalse(app.bundleID.isEmpty)
    }

    func test_S_PROBE_01_errorsBeforeTheHelloFailTheHandshake() {
        for code in [ErrorCode.malformedFrame, .unexpectedMessage, .internalError] {
            assertRejects(
                Frame(requestID: 0, body: .error(WireError(code: code, message: "no"))),
                "expected the server's Hello"
            )
        }
        assertRejects(Frame(requestID: 0, body: .appStateChanged(.active)), "expected the server's Hello")
        assertRejects(nil, "closed the connection before its Hello")
    }

    func test_S_PROBE_01_serverOfProtocol0FailsTheHandshake() throws {
        // The fixture's server is still at 0.5 (P-HELLO-03).
        assertRejects(try fixtureFrame("handshake-version-mismatch/02-s2c-hello.bin"), "P-HELLO-03")
    }
}
