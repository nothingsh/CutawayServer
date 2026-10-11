#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Whether a constraint's relation holds in the current layout (PROTOCOL.md, P-LAYOUT-06).
///
/// Both ends are measured the way Auto Layout measures them: in
/// the coordinate system of the nearest common ancestor of their views, from `center` and
/// `bounds` alone (no transform, no anchor point), a view by its alignment rectangle and a
/// layout guide by its `layoutFrame`; leading and trailing follow the layout direction of
/// that ancestor. Nothing is laid out first: the answer is about the layout as it is.
@MainActor
enum ConstraintCheck {
    static func status(of constraint: NSLayoutConstraint, screenScale: CGFloat) -> ConstraintStatus {
        guard let firstObject = constraint.firstItem,
              let first = End(firstObject, constraint.firstAttribute) else {
            return .unknown
        }
        let firstValue: CGFloat
        let rightSide: CGFloat
        if let secondObject = constraint.secondItem {
            guard let second = End(secondObject, constraint.secondAttribute),
                  let ancestor = commonAncestor(first.owner, second.owner),
                  !first.isScrollViewEdge(seenFrom: second, in: ancestor),
                  !second.isScrollViewEdge(seenFrom: first, in: ancestor),
                  let one = first.value(in: ancestor, direction: ancestor),
                  let other = second.value(in: ancestor, direction: ancestor) else {
                return .unknown
            }
            firstValue = one
            rightSide = other * constraint.multiplier + constraint.constant
        } else {
            // Without a second item only a size can be constrained, and a size is the same in
            // every coordinate system.
            guard first.isSize, let one = first.value(in: first.owner, direction: first.owner) else {
                return .unknown
            }
            firstValue = one
            rightSide = constraint.constant
        }
        guard firstValue.isFinite, rightSide.isFinite, screenScale > 0 else { return .unknown }
        let holding = holds(
            Double(firstValue),
            constraint.relation,
            Double(rightSide),
            tolerance: 0.5 / Double(screenScale)
        )
        return holding ? .satisfied : .unsatisfied
    }

    /// The relation, allowing `tolerance` either way.
    nonisolated static func holds(
        _ first: Double,
        _ relation: NSLayoutConstraint.Relation,
        _ second: Double,
        tolerance: Double
    ) -> Bool {
        switch relation {
        case .lessThanOrEqual: return first <= second + tolerance
        case .greaterThanOrEqual: return first >= second - tolerance
        default: return abs(first - second) <= tolerance
        }
    }

    /// One end of a constraint: a view or a layout guide, and one of its attributes. `nil`
    /// for an end that cannot be measured: text baselines, objects that are neither views
    /// nor owned guides, and margins of a guide, which has none.
    @MainActor private struct End {
        let view: UIView?
        let guide: UILayoutGuide?
        /// The view itself, or the guide's owner.
        let owner: UIView
        let attribute: NSLayoutConstraint.Attribute

        init?(_ item: AnyObject, _ attribute: NSLayoutConstraint.Attribute) {
            switch attribute {
            case .notAnAttribute, .firstBaseline, .lastBaseline: return nil
            default: break
            }
            if let view = item as? UIView {
                self.view = view
                guide = nil
                owner = view
            } else if let guide = item as? UILayoutGuide, let owner = guide.owningView,
                      !Self.margins.contains(attribute) {
                view = nil
                self.guide = guide
                self.owner = owner
            } else {
                return nil
            }
            self.attribute = attribute
        }

        static let margins: Set<NSLayoutConstraint.Attribute> = [
            .leftMargin,
            .rightMargin,
            .topMargin,
            .bottomMargin,
            .leadingMargin,
            .trailingMargin,
            .centerXWithinMargins,
            .centerYWithinMargins
        ]

        var isSize: Bool { attribute == .width || attribute == .height }

        /// A scroll view's own edge, constrained to a view inside it: Auto Layout reads it as an
        /// edge of the content, which this check does not try to work out.
        func isScrollViewEdge(seenFrom other: Self, in ancestor: UIView) -> Bool {
            guard let scrollView = view as? UIScrollView else { return false }
            return scrollView === ancestor && other.owner !== scrollView
        }

        /// The attribute's value in `ancestor`'s coordinate system. Leading and trailing are read
        /// in the layout direction of `direction`: right to left, the axis is mirrored, so the
        /// leading edge is the right one and its value is the negated x.
        ///
        /// The edges are taken as stored, not standardized: margins larger than the view give a
        /// negative size, and the top margin is still the top plus the margin.
        func value(in ancestor: UIView, direction: UIView) -> CGFloat? {
            guard let rect = rect(in: ancestor) else { return nil }
            let left = rect.origin.x
            let right = rect.origin.x + rect.size.width
            let top = rect.origin.y
            let bottom = rect.origin.y + rect.size.height
            let rightToLeft = direction.effectiveUserInterfaceLayoutDirection == .rightToLeft
            switch attribute {
            case .left, .leftMargin: return left
            case .right, .rightMargin: return right
            case .top, .topMargin: return top
            case .bottom, .bottomMargin: return bottom
            case .leading, .leadingMargin: return rightToLeft ? -right : left
            case .trailing, .trailingMargin: return rightToLeft ? -left : right
            case .width: return rect.size.width
            case .height: return rect.size.height
            case .centerX, .centerXWithinMargins: return left + rect.size.width / 2
            case .centerY, .centerYWithinMargins: return top + rect.size.height / 2
            default: return nil
            }
        }

        private func rect(in ancestor: UIView) -> CGRect? {
            if let guide {
                return ConstraintCheck.convert(guide.layoutFrame, from: owner, to: ancestor)
            }
            guard let view else { return nil }
            let alignment: CGRect?
            if view === ancestor {
                alignment = view.alignmentRect(forFrame: view.bounds)
            } else if let superview = view.superview {
                alignment = ConstraintCheck.convert(
                    view.alignmentRect(forFrame: ConstraintCheck.untransformedFrame(of: view)),
                    from: superview,
                    to: ancestor
                )
            } else {
                alignment = nil
            }
            // Margins are taken from the alignment rectangle.
            guard Self.margins.contains(attribute) else { return alignment }
            let margins = view.layoutMargins
            return alignment.map {
                CGRect(
                    x: $0.origin.x + margins.left,
                    y: $0.origin.y + margins.top,
                    width: $0.size.width - margins.left - margins.right,
                    height: $0.size.height - margins.top - margins.bottom
                )
            }
        }
    }

    /// The frame Auto Layout sees, in the superview's coordinates: `center` and the size of
    /// `bounds`, without the transform and regardless of the anchor point.
    private static func untransformedFrame(of view: UIView) -> CGRect {
        let size = view.bounds.size
        let center = view.center
        return CGRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// A rectangle in `view`'s coordinates, in `ancestor`'s; `nil` when `ancestor` is not one.
    private static func convert(_ rect: CGRect, from view: UIView, to ancestor: UIView) -> CGRect? {
        var rect = rect
        var current = view
        while current !== ancestor {
            guard let superview = current.superview else { return nil }
            let frame = untransformedFrame(of: current)
            rect.origin.x += frame.origin.x - current.bounds.origin.x
            rect.origin.y += frame.origin.y - current.bounds.origin.y
            current = superview
        }
        return rect
    }

    /// The nearest view that is `first` or one of its ancestors and also `second` or one of
    /// its ancestors.
    private static func commonAncestor(_ first: UIView, _ second: UIView) -> UIView? {
        var chain = Set<ObjectIdentifier>()
        var current: UIView? = first
        while let view = current {
            chain.insert(ObjectIdentifier(view))
            current = view.superview
        }
        current = second
        while let view = current {
            if chain.contains(ObjectIdentifier(view)) { return view }
            current = view.superview
        }
        return nil
    }
}
#endif
