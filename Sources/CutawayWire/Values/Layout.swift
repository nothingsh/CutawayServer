#if !canImport(UIKit) || DEBUG || ReleaseEnabled

// The value types of constraints (PROTOCOL.md, "Constraints", protocol 0.4).

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
