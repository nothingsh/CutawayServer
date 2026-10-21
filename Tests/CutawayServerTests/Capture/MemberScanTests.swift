import CutawayWire
import ObjectiveC
import UIKit
import XCTest

@testable import CutawayServer

// Holders of every kind the scan reads (S-HIER-09).
class MemberBaseController: UIViewController {
    let baseLabel = UILabel()
    var baseLayer: CALayer?
}

struct MemberPair {
    var count: Int
    var view: UIView
}

final class MemberController: MemberBaseController {
    let strongView = UIView()
    weak var weakView: UIView?
    var optionalView: UIView?
    var implicitView: UIView!
    unowned(unsafe) var unsafeView: UIView
    lazy var lazyView = UIView()
    var tuple: (Int, UIView)
    var pair: MemberPair

    init(unsafeView: UIView, tupleView: UIView, pairView: UIView) {
        self.unsafeView = unsafeView
        tuple = (1, tupleView)
        pair = MemberPair(count: 2, view: pairView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

final class MemberHolderView: UIView {
    let heldLayer = CALayer()
}

// References that do not come from an ancestor.
final class SiblingView: UIView {
    var other: UIView?
    var parentView: UIView?
    var ownLayer: CALayer?
}

// What the scan cannot see.
final class UnsupportedView: UIView {
    unowned var unownedView: UIView
    var array: [UIView] = []

    init(unownedView: UIView) {
        self.unownedView = unownedView
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

// The runtime lists the variables of a generic class too.
final class GenericHolderView<Content>: UIView {
    var held: UIView?
    var content: Content?
}

// References to objects that are gone.
final class ReleasedHolderView: UIView {
    weak var weakView: UIView?
    unowned var unownedView: UIView
    unowned(unsafe) var unsafeView: UIView

    init(target: UIView) {
        unownedView = target
        unsafeView = target
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
}

final class GetterView: UIView {
    var reads = 0
    var sets = 0
    var target: UIView? { didSet { sets += 1 } }
    var computed: UIView? {
        reads += 1
        return target
    }
}

/// The instance variables that hold a layer or its view. No server, no
/// connection.
final class MemberScanTests: CaptureTestCase {
    private func reference(_ owner: String, _ name: String, module: Bool = true) -> MemberReference {
        MemberReference(
            ownerClassName: module ? "CutawayServerTests.\(owner)" : owner,
            ownerDisplayClassName: owner,
            name: name
        )
    }

    private func references(
        of object: AnyObject,
        in hierarchy: Hierarchy,
        registry: LayerRegistry,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [MemberReference] {
        let layer = (object as? UIView)?.layer ?? (object as! CALayer)
        return try node(of: layer, in: hierarchy, registry: registry, file: file, line: line).memberReferences
    }

    func test_S_HIER_09_referencesNameTheDeclaringClassAndVariable() throws {
        let window = try makeWindow()
        let unsafe = UIView()
        let tupleView = UIView()
        let pairView = UIView()
        let controller = MemberController(unsafeView: unsafe, tupleView: tupleView, pairView: pairView)
        window.rootViewController = controller
        let weak = UIView()
        let optional = UIView()
        let implicit = UIView()
        let baseLayer = CALayer()
        controller.weakView = weak
        controller.optionalView = optional
        controller.implicitView = implicit
        controller.baseLayer = baseLayer
        let holder = MemberHolderView()
        let generic = GenericHolderView<Int>()
        let held = UIView()
        generic.held = held
        for view in [
            controller.baseLabel,
            controller.strongView,
            weak,
            optional,
            implicit,
            unsafe,
            controller.lazyView,
            tupleView,
            pairView,
            holder,
            generic
        ] {
            controller.view.addSubview(view)
        }
        controller.view.layer.addSublayer(baseLayer)
        holder.layer.addSublayer(holder.heldLayer)
        generic.addSubview(held)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        let expected: [(AnyObject, MemberReference)] = [
            (controller.baseLabel, reference("MemberBaseController", "baseLabel")),
            (baseLayer, reference("MemberBaseController", "baseLayer")),
            (controller.strongView, reference("MemberController", "strongView")),
            (weak, reference("MemberController", "weakView")),
            (optional, reference("MemberController", "optionalView")),
            (implicit, reference("MemberController", "implicitView")),
            (unsafe, reference("MemberController", "unsafeView")),
            // Without the prefix of the lazy storage.
            (controller.lazyView, reference("MemberController", "lazyView")),
            // In the second word of a tuple, and of a struct.
            (tupleView, reference("MemberController", "tuple")),
            (pairView, reference("MemberController", "pair")),
            // A layer that backs no view, held by a view of the tests' own.
            (holder.heldLayer, reference("MemberHolderView", "heldLayer")),
            // Declared by a generic class: its mangled runtime name, and a readable one.
            (
                held,
                MemberReference(
                    ownerClassName: "_TtGC18CutawayServerTests17GenericHolderViewSi_",
                    ownerDisplayClassName: "GenericHolderView<Int>",
                    name: "held"
                )
            )
        ]
        for (object, reference) in expected {
            XCTAssertEqual(
                try references(of: object, in: hierarchy, registry: registry),
                [reference],
                "\(reference.name)"
            )
        }
    }

    func test_S_HIER_09_referencesAreOrderedNearestFirst() throws {
        let window = try makeWindow()
        let controller = OrderController()
        window.rootViewController = controller
        let root = controller.view as! OrderRootView
        let outer = OrderOuterView()
        let inner = OrderInnerView()
        let leaf = UIView()
        root.addSubview(outer)
        outer.addSubview(inner)
        inner.addSubview(leaf)
        for holder in [root.target, outer.target, inner.target] { XCTAssertNil(holder) }
        root.target = leaf
        outer.target = leaf
        inner.target = leaf
        controller.baseTarget = leaf
        controller.second = leaf
        controller.first = leaf

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(
            try references(of: leaf, in: hierarchy, registry: registry),
            [
                // The nearest holder first.
                reference("OrderInnerView", "target"),
                reference("OrderOuterView", "target"),
                // On one node, the view before its controller.
                reference("OrderRootView", "target"),
                // In one controller: the subclass before the superclass, then the order of declaration.
                reference("OrderController", "first"),
                reference("OrderController", "second"),
                reference("OrderBaseController", "baseTarget")
            ]
        )
    }

    func test_S_HIER_09_onlyAncestorsCount() throws {
        let window = try makeWindow()
        let controller = UIViewController()
        window.rootViewController = controller
        let firstSibling = SiblingView()
        let secondSibling = SiblingView()
        let child = SiblingView()
        controller.view.addSubview(firstSibling)
        controller.view.addSubview(secondSibling)
        firstSibling.addSubview(child)
        // A sibling, a parent, and the holder's own layer: none is below the holder.
        firstSibling.other = secondSibling
        secondSibling.other = firstSibling
        child.parentView = firstSibling
        firstSibling.ownLayer = firstSibling.layer

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        for object in [firstSibling, secondSibling, child, window] {
            // A view's `_layer` points at the node itself.
            XCTAssertEqual(try references(of: object, in: hierarchy, registry: registry), [], "\(object)")
        }
        // The controller's `_view` points at the node itself too. (UIKit's container of firstSibling root
        // view controller's view holds it as well, and that container is an ancestor.)
        let rootReferences = try references(of: controller.view!, in: hierarchy, registry: registry)
        XCTAssertFalse(rootReferences.contains { $0.ownerClassName == "UIViewController" }, "\(rootReferences)")
    }

    func test_S_HIER_09_uikitHoldersCount() throws {
        let window = try makeWindow()
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.frame = CGRect(x: 0, y: 0, width: 320, height: 44)
        cell.textLabel?.text = "Cell"
        window.addSubview(cell)
        window.layoutIfNeeded()

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        // UIKit's own variables, with their underscore (P-HIER-09).
        XCTAssertTrue(
            try references(of: cell.contentView, in: hierarchy, registry: registry)
                .contains(reference("UITableViewCell", "_contentView", module: false))
        )
        let label = try XCTUnwrap(cell.textLabel)
        XCTAssertTrue(
            try references(of: label, in: hierarchy, registry: registry)
                .contains(reference("UITableViewCell", "_textLabel", module: false))
        )
    }

    func test_S_HIER_09_unsupportedFormsAreLeftOut() throws {
        let window = try makeWindow()
        let unownedTarget = UIView()
        let unsupported = UnsupportedView(unownedView: unownedTarget)
        let inArray = UIView()
        unsupported.array = [inArray]
        unsupported.addSubview(unownedTarget)
        unsupported.addSubview(inArray)
        window.addSubview(unsupported)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        for target in [unownedTarget, inArray] {
            let names = try references(of: target, in: hierarchy, registry: registry).map(\.name)
            XCTAssertFalse(names.contains("unownedView"), "\(names)")
            XCTAssertFalse(names.contains("array"), "\(names)")
        }
    }

    func test_S_HIER_09_releasedTargetsAreSafe() throws {
        let window = try makeWindow()
        var target: UIView? = UIView()
        let holder = ReleasedHolderView(target: target!)
        holder.weakView = target
        // The holder needs something below it, or it is not looked at.
        let child = UIView()
        holder.addSubview(child)
        window.addSubview(holder)
        // Everything in the hierarchy exists before the target goes, so that no new object
        // can take its address.
        target = nil
        CATransaction.flush()

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(try references(of: child, in: hierarchy, registry: registry), [])
    }

    func test_S_HIER_09_noGetterIsCalled() throws {
        let window = try makeWindow()
        let holder = GetterView()
        let child = UIView()
        holder.addSubview(child)
        holder.target = child
        window.addSubview(holder)
        XCTAssertEqual(holder.sets, 1)

        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        XCTAssertEqual(
            try references(of: child, in: hierarchy, registry: registry),
            [reference("GetterView", "target")]
        )
        XCTAssertEqual(holder.reads, 0, "a getter ran")
        XCTAssertEqual(holder.sets, 1, "a setter ran")
    }

    func test_S_HIER_09_scanStaysInsideTheObject() {
        let classes: [AnyClass] = [
            UIView.self,
            UILabel.self,
            UIScrollView.self,
            UITableViewCell.self,
            UIViewController.self,
            UINavigationController.self,
            UIWindow.self,
            MemberController.self,
            MemberHolderView.self,
            GenericHolderView<Int>.self,
            OrderController.self,
            GetterView.self,
            UnsupportedView.self
        ]
        for start in classes {
            var type: AnyClass? = start
            while let current = type, ObjectIdentifier(current) != ObjectIdentifier(UIResponder.self) {
                let size = class_getInstanceSize(current)
                for variable in MemberScan.plan(for: current) {
                    for offset in variable.offsets {
                        XCTAssertEqual(offset % 8, 0, "\(current).\(variable.name)")
                        XCTAssertLessThanOrEqual(offset + 8, size, "\(current).\(variable.name)")
                    }
                }
                type = class_getSuperclass(current)
            }
        }
        // What the plan of a Swift class holds: every word of a tuple, the lazy name without its
        // prefix, nothing for a Bool or an Int that fits in less than a word.
        let plan = MemberScan.plan(for: MemberController.self)
        XCTAssertEqual(plan.first { $0.name == "tuple" }?.offsets.count, 2)
        XCTAssertEqual(plan.first { $0.name == "pair" }?.offsets.count, 2)
        XCTAssertNotNil(plan.first { $0.name == "lazyView" })
        XCTAssertNil(plan.first { $0.name.hasPrefix("$") })
        XCTAssertEqual(MemberScan.name(of: "$__lazy_storage_$_x"), "x")
        XCTAssertEqual(MemberScan.name(of: "_titleLabel"), "_titleLabel")
    }
}
