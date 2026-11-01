#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire

// Hierarchy change notifications (protocol 1.3, P-WATCH-01 to 09): how the session reaches the
// connection's `HierarchyWatch`, on the main thread, and the requests that tell it what the
// client was told or what changed.
extension HostAccess {
    /// What a `GetHierarchy` or `GetSubtree` read, and the baseline it gives once it is sent.
    struct Captured<Candidate: Sendable>: Sendable {
        var hierarchy: Hierarchy?
        var candidate: Candidate?
    }

    /// P-WATCH-01: turns notifications on or off and answers the state after. `events` gets
    /// each `HierarchyChanged` on `queue`; `isActive` is the app's state as the session knows it.
    func setWatching(
        _ enabled: Bool,
        isActive: Bool,
        events: @escaping @Sendable (HierarchyChanged) -> Void,
        then answer: @escaping @Sendable (Bool) -> Void
    ) {
        let queue = self.queue
        perform(
            { _, connection in
                connection.watch.setEnabled(enabled, isActive: isActive) { changed in queue.async { events(changed) } }
                return connection.watch.isEnabled
            },
            then: answer
        )
    }

    /// P-WATCH-08: the app's state, as the session hears of it.
    func watchAppState(isActive: Bool) {
        onMain { [connection] in connection.watch.setActive(isActive) }
    }

    /// The connection ended: nothing more is checked.
    func stopWatching() {
        onMain { [connection] in connection.watch.stop() }
    }

    /// The hierarchy, with the baseline it gives while notifications are on: read in the same
    /// main thread block, so of the same moment.
    func captureHierarchy(
        version: ProtocolVersion,
        then answer: @escaping @Sendable (Captured<HierarchySignature.Snapshot>) -> Void
    ) {
        perform(
            version: version,
            { [connection] app, context in
                Captured(hierarchy: app.captureHierarchy(in: context), candidate: connection.watch.candidate())
            },
            then: answer
        )
    }

    /// The same for a subtree; `hierarchy` is `nil` when the layer does not exist (P-HIER-11).
    func captureSubtree(
        of rootID: UInt64,
        version: ProtocolVersion,
        then answer: @escaping @Sendable (Captured<[UInt64: HierarchySignature.Entry]>) -> Void
    ) {
        perform(
            version: version,
            { [connection] app, context in
                let hierarchy = app.captureSubtree(of: rootID, in: context)
                return Captured(
                    hierarchy: hierarchy,
                    candidate: hierarchy.flatMap { _ in connection.watch.candidate(ofSubtree: rootID) }
                )
            },
            then: answer
        )
    }

    /// A `Hierarchy` was sent (P-WATCH-02, P-WATCH-06): what the client was told.
    func didSendHierarchy(_ candidate: HierarchySignature.Snapshot?) {
        onMain { [connection] in connection.watch.didAnswerHierarchy(candidate) }
    }

    /// A subtree was sent (P-WATCH-06).
    func didSendSubtree(_ candidate: [UInt64: HierarchySignature.Entry]?) {
        onMain { [connection] in connection.watch.didAnswerSubtree(candidate) }
    }

    /// One `SetAttribute` (P-SET-01), whose window is then taken as told (P-WATCH-09).
    func setAttribute(
        _ change: SetAttribute,
        version: ProtocolVersion,
        then answer: @escaping @Sendable (Result<SetAttributeResult, WireError>) -> Void
    ) {
        performChange(
            version: version,
            { [connection] app, context in
                let result = app.setAttribute(change, in: context)
                // A refused value may have changed part of the app too (P-SET-05).
                connection.watch.didChangeAttribute(of: change.layerID)
                return result
            },
            then: answer
        )
    }
}
#endif
