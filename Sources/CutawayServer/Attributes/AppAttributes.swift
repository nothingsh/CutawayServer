#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The host app's attribute groups of one node as they are sent (PROTOCOL.md, P-ATTR-19): IDs
/// with the prefix `app.`, values converted and attributes made as the server's own are
/// (`AttributeSpec`), and every rule of the protocol the host app could break checked, leaving
/// out what breaks one. Also how each attribute is changed.
@MainActor
struct AppAttributes {
    static let prefix = "app."

    /// Groups the host app gave for a node, and the class they name when they give no type.
    struct Source {
        let groups: [CutawayServer.AttributeGroup]
        let className: String
    }

    /// The groups as sent, after the server's own.
    private(set) var groups: [AttributeGroup] = []
    /// The host app's attribute behind each attribute sent, by ID.
    private var sources: [String: CutawayServer.Attribute] = [:]

    /// - Parameters:
    ///   - serverGroups: The node's own groups, whose IDs, slots and clusters the host app's
    ///     must not meet (P-ATTR-12, 19).
    ///   - view: Whose traits colors resolve with (P-ATTR-17).
    init(_ sources: [Source], alongside serverGroups: [AttributeGroup], view: UIView?, reading: AttributeReading) {
        let serverAttributes = serverGroups.flatMap(\.attributes)
        var ids = Set(serverAttributes.map(\.id))
        var clusters = Clusters(serverAttributes)
        var groupIDs = Set<String>()
        for source in sources {
            for group in source.groups {
                // P-ATTR-01, 19: the whole group, when its ID is empty or taken, or one of its
                // attributes has no name.
                guard !group.id.isEmpty, !group.attributes.contains(where: \.name.isEmpty),
                      groupIDs.insert(group.id).inserted else {
                    continue
                }
                let groupID = Self.prefix + group.id
                var attributes: [Attribute] = []
                for appAttribute in group.attributes {
                    let id = "\(groupID).\(appAttribute.name)"
                    // A later attribute with an ID already sent is left out.
                    guard ids.insert(id).inserted else { continue }
                    var attribute = Self.attribute(appAttribute, id: id, view: view, reading: reading)
                    if !clusters.admit(attribute) {
                        attribute.cluster = nil
                        attribute.slot = nil
                    }
                    attributes.append(attribute)
                    self.sources[id] = appAttribute
                }
                groups.append(
                    AttributeGroup(
                        id: groupID,
                        title: group.title ?? AttributeCatalog.title(for: group.id),
                        attributes: attributes,
                        className: group.typeName ?? source.className,
                        fromApp: true
                    )
                )
            }
        }
        // P-ATTR-13: the cause must be an attribute of the node, once everything is known.
        for groupIndex in groups.indices {
            for index in groups[groupIndex].attributes.indices {
                if let cause = groups[groupIndex].attributes[index].inactiveCause, !ids.contains(cause) {
                    groups[groupIndex].attributes[index].inactiveCause = nil
                }
            }
        }
    }

    /// The attribute `id` as sent, and how the host app's `set` changes it; `nil` when no group
    /// has it. It reads as read-only without `set`, or when its value fell back to text.
    func attributeForEditing(_ id: String) -> AttributeEdit? {
        guard let source = sources[id],
              let sent = groups.lazy.flatMap(\.attributes).first(where: { $0.id == id }) else {
            return nil
        }
        guard sent.editable, let write = source.write else { return AttributeEdit(attribute: sent, prepare: nil) }
        return AttributeEdit(attribute: sent) { value in
            guard let value else { return .success { try write(nil) } }
            guard let input = Self.input(value), Self.kind(of: input) == sent.valueKind else {
                return .failure(AttributeRejection("takes a \(sent.valueKind.schemaName)"))
            }
            return .success { try write(input) }
        }
    }

    /// The clusters and slots one node uses (P-ATTR-12): each slot once, one section per
    /// cluster, only what the table has.
    private struct Clusters {
        private var slots = Set<String>()
        private var sections: [String: AttributeSection] = [:]

        init(_ attributes: [Attribute]) {
            for attribute in attributes { _ = admit(attribute) }
        }

        /// Records the attribute's cluster and slot; `false` when it may not have them.
        mutating func admit(_ attribute: Attribute) -> Bool {
            guard let cluster = attribute.cluster, let slot = attribute.slot else { return true }
            guard AttributeTables.clusters[cluster]?.contains(slot) == true,
                  sections[cluster, default: attribute.section] == attribute.section,
                  slots.insert("\(cluster)\u{0}\(slot)").inserted else {
                return false
            }
            sections[cluster] = attribute.section
            return true
        }
    }
}

// MARK: - Converting

extension AppAttributes {
    /// One attribute as sent, before the checks that need the whole node: made by the rules of
    /// the server's own (`AttributeSpec`), with the limits that hold (P-ATTR-09, 10) and the
    /// prefix on the inactive cause. An object is never written.
    static func attribute(
        _ source: CutawayServer.Attribute,
        id: String,
        view: UIView?,
        reading: AttributeReading
    ) -> Attribute {
        let kind = kind(of: source.value)
        let limits = source.limits.map(limit)
        let spec = AttributeSpec(
            kind: kind,
            acceptsNil: source.acceptsNil,
            section: section(source.section),
            cluster: source.cluster.map { ($0.name, $0.slot) },
            unit: unit(source.unit),
            limits: limitsAreValid(limits, kind: kind) ? limits : [],
            isEditable: source.write != nil && kind != .layerReference
        )
        return spec.attribute(
            id: id,
            title: source.title ?? AttributeCatalog.title(for: source.name),
            value: value(of: source.value, view: view, reading: reading),
            inactiveCause: source.inactiveBecauseOf.map { prefix + $0 }
        )
    }

    static func kind(of value: CutawayServer.Attribute.Value) -> AttributeValueKind {
        switch value {
        case .bool: return .bool
        case .int: return .int
        case .double: return .double
        case .string: return .string
        case .color: return .color
        case .point: return .point
        case .size: return .size
        case .rect: return .rect
        case .insets: return .insets
        case .transform: return .transform
        case .enumeration: return .enumeration
        case .references: return .layerReference
        }
    }

    /// As the server's own values are: numbers that are not finite become 0 (P-ATTR-05), a
    /// color resolves with the view's traits (P-ATTR-15, 17), an object is referred to by its
    /// layer (P-ATTR-18).
    static func value(
        of value: CutawayServer.Attribute.Value,
        view: UIView?,
        reading: AttributeReading
    ) -> AttributeValue? {
        switch value {
        case .bool(let flag): return flag.map(AttributeValue.bool)
        case .int(let number): return number.map(AttributeValue.int)
        case .double(let number): return number.map { AttributeOutputs.double(CGFloat($0)) }
        case .string(let text): return text.map(AttributeValue.string)
        case .color(let color):
            guard let color else { return nil }
            guard let view else { return AttributeOutputs.color(color.cgColor) }
            return AttributeOutputs.color(color, in: view)
        case .point(let point): return point.map(AttributeOutputs.point)
        case .size(let size): return size.map(AttributeOutputs.size)
        case .rect(let rect): return rect.map(AttributeOutputs.rect)
        case .insets(let insets): return insets.map(AttributeOutputs.insets)
        case .transform(let transform): return transform.map(AttributeOutputs.transform)
        case let .enumeration(raw, cases):
            guard let raw else { return nil }
            // P-ATTR-07; a raw value without a case is sent as its decimal text.
            guard let current = cases.first(where: { $0.value == raw }) else { return .string(String(raw)) }
            return .enumeration(
                value: raw,
                cases: cases.map(\.name),
                caseName: current.name,
                caseValues: cases.map(\.value)
            )
        case .references(let objects):
            return objects.map { .layerReference($0.map(reading.reference)) }
        }
    }

    /// A value from the wire as the host app's attribute takes it, in the case of its kind;
    /// `nil` for objects, which are never written.
    static func input(_ value: AttributeValue) -> CutawayServer.Attribute.Value? {
        switch value {
        case .bool(let flag): return .bool(flag)
        case .int(let number): return .int(number)
        case .double(let number): return .double(number)
        case .string(let text): return .string(text)
        case .color:
            guard case .success(let color?) = AttributeInputs.color(value) else { return nil }
            return .color(UIColor(cgColor: color))
        case .point(let point): return .point(CGPoint(point))
        case .size(let size): return .size(CGSize(size))
        case .rect(let rect): return .rect(CGRect(rect))
        case .insets(let insets): return .insets(UIEdgeInsets(insets))
        case .transform(let transform): return .transform(CATransform3D(transform))
        // The cases are the attribute's; writing takes the raw value only.
        case .enumeration(let raw, _, _, _): return .enumeration(raw, cases: [])
        case .layerReference: return nil
        }
    }

    static func section(_ section: CutawayServer.Attribute.Section) -> AttributeSection {
        switch section {
        case .general: return .general
        case .identity: return .identity
        case .layout: return .layout
        case .content: return .content
        case .appearance: return .appearance
        case .behavior: return .behavior
        case .accessibility: return .accessibility
        }
    }

    static func unit(_ unit: CutawayServer.Attribute.Unit) -> AttributeUnit {
        switch unit {
        case .none: return .unspecified
        case .points: return .points
        case .fraction: return .fraction
        }
    }

    static func limit(_ limit: CutawayServer.Attribute.Limit) -> NumberLimit {
        NumberLimit(
            minimum: limit.minimum,
            minimumIsExclusive: limit.minimum != nil && limit.minimumIsExclusive,
            maximum: limit.maximum,
            maximumIsExclusive: limit.maximum != nil && limit.maximumIsExclusive
        )
    }

    /// P-ATTR-09, 10: one entry or one per component, finite bounds, the minimum at most the
    /// maximum with some value between, integer bounds for an integer. Empty states none.
    static func limitsAreValid(_ limits: [NumberLimit], kind: AttributeValueKind) -> Bool {
        guard !limits.isEmpty else { return true }
        let count = kind.componentCount
        guard count > 0, limits.count == 1 || limits.count == count else { return false }
        return limits.allSatisfy { $0.isSatisfiable(byIntegersOnly: kind == .int) }
    }
}

extension NumberLimit {
    /// P-ATTR-10: its bounds are finite, and some value lies between them; an integer one when
    /// `byIntegersOnly`, whose bounds are integers too.
    func isSatisfiable(byIntegersOnly: Bool) -> Bool {
        let bounds = [minimum, maximum].compactMap { $0 }
        guard bounds.allSatisfy(\.isFinite) else { return false }
        if byIntegersOnly, !bounds.allSatisfy({ $0.rounded() == $0 }) { return false }
        guard let minimum, let maximum else { return true }
        if byIntegersOnly {
            return (minimumIsExclusive ? minimum + 1 : minimum) <= (maximumIsExclusive ? maximum - 1 : maximum)
        }
        return minimum < maximum || (minimum == maximum && !minimumIsExclusive && !maximumIsExclusive)
    }
}
#endif
