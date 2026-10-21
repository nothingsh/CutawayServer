#if canImport(UIKit) && (DEBUG || ReleaseEnabled)

/// What one request works out once and shares among its parts, dropped when it ends: the
/// registered colors as they resolve, and the virtual trees a details stream finds its nodes
/// in. A `GetLayerDetails` stream is one request, though each of its layers has a
/// `RequestContext` of its own; every other request has one memo with its one context.
/// Each part of the server keeps one entry, an object of a type of its own, so that this file
/// needs to know none of them.
@MainActor
final class RequestMemo {
    private var entries: [ObjectIdentifier: AnyObject] = [:]

    nonisolated init() {}

    /// The entry of type `Entry`, made with `make` the first time.
    func entry<Entry: AnyObject>(_ make: () -> Entry) -> Entry {
        let key = ObjectIdentifier(Entry.self)
        if let known = entries[key] as? Entry { return known }
        let made = make()
        entries[key] = made
        return made
    }

    /// Drops the entries on the main thread, once the request is over. What they hold may come
    /// from the host app's closures, and may hold the last reference to a view; the memo itself
    /// may be released elsewhere.
    nonisolated func discard() {
        onMain { self.entries.removeAll() }
    }
}
#endif
