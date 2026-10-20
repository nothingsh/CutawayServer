#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import UIKit

/// What the host app registered through the extension interface (S-API-04). The public
/// methods write the shared store; tests make stores of their own. Main thread only, read
/// afresh by every request.
@MainActor
final class ExtensionStore {
    /// A `CutawayServer.Description` with its subject's type erased.
    struct Description {
        let attributes: ((AnyObject) -> [CutawayServer.AttributeGroup])?
        let virtualChildren: ((AnyObject) -> [CutawayServer.VirtualNode])?
        let isCollapsedByDefault: Bool
        let isExcludedFromCapture: Bool
        /// The registered class, which the description's groups name when they give no type.
        let registeredClass: AnyClass
    }

    /// One registered color.
    struct NamedColor {
        let name: String
        let color: UIColor
    }

    static let shared = ExtensionStore()

    /// By the registered class, the views' apart from the layers'.
    private(set) var viewDescriptions: [ObjectIdentifier: Description] = [:]
    private(set) var layerDescriptions: [ObjectIdentifier: Description] = [:]
    /// In the order they were registered (P-ATTR-20).
    private(set) var colors: [NamedColor] = []

    nonisolated init() {}

    /// Nothing is registered: captures need not look anything up.
    var isEmpty: Bool { viewDescriptions.isEmpty && layerDescriptions.isEmpty && colors.isEmpty }

    func describe<Subject: AnyObject>(
        _ type: Subject.Type,
        _ description: CutawayServer.Description<Subject>,
        isView: Bool
    ) {
        let erased = Description(
            attributes: description.attributes.map { attributes in
                { object in (object as? Subject).map(attributes) ?? [] }
            },
            virtualChildren: description.virtualChildren.map { children in
                { object in (object as? Subject).map(children) ?? [] }
            },
            isCollapsedByDefault: description.isCollapsedByDefault,
            isExcludedFromCapture: description.isExcludedFromCapture,
            registeredClass: type
        )
        if isView {
            viewDescriptions[ObjectIdentifier(type)] = erased
        } else {
            layerDescriptions[ObjectIdentifier(type)] = erased
        }
    }

    func registerColor(_ color: UIColor, named name: String) {
        if let index = colors.firstIndex(where: { $0.name == name }) {
            colors[index] = NamedColor(name: name, color: color)
        } else {
            colors.append(NamedColor(name: name, color: color))
        }
    }

    /// Forgets everything; for tests that register on the shared store.
    func removeAll() {
        viewDescriptions = [:]
        layerDescriptions = [:]
        colors = []
    }
}
#endif
