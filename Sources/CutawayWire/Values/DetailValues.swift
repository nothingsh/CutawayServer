#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

// The value types of layer details (PROTOCOL.md, "Layer details", "Images", "Attributes").

/// What a client wants to know about one layer.
public struct LayerDetailRequest: Sendable, Equatable {
    public var layerID: UInt64
    public var wantSolo: Bool
    public var wantGroup: Bool
    public var wantAttributes: Bool
    /// The constraints that refer to the layer's view (P-LAYOUT-01, protocol 0.4).
    public var wantConstraints: Bool

    public init(
        layerID: UInt64,
        wantSolo: Bool,
        wantGroup: Bool,
        wantAttributes: Bool,
        wantConstraints: Bool = false
    ) {
        self.layerID = layerID
        self.wantSolo = wantSolo
        self.wantGroup = wantGroup
        self.wantAttributes = wantAttributes
        self.wantConstraints = wantConstraints
    }
}

public struct GetLayerDetails: Sendable, Equatable {
    public var requests: [LayerDetailRequest]
    /// In pixels; 0 means no limit (P-DET-05).
    public var maxTextureDimension: UInt32

    public init(requests: [LayerDetailRequest], maxTextureDimension: UInt32) {
        self.requests = requests
        self.maxTextureDimension = maxTextureDimension
    }
}

public enum DetailStatus: Sendable, Equatable {
    case ok
    case layerNotFound
    case captureFailed
}

public struct WireInsets: Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double, left: Double, bottom: Double, right: Double) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct WireColor: Sendable, Equatable {
    public var red: Float
    public var green: Float
    public var blue: Float
    public var alpha: Float

    public init(red: Float, green: Float, blue: Float, alpha: Float) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// One case per member of the schema's `AttributeValue` union. A struct that is absent on
/// the wire reads as zeros; an absent string reads as empty.
public enum AttributeValue: Sendable, Equatable {
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    /// `systemName` is the UIKit system color the server recognized it as (P-ATTR-15, protocol
    /// 1.1); a server reads only the color (P-SET-02).
    case color(WireColor, systemName: String? = nil)
    case point(WirePoint)
    case size(WireSize)
    case rect(WireRect)
    case insets(WireInsets)
    case transform(WireTransform)
    /// `cases` names every case in declaration order; `caseName` names the current one;
    /// `caseValues` is the raw value of each case, parallel to `cases` (P-ATTR-07).
    case enumeration(value: Int64, cases: [String], caseName: String, caseValues: [Int64])

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
        }
    }

    /// Every number the value holds, in the order of its fields (P-ATTR-09): x, y; width,
    /// height; origin x, origin y, width, height; top, left, bottom, right; m11 to m44. A
    /// colour's channels are included, for the check that numbers are finite (P-SET-03); a
    /// colour has no limits.
    public var components: [Double] {
        switch self {
        case .bool, .string, .enumeration:
            return []
        case .int(let number):
            return [Double(number)]
        case .double(let number):
            return [number]
        case .color(let color, _):
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

    /// The kinds that may carry limits (P-ATTR-09).
    public var isNumeric: Bool {
        switch self {
        case .int, .double, .point, .size, .rect, .insets, .transform: return true
        case .none, .bool, .string, .color, .enumeration: return false
        }
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

    /// The minor version of protocol 1 that named this value. No `default`, so that a value
    /// added later cannot reach every peer by accident (P-HELLO-04).
    public var minorVersion: UInt16 {
        switch self {
        case .unspecified: return 0
        case .identity, .general, .layout, .content, .appearance, .behavior: return 1
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

    /// P-ATTR-12: the clusters and their slots.
    public static let clusters: [String: Set<String>] = [
        "visibility": ["hidden", "opacity"],
        "corners": ["radius", "clip"],
        "border": ["width", "color"],
        "shadow": ["color", "opacity", "radius", "offset"],
        "geometry": ["frame", "bounds", "position", "anchor", "zPosition", "transform"],
        "sizing": [
            "hugging.horizontal",
            "hugging.vertical",
            "compression.horizontal",
            "compression.vertical",
            "intrinsic.width",
            "intrinsic.height"
        ],
        "autoLayout": ["autoresizing", "ambiguous"],
        "font": ["name", "size"],
        "lines": ["count", "lineBreak"],
        "state": ["enabled", "selected", "highlighted"],
        "scrolling": ["enabled", "paging"]
    ]
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

    public init(id: String, title: String, attributes: [Attribute], className: String? = nil) {
        self.id = id
        self.title = title
        self.attributes = attributes
        self.className = className
    }
}

/// What a server knows about one requested layer. Absent groups read as an empty array.
public struct LayerDetail: Sendable, Equatable {
    public var layerID: UInt64
    public var status: DetailStatus
    /// The layer without its sublayers.
    public var solo: WireImage?
    /// The layer with its whole subtree.
    public var group: WireImage?
    public var attributeGroups: [AttributeGroup]
    /// Absent on the wire reads as empty; P-LAYOUT-01 allows either.
    public var constraints: [LayoutConstraint]

    public init(
        layerID: UInt64,
        status: DetailStatus,
        solo: WireImage? = nil,
        group: WireImage? = nil,
        attributeGroups: [AttributeGroup] = [],
        constraints: [LayoutConstraint] = []
    ) {
        self.layerID = layerID
        self.status = status
        self.solo = solo
        self.group = group
        self.attributeGroups = attributeGroups
        self.constraints = constraints
    }
}

extension LayerDetail {
    /// P-HELLO-04, P-LAYOUT-08, P-ATTR-08, P-ATTR-14, P-LAYOUT-04: the detail as a peer working
    /// at `version` may receive it. Every layout attribute that `version` does not name becomes
    /// `notAnAttribute`, every section and unit it does not have `unspecified`, and every guide
    /// kind it does not have `other`; nothing else changes.
    public func adapted(to version: ProtocolVersion) -> LayerDetail {
        var detail = self
        detail.attributeGroups = attributeGroups.map { $0.adapted(to: version) }
        detail.constraints = constraints.map { $0.adapted(to: version) }
        return detail
    }
}

extension AttributeGroup {
    /// P-ATTR-08, P-ATTR-14: each section and unit the peer's version does not have becomes
    /// `unspecified`.
    func adapted(to version: ProtocolVersion) -> AttributeGroup {
        var group = self
        for index in group.attributes.indices {
            group.attributes[index].section = attributes[index].section.adapted(to: version)
            group.attributes[index].unit = attributes[index].unit.adapted(to: version)
        }
        return group
    }
}

public struct LayerDetailsChunk: Sendable, Equatable {
    /// Starts at 0 and grows by 1 (P-REQ-03).
    public var sequence: UInt32
    public var details: [LayerDetail]

    public init(sequence: UInt32, details: [LayerDetail]) {
        self.sequence = sequence
        self.details = details
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

// MARK: - Layout (protocol 0.4)

/// The same raw values as `NSLayoutConstraint.Attribute`.
public enum LayoutAttribute: UInt8, Sendable, Equatable, CaseIterable {
    case notAnAttribute = 0
    case left, right, top, bottom, leading, trailing, width, height, centerX, centerY
    case lastBaseline, firstBaseline
    case leftMargin, rightMargin, topMargin, bottomMargin, leadingMargin, trailingMargin
    case centerXWithinMargins, centerYWithinMargins
    /// UIKit's autoresizing mask constraints; not in the public `NSLayoutConstraint.Attribute`,
    /// same raw values: the view's edges in its superview (P-LAYOUT-07, 0.5).
    case minX = 32, minY = 33, maxX = 36, maxY = 37

    /// The minor version of protocol 1 that named this value: 1.0 names all there are. No
    /// `default`, so that a value added later cannot reach every peer by accident (P-HELLO-04).
    public var minorVersion: UInt16 {
        switch self {
        case .notAnAttribute, .left, .right, .top, .bottom, .leading, .trailing, .width, .height,
             .centerX, .centerY, .lastBaseline, .firstBaseline, .leftMargin, .rightMargin, .topMargin,
             .bottomMargin, .leadingMargin, .trailingMargin, .centerXWithinMargins,
             .centerYWithinMargins, .minX, .minY, .maxX, .maxY:
            return 0
        }
    }

    /// P-LAYOUT-08: a value the peer's version does not name is sent as no attribute.
    func adapted(to version: ProtocolVersion) -> Self {
        minorVersion <= version.minor ? self : .notAnAttribute
    }
}

/// Not the raw values of `NSLayoutConstraint.Relation` (PROTOCOL.md, "Constraints").
public enum LayoutRelation: Sendable, Equatable {
    case equal
    case lessThanOrEqual
    case greaterThanOrEqual
}

public enum LayoutItemKind: Sendable, Equatable {
    case view
    case layoutGuide
    case other
}

/// Which of its owner's guides a layout guide is (P-LAYOUT-04, protocol 1.1). `unknown` means
/// absent.
public enum LayoutGuideKind: Sendable, Equatable, CaseIterable {
    case unknown
    case other
    case safeArea
    case layoutMargins
    case readableContent
    case keyboard

    /// The minor version of protocol 1 that named this value. No `default` (P-HELLO-04).
    public var minorVersion: UInt16 {
        switch self {
        case .unknown: return 0
        case .other, .safeArea, .layoutMargins, .readableContent, .keyboard: return 1
        }
    }

    /// P-LAYOUT-04: a kind the peer's version does not have is sent as `other`. Absent stays
    /// absent.
    func adapted(to version: ProtocolVersion) -> Self {
        self == .unknown || minorVersion <= version.minor ? self : .other
    }
}

/// Whether a constraint's relation holds in the current layout (P-LAYOUT-06).
public enum ConstraintStatus: Sendable, Equatable {
    case unknown
    case satisfied
    case unsatisfied
}

/// One end of a constraint, field for field as on the wire, so that a checker can see which
/// fields were sent (P-LAYOUT-04).
public struct LayoutItem: Sendable, Equatable {
    public var kind: LayoutItemKind
    /// A view: its layer. A layout guide: its owning view's layer. 0 when absent.
    public var layerID: UInt64
    /// A layout guide only; 0 when absent.
    public var guideID: UInt64
    public var className: String?
    public var displayClassName: String?
    /// A layout guide's `identifier`.
    public var identifier: String?
    /// A layout guide's `layoutFrame`, in its owning view's bounds.
    public var guideFrame: WireRect?
    /// A layout guide only (protocol 1.1); `unknown` when absent.
    public var guideKind: LayoutGuideKind

    public init(
        kind: LayoutItemKind,
        layerID: UInt64 = 0,
        guideID: UInt64 = 0,
        className: String? = nil,
        displayClassName: String? = nil,
        identifier: String? = nil,
        guideFrame: WireRect? = nil,
        guideKind: LayoutGuideKind = .unknown
    ) {
        self.kind = kind
        self.layerID = layerID
        self.guideID = guideID
        self.className = className
        self.displayClassName = displayClassName
        self.identifier = identifier
        self.guideFrame = guideFrame
        self.guideKind = guideKind
    }
}

public struct LayoutConstraint: Sendable, Equatable {
    /// Stable within a connection, like layer IDs (P-LAYOUT-03).
    public var id: UInt64
    /// The runtime name of the constraint's class.
    public var className: String?
    public var identifier: String?
    /// Always sent (P-LAYOUT-04); `nil` only when a peer left it out.
    public var firstItem: LayoutItem?
    public var firstAttribute: LayoutAttribute
    public var relation: LayoutRelation
    /// `nil` when the constraint has no second item (P-LAYOUT-05).
    public var secondItem: LayoutItem?
    public var secondAttribute: LayoutAttribute
    public var multiplier: Double
    public var constant: Double
    public var priority: Float
    public var status: ConstraintStatus
    /// Whether UIKit created it (P-LAYOUT-09, protocol 1.1); `unknown` when absent.
    public var origin: Origin

    public init(
        id: UInt64,
        className: String?,
        identifier: String? = nil,
        firstItem: LayoutItem?,
        firstAttribute: LayoutAttribute,
        relation: LayoutRelation,
        secondItem: LayoutItem? = nil,
        secondAttribute: LayoutAttribute = .notAnAttribute,
        multiplier: Double,
        constant: Double,
        priority: Float,
        status: ConstraintStatus,
        origin: Origin = .unknown
    ) {
        self.id = id
        self.className = className
        self.identifier = identifier
        self.firstItem = firstItem
        self.firstAttribute = firstAttribute
        self.relation = relation
        self.secondItem = secondItem
        self.secondAttribute = secondAttribute
        self.multiplier = multiplier
        self.constant = constant
        self.priority = priority
        self.status = status
        self.origin = origin
    }
}

extension LayoutConstraint {
    /// P-LAYOUT-08: the constraint and both its items are sent all the same. P-LAYOUT-04: a
    /// guide kind the peer's version does not have becomes `other`.
    public func adapted(to version: ProtocolVersion) -> LayoutConstraint {
        var constraint = self
        constraint.firstAttribute = firstAttribute.adapted(to: version)
        constraint.secondAttribute = secondAttribute.adapted(to: version)
        constraint.firstItem?.guideKind = firstItem?.guideKind.adapted(to: version) ?? .unknown
        constraint.secondItem?.guideKind = secondItem?.guideKind.adapted(to: version) ?? .unknown
        return constraint
    }
}
#endif
