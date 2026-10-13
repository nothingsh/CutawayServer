import CutawayWire
import Foundation

/// What the attributes of a `LayerDetail` have to look like. Every function throws a
/// `ProbeFailure` naming the first thing that is wrong.
enum AttributeChecks {
    /// What holds for the attributes of any app (PROTOCOL.md, "Attributes"). A member of the
    /// `AttributeValue` union that protocol 0.3 does not have cannot get this far: it fails
    /// verification when the frame is decoded (P-REQ-07).
    static func structure(_ groups: [AttributeGroup], name: String, version: ProtocolVersion = .current) throws {
        var groupIDs = Set<String>()
        for group in groups {
            guard !group.id.isEmpty else { throw ProbeFailure("\(name) has a group with an empty id") }
            guard groupIDs.insert(group.id).inserted else {
                throw ProbeFailure("\(name) has two groups with the id \(group.id) (P-ATTR-01)")
            }
            guard !group.title.isEmpty else {
                throw ProbeFailure("\(name): group \(group.id) has an empty title")
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
                guard !attribute.title.isEmpty else { throw ProbeFailure("\(label) has an empty title") }
                guard attribute.valueKind != .none else {
                    throw ProbeFailure("\(label) has no value_kind (P-ATTR-06)")
                }
                // P-ATTR-08: no section the negotiated version does not have.
                if version.minor < 1, attribute.section != .unspecified {
                    throw ProbeFailure(
                        "\(label) has the section \(attribute.section), which protocol 1.\(version.minor) does not have (P-ATTR-08)"
                    )
                }
                try checkLimits(of: attribute, name: label)
                if let value = attribute.value {
                    guard value.kind == attribute.valueKind else {
                        throw ProbeFailure(
                            "\(label) is a \(value.kind) value, but its value_kind is \(attribute.valueKind) (P-ATTR-06)"
                        )
                    }
                    try check(value, name: label)
                }
            }
        }
    }

    private static func check(_ value: AttributeValue, name: String) throws {
        let numbers: [Double]
        switch value {
        case .bool, .int, .string:
            numbers = []
        case .double(let number):
            numbers = [number]
        case .color(let color):
            numbers = [color.red, color.green, color.blue, color.alpha].map(Double.init)
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

    struct Entry: Equatable {
        /// The part of the id after the group's id and the dot.
        var name: String
        var kind: AttributeValueKind
        /// May read as nil.
        var nullable: Bool
        var editable: Bool
        /// May be set to nil.
        var acceptsNil: Bool
    }

    /// The expected attributes and which of them can be changed, copied by hand: the probe
    /// checks the server against it and does not share code with the server.
    static let list: [String: [Entry]] = {
        func entry(
            _ name: String,
            _ kind: AttributeValueKind,
            nullable: Bool = false,
            editable: Bool = true,
            acceptsNil: Bool = false
        ) -> Entry {
            Entry(name: name, kind: kind, nullable: nullable, editable: editable, acceptsNil: acceptsNil)
        }
        return [
            "layer": [
                entry("frame", .rect, editable: false),
                entry("bounds", .rect),
                entry("position", .point),
                entry("anchorPoint", .point),
                entry("zPosition", .double),
                entry("transform", .transform),
                entry("hidden", .bool),
                entry("opacity", .double),
                entry("masksToBounds", .bool),
                entry("cornerRadius", .double),
                entry("backgroundColor", .color, nullable: true, acceptsNil: true),
                entry("borderWidth", .double),
                entry("borderColor", .color, nullable: true, acceptsNil: true),
                entry("shadowColor", .color, nullable: true, acceptsNil: true),
                entry("shadowOpacity", .double),
                entry("shadowRadius", .double),
                entry("shadowOffset", .size)
            ],
            "view": [
                entry("alpha", .double),
                entry("isHidden", .bool),
                entry("isOpaque", .bool),
                entry("clipsToBounds", .bool),
                entry("isUserInteractionEnabled", .bool),
                entry("tag", .int),
                entry("contentMode", .enumeration),
                entry("tintColor", .color, nullable: true, acceptsNil: true),
                entry("layoutMargins", .insets),
                entry("contentHuggingPriority.horizontal", .double),
                entry("contentHuggingPriority.vertical", .double),
                entry("contentCompressionResistancePriority.horizontal", .double),
                entry("contentCompressionResistancePriority.vertical", .double),
                entry("intrinsicContentSize.width", .double, nullable: true, editable: false),
                entry("intrinsicContentSize.height", .double, nullable: true, editable: false),
                entry("translatesAutoresizingMaskIntoConstraints", .bool),
                entry("hasAmbiguousLayout", .bool, editable: false)
            ],
            "label": [
                entry("text", .string, nullable: true, acceptsNil: true),
                entry("fontName", .string),
                entry("fontSize", .double),
                entry("textColor", .color, nullable: true, acceptsNil: true),
                entry("textAlignment", .enumeration),
                entry("numberOfLines", .int),
                entry("lineBreakMode", .enumeration)
            ],
            "imageView": [
                entry("imageSize", .size, nullable: true, editable: false),
                entry("isHighlighted", .bool)
            ],
            "control": [entry("isEnabled", .bool), entry("isSelected", .bool), entry("isHighlighted", .bool)],
            "button": [
                entry("currentTitle", .string, nullable: true, acceptsNil: true),
                entry("currentTitleColor", .color, nullable: true, acceptsNil: true)
            ],
            "scrollView": [
                entry("contentOffset", .point),
                entry("contentSize", .size),
                entry("contentInset", .insets),
                entry("adjustedContentInset", .insets, editable: false),
                entry("isScrollEnabled", .bool),
                entry("isPagingEnabled", .bool)
            ],
            "stackView": [
                entry("axis", .enumeration),
                entry("alignment", .enumeration),
                entry("distribution", .enumeration),
                entry("spacing", .double)
            ],
            "textField": [
                entry("text", .string, nullable: true, acceptsNil: true),
                entry("placeholder", .string, nullable: true, acceptsNil: true),
                entry("fontName", .string, nullable: true),
                entry("fontSize", .double, nullable: true),
                entry("textColor", .color, nullable: true, acceptsNil: true)
            ],
            "textView": [
                entry("text", .string),
                entry("fontName", .string, nullable: true),
                entry("fontSize", .double, nullable: true),
                entry("textColor", .color, nullable: true, acceptsNil: true),
                entry("isEditable", .bool)
            ]
        ]
    }()

    /// Fails unless the group has exactly the attributes of the list, in its order, with its
    /// kinds of values, nil only where the list allows it, and its flags (P-ATTR-06); from a
    /// server at 1.1 or later also with its sections and limits (P-ATTR-08, 09). A value that
    /// fell back to a `StringValue` (P-ATTR-03) has to be read-only, of its own kind, without
    /// limits.
    static func matchesList(_ group: AttributeGroup, name: String, version: ProtocolVersion = .current) throws {
        guard let entries = list[group.id] else {
            throw ProbeFailure(
                "\(name) has the group \(group.id), which the attribute list of version 0.1 does not have"
            )
        }
        let expected = entries.map { "\(group.id).\($0.name)" }
        let actual = group.attributes.map(\.id)
        guard actual == expected else {
            throw ProbeFailure(
                "\(name): group \(group.id) has the attributes \(actual), expected \(expected)"
            )
        }
        for (attribute, entry) in zip(group.attributes, entries) {
            var expected = (kind: entry.kind, editable: entry.editable, acceptsNil: entry.acceptsNil)
            if let value = attribute.value {
                if value.kind == .string, entry.kind != .string {
                    expected = (.string, false, false)
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
            guard version.minor >= 1 else { continue }
            let section = sections[attribute.id] ?? .general
            guard attribute.section == section else {
                throw ProbeFailure(
                    "\(name): attribute \(attribute.id) has the section \(attribute.section); the list says \(section) (P-ATTR-08)"
                )
            }
            let limits = expected.editable ? self.limits[attribute.id] ?? [] : []
            guard attribute.limits == limits else {
                throw ProbeFailure(
                    "\(name): attribute \(attribute.id) has the limits \(attribute.limits); the list says \(limits) (P-ATTR-09)"
                )
            }
        }
    }

    /// The sections other than `general`, copied by hand like `list` (protocol 1.1, P-ATTR-08).
    static let sections: [String: AttributeSection] = {
        var sections: [String: AttributeSection] = ["view.tag": .identity]
        for id in [
            "layer.frame",
            "layer.bounds",
            "layer.position",
            "layer.anchorPoint",
            "layer.zPosition",
            "layer.transform",
            "view.layoutMargins",
            "view.contentHuggingPriority.horizontal",
            "view.contentHuggingPriority.vertical",
            "view.contentCompressionResistancePriority.horizontal",
            "view.contentCompressionResistancePriority.vertical",
            "view.intrinsicContentSize.width",
            "view.intrinsicContentSize.height",
            "view.translatesAutoresizingMaskIntoConstraints",
            "view.hasAmbiguousLayout",
            "scrollView.contentOffset",
            "scrollView.contentSize",
            "scrollView.contentInset",
            "scrollView.adjustedContentInset",
            "stackView.axis",
            "stackView.alignment",
            "stackView.distribution",
            "stackView.spacing"
        ] {
            sections[id] = .layout
        }
        return sections
    }()

    /// The limits, copied by hand like `list` (protocol 1.1, P-ATTR-09); none for every other
    /// attribute.
    static let limits: [String: [NumberLimit]] = {
        let atLeastZero = [NumberLimit(minimum: 0)]
        let unit = [NumberLimit(minimum: 0, maximum: 1)]
        let priority = [NumberLimit(minimum: 1, maximum: 1000)]
        let positive = [NumberLimit(minimum: 0, minimumIsExclusive: true)]
        var limits: [String: [NumberLimit]] = [
            "layer.bounds": [.free, .free, NumberLimit(minimum: 0), NumberLimit(minimum: 0)],
            "label.numberOfLines": atLeastZero,
            "scrollView.contentSize": atLeastZero
        ]
        for id in ["layer.opacity", "layer.shadowOpacity", "view.alpha"] { limits[id] = unit }
        for id in ["layer.cornerRadius", "layer.borderWidth", "layer.shadowRadius"] { limits[id] = atLeastZero }
        for id in ["label.fontSize", "textField.fontSize", "textView.fontSize"] { limits[id] = positive }
        for axis in ["horizontal", "vertical"] {
            limits["view.contentHuggingPriority.\(axis)"] = priority
            limits["view.contentCompressionResistancePriority.\(axis)"] = priority
        }
        return limits
    }()

    /// The value of the attribute `id` (with its group's prefix); `nil` when it is nil or absent.
    static func value(_ id: String, in groups: [AttributeGroup]) -> AttributeValue? {
        groups.lazy.flatMap(\.attributes).first { $0.id == id }?.value
    }
}
