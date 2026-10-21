import UIKit
import XCTest

@testable import CutawayServer

/// What overriding the environment of protocol 1.2 rests on: UIKit lays views out by an
/// overridden layout direction, a window's traits can be overridden and put back, and the main
/// run loop runs a block queued from the main queue in a later turn. UIKit's and the main
/// queue's own behavior, tested without the server. The layout direction is also tried on a
/// device.
final class EnvironmentAssumptionTests: CaptureTestCase {
    // MARK: - The layout direction

    /// Overriding a window's layout direction makes UIKit lay its views out right to left.
    func test_S_ENV_02_H1_layoutDirectionOverrideLaysOutRightToLeft() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("trait overrides need iOS 17") }
        let (window, content) = try makeContentWindow()
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(box)
        let first = UIView()
        let second = UIView()
        let stack = UIStackView(arrangedSubviews: [first, second])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.distribution = .fillEqually
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            box.topAnchor.constraint(equalTo: content.topAnchor, constant: 100),
            box.widthAnchor.constraint(equalToConstant: 50),
            box.heightAnchor.constraint(equalToConstant: 50),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 200),
            stack.heightAnchor.constraint(equalToConstant: 40)
        ])
        window.layoutIfNeeded()
        XCTAssertEqual(box.effectiveUserInterfaceLayoutDirection, .leftToRight)
        XCTAssertEqual(box.frame.minX, 20)
        XCTAssertLessThan(first.frame.minX, second.frame.minX)

        window.traitOverrides.layoutDirection = .rightToLeft
        window.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(window.traitCollection.layoutDirection, .rightToLeft)
        XCTAssertEqual(box.traitCollection.layoutDirection, .rightToLeft)
        XCTAssertEqual(box.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        XCTAssertEqual(box.frame.maxX, content.bounds.width - 20, "the leading edge moved to the right")
        XCTAssertGreaterThan(first.frame.minX, second.frame.minX, "the first arranged view is on the right")

        window.traitOverrides.remove(UITraitLayoutDirection.self)
        window.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(box.effectiveUserInterfaceLayoutDirection, .leftToRight)
        XCTAssertEqual(box.frame.minX, 20)
    }

    // MARK: - The appearance

    /// A window's `overrideUserInterfaceStyle` can be read, replaced and put back.
    func test_S_ENV_03_H2_windowStyleOfTheAppIsRestored() throws {
        let (window, content) = try makeContentWindow()
        window.overrideUserInterfaceStyle = .light
        let own = window.overrideUserInterfaceStyle

        window.overrideUserInterfaceStyle = .dark
        window.layoutIfNeeded()
        XCTAssertEqual(content.traitCollection.userInterfaceStyle, .dark)

        window.overrideUserInterfaceStyle = own
        window.layoutIfNeeded()
        XCTAssertEqual(window.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(content.traitCollection.userInterfaceStyle, .light)
    }

    /// On iOS 17, a style the app sets with `traitOverrides` reads back through
    /// `overrideUserInterfaceStyle`, so recording one records the other.
    func test_S_ENV_03_H2_styleTraitOverrideIsTheSameAsOverrideStyle() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("trait overrides need iOS 17") }
        let (window, content) = try makeContentWindow()
        window.traitOverrides.userInterfaceStyle = .light
        XCTAssertEqual(window.overrideUserInterfaceStyle, .light)

        window.overrideUserInterfaceStyle = .dark
        window.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(content.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(window.traitOverrides.userInterfaceStyle, .dark)

        window.overrideUserInterfaceStyle = .unspecified
        XCTAssertFalse(window.traitOverrides.contains(UITraitUserInterfaceStyle.self))
    }

    /// A window's style takes precedence over the scene's.
    func test_S_ENV_02_H2_windowStyleWinsOverSceneOverride() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("trait overrides need iOS 17") }
        let scene = try hostScene()
        let hadOwn = scene.traitOverrides.contains(UITraitUserInterfaceStyle.self)
        XCTAssertFalse(hadOwn, "the test host sets no style on its scene")
        scene.traitOverrides.userInterfaceStyle = .light
        defer { scene.traitOverrides.remove(UITraitUserInterfaceStyle.self) }
        let (window, content) = try makeContentWindow()
        window.layoutIfNeeded()
        XCTAssertEqual(content.traitCollection.userInterfaceStyle, .light)

        window.overrideUserInterfaceStyle = .dark
        window.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(content.traitCollection.userInterfaceStyle, .dark)
    }

    /// P-ENV-05: a view controller's own style still wins below it.
    func test_S_ENV_02_H2_viewControllerStyleStillWins() throws {
        let (window, _) = try makeContentWindow()
        let child = UIViewController()
        child.overrideUserInterfaceStyle = .light
        let root = try XCTUnwrap(window.rootViewController)
        root.addChild(child)
        root.view.addSubview(child.view)
        child.didMove(toParent: root)

        window.overrideUserInterfaceStyle = .dark
        if #available(iOS 17, *) { window.updateTraitsIfNeeded() }
        window.layoutIfNeeded()
        XCTAssertEqual(root.view.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(child.view.traitCollection.userInterfaceStyle, .light)
    }

    // MARK: - The other four kinds

    /// A trait the app overrides on a window can be recorded, replaced and put back, and
    /// one it does not override can be removed again.
    func test_S_ENV_03_H2_windowTraitOverridesAreRestored() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("trait overrides need iOS 17") }
        let (window, content) = try makeContentWindow()
        window.traitOverrides.preferredContentSizeCategory = .small
        let ownSize = window.traitOverrides.contains(UITraitPreferredContentSizeCategory.self)
            ? window.traitOverrides.preferredContentSizeCategory : nil
        let hadOwnClass = window.traitOverrides.contains(UITraitHorizontalSizeClass.self)

        window.traitOverrides.preferredContentSizeCategory = .accessibilityLarge
        window.traitOverrides.horizontalSizeClass = .regular
        window.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(content.traitCollection.preferredContentSizeCategory, .accessibilityLarge)
        XCTAssertEqual(content.traitCollection.horizontalSizeClass, .regular)

        if let ownSize { window.traitOverrides.preferredContentSizeCategory = ownSize }
        if !hadOwnClass { window.traitOverrides.remove(UITraitHorizontalSizeClass.self) }
        window.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        XCTAssertEqual(content.traitCollection.preferredContentSizeCategory, .small)
        XCTAssertFalse(window.traitOverrides.contains(UITraitHorizontalSizeClass.self))
        XCTAssertEqual(content.traitCollection.horizontalSizeClass, .compact)
    }

    /// Overriding the content size category changes a font that follows Dynamic Type.
    func test_S_ENV_02_H2_contentSizeOverrideChangesScalableFonts() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("trait overrides need iOS 17") }
        let (window, content) = try makeContentWindow()
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        content.addSubview(label)
        window.layoutIfNeeded()
        let before = label.font.pointSize

        window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
        window.updateTraitsIfNeeded()
        window.layoutIfNeeded()
        XCTAssertGreaterThan(label.font.pointSize, before)
    }

    // MARK: - Turns of the main run loop

    /// A block queued on the main queue from a block of the main queue runs in a later turn
    /// of the main run loop, so that each block the server queues after another is one more turn.
    func test_S_ENV_05_H9_eachBlockQueuedFromTheMainQueueRunsInALaterTurn() {
        let turns = MainRunLoopTurns()
        defer { turns.stop() }
        let seen = SeenTurns()
        let done = expectation(description: "four blocks ran")
        @Sendable func queue(_ remaining: Int) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    seen.turns.append(turns.count)
                    if remaining > 1 { queue(remaining - 1) } else { done.fulfill() }
                }
            }
        }
        queue(4)
        wait(for: [done], timeout: 5)

        print("Main run loop: the blocks ran in turns \(seen.turns)")
        XCTAssertEqual(seen.turns.count, 4)
        for (earlier, later) in zip(seen.turns, seen.turns.dropFirst()) {
            XCTAssertGreaterThan(later, earlier, "turns \(seen.turns)")
        }
    }

    // MARK: - Support

    @MainActor
    private final class SeenTurns {
        var turns: [Int] = []
    }

    /// A shown window with a root view controller, and that controller's view.
    private func makeContentWindow() throws -> (UIWindow, UIView) {
        let window = try makeWindow()
        let root = UIViewController()
        window.rootViewController = root
        window.layoutIfNeeded()
        return (window, root.view)
    }
}
