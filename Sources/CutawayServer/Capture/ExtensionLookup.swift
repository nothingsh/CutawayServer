#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import UIKit

/// Finds what the host app registered for a layer (S-API-04): the descriptions of the layer's
/// classes and of its view's, merged. One lookup serves one request; it remembers each class's
/// descriptions, so that a class is looked up along its superclasses once.
@MainActor
struct ExtensionLookup {
    /// What applies to one layer.
    struct Resolved {
        /// A description and the object it describes.
        struct Source {
            let description: ExtensionStore.Description
            let subject: AnyObject
        }

        /// Every description with groups: the layer's before the view's, each from the
        /// superclass down.
        var attributeSources: [Source] = []
        /// The most specific description with virtual children, a view's before a layer's.
        var virtualSource: Source?
        var isCollapsedByDefault = false
        var isExcludedFromCapture = false

        /// The virtual children the host app gives now; empty when it describes none.
        func virtualChildren() -> [CutawayServer.VirtualNode] {
            guard let source = virtualSource else { return [] }
            return source.description.virtualChildren?(source.subject) ?? []
        }
    }

    let store: ExtensionStore
    private var viewChains: [ObjectIdentifier: [ExtensionStore.Description]] = [:]
    private var layerChains: [ObjectIdentifier: [ExtensionStore.Description]] = [:]

    init(store: ExtensionStore) {
        self.store = store
    }

    /// What applies to `layer`, which backs `view` when there is one.
    mutating func resolve(_ layer: CALayer, view: UIView?) -> Resolved {
        var resolved = Resolved()
        guard !(store.viewDescriptions.isEmpty && store.layerDescriptions.isEmpty) else { return resolved }
        let layers = chain(of: type(of: layer), in: store.layerDescriptions, cache: &layerChains)
            .map { Resolved.Source(description: $0, subject: layer) }
        let views = view.map { view in
            chain(of: type(of: view), in: store.viewDescriptions, cache: &viewChains)
                .map { Resolved.Source(description: $0, subject: view) }
        } ?? []
        let all = layers + views
        resolved.attributeSources = all.filter { $0.description.attributes != nil }
        resolved.virtualSource = (views.reversed() + layers.reversed()).first { $0.description.virtualChildren != nil }
        resolved.isCollapsedByDefault = all.contains { $0.description.isCollapsedByDefault }
        resolved.isExcludedFromCapture = all.contains { $0.description.isExcludedFromCapture }
        return resolved
    }

    /// The descriptions registered for `type` and its superclasses, the superclass's first.
    private func chain(
        of type: AnyClass,
        in descriptions: [ObjectIdentifier: ExtensionStore.Description],
        cache: inout [ObjectIdentifier: [ExtensionStore.Description]]
    ) -> [ExtensionStore.Description] {
        let key = ObjectIdentifier(type)
        if let known = cache[key] { return known }
        var found: [ExtensionStore.Description] = []
        var current: AnyClass? = type
        while let someClass = current {
            if let description = descriptions[ObjectIdentifier(someClass)] { found.append(description) }
            current = class_getSuperclass(someClass)
        }
        found.reverse()
        cache[key] = found
        return found
    }
}
#endif
