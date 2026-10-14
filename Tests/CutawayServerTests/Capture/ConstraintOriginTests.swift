import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// A layout library's constraint class: the app's.
private final class LibraryConstraint: NSLayoutConstraint {}

/// P-LAYOUT-09, P-LAYOUT-04: who made each constraint, and which guide a layout guide is.
@MainActor
final class ConstraintOriginTests: CaptureTestCase {
    private let registry = LayerRegistry()

    private func captured(_ view: UIView) -> [LayoutConstraint] {
        ConstraintCapture.constraints(of: view, registry: registry)
    }

    func test_S_LAYOUT_06_uikitsOwnConstraintsAreTheSystems() throws {
        let window = try makeWindow()
        let root = UIView(frame: window.bounds)
        window.addSubview(root)
        let label = UILabel()
        label.text = "Label"
        label.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(label)
        let framed = UIView(frame: CGRect(x: 10, y: 300, width: 40, height: 40))
        root.addSubview(framed)
        let arranged = [UILabel(), UILabel()]
        let stack = UIStackView(arrangedSubviews: arranged)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        let anchored = label.leadingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.leadingAnchor, constant: 10)
        let library = LibraryConstraint(
            item: stack,
            attribute: .top,
            relatedBy: .equal,
            toItem: framed,
            attribute: .bottom,
            multiplier: 1,
            constant: 8
        )
        NSLayoutConstraint.activate([
            anchored,
            label.topAnchor.constraint(equalTo: root.layoutMarginsGuide.topAnchor),
            library,
            stack.leadingAnchor.constraint(equalTo: root.readableContentGuide.leadingAnchor)
        ])
        window.layoutIfNeeded()

        func origin(of constraint: NSLayoutConstraint, in view: UIView) throws -> Origin {
            try XCTUnwrap(captured(view).first { $0.id == registry.register(constraint) }).origin
        }
        // The app's, made with anchors (a private class of UIKit's) or with a class of its own.
        XCTAssertEqual(try origin(of: anchored, in: label), .app)
        XCTAssertEqual(try origin(of: library, in: stack), .app)

        // UIKit's: from an autoresizing mask, a stack view's arrangement, a label's content size,
        // and the guides' own.
        let all = [root, label, framed, stack] + arranged
        let constraints = all.flatMap { captured($0) }
        for constraint in constraints {
            XCTAssertNotEqual(constraint.origin, .unknown, "\(constraint)")
        }
        let system = constraints.filter { $0.origin == .system }
        XCTAssertTrue(system.contains { $0.className == "NSAutoresizingMaskLayoutConstraint" })
        XCTAssertTrue(system.contains { $0.identifier?.hasPrefix("UISV-") == true })
        XCTAssertTrue(system.contains { $0.identifier?.hasPrefix("UIViewSafeAreaLayoutGuide-") == true })
        XCTAssertTrue(system.contains { $0.identifier?.hasPrefix("UIView-") == true })
        for constraint in constraints where constraint.className == "NSAutoresizingMaskLayoutConstraint"
            || constraint.className == "NSContentSizeLayoutConstraint"
            || constraint.identifier?.hasPrefix("UISV-") == true {
            XCTAssertEqual(constraint.origin, .system, "\(constraint)")
        }
    }

    func test_S_LAYOUT_06_guidesAreKnownByTheirOwnClassAndIdentifier() throws {
        let window = try makeWindow()
        let owner = UIView(frame: window.bounds)
        window.addSubview(owner)
        let follower = UIView()
        follower.translatesAutoresizingMaskIntoConstraints = false
        owner.addSubview(follower)
        let own = UILayoutGuide()
        own.identifier = "test.guide"
        owner.addLayoutGuide(own)
        let guides: [(UILayoutGuide, LayoutGuideKind)] = [
            (owner.safeAreaLayoutGuide, .safeArea),
            (owner.layoutMarginsGuide, .layoutMargins),
            (owner.readableContentGuide, .readableContent),
            (owner.keyboardLayoutGuide, .keyboard),
            (own, .other)
        ]
        NSLayoutConstraint.activate(guides.map { follower.topAnchor.constraint(greaterThanOrEqualTo: $0.0.topAnchor) })
        window.layoutIfNeeded()

        let items = captured(follower).compactMap(\.secondItem).filter { $0.kind == .layoutGuide }
        for (guide, kind) in guides {
            let item = try XCTUnwrap(items.first { $0.guideID == registry.register(guide) }, "\(kind)")
            XCTAssertEqual(item.guideKind, kind, guide.identifier)
            XCTAssertEqual(ConstraintCapture.kind(of: guide), kind)
        }
        // Other items have no kind.
        for constraint in captured(follower) {
            for item in [constraint.firstItem, constraint.secondItem].compactMap({ $0 })
                where item.kind != .layoutGuide {
                XCTAssertEqual(item.guideKind, .unknown)
            }
        }
    }

    func test_S_LAYOUT_06_theOwnersGuidesAreNotMadeByTheCapture() throws {
        let window = try makeWindow()
        let owner = UIView(frame: window.bounds)
        window.addSubview(owner)
        let follower = UIView()
        follower.translatesAutoresizingMaskIntoConstraints = false
        owner.addSubview(follower)
        let own = UILayoutGuide()
        owner.addLayoutGuide(own)
        follower.topAnchor.constraint(equalTo: own.topAnchor).isActive = true

        let before = owner.layoutGuides.count
        XCTAssertEqual(captured(follower).compactMap(\.secondItem).first?.guideKind, .other)
        _ = captured(owner)
        // Reading `safeAreaLayoutGuide` and the like would have added guides to the owner.
        XCTAssertEqual(owner.layoutGuides.count, before)
    }
}
