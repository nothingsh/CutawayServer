#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Carries out one `SetAttribute` (PROTOCOL.md, P-SET-01 to P-SET-05). The server's own
/// attributes and the host app's are changed alike: each is looked up as an `AttributeEdit`,
/// checked, and changed by `commit`.
@MainActor
enum AttributeEditing {
    /// Checks the request, changes the attribute, lays the window out and reads the layer's
    /// attributes again. A request that fails a check changes nothing (P-SET-03): every check
    /// comes before the change. Whether the app is active is checked before, by the host
    /// (P-APP-01).
    ///
    /// - Parameters:
    ///   - context: The request's windows, registry, and what the host app registered.
    ///   - catalog: The attributes a layer has and how they are written.
    static func apply(
        _ request: SetAttribute,
        in context: RequestContext,
        catalog: AttributeCatalog = .standard
    ) -> Result<SetAttributeResult, WireError> {
        let attributes = NodeAttributes(catalog: catalog, context: context)
        let reading = attributes.reading
        // P-SET-03, in its order: the layer, the attribute, the value.
        guard let layer = context.registry.layer(for: request.layerID),
              let ancestors = LayerTopology.ancestors(of: layer, in: context.windows) else {
            guard let node = attributes.virtualNode(request.layerID) else {
                return .failure(.layerNotFound(request.layerID))
            }
            return apply(request, to: node, attributes: attributes)
        }
        // The window is the delegate of the topmost ancestor, or of the layer itself when it is
        // a window's.
        let window = (ancestors.first ?? layer).delegate as? UIWindow
        let id = request.attributeID
        let changed: Result<Void, WireError>
        if id.hasPrefix(AppAttributes.prefix) {
            // The host app's `set` may draw the layer anew: it is redrawn before the answer, so
            // that its images show the change.
            let app = attributes.app(of: layer, alongside: catalog.read(layer, reading: reading))
            changed = change(
                request,
                app.attributeForEditing(id),
                notFound: .notAnAttribute(id, of: "layer \(request.layerID)"),
                window: window,
                redrawing: layer
            )
        } else {
            changed = change(
                request,
                catalog.attributeForEditing(id, of: layer, reading: reading),
                notFound: notAnAttribute(id, of: layer, layerID: request.layerID),
                window: window
            )
        }
        return changed.map { SetAttributeResult(layerID: request.layerID, attributeGroups: attributes.read(layer)) }
    }

    /// P-SET-05 for a virtual node: it has only the host app's attributes (P-DET-09); the
    /// window and the layer redrawn are its nearest layer ancestor's.
    private static func apply(
        _ request: SetAttribute,
        to node: VirtualNodes.Found,
        attributes: NodeAttributes
    ) -> Result<SetAttributeResult, WireError> {
        let id = request.attributeID
        let what = "virtual node \(request.layerID)"
        guard id.hasPrefix(AppAttributes.prefix) else { return .failure(.onlyAppAttributes(id, of: what)) }
        let ancestors = LayerTopology.ancestors(of: node.layer, in: attributes.context.windows) ?? []
        let window = (ancestors.first ?? node.layer).delegate as? UIWindow
        let changed = change(
            request,
            attributes.app(of: node).attributeForEditing(id),
            notFound: .notAnAttribute(id, of: what),
            window: window,
            redrawing: node.layer
        )
        return changed.map {
            // Read again: the change may have changed the node's attributes, or the node itself.
            let groups = attributes.virtualNode(request.layerID).map(attributes.read) ?? []
            return SetAttributeResult(layerID: request.layerID, attributeGroups: groups)
        }
    }

    /// Why the server's attribute `id` is not one of `layer`'s: P-ATTR-11 leaves out the layer's
    /// side of a pair when the layer backs a view.
    private static func notAnAttribute(_ id: String, of layer: CALayer, layerID: UInt64) -> WireError {
        if let pair = AttributeTables.pairs.first(where: { $0.layer == id }),
           LayerTopology.backingView(of: layer) != nil {
            return .backsAView(layerID, set: pair.view, insteadOf: id)
        }
        return .notAnAttribute(id, of: "this layer")
    }

    /// P-SET-03: checks the request against `edit`, the attribute as it reads now, in this
    /// order: that it exists (`notFound` otherwise), that it can be changed, the rules of every
    /// attribute (`check`), and its own; then makes the change (`commit`).
    private static func change(
        _ request: SetAttribute,
        _ edit: AttributeEdit?,
        notFound: @autoclosure () -> WireError,
        window: UIWindow?,
        redrawing layer: CALayer? = nil
    ) -> Result<Void, WireError> {
        let id = request.attributeID
        guard let edit else { return .failure(notFound()) }
        // As it reads now: a value that fell back to text is read-only (P-ATTR-06).
        guard let prepare = edit.prepare else { return .failure(.readOnly(id)) }
        if let rejection = check(request.value, against: edit.attribute) {
            return .failure(.invalidValue(id, rejection.reason))
        }
        switch prepare(request.value) {
        case .failure(let rejection):
            return .failure(.invalidValue(id, rejection.reason))
        case .success(let change):
            return commit(change, layingOut: window, redrawing: layer)
        }
    }

    /// P-SET-05: makes a change that passed every check. No implicit animation, also for what
    /// the layout moves; the window is laid out and `layer` redrawn before the answer. A change
    /// that throws (the host app's `set` refusing the value) is the answer's message, after the
    /// layout all the same: the change may have changed part of the app.
    private static func commit(
        _ change: () throws -> Void,
        layingOut window: UIWindow?,
        redrawing layer: CALayer?
    ) -> Result<Void, WireError> {
        let refusal: (any Error)? = changeWithoutAnimation(
            .attributes,
            layingOut: window.map { [$0] } ?? [],
            redrawing: layer
        ) {
            do {
                try change()
                return nil
            } catch {
                return error
            }
        }
        return refusal.map { .failure(.refused(by: $0)) } ?? .success(())
    }

    /// P-SET-02, P-SET-03, P-SET-07: what holds for every attribute, its limits included. The
    /// attribute is the one read just now, whose limits are the ones a client is sent; the
    /// writer only has rules that are not limits (a font's name).
    static func check(_ value: AttributeValue?, against attribute: Attribute) -> AttributeRejection? {
        guard let value else {
            return attribute.acceptsNil ? nil : AttributeRejection("cannot be nil")
        }
        guard value.kind == attribute.valueKind else {
            return AttributeRejection("takes a \(attribute.valueKind.schemaName)")
        }
        let components = value.components
        guard components.allSatisfy(\.isFinite) else {
            return AttributeRejection("takes finite numbers only")
        }
        if case .enumeration(let raw, _, _, _) = value,
           case .enumeration(_, _, _, let caseValues)? = attribute.value, !caseValues.contains(raw) {
            return AttributeRejection("has no case with the value \(raw)")
        }
        if let limits = NumberLimit.perComponent(attribute.limits, count: components.count),
           let index = components.indices.first(where: { !limits[$0].admits(components[$0]) }) {
            let names = value.kind.componentNames
            let reason = limits[index].reason
            return AttributeRejection(names.count > 1 ? "\(names[index]) \(reason)" : reason)
        }
        return nil
    }
}

extension NumberLimit {
    /// What a value outside the limit must be, completing a sentence that begins with what it
    /// limits: "cannot be negative", "must be between 0 and 1".
    var reason: String {
        func number(_ value: Double) -> String {
            value.rounded() == value && abs(value) < 1e15 ? String(Int64(value)) : "\(value)"
        }
        switch (minimum, maximum) {
        case let (minimum?, nil) where minimum == 0 && !minimumIsExclusive:
            return "cannot be negative"
        case let (minimum?, nil):
            return minimumIsExclusive ? "must be greater than \(number(minimum))" : "must be at least \(number(minimum))"
        case let (nil, maximum?):
            return maximumIsExclusive ? "must be less than \(number(maximum))" : "must be at most \(number(maximum))"
        case let (minimum?, maximum?) where !minimumIsExclusive && !maximumIsExclusive:
            return "must be between \(number(minimum)) and \(number(maximum))"
        case let (minimum?, maximum?):
            let lower = minimumIsExclusive ? "greater than" : "at least"
            let upper = maximumIsExclusive ? "less than" : "at most"
            return "must be \(lower) \(number(minimum)) and \(upper) \(number(maximum))"
        case (nil, nil):
            return "is outside its limits"
        }
    }
}

extension AttributeValueKind {
    /// The name of the member in the schema, as the `set-attribute-rejected` fixture says it.
    var schemaName: String {
        switch self {
        case .none: return "value"
        case .bool: return "BoolValue"
        case .int: return "IntValue"
        case .double: return "DoubleValue"
        case .string: return "StringValue"
        case .color: return "ColorValue"
        case .point: return "PointValue"
        case .size: return "SizeValue"
        case .rect: return "RectValue"
        case .insets: return "InsetsValue"
        case .transform: return "TransformValue"
        case .enumeration: return "EnumValue"
        case .layerReference: return "LayerReferenceValue"
        }
    }
}
#endif
