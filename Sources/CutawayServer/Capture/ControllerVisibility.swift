#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Whether view controllers are shown (PROTOCOL.md, P-HIER-18), worked out once per controller
/// in one capture.
///
/// Only reads what is already there: `viewIfLoaded`, `window`, `parent`, a page view
/// controller's `viewControllers` and a split view controller's columns and display mode. A
/// controller's view is never loaded, and no `presentationController` is asked for, since
/// asking creates one. UIKit takes out of the window the view of a controller under a
/// full-screen presentation, below the top of a navigation stack, or on a tab that is not
/// selected, so "in a window" covers them. During a transition either answer is allowed.
@MainActor
struct ControllerVisibility {
    private var known: [ObjectIdentifier: Bool] = [:]

    mutating func visibility(of controller: UIViewController) -> ViewControllerVisibility {
        isShown(controller) ? .shown : .notShown
    }

    private mutating func isShown(_ controller: UIViewController) -> Bool {
        let key = ObjectIdentifier(controller)
        if let answer = known[key] { return answer }
        let answer = Self.isInWindow(controller) && parentShows(controller)
        known[key] = answer
        return answer
    }

    private static func isInWindow(_ controller: UIViewController) -> Bool {
        controller.viewIfLoaded?.window != nil
    }

    /// Whether the parent is shown, and shows this child among its children.
    private mutating func parentShows(_ child: UIViewController) -> Bool {
        guard let parent = child.parent else { return true }
        guard isShown(parent) else { return false }
        if let pages = parent as? UIPageViewController {
            return pages.viewControllers?.contains { $0 === child } ?? false
        }
        if let split = parent as? UISplitViewController {
            return Self.split(split, shows: child)
        }
        return true
    }

    /// When collapsed, the children not shown are out of the window already. Otherwise the
    /// display mode says which columns show.
    private static func split(_ split: UISplitViewController, shows child: UIViewController) -> Bool {
        guard !split.isCollapsed, let column = column(of: child, in: split) else { return true }
        switch (column, split.displayMode) {
        case (.secondary, _):
            return true
        case (.primary, .secondaryOnly):
            return false
        case (.primary, .oneBesideSecondary), (.primary, .oneOverSecondary):
            // With three columns, the one beside the secondary is the supplementary.
            return !hasSupplementary(split)
        case (.supplementary, .secondaryOnly):
            return false
        default:
            return true
        }
    }

    private enum Column {
        case primary
        case supplementary
        case secondary
    }

    /// The column whose controller `child` is. A split view controller puts a controller set
    /// for a column into a navigation controller of its own, which is then the child.
    private static func column(of child: UIViewController, in split: UISplitViewController) -> Column? {
        if #available(iOS 14, *), split.style != .unspecified {
            let columns: [(UISplitViewController.Column, Column)] = [
                (.primary, .primary),
                (.supplementary, .supplementary),
                (.secondary, .secondary)
            ]
            for (column, name) in columns {
                guard let controller = split.viewController(for: column) else { continue }
                if controller === child || controller.navigationController === child { return name }
            }
            return nil
        }
        let children = split.viewControllers
        guard let index = children.firstIndex(where: { $0 === child }) else { return nil }
        return index == 0 ? .primary : .secondary
    }

    private static func hasSupplementary(_ split: UISplitViewController) -> Bool {
        if #available(iOS 14, *) { return split.style == .tripleColumn }
        return false
    }
}
#endif
