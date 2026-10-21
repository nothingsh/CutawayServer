import CutawayWire
import Foundation

/// What the attributes of a `LayerDetail` have to look like. Every function throws a
/// `ProbeFailure` naming the first thing that is wrong.
enum AttributeChecks {
    /// What holds for the attributes of any app (PROTOCOL.md, "Attributes"). A member of the
    /// `AttributeValue` union that protocol 0.3 does not have cannot get this far: it fails
    /// verification when the frame is decoded (P-REQ-07).
    ///
    /// - Parameter layerIDs: The layers of the hierarchy, which references may name (P-ATTR-18);
    ///   `nil` when there is none to compare with.
    static func structure(
        _ groups: [AttributeGroup],
        name: String,
        version: ProtocolVersion = .current,
        layerIDs: Set<UInt64>? = nil
    ) throws {
        var groupIDs = Set<String>()
        for group in groups {
            guard !group.id.isEmpty else { throw ProbeFailure("\(name) has a group with an empty id") }
            guard groupIDs.insert(group.id).inserted else {
                throw ProbeFailure("\(name) has two groups with the id \(group.id) (P-ATTR-01)")
            }
            guard !group.title.isEmpty else {
                throw ProbeFailure("\(name): group \(group.id) has an empty title")
            }
            // P-ATTR-19: the host app's groups, and so their attributes, begin with "app.";
            // no other does.
            guard group.fromApp == group.id.hasPrefix("app.") else {
                throw ProbeFailure(
                    group.fromApp
                        ? "\(name): group \(group.id) is from the app but does not begin with \"app.\" (P-ATTR-19)"
                        : "\(name): group \(group.id) begins with \"app.\" but is not from the app (P-ATTR-19)"
                )
            }
            var attributeIDs = Set<String>()
            for attribute in group.attributes {
                let label = "\(name): attribute \(attribute.id)"
                guard attribute.id.hasPrefix(group.id + "."), attribute.id.count > group.id.count + 1 else {
                    throw ProbeFailure("\(label) of group \(group.id) does not begin with \"\(group.id).\"")
                }
                guard attributeIDs.insert(attribute.id).inserted else {
                    throw ProbeFailure(
                        "\(name): group \(group.id) has two attributes with the id \(attribute.id) (P-ATTR-01)"
                    )
                }
                try check(attribute, name: label, version: version, layerIDs: layerIDs)
            }
        }
        try checkLayer(groups, name: name, version: version)
    }

    /// What holds for one attribute on its own.
    private static func check(
        _ attribute: Attribute,
        name label: String,
        version: ProtocolVersion,
        layerIDs: Set<UInt64>?
    ) throws {
        guard !attribute.title.isEmpty else { throw ProbeFailure("\(label) has an empty title") }
        guard attribute.valueKind != .none else {
            throw ProbeFailure("\(label) has no value_kind (P-ATTR-06)")
        }
        // P-ATTR-03: a value the negotiated version does not have is sent as text.
        if attribute.valueKind.minorVersion > version.minor {
            throw ProbeFailure(
                "\(label) is a \(attribute.valueKind) value, which protocol 1.\(version.minor) does not have (P-ATTR-03)"
            )
        }
        // P-ATTR-08: no section the negotiated version does not have.
        if attribute.section.minorVersion > version.minor {
            throw ProbeFailure(
                "\(label) has the section \(attribute.section), which protocol 1.\(version.minor) does not have (P-ATTR-08)"
            )
        }
        try checkUnit(of: attribute, name: label, version: version)
        try checkLimits(of: attribute, name: label)
        if attribute.valueKind == .layerReference, attribute.editable {
            throw ProbeFailure("\(label) refers to objects, but is editable (P-ATTR-18)")
        }
        if let value = attribute.value {
            guard value.kind == attribute.valueKind else {
                throw ProbeFailure(
                    "\(label) is a \(value.kind) value, but its value_kind is \(attribute.valueKind) (P-ATTR-06)"
                )
            }
            try check(value, name: label, layerIDs: layerIDs)
        }
    }

    /// The value kinds a unit may go with (P-ATTR-14).
    private static let kindsWithUnits: Set<AttributeValueKind> = [.int, .double, .point, .size, .rect, .insets]

    /// P-ATTR-14 (protocol 1.1): units only on numbers, and of the negotiated version.
    private static func checkUnit(of attribute: Attribute, name: String, version: ProtocolVersion) throws {
        guard attribute.unit != .unspecified else { return }
        guard attribute.unit.minorVersion <= version.minor else {
            throw ProbeFailure(
                "\(name) has the unit \(attribute.unit), which protocol 1.\(version.minor) does not have (P-ATTR-14)"
            )
        }
        guard kindsWithUnits.contains(attribute.valueKind) else {
            throw ProbeFailure(
                "\(name) has the unit \(attribute.unit), but is a \(attribute.valueKind) value (P-ATTR-14)"
            )
        }
    }

    /// The attributes whose value is a `CGColor`: never named (P-ATTR-15).
    private static let cgColorAttributes: Set<String> = [
        "layer.backgroundColor",
        "layer.borderColor",
        "layer.shadowColor"
    ]

    /// What holds across one layer's groups (protocol 1.1): the class names of the groups
    /// (P-ATTR-16), one attribute of each pair (P-ATTR-11), clusters (P-ATTR-12), inactive
    /// causes (P-ATTR-13) and system color names (P-ATTR-15).
    private static func checkLayer(_ groups: [AttributeGroup], name: String, version: ProtocolVersion) throws {
        let attributes = groups.flatMap(\.attributes)
        let ids = Set(attributes.map(\.id))
        for pair in AttributeTables.pairs where ids.contains(pair.view) && ids.contains(pair.layer) {
            throw ProbeFailure("\(name) has both \(pair.view) and \(pair.layer) (P-ATTR-11)")
        }
        var slots: [String: String] = [:]
        var sections: [String: AttributeSection] = [:]
        let table = AttributeTables.clusters(at: version)
        for attribute in attributes {
            let label = "\(name): attribute \(attribute.id)"
            guard (attribute.cluster == nil) == (attribute.slot == nil) else {
                throw ProbeFailure("\(label) has a cluster without a slot, or a slot without a cluster (P-ATTR-12)")
            }
            if let cluster = attribute.cluster, let slot = attribute.slot {
                // P-ATTR-12 (1.2): only the clusters and slots of the negotiated version's table.
                guard table[cluster]?.contains(slot) == true else {
                    throw ProbeFailure(
                        "\(label) is the \(slot) of the cluster \(cluster), which protocol 1.\(version.minor) does not name (P-ATTR-12)"
                    )
                }
                if let other = slots.updateValue(attribute.id, forKey: "\(cluster).\(slot)") {
                    throw ProbeFailure(
                        "\(label) and \(other) are both the \(slot) of the cluster \(cluster) (P-ATTR-12)"
                    )
                }
                if let section = sections.updateValue(attribute.section, forKey: cluster),
                   section != attribute.section {
                    throw ProbeFailure(
                        "\(label) is in the section \(attribute.section), another attribute of the cluster \(cluster) in \(section) (P-ATTR-12)"
                    )
                }
            }
            if let cause = attribute.inactiveCause, !ids.contains(cause) {
                throw ProbeFailure(
                    "\(label) has no effect because of \(cause), which the layer does not have (P-ATTR-13)"
                )
            }
            if case .color(_, let systemName?, _, _, _)? = attribute.value, cgColorAttributes.contains(attribute.id) {
                throw ProbeFailure("\(label) is a CGColor, but has the system name \(systemName) (P-ATTR-15)")
            }
        }
        guard version.supportsGroupClassNames else { return }
        for group in groups where group.className?.isEmpty != false {
            throw ProbeFailure("\(name): group \(group.id) has no class_name (P-ATTR-16)")
        }
    }

    private static func check(_ value: AttributeValue, name: String, layerIDs: Set<UInt64>?) throws {
        let numbers: [Double]
        switch value {
        case .bool, .int, .string:
            numbers = []
        case .layerReference(let references):
            try check(references, name: name, layerIDs: layerIDs)
            numbers = []
        case .double(let number):
            numbers = [number]
        case let .color(color, _, light, dark, _):
            try checkAppearances(light: light, dark: dark, name: name)
            numbers = ([color] + [light, dark].compactMap { $0 }).flatMap { color in
                [color.red, color.green, color.blue, color.alpha].map(Double.init)
            }
        case .point(let point):
            numbers = [point.x, point.y]
        case .size(let size):
            numbers = [size.width, size.height]
        case .rect(let rect):
            numbers = [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        case .insets(let insets):
            numbers = [insets.top, insets.left, insets.bottom, insets.right]
        case .transform(let transform):
            numbers = transform.components
        case let .enumeration(value, cases, caseName, caseValues):
            guard !cases.isEmpty, !cases.contains(where: \.isEmpty) else {
                throw ProbeFailure("\(name) is an enumeration with no cases, or a case without a name")
            }
            guard cases.contains(caseName) else {
                throw ProbeFailure("\(name) is the case \"\(caseName)\", which is not one of its cases \(cases)")
            }
            guard caseValues.count == cases.count, Set(caseValues).count == caseValues.count else {
                throw ProbeFailure(
                    "\(name) has the case values \(caseValues) for the cases \(cases): they must be as many, each once (P-ATTR-07)"
                )
            }
            guard let index = caseValues.firstIndex(of: value), cases[index] == caseName else {
                throw ProbeFailure(
                    "\(name) has the value \(value) and the case \"\(caseName)\", which the case values \(caseValues) do not pair (P-ATTR-07)"
                )
            }
            numbers = []
        }
        guard numbers.allSatisfy(\.isFinite) else {
            throw ProbeFailure("\(name) has a number that is not finite")
        }
    }

    /// P-ATTR-17 (1.2): `light` and `dark` together, and only when they differ in 8 bits.
    private static func checkAppearances(light: WireColor?, dark: WireColor?, name: String) throws {
        switch (light, dark) {
        case (nil, nil):
            return
        case let (light?, dark?):
            func in8Bits(_ color: WireColor) -> [Int] {
                [color.red, color.green, color.blue, color.alpha].map { Int(($0 * 255).rounded()) }
            }
            guard in8Bits(light) != in8Bits(dark) else {
                throw ProbeFailure("\(name) has a light and a dark that are the same in 8 bits (P-ATTR-17)")
            }
        default:
            throw ProbeFailure("\(name) has one of light and dark without the other (P-ATTR-17)")
        }
    }

    /// P-ATTR-18 (1.2): each object named by its classes, and by a layer of the hierarchy or 0.
    private static func check(_ references: [ObjectReference], name: String, layerIDs: Set<UInt64>?) throws {
        for (index, reference) in references.enumerated() {
            guard !reference.className.isEmpty, !reference.displayClassName.isEmpty else {
                throw ProbeFailure("\(name): reference \(index) has no class_name or display_class_name (P-ATTR-18)")
            }
            if let layerIDs, reference.layerID != 0, !layerIDs.contains(reference.layerID) {
                throw ProbeFailure(
                    "\(name): reference \(index) names layer \(reference.layerID), which the hierarchy does not have (P-ATTR-18)"
                )
            }
        }
    }

    /// The number of components of a value of each kind that may have limits (P-ATTR-09).
    private static let componentCounts: [AttributeValueKind: Int] = [
        .int: 1,
        .double: 1,
        .point: 2,
        .size: 2,
        .rect: 4,
        .insets: 4,
        .transform: 16
    ]

    /// P-ATTR-09, 10: limits only on what can be changed and is a number, as many as the value has
    /// components or one, each with finite bounds that leave some value between them.
    private static func checkLimits(of attribute: Attribute, name: String) throws {
        guard !attribute.limits.isEmpty else { return }
        guard attribute.editable, let count = componentCounts[attribute.valueKind] else {
            throw ProbeFailure(
                "\(name) has limits, but is \(attribute.editable ? "a \(attribute.valueKind) value" : "read-only") (P-ATTR-09)"
            )
        }
        guard [1, count].contains(attribute.limits.count) else {
            throw ProbeFailure(
                "\(name) has \(attribute.limits.count) limits for a value of \(count) components (P-ATTR-09)"
            )
        }
        for (index, limit) in attribute.limits.enumerated() {
            let label = "\(name): limit \(index)"
            guard limit.minimum != nil || !limit.minimumIsExclusive,
                  limit.maximum != nil || !limit.maximumIsExclusive else {
                throw ProbeFailure("\(label) is exclusive on a side it does not bound (P-ATTR-10)")
            }
            let bounds = [limit.minimum, limit.maximum].compactMap { $0 }
            guard bounds.allSatisfy(\.isFinite)
            else { throw ProbeFailure("\(label) has a bound that is not finite (P-ATTR-10)") }
            if attribute.valueKind == .int, !bounds.allSatisfy({ $0.rounded() == $0 }) {
                throw ProbeFailure("\(label) bounds an integer by a fraction (P-ATTR-10)")
            }
            if let minimum = limit.minimum, let maximum = limit.maximum {
                let open = limit.minimumIsExclusive || limit.maximumIsExclusive
                guard open ? minimum < maximum : minimum <= maximum else {
                    throw ProbeFailure("\(label) leaves no value between \(minimum) and \(maximum) (P-ATTR-10)")
                }
            }
        }
    }

    /// The attributes whose value lies outside their own limits. Not a failure: the app may
    /// have set such a value itself (P-SET-07). Described one per line.
    static func valuesOutsideLimits(_ groups: [AttributeGroup], name: String) -> [String] {
        groups.flatMap(\.attributes).compactMap { attribute in
            guard let value = attribute.value else { return nil }
            let components = value.components
            guard let limits = NumberLimit.perComponent(attribute.limits, count: components.count),
                  let index = components.indices.first(where: { !limits[$0].admits(components[$0]) })
            else { return nil }
            return "\(name): \(attribute.id) has \(components[index]) as component \(index), outside its limits"
        }
    }

    // MARK: - The attribute list

    /// Fails unless the group has exactly the attributes of the list, in its order, with its
    /// kinds of values, nil only where the list allows it, and its flags (P-ATTR-06); from a
    /// server at 1.1 or later also with its sections, limits, titles, clusters, units and class
    /// name (P-ATTR-08, 09, 12, 14, 16). A value that fell back to a `StringValue` (P-ATTR-03)
    /// has to be read-only, of its own kind, without limits or a unit.
    ///
    /// - Parameter backsView: Whether the group's layer backs a view: its `layer` group then
    ///   leaves out the layer's side of each pair (P-ATTR-11).
    static func matchesList(
        _ group: AttributeGroup,
        name: String,
        backsView: Bool,
        version: ProtocolVersion = .current
    ) throws {
        guard let listed = list[group.id] else {
            throw ProbeFailure(
                "\(name) has the group \(group.id), which the attribute list of version 0.1 does not have"
            )
        }
        let entries = backsView ? listed.filter { !$0.onlyWithoutView } : listed
        let expected = entries.map { "\(group.id).\($0.name)" }
        let actual = group.attributes.map(\.id)
        guard actual == expected else {
            throw ProbeFailure(
                "\(name): group \(group.id) has the attributes \(actual), expected \(expected)"
            )
        }
        if version.supportsGroupClassNames, group.className != classNames[group.id] {
            throw ProbeFailure(
                "\(name): group \(group.id) has the class_name \(group.className ?? "nil"); the list says \(classNames[group.id] ?? "nil") (P-ATTR-16)"
            )
        }
        for (attribute, entry) in zip(group.attributes, entries) {
            var expected = (kind: entry.kind, editable: entry.editable, acceptsNil: entry.acceptsNil)
            var unit = entry.unit
            if let value = attribute.value {
                if value.kind == .string, entry.kind != .string {
                    expected = (.string, false, false)
                    unit = .unspecified
                } else {
                    guard value.kind == entry.kind else {
                        throw ProbeFailure(
                            "\(name): attribute \(attribute.id) is a \(value.kind) value, expected \(entry.kind)"
                        )
                    }
                }
            } else {
                guard entry.nullable else {
                    throw ProbeFailure("\(name): attribute \(attribute.id) is nil, which the list does not allow")
                }
            }
            let actual = (kind: attribute.valueKind, editable: attribute.editable, acceptsNil: attribute.acceptsNil)
            guard actual == expected else {
                throw ProbeFailure(
                    "\(name): attribute \(attribute.id) has value_kind \(actual.kind), editable \(actual.editable), "
                        + "accepts_nil \(actual.acceptsNil); the list says \(expected.kind), \(expected.editable), "
                        + "\(expected.acceptsNil) (P-ATTR-06)"
                )
            }
            // Protocol 1.1: the section whatever the value; limits only while it can be changed.
            guard version.supportsAttributeMetadata else { continue }
            try checkFieldsOf11(attribute, entry: entry, editable: expected.editable, unit: unit, name: name)
        }
    }

    /// The fields of protocol 1.1 the list gives: the section, the limits while the attribute can
    /// be changed, the title, the cluster and the unit (P-ATTR-08, 09, 12, 14).
    private static func checkFieldsOf11(
        _ attribute: Attribute,
        entry: Entry,
        editable: Bool,
        unit: AttributeUnit,
        name: String
    ) throws {
        let label = "\(name): attribute \(attribute.id)"
        guard attribute.section == entry.section else {
            throw ProbeFailure(
                "\(label) has the section \(attribute.section); the list says \(entry.section) (P-ATTR-08)"
            )
        }
        let limits = editable ? self.limits[attribute.id] ?? [] : []
        guard attribute.limits == limits else {
            throw ProbeFailure("\(label) has the limits \(attribute.limits); the list says \(limits) (P-ATTR-09)")
        }
        guard attribute.title == entry.title else {
            throw ProbeFailure("\(label) has the title \"\(attribute.title)\"; the list says \"\(entry.title)\"")
        }
        guard attribute.cluster == entry.cluster, attribute.slot == entry.slot else {
            throw ProbeFailure(
                "\(label) is the \(attribute.slot ?? "nil") of the cluster \(attribute.cluster ?? "nil"); "
                    + "the list says the \(entry.slot ?? "nil") of \(entry.cluster ?? "nil") (P-ATTR-12)"
            )
        }
        guard attribute.unit == unit else {
            throw ProbeFailure("\(label) has the unit \(attribute.unit); the list says \(unit) (P-ATTR-14)")
        }
    }

    /// The value of the attribute `id` (with its group's prefix); `nil` when it is nil or absent.
    static func value(_ id: String, in groups: [AttributeGroup]) -> AttributeValue? {
        groups.lazy.flatMap(\.attributes).first { $0.id == id }?.value
    }
}
