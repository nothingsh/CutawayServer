import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// When a watch checks and what it sends (PROTOCOL.md, P-WATCH-01, 02, 04 to 06, 08, 09),
/// with a clock and a scheduler the test moves by hand and no run loop observer: the test
/// tells the watch of the app's activity itself.
final class HierarchyWatchTests: CaptureTestCase {
    /// The clock and the work scheduled on it. Each piece of work runs in a turn of the main
    /// run loop of its own, which ends as every turn does: the watch is told of it.
    @MainActor
    private final class Time {
        var now: TimeInterval = 1000
        var endOfTurn: () -> Void = {}
        /// How often the watch read the windows; a check does once, whatever it finds.
        var windowReads = 0
        private var scheduled: [(at: TimeInterval, work: @MainActor @Sendable () -> Void)] = []

        var pending: [TimeInterval] { scheduled.map(\.at) }

        func schedule(_ delay: TimeInterval, _ work: @escaping @MainActor @Sendable () -> Void) {
            scheduled.append((now + delay, work))
        }

        /// Moves on by `seconds`, running what falls due, in order.
        func advance(_ seconds: TimeInterval) {
            let end = now + seconds
            while let next = scheduled.enumerated().filter({ $0.element.at <= end })
                .min(by: { $0.element.at < $1.element.at }) {
                scheduled.remove(at: next.offset)
                now = next.element.at
                next.element.work()
                endOfTurn()
            }
            now = end
        }
    }

    /// What the watch sent, on the main thread.
    @MainActor
    private final class Sent {
        var events: [HierarchyChanged] = []
    }

    private let registry = LayerRegistry()
    private let time = Time()
    private let sent = Sent()
    private var windows: [UIWindow] = []

    private func makeWatch() -> HierarchyWatch {
        let time = self.time
        let windows = self.windows
        var surroundings = HierarchyWatch.Surroundings()
        surroundings.now = { time.now }
        surroundings.schedule = { delay, work in time.schedule(delay, work) }
        surroundings.windows = {
            time.windowReads += 1
            return windows
        }
        surroundings.makeActivity = { nil }
        let watch = HierarchyWatch(registry: registry, surroundings: surroundings)
        time.endOfTurn = { [weak watch] in watch?.noteActivity(tracking: false) }
        return watch
    }

    /// A window with one view, a watch of it that is on, and a hierarchy answered.
    private func makeWatched(answered: Bool = true) throws -> (watch: HierarchyWatch, view: UIView) {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        window.addSubview(view)
        windows = [window]
        let watch = makeWatch()
        enable(watch)
        if answered { watch.didAnswerHierarchy(watch.candidate()) }
        return (watch, view)
    }

    private func enable(_ watch: HierarchyWatch, active: Bool = true) {
        let sent = self.sent
        watch.setEnabled(true, isActive: active) { changed in
            MainActor.assumeIsolated { sent.events.append(changed) }
        }
    }

    private func root(_ view: UIView) -> HierarchyChanged {
        HierarchyChanged(roots: [registry.register(view.layer)], whole: false)
    }

    /// The app changes something and holds still.
    private func change(_ watch: HierarchyWatch, _ work: () -> Void) {
        work()
        watch.noteActivity(tracking: false)
        time.advance(0.31)
    }

    // MARK: - S-WATCH-02

    func test_S_WATCH_02_eventsOnlyOnceAHierarchyWasAnswered() throws {
        let (watch, view) = try makeWatched(answered: false)
        change(watch) { view.frame.origin.x += 1 }
        XCTAssertEqual(sent.events, [])

        watch.didAnswerHierarchy(watch.candidate())
        change(watch) { view.frame.origin.x += 1 }
        XCTAssertEqual(sent.events, [root(view)])
    }

    /// Turned on after the hierarchy was answered: no baseline, so the whole, at once.
    func test_S_WATCH_02_turnedOnAfterTheHierarchyGivesTheWhole() throws {
        let window = try makeWindow()
        windows = [window]
        let watch = makeWatch()
        watch.didAnswerHierarchy(watch.candidate())
        XCTAssertNil(watch.candidate())
        enable(watch)
        XCTAssertEqual(sent.events, [.everything])
        // Then as usual.
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: 5))
        time.advance(1)
        change(watch) { window.addSubview(view) }
        XCTAssertEqual(
            sent.events,
            [.everything, HierarchyChanged(roots: [registry.register(window.layer)], whole: false)]
        )
    }

    func test_S_WATCH_02_offSendsNothing() throws {
        let (watch, view) = try makeWatched()
        watch.setEnabled(false, isActive: true) { _ in }
        XCTAssertFalse(watch.isEnabled)
        XCTAssertNil(watch.baseline)
        change(watch) { view.frame.origin.x += 1 }
        XCTAssertEqual(sent.events, [])
        XCTAssertEqual(time.pending, [])
    }

    /// After a successful `SetEnvironment`, nothing until the next hierarchy is answered.
    func test_S_WATCH_02_nothingAfterAnEnvironmentUntilTheNextHierarchy() throws {
        let (watch, view) = try makeWatched()
        watch.didChangeEnvironment()
        change(watch) { view.frame.origin.x += 1 }
        XCTAssertEqual(sent.events, [])

        watch.didAnswerHierarchy(watch.candidate())
        change(watch) { view.frame.origin.x += 1 }
        XCTAssertEqual(sent.events, [root(view)])
    }

    // MARK: - S-WATCH-04

    /// A change is reported once, whether or not the client gets it.
    func test_S_WATCH_04_aChangeIsReportedOnce() throws {
        let (watch, view) = try makeWatched()
        change(watch) { view.frame.origin.x += 1 }
        time.advance(1)
        change(watch) {}
        XCTAssertEqual(sent.events, [root(view)])
    }

    /// What a subtree told is not reported; its root's place is.
    func test_S_WATCH_04_aSubtreeAnsweredIsTold() throws {
        let (watch, view) = try makeWatched()
        view.frame.origin.x += 1
        watch.didAnswerSubtree(watch.candidate(ofSubtree: registry.register(view.layer)))
        change(watch) {}
        XCTAssertEqual(sent.events, [])
    }

    /// Changed while off: reported once on again, as the whole (no baseline).
    func test_S_WATCH_04_changesWhileOffComeWhenOn() throws {
        let (watch, view) = try makeWatched()
        watch.setEnabled(false, isActive: true) { _ in }
        view.frame.origin.x += 1
        enable(watch)
        XCTAssertEqual(sent.events, [.everything])
    }

    // MARK: - S-WATCH-05

    func test_S_WATCH_05_noActivityNoCheck() throws {
        let (watch, view) = try makeWatched()
        view.frame.origin.x += 1
        time.advance(10)
        XCTAssertEqual(sent.events, [])
        XCTAssertEqual(time.pending, [])
        _ = watch
    }

    /// A check 0.3 seconds after the app last did something.
    func test_S_WATCH_05_checksOnceStill() throws {
        let (watch, view) = try makeWatched()
        view.frame.origin.x += 1
        watch.noteActivity(tracking: false)
        time.advance(0.2)
        watch.noteActivity(tracking: false)
        time.advance(0.29)
        XCTAssertEqual(sent.events, [])
        time.advance(0.02)
        XCTAssertEqual(sent.events, [root(view)])
    }

    /// While the person's finger is on the screen, no check, however long; once it is off and
    /// the app holds still, one.
    func test_S_WATCH_05_noCheckWhileTracking() throws {
        let (watch, view) = try makeWatched()
        for _ in 0..<50 {
            view.frame.origin.x += 1
            watch.noteActivity(tracking: true)
            time.advance(0.1)
        }
        XCTAssertEqual(sent.events, [])
        watch.noteActivity(tracking: false)
        time.advance(0.31)
        XCTAssertEqual(sent.events, [root(view)])
    }

    /// An app that never holds still: a check every two seconds, a change at a time.
    func test_S_WATCH_05_continuousActivityChecksEveryTwoSeconds() throws {
        let (watch, view) = try makeWatched()
        var checkTimes: [TimeInterval] = []
        let start = time.now
        for _ in 0..<70 {
            view.frame.origin.x += 1
            let before = sent.events.count
            watch.noteActivity(tracking: false)
            time.advance(0.1)
            if sent.events.count > before { checkTimes.append(time.now - start) }
        }
        XCTAssertEqual(checkTimes.count, 3, "\(checkTimes)")
        for (index, seconds) in checkTimes.enumerated() {
            XCTAssertEqual(seconds, Double(index + 1) * 2, accuracy: 0.05, "\(checkTimes)")
        }
    }

    /// Two events at least a second apart; the change in between is not lost.
    func test_S_WATCH_05_eventsAreASecondApart() throws {
        let (watch, view) = try makeWatched()
        change(watch) { view.frame.origin.x += 1 }
        let first = time.now
        change(watch) { view.frame.origin.y += 1 }
        XCTAssertEqual(sent.events.count, 1)
        time.advance(1)
        XCTAssertEqual(sent.events, [root(view), root(view)])
        XCTAssertGreaterThanOrEqual(time.now - first, 1)
    }

    /// An app that does something every 0.4 seconds holds still in between each time: a check a
    /// second at most, not one each time, and the change made after a check is not lost.
    func test_S_WATCH_05_checksAreASecondApart() throws {
        let (watch, view) = try makeWatched()
        time.windowReads = 0
        watch.noteActivity(tracking: false)
        time.advance(0.4)
        view.frame.origin.x += 1
        for _ in 0..<9 {
            watch.noteActivity(tracking: false)
            time.advance(0.4)
        }
        XCTAssertEqual(time.windowReads, 4)
        XCTAssertEqual(sent.events, [root(view)])
    }

    /// Active again checks at once, however recent the last check was.
    func test_S_WATCH_05_activeAgainDoesNotWaitForTheCheckInterval() throws {
        let (watch, view) = try makeWatched()
        change(watch) {}
        XCTAssertEqual(sent.events, [])
        watch.setActive(false)
        view.frame.origin.x += 1
        watch.setActive(true)
        XCTAssertEqual(sent.events, [root(view)])
    }

    /// Not active: no check. Active again: one at once.
    func test_S_WATCH_05_noCheckWhileNotActive() throws {
        let (watch, view) = try makeWatched()
        watch.setActive(false)
        change(watch) { view.frame.origin.x += 1 }
        XCTAssertEqual(sent.events, [])
        watch.setActive(true)
        XCTAssertEqual(sent.events, [root(view)])
    }

    // MARK: - S-WATCH-06

    /// The window `SetAttribute` changed is taken as told until the check after the changes
    /// stop; another window is reported as usual.
    func test_S_WATCH_06_aChangedWindowIsTakenAsTold() throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        window.addSubview(view)
        let other = try makeWindow()
        let elsewhere = UIView(frame: CGRect(x: 0, y: 0, width: 5, height: 5))
        other.addSubview(elsewhere)
        windows = [window, other]
        let watch = makeWatch()
        enable(watch)
        watch.didAnswerHierarchy(watch.candidate())

        // Dragging: a change every 0.1 seconds for three seconds, with one elsewhere.
        for step in 0..<30 {
            view.frame.origin.x += 1
            watch.didChangeAttribute(of: registry.register(view.layer))
            if step == 5 { elsewhere.frame.origin.x += 1 }
            watch.noteActivity(tracking: false)
            time.advance(0.1)
        }
        time.advance(0.31)
        XCTAssertEqual(sent.events, [root(elsewhere)])
        XCTAssertEqual(watch.absorbing, [:])

        // Then the window is watched again.
        time.advance(1)
        change(watch) { view.frame.origin.y += 1 }
        XCTAssertEqual(sent.events, [root(elsewhere), root(view)])
    }
}
