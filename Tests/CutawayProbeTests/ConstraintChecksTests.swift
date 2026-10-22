import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// What the probe checks in the constraints of every layer, and in the demo
/// app's known constraints.
final class ConstraintChecksTests: XCTestCase {
    /// Asserts that the check fails and that its message contains every one of `expected`.
    private func assertRejects(
        _ expected: String...,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: () throws -> Void
    ) {
        XCTAssertThrowsError(
            try check(),
            "expected a failure mentioning \(expected)",
            file: file,
            line: line
        ) { error in
            for part in expected {
                XCTAssertTrue(
                    "\(error)".contains(part),
                    "\"\(error)\" does not mention \"\(part)\"",
                    file: file,
                    line: line
                )
            }
        }
    }

    // MARK: - Structure

    private static func viewNode(_ id: UInt64, _ parent: UInt64) -> LayerNode {
        LayerNode(
            id: id,
            parentID: parent,
            className: "CALayer",
            displayClassName: "CALayer",
            viewClassName: "UIView",
            viewDisplayClassName: "UIView",
            bounds: WireRect(x: 0, y: 0, width: 10, height: 10),
            position: WirePoint(x: 5, y: 5)
        )
    }

    /// Layer 1 backs a view and owns guide 50; layer 2 is its subview; layer 3 backs no view.
    private var nodes: [UInt64: LayerNode] {
        var bare = Self.viewNode(3, 1)
        bare.viewClassName = nil
        bare.viewDisplayClassName = nil
        return [1: Self.viewNode(1, 0), 2: Self.viewNode(2, 1), 3: bare]
    }

    private static let guide = LayoutItem(
        kind: .layoutGuide,
        layerID: 1,
        guideID: 50,
        className: "UILayoutGuide",
        displayClassName: "UILayoutGuide",
        identifier: "UIViewSafeAreaLayoutGuide",
        guideFrame: WireRect(x: 0, y: 2, width: 10, height: 8),
        guideKind: .safeArea
    )

    private static func view(_ layerID: UInt64) -> LayoutItem { LayoutItem(kind: .view, layerID: layerID) }

    private static func constraint(
        _ id: UInt64,
        _ first: LayoutItem?,
        _ firstAttribute: LayoutAttribute,
        _ second: LayoutItem? = nil,
        _ secondAttribute: LayoutAttribute = .notAnAttribute,
        constant: Double = 0,
        priority: Float = 1000,
        status: ConstraintStatus = .satisfied,
        className: String? = "NSLayoutConstraint"
    ) -> LayoutConstraint {
        LayoutConstraint(
            id: id,
            className: className,
            firstItem: first,
            firstAttribute: firstAttribute,
            relation: .equal,
            secondItem: second,
            secondAttribute: secondAttribute,
            multiplier: 1,
            constant: constant,
            priority: priority,
            status: status,
            origin: ["NSAutoresizingMaskLayoutConstraint", "NSContentSizeLayoutConstraint"]
                .contains(className) ? .system : .app
        )
    }

    /// Layer 2's constraints: to its superview, to the superview's guide, one with a single
    /// item, one to something that is neither, and two of UIKit's autoresizing mask (0.5).
    private var detail: LayerDetail {
        let other = LayoutItem(kind: .other, className: "_UIOdd", displayClassName: "Odd")
        return LayerDetail(
            layerID: 2,
            status: .ok,
            constraints: [
                Self.constraint(1, Self.view(2), .leading, Self.view(1), .leading, constant: 8),
                Self.constraint(2, Self.view(2), .top, Self.guide, .top),
                Self.constraint(3, Self.view(2), .width, constant: 30, priority: 500, status: .unsatisfied),
                Self.constraint(4, Self.view(2), .height, other, .height, status: .unknown),
                Self.constraint(
                    5,
                    Self.view(1),
                    .width,
                    Self.view(2),
                    .maxX,
                    constant: 42,
                    status: .unknown,
                    className: "NSAutoresizingMaskLayoutConstraint"
                ),
                Self.constraint(
                    6,
                    Self.view(2),
                    .minY,
                    constant: 100,
                    status: .unknown,
                    className: "NSAutoresizingMaskLayoutConstraint"
                )
            ]
        )
    }

    private static let wantConstraints = LayerDetailRequest(
        layerID: 2,
        wantSolo: false,
        wantGroup: false,
        wantAttributes: false,
        wantConstraints: true
    )

    private func check(
        _ detail: LayerDetail,
        request: LayerDetailRequest = wantConstraints,
        tables: inout ConstraintChecks.Tables
    ) throws {
        try ConstraintChecks.structure(
            detail,
            for: request,
            node: nodes[detail.layerID],
            nodes: nodes,
            tables: &tables
        )
    }

    private func assertStructureRejects(
        _ expected: String...,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: (inout LayerDetail) -> Void
    ) {
        var changed = detail
        change(&changed)
        var tables = ConstraintChecks.Tables()
        XCTAssertThrowsError(try check(changed, tables: &tables), file: file, line: line) { error in
            for part in expected {
                XCTAssertTrue(
                    "\(error)".contains(part),
                    "\"\(error)\" does not mention \"\(part)\"",
                    file: file,
                    line: line
                )
            }
        }
    }

    func test_S_PROBE_06_constraintsHaveOriginsAndGuidesKinds() {
        assertStructureRejects("constraint 1 of layer 2 has no origin (P-LAYOUT-09)") {
            $0.constraints[0].origin = .unknown
        }
        assertStructureRejects("layout guide 50 has no guide_kind (P-LAYOUT-04)") {
            $0.constraints[1].secondItem?.guideKind = .unknown
        }
        assertStructureRejects("an item of kind other has guide_kind safeArea (P-LAYOUT-04)") {
            $0.constraints[3].secondItem?.guideKind = .safeArea
        }
        // A 1.0 peer: no origins needed, and a guide is `Other` or absent.
        var old = detail
        for index in old.constraints.indices { old.constraints[index].origin = .unknown }
        old.constraints[1].secondItem?.guideKind = .other
        var tables = ConstraintChecks.Tables()
        let version10 = ProtocolVersion(major: 1, minor: 0)
        XCTAssertNoThrow(
            try ConstraintChecks.structure(
                old,
                for: Self.wantConstraints,
                node: nodes[2],
                nodes: nodes,
                tables: &tables,
                version: version10
            )
        )
        old.constraints[1].secondItem?.guideKind = .safeArea
        tables = ConstraintChecks.Tables()
        assertRejects("guide_kind safeArea, which protocol 1.0 does not have (P-LAYOUT-04)") {
            try ConstraintChecks.structure(
                old,
                for: Self.wantConstraints,
                node: self.nodes[2],
                nodes: self.nodes,
                tables: &tables,
                version: version10
            )
        }
    }

    func test_S_PROBE_04_structureAcceptsSoundConstraints() throws {
        var tables = ConstraintChecks.Tables()
        XCTAssertNoThrow(try check(detail, tables: &tables))
        // The same constraints and guide again, as the superview's detail would list them.
        var superview = detail
        superview.layerID = 1
        superview.constraints = [detail.constraints[0], detail.constraints[1], detail.constraints[4]]
        XCTAssertNoThrow(try check(superview, tables: &tables))
        XCTAssertEqual(tables.constraints.count, 6)
        XCTAssertEqual(tables.guides.count, 1)

        // Nothing asked, nothing given; a layer without a view has none; nor has a missing one.
        var none = detail
        none.constraints = []
        XCTAssertNoThrow(
            try check(
                none,
                request: LayerDetailRequest(layerID: 2, wantSolo: true, wantGroup: false, wantAttributes: false),
                tables: &tables
            )
        )
        XCTAssertNoThrow(try check(LayerDetail(layerID: 3, status: .ok), tables: &tables))
        XCTAssertNoThrow(try check(LayerDetail(layerID: 99, status: .layerNotFound), tables: &tables))
    }

    func test_S_PROBE_04_structureRejectsWhatWasNotAskedFor() {
        var tables = ConstraintChecks.Tables()
        let imagesOnly = LayerDetailRequest(layerID: 2, wantSolo: true, wantGroup: false, wantAttributes: false)
        assertRejects("layer 2", "did not want them", "P-LAYOUT-01") {
            try check(detail, request: imagesOnly, tables: &tables)
        }
        var bare = detail
        bare.layerID = 3
        assertRejects("layer 3", "backs no view", "P-LAYOUT-01") { try check(bare, tables: &tables) }
        var missing = detail
        missing.layerID = 99
        missing.status = .layerNotFound
        assertRejects("layer 99", "LayerNotFound", "P-DET-02") { try check(missing, tables: &tables) }
    }

    func test_S_PROBE_04_structureRejectsBrokenConstraints() {
        assertStructureRejects("constraint 0", "P-LAYOUT-03") { $0.constraints[0].id = 0 }
        assertStructureRejects("constraint 1", "class_name", "P-LAYOUT-02") { $0.constraints[0].className = "" }
        assertStructureRejects("constraint 1", "class_name", "P-LAYOUT-02") { $0.constraints[0].className = nil }
        assertStructureRejects("constraint 1", "first_item", "P-LAYOUT-04") { $0.constraints[0].firstItem = nil }
        assertStructureRejects("constraint 6", "first_attribute", "NotAnAttribute", "P-LAYOUT-08") {
            $0.constraints[5].firstAttribute = .notAnAttribute
        }
        assertStructureRejects("constraint 5", "second_attribute", "P-LAYOUT-05", "P-LAYOUT-08") {
            $0.constraints[4].secondAttribute = .notAnAttribute
        }
        assertStructureRejects("constraint 3", "second_attribute", "P-LAYOUT-05") {
            $0.constraints[2].secondAttribute = .height
        }
        assertStructureRejects("constraint 3", "priority", "P-LAYOUT-05") { $0.constraints[2].priority = 0 }
        assertStructureRejects("constraint 3", "priority", "P-LAYOUT-05") { $0.constraints[2].priority = 1001 }
        assertStructureRejects("constraint 1", "multiplier", "P-LAYOUT-05") { $0.constraints[0].multiplier = .nan }
        assertStructureRejects("constraint 1", "constant", "P-LAYOUT-05") { $0.constraints[0].constant = .infinity }
        // Neither end is layer 2 or one of its guides.
        assertStructureRejects("constraint 1", "layer 2", "P-LAYOUT-01") {
            $0.constraints[0].firstItem = Self.view(1)
        }
    }

    func test_S_PROBE_04_structureRejectsBrokenItems() {
        // A view item with more than its layer, or with a layer that backs no view or is not
        // in the hierarchy.
        assertStructureRejects("constraint 1", "View", "P-LAYOUT-04") {
            $0.constraints[0].secondItem?.className = "UIView"
        }
        assertStructureRejects("constraint 1", "View", "P-LAYOUT-04") { $0.constraints[0].secondItem?.guideID = 7 }
        assertStructureRejects("constraint 1", "layer 3", "P-LAYOUT-04") { $0.constraints[0].secondItem?.layerID = 3 }
        assertStructureRejects("constraint 1", "layer 77", "P-LAYOUT-04") { $0.constraints[0].secondItem?.layerID = 77 }
        // A guide without its ID, class names or frame, or owned by a layer that backs no view.
        assertStructureRejects("constraint 2", "LayoutGuide", "P-LAYOUT-04") {
            $0.constraints[1].secondItem?.guideID = 0
        }
        assertStructureRejects("constraint 2", "LayoutGuide", "P-LAYOUT-04") {
            $0.constraints[1].secondItem?.className = nil
        }
        assertStructureRejects("constraint 2", "LayoutGuide", "P-LAYOUT-04") {
            $0.constraints[1].secondItem?.displayClassName = ""
        }
        assertStructureRejects("constraint 2", "LayoutGuide", "P-LAYOUT-04") {
            $0.constraints[1].secondItem?.guideFrame = nil
        }
        assertStructureRejects("constraint 2", "layer 3", "P-LAYOUT-04") { $0.constraints[1].secondItem?.layerID = 3 }
        // Anything else carries its class names and nothing more.
        assertStructureRejects("constraint 4", "Other", "P-LAYOUT-04") { $0.constraints[3].secondItem?.layerID = 1 }
        assertStructureRejects("constraint 4", "Other", "P-LAYOUT-04") { $0.constraints[3].secondItem?.identifier = "x"
        }
        assertStructureRejects("constraint 4", "Other", "P-LAYOUT-04") { $0.constraints[3].secondItem?.className = nil }
    }

    func test_S_PROBE_04_structureRejectsDifferentCopies() {
        var tables = ConstraintChecks.Tables()
        XCTAssertNoThrow(try check(detail, tables: &tables))
        var superview = detail
        superview.layerID = 1
        superview.constraints = [detail.constraints[0]]
        superview.constraints[0].constant = 9
        assertRejects("constraint 1", "differs", "P-LAYOUT-03") { try check(superview, tables: &tables) }

        var moved = detail
        moved.layerID = 1
        moved.constraints = [detail.constraints[1]]
        moved.constraints[0].id = 7
        moved.constraints[0].secondItem?.guideFrame = WireRect(x: 0, y: 0, width: 1, height: 1)
        assertRejects("guide 50", "differs", "P-LAYOUT-03") { try check(moved, tables: &tables) }
    }

    // MARK: - The demo app's screen

    private static let screenID: UInt64 = 3
    private static let labelID: UInt64 = 30
    private static let boxID: UInt64 = 31
    private static let autoresizing = "NSAutoresizingMaskLayoutConstraint"

    /// What a correct server sends for the demo's top right corner on a screen 402 points
    /// wide (Demo/CutawayDemo/DemoViewController.swift).
    private func demo() -> (hierarchy: Hierarchy, details: [LayerDetail]) {
        var screen = Self.viewNode(Self.screenID, 2)
        screen.bounds.size = WireSize(width: 402, height: 874)
        screen.viewControllerClassName = "CutawayDemo.DemoViewController"
        screen.viewControllerDisplayClassName = "DemoViewController"
        var label = Self.viewNode(Self.labelID, Self.screenID)
        label.viewClassName = "UILabel"
        var box = Self.viewNode(Self.boxID, Self.screenID)
        box.memberReferences = [DemoReferences.reference("autoresizingBox")]
        let hierarchy = Hierarchy(
            nodes: [Self.viewNode(1, 0), Self.viewNode(2, 1), screen, label, box, Self.viewNode(32, Self.boxID)],
            keyWindowID: 1
        )

        let safeArea = LayoutItem(
            kind: .layoutGuide,
            layerID: Self.screenID,
            guideID: 60,
            className: "UILayoutGuide",
            displayClassName: "UILayoutGuide",
            identifier: "UIViewSafeAreaLayoutGuide",
            guideFrame: WireRect(x: 0, y: 62, width: 402, height: 778),
            guideKind: .safeArea
        )
        let top = Self.constraint(59, Self.view(Self.labelID), .top, safeArea, .top, constant: 8)
        let trailing = Self.constraint(61, Self.view(Self.labelID), .trailing, safeArea, .trailing, constant: -16)
        let labelConstraints = [
            Self.constraint(
                139,
                Self.view(Self.labelID),
                .width,
                constant: 43.67,
                className: "NSContentSizeLayoutConstraint"
            ),
            Self.constraint(
                140,
                Self.view(Self.labelID),
                .height,
                constant: 17,
                className: "NSContentSizeLayoutConstraint"
            ),
            Self.constraint(141, Self.view(Self.labelID), .width, constant: 30, priority: 500, status: .unsatisfied),
            top,
            trailing
        ]
        let dot = Self.view(32)
        let boxConstraints = [
            Self.constraint(142, dot, .centerX, Self.view(Self.boxID), .centerX),
            Self.constraint(143, dot, .centerY, Self.view(Self.boxID), .centerY),
            Self.constraint(
                56,
                Self.view(Self.screenID),
                .width,
                Self.view(Self.boxID),
                .maxX,
                constant: 42,
                status: .unknown,
                className: Self.autoresizing
            ),
            Self.constraint(144, Self.view(Self.boxID), .width, constant: 60, className: Self.autoresizing),
            Self.constraint(
                145,
                Self.view(Self.boxID),
                .minY,
                constant: 100,
                status: .unknown,
                className: Self.autoresizing
            ),
            Self.constraint(146, Self.view(Self.boxID), .height, constant: 24, className: Self.autoresizing)
        ]
        let text = Attribute(
            id: "label.text",
            title: "Text",
            value: .string("Layout"),
            editable: true,
            valueKind: .string
        )
        let resistance = Attribute(
            id: "view.contentCompressionResistancePriority.horizontal",
            title: "Resistance",
            value: .double(750),
            editable: true,
            valueKind: .double
        )
        let details = [
            LayerDetail(layerID: Self.screenID, status: .ok, constraints: [top, trailing, boxConstraints[2]]),
            LayerDetail(
                layerID: Self.labelID,
                status: .ok,
                attributeGroups: [
                    AttributeGroup(id: "view", title: "View", attributes: [resistance]),
                    AttributeGroup(id: "label", title: "Label", attributes: [text])
                ],
                constraints: labelConstraints
            ),
            LayerDetail(layerID: Self.boxID, status: .ok, constraints: boxConstraints)
        ]
        return (hierarchy, details)
    }

    /// The demo check with the nodes the scene would find: the screen's view, the label
    /// "Layout" and the box.
    private static func demo(_ details: [LayerDetail], hierarchy: Hierarchy) throws -> ConstraintChecks
        .DemoConstraints {
        try ConstraintChecks.demo(
            details,
            screen: hierarchy.nodes[2],
            layoutLabel: hierarchy.nodes[3],
            box: hierarchy.nodes[4]
        )
    }

    private func assertDemoRejects(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: (inout Hierarchy, inout [LayerDetail]) -> Void
    ) {
        var (hierarchy, details) = demo()
        change(&hierarchy, &details)
        assertRejects(expected, file: file, line: line) {
            _ = try Self.demo(details, hierarchy: hierarchy)
        }
    }

    /// The constraint with this ID in the detail of `layerID`.
    private func edit(
        _ details: inout [LayerDetail],
        layer layerID: UInt64,
        constraint id: UInt64,
        _ body: (inout LayoutConstraint) -> Void
    ) {
        guard let detailIndex = details.firstIndex(where: { $0.layerID == layerID }),
              let constraintIndex = details[detailIndex].constraints.firstIndex(where: { $0.id == id })
        else { return XCTFail("no constraint \(id) on layer \(layerID)") }
        body(&details[detailIndex].constraints[constraintIndex])
    }

    func test_S_PROBE_04_demoChecksAcceptTheExpectedConstraints() throws {
        let (hierarchy, details) = demo()
        let found = try Self.demo(details, hierarchy: hierarchy)
        XCTAssertEqual(found.labelID, Self.labelID)
        XCTAssertEqual(found.narrowID, 141)
        XCTAssertEqual(found.handwrittenIDs, [59, 61, 141])
        XCTAssertEqual(found.compressionResistance, 750)
        XCTAssertEqual(found.labelConstraints.count, 5)
        // Any order will do.
        var reversed = details
        for index in reversed.indices { reversed[index].constraints.reverse() }
        XCTAssertNoThrow(try Self.demo(reversed, hierarchy: hierarchy))
    }

    func test_S_PROBE_06_demoChecksRequireOriginsAndTheSafeAreasKind() {
        // The guide is the safe area by its kind too (P-LAYOUT-04).
        assertDemoRejects("top") { _, details in
            edit(&details, layer: Self.labelID, constraint: 59) { $0.secondItem?.guideKind = .other }
        }
        // The demo's own constraint is the app's, UIKit's for the mask the system's (P-LAYOUT-09).
        assertDemoRejects("top") { _, details in
            edit(&details, layer: Self.labelID, constraint: 59) { $0.origin = .system }
        }
        assertDemoRejects("autoresizing mask constraints") { _, details in
            edit(&details, layer: Self.boxID, constraint: 144) { $0.origin = .app }
        }
    }

    func test_S_PROBE_04_demoChecksRejectOtherConstraints() {
        assertDemoRejects("has no view.contentCompressionResistancePriority.horizontal") { _, details in
            details[1].attributeGroups.removeAll()
        }
        assertDemoRejects("no detail for the label \"Layout\"") { _, details in details.remove(at: 1) }
        assertDemoRejects("top") { _, details in
            edit(&details, layer: Self.labelID, constraint: 59) { $0.secondItem?.identifier = "other" }
        }
        assertDemoRejects("top") { _, details in
            edit(&details, layer: Self.labelID, constraint: 59) { $0.secondItem?.layerID = Self.boxID }
        }
        assertDemoRejects("trailing") { _, details in
            edit(&details, layer: Self.labelID, constraint: 61) { $0.constant = 16 }
        }
        assertDemoRejects("top") { _, details in
            edit(&details, layer: Self.labelID, constraint: 59) { $0.status = .unknown }
        }
        assertDemoRejects("width == 30") { _, details in
            edit(&details, layer: Self.labelID, constraint: 141) { $0.status = .satisfied }
        }
        assertDemoRejects("width == 30") { _, details in
            edit(&details, layer: Self.labelID, constraint: 141) { $0.priority = 250 }
        }
        assertDemoRejects("width == 30") { _, details in
            details[1].constraints.removeAll { $0.id == 141 }
        }
        // The safe area's constraints, also on the guide owner's side.
        assertDemoRejects("the screen's view") { _, details in details[0].constraints.removeFirst() }
        // The box: missing, without UIKit's constraints, or with other ones.
        assertDemoRejects("no detail for autoresizingBox") { _, details in details.removeLast() }
        assertDemoRejects("autoresizing") { _, details in
            details[2].constraints.removeAll { $0.className == Self.autoresizing }
        }
        assertDemoRejects("autoresizing") { _, details in
            edit(&details, layer: Self.boxID, constraint: 56) { $0.firstItem = Self.view(Self.boxID) }
        }
        assertDemoRejects("autoresizing") { _, details in
            edit(&details, layer: Self.boxID, constraint: 56) { $0.constant = 33 }
        }
        assertDemoRejects("autoresizing") { _, details in
            edit(&details, layer: Self.boxID, constraint: 145) { $0.status = .satisfied }
        }
        assertDemoRejects("autoresizing") { _, details in
            edit(&details, layer: Self.boxID, constraint: 145) { $0.firstAttribute = .top }
        }
    }

    func test_S_PROBE_04_loweredResistanceLetsTheWidthWin() throws {
        let (hierarchy, details) = demo()
        let found = try Self.demo(details, hierarchy: hierarchy)
        var lowered = details[1]
        lowered.attributeGroups = []
        edit(&lowered.constraints, id: 141) { $0.status = .satisfied }
        // UIKit replaces the content size constraint for the width.
        lowered.constraints[0].id = 149
        lowered.constraints[0].status = .unsatisfied
        XCTAssertNoThrow(try ConstraintChecks.lowered(lowered, demo: found))

        var still = lowered
        edit(&still.constraints, id: 141) { $0.status = .unsatisfied }
        assertRejects("width == 30") { try ConstraintChecks.lowered(still, demo: found) }
        var renamed = lowered
        edit(&renamed.constraints, id: 141) { $0.id = 200 }
        assertRejects("width == 30", "P-LAYOUT-03") { try ConstraintChecks.lowered(renamed, demo: found) }
    }

    func test_S_PROBE_04_changingBackRestoresTheConstraints() throws {
        let (hierarchy, details) = demo()
        let found = try Self.demo(details, hierarchy: hierarchy)
        var restored = details[1]
        restored.attributeGroups = []
        // A new content size constraint, and another order.
        restored.constraints[0].id = 150
        restored.constraints.swapAt(0, 1)
        XCTAssertNoThrow(try ConstraintChecks.restored(restored, demo: found))

        var stillWinning = restored
        edit(&stillWinning.constraints, id: 141) { $0.status = .satisfied }
        assertRejects("changing back") { try ConstraintChecks.restored(stillWinning, demo: found) }
        var newID = restored
        edit(&newID.constraints, id: 59) { $0.id = 300 }
        assertRejects("59", "P-LAYOUT-03") { try ConstraintChecks.restored(newID, demo: found) }
        var extra = restored
        extra.constraints.append(Self.constraint(301, Self.view(Self.labelID), .height, constant: 5))
        assertRejects("changing back") { try ConstraintChecks.restored(extra, demo: found) }
    }

    private func edit(_ constraints: inout [LayoutConstraint], id: UInt64, _ body: (inout LayoutConstraint) -> Void) {
        guard let index = constraints.firstIndex(where: { $0.id == id }) else { return XCTFail("no constraint \(id)") }
        body(&constraints[index])
    }
}
