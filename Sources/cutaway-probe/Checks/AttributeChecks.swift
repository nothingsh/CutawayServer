import CutawayWire
import Foundation

/// What the attributes of a `LayerDetail` have to look like. Every function throws a
/// `ProbeFailure` naming the first thing that is wrong.
enum AttributeChecks {
    /// What holds for the attributes of any app (PROTOCOL.md, "Attributes"). A member of the
    /// `AttributeValue` union that protocol 0.3 does not have cannot get this far: it fails
    /// verification when the frame is decoded (P-REQ-07).
    static func structure(_ groups: [AttributeGroup], name: String) throws {
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
    /// kinds of values, nil only where the list allows it, and its flags (P-ATTR-06). A value
    /// that fell back to a `StringValue` (P-ATTR-03) has to be read-only, of its own kind.
    static func matchesList(_ group: AttributeGroup, name: String) throws {
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
        }
    }

    /// The value of the attribute `id` (with its group's prefix); `nil` when it is nil or absent.
    static func value(_ id: String, in groups: [AttributeGroup]) -> AttributeValue? {
        groups.lazy.flatMap(\.attributes).first { $0.id == id }?.value
    }
}
