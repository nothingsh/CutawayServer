#if !canImport(UIKit) || DEBUG || ReleaseEnabled

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

/// Where a class, or a constraint, comes from (P-HIER-16, P-LAYOUT-09, protocol 1.1).
/// `unknown` means absent.
public enum Origin: Sendable, Equatable, CaseIterable {
    case unknown
    case system
    case app
}

/// Whether a view controller is shown (P-HIER-18, protocol 1.1). `unknown` means absent.
public enum ViewControllerVisibility: Sendable, Equatable, CaseIterable {
    case unknown
    case shown
    case notShown
}

/// What a hierarchy node stands for (P-HIER-19, protocol 1.2).
public enum NodeKind: Sendable, Equatable, CaseIterable {
    /// A layer of the app.
    case layer
    /// A part of the interface the host app draws itself and describes to the server.
    case virtual
}

/// The protocol's tables of known classes (P-HIER-17, protocol 1.1): only appended to, each
/// entry with the minor version of protocol 1 that added it.
public enum KnownClasses {
    public struct Entry: Sendable, Equatable {
        /// The runtime name of the class; `UIHostingView` names no class (see `hostingView`).
        public var name: String
        public var minorVersion: UInt16
    }

    /// Stands for a view SwiftUI uses to host SwiftUI content in UIKit; not a runtime name.
    public static let hostingView = "UIHostingView"

    public static let views: [Entry] = [
        "UIWindow",
        "UILabel",
        "UITextField",
        "UITextView",
        "UISegmentedControl",
        "UIPageControl",
        "UIStepper",
        "UIDatePicker",
        "UIPickerView",
        "UIButton",
        "UISwitch",
        "UISlider",
        "UIControl",
        "UIImageView",
        "UITableViewCell",
        "UICollectionViewCell",
        "UICollectionReusableView",
        "UITableViewHeaderFooterView",
        "UICollectionView",
        "UITableView",
        "UIScrollView",
        "UINavigationBar",
        "UITabBar",
        "UIToolbar",
        "UISearchBar",
        "WKWebView",
        "MKMapView",
        "UIActivityIndicatorView",
        "UIProgressView",
        "UIStackView",
        "UIVisualEffectView",
        hostingView
    ].map { Entry(name: $0, minorVersion: 1) }

    public static let layers: [Entry] = ["CAShapeLayer", "CAGradientLayer", "CATextLayer"]
        .map { Entry(name: $0, minorVersion: 1) }

    /// The names of `entries` that a peer working at `version` knows.
    public static func names(of entries: [Entry], at version: ProtocolVersion) -> Set<String> {
        Set(entries.filter { $0.minorVersion <= version.minor }.map(\.name))
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
    /// Addresses in the app's process when the hierarchy was captured, for display only: an
    /// address may be reused once its object is released (P-HIER-14, P-HIER-15, protocol 1.1).
    /// 0 when absent on the wire.
    public var layerAddress: UInt64
    /// Set exactly when `viewClassName` is. 0 on the wire reads as nil.
    public var viewAddress: UInt64?
    /// Set exactly when `viewControllerClassName` is. 0 on the wire reads as nil.
    public var viewControllerAddress: UInt64?
    /// Where each class comes from, given exactly when its name is (P-HIER-16, protocol 1.1).
    public var layerClassOrigin: Origin
    public var viewClassOrigin: Origin
    public var viewControllerClassOrigin: Origin
    /// The nearest class of the protocol's tables (P-HIER-17, protocol 1.1).
    public var layerBaseClassName: String?
    /// Only when the layer backs a view.
    public var viewBaseClassName: String?
    /// Given exactly when `viewControllerClassName` is (P-HIER-18, protocol 1.1).
    public var viewControllerVisibility: ViewControllerVisibility
    /// A layer or a virtual node (P-HIER-19, protocol 1.2).
    public var nodeKind: NodeKind
    /// A virtual node's short label (P-HIER-20, protocol 1.2); layers have none.
    public var name: String?
    /// The host app would like the node shown collapsed at first (P-HIER-23, protocol 1.2).
    public var isCollapsedByDefault: Bool
    /// The host app excludes the node, with its subtree, from images (P-DET-10, protocol 1.2).
    public var isCaptureExcluded: Bool

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
        memberReferences: [MemberReference] = [],
        layerAddress: UInt64 = 0,
        viewAddress: UInt64? = nil,
        viewControllerAddress: UInt64? = nil,
        layerClassOrigin: Origin = .unknown,
        viewClassOrigin: Origin = .unknown,
        viewControllerClassOrigin: Origin = .unknown,
        layerBaseClassName: String? = nil,
        viewBaseClassName: String? = nil,
        viewControllerVisibility: ViewControllerVisibility = .unknown,
        nodeKind: NodeKind = .layer,
        name: String? = nil,
        isCollapsedByDefault: Bool = false,
        isCaptureExcluded: Bool = false
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
        self.layerAddress = layerAddress
        self.viewAddress = viewAddress
        self.viewControllerAddress = viewControllerAddress
        self.layerClassOrigin = layerClassOrigin
        self.viewClassOrigin = viewClassOrigin
        self.viewControllerClassOrigin = viewControllerClassOrigin
        self.layerBaseClassName = layerBaseClassName
        self.viewBaseClassName = viewBaseClassName
        self.viewControllerVisibility = viewControllerVisibility
        self.nodeKind = nodeKind
        self.name = name
        self.isCollapsedByDefault = isCollapsedByDefault
        self.isCaptureExcluded = isCaptureExcluded
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
