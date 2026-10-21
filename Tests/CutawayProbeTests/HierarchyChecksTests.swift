import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's hierarchy checks: they accept what a correct server sends and name what is
/// wrong with anything else. A check that accepts everything would make the probe worthless.
final class HierarchyChecksTests: XCTestCase {
    private func fixtureFrame() throws -> Frame {
        try Fixtures.frame("hierarchy/02-s2c-hierarchy.bin")
    }

    /// The whole fixture: nodes 1 to 9, and the virtual and excluded nodes 10 to 14 of 1.2.
    private func fullFixtureHierarchy() throws -> Hierarchy {
        try HierarchyChecks.hierarchy(try fixtureFrame())
    }

    /// Nodes 1 to 9 of the fixture, the layers before 1.2: each at the index of its ID less one,
    /// which the tests below that change one node rely on.
    private func fixtureHierarchy() throws -> Hierarchy {
        var hierarchy = try fullFixtureHierarchy()
        hierarchy.nodes.removeAll { $0.id > 9 }
        return hierarchy
    }

    /// Asserts that the check fails and that its message contains `expected`.
    private func assertRejects(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: () throws -> Void
    ) {
        XCTAssertThrowsError(
            try check(),
            "expected a failure mentioning \"\(expected)\"",
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(
                "\(error)".contains(expected),
                "\"\(error)\" does not mention \"\(expected)\"",
                file: file,
                line: line
            )
        }
    }

    private func assertStructureRejects(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: (inout Hierarchy) -> Void
    ) throws {
        var hierarchy = try fixtureHierarchy()
        change(&hierarchy)
        assertRejects(expected, file: file, line: line) { try HierarchyChecks.structure(hierarchy) }
    }

    // MARK: - Structure

    func test_S_PROBE_01_structureChecksAcceptTheHierarchyFixture() throws {
        XCTAssertEqual(try fullFixtureHierarchy().nodes.map(\.id), [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        let hierarchy = try fixtureHierarchy()
        XCTAssertNoThrow(try HierarchyChecks.structure(hierarchy))

        // Several windows, and no key window, are fine too.
        var two = hierarchy
        two.nodes += hierarchy.nodes.map { node in
            var copy = node
            copy.id += 100
            if copy.parentID != 0 { copy.parentID += 100 }
            return copy
        }
        two.keyWindowID = 0
        XCTAssertNoThrow(try HierarchyChecks.structure(two))
        two.keyWindowID = 101
        XCTAssertNoThrow(try HierarchyChecks.structure(two))
    }

    func test_S_PROBE_01_hierarchyCheckRejectsOtherResponses() throws {
        assertRejects("expected Hierarchy, got Error(appNotActive") {
            _ = try HierarchyChecks.hierarchy(
                Frame(
                    requestID: 2,
                    body: .error(WireError(code: .appNotActive, message: "the app is not active"))
                )
            )
        }
        assertRejects("expected Hierarchy") {
            _ = try HierarchyChecks.hierarchy(Frame(requestID: 2, body: nil))
        }
    }

    func test_S_PROBE_01_structureChecksRejectBrokenHierarchies() throws {
        try assertStructureRejects("has no nodes") { $0.nodes = [] }
        try assertStructureRejects("nodes[2] has id 0") { $0.nodes[2].id = 0 }
        try assertStructureRejects("nodes[6] repeats id 3") { $0.nodes[6].id = 3 }
        // Node 5 is the child of node 4: swapped, the child comes first.
        try assertStructureRejects("comes before its parent 4") { $0.nodes.swapAt(3, 4) }
        try assertStructureRejects("comes before its parent 77") { $0.nodes[8].parentID = 77 }
        try assertStructureRejects("comes before its parent 3") { $0.nodes[2].parentID = 3 }
        // Node 7 belongs to node 6. After node 8, a sibling of node 6, it is out of pre-order.
        try assertStructureRejects("nodes[7] (id 7) is not in pre-order") { $0.nodes.swapAt(6, 7) }
        // Node 5 follows node 4 but claims node 3, a sibling of node 4, as its parent.
        try assertStructureRejects("nodes[4] (id 5) is not in pre-order") { $0.nodes[4].parentID = 3 }
        try assertStructureRejects("key_window_id 2 is not the id of a root") { $0.keyWindowID = 2 }
        try assertStructureRejects("key_window_id 99 is not the id of a root") { $0.keyWindowID = 99 }
        try assertStructureRejects("empty class name") { $0.nodes[1].className = "" }
        try assertStructureRejects("empty class name") { $0.nodes[1].displayClassName = "" }
        try assertStructureRejects("both view class names") { $0.nodes[1].viewDisplayClassName = nil }
        try assertStructureRejects("both view class names") { $0.nodes[4].viewClassName = "UIView" }
        try assertStructureRejects("both view class names") { $0.nodes[1].viewClassName = "" }
        try assertStructureRejects("not finite") { $0.nodes[3].transform.m11 = .nan }
        try assertStructureRejects("not finite") { $0.nodes[3].transform.m44 = .infinity }
        try assertStructureRejects("not finite") { $0.nodes[3].bounds.size.width = .infinity }
        try assertStructureRejects("not finite") { $0.nodes[3].bounds.origin.y = .nan }
        try assertStructureRejects("not finite") { $0.nodes[3].position.x = -.infinity }
        try assertStructureRejects("not finite") { $0.nodes[3].anchorPoint.y = .nan }
        try assertStructureRejects("not finite") { $0.nodes[3].zPosition = .nan }
        try assertStructureRejects("not finite") { $0.nodes[3].opacity = .nan }
    }

    // MARK: - Subtrees

    private func subtreeFrame() throws -> Frame {
        try Fixtures.frame("subtree/02-s2c-hierarchy.bin")
    }

    func test_S_HIER_11_subtreeCheckAcceptsTheFixture() throws {
        let subtree = try HierarchyChecks.subtree(
            try subtreeFrame(),
            rootID: 4,
            hierarchy: try fullFixtureHierarchy()
        )
        XCTAssertEqual(subtree.nodes.map(\.id), [4, 10, 11, 12, 5])

        // The subtree of a window is the whole window.
        let hierarchy = try fullFixtureHierarchy()
        let whole = Frame(requestID: 1, body: .hierarchy(hierarchy))
        XCTAssertNoThrow(try HierarchyChecks.subtree(whole, rootID: 1, hierarchy: hierarchy))
    }

    func test_S_HIER_11_subtreeCheckRejectsOtherSubtrees() throws {
        let hierarchy = try fullFixtureHierarchy()
        guard case .hierarchy(let fixture)? = try subtreeFrame().body else {
            return XCTFail("the fixture is not a Hierarchy")
        }
        func assertSubtreeRejects(
            _ expected: String,
            rootID: UInt64 = 4,
            line: UInt = #line,
            _ change: (inout Hierarchy) -> Void
        ) {
            var subtree = fixture
            change(&subtree)
            assertRejects(expected, line: line) {
                _ = try HierarchyChecks.subtree(
                    Frame(requestID: 1, body: .hierarchy(subtree)),
                    rootID: rootID,
                    hierarchy: hierarchy
                )
            }
        }
        assertRejects("expected Hierarchy for GetSubtree, got Error") {
            _ = try HierarchyChecks.subtree(
                Frame(requestID: 1, body: .error(WireError(code: .layerNotFound, message: "gone"))),
                rootID: 4,
                hierarchy: hierarchy
            )
        }
        assertSubtreeRejects("the subtree of 3 begins with node 4 (P-HIER-10)", rootID: 3) { _ in }
        assertSubtreeRejects("the subtree of 4 begins with no node") { $0.nodes = [] }
        assertSubtreeRejects("the subtree of 4 begins with node 5") { $0.nodes.reverse() }
        assertSubtreeRejects("the subtree's root 77 is not in the hierarchy", rootID: 77) {
            $0.nodes[0].id = 77
        }
        // The root keeps its parent; every node is as the hierarchy has it.
        assertSubtreeRejects("differs from the hierarchy at node 0 (id 4, expected 4)") {
            $0.nodes[0].parentID = 0
        }
        assertSubtreeRejects("differs from the hierarchy at node 4 (id 5, expected 5)") {
            $0.nodes[4].memberReferences = []
        }
        assertSubtreeRejects("differs from the hierarchy at node 1 (id 10, expected 10)") {
            $0.nodes[1].name = "Other"
        }
        assertSubtreeRejects("the subtree of 4 has 4 nodes, the hierarchy 5") { $0.nodes.removeLast() }
        assertSubtreeRejects("the subtree of 4 has 6 nodes, the hierarchy 5") {
            $0.nodes.append(hierarchy.nodes[2])
        }
        assertSubtreeRejects("the subtree's key_window_id is 0, the hierarchy's 1") { $0.keyWindowID = 0 }
    }

    func test_S_HIER_08_structureChecksCoverViewControllers() throws {
        // The fixture: node 2 is a view controller's root view; nodes 3 to 6 and 8 have member
        // references.
        try assertStructureRejects("both view controller class names") {
            $0.nodes[1].viewControllerDisplayClassName = nil
        }
        try assertStructureRejects("both view controller class names") {
            $0.nodes[2].viewControllerClassName = "Demo.OtherController"
        }
        try assertStructureRejects("both view controller class names") {
            $0.nodes[1].viewControllerClassName = ""
        }
        // Node 5 backs no view.
        try assertStructureRejects("names a view controller but backs no view") {
            $0.nodes[4].viewControllerClassName = "Demo.OtherController"
            $0.nodes[4].viewControllerDisplayClassName = "OtherController"
        }
        try assertStructureRejects("member_references[0] has an empty field") {
            $0.nodes[2].memberReferences[0].name = ""
        }
        try assertStructureRejects("member_references[1] has an empty field") {
            $0.nodes[4].memberReferences[1].ownerDisplayClassName = ""
        }
        try assertStructureRejects("member_references[0] has an empty field") {
            $0.nodes[7].memberReferences[0].ownerClassName = ""
        }
    }

    func test_S_HIER_09_structureChecksRejectLazyStorageNames() throws {
        try assertStructureRejects("the prefix of a lazy property's storage must be left out") {
            $0.nodes[2].memberReferences[0].name = "$__lazy_storage_$_titleLabel"
        }
        // Objective-C's underscore is fine (node 8 of the fixture).
        let hierarchy = try fixtureHierarchy()
        XCTAssertEqual(hierarchy.nodes[7].memberReferences.first?.name, "_dividerLayer")
        XCTAssertNoThrow(try HierarchyChecks.structure(hierarchy))
    }

    func test_S_HIER_10_structureChecksRequireDrawingOrder() throws {
        // Node 6 follows its sibling node 4 (z_position 0): further back is out of order.
        try assertStructureRejects("less than the 0.0 of the sibling before it") {
            $0.nodes[5].zPosition = -1
        }
        var hierarchy = try fixtureHierarchy()
        // The first child may be anywhere; equal values and steps up are fine.
        hierarchy.nodes[2].zPosition = -3
        hierarchy.nodes[3].zPosition = -3
        hierarchy.nodes[5].zPosition = 2
        hierarchy.nodes[7].zPosition = 2.5
        hierarchy.nodes[8].zPosition = 2.5
        // Children of different parents are not compared: node 5's parent is node 4.
        hierarchy.nodes[4].zPosition = -10
        XCTAssertNoThrow(try HierarchyChecks.structure(hierarchy))
        // Windows are not compared either.
        var windows = hierarchy
        windows.nodes.append(
            LayerNode(
                id: 50,
                parentID: 0,
                className: "UIWindowLayer",
                displayClassName: "UIWindowLayer",
                bounds: WireRect(x: 0, y: 0, width: 1, height: 1),
                position: WirePoint(x: 0, y: 0),
                zPosition: -1,
                layerAddress: 0x6000_0000_1000,
                layerClassOrigin: .system
            )
        )
        XCTAssertNoThrow(try HierarchyChecks.structure(windows))
    }

    func test_S_PROBE_05_structureChecksRequireAddresses() throws {
        // The fixture has them (P-HIER-14).
        XCTAssertNoThrow(try HierarchyChecks.structure(try fixtureHierarchy()))
        try assertStructureRejects("Hierarchy.nodes[0] (id 1) has no layer_address (P-HIER-14)") {
            $0.nodes[0].layerAddress = 0
        }
        try assertStructureRejects("(id 2) has no view_address but a view_class_name (P-HIER-14)") {
            $0.nodes[1].viewAddress = nil
        }
        try assertStructureRejects("(id 5) has a view_address but no view_class_name (P-HIER-14)") {
            $0.nodes[4].viewAddress = 0x1000
        }
        try assertStructureRejects(
            "(id 3) has a view_controller_address but no view_controller_class_name (P-HIER-14)"
        ) { $0.nodes[2].viewControllerAddress = 0x1000 }
        try assertStructureRejects(
            "(id 2) has no view_controller_address but a view_controller_class_name (P-HIER-14)"
        ) { $0.nodes[1].viewControllerAddress = nil }

        // A 1.0 server sends none.
        var plain = try fixtureHierarchy()
        for index in plain.nodes.indices {
            plain.nodes[index].layerAddress = 0
            plain.nodes[index].viewAddress = nil
            plain.nodes[index].viewControllerAddress = nil
            // Nor the base classes of the tables 1.0 does not have (P-HIER-17).
            plain.nodes[index].viewBaseClassName = nil
            plain.nodes[index].layerBaseClassName = nil
        }
        XCTAssertNoThrow(try HierarchyChecks.structure(plain, version: ProtocolVersion(major: 1, minor: 0)))
        XCTAssertThrowsError(try HierarchyChecks.structure(plain))
    }

    /// Changes the whole fixture, virtual and excluded nodes included, and expects the
    /// structure check at `version` to object.
    private func assertFullStructureRejects(
        _ expected: String,
        version: ProtocolVersion = .current,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: (inout Hierarchy) -> Void
    ) throws {
        var hierarchy = try fullFixtureHierarchy()
        change(&hierarchy)
        assertRejects(expected, file: file, line: line) { try HierarchyChecks.structure(hierarchy, version: version) }
    }

    func test_S_PROBE_08_structureChecksCoverVirtualAndExcludedNodes() throws {
        // Indices of the full fixture: 3 is node 4; 4, 5, 6 the virtual nodes 10, 11, 12; 7 is
        // node 5, node 4's sublayer; 12 and 13 the excluded nodes 13 and 14.
        XCTAssertNoThrow(try HierarchyChecks.structure(try fullFixtureHierarchy()))
        try assertFullStructureRejects(
            "is a virtual node, sent to a client of protocol 1.1",
            version: ProtocolVersion(major: 1, minor: 1)
        ) { _ in }
        try assertFullStructureRejects("nodes[7] (id 12) is a virtual node after a sublayer of 4") { $0.nodes.swapAt(
            6,
            7
        ) }
        try assertFullStructureRejects("(id 11) is a layer under the virtual node 10") {
            $0.nodes[5].nodeKind = .layer
            $0.nodes[5].name = nil
            $0.nodes[5].layerAddress = 0x1000
            $0.nodes[5].layerClassOrigin = .system
        }
        try assertFullStructureRejects("(id 4) is a layer with a name") { $0.nodes[3].name = "Card" }
        try assertFullStructureRejects("(id 10) is a virtual node without a parent") { $0.nodes[4].parentID = 0 }
        try assertFullStructureRejects("(id 10) is a virtual node with layer_address") {
            $0.nodes[4].layerAddress = 0x1000
        }
        try assertFullStructureRejects("(id 10) is a virtual node with a view") {
            $0.nodes[4].viewClassName = "UIView"
            $0.nodes[4].viewDisplayClassName = "UIView"
            $0.nodes[4].viewAddress = 0x1000
            $0.nodes[4].viewClassOrigin = .system
        }
        try assertFullStructureRejects("(id 11) is a virtual node with member_references") {
            $0.nodes[5].memberReferences = [
                MemberReference(ownerClassName: "Demo.CardView", ownerDisplayClassName: "CardView", name: "badge")
            ]
        }
        try assertFullStructureRejects("(id 12) is a virtual node with a base class") {
            $0.nodes[6].layerBaseClassName = "CAShapeLayer"
        }
        try assertFullStructureRejects("(id 12) is a virtual node whose layer_class_origin is system, not App") {
            $0.nodes[6].layerClassOrigin = .system
        }
        try assertFullStructureRejects("(id 14) has no capture_excluded, but its parent 13 has") {
            $0.nodes[13].isCaptureExcluded = false
        }
    }

    // MARK: - The demo app's screen

    /// What a correct server reports for the demo app: a window, the transition views UIKit
    /// puts between it and the screen's view, and everything DemoViewController adds.
    private func demoHierarchy() -> Hierarchy {
        func view(
            _ id: UInt64,
            in parentID: UInt64,
            _ viewClass: String,
            layerClass: String = "CALayer",
            size: WireSize
        ) -> LayerNode {
            LayerNode(
                id: id,
                parentID: parentID,
                className: layerClass,
                displayClassName: layerClass,
                viewClassName: viewClass,
                viewDisplayClassName: viewClass,
                bounds: WireRect(origin: WirePoint(x: 0, y: 0), size: size),
                position: WirePoint(x: 100, y: 100)
            )
        }
        let screen = WireSize(width: 393, height: 852)
        var screenView = view(3, in: 2, "UIView", size: screen)
        screenView.viewControllerClassName = "CutawayDemo.DemoViewController"
        screenView.viewControllerDisplayClassName = "DemoViewController"
        // The blocks of different depth, back to front.
        let block = WireSize(width: 80, height: 40)
        var blocks = [view(12, in: 11, "UIView", size: block), view(13, in: 11, "UIView", size: block)]
        blocks.append(view(14, in: 11, "UIView", size: block))
        for (index, (zPosition, x)) in [(-1.0, 90.0), (0, 140), (1, 40)].enumerated() {
            blocks[index].zPosition = zPosition
            blocks[index].position.x = x
        }
        var navigation = view(15, in: 3, "UILayoutContainerView", size: WireSize(width: 260, height: 110))
        navigation.viewControllerClassName = "UINavigationController"
        navigation.viewControllerDisplayClassName = "UINavigationController"
        var detail = view(17, in: 16, "UIView", size: WireSize(width: 260, height: 110))
        detail.viewControllerClassName = "CutawayDemo.DemoDetailViewController"
        detail.viewControllerDisplayClassName = "DemoDetailViewController"
        var card = view(5, in: 3, "CutawayDemo.CardView", size: WireSize(width: 300, height: 180))
        card.viewDisplayClassName = "CardView"
        card.masksToBounds = true
        card.transform.m11 = cos(.pi / 6)
        card.transform.m12 = sin(.pi / 6)
        card.transform.m21 = -sin(.pi / 6)
        card.transform.m22 = cos(.pi / 6)
        let shape = LayerNode(
            id: 6,
            parentID: 5,
            className: "CAShapeLayer",
            displayClassName: "CAShapeLayer",
            bounds: WireRect(x: 0, y: 0, width: 40, height: 40),
            position: WirePoint(x: 40, y: 40),
            isHidden: true,
            opacity: 0.5
        )
        var scrollView = view(7, in: 3, "UIScrollView", size: WireSize(width: 300, height: 200))
        scrollView.bounds.origin.y = 100
        scrollView.masksToBounds = true
        let bareLayer = LayerNode(
            id: 9,
            parentID: 3,
            className: "CALayer",
            displayClassName: "CALayer",
            bounds: WireRect(x: 0, y: 0, width: 60, height: 30),
            position: WirePoint(x: 10, y: 10),
            anchorPoint: WirePoint(x: 0, y: 0)
        )
        var hierarchy = Hierarchy(
            nodes: [
                view(1, in: 0, "UIWindow", layerClass: "UIWindowLayer", size: screen),
                view(2, in: 1, "UITransitionView", size: screen),
                screenView,
                view(4, in: 3, "UILabel", layerClass: "_UILabelLayer", size: WireSize(width: 200, height: 24)),
                card,
                shape,
                scrollView,
                view(8, in: 7, "UILabel", layerClass: "_UILabelLayer", size: WireSize(width: 100, height: 40)),
                bareLayer,
                view(10, in: 3, "UIView", size: WireSize(width: 0, height: 0)),
                view(11, in: 3, "UIView", size: WireSize(width: 180, height: 40))
            ] + blocks + [
                navigation,
                view(16, in: 15, "UINavigationTransitionView", size: WireSize(width: 260, height: 110)),
                detail,
                // The editing corner: the stack view with its label and block, and the view
                // without a background colour.
                view(18, in: 3, "UIStackView", layerClass: "CATransformLayer", size: WireSize(width: 90, height: 37)),
                view(19, in: 18, "UILabel", layerClass: "_UILabelLayer", size: WireSize(width: 90, height: 17)),
                view(20, in: 18, "UIView", size: WireSize(width: 90, height: 20)),
                view(21, in: 3, "UIView", size: WireSize(width: 90, height: 30)),
                // The layout corner: the label "Layout", the box with an autoresizing mask and its dot.
                view(22, in: 3, "UILabel", layerClass: "_UILabelLayer", size: WireSize(width: 43.67, height: 17)),
                view(23, in: 3, "UIView", size: WireSize(width: 60, height: 24)),
                view(24, in: 23, "UIView", size: WireSize(width: 12, height: 12))
            ],
            keyWindowID: 1
        )
        DemoReferences.add(
            to: &hierarchy,
            ids: DemoReferences.NodeIDs(
                label: 4,
                card: 5,
                shape: 6,
                scrollView: 7,
                bareLayer: 9,
                emptyView: 10,
                depth: 11,
                pushStack: 18,
                pushLabel: 19,
                pushedView: 20,
                plainView: 21,
                layoutLabel: 22,
                autoresizingBox: 23,
                autoresizedDot: 24
            )
        )
        Addresses.add(to: &hierarchy)
        return hierarchy
    }

    private func assertDemoRejects(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: (inout Hierarchy) -> Void
    ) {
        var hierarchy = demoHierarchy()
        change(&hierarchy)
        Addresses.add(to: &hierarchy)
        // The change leaves a well-formed hierarchy: only the demo check may object.
        XCTAssertNoThrow(try HierarchyChecks.structure(hierarchy), file: file, line: line)
        assertRejects(expected, file: file, line: line) { _ = try HierarchyChecks.demoScene(hierarchy) }
    }

    func test_S_PROBE_06_structureChecksRequireTheFactsAboutClasses() throws {
        try assertStructureRejects("(id 1) has no layer_class_origin, but a class name for it (P-HIER-16, 18)") {
            $0.nodes[0].layerClassOrigin = .unknown
        }
        try assertStructureRejects("(id 2) has no view_class_origin, but a class name for it") {
            $0.nodes[1].viewClassOrigin = .unknown
        }
        try assertStructureRejects("(id 5) has a view_class_origin, but no class name for it") {
            $0.nodes[4].viewClassOrigin = .app
        }
        try assertStructureRejects("(id 2) has no view_controller_visibility, but a class name for it") {
            $0.nodes[1].viewControllerVisibility = .unknown
        }
        try assertStructureRejects("(id 3) has a view_controller_class_origin, but no class name for it") {
            $0.nodes[2].viewControllerClassOrigin = .system
        }
        try assertStructureRejects("(id 2) has view_base_class_name UIViewController, which the view table") {
            $0.nodes[1].viewBaseClassName = "UIViewController"
        }
        try assertStructureRejects("(id 5) has view_base_class_name UILabel but backs no view (P-HIER-17)") {
            $0.nodes[4].viewBaseClassName = "UILabel"
        }
        try assertStructureRejects("(id 1) has layer_base_class_name CALayer, which the layer table") {
            $0.nodes[0].layerBaseClassName = "CALayer"
        }
        // A 1.0 client knows no table.
        let fixture = try fixtureHierarchy()
        assertRejects("has view_base_class_name UIWindow, which the view table of protocol 1.0 does not have") {
            try HierarchyChecks.structure(fixture, version: ProtocolVersion(major: 1, minor: 0))
        }
    }

    func test_S_PROBE_06_demoChecksRequireTheFactsAboutTheDemosClasses() {
        func assertRejects(_ expected: String, line: UInt = #line, _ change: (inout Hierarchy) -> Void) {
            var hierarchy = demoHierarchy()
            Addresses.add(to: &hierarchy)
            change(&hierarchy)
            XCTAssertNoThrow(try HierarchyChecks.structure(hierarchy), line: line)
            self.assertRejects(expected, line: line) { _ = try HierarchyChecks.demoScene(hierarchy) }
        }
        func node(_ name: String, in hierarchy: Hierarchy) -> Int {
            hierarchy.nodes.firstIndex { $0.viewControllerClassName == name || $0.viewClassName == name }!
        }
        assertRejects("the screen's view has view_controller_class_origin system, expected app") {
            $0.nodes[node("CutawayDemo.DemoViewController", in: $0)].viewControllerClassOrigin = .system
        }
        assertRejects("the screen's view has view_controller_visibility notShown, expected shown") {
            $0.nodes[node("CutawayDemo.DemoViewController", in: $0)].viewControllerVisibility = .notShown
        }
        assertRejects("CardView has view_class_origin system, expected app") {
            $0.nodes[node("CutawayDemo.CardView", in: $0)].viewClassOrigin = .system
        }
        assertRejects("the key window has view_base_class_name nil, expected Optional(\"UIWindow\")") {
            $0.nodes[0].viewBaseClassName = nil
        }
    }

    func test_S_PROBE_01_demoChecksAcceptTheExpectedScene() throws {
        let hierarchy = demoHierarchy()
        XCTAssertNoThrow(try HierarchyChecks.structure(hierarchy))
        let scene = try HierarchyChecks.demoScene(hierarchy)
        // What the scene finds by where it is, not by a variable.
        XCTAssertEqual(scene.window.id, 1)
        XCTAssertEqual(scene.screen.id, 3)
        XCTAssertEqual(scene.scrolledLabel.id, 8)
        XCTAssertEqual(scene.blocks.map(\.id), [12, 13, 14])
        XCTAssertEqual(scene.navigation.id, 15)
        XCTAssertEqual(scene.detail.id, 17)
        XCTAssertEqual(scene.screenSubviews.map(\.node.id), [4, 5, 7, 9, 10, 11, 15, 18, 21, 22, 23])
        // The fixture describes another app: its variables belong to Demo, not CutawayDemo.
        assertRejects("expected the root view of CutawayDemo.DemoViewController, found 0") {
            _ = try HierarchyChecks.demoScene(try fixtureHierarchy())
        }
    }

    func test_S_PROBE_01_demoChecksRejectChangedScenes() {
        assertDemoRejects("key_window_id is 0") { $0.keyWindowID = 0 }
        assertDemoRejects("the key window has view class DemoWindow, expected UIWindow") {
            $0.nodes[0].viewClassName = "DemoWindow"
        }
        assertDemoRejects("expected one node with view_class_name CutawayDemo.CardView, found 0") {
            $0.nodes[4].viewClassName = "CutawayDemo.OtherView"
        }
        assertDemoRejects("expected one node with view_class_name CutawayDemo.CardView, found 2") {
            $0.nodes[9].viewClassName = "CutawayDemo.CardView"
        }
        assertDemoRejects("emptyView has view class CutawayDemo.OtherView, expected UIView") {
            $0.nodes[9].viewClassName = "CutawayDemo.OtherView"
        }
        assertDemoRejects("cardView has view display class CutawayDemo.CardView, expected CardView") {
            $0.nodes[4].viewDisplayClassName = "CutawayDemo.CardView"
        }
        assertDemoRejects("cardView has masksToBounds false, expected true") { $0.nodes[4].masksToBounds = false }
        assertDemoRejects("cardView is 300.0 x 181.0 points, expected 300.0 x 180.0") {
            $0.nodes[4].bounds.size.height = 181
        }
        assertDemoRejects("not a rotation by 30 degrees") { $0.nodes[4].transform = .identity }
        assertDemoRejects("not a rotation by 30 degrees") { $0.nodes[4].transform.m12 = -0.5 }
        assertDemoRejects("badge has hidden false, expected true") { $0.nodes[5].isHidden = false }
        assertDemoRejects("badge has opacity 1.0, expected 0.5") { $0.nodes[5].opacity = 1 }
        assertDemoRejects("badge backs a view (UIView), expected none") {
            $0.nodes[5].viewClassName = "UIView"
            $0.nodes[5].viewDisplayClassName = "UIView"
        }
        assertDemoRejects("cardView must hold badge, found 0 sublayers") { $0.nodes[5].parentID = 3 }
        assertDemoRejects("scrollView has bounds origin (0.0, 0.0), expected (0.0, 100.0)") {
            $0.nodes[6].bounds.origin.y = 0
        }
        assertDemoRejects("expected a UILabel in scrollView, found 0") { $0.nodes[7].viewClassName = "UIView" }
        assertDemoRejects("bareLayer has anchor point (0.5, 0.5), expected (0.0, 0.0)") {
            $0.nodes[8].anchorPoint = WirePoint(x: 0.5, y: 0.5)
        }
        assertDemoRejects("emptyView is 1.0 x 0.0 points, expected 0.0 x 0.0") { $0.nodes[9].bounds.size.width = 1 }
        // The subviews in another order: the bare layer and the empty view swapped, and the
        // label after the card instead of before it (P-HIER-01).
        assertDemoRejects("emptyView comes before bareLayer") { $0.nodes.swapAt(8, 9) }
        assertDemoRejects("cardView comes before titleLabel") {
            let label = $0.nodes.remove(at: 3)
            $0.nodes.insert(label, at: 9)
        }
        assertDemoRejects("titleLabel is not on the screen's view") {
            // Under the transition view, listed before the screen's view: still in pre-order.
            var label = $0.nodes.remove(at: 3)
            label.parentID = 2
            $0.nodes.insert(label, at: 2)
        }
    }

    func test_S_HIER_08_demoChecksRejectMissingViewControllers() {
        assertDemoRejects("expected the root view of CutawayDemo.DemoViewController, found 0") {
            $0.nodes[2].viewControllerClassName = nil
            $0.nodes[2].viewControllerDisplayClassName = nil
        }
        assertDemoRejects(
            "the screen's view has view controller display class CutawayDemo.DemoViewController, expected "
                + "DemoViewController"
        ) {
            $0.nodes[2].viewControllerDisplayClassName = "CutawayDemo.DemoViewController"
        }
        assertDemoRejects("expected the root view of CutawayDemo.DemoViewController, found 0") {
            $0.nodes[2].viewControllerClassName = "CutawayDemo.OtherController"
        }
        assertDemoRejects("expected the root view of a UINavigationController on the screen's view, found 0") {
            $0.nodes[14].viewControllerClassName = "UITabBarController"
        }
        assertDemoRejects("the navigation controller's view is 261.0 x 110.0 points, expected 260.0 x 110.0") {
            $0.nodes[14].bounds.size.width = 261
        }
        assertDemoRejects("DemoDetailViewController inside the navigation controller, found 0") {
            $0.nodes[16].viewControllerClassName = "CutawayDemo.OtherController"
        }
        // Nodes 15 to 17: the navigation controller's views.
        assertDemoRejects("the root view of a UINavigationController on the screen's view, found 0") {
            $0.nodes.removeAll { (15...17).contains($0.id) }
        }
    }

    func test_S_PROBE_03_demoChecksRequireTheEditingCorner() {
        // Nodes 18 to 21: the stack view, its label, its block, the view of 90 x 30.
        assertDemoRejects("DemoViewController / pushStack, found 0 (P-HIER-08)") { $0.nodes.removeLast(7) }
        assertDemoRejects("pushStack has view class UIView, expected UIStackView") {
            $0.nodes[17].viewClassName = "UIView"
        }
        assertDemoRejects("pushStack is 100.0 points wide, expected 90.0") { $0.nodes[17].bounds.size.width = 100 }
        assertDemoRejects("pushedView is 90.0 x 30.0 points, expected 90.0 x 20.0") {
            $0.nodes[19].bounds.size = WireSize(width: 90, height: 30)
        }
        assertDemoRejects("pushStack must hold pushLabel then pushedView, found 2 sublayers in another order") {
            $0.nodes.swapAt(18, 19)
        }
        assertDemoRejects("plainView is 90.0 x 31.0 points, expected 90.0 x 30.0") {
            $0.nodes[20].bounds.size.height = 31
        }
        assertDemoRejects("plainView must hold nothing, found 1 sublayers") {
            // Right after its parent: the hierarchy lists every layer before its sublayers.
            $0.nodes.insert(
                LayerNode(
                    id: 99,
                    parentID: 21,
                    className: "CALayer",
                    displayClassName: "CALayer",
                    bounds: WireRect(x: 0, y: 0, width: 1, height: 1),
                    position: WirePoint(x: 0, y: 0)
                ),
                at: 21
            )
        }
        assertDemoRejects("DemoViewController / pushStack, found 0") { $0.nodes[17].memberReferences = [] }
        assertDemoRejects("DemoViewController / pushLabel, found 0") { $0.nodes[18].memberReferences[0].name = "label" }
        assertDemoRejects("DemoViewController / pushLabel, found 2") {
            $0.nodes[19].memberReferences = [DemoReferences.reference("pushLabel")]
        }
        assertDemoRejects("DemoViewController / plainView, found 0") {
            $0.nodes[20].memberReferences[0].ownerDisplayClassName = "View"
        }
    }

    func test_S_PROBE_04_demoChecksRequireTheLayoutCorner() {
        // Nodes 22 to 24: the label "Layout", the box of 60 x 24, its dot of 12 x 12.
        assertDemoRejects("DemoViewController / layoutLabel, found 0") { $0.nodes.removeLast(3) }
        assertDemoRejects("layoutLabel has view class UIView, expected UILabel") {
            $0.nodes[21].viewClassName = "UIView"
        }
        assertDemoRejects("autoresizingBox is 61.0 x 24.0 points, expected 60.0 x 24.0") {
            $0.nodes[22].bounds.size.width = 61
        }
        assertDemoRejects("DemoViewController / autoresizedDot, found 0") { $0.nodes.removeLast() }
        assertDemoRejects("autoresizedDot is 12.0 x 13.0 points, expected 12.0 x 12.0") {
            $0.nodes[23].bounds.size = WireSize(width: 12, height: 13)
        }
        assertDemoRejects("DemoViewController / layoutLabel, found 0") { $0.nodes[21].memberReferences = [] }
        assertDemoRejects("DemoViewController / autoresizingBox, found 0") {
            $0.nodes[22].memberReferences[0].name = "box"
        }
        assertDemoRejects("DemoViewController / autoresizingBox, found 2") {
            $0.nodes[23].memberReferences = [DemoReferences.reference("autoresizingBox")]
        }
    }

    func test_S_PROBE_02_demoChecksRejectOtherMemberReferences() {
        // Node 4 is the label, 5 the card, 6 its shape layer, 7 the scroll view, 9 the bare
        // layer, 11 the blocks' view.
        assertDemoRejects(
            "expected one node whose first member reference is CutawayDemo.DemoViewController / DemoViewController / "
                + "titleLabel, found 0 (P-HIER-08)"
        ) {
            $0.nodes[3].memberReferences = []
        }
        assertDemoRejects("DemoViewController / cardView, found 0") { $0.nodes[4].memberReferences[0].name = "card" }
        assertDemoRejects("CutawayDemo.CardView / CardView / badge, found 0") {
            $0.nodes[5].memberReferences = [DemoReferences.reference("badge")]
        }
        assertDemoRejects("DemoViewController / scrollView, found 0") {
            $0.nodes[6].memberReferences[0].ownerClassName = "DemoViewController"
        }
        assertDemoRejects("DemoViewController / bareLayer, found 0") {
            $0.nodes[8].memberReferences[0].ownerDisplayClassName = "CutawayDemo.DemoViewController"
        }
        // A nearer holder comes first, so the demo's variable is no longer the first.
        assertDemoRejects("DemoViewController / depthView, found 0") {
            $0.nodes[10].memberReferences.insert(
                MemberReference(ownerClassName: "UIView", ownerDisplayClassName: "UIView", name: "_other"),
                at: 0
            )
        }
        // References from holders further up do not matter.
        var farther = demoHierarchy()
        farther.nodes[3].memberReferences.append(
            MemberReference(ownerClassName: "UIWindow", ownerDisplayClassName: "UIWindow", name: "_far")
        )
        XCTAssertNoThrow(try HierarchyChecks.demoScene(farther))
    }

    func test_S_HIER_10_demoChecksRejectBlocksInAnotherOrder() {
        // The blocks in the order they were added: z_position 1 first is out of drawing order
        // for the structure check, so swap their positions instead.
        assertDemoRejects("position.x 90, 140, 40") {
            $0.nodes[11].position.x = 40
            $0.nodes[13].position.x = 90
        }
        assertDemoRejects("depthView has 2 sublayers, expected the three blocks") { $0.nodes.remove(at: 13) }
        assertDemoRejects("block 1 of depthView is 80.0 x 41.0 points, expected 80.0 x 40.0") {
            $0.nodes[12].bounds.size.height = 41
        }
    }
}
