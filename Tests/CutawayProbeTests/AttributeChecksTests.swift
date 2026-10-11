import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's attribute checks: they accept what a correct server sends and name what is
/// wrong with anything else.
final class AttributeChecksTests: XCTestCase {
    /// Tests/CutawayProbeTests/AttributeChecksTests.swift -> the repository root.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The attribute groups the fixture's chunk gives the layer `layerID`.
    private func fixtureGroups(_ path: String, layer layerID: UInt64) throws -> [AttributeGroup] {
        let frame = try FrameCodec.decode(
            Data(contentsOf: Self.root.appendingPathComponent("Protocol/fixtures/bin").appendingPathComponent(path))
        )
        guard case .layerDetailsChunk(let chunk)? = frame.body else {
            throw ProbeFailure("\(path) is not a chunk")
        }
        return try XCTUnwrap(chunk.details.first { $0.layerID == layerID }).attributeGroups
    }

    /// Layer 3 of `layer-details`: three groups that use all eleven kinds of value and a nil.
    private func layer3() throws -> [AttributeGroup] {
        try fixtureGroups("layer-details/02-s2c-chunk-0.bin", layer: 3)
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
        _ change: (inout [AttributeGroup]) -> Void
    ) throws {
        var groups = try layer3()
        change(&groups)
        assertRejects(expected, file: file, line: line) {
            try AttributeChecks.structure(groups, name: "layer 3")
        }
    }

    // MARK: - Structure

    func test_S_PROBE_01_attributeChecksAcceptTheFixtures() throws {
        let groups = try layer3()
        XCTAssertEqual(groups.map(\.id), ["layer", "label", "view"])
        XCTAssertNoThrow(try AttributeChecks.structure(groups, name: "layer 3"))
        XCTAssertNoThrow(
            try AttributeChecks.structure(
                try fixtureGroups("layer-details-edge/02-s2c-chunk-0.bin", layer: 9),
                name: "layer 9"
            )
        )
        XCTAssertNoThrow(try AttributeChecks.structure([], name: "nothing"))
    }

    func test_S_PROBE_01_attributeChecksRejectBrokenGroups() throws {
        try assertStructureRejects("has a group with an empty id") { $0[0].id = "" }
        try assertStructureRejects("has two groups with the id layer (P-ATTR-01)") { $0[1].id = "layer" }
        try assertStructureRejects("group label has an empty title") { $0[1].title = "" }
        try assertStructureRejects("attribute frame of group layer does not begin with \"layer.\"") {
            $0[0].attributes[0].id = "frame"
        }
        try assertStructureRejects("attribute layer. of group layer does not begin") {
            $0[0].attributes[0].id = "layer."
        }
        try assertStructureRejects("attribute layer.frame of group label does not begin") {
            $0[1].attributes.append($0[0].attributes[0])
        }
        try assertStructureRejects("group layer has two attributes with the id layer.frame (P-ATTR-01)") {
            $0[0].attributes[1].id = "layer.frame"
        }
        try assertStructureRejects("attribute label.text has an empty title") { $0[1].attributes[0].title = "" }
        try assertStructureRejects("attribute layer.opacity has a number that is not finite") {
            $0[0].attributes[3].value = .double(.nan)
        }
        try assertStructureRejects("attribute layer.frame has a number that is not finite") {
            $0[0].attributes[0].value = .rect(WireRect(x: 0, y: .infinity, width: 1, height: 1))
        }
        try assertStructureRejects("attribute layer.borderColor has a number that is not finite") {
            $0[0].attributes[6].value = .color(WireColor(red: .nan, green: 0, blue: 0, alpha: 1))
        }
        try assertStructureRejects("attribute label.textAlignment is the case \"middle\"") {
            $0[1].attributes[2].value = .enumeration(
                value: 1,
                cases: ["left", "center"],
                caseName: "middle",
                caseValues: [0, 1]
            )
        }
        try assertStructureRejects("attribute label.textAlignment is an enumeration with no cases") {
            $0[1].attributes[2].value = .enumeration(value: 0, cases: [], caseName: "", caseValues: [])
        }
        try assertStructureRejects(
            "attribute label.textAlignment is an enumeration with no cases, or a case without a name"
        ) {
            $0[1].attributes[2].value = .enumeration(
                value: 0,
                cases: ["", "center"],
                caseName: "center",
                caseValues: [0, 1]
            )
        }
    }

    func test_S_ATTR_05_attributeChecksRequireAValueKindThatFits() throws {
        try assertStructureRejects("attribute layer.opacity has no value_kind (P-ATTR-06)") {
            $0[0].attributes[3].valueKind = .none
        }
        try assertStructureRejects("attribute layer.backgroundColor has no value_kind (P-ATTR-06)") {
            // Nil, so only its value_kind says what it takes.
            $0[0].attributes[5].valueKind = .none
        }
        try assertStructureRejects(
            "attribute layer.opacity is a double value, but its value_kind is int (P-ATTR-06)"
        ) { $0[0].attributes[3].valueKind = .int }
    }

    func test_S_ATTR_06_attributeChecksRequireCaseValuesThatPair() throws {
        func alignment(_ value: Int64, _ caseName: String, _ caseValues: [Int64]) -> AttributeValue {
            .enumeration(
                value: value,
                cases: ["left", "center", "right"],
                caseName: caseName,
                caseValues: caseValues
            )
        }
        try assertStructureRejects("they must be as many, each once (P-ATTR-07)") {
            $0[1].attributes[2].value = alignment(1, "center", [0, 1])
        }
        try assertStructureRejects("they must be as many, each once (P-ATTR-07)") {
            $0[1].attributes[2].value = alignment(1, "center", [0, 1, 1])
        }
        try assertStructureRejects("has the value 7 and the case \"center\"") {
            $0[1].attributes[2].value = alignment(7, "center", [0, 1, 2])
        }
        try assertStructureRejects("has the value 2 and the case \"center\"") {
            $0[1].attributes[2].value = alignment(2, "center", [0, 1, 2])
        }
        // Raw values need not start at 0 or be in order.
        var groups = try layer3()
        groups[1].attributes[2].value = alignment(-3, "right", [10, 4, -3])
        XCTAssertNoThrow(try AttributeChecks.structure(groups, name: "layer 3"))
    }

    // MARK: - The attribute list

    func test_S_PROBE_01_theListHasEveryAttributeOfVersion01() {
        XCTAssertEqual(
            Set(AttributeChecks.list.keys),
            [
                "layer",
                "view",
                "label",
                "imageView",
                "control",
                "button",
                "scrollView",
                "stackView",
                "textField",
                "textView"
            ]
        )
        // 60 of version 0.1 and the 8 of S-ATTR-07.
        XCTAssertEqual(AttributeChecks.list.values.reduce(0) { $0 + $1.count }, 68)
    }

    func test_S_ATTR_07_theListHasTheLayoutAttributes() {
        let view = AttributeChecks.list["view"]!
        XCTAssertEqual(
            view.suffix(8).map(\.name),
            [
                "contentHuggingPriority.horizontal",
                "contentHuggingPriority.vertical",
                "contentCompressionResistancePriority.horizontal",
                "contentCompressionResistancePriority.vertical",
                "intrinsicContentSize.width",
                "intrinsicContentSize.height",
                "translatesAutoresizingMaskIntoConstraints",
                "hasAmbiguousLayout"
            ]
        )
        XCTAssertEqual(view.suffix(8).map(\.editable), [true, true, true, true, false, false, true, false])
        XCTAssertEqual(view.suffix(8).map(\.nullable), [false, false, false, false, true, true, false, false])
        XCTAssertTrue(view.suffix(8).allSatisfy { !$0.acceptsNil })
    }

    // MARK: - The demo app's screen

    /// A value of each kind, for attributes whose value the checks do not look at.
    private func placeholder(_ kind: AttributeValueKind) -> AttributeValue {
        switch kind {
        case .none: fatalError("every attribute of the list has a kind")
        case .bool: .bool(false)
        case .int: .int(0)
        case .double: .double(1)
        case .string: .string("text")
        case .color: .color(WireColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        case .point: .point(WirePoint(x: 1, y: 2))
        case .size: .size(WireSize(width: 3, height: 4))
        case .rect: .rect(WireRect(x: 1, y: 2, width: 3, height: 4))
        case .insets: .insets(WireInsets(top: 1, left: 2, bottom: 3, right: 4))
        case .transform: .transform(.identity)
        case .enumeration: .enumeration(value: 0, cases: ["only"], caseName: "only", caseValues: [0])
        }
    }

    /// Groups with every attribute of the list, the geometry of `node`, and `values` where given.
    private func groups(
        _ ids: [String],
        for node: LayerNode,
        _ values: [String: AttributeValue] = [:]
    ) -> [AttributeGroup] {
        var known: [String: AttributeValue] = [
            "layer.bounds": .rect(node.bounds),
            "layer.position": .point(node.position),
            "layer.anchorPoint": .point(node.anchorPoint),
            "layer.transform": .transform(node.transform),
            "layer.zPosition": .double(node.zPosition),
            "layer.hidden": .bool(node.isHidden),
            "layer.opacity": .double(Double(node.opacity)),
            "layer.masksToBounds": .bool(node.masksToBounds)
        ]
        known.merge(values) { $1 }
        return ids.map { groupID in
            AttributeGroup(
                id: groupID,
                title: groupID,
                attributes: AttributeChecks.list[groupID]!.map { entry in
                    let id = "\(groupID).\(entry.name)"
                    return Attribute(
                        id: id,
                        title: entry.name,
                        value: known[id] ?? placeholder(entry.kind),
                        editable: entry.editable,
                        acceptsNil: entry.acceptsNil,
                        valueKind: entry.kind
                    )
                }
            )
        }
    }

    /// The demo app's screen as a correct server reports it: a window, the screen's view, and
    /// everything DemoViewController adds to it.
    private func demo() -> (hierarchy: Hierarchy, details: [LayerDetail]) {
        func node(
            _ id: UInt64,
            in parentID: UInt64,
            _ viewClass: String?,
            layerClass: String = "CALayer",
            width: Double,
            height: Double
        ) -> LayerNode {
            LayerNode(
                id: id,
                parentID: parentID,
                className: layerClass,
                displayClassName: layerClass,
                viewClassName: viewClass,
                viewDisplayClassName: viewClass,
                bounds: WireRect(x: 0, y: 0, width: width, height: height),
                position: WirePoint(x: 100, y: 100)
            )
        }
        let window = node(1, in: 0, "UIWindow", layerClass: "UIWindowLayer", width: 393, height: 852)
        var screen = node(2, in: 1, "UIView", width: 393, height: 852)
        screen.viewControllerClassName = "CutawayDemo.DemoViewController"
        screen.viewControllerDisplayClassName = "DemoViewController"
        let label = node(3, in: 2, "UILabel", layerClass: "_UILabelLayer", width: 200, height: 24)
        var card = node(4, in: 2, "CutawayDemo.CardView", width: 300, height: 180)
        card.viewDisplayClassName = "CardView"
        card.masksToBounds = true
        card.transform.m11 = cos(.pi / 6)
        card.transform.m12 = sin(.pi / 6)
        card.transform.m21 = -sin(.pi / 6)
        card.transform.m22 = cos(.pi / 6)
        var shape = node(5, in: 4, nil, layerClass: "CAShapeLayer", width: 40, height: 40)
        shape.isHidden = true
        shape.opacity = 0.5
        var scrollView = node(6, in: 2, "UIScrollView", width: 300, height: 200)
        scrollView.bounds.origin.y = 100
        scrollView.masksToBounds = true
        let scrolled = node(7, in: 6, "UILabel", layerClass: "_UILabelLayer", width: 100, height: 40)
        var bare = node(8, in: 2, nil, width: 60, height: 30)
        bare.anchorPoint = WirePoint(x: 0, y: 0)
        let empty = node(9, in: 2, "UIView", width: 0, height: 0)
        let depth = node(10, in: 2, "UIView", width: 180, height: 40)
        let blocks = [(11, -1.0, 90.0), (12, 0, 140), (13, 1, 40)].map { id, zPosition, x -> LayerNode in
            var block = node(UInt64(id), in: 10, "UIView", width: 80, height: 40)
            block.zPosition = zPosition
            block.position.x = x
            return block
        }
        var navigation = node(14, in: 2, "UILayoutContainerView", width: 260, height: 110)
        navigation.viewControllerClassName = "UINavigationController"
        navigation.viewControllerDisplayClassName = "UINavigationController"
        let transition = node(15, in: 14, "UINavigationTransitionView", width: 260, height: 110)
        var detail = node(16, in: 15, "UIView", width: 260, height: 110)
        detail.viewControllerClassName = "CutawayDemo.DemoDetailViewController"
        detail.viewControllerDisplayClassName = "DemoDetailViewController"
        let added = [depth] + blocks + [navigation, transition, detail]
        // Protocol 0.3: the stack view with its label and block, and the view without a
        // background colour.
        let stack = node(17, in: 2, "UIStackView", layerClass: "CATransformLayer", width: 90, height: 37)
        let push = node(18, in: 17, "UILabel", layerClass: "_UILabelLayer", width: 90, height: 17)
        let pushed = node(19, in: 17, "UIView", width: 90, height: 20)
        let plain = node(20, in: 2, "UIView", width: 90, height: 30)
        // Protocol 0.4: the label "Layout", the box with an autoresizing mask and its dot.
        let layout = node(21, in: 2, "UILabel", layerClass: "_UILabelLayer", width: 43.67, height: 17)
        let box = node(22, in: 2, "UIView", width: 60, height: 24)
        let dot = node(23, in: 22, "UIView", width: 12, height: 12)
        var hierarchy = Hierarchy(
            nodes: [window, screen, label, card, shape, scrollView, scrolled, bare, empty] + added
                + [stack, push, pushed, plain, layout, box, dot],
            keyWindowID: 1
        )
        DemoReferences.add(
            to: &hierarchy,
            ids: DemoReferences.NodeIDs(
                label: 3,
                card: 4,
                shape: 5,
                scrollView: 6,
                bareLayer: 8,
                emptyView: 9,
                depth: 10,
                pushStack: 17,
                pushLabel: 18,
                pushedView: 19,
                plainView: 20,
                layoutLabel: 21,
                autoresizingBox: 22,
                autoresizedDot: 23
            )
        )

        let black = AttributeValue.color(WireColor(red: 0, green: 0, blue: 0, alpha: 1))
        let details = [
            LayerDetail(layerID: 1, status: .ok, attributeGroups: groups(["layer", "view"], for: window)),
            LayerDetail(layerID: 2, status: .ok, attributeGroups: groups(["layer", "view"], for: screen)),
            LayerDetail(
                layerID: 3,
                status: .ok,
                attributeGroups: groups(
                    ["layer", "view", "label"],
                    for: label,
                    ["label.text": .string("CutawayDemo"), "label.textColor": black]
                )
            ),
            LayerDetail(
                layerID: 4,
                status: .ok,
                attributeGroups: groups(["layer", "view"], for: card, ["view.clipsToBounds": .bool(true)])
            ),
            LayerDetail(layerID: 5, status: .ok, attributeGroups: groups(["layer"], for: shape)),
            LayerDetail(
                layerID: 6,
                status: .ok,
                attributeGroups: groups(
                    ["layer", "view", "scrollView"],
                    for: scrollView,
                    [
                        "scrollView.contentOffset": .point(WirePoint(x: 0, y: 100)),
                        "scrollView.contentSize": .size(WireSize(width: 300, height: 600)),
                        "scrollView.contentInset": .insets(WireInsets(top: 0, left: 0, bottom: 0, right: 0))
                    ]
                )
            ),
            LayerDetail(
                layerID: 7,
                status: .ok,
                attributeGroups: groups(
                    ["layer", "view", "label"],
                    for: scrolled,
                    ["label.text": .string("Scrolled")]
                )
            ),
            LayerDetail(
                layerID: 8,
                status: .ok,
                attributeGroups: groups(
                    ["layer"],
                    for: bare,
                    ["layer.backgroundColor": .color(WireColor(red: 1, green: 0.5, blue: 0, alpha: 1))]
                )
            ),
            LayerDetail(layerID: 9, status: .captureFailed, attributeGroups: groups(["layer", "view"], for: empty))
        ] + added.map { LayerDetail(layerID: $0.id, status: .ok, attributeGroups: groups(["layer", "view"], for: $0)) }
            + [
                LayerDetail(
                    layerID: 17,
                    status: .ok,
                    attributeGroups: groups(["layer", "view", "stackView"], for: stack)
                ),
                LayerDetail(
                    layerID: 18,
                    status: .ok,
                    attributeGroups: groups(["layer", "view", "label"], for: push, ["label.text": .string("Push")])
                ),
                LayerDetail(layerID: 19, status: .ok, attributeGroups: groups(["layer", "view"], for: pushed)),
                LayerDetail(layerID: 20, status: .ok, attributeGroups: groups(["layer", "view"], for: plain)),
                LayerDetail(
                    layerID: 21,
                    status: .ok,
                    attributeGroups: groups(
                        ["layer", "view", "label"],
                        for: layout,
                        ["label.text": .string("Layout")]
                    )
                ),
                LayerDetail(layerID: 22, status: .ok, attributeGroups: groups(["layer", "view"], for: box)),
                LayerDetail(layerID: 23, status: .ok, attributeGroups: groups(["layer", "view"], for: dot))
            ]
        return (hierarchy, details)
    }

    /// Changes the attributes of the layer `layerID` and expects the demo check to object.
    private func assertDemoRejects(
        _ expected: String,
        layer layerID: UInt64,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: (inout [AttributeGroup]) -> Void
    ) {
        let (hierarchy, fixtureDetails) = demo()
        var details = fixtureDetails
        let index = details.firstIndex { $0.layerID == layerID }!
        change(&details[index].attributeGroups)
        assertRejects(expected, file: file, line: line) {
            try AttributeChecks.demo(details, hierarchy: hierarchy, scene: try DemoScene(hierarchy))
        }
    }

    /// Sets the value of the attribute `id` in the groups.
    private func set(_ id: String, _ value: AttributeValue?, in groups: inout [AttributeGroup]) {
        for groupIndex in groups.indices {
            for attributeIndex in groups[groupIndex].attributes.indices
                where groups[groupIndex].attributes[attributeIndex].id == id {
                groups[groupIndex].attributes[attributeIndex].value = value
            }
        }
    }

    func test_S_PROBE_01_demoAttributeChecksAcceptTheExpectedScreen() throws {
        let (hierarchy, details) = demo()
        XCTAssertNoThrow(try HierarchyChecks.structure(hierarchy))
        let scene = try HierarchyChecks.demoScene(hierarchy)
        for detail in details {
            XCTAssertNoThrow(try AttributeChecks.structure(detail.attributeGroups, name: "\(detail.layerID)"))
        }
        XCTAssertNoThrow(try AttributeChecks.demo(details, hierarchy: hierarchy, scene: scene))

        // Colours within 1/255 of the expected ones are close enough.
        var close = details
        set(
            "label.textColor",
            .color(WireColor(red: 0.003, green: 0, blue: 0, alpha: 1)),
            in: &close[2].attributeGroups
        )
        XCTAssertNoThrow(try AttributeChecks.demo(close, hierarchy: hierarchy, scene: scene))
        // A nullable attribute may be nil.
        set("view.tintColor", nil, in: &close[0].attributeGroups)
        XCTAssertNoThrow(try AttributeChecks.demo(close, hierarchy: hierarchy, scene: scene))
    }

    func test_S_ATTR_05_demoAttributeChecksAcceptReadOnlyFallbacks() throws {
        let (hierarchy, details) = demo()
        let scene = try DemoScene(hierarchy)
        var fallback = details
        // view.contentMode of the screen's view, with a raw value that has no name.
        fallback[1].attributeGroups[1].attributes[6] = Attribute(
            id: "view.contentMode",
            title: "contentMode",
            value: .string("99"),
            valueKind: .string
        )
        XCTAssertNoThrow(try AttributeChecks.demo(fallback, hierarchy: hierarchy, scene: scene))
    }

    func test_S_PROBE_01_demoAttributeChecksRejectChangedScreens() {
        // The list: missing, extra and swapped attributes, the wrong kind, a nil it does not allow.
        assertDemoRejects("group view has the attributes", layer: 2) { $0[1].attributes.removeLast() }
        assertDemoRejects("group view has the attributes", layer: 2) {
            $0[1].attributes.append(
                Attribute(id: "view.extra", title: "Extra", value: .bool(true), editable: true, valueKind: .bool)
            )
        }
        assertDemoRejects("group layer has the attributes", layer: 8) { $0[0].attributes.swapAt(0, 1) }
        assertDemoRejects("attribute view.tag is a double value, expected int", layer: 2) {
            self.set("view.tag", .double(1), in: &$0)
        }
        assertDemoRejects("attribute layer.cornerRadius is nil, which the list does not allow", layer: 2) {
            self.set("layer.cornerRadius", nil, in: &$0)
        }
        assertDemoRejects("the group switch, which the attribute list of version 0.1 does not have", layer: 2) {
            $0.append(AttributeGroup(id: "switch", title: "Switch", attributes: []))
        }
        // The flags of the list (P-ATTR-06).
        assertDemoRejects(
            "attribute layer.frame has value_kind rect, editable true, accepts_nil false; the list says rect, false, " +
                "false",
            layer: 2
        ) { $0[0].attributes[0].editable = true }
        assertDemoRejects(
            "attribute layer.backgroundColor has value_kind color, editable true, accepts_nil false; the list says " +
                "color, true, true",
            layer: 2
        ) { $0[0].attributes[10].acceptsNil = false }
        assertDemoRejects(
            "attribute view.tag has value_kind double, editable true, accepts_nil false; the list says int, true, " +
                "false",
            layer: 2
        ) { $0[1].attributes[5].valueKind = .double }
        assertDemoRejects(
            "attribute view.contentMode has value_kind string, editable true, accepts_nil false; the list says " +
                "string, false, false",
            layer: 2
        ) {
            // A value that fell back to text has to be read-only.
            $0[1].attributes[6].value = .string("99")
            $0[1].attributes[6].valueKind = .string
        }
        // Which groups.
        assertDemoRejects("backs no view and has the groups [\"layer\", \"view\"]", layer: 5) {
            $0.append(contentsOf: self.groups(["view"], for: self.demo().hierarchy.nodes[4]))
        }
        assertDemoRejects("backs a view and has the groups [\"layer\"]", layer: 9) { $0.removeLast() }
        assertDemoRejects("backs a view and has the groups [\"view\", \"layer\"]", layer: 2) { $0.swapAt(0, 1) }
        assertDemoRejects("the label CutawayDemo has the groups [\"layer\", \"view\"]", layer: 3) { $0.removeLast() }
        assertDemoRejects("the scroll view has the groups [\"layer\", \"view\", \"scrollView\", \"label\"]", layer: 6) {
            $0.append(contentsOf: self.groups(["label"], for: self.demo().hierarchy.nodes[5]))
        }
        // Geometry that disagrees with the hierarchy.
        assertDemoRejects("layer.bounds is", layer: 4) {
            self.set("layer.bounds", .rect(WireRect(x: 0, y: 0, width: 300, height: 181)), in: &$0)
        }
        assertDemoRejects("layer.opacity is", layer: 5) { self.set("layer.opacity", .double(1), in: &$0) }
        assertDemoRejects("layer.transform is", layer: 4) {
            var turned = WireTransform.identity
            turned.m12 = 0.5
            self.set("layer.transform", .transform(turned), in: &$0)
        }
        // The known values.
        assertDemoRejects("label.text of the label CutawayDemo is", layer: 3) {
            self.set("label.text", .string("Demo"), in: &$0)
        }
        assertDemoRejects("label.textColor of the label CutawayDemo is", layer: 3) {
            self.set("label.textColor", .color(WireColor(red: 0.01, green: 0, blue: 0, alpha: 1)), in: &$0)
        }
        assertDemoRejects("label.text of the label Scrolled is nil", layer: 7) {
            self.set("label.text", nil, in: &$0)
        }
        assertDemoRejects("view.clipsToBounds of CardView is", layer: 4) {
            self.set("view.clipsToBounds", .bool(false), in: &$0)
        }
        assertDemoRejects("scrollView.contentOffset of the scroll view is", layer: 6) {
            self.set("scrollView.contentOffset", .point(WirePoint(x: 0, y: 0)), in: &$0)
        }
        assertDemoRejects("scrollView.contentSize of the scroll view is", layer: 6) {
            self.set("scrollView.contentSize", .size(WireSize(width: 300, height: 200)), in: &$0)
        }
        assertDemoRejects("scrollView.contentInset of the scroll view is", layer: 6) {
            self.set("scrollView.contentInset", .insets(WireInsets(top: 1, left: 0, bottom: 0, right: 0)), in: &$0)
        }
        assertDemoRejects("expected one label with the text \"Push\", found 2", layer: 7) {
            self.set("label.text", .string("Push"), in: &$0)
        }
        assertDemoRejects("expected one label with the text \"Layout\", found 0", layer: 21) {
            self.set("label.text", .string("Layouts"), in: &$0)
        }
        assertDemoRejects("layer.backgroundColor of the bare layer is nil", layer: 8) {
            self.set("layer.backgroundColor", nil, in: &$0)
        }
        // A layer without its detail.
        let (hierarchy, details) = demo()
        assertRejects("demo: layer 9 (UIView) has no detail") {
            try AttributeChecks.demo(
                details.filter { $0.layerID != 9 },
                hierarchy: hierarchy,
                scene: try DemoScene(hierarchy)
            )
        }
    }

    func test_S_ATTR_07_demoAttributeChecksKnowTheLayoutAttributes() throws {
        let (hierarchy, details) = demo()
        let scene = try DemoScene(hierarchy)
        // A view without an intrinsic size in one dimension reads nil there.
        var noIntrinsicSize = details
        set("view.intrinsicContentSize.width", nil, in: &noIntrinsicSize[1].attributeGroups)
        XCTAssertNoThrow(try AttributeChecks.demo(noIntrinsicSize, hierarchy: hierarchy, scene: scene))

        func index(_ id: String, in groups: [AttributeGroup]) -> Int {
            groups[1].attributes.firstIndex { $0.id == id }!
        }
        assertDemoRejects(
            "attribute view.intrinsicContentSize.width has value_kind double, editable true, accepts_nil false; the " +
                "list says double, false, false",
            layer: 2
        ) { $0[1].attributes[index("view.intrinsicContentSize.width", in: $0)].editable = true }
        assertDemoRejects(
            "attribute view.contentHuggingPriority.vertical has value_kind double, editable false, accepts_nil " +
                "false; the list says double, true, false",
            layer: 2
        ) { $0[1].attributes[index("view.contentHuggingPriority.vertical", in: $0)].editable = false }
        assertDemoRejects("attribute view.hasAmbiguousLayout is nil, which the list does not allow", layer: 2) {
            self.set("view.hasAmbiguousLayout", nil, in: &$0)
        }
        assertDemoRejects("group view has the attributes", layer: 2) {
            $0[1].attributes.remove(at: index("view.translatesAutoresizingMaskIntoConstraints", in: $0))
        }
    }
}
