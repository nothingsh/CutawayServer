import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// `GetEnvironment` and `SetEnvironment` over a real connection, on the test host's windows
/// (protocol 1.2; PROTOCOL.md, P-ENV-01 to 04).
final class EnvironmentRequestTests: ServerTestCase {
    /// The overrides of every `Environment` an `environment` fixture frame answers with.
    private func fixtureOverrides(_ path: String) throws -> Traits {
        guard case .environment(let environment)? = try Fixtures.frame(path).body else {
            throw TestClientError(description: "\(path) is not an Environment")
        }
        return environment.overrides
    }

    private func environment(of frame: Frame?) throws -> Environment {
        guard case .environment(let environment)? = frame?.body else {
            throw TestClientError(description: "expected an Environment, got \(String(describing: frame))")
        }
        return environment
    }

    @MainActor
    private static func keyStyle() -> UIUserInterfaceStyle {
        (HostWindows.all().last(where: \.isKeyWindow) ?? HostWindows.all().first)?.traitCollection.userInterfaceStyle
            ?? .unspecified
    }

    func test_S_ENV_02_theFixtureRequestsOverrideTheTestHost() async throws {
        guard #available(iOS 17, *) else { throw XCTSkip("the fixture overrides three kinds, which needs iOS 17") }
        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)
        let before = await Self.keyStyle()

        // The fixture's four requests, in its bytes: each answer has the fixture's overrides, and
        // `current` follows them.
        try await client.send(Fixtures.data("environment/c2s.stream"))
        let answers = [
            try environment(of: try await client.nextFrame()),
            try environment(of: try await client.nextFrame()),
            try environment(of: try await client.nextFrame()),
            try environment(of: try await client.nextFrame())
        ]
        XCTAssertEqual(
            answers.map(\.overrides),
            try ["02", "04", "06", "08"].map { try fixtureOverrides("environment/\($0)-s2c-environment.bin") }
        )
        XCTAssertEqual(answers.map(\.overridable), Array(repeating: TraitKind.allCases, count: 4))
        XCTAssertEqual(answers[1].current.userInterfaceStyle, .dark)
        XCTAssertEqual(answers[1].current.contentSizeCategory, .accessibilityLarge)
        XCTAssertEqual(answers[1].current.layoutDirection, .rightToLeft)
        XCTAssertEqual(answers[2].current.layoutDirection, answers[0].current.layoutDirection)
        XCTAssertEqual(answers[3].current, answers[0].current, "all overrides removed")
        let after = await Self.keyStyle()
        XCTAssertEqual(after, before)
    }

    func test_S_ENV_03_closingTheConnectionRemovesTheOverrides() async throws {
        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)
        let before = await Self.keyStyle()
        let opposite: UserInterfaceStyle = before == .dark ? .light : .dark

        try await client.send(Frame(
            requestID: 1,
            body: .setEnvironment(overrides: Traits(userInterfaceStyle: opposite))
        ))
        _ = try environment(of: try await client.nextFrame())
        let during = await Self.keyStyle()
        XCTAssertNotEqual(during, before)

        client.close()
        let deadline = Date().addingTimeInterval(5)
        while await Self.keyStyle() != before {
            guard Date() < deadline else { return XCTFail("the overrides were not removed") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}
