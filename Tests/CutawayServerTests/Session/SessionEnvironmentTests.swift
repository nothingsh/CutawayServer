import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// `GetEnvironment` and `SetEnvironment` in the session, over a fake transport (protocol 1.2).
/// The host app is the harness's: no window is touched here.
final class SessionEnvironmentTests: XCTestCase {
    private func set(_ requestID: UInt32, _ overrides: Traits?) -> Frame {
        Frame(requestID: requestID, body: .setEnvironment(overrides: overrides))
    }

    private func environment(_ requestID: UInt32, _ overrides: Traits, overridable: [TraitKind] = TraitKind.allCases)
        -> Frame {
        Frame(
            requestID: requestID,
            body: .environment(Environment(
                overrides: overrides,
                current: SessionHarness.current,
                overridable: overridable
            ))
        )
    }

    private func error(_ requestID: UInt32, _ code: ErrorCode, _ message: String) -> Frame {
        Frame(requestID: requestID, body: .error(WireError(code: code, message: message)))
    }

    func test_S_ENV_01_getEnvironmentIsAnsweredWhetherTheAppIsActiveOrNot() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        harness.receive(Frame(requestID: 2, body: .getEnvironment))
        var frames = try await harness.frames(3)
        XCTAssertEqual(frames[2], environment(2, .none))

        // P-APP-01: also when the app is not active.
        harness.setAppState(.background)
        harness.receive(Frame(requestID: 3, body: .getEnvironment))
        frames = try await harness.frames(5)
        XCTAssertEqual(frames[3], Frame(requestID: 0, body: .appStateChanged(.background)))
        XCTAssertEqual(frames[4], environment(3, .none))
    }

    func test_S_ENV_02_setEnvironmentReplacesEveryOverride() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        let three = Traits(
            userInterfaceStyle: .dark,
            contentSizeCategory: .accessibilityLarge,
            layoutDirection: .rightToLeft
        )
        let one = Traits(userInterfaceStyle: .dark)
        harness.receive(set(2, three), set(3, one), set(4, nil), Frame(requestID: 5, body: .getEnvironment))
        let frames = try await harness.frames(6)
        XCTAssertEqual(frames[2], environment(2, three))
        XCTAssertEqual(frames[3], environment(3, one), "the other two are no longer overridden")
        XCTAssertEqual(frames[4], environment(4, .none), "no overrides removes them all")
        XCTAssertEqual(frames[5], environment(5, .none))
        let applied = await MainActor.run { harness.environment.applied }
        XCTAssertEqual(applied, [three, one, .none])
    }

    func test_S_ENV_04_setEnvironmentNeedsAnActiveApp() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        // Both refusals apply: the app's state comes first (P-ENV-04).
        await MainActor.run { harness.environment.overridable = [.userInterfaceStyle] }
        harness.setAppState(.background)
        harness.receive(set(2, Traits(userInterfaceStyle: .dark, layoutDirection: .rightToLeft)))
        let frames = try await harness.frames(4)
        XCTAssertEqual(frames[3], error(2, .appNotActive, "the app is not active"))
        let applied = await MainActor.run { harness.environment.applied }
        XCTAssertEqual(applied, [], "nothing is applied while the app is not active")
    }

    func test_S_ENV_04_aKindThatCannotBeOverriddenIsNotSupported() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        await MainActor.run { harness.environment.overridable = [.userInterfaceStyle] }

        // The words of the `environment-rejected` fixture; the appearance is not applied either.
        harness.receive(
            set(2, Traits(userInterfaceStyle: .dark, layoutDirection: .rightToLeft)),
            Frame(requestID: 3, body: .getEnvironment)
        )
        let frames = try await harness.frames(4)
        XCTAssertEqual(frames[2], error(2, .notSupported, "the layout direction cannot be overridden on this device"))
        XCTAssertEqual(frames[3], environment(3, .none, overridable: [.userInterfaceStyle]))
        XCTAssertEqual(harness.endedCount, 0, "the connection stays")
    }

    func test_S_ENV_04_refusalNamesTheFirstKindThatCannotBeApplied() {
        let all = TraitKind.allCases
        XCTAssertNil(EnvironmentOverrides.refusal(of: .none, overridable: []))
        XCTAssertNil(EnvironmentOverrides.refusal(
            of: Traits(userInterfaceStyle: .dark),
            overridable: [.userInterfaceStyle]
        ))
        XCTAssertEqual(
            EnvironmentOverrides.refusal(of: Traits(verticalSizeClass: .compact), overridable: [.userInterfaceStyle]),
            WireError(code: .notSupported, message: "the vertical size class cannot be overridden on this device")
        )
        // A value this build does not know, even of a kind that can be overridden.
        XCTAssertEqual(
            EnvironmentOverrides.refusal(of: Traits(unknownKinds: [.contentSizeCategory]), overridable: all),
            WireError(code: .notSupported, message: "the content size category has a value this server does not know")
        )
    }

    func test_S_ENV_03_overridesAreRemovedHoweverTheSessionEnds() async throws {
        // The peer closes, a frame is malformed, the server stops. In the last case nothing was
        // overridden: removing nothing is harmless.
        let malformed = { (harness: SessionHarness) in
            harness.queue.async { harness.transport.deliver(Data([1, 2, 3])) }
        }
        let endings: [(name: String, overrides: Bool, end: (SessionHarness) -> Void)] = [
            ("the peer closes", true, { $0.closeFromThePeer() }),
            ("a malformed frame", true, malformed),
            ("the server stops", false, { $0.stop() })
        ]
        for (name, overrides, end) in endings {
            let harness = SessionHarness()
            try await harness.handshake()
            if overrides {
                harness.receive(set(2, Traits(userInterfaceStyle: .dark)))
                _ = try await harness.frames(3)
            }

            end(harness)
            try await waitUntil("the session ended: \(name)") { harness.endedCount == 1 }
            await harness.settle()
            let (removals, remaining) = await MainActor
                .run { (harness.environment.removals, harness.environment.overrides) }
            XCTAssertEqual(removals, 1, name)
            XCTAssertEqual(remaining, .none, name)
        }
    }
}
