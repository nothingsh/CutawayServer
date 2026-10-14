#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// The Auto Layout constraints of a view (PROTOCOL.md, P-LAYOUT-01 to P-LAYOUT-05).
///
/// Reading only reads: `constraints`, the two items of each, a guide's `owningView`,
/// `identifier` and `layoutFrame`. Getters that create a layout guide on first use
/// (`safeAreaLayoutGuide`, `layoutMarginsGuide` and the like) are never called.
@MainActor
enum ConstraintCapture {
    /// P-LAYOUT-01: the active constraints whose first or second item is `view` or a layout
    /// guide that `view` owns, in the order they are found.
    ///
    /// An active constraint is installed on the nearest common ancestor of its items, so the
    /// view and its ancestors hold every one of them.
    ///
    /// - Parameter screenScale: Pixels per point; a relation holds within half a pixel
    ///   (P-LAYOUT-06).
    static func constraints(
        of view: UIView,
        registry: LayerRegistry,
        screenScale: CGFloat = UIScreen.main.scale
    ) -> [LayoutConstraint] {
        var found: [LayoutConstraint] = []
        var seen = Set<ObjectIdentifier>()
        var holder: UIView? = view
        while let current = holder {
            for constraint in current.constraints
                where refers(constraint.firstItem, to: view) || refers(constraint.secondItem, to: view) {
                guard seen.insert(ObjectIdentifier(constraint)).inserted else { continue }
                found.append(wireConstraint(constraint, registry: registry, screenScale: screenScale))
            }
            holder = current.superview
        }
        return found
    }

    /// Whether a constraint's item is `view`, or a layout guide `view` owns.
    private static func refers(_ item: AnyObject?, to view: UIView) -> Bool {
        guard let item else { return false }
        if item === view { return true }
        if let guide = item as? UILayoutGuide { return guide.owningView === view }
        return false
    }

    static func wireConstraint(
        _ constraint: NSLayoutConstraint,
        registry: LayerRegistry,
        screenScale: CGFloat
    ) -> LayoutConstraint {
        let identifier = constraint.identifier
        return LayoutConstraint(
            id: registry.register(constraint),
            className: ClassNames.runtimeName(of: type(of: constraint)),
            identifier: identifier?.isEmpty == false ? identifier : nil,
            firstItem: constraint.firstItem.map { item($0, registry: registry) },
            firstAttribute: attribute(constraint.firstAttribute),
            relation: relation(constraint.relation),
            secondItem: constraint.secondItem.map { item($0, registry: registry) },
            secondAttribute: constraint.secondItem == nil ? .notAnAttribute : attribute(constraint.secondAttribute),
            multiplier: WireGeometry.finite(constraint.multiplier),
            constant: WireGeometry.finite(constraint.constant),
            priority: WireGeometry.finite(constraint.priority.rawValue),
            status: ConstraintCheck.status(of: constraint, screenScale: screenScale),
            origin: origin(of: constraint)
        )
    }

    // MARK: - Who made it (P-LAYOUT-09)

    /// UIKit's conventions for the constraints it makes itself, as seen on iOS 26; they change,
    /// and these follow them. Not a closed list: a constraint UIKit makes through the public API
    /// without an identifier (inside one of its controls, say) is taken as the app's.
    private static let systemClassNames: Set<String> = [
        "NSAutoresizingMaskLayoutConstraint",
        "NSContentSizeLayoutConstraint",
        "_UILayoutSupportConstraint"
    ]

    private static let systemIdentifierPrefixes = [
        "UISV-",
        "UIView-",
        "UIViewSafeAreaLayoutGuide-",
        "UIViewKeyboardLayoutGuide-",
        "UIKeyboardLayoutGuide-",
        "_UITemporaryLayout"
    ]

    /// The class of a constraint made with layout anchors is a private one of UIKit's, so the
    /// image of the class says nothing: only UIKit's own classes and identifiers do.
    static func origin(of constraint: NSLayoutConstraint) -> Origin {
        var type: AnyClass? = Swift.type(of: constraint)
        while let current = type, current != NSLayoutConstraint.self {
            if systemClassNames.contains(NSStringFromClass(current)) { return .system }
            type = class_getSuperclass(current)
        }
        if let identifier = constraint.identifier,
           systemIdentifierPrefixes.contains(where: { identifier.hasPrefix($0) }) {
            return .system
        }
        return .app
    }

    /// P-LAYOUT-04: a view is given by its layer; a layout guide by its owner's layer, its own
    /// ID, its class and its frame; anything else by its class alone.
    static func item(_ object: AnyObject, registry: LayerRegistry) -> LayoutItem {
        if let view = object as? UIView {
            return LayoutItem(kind: .view, layerID: registry.register(view.layer))
        }
        let type: AnyClass = Swift.type(of: object)
        let className = ClassNames.runtimeName(of: type)
        let displayClassName = ClassNames.displayName(of: type)
        // A guide without an owner takes part in no active constraint; told apart all the same.
        if let guide = object as? UILayoutGuide, let owner = guide.owningView {
            let identifier = guide.identifier
            return LayoutItem(
                kind: .layoutGuide,
                layerID: registry.register(owner.layer),
                guideID: registry.register(guide),
                className: className,
                displayClassName: displayClassName,
                identifier: identifier.isEmpty ? nil : identifier,
                guideFrame: WireGeometry.rect(guide.layoutFrame),
                guideKind: kind(of: guide)
            )
        }
        return LayoutItem(kind: .other, className: className, displayClassName: displayClassName)
    }

    /// P-LAYOUT-04: which of its owner's guides `guide` is, from its own class and identifier.
    /// The owner's guide properties are not read: each makes its guide the first time.
    static func kind(of guide: UILayoutGuide) -> LayoutGuideKind {
        if #available(iOS 15, *), guide is UIKeyboardLayoutGuide { return .keyboard }
        switch guide.identifier {
        case "UIViewSafeAreaLayoutGuide": return .safeArea
        case "UIViewLayoutMarginsGuide": return .layoutMargins
        case "UIViewReadableContentGuide": return .readableContent
        default: return .other
        }
    }

    /// The raw values are the same, UIKit's unpublished ones for autoresizing masks included
    /// (P-LAYOUT-07). One the protocol does not name is sent as no attribute (P-LAYOUT-08);
    /// the session also replaces those the client's version lacks.
    static func attribute(_ attribute: NSLayoutConstraint.Attribute) -> LayoutAttribute {
        UInt8(exactly: attribute.rawValue).flatMap(LayoutAttribute.init(rawValue:)) ?? .notAnAttribute
    }

    static func relation(_ relation: NSLayoutConstraint.Relation) -> LayoutRelation {
        switch relation {
        case .lessThanOrEqual: return .lessThanOrEqual
        case .equal: return .equal
        case .greaterThanOrEqual: return .greaterThanOrEqual
        @unknown default: return .equal
        }
    }
}
#endif
