#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Reads the attribute groups of the nodes of one request: the server's own, then the host
/// app's (P-ATTR-19), with the names of the colors it registered (P-ATTR-20). A virtual node
/// has only the host app's (P-DET-09).
@MainActor
final class NodeAttributes {
    let catalog: AttributeCatalog
    let context: RequestContext
    let reading: AttributeReading
    private let colors: ColorNames.Registered

    /// - Parameter context: The request's windows, registry, and what the host app registered.
    init(catalog: AttributeCatalog = .standard, context: RequestContext) {
        self.catalog = catalog
        self.context = context
        reading = AttributeReading(registry: context.registry, windows: context.windows)
        colors = ColorNames.Registered(context.extensions.store)
    }

    /// `nil` when the host app registered nothing.
    private var lookup: ExtensionLookup? {
        context.extensions.isEmpty ? nil : context.extensions
    }

    /// Every group of `layer`.
    func read(_ layer: CALayer) -> [AttributeGroup] {
        let own = catalog.read(layer, reading: reading)
        guard lookup != nil else { return own }
        return named(own + app(of: layer, alongside: own).groups, in: LayerTopology.nearestView(of: layer))
    }

    /// Every group of a virtual node.
    func read(_ node: VirtualNodes.Found) -> [AttributeGroup] {
        named(app(of: node).groups, in: LayerTopology.nearestView(of: node.layer))
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

    /// The host app's groups of a virtual node, which it works out now.
    func app(of node: VirtualNodes.Found) -> AppAttributes {
        AppAttributes(
            [AppAttributes.Source(groups: node.node.attributes(), className: node.node.className)],
            alongside: [],
            view: LayerTopology.nearestView(of: node.layer),
            reading: reading
        )
    }

    /// The virtual node with this ID, as `VirtualNodes.find` finds it.
    func virtualNode(_ id: UInt64) -> VirtualNodes.Found? {
        guard lookup != nil else { return nil }
        return VirtualNodes.find(id, in: context)
    }

    /// `groups` with the names of the registered colors their values equal.
    private func named(_ groups: [AttributeGroup], in view: UIView?) -> [AttributeGroup] {
        ColorNames.named(groups, registered: colors, cache: context.memo.entry(ColorNames.Cache.init), in: view)
    }
}
#endif
