#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import QuartzCore

/// Gives the layers of one connection their IDs and finds a layer by its ID
/// (PROTOCOL.md, P-HIER-03). Constraints and layout guides get their IDs here too, from the
/// same counter (P-LAYOUT-03). It holds every object weakly and writes nothing onto it.
@MainActor
final class LayerRegistry {
    struct Entry {
        var id: UInt64
        weak var object: AnyObject?
    }

    /// Keyed by the object's address. An address can be taken over by a new object once the
    /// old one is released, so an entry only counts while its weak reference still is that
    /// object. Read by the tests.
    private(set) var entries: [ObjectIdentifier: Entry] = [:]
    private var keys: [UInt64: ObjectIdentifier] = [:]
    private var lastID: UInt64 = 0

    /// The registry is created on the server queue and used on the main thread.
    nonisolated init() {}

    /// The object's ID in this connection — a layer, a constraint or a layout guide; a new one
    /// the first time the object is seen. IDs start at 1 and are never given out twice.
    func register(_ object: AnyObject) -> UInt64 {
        let key = ObjectIdentifier(object)
        if let entry = entries[key] {
            if entry.object === object { return entry.id }
            // The address belongs to a new object: the one that had it was released.
            keys[entry.id] = nil
        }
        lastID += 1
        entries[key] = Entry(id: lastID, object: object)
        keys[lastID] = key
        return lastID
    }

    /// The layer with this ID, if it is still alive; `nil` for the ID of another kind of
    /// object.
    func layer(for id: UInt64) -> CALayer? {
        guard let key = keys[id] else { return nil }
        return entries[key]?.object as? CALayer
    }

    /// Forgets the objects that were released.
    func removeReleased() {
        let released = entries.filter { $0.value.object == nil }
        for (key, entry) in released {
            entries[key] = nil
            keys[entry.id] = nil
        }
    }
}
#endif
