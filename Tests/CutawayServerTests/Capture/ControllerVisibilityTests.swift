import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Counts how often its presentation controller is asked for: reading it creates one.
private final class WatchedController: UIViewController {
    var presentationControllerReads = 0

    override var presentationController: UIPresentationController? {
        presentationControllerReads += 1
        return super.presentationController
    }
}

/// P-HIER-18: whether the view controllers in a hierarchy are shown.
@MainActor
final class ControllerVisibilityTests: CaptureTestCase {
    private func visibility(
        of controller: UIViewController,
        in window: UIWindow,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ViewControllerVisibility {
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        let view = try XCTUnwrap(controller.viewIfLoaded, "the view is not loaded", file: file, line: line)
        guard let node = hierarchy.nodes.first(where: { $0.id == registry.register(view.layer) }) else {
            // A view out of the window has no node; its controller is not shown.
            var visibility = ControllerVisibility()
            return visibility.visibility(of: controller)
        }
        // Given exactly when the controller's class name is.
        for node in hierarchy.nodes {
            XCTAssertEqual(
                node.viewControllerVisibility != .unknown,
                node.viewControllerClassName != nil,
                "\(node.id)",
                file: file,
                line: line
            )
        }
        return node.viewControllerVisibility
    }

    /// Runs the main run loop until `condition` holds: presentations and the end of a
    /// transition take a turn or two even without animation.
    private func wait(until condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertTrue(condition(), "timed out", file: file, line: line)
    }

    func test_S_HIER_16_theRootControllerIsShown() throws {
        let window = try makeWindow()
        let root = UIViewController()
        window.rootViewController = root
        XCTAssertEqual(try visibility(of: root, in: window), .shown)
    }

    func test_S_HIER_16_onlyTheTopOfANavigationStackIsShown() throws {
        let window = try makeWindow()
        let bottom = UIViewController()
        let navigation = UINavigationController(rootViewController: bottom)
        window.rootViewController = navigation
        window.layoutIfNeeded()
        let top = UIViewController()
        navigation.pushViewController(top, animated: false)
        wait { bottom.viewIfLoaded?.window == nil && top.viewIfLoaded?.window != nil }

        XCTAssertEqual(try visibility(of: navigation, in: window), .shown)
        XCTAssertEqual(try visibility(of: top, in: window), .shown)
        XCTAssertEqual(try visibility(of: bottom, in: window), .notShown)
    }

    func test_S_HIER_16_onlyTheSelectedTabIsShown() throws {
        let window = try makeWindow()
        let first = UIViewController()
        let second = UIViewController()
        let tabs = UITabBarController()
        tabs.viewControllers = [first, second]
        window.rootViewController = tabs
        window.layoutIfNeeded()
        // Both views loaded, the second one left.
        tabs.selectedIndex = 1
        window.layoutIfNeeded()
        tabs.selectedIndex = 0
        wait { second.viewIfLoaded != nil && second.viewIfLoaded?.window == nil && first.view.window != nil }

        XCTAssertEqual(try visibility(of: first, in: window), .shown)
        XCTAssertEqual(try visibility(of: second, in: window), .notShown)
    }

    func test_S_HIER_16_aFullScreenPresentationCoversWhatIsBelow() throws {
        let window = try makeWindow()
        let root = WatchedController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let presented = WatchedController()
        presented.modalPresentationStyle = .fullScreen
        root.present(presented, animated: false)
        wait { root.view.window == nil && presented.viewIfLoaded?.window != nil }

        XCTAssertEqual(try visibility(of: presented, in: window), .shown)
        XCTAssertEqual(try visibility(of: root, in: window), .notShown)
        // The presented controller exists; nothing else asked for one.
        let readsBefore = (root.presentationControllerReads, presented.presentationControllerReads)
        _ = HierarchyCapture.capture(.testing(windows: [window], registry: LayerRegistry()))
        XCTAssertEqual(root.presentationControllerReads, readsBefore.0)
        XCTAssertEqual(presented.presentationControllerReads, readsBefore.1)
        presented.dismiss(animated: false)
        wait { root.presentedViewController == nil }
    }

    func test_S_HIER_16_anOverFullScreenPresentationLeavesWhatIsBelowShown() throws {
        let window = try makeWindow()
        let root = UIViewController()
        window.rootViewController = root
        window.makeKeyAndVisible()
        let presented = UIViewController()
        presented.modalPresentationStyle = .overFullScreen
        root.present(presented, animated: false)
        wait { presented.viewIfLoaded?.window != nil }

        XCTAssertEqual(try visibility(of: presented, in: window), .shown)
        XCTAssertEqual(try visibility(of: root, in: window), .shown)
        presented.dismiss(animated: false)
        wait { root.presentedViewController == nil }
    }

    func test_S_HIER_16_thePagesOnScreenAreShown() throws {
        let window = try makeWindow()
        let pages = UIPageViewController(transitionStyle: .scroll, navigationOrientation: .horizontal)
        let page = UIViewController()
        pages.setViewControllers([page], direction: .forward, animated: false)
        window.rootViewController = pages
        window.layoutIfNeeded()

        XCTAssertEqual(try visibility(of: pages, in: window), .shown)
        XCTAssertEqual(try visibility(of: page, in: window), .shown)

        // A page that is a child but not one of the current pages, as during a scroll.
        let neighbor = UIViewController()
        pages.addChild(neighbor)
        pages.view.addSubview(neighbor.view)
        neighbor.didMove(toParent: pages)
        XCTAssertEqual(try visibility(of: neighbor, in: window), .notShown)
    }

    func test_S_HIER_16_aHiddenColumnOfASplitViewIsNotShown() throws {
        let window = try makeWindow()
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let split = UISplitViewController(style: .doubleColumn)
        let primary = UIViewController()
        let secondary = UIViewController()
        split.setViewController(primary, for: .primary)
        split.setViewController(secondary, for: .secondary)
        split.preferredDisplayMode = .secondaryOnly
        // Regular width, so that the split view does not collapse.
        let container = UIViewController()
        container.addChild(split)
        container.view.addSubview(split.view)
        split.view.frame = container.view.bounds
        split.didMove(toParent: container)
        container.setOverrideTraitCollection(UITraitCollection(horizontalSizeClass: .regular), forChild: split)
        window.rootViewController = container
        window.layoutIfNeeded()
        wait { !split.isCollapsed && split.displayMode == .secondaryOnly && secondary.viewIfLoaded?.window != nil }

        XCTAssertEqual(try visibility(of: secondary, in: window), .shown)
        // In the window or not, the hidden column is not shown.
        XCTAssertTrue(primary.isViewLoaded, "the split view loads its columns")
        XCTAssertEqual(try visibility(of: primary, in: window), .notShown)
        // The column's navigation controller is the split view's child.
        if let column = primary.navigationController, column.isViewLoaded {
            XCTAssertEqual(try visibility(of: column, in: window), .notShown)
        }

        split.preferredDisplayMode = .oneBesideSecondary
        wait { split.displayMode == .oneBesideSecondary && primary.viewIfLoaded?.window != nil }
        XCTAssertEqual(try visibility(of: primary, in: window), .shown)
    }

    func test_S_HIER_16_aViewOutOfTheWindowIsNotShownAndNothingIsLoaded() throws {
        let window = try makeWindow()
        let root = UIViewController()
        window.rootViewController = root
        let unloaded = UIViewController()
        root.addChild(unloaded)
        unloaded.didMove(toParent: root)
        _ = HierarchyCapture.capture(.testing(windows: [window], registry: LayerRegistry()))
        XCTAssertFalse(unloaded.isViewLoaded)
    }
}
