import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// `WatchHierarchy` and `HierarchyChanged` through a session (PROTOCOL.md, P-WATCH-01,
/// P-WATCH-02, P-REQ-02, P-APP-01): the answers, the versions, and an event of the real watch,
/// with the main run loop's own activity.
final class WatchSessionTests: CaptureTestCase {
    private func watch(_ requestID: UInt32, _ enabled: Bool) -> Frame {
        Frame(requestID: requestID, body: .watchHierarchy(enabled: enabled))
    }

    func test_S_WATCH_01_answersWithTheStateAfter() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        harness.receive(watch(1, true), watch(2, true), watch(3, false), watch(4, false))
        let frames = try await harness.frames(6)
        XCTAssertEqual(
            Array(frames[2...]),
            [
                Frame(requestID: 1, body: .watchHierarchyResult(enabled: true)),
                Frame(requestID: 2, body: .watchHierarchyResult(enabled: true)),
                Frame(requestID: 3, body: .watchHierarchyResult(enabled: false)),
                Frame(requestID: 4, body: .watchHierarchyResult(enabled: false))
            ]
        )
    }

    /// P-APP-01 does not apply: answered while the app is in the background.
    func test_S_WATCH_01_answeredWhileNotActive() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        harness.setAppState(.background)
        _ = try await harness.frames(3)
        harness.receive(watch(1, true))
        let frames = try await harness.frames(4)
        XCTAssertEqual(frames[3], Frame(requestID: 1, body: .watchHierarchyResult(enabled: true)))
        XCTAssertTrue(harness.watch.isEnabled)
    }

    func test_S_CONN_12_aClientOf1_2CannotWatch() async throws {
        let harness = SessionHarness()
        try await harness.handshake(version: ProtocolVersion(major: 1, minor: 2))
        harness.receive(watch(1, true))
        let frames = try await harness.frames(3)
        XCTAssertEqual(frames[2], Frame(requestID: 1, body: .error(.unexpectedMessage)))
        XCTAssertFalse(harness.watch.isEnabled)
    }

    /// A successful `SetEnvironment` stops events until the next hierarchy; a refused one
    /// changes nothing.
    func test_S_WATCH_02_aSuccessfulEnvironmentWaitsForTheHierarchy() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        harness.receive(watch(1, true), Frame(requestID: 2, body: .getHierarchy))
        _ = try await harness.frames(4)
        await harness.settle()
        XCTAssertTrue(harness.watch.hasAnsweredHierarchy)

        harness.environment.overridable = [.userInterfaceStyle]
        harness.receive(Frame(requestID: 3, body: .setEnvironment(overrides: Traits(layoutDirection: .rightToLeft))))
        _ = try await harness.frames(5)
        XCTAssertTrue(harness.watch.hasAnsweredHierarchy, "refused")

        harness.receive(Frame(requestID: 4, body: .setEnvironment(overrides: Traits(userInterfaceStyle: .dark))))
        _ = try await harness.frames(6)
        XCTAssertFalse(harness.watch.hasAnsweredHierarchy)

        harness.receive(Frame(requestID: 5, body: .getHierarchy))
        _ = try await harness.frames(7)
        await harness.settle()
        XCTAssertTrue(harness.watch.hasAnsweredHierarchy)
        XCTAssertNotNil(harness.watch.baseline)
    }

    /// The real watch: a view moves after the hierarchy was answered, the main run loop turns,
    /// and an event with `request_id` 0 names the view.
    func test_S_WATCH_02_aChangeBecomesAnEvent() async throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        window.addSubview(view)
        let harness = SessionHarness()
        try await harness.handshake()
        harness.receive(watch(1, true), Frame(requestID: 2, body: .getHierarchy))
        _ = try await harness.frames(4)
        await harness.settle()

        view.frame.origin.x += 7
        let id = harness.connectionRegistry.register(view.layer)
        let transport = harness.transport
        try await waitUntil("an event naming the view", timeout: 5) {
            transport.sent.contains { frame in
                guard case .hierarchyChanged(let changed)? = frame.body else { return false }
                return frame.requestID == 0 && changed.roots.contains(id)
            }
        }
        // None before the answers.
        let firstEvent = try XCTUnwrap(transport.sent
            .firstIndex { if case .hierarchyChanged? = $0.body { true } else { false } })
        XCTAssertGreaterThanOrEqual(firstEvent, 4)

        // Off: none after the answer.
        harness.receive(watch(3, false))
        let count = try await harness.frames(transport.sent.count + 1).count
        view.frame.origin.x += 7
        try await Task.sleep(nanoseconds: 800_000_000)
        XCTAssertEqual(transport.sent.count, count)
    }
}
