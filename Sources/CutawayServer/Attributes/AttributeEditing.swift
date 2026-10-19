#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Carries out one `SetAttribute` (PROTOCOL.md, P-SET-01 to P-SET-05).
@MainActor
enum AttributeEditing {
    /// Checks the request, changes the attribute, lays the window out and reads the layer's
    /// attributes again. A request that fails a check changes nothing (P-SET-03): every check
    /// comes before the change.
    ///
    /// - Parameters:
    ///   - appState: The app's state now, read on the main thread.
    ///   - catalog: The attributes a layer has and how they are written.
    static func apply(
        _ request: SetAttribute,
        windows: [UIWindow],
        registry: LayerRegistry,
        appState: AppState,
        catalog: AttributeCatalog = .standard
    ) -> Result<SetAttributeResult, WireError> {
        // P-APP-01: nothing is changed unless the app is active.
        guard appState == .active else { return .failure(.appNotActive) }
        // P-SET-03, in its order: the layer, the attribute, the value.
        guard let layer = registry.layer(for: request.layerID),
              let ancestors = LayerTopology.ancestors(of: layer, in: windows) else {
            return .failure(.layerNotFound(request.layerID))
        }
        let id = request.attributeID
        guard let edit = catalog.attributeForEditing(id, of: layer) else {
            // P-ATTR-11: the layer's side of a pair is left out when the layer backs a view.
            if let pair = AttributeTables.pairs.first(where: { $0.layer == id }),
               LayerTopology.backingView(of: layer) != nil {
                return .failure(error(
                    .attributeNotEditable,
                    "layer \(request.layerID) backs a view; set \(pair.view) instead of \(id)"
                ))
            }
            return .failure(error(.attributeNotEditable, "\(id) is not an attribute of this layer"))
        }
        // As it reads now: a value that fell back to text is read-only (P-ATTR-06).
        guard let prepare = edit.prepare else {
            return .failure(error(.attributeNotEditable, "\(id) is read-only"))
        }
        if let rejection = check(request.value, against: edit.attribute) {
            return .failure(error(.invalidAttributeValue, "\(id) \(rejection.reason)"))
        }
        let change: () -> Void
        switch prepare(request.value) {
        case .failure(let rejection):
            return .failure(error(.invalidAttributeValue, "\(id) \(rejection.reason)"))
        case .success(let prepared):
            change = prepared
        }

        // P-SET-05: no implicit animation, also for what the layout moves, and also inside an
        // animation block of the host's: with actions disabled, no layer asks for one. The window
        // is laid out before the answer; it is the delegate of the topmost ancestor, or of the
        // layer itself when it is a window's.
        let window = (ancestors.first ?? layer).delegate as? UIWindow
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        window?.layoutIfNeeded()
        CATransaction.commit()
        return .success(
            SetAttributeResult(layerID: request.layerID, attributeGroups: catalog.read(layer))
        )
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
            let names = value.componentNames
            let reason = limits[index].reason
            return AttributeRejection(names.count > 1 ? "\(names[index]) \(reason)" : reason)
        }
        return nil
    }

    private static func error(_ code: ErrorCode, _ message: String) -> WireError {
        WireError(code: code, message: message)
    }
}

extension AttributeValue {
    /// The name of each of `components`, for a message.
    var componentNames: [String] {
        switch self {
        case .point: return ["x", "y"]
        case .size: return ["width", "height"]
        case .rect: return ["x", "y", "width", "height"]
        case .insets: return ["top", "left", "bottom", "right"]
        case .transform: return (1...4).flatMap { row in (1...4).map { "m\(row)\($0)" } }
        case .bool, .int, .double, .string, .color, .enumeration, .layerReference:
            return components.map { _ in "value" }
        }
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
