import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's checks of the environment: they accept the fixtures and name what is
/// wrong with anything else.
final class EnvironmentChecksTests: XCTestCase {
    private func assertRejects(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: () throws -> Void
    ) {
        XCTAssertThrowsError(try check(), file: file, line: line) { error in
            XCTAssertTrue(
                "\(error)".contains(expected),
                "\"\(error)\" does not mention \"\(expected)\"",
                file: file,
                line: line
            )
        }
    }

    func test_S_PROBE_07_environmentChecksAcceptTheFixtures() throws {
        let before = try EnvironmentChecks.environment(
            try Fixtures.frame("environment/02-s2c-environment.bin"),
            answering: "1"
        )
        XCTAssertEqual(before.overridable.count, 5)
        let dark = try EnvironmentChecks.environment(
            try Fixtures.frame("environment/06-s2c-environment.bin"),
            answering: "3"
        )
        XCTAssertNoThrow(try EnvironmentChecks.dark(dark))
        let restored = try EnvironmentChecks.environment(
            try Fixtures.frame("environment/08-s2c-environment.bin"),
            answering: "4"
        )
        XCTAssertNoThrow(try EnvironmentChecks.restored(restored, before: before))
        let one = try EnvironmentChecks.environment(
            try Fixtures.frame("environment-rejected/02-s2c-environment.bin"),
            answering: "1"
        )
        XCTAssertEqual(one.overridable, [.userInterfaceStyle])
    }

    func test_S_PROBE_07_environmentChecksRejectWhatIsWrong() throws {
        let fixture = try Fixtures.frame("environment/02-s2c-environment.bin")
        guard case .environment(var environment)? = fixture.body else { return XCTFail("not an Environment") }
        let before = environment
        environment.overridable.append(.userInterfaceStyle)
        assertRejects("lists userInterfaceStyle twice in overridable (P-ENV-01)") {
            _ = try EnvironmentChecks.environment(
                Frame(requestID: fixture.requestID, body: .environment(environment)),
                answering: "GetEnvironment"
            )
        }
        assertRejects("expected Environment in answer to GetEnvironment") {
            _ = try EnvironmentChecks.environment(Frame(requestID: 1, body: .getHierarchy), answering: "GetEnvironment")
        }
        // Still light, overridden or not.
        assertRejects("after SetEnvironment to dark, overrides has the appearance unspecified") {
            try EnvironmentChecks.dark(before)
        }
        var overriddenOnly = before
        overriddenOnly.overrides.userInterfaceStyle = .dark
        assertRejects("after SetEnvironment to dark, the current appearance is light (P-ENV-02)") {
            try EnvironmentChecks.dark(overriddenOnly)
        }
        assertRejects("after SetEnvironment without overrides, overrides is") {
            try EnvironmentChecks.restored(overriddenOnly, before: before)
        }
        var darker = before
        darker.current.userInterfaceStyle = .dark
        assertRejects("but they were") {
            try EnvironmentChecks.restored(darker, before: before)
        }
    }
}
