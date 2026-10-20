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
    /// Virtual nodes (P-HIER-19): by their nearest layer ancestor and the identity the host app
    /// gave, and back. Read by the tests.
    private(set) var virtualIDs: [VirtualKey: UInt64] = [:]
    private var virtualKeys: [UInt64: VirtualKey] = [:]
    private var lastID: UInt64 = 0

    /// What identifies a virtual node within a connection.
    struct VirtualKey: Hashable {
        /// The ID of its nearest layer ancestor; layer IDs are never given out again, so neither
        /// are the keys under a released layer.
        let layerID: UInt64
        let identity: AnyHashable
    }

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

    /// The ID of the virtual node with this identity under the layer `layerID`; a new one the
    /// first time, from the same counter as the layers' (P-HIER-19).
    func register(virtual identity: AnyHashable, under layerID: UInt64) -> UInt64 {
        let key = VirtualKey(layerID: layerID, identity: identity)
        if let id = virtualIDs[key] { return id }
        lastID += 1
        virtualIDs[key] = lastID
        virtualKeys[lastID] = key
        return lastID
    }

    /// The nearest layer ancestor and the identity of the virtual node with this ID; `nil` for
    /// any other ID.
    func virtualNode(for id: UInt64) -> VirtualKey? {
        virtualKeys[id]
    }

    /// The layer with this ID, if it is still alive; `nil` for the ID of another kind of
    /// object.
    func layer(for id: UInt64) -> CALayer? {
        guard let key = keys[id] else { return nil }
        return entries[key]?.object as? CALayer
    }

    /// Forgets the objects that were released, and the virtual nodes under released layers.
    func removeReleased() {
        let released = entries.filter { $0.value.object == nil }
        for (key, entry) in released {
            entries[key] = nil
            keys[entry.id] = nil
        }
        guard !released.isEmpty, !virtualKeys.isEmpty else { return }
        for (id, key) in virtualKeys where keys[key.layerID] == nil {
            virtualKeys[id] = nil
            virtualIDs[key] = nil
        }
    }
}
#endif
