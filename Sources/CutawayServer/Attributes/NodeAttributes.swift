#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Reads the attribute groups of the nodes of one request: the server's own, then the host
/// app's (P-ATTR-19), with the names of the colors it registered (P-ATTR-20). A virtual node
/// has only the host app's (P-DET-09).
@MainActor
final class NodeAttributes {
    let catalog: AttributeCatalog
    let reading: AttributeReading
    private let colors: [ExtensionStore.NamedColor]
    private var lookup: ExtensionLookup?

    /// - Parameter extensions: What the host app registered; `nil` for nothing.
    init(catalog: AttributeCatalog = .standard, reading: AttributeReading, extensions: ExtensionStore?) {
        self.catalog = catalog
        self.reading = reading
        colors = extensions?.colors ?? []
        lookup = extensions.flatMap { $0.isEmpty ? nil : ExtensionLookup(store: $0) }
    }

    /// Every group of `layer`.
    func read(_ layer: CALayer) -> [AttributeGroup] {
        let own = catalog.read(layer, reading: reading)
        guard lookup != nil else { return own }
        let view = LayerTopology.nearestView(of: layer)
        return ColorNames.named(own + app(of: layer, alongside: own).groups, colors: colors, in: view)
    }

    /// Every group of a virtual node.
    func read(_ node: VirtualNodes.Found) -> [AttributeGroup] {
        ColorNames.named(app(of: node).groups, colors: colors, in: LayerTopology.nearestView(of: node.layer))
    }

    /// The host app's groups of `layer`, beside its own groups `own`.
    func app(of layer: CALayer, alongside own: [AttributeGroup]) -> AppAttributes {
        let view = LayerTopology.backingView(of: layer)
        let sources = lookup?.resolve(layer, view: view).attributeSources ?? []
        return AppAttributes(
            sources.map { source in
                AppAttributes.Source(
                    groups: source.description.attributes?(source.subject) ?? [],
                    className: ClassNames.runtimeName(of: source.description.registeredClass)
                )
            },
            alongside: own,
            view: view ?? LayerTopology.nearestView(of: layer),
            reading: reading
        )
    }

    /// The host app's groups of a virtual node.
    func app(of node: VirtualNodes.Found) -> AppAttributes {
        AppAttributes(
            [AppAttributes.Source(groups: node.node.attributes, className: node.node.className)],
            alongside: [],
            view: LayerTopology.nearestView(of: node.layer),
            reading: reading
        )
    }

    /// The virtual node with this ID, as `VirtualNodes.find` finds it.
    func virtualNode(_ id: UInt64) -> VirtualNodes.Found? {
        guard var current = lookup else { return nil }
        defer { lookup = current }
        return VirtualNodes.find(id, windows: reading.windows, registry: reading.registry, lookup: &current)
    }
}
#endif
