import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Counts its layout passes and constraint updates.
private final class StatusCountingView: UIView {
    var layouts = 0
    var constraintUpdates = 0

    override func layoutSubviews() {
        layouts += 1
        super.layoutSubviews()
    }

    override func updateConstraints() {
        constraintUpdates += 1
        super.updateConstraints()
    }
}

/// A view whose alignment rectangle is smaller than its frame.
private final class InsetAlignmentView: UIView {
    override var alignmentRectInsets: UIEdgeInsets { UIEdgeInsets(top: 2, left: 3, bottom: 4, right: 5) }
}

/// Whether a constraint holds (S-LAYOUT-04). No server, no connection.
///
/// A scene that Auto Layout has solved holds every required constraint that conflicts with
/// none, so each of those must be judged satisfied: one that is not shows that the check
/// measures differently from Auto Layout.
final class ConstraintCheckTests: CaptureTestCase {
    private func status(_ constraint: NSLayoutConstraint, scale: CGFloat = 3) -> ConstraintStatus {
        ConstraintCheck.status(of: constraint, screenScale: scale)
    }

    private func assertStatus(
        _ expected: ConstraintStatus,
        _ constraints: [NSLayoutConstraint],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for constraint in constraints {
            XCTAssertEqual(status(constraint), expected, "\(constraint)", file: file, line: line)
        }
    }

    /// A window with a root view that fills it, with margins of its own.
    private func makeRoot<Root: UIView>(_ type: Root.Type = UIView.self) throws -> (UIWindow, Root) {
        let window = try makeWindow()
        let root = Root(frame: window.bounds)
        root.insetsLayoutMarginsFromSafeArea = false
        root.layoutMargins = UIEdgeInsets(top: 7, left: 9, bottom: 11, right: 13)
        window.addSubview(root)
        return (window, root)
    }

    private func add<View: UIView>(_ view: View, to parent: UIView) -> View {
        view.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(view)
        return view
    }

    /// The constraints the scene of `heldConstraintsAreSatisfied` is made of.
    private func heldScene(in root: UIView) -> [NSLayoutConstraint] {
        let edgeView = add(UIView(), to: root)
        let siblingView = add(UIView(), to: root)
        let cornerView = add(UIView(), to: root)
        let marginView = add(UIView(), to: root)
        marginView.insetsLayoutMarginsFromSafeArea = false
        marginView.layoutMargins = UIEdgeInsets(top: 4, left: 5, bottom: 6, right: 7)
        let centeredView = add(UIView(), to: root)
        // Margins smaller than the view (see marginsLargerThanTheViewDoNotHold).
        centeredView.insetsLayoutMarginsFromSafeArea = false
        centeredView.layoutMargins = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        let guide = UILayoutGuide()
        root.addLayoutGuide(guide)
        let guidedView = add(UIView(), to: root)
        let outer = add(UIView(), to: root)
        let inner = add(UIView(), to: outer)
        let siblingHeight = siblingView.heightAnchor.constraint(equalToConstant: 40)
        siblingHeight.priority = UILayoutPriority(500)
        let constraints = [
            // Edges, against the parent and its safe area.
            edgeView.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 10),
            edgeView.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 20),
            edgeView.widthAnchor.constraint(equalToConstant: 50),
            edgeView.heightAnchor.constraint(equalToConstant: 30),
            // A sibling, a multiplier, inequalities.
            siblingView.leadingAnchor.constraint(equalTo: edgeView.trailingAnchor, constant: 8),
            siblingView.centerYAnchor.constraint(equalTo: edgeView.centerYAnchor),
            siblingView.widthAnchor.constraint(equalTo: edgeView.widthAnchor, multiplier: 1.5, constant: 2),
            siblingView.heightAnchor.constraint(lessThanOrEqualToConstant: 100),
            siblingView.heightAnchor.constraint(greaterThanOrEqualTo: edgeView.heightAnchor),
            siblingHeight,
            // The right and bottom edges.
            cornerView.rightAnchor.constraint(equalTo: root.rightAnchor, constant: -12),
            cornerView.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            cornerView.widthAnchor.constraint(equalToConstant: 40),
            cornerView.heightAnchor.constraint(equalToConstant: 40),
            // Margins: of the parent through its guide and its own attributes, and of the view.
            marginView.leadingAnchor.constraint(equalTo: root.layoutMarginsGuide.leadingAnchor),
            NSLayoutConstraint(
                item: marginView,
                attribute: .top,
                relatedBy: .equal,
                toItem: root,
                attribute: .topMargin,
                multiplier: 1,
                constant: 100
            ),
            NSLayoutConstraint(
                item: marginView,
                attribute: .trailingMargin,
                relatedBy: .equal,
                toItem: root,
                attribute: .trailingMargin,
                multiplier: 1,
                constant: 0
            ),
            marginView.heightAnchor.constraint(equalToConstant: 20),
            // Centres, also within margins, and a multiplier on a size.
            centeredView.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            NSLayoutConstraint(
                item: centeredView,
                attribute: .centerYWithinMargins,
                relatedBy: .equal,
                toItem: root,
                attribute: .centerYWithinMargins,
                multiplier: 1,
                constant: 0
            ),
            centeredView.widthAnchor.constraint(equalTo: root.widthAnchor, multiplier: 0.25),
            centeredView.heightAnchor.constraint(equalToConstant: 10),
            // A guide of the view's own, and a view placed against it.
            guide.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 30),
            guide.topAnchor.constraint(equalTo: edgeView.bottomAnchor, constant: 5),
            guide.widthAnchor.constraint(equalToConstant: 60),
            guide.heightAnchor.constraint(equalToConstant: 10),
            guidedView.leadingAnchor.constraint(equalTo: guide.trailingAnchor),
            guidedView.topAnchor.constraint(equalTo: guide.bottomAnchor),
            guidedView.widthAnchor.constraint(equalToConstant: 10),
            guidedView.heightAnchor.constraint(equalToConstant: 10),
            // Two levels down, and across the levels.
            outer.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 40),
            outer.topAnchor.constraint(equalTo: root.topAnchor, constant: 300),
            outer.widthAnchor.constraint(equalToConstant: 100),
            outer.heightAnchor.constraint(equalToConstant: 100),
            inner.leadingAnchor.constraint(equalTo: outer.leadingAnchor, constant: 5),
            inner.topAnchor.constraint(equalTo: outer.topAnchor, constant: 6),
            inner.leftAnchor.constraint(equalTo: edgeView.leftAnchor, constant: 35),
            inner.widthAnchor.constraint(equalToConstant: 10),
            inner.heightAnchor.constraint(equalToConstant: 10)
        ]
        NSLayoutConstraint.activate(constraints)
        return constraints
    }

    /// Every constraint held by `view` and the views under it.
    private func allConstraints(under view: UIView) -> [NSLayoutConstraint] {
        view.constraints + view.subviews.flatMap(allConstraints(under:))
    }

    // MARK: - S-LAYOUT-04, Auto Layout's geometry

    func test_S_LAYOUT_04_heldConstraintsAreSatisfied() throws {
        let (window, root) = try makeRoot()
        let constraints = heldScene(in: root)
        window.layoutIfNeeded()
        assertStatus(.satisfied, constraints)
        // UIKit's own constraints in the scene, such as those of the guides, are not misjudged.
        for constraint in allConstraints(under: window) {
            XCTAssertNotEqual(status(constraint), .unsatisfied, "\(constraint)")
        }
    }

    func test_S_LAYOUT_04_transformsDoNotCount() throws {
        let (window, root) = try makeRoot()
        let label = add(UILabel(), to: root)
        label.text = "Title"
        let card = add(UIView(), to: root)
        let child = add(UIView(), to: card)
        // Anchored at its top left corner instead of its centre.
        let anchored = add(UIView(), to: root)
        anchored.layer.anchorPoint = .zero
        let constraints = [
            label.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 20),
            label.topAnchor.constraint(equalTo: root.topAnchor, constant: 60),
            card.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 78),
            card.widthAnchor.constraint(equalToConstant: 300),
            card.heightAnchor.constraint(equalToConstant: 180),
            card.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            child.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
            child.topAnchor.constraint(equalTo: card.topAnchor, constant: 10),
            child.widthAnchor.constraint(equalToConstant: 30),
            child.heightAnchor.constraint(equalToConstant: 30),
            anchored.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 20),
            anchored.topAnchor.constraint(equalTo: root.topAnchor, constant: 400),
            anchored.widthAnchor.constraint(equalToConstant: 30),
            anchored.heightAnchor.constraint(equalToConstant: 30)
        ]
        NSLayoutConstraint.activate(constraints)
        card.transform = CGAffineTransform(rotationAngle: .pi / 6)
        window.layoutIfNeeded()
        XCTAssertNotEqual(card.frame.width, 300, accuracy: 1, "the card is turned")
        assertStatus(.satisfied, constraints)
    }

    func test_S_LAYOUT_04_alignmentRectsCount() throws {
        let (window, root) = try makeRoot()
        let inset = add(InsetAlignmentView(), to: root)
        inset.insetsLayoutMarginsFromSafeArea = false
        inset.layoutMargins = UIEdgeInsets(top: 1, left: 1, bottom: 1, right: 1)
        let next = add(UIView(), to: root)
        let onMargin = add(UIView(), to: root)
        let constraints = [
            inset.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 20),
            inset.topAnchor.constraint(equalTo: root.topAnchor, constant: 200),
            inset.widthAnchor.constraint(equalToConstant: 50),
            inset.heightAnchor.constraint(equalToConstant: 50),
            next.leftAnchor.constraint(equalTo: inset.rightAnchor, constant: 4),
            next.topAnchor.constraint(equalTo: inset.bottomAnchor),
            next.widthAnchor.constraint(equalToConstant: 10),
            next.heightAnchor.constraint(equalToConstant: 10),
            // Tells apart a margin taken from the frame and one taken from the alignment rectangle.
            NSLayoutConstraint(
                item: onMargin,
                attribute: .left,
                relatedBy: .equal,
                toItem: inset,
                attribute: .leftMargin,
                multiplier: 1,
                constant: 0
            ),
            onMargin.topAnchor.constraint(equalTo: root.topAnchor, constant: 300),
            onMargin.widthAnchor.constraint(equalToConstant: 10),
            onMargin.heightAnchor.constraint(equalToConstant: 10)
        ]
        NSLayoutConstraint.activate(constraints)
        window.layoutIfNeeded()
        // The frame is larger than the alignment rectangle the constraints place.
        XCTAssertEqual(inset.frame, CGRect(x: 17, y: 198, width: 58, height: 56))
        // Margins are taken from the alignment rectangle: 20 + 1, not 17 + 1.
        XCTAssertEqual(onMargin.frame.minX, 21)
        assertStatus(.satisfied, constraints)
    }

    func test_S_LAYOUT_04_scrollViewGuides() throws {
        let (window, root) = try makeRoot()
        let scrollView = UIScrollView(frame: CGRect(x: 20, y: 100, width: 200, height: 200))
        root.addSubview(scrollView)
        let content = add(UIView(), to: scrollView)
        let overlay = add(UIView(), to: scrollView)
        let legacy = add(UIView(), to: scrollView)
        // Inside the scrolled scroll view, placed against a view outside it: the scroll offset
        // is part of the way between them.
        let header = add(UIView(), to: root)
        let pinned = add(UIView(), to: scrollView)
        let throughGuides = [
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: 200),
            content.heightAnchor.constraint(equalToConstant: 600),
            overlay.topAnchor.constraint(equalTo: scrollView.frameLayoutGuide.topAnchor, constant: 10),
            overlay.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 10),
            overlay.widthAnchor.constraint(equalToConstant: 20),
            overlay.heightAnchor.constraint(equalToConstant: 20),
            legacy.widthAnchor.constraint(equalToConstant: 20),
            legacy.heightAnchor.constraint(equalToConstant: 20),
            header.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 20),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 40),
            header.widthAnchor.constraint(equalToConstant: 20),
            header.heightAnchor.constraint(equalToConstant: 20),
            pinned.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 70),
            pinned.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 50),
            pinned.widthAnchor.constraint(equalToConstant: 20),
            pinned.heightAnchor.constraint(equalToConstant: 20)
        ]
        // The scroll view's own edges, against a view inside it.
        let toScrollViewEdges = [
            legacy.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 5),
            legacy.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 5)
        ]
        NSLayoutConstraint.activate(throughGuides + toScrollViewEdges)
        window.layoutIfNeeded()
        scrollView.contentOffset = CGPoint(x: 0, y: 100)
        window.layoutIfNeeded()
        XCTAssertEqual(scrollView.bounds.origin.y, 100, "the scroll view is scrolled")
        // 40 + 20 + 70 in the root is 30 below the scroll view's top, plus the offset of 100.
        XCTAssertEqual(pinned.frame.minY, 130, accuracy: 0.01)
        assertStatus(.satisfied, throughGuides)
        assertStatus(.unknown, toScrollViewEdges)
    }

    // MARK: - Layout direction

    func test_S_LAYOUT_04_rightToLeft() throws {
        let (window, root) = try makeRoot()
        let container = add(UIView(), to: root)
        let first = add(UIView(), to: container)
        let second = add(UIView(), to: container)
        let leftToRight = add(UIView(), to: container)
        for view in [container, first, second] { view.semanticContentAttribute = .forceRightToLeft }
        leftToRight.semanticContentAttribute = .forceLeftToRight
        let rightToLeft = [
            container.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 20),
            container.topAnchor.constraint(equalTo: root.topAnchor, constant: 100),
            container.widthAnchor.constraint(equalToConstant: 200),
            container.heightAnchor.constraint(equalToConstant: 100),
            first.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            first.topAnchor.constraint(equalTo: container.topAnchor),
            first.widthAnchor.constraint(equalToConstant: 30),
            first.heightAnchor.constraint(equalToConstant: 30),
            second.leadingAnchor.constraint(equalTo: first.trailingAnchor, constant: 5),
            second.topAnchor.constraint(equalTo: container.topAnchor),
            second.widthAnchor.constraint(equalToConstant: 30),
            second.heightAnchor.constraint(equalToConstant: 30)
        ]
        // One end left to right, the other right to left.
        let mixed = leftToRight.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10)
        let mixedRest = [
            leftToRight.topAnchor.constraint(equalTo: container.topAnchor, constant: 50),
            leftToRight.widthAnchor.constraint(equalToConstant: 30),
            leftToRight.heightAnchor.constraint(equalToConstant: 30)
        ]
        // A right-to-left view in the right-to-left container, placed against a left-to-right
        // view outside it: their nearest common ancestor, the root, is left to right.
        let outside = add(UIView(), to: root)
        outside.semanticContentAttribute = .forceLeftToRight
        let inside = add(UIView(), to: container)
        inside.semanticContentAttribute = .forceRightToLeft
        let across = inside.leadingAnchor.constraint(equalTo: outside.trailingAnchor, constant: 5)
        let acrossRest = [
            outside.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 10),
            outside.topAnchor.constraint(equalTo: root.topAnchor, constant: 300),
            outside.widthAnchor.constraint(equalToConstant: 30),
            outside.heightAnchor.constraint(equalToConstant: 30),
            inside.topAnchor.constraint(equalTo: container.topAnchor, constant: 70),
            inside.widthAnchor.constraint(equalToConstant: 30),
            inside.heightAnchor.constraint(equalToConstant: 30)
        ]
        NSLayoutConstraint.activate(rightToLeft + [mixed] + mixedRest + [across] + acrossRest)
        window.layoutIfNeeded()
        XCTAssertEqual(first.effectiveUserInterfaceLayoutDirection, .rightToLeft)
        // Right to left, the leading edge is the right one.
        XCTAssertEqual(first.frame.maxX, 190, accuracy: 0.01)
        // The direction is the nearest common ancestor's, not the items' own. The
        // left-to-right view is placed from the right of its right-to-left container...
        XCTAssertEqual(leftToRight.effectiveUserInterfaceLayoutDirection, .leftToRight)
        XCTAssertEqual(leftToRight.frame.maxX, 190, accuracy: 0.01)
        // ...and the right-to-left view follows the left-to-right root: its left edge is 5
        // after the outside view's right edge, at 45 in the root.
        XCTAssertEqual(inside.convert(inside.bounds, to: root).minX, 45, accuracy: 0.01)
        assertStatus(.satisfied, rightToLeft + [mixed] + mixedRest + [across] + acrossRest)
    }

    /// A view smaller than its layout margins: UIKit reports its margins guide with the size
    /// made positive, so the guide's own top and bottom constraints do not hold as reported.
    func test_S_LAYOUT_04_marginsLargerThanTheViewDoNotHold() throws {
        let (window, root) = try makeRoot()
        let small = add(UIView(), to: root)
        let place = [
            small.leftAnchor.constraint(equalTo: root.leftAnchor),
            small.topAnchor.constraint(equalTo: root.topAnchor, constant: 400),
            small.widthAnchor.constraint(equalToConstant: 40),
            small.heightAnchor.constraint(equalToConstant: 10)
        ]
        NSLayoutConstraint.activate(place)
        // Default margins of 8 on a view 10 high.
        let guide = small.layoutMarginsGuide
        // A view placed at the small view's top margin: the margin counts from the top even
        // though the margins are larger than the view.
        let atMargin = add(UIView(), to: root)
        let marginEdge = NSLayoutConstraint(
            item: atMargin,
            attribute: .top,
            relatedBy: .equal,
            toItem: small,
            attribute: .topMargin,
            multiplier: 1,
            constant: 0
        )
        let atMarginRest = [
            atMargin.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 100),
            atMargin.widthAnchor.constraint(equalToConstant: 10),
            atMargin.heightAnchor.constraint(equalToConstant: 10)
        ]
        NSLayoutConstraint.activate([marginEdge] + atMarginRest)
        window.layoutIfNeeded()
        XCTAssertEqual(atMargin.frame.minY, 408, accuracy: 0.01)
        assertStatus(.satisfied, [marginEdge] + atMarginRest)
        XCTAssertEqual(guide.layoutFrame, CGRect(x: 8, y: 2, width: 24, height: 6))
        let guideConstraints = small.constraints.filter {
            $0.firstItem === guide || $0.secondItem === guide
        }
        let vertical = guideConstraints.filter {
            [.top, .bottom].contains($0.firstAttribute) || [.top, .bottom].contains($0.secondAttribute)
        }
        XCTAssertEqual(vertical.count, 2)
        assertStatus(.unsatisfied, vertical)
        assertStatus(.satisfied, guideConstraints.filter { !vertical.contains($0) } + place)
    }

    // MARK: - Constraints that do not hold

    func test_S_LAYOUT_04_losingOptionalConstraintIsUnsatisfied() throws {
        let (window, root) = try makeRoot()
        let view = add(UIView(), to: root)
        let wish = view.widthAnchor.constraint(equalToConstant: 240)
        wish.priority = UILayoutPriority(250)
        let limit = view.widthAnchor.constraint(lessThanOrEqualToConstant: 200)
        let place = [
            view.leftAnchor.constraint(equalTo: root.leftAnchor),
            view.topAnchor.constraint(equalTo: root.topAnchor),
            view.heightAnchor.constraint(equalToConstant: 10)
        ]
        NSLayoutConstraint.activate([wish, limit] + place)
        window.layoutIfNeeded()
        XCTAssertEqual(view.frame.width, 200, accuracy: 0.01)
        XCTAssertEqual(status(wish), .unsatisfied)
        assertStatus(.satisfied, [limit] + place)
    }

    /// UIKit's constraints for intrinsic sizes take part like any other: a label stretched
    /// past its text's width does not hold its hugging.
    func test_S_LAYOUT_04_contentSizeConstraints() throws {
        let (window, root) = try makeRoot()
        let natural = add(UILabel(), to: root)
        natural.text = "Natural"
        let stretched = add(UILabel(), to: root)
        stretched.text = "Stretched"
        NSLayoutConstraint.activate([
            natural.leftAnchor.constraint(equalTo: root.leftAnchor),
            natural.topAnchor.constraint(equalTo: root.topAnchor, constant: 100),
            stretched.leftAnchor.constraint(equalTo: root.leftAnchor),
            stretched.topAnchor.constraint(equalTo: root.topAnchor, constant: 200),
            stretched.widthAnchor.constraint(equalToConstant: 200)
        ])
        window.layoutIfNeeded()
        func contentWidth(_ label: UILabel) throws -> NSLayoutConstraint {
            try XCTUnwrap(
                label.constraints.first {
                    NSStringFromClass(type(of: $0)) == "NSContentSizeLayoutConstraint" && $0.firstAttribute == .width
                }
            )
        }
        XCTAssertEqual(status(try contentWidth(natural)), .satisfied)
        XCTAssertEqual(status(try contentWidth(stretched)), .unsatisfied)
    }

    /// A required constraint that UIKit gave up on in a conflict stays active.
    func test_S_LAYOUT_04_brokenRequiredConstraintIsUnsatisfied() throws {
        let (window, root) = try makeRoot()
        let view = add(UIView(), to: root)
        let narrow = view.widthAnchor.constraint(equalToConstant: 100)
        let wide = view.widthAnchor.constraint(equalToConstant: 200)
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: root.leftAnchor),
            view.topAnchor.constraint(equalTo: root.topAnchor),
            view.heightAnchor.constraint(equalToConstant: 10),
            narrow,
            wide
        ])
        // UIKit logs that it cannot satisfy both, and gives one of them up.
        window.layoutIfNeeded()
        XCTAssertTrue(narrow.isActive && wide.isActive, "a constraint given up stays active")
        XCTAssertTrue(view.constraints.contains(narrow) && view.constraints.contains(wide))
        XCTAssertEqual(Set([status(narrow), status(wide)]), [.satisfied, .unsatisfied])
    }

    // MARK: - What cannot be judged

    func test_S_LAYOUT_04_baselinesAndOtherItemsAreUnknown() throws {
        let (window, root) = try makeRoot()
        let upper = add(UILabel(), to: root)
        upper.text = "Upper"
        let lower = add(UILabel(), to: root)
        lower.text = "Lower"
        let baseline = lower.firstBaselineAnchor.constraint(equalTo: upper.lastBaselineAnchor, constant: 10)
        NSLayoutConstraint.activate([
            upper.leftAnchor.constraint(equalTo: root.leftAnchor),
            upper.topAnchor.constraint(equalTo: root.topAnchor, constant: 50),
            lower.leftAnchor.constraint(equalTo: root.leftAnchor),
            baseline
        ])
        window.layoutIfNeeded()
        XCTAssertEqual(status(baseline), .unknown)
        // A guide that no view owns. Held here: a constraint does not keep its items alive.
        let unownedGuide = UILayoutGuide()
        let unowned = unownedGuide.widthAnchor.constraint(equalToConstant: 10)
        XCTAssertEqual(status(unowned), .unknown)
        // Views in two different windows have no common ancestor.
        let elsewhere = try makeWindow()
        let away = UIView()
        elsewhere.addSubview(away)
        let apart = upper.leftAnchor.constraint(equalTo: away.leftAnchor)
        XCTAssertEqual(status(apart), .unknown)
    }

    // MARK: - Tolerance and timing

    func test_S_LAYOUT_04_toleranceIsHalfAPixelAtTheScreenScale() throws {
        // At 2 pixels per point, half a pixel is 0.25 points.
        let tolerance = 0.5 / 2
        XCTAssertTrue(ConstraintCheck.holds(10, .equal, 10.25, tolerance: tolerance))
        XCTAssertTrue(ConstraintCheck.holds(10.25, .equal, 10, tolerance: tolerance))
        XCTAssertFalse(ConstraintCheck.holds(10, .equal, 10.26, tolerance: tolerance))
        XCTAssertTrue(ConstraintCheck.holds(10.25, .lessThanOrEqual, 10, tolerance: tolerance))
        XCTAssertFalse(ConstraintCheck.holds(10.26, .lessThanOrEqual, 10, tolerance: tolerance))
        XCTAssertTrue(ConstraintCheck.holds(-100, .lessThanOrEqual, 10, tolerance: tolerance))
        XCTAssertTrue(ConstraintCheck.holds(9.75, .greaterThanOrEqual, 10, tolerance: tolerance))
        XCTAssertFalse(ConstraintCheck.holds(9.74, .greaterThanOrEqual, 10, tolerance: tolerance))
        XCTAssertTrue(ConstraintCheck.holds(100, .greaterThanOrEqual, 10, tolerance: tolerance))

        let (window, root) = try makeRoot()
        let view = add(UIView(), to: root)
        let width = view.widthAnchor.constraint(equalToConstant: 50)
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: root.leftAnchor),
            view.topAnchor.constraint(equalTo: root.topAnchor),
            view.heightAnchor.constraint(equalToConstant: 10),
            width
        ])
        window.layoutIfNeeded()
        // 0.3 points off without a layout: within half a pixel at 1x, not at 3x.
        width.constant = 50.3
        XCTAssertEqual(status(width, scale: 1), .satisfied)
        XCTAssertEqual(status(width, scale: 3), .unsatisfied)
    }

    func test_S_LAYOUT_04_layoutIsNotForced() throws {
        let (window, root) = try makeRoot()
        let view = add(UIView(), to: root)
        let width = view.widthAnchor.constraint(equalToConstant: 50)
        NSLayoutConstraint.activate([
            view.leftAnchor.constraint(equalTo: root.leftAnchor),
            view.topAnchor.constraint(equalTo: root.topAnchor),
            view.heightAnchor.constraint(equalToConstant: 10),
            width
        ])
        window.layoutIfNeeded()
        XCTAssertEqual(status(width), .satisfied)

        width.constant = 80
        XCTAssertTrue(root.layer.needsLayout() || window.layer.needsLayout(), "the change waits for a layout")
        XCTAssertEqual(status(width), .unsatisfied, "judged against the layout as it is")
        XCTAssertEqual(view.frame.width, 50, "judging did not lay the view out")
        XCTAssertTrue(root.layer.needsLayout() || window.layer.needsLayout(), "the layout is still pending")
        window.layoutIfNeeded()
        XCTAssertEqual(status(width), .satisfied)
    }

    /// Reading `directionalLayoutMargins` and `alignmentRectInsets` does not lay out.
    func test_S_LAYOUT_04_judgingDoesNotLayOut() throws {
        let (window, root) = try makeRoot(StatusCountingView.self)
        let constraints = heldScene(in: root)
        let inset = add(InsetAlignmentView(), to: root)
        let counted = add(StatusCountingView(), to: root)
        let more = [
            inset.leftAnchor.constraint(equalTo: root.leftAnchor, constant: 20),
            inset.topAnchor.constraint(equalTo: root.topAnchor, constant: 200),
            inset.widthAnchor.constraint(equalToConstant: 50),
            inset.heightAnchor.constraint(equalToConstant: 50),
            counted.leadingAnchor.constraint(equalTo: inset.trailingAnchor),
            counted.topAnchor.constraint(equalTo: inset.topAnchor),
            counted.widthAnchor.constraint(equalToConstant: 10),
            counted.heightAnchor.constraint(equalToConstant: 10)
        ]
        NSLayoutConstraint.activate(more)
        window.layoutIfNeeded()
        let views = [root, counted]
        func counts() -> [Int] { views.flatMap { [$0.layouts, $0.constraintUpdates] } }
        let all = allConstraints(under: window)

        var before = counts()
        for constraint in all { _ = status(constraint) }
        XCTAssertEqual(counts(), before, "judging laid out or updated constraints")

        for view in [root, counted, inset] as [UIView] {
            view.setNeedsLayout()
            view.setNeedsUpdateConstraints()
        }
        before = counts()
        for constraint in all { _ = status(constraint) }
        XCTAssertEqual(counts(), before, "judging laid out or updated constraints")
        XCTAssertTrue([root, counted, inset].allSatisfy { $0.layer.needsLayout() }, "a pending layout was carried out")
        XCTAssertTrue(
            [root, counted, inset].allSatisfy { $0.needsUpdateConstraints() },
            "a pending constraint update was carried out"
        )
        _ = constraints
    }

    // MARK: - Details

    func test_S_LAYOUT_04_detailsCarryTheStatus() throws {
        let (window, root) = try makeRoot()
        let constraints = heldScene(in: root)
        window.layoutIfNeeded()
        let registry = LayerRegistry()
        let view = try XCTUnwrap(constraints.first?.firstItem as? UIView)
        let detail = try XCTUnwrap(
            DetailCapture.capture(
                LayerDetailRequest(
                    layerID: registry.register(view.layer),
                    wantSolo: false,
                    wantGroup: false,
                    wantAttributes: false,
                    wantConstraints: true
                ),
                maxTextureDimension: 0,
                in: .testing(windows: [window], registry: registry),
                stopFlag: StopFlag(),
                screenScale: 2,
                readAttributes: { _ in [] }
            )
        )
        XCTAssertFalse(detail.constraints.isEmpty)
        XCTAssertTrue(detail.constraints.allSatisfy { $0.status == .satisfied })

        // The screen scale of the request is the one the check uses.
        let width = try XCTUnwrap(view.constraints.first { $0.firstAttribute == .width && $0.secondItem == nil })
        width.constant += 0.3
        let coarse = try XCTUnwrap(
            DetailCapture.capture(
                LayerDetailRequest(
                    layerID: registry.register(view.layer),
                    wantSolo: false,
                    wantGroup: false,
                    wantAttributes: false,
                    wantConstraints: true
                ),
                maxTextureDimension: 0,
                in: .testing(windows: [window], registry: registry),
                stopFlag: StopFlag(),
                screenScale: 1,
                readAttributes: { _ in [] }
            )
        )
        let fine = try XCTUnwrap(
            DetailCapture.capture(
                LayerDetailRequest(
                    layerID: registry.register(view.layer),
                    wantSolo: false,
                    wantGroup: false,
                    wantAttributes: false,
                    wantConstraints: true
                ),
                maxTextureDimension: 0,
                in: .testing(windows: [window], registry: registry),
                stopFlag: StopFlag(),
                screenScale: 3,
                readAttributes: { _ in [] }
            )
        )
        let id = registry.register(width)
        XCTAssertEqual(coarse.constraints.first { $0.id == id }?.status, .satisfied)
        XCTAssertEqual(fine.constraints.first { $0.id == id }?.status, .unsatisfied)
    }
}
