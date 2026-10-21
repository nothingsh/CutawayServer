#if !canImport(UIKit) || DEBUG || ReleaseEnabled

// The value types of attributes and of changing them (PROTOCOL.md, "Attributes", "Modifying
// attributes").

/// One case per member of the schema's `AttributeValue` union. A struct that is absent on
/// the wire reads as zeros; an absent string reads as empty.
public enum AttributeValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    /// `systemName` is the UIKit system color the server recognized it as (P-ATTR-15, protocol
    /// 1.1); `light` and `dark` are the value in either appearance, both or neither (P-ATTR-17,
    /// protocol 1.2); `name` is a color the host app registered that equals it (P-ATTR-20,
    /// protocol 1.2). A server reads only the color (P-SET-02).
    case color(
        WireColor,
        systemName: String? = nil,
        light: WireColor? = nil,
        dark: WireColor? = nil,
        name: String? = nil
    )
    case point(WirePoint)
    case size(WireSize)
    case rect(WireRect)
    case insets(WireInsets)
    case transform(WireTransform)
    /// `cases` names every case in declaration order; `caseName` names the current one;
    /// `caseValues` is the raw value of each case, parallel to `cases` (P-ATTR-07).
    case enumeration(value: Int64, cases: [String], caseName: String, caseValues: [Int64])
    /// The objects the attribute holds, in order (P-ATTR-18, protocol 1.2). Always read-only.
    case layerReference([ObjectReference])

    /// The member of the union this value is.
    public var kind: AttributeValueKind {
        switch self {
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
        case .layerReference: return .layerReference
        }
    }

    /// Every number the value holds, in the order of its fields (P-ATTR-09): x, y; width,
    /// height; origin x, origin y, width, height; top, left, bottom, right; m11 to m44. A
    /// colour's channels are included, for the check that numbers are finite (P-SET-03); a
    /// colour has no limits.
    public var components: [Double] {
        switch self {
        case .bool, .string, .enumeration, .layerReference:
            return []
        case .int(let number):
            return [Double(number)]
        case .double(let number):
            return [number]
        case .color(let color, _, _, _, _):
            return [color.red, color.green, color.blue, color.alpha].map(Double.init)
        case .point(let point):
            return [point.x, point.y]
        case .size(let size):
            return [size.width, size.height]
        case .rect(let rect):
            return [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        case .insets(let insets):
            return [insets.top, insets.left, insets.bottom, insets.right]
        case .transform(let transform):
            return transform.components
        }
    }
}

/// Names the members of `AttributeValue`; `none` names no member (P-ATTR-06).
public enum AttributeValueKind: Sendable, Equatable {
    case none
    case bool
    case int
    case double
    case string
    case color
    case point
    case size
    case rect
    case insets
    case transform
    case enumeration
    /// Protocol 1.2.
    case layerReference

    /// The kinds that may carry limits (P-ATTR-09).
    public var isNumeric: Bool {
        switch self {
        case .int, .double, .point, .size, .rect, .insets, .transform: return true
        case .none, .bool, .string, .color, .enumeration, .layerReference: return false
        }
    }

    /// The minor version of protocol 1 that named this member. No `default` (P-HELLO-04).
    public var minorVersion: UInt16 {
        switch self {
        case .none, .bool, .int, .double, .string, .color, .point, .size, .rect, .insets, .transform,
             .enumeration:
            return 0
        case .layerReference:
            return 2
        }
    }

    /// The number of components that limits apply to, one entry each (P-ATTR-09); 0 for a kind
    /// without limits. A colour's channels do not count, although `AttributeValue.components`
    /// lists them.
    public var componentCount: Int {
        switch self {
        case .int, .double: return 1
        case .point, .size: return 2
        case .rect, .insets: return 4
        case .transform: return 16
        case .none, .bool, .string, .color, .enumeration, .layerReference: return 0
        }
    }

    /// The name of each of those components, in the order of P-ATTR-09, for messages; "value"
    /// for the one number of `int` and `double`. Empty for a kind without limits.
    public var componentNames: [String] {
        switch self {
        case .int, .double: return ["value"]
        case .point: return ["x", "y"]
        case .size: return ["width", "height"]
        case .rect: return ["x", "y", "width", "height"]
        case .insets: return ["top", "left", "bottom", "right"]
        case .transform: return (1...4).flatMap { row in (1...4).map { "m\(row)\($0)" } }
        case .none, .bool, .string, .color, .enumeration, .layerReference: return []
        }
    }
}

/// One object an attribute refers to (P-ATTR-18, protocol 1.2).
public struct ObjectReference: Sendable, Equatable {
    /// The layer of the view, or of a view controller's root view; 0 when there is none, or it
    /// does not exist.
    public var layerID: UInt64
    /// The runtime name of the object's class.
    public var className: String
    /// The name to show, by the rule of hierarchy nodes.
    public var displayClassName: String

    public init(layerID: UInt64, className: String, displayClassName: String) {
        self.layerID = layerID
        self.className = className
        self.displayClassName = displayClassName
    }
}

/// The part of an inspector an attribute belongs on (P-ATTR-08, protocol 1.1).
public enum AttributeSection: Sendable, Equatable, CaseIterable {
    case unspecified
    case identity
    case general
    case layout
    case content
    case appearance
    case behavior
    /// Protocol 1.2.
    case accessibility

    /// The minor version of protocol 1 that named this value. No `default`, so that a value
    /// added later cannot reach every peer by accident (P-HELLO-04).
    public var minorVersion: UInt16 {
        switch self {
        case .unspecified: return 0
        case .identity, .general, .layout, .content, .appearance, .behavior: return 1
        case .accessibility: return 2
        }
    }

    /// P-ATTR-08: a section the peer's version does not have is sent as `unspecified`.
    func adapted(to version: ProtocolVersion) -> Self {
        minorVersion <= version.minor ? self : .unspecified
    }
}

/// How to read the numbers of an attribute's value (P-ATTR-14, protocol 1.1).
public enum AttributeUnit: Sendable, Equatable, CaseIterable {
    case unspecified
    /// Lengths in points.
    case points
    /// A proportion where 1 is the whole.
    case fraction

    /// The minor version of protocol 1 that named this value. No `default` (P-HELLO-04).
    public var minorVersion: UInt16 {
        switch self {
        case .unspecified: return 0
        case .points, .fraction: return 1
        }
    }

    /// P-ATTR-14: a unit the peer's version does not have is sent as `unspecified`.
    func adapted(to version: ProtocolVersion) -> Self {
        minorVersion <= version.minor ? self : .unspecified
    }
}

/// The values `SetAttribute` accepts for one numeric component (P-ATTR-10, protocol 1.1).
/// `nil` leaves that side unbounded; its exclusive flag then means nothing and should be false.
public struct NumberLimit: Sendable, Equatable {
    public var minimum: Double?
    /// The component must be greater than `minimum`, not equal to it.
    public var minimumIsExclusive: Bool
    public var maximum: Double?
    /// The component must be less than `maximum`, not equal to it.
    public var maximumIsExclusive: Bool

    public init(
        minimum: Double? = nil,
        minimumIsExclusive: Bool = false,
        maximum: Double? = nil,
        maximumIsExclusive: Bool = false
    ) {
        self.minimum = minimum
        self.minimumIsExclusive = minimumIsExclusive
        self.maximum = maximum
        self.maximumIsExclusive = maximumIsExclusive
    }

    /// No bound on either side.
    public static let free = Self()

    public func admits(_ value: Double) -> Bool {
        if let minimum, minimumIsExclusive ? value <= minimum : value < minimum { return false }
        if let maximum, maximumIsExclusive ? value >= maximum : value > maximum { return false }
        return true
    }

    /// P-ATTR-09: the limit of each of `count` components. One entry applies to every
    /// component; as many entries as components apply one each; any other number of entries
    /// states no limits, and gives `nil`.
    public static func perComponent(_ limits: [Self], count: Int) -> [Self]? {
        if limits.count == 1 { return Array(repeating: limits[0], count: count) }
        return limits.count == count && count > 0 ? limits : nil
    }
}

/// The protocol's tables about attributes (protocol 1.1): only appended to.
public enum AttributeTables {
    /// P-ATTR-11: a view attribute and a layer attribute that read and write the same state.
    /// One layer's groups hold at most one of each pair: the view's when the layer backs a
    /// view, the layer's otherwise.
    public static let pairs: [(view: String, layer: String)] = [
        ("view.isHidden", "layer.hidden"),
        ("view.alpha", "layer.opacity"),
        ("view.clipsToBounds", "layer.masksToBounds"),
        ("view.backgroundColor", "layer.backgroundColor")
    ]

    /// P-ATTR-12: the clusters and their slots, each slot with the minor version of protocol 1
    /// that added it.
    public static let clusterSlots: [String: [String: UInt16]] = [
        "visibility": ["hidden": 1, "opacity": 1],
        "corners": ["radius": 1, "clip": 1],
        "border": ["width": 1, "color": 1],
        "shadow": ["color": 1, "opacity": 1, "radius": 1, "offset": 1],
        "geometry": ["frame": 1, "bounds": 1, "position": 1, "anchor": 1, "zPosition": 1, "transform": 1],
        "sizing": [
            "hugging.horizontal": 1,
            "hugging.vertical": 1,
            "compression.horizontal": 1,
            "compression.vertical": 1,
            "intrinsic.width": 1,
            "intrinsic.height": 1
        ],
        "autoLayout": ["autoresizing": 1, "ambiguous": 1],
        "font": ["name": 1, "size": 1, "textStyle": 2, "scalable": 2],
        "lines": ["count": 1, "lineBreak": 1, "drawn": 2, "truncated": 2],
        "state": ["enabled": 1, "selected": 1, "highlighted": 1],
        "scrolling": ["enabled": 1, "paging": 1],
        "image": ["name": 2, "size": 2, "scale": 2, "renderingMode": 2, "symbolConfiguration": 2],
        "indexPath": ["section": 2, "item": 2],
        "listCounts": ["sections": 2, "items": 2]
    ]

    /// The clusters and slots of the table of `version`; a cluster with none of its slots there
    /// is left out.
    public static func clusters(at version: ProtocolVersion) -> [String: Set<String>] {
        clusterSlots.reduce(into: [:]) { table, entry in
            let slots = Set(entry.value.filter { $0.value <= version.minor }.keys)
            if !slots.isEmpty { table[entry.key] = slots }
        }
    }

    /// The clusters and slots of this build's version.
    public static let clusters = clusters(at: .current)
}

public struct Attribute: Sendable, Equatable {
    /// Stable, for example "layer.cornerRadius" (P-ATTR-01).
    public var id: String
    public var title: String
    /// `nil` means the attribute's value is nil (P-ATTR-02).
    public var value: AttributeValue?
    /// `SetAttribute` may change it (P-ATTR-06).
    public var editable: Bool
    /// `SetAttribute` may set it to nil; meaningful only when `editable`.
    public var acceptsNil: Bool
    /// The member `value` uses, also when `value` is nil.
    public var valueKind: AttributeValueKind
    /// Where an inspector shows it (P-ATTR-08, protocol 1.1).
    public var section: AttributeSection
    /// The values `SetAttribute` accepts: one entry for every component, or one per component
    /// (P-ATTR-09, protocol 1.1). Empty states no limits.
    public var limits: [NumberLimit]
    /// The compound row this attribute is part of, and its part in it; `slot` is set exactly
    /// when `cluster` is (P-ATTR-12, protocol 1.1).
    public var cluster: String?
    public var slot: String?
    /// The ID of the attribute of the same layer that makes this one have no effect now
    /// (P-ATTR-13, protocol 1.1).
    public var inactiveCause: String?
    /// How to read the value's numbers (P-ATTR-14, protocol 1.1).
    public var unit: AttributeUnit

    public init(
        id: String,
        title: String,
        value: AttributeValue?,
        editable: Bool = false,
        acceptsNil: Bool = false,
        valueKind: AttributeValueKind = .none,
        section: AttributeSection = .unspecified,
        limits: [NumberLimit] = [],
        cluster: String? = nil,
        slot: String? = nil,
        inactiveCause: String? = nil,
        unit: AttributeUnit = .unspecified
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.editable = editable
        self.acceptsNil = acceptsNil
        self.valueKind = valueKind
        self.section = section
        self.limits = limits
        self.cluster = cluster
        self.slot = slot
        self.inactiveCause = inactiveCause
        self.unit = unit
    }
}

public struct AttributeGroup: Sendable, Equatable {
    /// Stable, for example "layer" (P-ATTR-01).
    public var id: String
    public var title: String
    public var attributes: [Attribute]
    /// The runtime name of the class that declares the group's properties (P-ATTR-16,
    /// protocol 1.1).
    public var className: String?
    /// The group comes from the host app, not the server's own list (P-ATTR-19, protocol 1.2).
    public var fromApp: Bool

    public init(
        id: String,
        title: String,
        attributes: [Attribute],
        className: String? = nil,
        fromApp: Bool = false
    ) {
        self.id = id
        self.title = title
        self.attributes = attributes
        self.className = className
        self.fromApp = fromApp
    }
}

extension AttributeGroup {
    /// P-ATTR-08, P-ATTR-14: each section and unit the peer's version does not have becomes
    /// `unspecified`. P-ATTR-12: a cluster or slot not in its table is left out, both together.
    /// P-ATTR-03: a value whose member it does not have is sent as text.
    func adapted(to version: ProtocolVersion) -> AttributeGroup {
        var group = self
        let clusters = AttributeTables.clusters(at: version)
        group.attributes = attributes.map { original in
            var attribute = original
            attribute.section = original.section.adapted(to: version)
            attribute.unit = original.unit.adapted(to: version)
            if let cluster = original.cluster, let slot = original.slot,
               clusters[cluster]?.contains(slot) == true {
                // Kept.
            } else {
                attribute.cluster = nil
                attribute.slot = nil
            }
            if original.valueKind.minorVersion > version.minor {
                attribute.valueKind = .string
                attribute.value = original.value.map { .string($0.text) }
                attribute.editable = false
                attribute.acceptsNil = false
            }
            return attribute
        }
        return group
    }
}

extension AttributeValue {
    /// The value as text, for a peer whose version does not have its member (P-ATTR-03). Only
    /// members added after 1.0 need it.
    var text: String {
        switch self {
        case .layerReference(let references):
            references.isEmpty ? "None" : references.map(\.displayClassName).joined(separator: ", ")
        default:
            String(describing: self)
        }
    }
}

// MARK: - Editing (protocol 0.3)

public struct SetAttribute: Sendable, Equatable {
    public var layerID: UInt64
    public var attributeID: String
    /// `nil` sets the attribute to nil (P-SET-02).
    public var value: AttributeValue?

    public init(layerID: UInt64, attributeID: String, value: AttributeValue?) {
        self.layerID = layerID
        self.attributeID = attributeID
        self.value = value
    }
}

public struct SetAttributeResult: Sendable, Equatable {
    public var layerID: UInt64
    /// Every group of the layer, read after the change (P-SET-01).
    public var attributeGroups: [AttributeGroup]

    public init(layerID: UInt64, attributeGroups: [AttributeGroup]) {
        self.layerID = layerID
        self.attributeGroups = attributeGroups
    }
}

extension SetAttributeResult {
    /// P-HELLO-04, P-ATTR-08: the result as a peer working at `version` may receive it, by the
    /// rules of `LayerDetail.adapted(to:)`.
    public func adapted(to version: ProtocolVersion) -> SetAttributeResult {
        SetAttributeResult(layerID: layerID, attributeGroups: attributeGroups.map { $0.adapted(to: version) })
    }
}
#endif
