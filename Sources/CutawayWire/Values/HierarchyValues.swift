#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

// The value types of the layer hierarchy (PROTOCOL.md, "Hierarchy").

/// An instance variable that holds a layer, or the view the layer backs (PROTOCOL.md,
/// P-HIER-08, P-HIER-09).
public struct MemberReference: Sendable, Equatable {
    /// The runtime name of the class that declares the variable. Empty when absent on the wire.
    public var ownerClassName: String
    /// The readable name of that class. Empty when absent on the wire.
    public var ownerDisplayClassName: String
    /// The variable's name as declared. Empty when absent on the wire.
    public var name: String

    public init(ownerClassName: String, ownerDisplayClassName: String, name: String) {
        self.ownerClassName = ownerClassName
        self.ownerDisplayClassName = ownerDisplayClassName
        self.name = name
    }
}

/// One layer. Geometry holds the layer's model values (PROTOCOL.md, P-HIER-05, P-HIER-06).
/// A geometry field that is absent on the wire reads as zeros.
public struct LayerNode: Sendable, Equatable {
    /// Never 0 in a hierarchy a server sends (P-HIER-03).
    public var id: UInt64
    /// 0 for a window's root layer.
    public var parentID: UInt64
    /// The runtime name of the layer's class. Empty when absent on the wire.
    public var className: String
    /// The readable name of the layer's class. Empty when absent on the wire.
    public var displayClassName: String
    /// Set when the layer backs a view (P-HIER-04).
    public var viewClassName: String?
    public var viewDisplayClassName: String?
    public var bounds: WireRect
    /// In the parent layer's coordinates; a root layer's is in screen coordinates.
    public var position: WirePoint
    public var anchorPoint: WirePoint
    public var transform: WireTransform
    public var zPosition: Double
    public var isHidden: Bool
    public var opacity: Float
    public var masksToBounds: Bool
    /// Set when the layer backs a view controller's root view (P-HIER-07).
    public var viewControllerClassName: String?
    public var viewControllerDisplayClassName: String?
    /// Nearest holder first (P-HIER-08). Empty when absent on the wire.
    public var memberReferences: [MemberReference]

    public init(
        id: UInt64,
        parentID: UInt64,
        className: String,
        displayClassName: String,
        viewClassName: String? = nil,
        viewDisplayClassName: String? = nil,
        bounds: WireRect,
        position: WirePoint,
        anchorPoint: WirePoint = WirePoint(x: 0.5, y: 0.5),
        transform: WireTransform = .identity,
        zPosition: Double = 0,
        isHidden: Bool = false,
        opacity: Float = 1,
        masksToBounds: Bool = false,
        viewControllerClassName: String? = nil,
        viewControllerDisplayClassName: String? = nil,
        memberReferences: [MemberReference] = []
    ) {
        self.id = id
        self.parentID = parentID
        self.className = className
        self.displayClassName = displayClassName
        self.viewClassName = viewClassName
        self.viewDisplayClassName = viewDisplayClassName
        self.bounds = bounds
        self.position = position
        self.anchorPoint = anchorPoint
        self.transform = transform
        self.zPosition = zPosition
        self.isHidden = isHidden
        self.opacity = opacity
        self.masksToBounds = masksToBounds
        self.viewControllerClassName = viewControllerClassName
        self.viewControllerDisplayClassName = viewControllerDisplayClassName
        self.memberReferences = memberReferences
    }
}

public struct Hierarchy: Sendable, Equatable {
    /// Pre-order: a node's parent comes before it; siblings are in drawing order, back to
    /// front: by `zPosition`, then by their order in the parent's sublayers (P-HIER-01).
    public var nodes: [LayerNode]
    /// The ID of the key window's root layer; 0 when there is no key window.
    public var keyWindowID: UInt64

    public init(nodes: [LayerNode], keyWindowID: UInt64) {
        self.nodes = nodes
        self.keyWindowID = keyWindowID
    }
}
#endif
