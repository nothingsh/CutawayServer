import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Counts its layout passes and constraint updates.
private final class LayoutCountingView: UIView {
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

/// Finding a view's constraints, and what is sent for them
/// (S-LAYOUT-01 to S-LAYOUT-03). No server, no connection.
final class ConstraintCaptureTests: CaptureTestCase {
    private let registry = LayerRegistry()

    /// The scene of S-LAYOUT-01's acceptance criteria.
    private struct Scene {
        let window: UIWindow
        let root: LayoutCountingView
        /// Next to `root`'s safe area and layout margins.
        let label: UILabel
        /// Next to `label`, with a width and a height of its own.
        let box: LayoutCountingView
        /// Owns `guide`, which `follower` is placed against.
        let guided: LayoutCountingView
        let guide: UILayoutGuide
        let follower: UIView
        /// A stack view and its two arranged views: UIKit makes their constraints.
        let stack: UIStackView
        let arranged: [UILabel]
        /// A view with a frame and an autoresizing mask, which `below` is placed under.
        let framed: UIView
        let below: UIView
        /// Made but never activated, and activated then deactivated.
        let inactive: [NSLayoutConstraint]

        /// The views whose constraints are compared.
        var views: [UIView] { [root, label, box, guided, follower, stack, framed, below] + arranged }
    }

    private func makeScene() throws -> Scene {
        let window = try makeWindow()
        let root = LayoutCountingView(frame: window.bounds)
        window.addSubview(root)
        func add<V: UIView>(_ view: V) -> V {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            return view
        }
        let label = add(UILabel())
        label.text = "Label"
        let box = add(LayoutCountingView())
        let guided = add(LayoutCountingView())
        let guide = UILayoutGuide()
        guide.identifier = "test.guide"
        guided.addLayoutGuide(guide)
        let follower = add(UIView())
        let arranged = [UILabel(), UILabel()]
        for (index, view) in arranged.enumerated() { view.text = "Arranged \(index)" }
        let stack = add(UIStackView(arrangedSubviews: arranged))
        stack.axis = .vertical
        let framed = UIView(frame: CGRect(x: 10, y: 300, width: 40, height: 40))
        root.addSubview(framed)
        let below = add(UIView())

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: root.safeAreaLayoutGuide.leadingAnchor, constant: 10),
            label.topAnchor.constraint(equalTo: root.layoutMarginsGuide.topAnchor),
            box.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 8),
            box.topAnchor.constraint(equalTo: label.topAnchor),
            box.widthAnchor.constraint(equalToConstant: 50),
            box.heightAnchor.constraint(equalToConstant: 40),
            guided.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            guided.topAnchor.constraint(equalTo: box.bottomAnchor, constant: 10),
            guided.widthAnchor.constraint(equalToConstant: 100),
            guided.heightAnchor.constraint(equalToConstant: 30),
            guide.leadingAnchor.constraint(equalTo: guided.leadingAnchor, constant: 5),
            guide.topAnchor.constraint(equalTo: guided.topAnchor),
            guide.widthAnchor.constraint(equalToConstant: 20),
            guide.heightAnchor.constraint(equalToConstant: 10),
            follower.leadingAnchor.constraint(equalTo: guide.trailingAnchor),
            follower.topAnchor.constraint(equalTo: guided.bottomAnchor, constant: 10),
            follower.widthAnchor.constraint(equalToConstant: 30),
            follower.heightAnchor.constraint(equalToConstant: 30),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            stack.topAnchor.constraint(equalTo: follower.bottomAnchor, constant: 10),
            below.leadingAnchor.constraint(equalTo: framed.leadingAnchor),
            below.topAnchor.constraint(equalTo: framed.bottomAnchor, constant: 5),
            below.widthAnchor.constraint(equalToConstant: 40),
            below.heightAnchor.constraint(equalToConstant: 20)
        ])
        let never = label.widthAnchor.constraint(equalToConstant: 999)
        let deactivated = box.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        deactivated.isActive = true
        deactivated.isActive = false
        window.layoutIfNeeded()
        return Scene(
            window: window,
            root: root,
            label: label,
            box: box,
            guided: guided,
            guide: guide,
            follower: follower,
            stack: stack,
            arranged: arranged,
            framed: framed,
            below: below,
            inactive: [never, deactivated]
        )
    }

    /// Every view under `view`, `view` included.
    private func allViews(under view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(allViews(under:))
    }

    /// What S-LAYOUT-01 asks for, found the long way: every constraint any view of the window
    /// holds, kept when it refers to `view` or a guide `view` owns.
    private func expected(for view: UIView, in window: UIWindow) -> [NSLayoutConstraint] {
        func refers(_ item: AnyObject?) -> Bool {
            item === view || (item as? UILayoutGuide)?.owningView === view
        }
        return allViews(under: window).flatMap(\.constraints).filter {
            refers($0.firstItem) || refers($0.secondItem)
        }
    }

    private func captured(_ view: UIView) -> [LayoutConstraint] {
        ConstraintCapture.constraints(of: view, registry: registry)
    }

    // MARK: - S-LAYOUT-01

    func test_S_LAYOUT_01_everyReferringConstraintIsListed() throws {
        let scene = try makeScene()
        for view in scene.views {
            let name = "\(type(of: view)) at \(view.frame)"
            let ids = captured(view).map(\.id)
            XCTAssertEqual(Set(ids).count, ids.count, "\(name): a constraint is listed twice")
            let wanted = expected(for: view, in: scene.window)
            XCTAssertFalse(wanted.isEmpty, "\(name): the scene gives every view constraints")
            XCTAssertEqual(Set(ids), Set(wanted.map { registry.register($0) }), name)
            XCTAssertEqual(ids.count, wanted.count, name)
        }

        // What the scene is there for: UIKit's own constraints are among them.
        func classNames(_ view: UIView) -> Set<String> { Set(captured(view).compactMap(\.className)) }
        XCTAssertTrue(
            classNames(scene.framed).contains("NSAutoresizingMaskLayoutConstraint"),
            "a framed view that a constraint refers to gets constraints from its autoresizing mask"
        )
        XCTAssertTrue(
            captured(scene.arranged[0]).contains { $0.identifier?.hasPrefix("UISV-") == true },
            "the stack view's constraints of its arranged views are found"
        )
        let rootGuides = captured(scene.root).flatMap { [$0.firstItem, $0.secondItem] }
            .compactMap { $0 }.filter { $0.kind == .layoutGuide }
        XCTAssertTrue(
            rootGuides.contains { $0.identifier == scene.root.safeAreaLayoutGuide.identifier },
            "the root view's safe area is one end of the label's constraint"
        )
    }

    func test_S_LAYOUT_01_inactiveConstraintsAreNotListed() throws {
        let scene = try makeScene()
        let inactiveIDs = Set(scene.inactive.map { registry.register($0) })
        for view in scene.views {
            XCTAssertTrue(inactiveIDs.isDisjoint(with: captured(view).map(\.id)), "\(type(of: view))")
        }
    }

    func test_S_LAYOUT_01_onlyViewsWithTheRequestHaveConstraints() throws {
        let scene = try makeScene()
        func capture(_ layer: CALayer, constraints: Bool = true, group: Bool = false) -> CapturedDetail? {
            DetailCapture.capture(
                LayerDetailRequest(
                    layerID: registry.register(layer),
                    wantSolo: false,
                    wantGroup: group,
                    wantAttributes: false,
                    wantConstraints: constraints
                ),
                maxTextureDimension: 0,
                in: .testing(windows: [scene.window], registry: registry),
                stopFlag: StopFlag(),
                screenScale: 2,
                readAttributes: { _ in
                    XCTFail("attributes were read although the request did not want them")
                    return []
                }
            )
        }

        // Constraints alone: no image is made.
        let only = try XCTUnwrap(capture(scene.box.layer))
        XCTAssertEqual(only.status, .ok)
        XCTAssertEqual(only.constraints, captured(scene.box))
        XCTAssertFalse(only.constraints.isEmpty)
        XCTAssertEqual(only.pixelByteCount, 0)
        XCTAssertEqual(only.compressed().constraints, only.constraints)
        // Not wanted.
        XCTAssertEqual(capture(scene.box.layer, constraints: false)?.constraints, [])
        // A layer that backs no view.
        let bare = CALayer()
        bare.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        scene.root.layer.addSublayer(bare)
        let bareDetail = try XCTUnwrap(capture(bare))
        XCTAssertEqual(bareDetail.status, .ok)
        XCTAssertEqual(bareDetail.constraints, [])
        XCTAssertEqual(bareDetail.compressed(), LayerDetail(layerID: bareDetail.layerID, status: .ok))

        // P-DET-03: a view that cannot be captured keeps its constraints.
        let flat = UIView()
        flat.translatesAutoresizingMaskIntoConstraints = false
        scene.root.addSubview(flat)
        NSLayoutConstraint.activate([
            flat.widthAnchor.constraint(equalToConstant: 0),
            flat.heightAnchor.constraint(equalToConstant: 0),
            flat.leadingAnchor.constraint(equalTo: scene.root.leadingAnchor),
            flat.topAnchor.constraint(equalTo: scene.root.topAnchor)
        ])
        scene.window.layoutIfNeeded()
        let failed = try XCTUnwrap(capture(flat.layer, group: true))
        XCTAssertEqual(failed.status, .captureFailed)
        XCTAssertEqual(failed.constraints.count, 4)
        XCTAssertEqual(failed.compressed().constraints, failed.constraints)
    }

    /// Reading a view's constraints, their items, owning view, identifier and the frames of
    /// layout guides neither lays out nor updates constraints.
    func test_S_LAYOUT_01_readingConstraintsDoesNotLayOut() throws {
        let scene = try makeScene()
        let counted: [LayoutCountingView] = [scene.root, scene.box, scene.guided]
        func counts() -> [Int] { counted.flatMap { [$0.layouts, $0.constraintUpdates] } }

        // Nothing pending.
        var before = counts()
        var needsLayout = scene.views.map { $0.layer.needsLayout() }
        for view in scene.views { _ = captured(view) }
        XCTAssertEqual(counts(), before, "reading laid out or updated constraints")
        XCTAssertEqual(scene.views.map { $0.layer.needsLayout() }, needsLayout)

        // A layout pass and a constraint update pending on every view.
        for view in scene.views {
            view.setNeedsLayout()
            view.setNeedsUpdateConstraints()
        }
        before = counts()
        needsLayout = scene.views.map { $0.layer.needsLayout() }
        for view in scene.views { _ = captured(view) }
        XCTAssertEqual(counts(), before, "reading laid out or updated constraints")
        XCTAssertEqual(scene.views.map { $0.layer.needsLayout() }, needsLayout, "a pending layout was carried out")
        XCTAssertTrue(
            scene.views.allSatisfy { $0.needsUpdateConstraints() },
            "a pending constraint update was carried out"
        )
    }

    // MARK: - S-LAYOUT-02

    func test_S_LAYOUT_02_constraintFieldsMatchTheObject() throws {
        let window = try makeWindow()
        let first = UIView()
        let second = UIView()
        for view in [first, second] {
            view.translatesAutoresizingMaskIntoConstraints = false
            window.addSubview(view)
        }
        let related = first.widthAnchor.constraint(
            greaterThanOrEqualTo: second.widthAnchor,
            multiplier: 2,
            constant: 3.5
        )
        related.priority = UILayoutPriority(250)
        related.identifier = "test.related"
        let alone = first.heightAnchor.constraint(lessThanOrEqualToConstant: 44)
        let unnamed = second.heightAnchor.constraint(equalToConstant: 10)
        unnamed.identifier = ""
        NSLayoutConstraint.activate([related, alone, unnamed])

        let list = captured(first)
        let wire = try XCTUnwrap(list.first { $0.id == registry.register(related) })
        XCTAssertEqual(
            wire,
            LayoutConstraint(
                id: registry.register(related),
                className: "NSLayoutConstraint",
                identifier: "test.related",
                firstItem: LayoutItem(kind: .view, layerID: registry.register(first.layer)),
                firstAttribute: .width,
                relation: .greaterThanOrEqual,
                secondItem: LayoutItem(kind: .view, layerID: registry.register(second.layer)),
                secondAttribute: .width,
                multiplier: 2,
                constant: 3.5,
                priority: 250,
                // The scene is not complete enough to say; ConstraintCheckTests judges statuses.
                status: wire.status,
                origin: .app
            )
        )

        // P-LAYOUT-05: no second item.
        let single = try XCTUnwrap(list.first { $0.id == registry.register(alone) })
        XCTAssertNil(single.secondItem)
        XCTAssertEqual(single.secondAttribute, .notAnAttribute)
        XCTAssertEqual(single.relation, .lessThanOrEqual)
        XCTAssertEqual(single.priority, 1000)
        XCTAssertNil(single.identifier)
        // An empty identifier is no identifier.
        let empty = try XCTUnwrap(captured(second).first { $0.id == registry.register(unnamed) })
        XCTAssertNil(empty.identifier)
    }

    func test_S_LAYOUT_02_everyAttributeAndRelationMaps() {
        let attributes: [(NSLayoutConstraint.Attribute, LayoutAttribute)] = [
            (.notAnAttribute, .notAnAttribute),
            (.left, .left),
            (.right, .right),
            (.top, .top),
            (.bottom, .bottom),
            (.leading, .leading),
            (.trailing, .trailing),
            (.width, .width),
            (.height, .height),
            (.centerX, .centerX),
            (.centerY, .centerY),
            (.lastBaseline, .lastBaseline),
            (.firstBaseline, .firstBaseline),
            (.leftMargin, .leftMargin),
            (.rightMargin, .rightMargin),
            (.topMargin, .topMargin),
            (.bottomMargin, .bottomMargin),
            (.leadingMargin, .leadingMargin),
            (.trailingMargin, .trailingMargin),
            (.centerXWithinMargins, .centerXWithinMargins),
            (.centerYWithinMargins, .centerYWithinMargins),
            // UIKit's autoresizing mask constraints (0.5, P-LAYOUT-07).
            (NSLayoutConstraint.Attribute(rawValue: 32)!, .minX),
            (NSLayoutConstraint.Attribute(rawValue: 33)!, .minY),
            (NSLayoutConstraint.Attribute(rawValue: 36)!, .maxX),
            (NSLayoutConstraint.Attribute(rawValue: 37)!, .maxY)
        ]
        XCTAssertEqual(attributes.count, LayoutAttribute.allCases.count)
        for (uiKit, wire) in attributes {
            XCTAssertEqual(ConstraintCapture.attribute(uiKit), wire, "\(uiKit.rawValue)")
        }
        XCTAssertEqual(NSLayoutConstraint.Attribute.lastBaseline.rawValue, 11)
        XCTAssertEqual(NSLayoutConstraint.Attribute.firstBaseline.rawValue, 12)
        // Values the protocol does not name (P-LAYOUT-08).
        for raw in [21, 34, 35, 99] {
            XCTAssertEqual(
                ConstraintCapture.attribute(NSLayoutConstraint.Attribute(rawValue: raw)!),
                .notAnAttribute,
                "\(raw)"
            )
        }

        XCTAssertEqual(ConstraintCapture.relation(.lessThanOrEqual), .lessThanOrEqual)
        XCTAssertEqual(ConstraintCapture.relation(.equal), .equal)
        XCTAssertEqual(ConstraintCapture.relation(.greaterThanOrEqual), .greaterThanOrEqual)
    }

    func test_S_LAYOUT_02_layoutGuideItems() throws {
        let scene = try makeScene()
        // The guide of the view's own, at (5, 0) in `guided`, 20 x 10.
        let toGuide = try XCTUnwrap(
            captured(scene.follower).first { $0.secondItem?.kind == .layoutGuide }
        )
        XCTAssertEqual(toGuide.firstItem, LayoutItem(kind: .view, layerID: registry.register(scene.follower.layer)))
        XCTAssertEqual(
            toGuide.secondItem,
            LayoutItem(
                kind: .layoutGuide,
                layerID: registry.register(scene.guided.layer),
                guideID: registry.register(scene.guide),
                className: "UILayoutGuide",
                displayClassName: "UILayoutGuide",
                identifier: "test.guide",
                guideFrame: WireRect(x: 5, y: 0, width: 20, height: 10),
                guideKind: .other
            )
        )
        // The same guide is listed for its owner.
        XCTAssertTrue(captured(scene.guided).contains { $0.id == toGuide.id })

        // The root view's safe area.
        let safeArea = scene.root.safeAreaLayoutGuide
        let toSafeArea = try XCTUnwrap(
            captured(scene.label).first { $0.secondItem?.guideID == registry.register(safeArea) }
        )
        let guideType: AnyClass = type(of: safeArea)
        XCTAssertEqual(
            toSafeArea.secondItem,
            LayoutItem(
                kind: .layoutGuide,
                layerID: registry.register(scene.root.layer),
                guideID: registry.register(safeArea),
                className: NSStringFromClass(guideType),
                displayClassName: String(describing: guideType),
                identifier: safeArea.identifier.isEmpty ? nil : safeArea.identifier,
                guideFrame: WireGeometry.rect(safeArea.layoutFrame),
                guideKind: .safeArea
            )
        )
    }

    func test_S_LAYOUT_02_otherItemsCarryOnlyClassNames() {
        XCTAssertEqual(
            ConstraintCapture.item(NSObject(), registry: registry),
            LayoutItem(kind: .other, className: "NSObject", displayClassName: "NSObject")
        )
        // A guide that no view owns.
        XCTAssertEqual(
            ConstraintCapture.item(UILayoutGuide(), registry: registry),
            LayoutItem(kind: .other, className: "UILayoutGuide", displayClassName: "UILayoutGuide")
        )
    }

    func test_S_LAYOUT_02_matchesTheFixtureShape() throws {
        let scene = try makeScene()
        let details = scene.views.map { view in
            LayerDetail(layerID: registry.register(view.layer), status: .ok, constraints: captured(view))
        }
        let frame = Frame(
            requestID: 1,
            body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: details))
        )
        let decoded = try FrameCodec.decode(FrameCodec.encode(frame))
        XCTAssertEqual(decoded, frame)

        // What the `layout-constraints` fixture shows (Protocol/fixtures/README.md).
        for detail in details {
            for constraint in detail.constraints {
                let name = "\(detail.layerID): \(constraint.id)"
                XCTAssertNotEqual(constraint.id, 0, name)
                XCTAssertNotNil(constraint.className, name)
                XCTAssertNotNil(constraint.firstItem, name)
                XCTAssertEqual(constraint.secondItem == nil, constraint.secondAttribute == .notAnAttribute, name)
                XCTAssertTrue((1...1000).contains(constraint.priority), name)
                // Whether each holds is ConstraintCheckTests' to check (S-LAYOUT-04): even here a
                // stretched label's intrinsic width does not hold.
                let ends = [constraint.firstItem, constraint.secondItem].compactMap { $0 }
                // One end is this layer or one of its guides.
                XCTAssertTrue(ends.contains { $0.layerID == detail.layerID }, name)
                for item in ends {
                    switch item.kind {
                    case .view:
                        XCTAssertEqual(item, LayoutItem(kind: .view, layerID: item.layerID), name)
                        XCTAssertNotEqual(item.layerID, 0, name)
                    case .layoutGuide:
                        XCTAssertNotEqual(item.layerID, 0, name)
                        XCTAssertNotEqual(item.guideID, 0, name)
                        XCTAssertNotNil(item.className, name)
                        XCTAssertNotNil(item.displayClassName, name)
                        XCTAssertNotNil(item.guideFrame, name)
                        XCTAssertNotEqual(item.identifier, "", name)
                    case .other:
                        XCTFail("\(name): the scene has nothing but views and guides")
                    }
                }
            }
        }
    }

    // MARK: - S-LAYOUT-03

    func test_S_LAYOUT_03_idsAreNonZeroAndShared() throws {
        let scene = try makeScene()
        // `box.leading == label.trailing + 8` is listed for both of its views.
        let ofLabel = captured(scene.label)
        let ofBox = captured(scene.box)
        let shared = ofLabel.filter { constraint in ofBox.contains { $0.id == constraint.id } }
        XCTAssertEqual(shared.count, 2, "box.leading and box.top refer to the label")
        for constraint in shared {
            XCTAssertEqual(ofBox.first { $0.id == constraint.id }, constraint, "the same everywhere")
        }

        // One counter for layers, constraints and guides.
        let layerIDs = Set(allViews(under: scene.window).map { registry.register($0.layer) })
        let constraintIDs = Set(scene.views.flatMap(captured).map(\.id))
        let guideIDs = Set(
            scene.views.flatMap(captured).flatMap { [$0.firstItem, $0.secondItem] }.compactMap { $0 }
                .filter { $0.kind == .layoutGuide }.map(\.guideID)
        )
        XCTAssertFalse(constraintIDs.contains(0))
        XCTAssertFalse(guideIDs.contains(0))
        XCTAssertTrue(layerIDs.isDisjoint(with: constraintIDs))
        XCTAssertTrue(layerIDs.isDisjoint(with: guideIDs))
        XCTAssertTrue(constraintIDs.isDisjoint(with: guideIDs))
        // An ID of a constraint does not lead to a layer.
        XCTAssertNil(registry.layer(for: try XCTUnwrap(constraintIDs.first)))
    }

    func test_S_LAYOUT_03_idsStayWithinAConnection() throws {
        let scene = try makeScene()
        let first = scene.views.map(captured)
        XCTAssertEqual(scene.views.map(captured), first)
        // Also after the hierarchy was read in between, which gives out more IDs.
        _ = HierarchyCapture.capture(.testing(windows: [scene.window], registry: registry))
        XCTAssertEqual(scene.views.map(captured), first)
    }

    func test_S_LAYOUT_03_releasedConstraintsGiveTheirIDsUp() throws {
        let view = UIView()
        var oldID: UInt64 = 0
        var address: ObjectIdentifier?
        autoreleasepool {
            let old = view.widthAnchor.constraint(equalToConstant: 1)
            oldID = registry.register(old)
            address = ObjectIdentifier(old)
        }
        // Make constraints until the allocator hands the old address out again.
        var others: [NSLayoutConstraint] = []
        var reused: NSLayoutConstraint?
        for _ in 0..<100_000 {
            let constraint = view.widthAnchor.constraint(equalToConstant: 1)
            if ObjectIdentifier(constraint) == address {
                reused = constraint
                break
            }
            others.append(constraint)
        }
        let constraint = try XCTUnwrap(reused, "the allocator never handed the address out again")
        let newID = registry.register(constraint)
        XCTAssertGreaterThan(newID, oldID)
        XCTAssertEqual(registry.register(constraint), newID)
    }

    func test_S_LAYOUT_03_doesNotKeepObjectsAlive() throws {
        let window = try makeWindow()
        weak var view: UIView?
        weak var constraint: NSLayoutConstraint?
        weak var guide: UILayoutGuide?
        var list: [LayoutConstraint] = []
        autoreleasepool {
            let strongView = UIView()
            strongView.translatesAutoresizingMaskIntoConstraints = false
            window.addSubview(strongView)
            let strongGuide = UILayoutGuide()
            strongView.addLayoutGuide(strongGuide)
            let strongConstraint = strongGuide.widthAnchor.constraint(equalTo: strongView.widthAnchor)
            NSLayoutConstraint.activate([
                strongConstraint,
                strongView.widthAnchor.constraint(equalToConstant: 10),
                strongView.heightAnchor.constraint(equalToConstant: 10)
            ])
            window.layoutIfNeeded()
            view = strongView
            constraint = strongConstraint
            guide = strongGuide
            list = captured(strongView)
            strongView.removeLayoutGuide(strongGuide)
            strongView.removeFromSuperview()
        }
        CATransaction.flush()
        XCTAssertEqual(list.count, 3, "the list is still held here")
        XCTAssertNil(view, "the capture kept the view alive")
        XCTAssertNil(constraint, "the capture kept the constraint alive")
        XCTAssertNil(guide, "the capture kept the guide alive")
    }
}
