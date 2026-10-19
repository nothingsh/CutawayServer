import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Overriding the environment on real windows of the test host (protocol 1.2; PROTOCOL.md,
/// P-ENV-01 to 05). Every test removes its overrides before it ends, so that no other window of
/// the test host gets them.
final class EnvironmentOverridesTests: CaptureTestCase {
    /// A shown window with a root view controller, and that controller's view.
    private func makeContentWindow(hidden: Bool = false) throws -> (UIWindow, UIView) {
        let window = try makeWindow(hidden: hidden)
        let root = UIViewController()
        window.rootViewController = root
        window.layoutIfNeeded()
        return (window, root.view)
    }

    // MARK: - S-ENV-01

    func test_S_ENV_01_environmentDescribesTheKeyOrFirstWindow() throws {
        let (window, _) = try makeContentWindow()
        let overrides = EnvironmentOverrides()
        let environment = overrides.environment(windows: [window])
        XCTAssertEqual(environment.overrides, .none)
        XCTAssertEqual(environment.current, EnvironmentOverrides.traits(of: window.traitCollection))
        XCTAssertNotEqual(environment.current.userInterfaceStyle, .unspecified)
        XCTAssertNotEqual(environment.current.contentSizeCategory, .unspecified)
        XCTAssertNotEqual(environment.current.layoutDirection, .unspecified)
        XCTAssertNotEqual(environment.current.horizontalSizeClass, .unspecified)
        XCTAssertNotEqual(environment.current.verticalSizeClass, .unspecified)
        XCTAssertEqual(overrides.environment(windows: []).current, .none)
        if #available(iOS 17, *) {
            XCTAssertEqual(environment.overridable, TraitKind.allCases)
        } else {
            XCTAssertEqual(environment.overridable, [.userInterfaceStyle])
        }
        XCTAssertEqual(EnvironmentOverrides(method: .styleOnly).overridable, [.userInterfaceStyle])
    }

    // MARK: - S-ENV-02

    func test_S_ENV_02_eachKindTakesEffect() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("the four kinds need iOS 17") }
        let (window, content) = try makeContentWindow()
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        let box = UIView()
        box.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(label)
        content.addSubview(box)
        NSLayoutConstraint.activate([
            box.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            box.topAnchor.constraint(equalTo: content.topAnchor, constant: 100),
            box.widthAnchor.constraint(equalToConstant: 50),
            box.heightAnchor.constraint(equalToConstant: 50)
        ])
        window.layoutIfNeeded()
        let fontSize = label.font.pointSize
        let overrides = EnvironmentOverrides()
        defer { overrides.removeAll() }

        let traits = Traits(
            userInterfaceStyle: .dark,
            contentSizeCategory: .accessibilityExtraExtraExtraLarge,
            layoutDirection: .rightToLeft,
            horizontalSizeClass: .regular,
            verticalSizeClass: .compact
        )
        overrides.replace(with: traits, windows: [window])
        XCTAssertEqual(content.traitCollection.userInterfaceStyle, .dark)
        XCTAssertGreaterThan(label.font.pointSize, fontSize)
        XCTAssertEqual(box.frame.maxX, content.bounds.width - 20, "laid out right to left, before the answer")
        XCTAssertEqual(content.traitCollection.horizontalSizeClass, .regular)
        XCTAssertEqual(content.traitCollection.verticalSizeClass, .compact)
        XCTAssertEqual(
            overrides.environment(windows: [window]),
            Environment(overrides: traits, current: traits, overridable: TraitKind.allCases)
        )
    }

    func test_S_ENV_02_replacingPutsBackWhatIsNoLongerOverridden() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("the four kinds need iOS 17") }
        let (window, content) = try makeContentWindow()
        let before = EnvironmentOverrides.traits(of: content.traitCollection)
        let overrides = EnvironmentOverrides()
        defer { overrides.removeAll() }

        overrides.replace(
            with: Traits(
                userInterfaceStyle: .dark,
                contentSizeCategory: .accessibilityLarge,
                layoutDirection: .rightToLeft
            ),
            windows: [window]
        )
        overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [window])
        var expected = before
        expected.userInterfaceStyle = .dark
        XCTAssertEqual(EnvironmentOverrides.traits(of: content.traitCollection), expected)
        XCTAssertFalse(window.traitOverrides.contains(UITraitPreferredContentSizeCategory.self))
        XCTAssertFalse(window.traitOverrides.contains(UITraitLayoutDirection.self))

        overrides.replace(with: .none, windows: [window])
        XCTAssertEqual(EnvironmentOverrides.traits(of: content.traitCollection), before)
        XCTAssertEqual(window.overrideUserInterfaceStyle, .unspecified)
    }

    func test_S_ENV_02_overridesWinOverTheAppsWindowAndScene() throws {
        let (pinned, pinnedContent) = try makeContentWindow()
        pinned.overrideUserInterfaceStyle = .light
        let (plain, plainContent) = try makeContentWindow()
        let scene = try hostScene()
        if #available(iOS 17, *) {
            scene.traitOverrides.userInterfaceStyle = .light
        }
        defer {
            if #available(iOS 17, *) { scene.traitOverrides.remove(UITraitUserInterfaceStyle.self) }
        }
        let overrides = EnvironmentOverrides()
        defer { overrides.removeAll() }

        overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [pinned, plain])
        XCTAssertEqual(pinnedContent.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(plainContent.traitCollection.userInterfaceStyle, .dark)
    }

    func test_S_ENV_02_aViewControllersOwnValueStillWins() throws {
        let (window, _) = try makeContentWindow()
        let root = try XCTUnwrap(window.rootViewController)
        let child = UIViewController()
        child.overrideUserInterfaceStyle = .light
        root.addChild(child)
        root.view.addSubview(child.view)
        child.didMove(toParent: root)
        let overrides = EnvironmentOverrides()
        defer { overrides.removeAll() }

        overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [window])
        XCTAssertEqual(root.view.traitCollection.userInterfaceStyle, .dark)
        XCTAssertEqual(child.view.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(child.overrideUserInterfaceStyle, .light, "not touched (P-ENV-05)")
    }

    func test_S_ENV_02_aWindowThatAppearsLaterIsOverriddenToo() async throws {
        let (window, _) = try makeContentWindow()
        let (later, laterContent) = try makeContentWindow(hidden: true)
        let overrides = EnvironmentOverrides()
        defer { overrides.removeAll() }

        overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [window])
        XCTAssertEqual(later.overrideUserInterfaceStyle, .unspecified)
        later.isHidden = false
        await drain(.main)
        XCTAssertEqual(later.overrideUserInterfaceStyle, .dark)
        XCTAssertEqual(laterContent.traitCollection.userInterfaceStyle, .dark)

        overrides.removeAll()
        XCTAssertEqual(later.overrideUserInterfaceStyle, .unspecified, "put back with the others")
    }

    func test_S_ENV_02_noImplicitAnimations() throws {
        let (window, content) = try makeContentWindow()
        let colored = UIView(frame: CGRect(x: 0, y: 0, width: 50, height: 50))
        colored.backgroundColor = .systemBackground
        content.addSubview(colored)
        window.layoutIfNeeded()
        CATransaction.flush()
        let overrides = EnvironmentOverrides()
        defer { overrides.removeAll() }

        overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [window])
        for layer in [window.layer, content.layer, colored.layer] {
            XCTAssertNil(layer.animationKeys(), "\(layer)")
        }
    }

    func test_S_ENV_02_beforeIOS17OnlyTheAppearance() throws {
        let (window, content) = try makeContentWindow()
        let overrides = EnvironmentOverrides(method: .styleOnly)
        defer { overrides.removeAll() }
        XCTAssertEqual(overrides.overridable, [.userInterfaceStyle])
        XCTAssertNotNil(
            EnvironmentOverrides.refusal(of: Traits(layoutDirection: .rightToLeft), overridable: overrides.overridable)
        )

        overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [window])
        XCTAssertEqual(content.traitCollection.userInterfaceStyle, .dark)
        if #available(iOS 17, *) {
            XCTAssertFalse(window.traitOverrides.contains(UITraitLayoutDirection.self))
        }
    }

    // MARK: - S-ENV-03

    func test_S_ENV_03_removingPutsBackTheAppsOwnValues() throws {
        guard #available(iOS 17, *) else { throw XCTSkip("the four kinds need iOS 17") }
        let (pinned, pinnedContent) = try makeContentWindow()
        pinned.overrideUserInterfaceStyle = .light
        pinned.traitOverrides.preferredContentSizeCategory = .small
        let (plain, plainContent) = try makeContentWindow()
        let plainBefore = EnvironmentOverrides.traits(of: plainContent.traitCollection)
        let overrides = EnvironmentOverrides()

        overrides.replace(
            with: Traits(
                userInterfaceStyle: .dark,
                contentSizeCategory: .accessibilityLarge,
                horizontalSizeClass: .regular
            ),
            windows: [pinned, plain]
        )
        XCTAssertEqual(pinnedContent.traitCollection.preferredContentSizeCategory, .accessibilityLarge)
        overrides.removeAll()

        XCTAssertEqual(pinned.overrideUserInterfaceStyle, .light)
        XCTAssertEqual(pinned.traitOverrides.preferredContentSizeCategory, .small)
        XCTAssertFalse(pinned.traitOverrides.contains(UITraitHorizontalSizeClass.self))
        XCTAssertEqual(pinnedContent.traitCollection.userInterfaceStyle, .light)
        XCTAssertEqual(plain.overrideUserInterfaceStyle, .unspecified)
        XCTAssertFalse(plain.traitOverrides.contains(UITraitPreferredContentSizeCategory.self))
        XCTAssertEqual(EnvironmentOverrides.traits(of: plainContent.traitCollection), plainBefore)
        XCTAssertEqual(overrides.overrides, .none)
    }

    /// S-D-176: what the app sets itself while it is overridden is not kept.
    func test_S_ENV_03_theValueRecordedFirstIsPutBack() throws {
        let (window, _) = try makeContentWindow()
        window.overrideUserInterfaceStyle = .light
        let overrides = EnvironmentOverrides()
        overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [window])
        overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [window])
        window.overrideUserInterfaceStyle = .unspecified

        overrides.removeAll()
        XCTAssertEqual(window.overrideUserInterfaceStyle, .light)
    }

    func test_S_ENV_03_windowsAreHeldWeakly() throws {
        let overrides = EnvironmentOverrides()
        weak var released: UIWindow?
        do {
            let window = makeDetachedWindow()
            released = window
            overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [window])
        }
        CATransaction.flush()
        XCTAssertNil(released)
        overrides.removeAll()
    }
}
