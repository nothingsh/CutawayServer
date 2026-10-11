@testable import CutawayServer

// What the tests count in a registry. `entries` is `private(set)` for this purpose.

extension LayerRegistry {
    /// How many objects the registry knows, released or not.
    var count: Int { entries.count }

    /// How many of the objects the registry knows are still alive.
    var liveCount: Int { entries.values.filter { $0.object != nil }.count }

    /// The IDs of the objects that were released and are not forgotten yet.
    var releasedIDs: Set<UInt64> { Set(entries.values.filter { $0.object == nil }.map(\.id)) }
}
