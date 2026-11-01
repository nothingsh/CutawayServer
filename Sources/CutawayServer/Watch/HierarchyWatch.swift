#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import QuartzCore
import UIKit

/// Hierarchy change notifications for one connection (PROTOCOL.md, "Hierarchy changes"): when
/// to check, the baseline, and what a check reports. Made on the server queue with the
/// connection, used on the main thread only. Events go to the closure given when they are
/// turned on, which takes them to the session.
@MainActor
final class HierarchyWatch {
    /// How long things take; tests make them short.
    struct Timing: Sendable {
        /// The app holds still this long before a check (the request list's #11).
        var quiet: TimeInterval = 0.3
        /// When the app never holds still, outside tracking: one check this often.
        var continuous: TimeInterval = 2
        /// The app's activity asks for a check at most this often: one that wakes more often
        /// than `quiet`, such as a `Timer`, holds still in between each time.
        var checkInterval: TimeInterval = 1
        /// P-WATCH-08: two events at least this far apart.
        var interval: TimeInterval = 1
    }

    /// What the watch takes from outside; tests replace parts of it.
    struct Surroundings: Sendable {
        var timing = Timing()
        var now: @MainActor @Sendable () -> TimeInterval = { CACurrentMediaTime() }
        /// The windows a check reads (P-HIER-02).
        var windows: @MainActor @Sendable () -> [UIWindow] = { HostWindows.all() }
        /// Runs `work` on the main thread after `delay` seconds.
        var schedule: @MainActor @Sendable (_ delay: TimeInterval, _ work: @escaping @MainActor @Sendable () -> Void)
            -> Void = { delay, work in
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated(work) }
            }

        /// What tells the watch the app did something; `nil` for none.
        var makeActivity: @MainActor @Sendable () -> (any ActivitySource)? = { RunLoopActivity() }
    }

    private let registry: LayerRegistry
    private let surroundings: Surroundings
    private var timing: Timing { surroundings.timing }

    /// P-WATCH-01: off when the connection begins.
    private(set) var isEnabled = false
    private var isActive = true
    /// P-WATCH-02: a `GetHierarchy` was answered, and no successful `SetEnvironment` since.
    private(set) var hasAnsweredHierarchy = false
    /// P-WATCH-06; `nil` while off, and until it can be set from what the client was told.
    private(set) var baseline: HierarchySignature.Snapshot?
    /// P-WATCH-09: the windows `SetAttribute` changed, by their root layers, with the time of
    /// the last change.
    private(set) var absorbing: [UInt64: TimeInterval] = [:]
    private var send: (@Sendable (HierarchyChanged) -> Void)?
    private var activity: (any ActivitySource)?

    private var lastEvent = -TimeInterval.infinity
    private var lastCheck = -TimeInterval.infinity
    /// The first activity since the last check, and the latest; whether the latest was in
    /// tracking (the person's finger on the screen).
    private var firstActivity: TimeInterval?
    private var lastActivity = -TimeInterval.infinity
    private var isTracking = false
    /// Check without waiting for activity (P-WATCH-08): turned on, or active again.
    private var checksSoon = false
    /// Only the latest wake counts.
    private var wakeGeneration = 0
    /// The run loop turn of the watch's own wake is not the app's activity. Only a wake starts
    /// a turn of its own: a check made while the observer is told of a turn is part of that turn.
    private var ignoresNextActivity = false

    nonisolated init(registry: LayerRegistry, surroundings: Surroundings = Surroundings()) {
        self.registry = registry
        self.surroundings = surroundings
    }

    // MARK: - Requests

    /// P-WATCH-01: turns notifications on or off. On, the app's state is `isActive`, and the
    /// events go to `send`.
    func setEnabled(_ enabled: Bool, isActive: Bool, send: @escaping @Sendable (HierarchyChanged) -> Void) {
        self.isActive = isActive
        guard enabled else {
            stop()
            return
        }
        self.send = send
        if !isEnabled {
            isEnabled = true
            activity = surroundings.makeActivity()
            activity?.start { [weak self] tracking in self?.noteActivity(tracking: tracking) }
            checkSoon()
        }
    }

    /// Off, as when the connection ends: nothing is kept, and nothing runs any more.
    func stop() {
        isEnabled = false
        activity?.stop()
        activity = nil
        send = nil
        baseline = nil
        absorbing = [:]
        firstActivity = nil
        checksSoon = false
        wakeGeneration += 1
    }

    /// The baseline a `GetHierarchy` answered now would give; `nil` while off.
    func candidate() -> HierarchySignature.Snapshot? {
        guard isEnabled else { return nil }
        return HierarchySignature.snapshot(of: surroundings.windows(), registry: registry)
    }

    /// The same for a `GetSubtree` of `rootID`; `nil` while off or for a virtual node.
    func candidate(ofSubtree rootID: UInt64) -> [UInt64: HierarchySignature.Entry]? {
        guard isEnabled, let layer = registry.layer(for: rootID) else { return nil }
        return HierarchySignature.entries(ofSubtree: layer, registry: registry)
    }

    /// A `Hierarchy` went out, read with `candidate` (P-WATCH-02, P-WATCH-06). Read while off,
    /// it leaves no baseline, and the first check once on reports the whole.
    func didAnswerHierarchy(_ candidate: HierarchySignature.Snapshot?) {
        hasAnsweredHierarchy = true
        guard isEnabled else { return }
        if let candidate {
            // As fresh as a check: no need for one soon.
            baseline = candidate
            checksSoon = false
        } else {
            // Turned on while it was being read: the whole, once it can be sent.
            checkSoon()
        }
    }

    /// A subtree went out: its nodes as told; the rest stays (P-WATCH-06).
    func didAnswerSubtree(_ entries: [UInt64: HierarchySignature.Entry]?) {
        guard isEnabled, let entries, baseline != nil else { return }
        baseline?.entries.merge(entries) { _, told in told }
    }

    /// P-WATCH-02: after a successful `SetEnvironment`, no event until the next `GetHierarchy`
    /// is answered, which sets the baseline again.
    func didChangeEnvironment() {
        hasAnsweredHierarchy = false
        baseline = nil
    }

    /// P-WATCH-09: the window that holds the layer, or the virtual node's nearest layer
    /// ancestor, is taken as told until the check after the changes stop.
    func didChangeAttribute(of id: UInt64) {
        guard isEnabled else { return }
        guard let layer = registry.layer(for: id)
            ?? registry.virtualNode(for: id).flatMap({ registry.layer(for: $0.layerID) }) else { return }
        let root = LayerTopology.ancestors(of: layer, in: surroundings.windows())?.first ?? layer
        absorbing[registry.register(root)] = surroundings.now()
    }

    /// P-WATCH-08: no check while the app is not active, and one when it is again.
    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if active { checkSoon() }
    }

    // MARK: - When to check

    /// The app did something on the main thread; `tracking` while the person's finger is on
    /// the screen.
    func noteActivity(tracking: Bool) {
        guard isEnabled else { return }
        if ignoresNextActivity {
            ignoresNextActivity = false
            return
        }
        let now = surroundings.now()
        if firstActivity == nil { firstActivity = now }
        lastActivity = now
        isTracking = tracking
        evaluate()
    }

    private func checkSoon() {
        checksSoon = true
        evaluate()
    }

    /// Checks now if it is time, or wakes when it will be. While the person scrolls, it waits
    /// for them to stop: the protocol lets a check be delayed (P-WATCH-05), and this one would
    /// cost frames.
    private func evaluate() {
        guard isEnabled, isActive, hasAnsweredHierarchy else { return }
        let now = surroundings.now()
        var due: TimeInterval
        if checksSoon {
            due = now
        } else {
            guard let firstActivity, !isTracking else { return }
            due = min(lastActivity + timing.quiet, firstActivity + timing.continuous)
            due = max(due, lastCheck + timing.checkInterval)
        }
        due = max(due, lastEvent + timing.interval)
        if due <= now {
            // Still since the last activity: what changed before it has stopped (P-WATCH-09).
            let isStill = !checksSoon && firstActivity != nil && now >= lastActivity + timing.quiet
            check(releasingChangesBefore: isStill ? lastActivity : nil)
        } else {
            wake(after: due - now)
        }
    }

    private func wake(after delay: TimeInterval) {
        wakeGeneration += 1
        let generation = wakeGeneration
        surroundings.schedule(delay) { [weak self] in
            guard let self else { return }
            // A wake that came too late still turned the run loop: that turn is not the app's,
            // or every stale wake would push the check back again.
            self.ignoresNextActivity = true
            guard generation == self.wakeGeneration else { return }
            self.evaluate()
        }
    }

    /// Compares the windows with the baseline, takes what it read as the new one, and reports
    /// what changed. Without a baseline, the whole (P-WATCH-03). The windows changed by
    /// `SetAttribute` at or before `releasingChangesBefore` are watched again after it.
    private func check(releasingChangesBefore stopped: TimeInterval?) {
        checksSoon = false
        firstActivity = nil
        let now = HierarchySignature.snapshot(of: surroundings.windows(), registry: registry)
        let time = surroundings.now()
        lastCheck = time
        let changes: HierarchyChanged?
        if let baseline {
            changes = HierarchySignature.changes(from: baseline, to: now, absorbing: Set(absorbing.keys))
        } else {
            changes = .everything
        }
        baseline = now
        if let stopped { absorbing = absorbing.filter { $0.value > stopped } }
        registry.removeReleased()
        guard let changes else { return }
        lastEvent = time
        send?(changes)
    }
}

/// What tells a watch the app did something on the main thread.
@MainActor
protocol ActivitySource: AnyObject {
    /// `handler` gets whether the main run loop is in tracking mode.
    func start(_ handler: @escaping @MainActor (_ tracking: Bool) -> Void)
    func stop()
}
#endif
