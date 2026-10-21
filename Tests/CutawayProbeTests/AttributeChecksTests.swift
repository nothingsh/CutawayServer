import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's attribute checks: they accept what a correct server sends and name what is
/// wrong with anything else.
final class AttributeChecksTests: XCTestCase {
    /// The attribute groups the fixture's chunk gives the layer `layerID`.
    private func fixtureGroups(_ path: String, layer layerID: UInt64) throws -> [AttributeGroup] {
        let frame = try Fixtures.frame(path)
        guard case .layerDetailsChunk(let chunk)? = frame.body else {
            throw ProbeFailure("\(path) is not a chunk")
        }
        return try XCTUnwrap(chunk.details.first { $0.layerID == layerID }).attributeGroups
    }

    /// Layer 3 of `layer-details`: three groups that use all eleven kinds of value and a nil, with
    /// sections and limits (1.1). In the `layer` group, `shadowOpacity` is at 3 and `borderColor`
    /// at 6; in the `label` group, `numberOfLines` is at 4 and `textAlignment` at 5; in the `view` group, the nil
    /// `backgroundColor` is at 3 and `isUserInteractionEnabled` at 5.
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
        try assertStructureRejects("attribute layer.shadowOpacity has a number that is not finite") {
            $0[0].attributes[3].value = .double(.nan)
        }
        try assertStructureRejects("attribute layer.frame has a number that is not finite") {
            $0[0].attributes[0].value = .rect(WireRect(x: 0, y: .infinity, width: 1, height: 1))
        }
        try assertStructureRejects("attribute layer.borderColor has a number that is not finite") {
            $0[0].attributes[6].value = .color(WireColor(red: .nan, green: 0, blue: 0, alpha: 1))
        }
        try assertStructureRejects("attribute label.textAlignment is the case \"middle\"") {
            $0[1].attributes[5].value = .enumeration(
                value: 1,
                cases: ["left", "center"],
                caseName: "middle",
                caseValues: [0, 1]
            )
        }
        try assertStructureRejects("attribute label.textAlignment is an enumeration with no cases") {
            $0[1].attributes[5].value = .enumeration(value: 0, cases: [], caseName: "", caseValues: [])
        }
        try assertStructureRejects(
            "attribute label.textAlignment is an enumeration with no cases, or a case without a name"
        ) {
            $0[1].attributes[5].value = .enumeration(
                value: 0,
                cases: ["", "center"],
                caseName: "center",
                caseValues: [0, 1]
            )
        }
    }

    func test_S_PROBE_08_onlyTheAppsGroupsBeginWithApp() throws {
        var row = AttributeGroup(
            id: "app.row",
            title: "Row",
            attributes: [
                Attribute(
                    id: "app.row.title",
                    title: "Title",
                    value: .string("Total"),
                    valueKind: .string,
                    section: .content
                )
            ],
            className: "Demo.CardRow",
            fromApp: true
        )
        XCTAssertNoThrow(try AttributeChecks.structure(try layer3() + [row], name: "layer 3"))
        row.fromApp = false
        assertRejects("group app.row begins with \"app.\" but is not from the app (P-ATTR-19)") {
            try AttributeChecks.structure([row], name: "layer 10")
        }
        try assertStructureRejects("group label is from the app but does not begin with \"app.\" (P-ATTR-19)") {
            $0[1].fromApp = true
        }
    }

    func test_S_ATTR_05_attributeChecksRequireAValueKindThatFits() throws {
        try assertStructureRejects("attribute layer.shadowOpacity has no value_kind (P-ATTR-06)") {
            $0[0].attributes[3].valueKind = .none
        }
        try assertStructureRejects("attribute view.backgroundColor has no value_kind (P-ATTR-06)") {
            // Nil, so only its value_kind says what it takes.
            $0[2].attributes[3].valueKind = .none
        }
        try assertStructureRejects(
            "attribute layer.shadowOpacity is a double value, but its value_kind is int (P-ATTR-06)"
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
            $0[1].attributes[5].value = alignment(1, "center", [0, 1])
        }
        try assertStructureRejects("they must be as many, each once (P-ATTR-07)") {
            $0[1].attributes[5].value = alignment(1, "center", [0, 1, 1])
        }
        try assertStructureRejects("has the value 7 and the case \"center\"") {
            $0[1].attributes[5].value = alignment(7, "center", [0, 1, 2])
        }
        try assertStructureRejects("has the value 2 and the case \"center\"") {
            $0[1].attributes[5].value = alignment(2, "center", [0, 1, 2])
        }
        // Raw values need not start at 0 or be in order.
        var groups = try layer3()
        groups[1].attributes[5].value = alignment(-3, "right", [10, 4, -3])
        XCTAssertNoThrow(try AttributeChecks.structure(groups, name: "layer 3"))
    }

    // MARK: - Protocol 1.1

    func test_S_PROBE_05_attributeChecksKeepToTheSectionsOfTheVersion() throws {
        let groups = try layer3()
        let old = ProtocolVersion(major: 1, minor: 0)
        // P-ATTR-08: a 1.0 peer gets no section 1.0 does not have.
        assertRejects("attribute layer.frame has the section layout, which protocol 1.0 does not have (P-ATTR-08)") {
            try AttributeChecks.structure(groups, name: "layer 3", version: old)
        }
        var unspecified = groups
        for group in unspecified.indices {
            for attribute in unspecified[group].attributes.indices {
                unspecified[group].attributes[attribute].section = .unspecified
            }
        }
        // P-ATTR-14: nor a unit.
        assertRejects("attribute layer.frame has the unit points, which protocol 1.0 does not have (P-ATTR-14)") {
            try AttributeChecks.structure(unspecified, name: "layer 3", version: old)
        }
        for group in unspecified.indices {
            for attribute in unspecified[group].attributes.indices {
                unspecified[group].attributes[attribute].unit = .unspecified
            }
        }
        // P-ATTR-12: nor a cluster, as the table of 1.0 is empty.
        assertRejects(
            "attribute layer.frame is the frame of the cluster geometry, which protocol 1.0 does not name (P-ATTR-12)"
        ) {
            try AttributeChecks.structure(unspecified, name: "layer 3", version: old)
        }
        for group in unspecified.indices {
            for attribute in unspecified[group].attributes.indices {
                unspecified[group].attributes[attribute].cluster = nil
                unspecified[group].attributes[attribute].slot = nil
            }
        }
        XCTAssertNoThrow(try AttributeChecks.structure(unspecified, name: "layer 3", version: old))
        XCTAssertNoThrow(try AttributeChecks.structure(unspecified, name: "layer 3"))
    }

    func test_S_PROBE_05_attributeChecksRequireLimitsOfTheProtocolsShape() throws {
        let atLeastZero = NumberLimit(minimum: 0)
        // Layer 3: layer.frame is read-only, layer.bounds a rectangle, view.isHidden a boolean,
        // label.numberOfLines an integer, layer.shadowOpacity a number.
        try assertStructureRejects("attribute layer.frame has limits, but is read-only (P-ATTR-09)") {
            $0[0].attributes[0].limits = [atLeastZero]
        }
        try assertStructureRejects("attribute view.isHidden has limits, but is a bool value (P-ATTR-09)") {
            $0[2].attributes[1].limits = [atLeastZero]
        }
        try assertStructureRejects("attribute layer.bounds has 3 limits for a value of 4 components (P-ATTR-09)") {
            $0[0].attributes[1].limits = [.free, .free, atLeastZero]
        }
        try assertStructureRejects("limit 0 is exclusive on a side it does not bound (P-ATTR-10)") {
            $0[0].attributes[3].limits = [NumberLimit(maximumIsExclusive: true)]
        }
        try assertStructureRejects("limit 0 has a bound that is not finite (P-ATTR-10)") {
            $0[0].attributes[3].limits = [NumberLimit(maximum: .infinity)]
        }
        try assertStructureRejects("limit 0 leaves no value between 1.0 and 0.0 (P-ATTR-10)") {
            $0[0].attributes[3].limits = [NumberLimit(minimum: 1, maximum: 0)]
        }
        try assertStructureRejects("limit 0 leaves no value between 1.0 and 1.0 (P-ATTR-10)") {
            $0[0].attributes[3].limits = [NumberLimit(minimum: 1, minimumIsExclusive: true, maximum: 1)]
        }
        try assertStructureRejects(
            "attribute label.numberOfLines: limit 0 bounds an integer by a fraction (P-ATTR-10)"
        ) {
            $0[1].attributes[4].limits = [NumberLimit(minimum: 0.5)]
        }
        // A single value between equal bounds is fine.
        var groups = try layer3()
        groups[0].attributes[3].limits = [NumberLimit(minimum: 1, maximum: 1)]
        XCTAssertNoThrow(try AttributeChecks.structure(groups, name: "layer 3"))
    }

    func test_S_PROBE_05_valuesOutsideTheirLimitsAreOnlyReported() throws {
        var groups = try layer3()
        XCTAssertEqual(AttributeChecks.valuesOutsideLimits(groups, name: "layer 3"), [])
        // The app set them itself (P-SET-07): not a failure.
        groups[0].attributes[3].value = .double(1.5)
        groups[0].attributes[1].value = .rect(WireRect(x: -5, y: 0, width: -10, height: 24))
        XCTAssertNoThrow(try AttributeChecks.structure(groups, name: "layer 3"))
        XCTAssertEqual(
            AttributeChecks.valuesOutsideLimits(groups, name: "layer 3"),
            [
                "layer 3: layer.bounds has -10.0 as component 2, outside its limits",
                "layer 3: layer.shadowOpacity has 1.5 as component 0, outside its limits"
            ]
        )
    }

    func test_S_PROBE_06_attributeChecksRequireTheRulesOfDev2() throws {
        // Layer 3 backs a view: layer 0 is `layer`, 1 `label`, 2 `view`.
        XCTAssertNoThrow(try AttributeChecks.structure(try layer3(), name: "layer 3"))
        try assertStructureRejects("layer 3 has both view.alpha and layer.opacity (P-ATTR-11)") {
            $0[0].attributes.append(Attribute(
                id: "layer.opacity",
                title: "Opacity",
                value: .double(1),
                valueKind: .double
            ))
        }
        try assertStructureRejects("has a cluster without a slot, or a slot without a cluster (P-ATTR-12)") {
            $0[0].attributes[0].slot = nil
        }
        try assertStructureRejects("attribute layer.bounds and layer.frame are both the frame of the cluster") {
            $0[0].attributes[1].slot = "frame"
        }
        try assertStructureRejects("is in the section appearance, another attribute of the cluster geometry") {
            $0[0].attributes[1].section = .appearance
        }
        try assertStructureRejects("has no effect because of layer.nothing, which the layer does not have") {
            $0[0].attributes[6].inactiveCause = "layer.nothing"
        }
        try assertStructureRejects("attribute label.text has the unit points, but is a string value (P-ATTR-14)") {
            $0[1].attributes[0].unit = .points
        }
        try assertStructureRejects(
            "attribute layer.borderColor is a CGColor, but has the system name systemBlue (P-ATTR-15)"
        ) {
            $0[0].attributes[6].value = .color(WireColor(red: 0, green: 0, blue: 0, alpha: 1), systemName: "systemBlue")
        }
        try assertStructureRejects("group view has no class_name (P-ATTR-16)") { $0[2].className = nil }
    }

    // MARK: - Protocol 1.2

    func test_S_PROBE_07_clustersAreThoseOfTheNegotiatedTable() throws {
        // Since 1.2 a cluster or slot outside the negotiated table is a failure (P-ATTR-12).
        try assertStructureRejects(
            "view.isUserInteractionEnabled is the enabled of the cluster interaction, "
                + "which protocol 1.2 does not name (P-ATTR-12)"
        ) {
            $0[2].attributes[5].cluster = "interaction"
            $0[2].attributes[5].slot = "enabled"
        }
        // A slot of 1.2 at 1.1.
        var style = Attribute(
            id: "label.fontTextStyle",
            title: "Text Style",
            value: .string("body"),
            valueKind: .string,
            section: .content
        )
        style.cluster = "font"
        style.slot = "textStyle"
        let groups = [AttributeGroup(id: "label", title: "Label", attributes: [style], className: "UILabel")]
        let previous = ProtocolVersion(major: 1, minor: 1)
        XCTAssertNoThrow(try AttributeChecks.structure(groups, name: "layer 3"))
        assertRejects("label.fontTextStyle is the textStyle of the cluster font, which protocol 1.1 does not name") {
            try AttributeChecks.structure(groups, name: "layer 3", version: previous)
        }
        style.cluster = nil
        style.slot = nil
        let unclustered = [AttributeGroup(id: "label", title: "Label", attributes: [style], className: "UILabel")]
        XCTAssertNoThrow(try AttributeChecks.structure(unclustered, name: "layer 3", version: previous))
    }

    func test_S_PROBE_07_accessibilityIsNotSentTo1_1() throws {
        let groups = try layer3()
        XCTAssertTrue(groups.flatMap(\.attributes).contains { $0.section == .accessibility })
        assertRejects("which protocol 1.1 does not have (P-ATTR-08)") {
            try AttributeChecks.structure(groups, name: "layer 3", version: ProtocolVersion(major: 1, minor: 1))
        }
    }

    func test_S_PROBE_07_lightAndDarkComeTogetherAndDiffer() throws {
        let groups = try layer3()
        let tint = try XCTUnwrap(groups[2].attributes.firstIndex { $0.id == "view.tintColor" })
        guard case let .color(value, name, light?, _?, _)? = groups[2].attributes[tint].value else {
            return XCTFail("the fixture's tint has a light and a dark")
        }
        try assertStructureRejects("has one of light and dark without the other (P-ATTR-17)") {
            $0[2].attributes[tint].value = .color(value, systemName: name, light: light, dark: nil)
        }
        try assertStructureRejects("has a light and a dark that are the same in 8 bits (P-ATTR-17)") {
            var near = light
            near.red += 0.001
            $0[2].attributes[tint].value = .color(value, systemName: name, light: light, dark: near)
        }
    }

    func test_S_PROBE_07_referencesAreReadOnlyAndNameLayersOfTheHierarchy() throws {
        let reference = ObjectReference(layerID: 7, className: "Demo.Source", displayClassName: "Source")
        let groups = [
            AttributeGroup(
                id: "scrollView",
                title: "Scroll View",
                attributes: [
                    Attribute(
                        id: "scrollView.delegate",
                        title: "Delegate",
                        value: .layerReference([
                            reference,
                            ObjectReference(layerID: 0, className: "X", displayClassName: "X")
                        ]),
                        valueKind: .layerReference,
                        section: .content
                    )
                ],
                className: "UIScrollView"
            )
        ]
        XCTAssertNoThrow(try AttributeChecks.structure(groups, name: "layer 9", layerIDs: [7]))
        // P-ATTR-03: a 1.1 client gets text instead.
        assertRejects(
            "attribute scrollView.delegate is a layerReference value, which protocol 1.1 does not have (P-ATTR-03)"
        ) {
            try AttributeChecks.structure(groups, name: "layer 9", version: ProtocolVersion(major: 1, minor: 1))
        }
        assertRejects("reference 0 names layer 7, which the hierarchy does not have (P-ATTR-18)") {
            try AttributeChecks.structure(groups, name: "layer 9", layerIDs: [8])
        }
        var editable = groups
        editable[0].attributes[0].editable = true
        assertRejects("attribute scrollView.delegate refers to objects, but is editable (P-ATTR-18)") {
            try AttributeChecks.structure(editable, name: "layer 9", layerIDs: [7])
        }
        var unnamed = groups
        let nameless = ObjectReference(layerID: 0, className: "", displayClassName: "")
        unnamed[0].attributes[0].value = .layerReference([nameless])
        assertRejects("reference 0 has no class_name or display_class_name (P-ATTR-18)") {
            try AttributeChecks.structure(unnamed, name: "layer 9")
        }
    }

    func test_S_PROBE_06_demoAttributeChecksRequireTheList() {
        func first(_ id: String, in groups: inout [AttributeGroup], _ change: (inout Attribute) -> Void) {
            for group in groups.indices {
                for index in groups[group].attributes.indices where groups[group].attributes[index].id == id {
                    change(&groups[group].attributes[index])
                }
            }
        }
        assertDemoRejects("attribute view.alpha has the title \"Alpha\"; the list says \"Opacity\"", layer: 2) {
            first("view.alpha", in: &$0) { $0.title = "Alpha" }
        }
        assertDemoRejects("attribute view.alpha is the nil of the cluster nil", layer: 2) {
            first("view.alpha", in: &$0) { $0.cluster = nil; $0.slot = nil }
        }
        assertDemoRejects(
            "attribute view.alpha has the unit unspecified; the list says fraction (P-ATTR-14)",
            layer: 2
        ) {
            first("view.alpha", in: &$0) { $0.unit = .unspecified }
        }
        assertDemoRejects("group view has the class_name UIControl; the list says UIView (P-ATTR-16)", layer: 2) {
            $0[1].className = "UIControl"
        }
        // A layer of its own has the layer's side of each pair, a view's layer not.
        assertDemoRejects("group layer has the attributes", layer: 5) {
            $0[0].attributes.removeAll { $0.id == "layer.opacity" }
        }
    }

    func test_S_PROBE_05_theListAgreesWithTheFixture() throws {
        // The fixture's assignment is an example (Protocol/fixtures/README.md), but it is the
        // standard catalog's, and so the list's.
        let entries = Dictionary(
            uniqueKeysWithValues: AttributeChecks.list.flatMap { group, entries in
                entries.map { ("\(group).\($0.name)", $0) }
            }
        )
        for attribute in try layer3().flatMap(\.attributes) {
            let entry = try XCTUnwrap(entries[attribute.id], attribute.id)
            XCTAssertEqual(attribute.section, entry.section, attribute.id)
            XCTAssertEqual(attribute.title, entry.title, attribute.id)
            XCTAssertEqual(attribute.cluster, entry.cluster, attribute.id)
            XCTAssertEqual(attribute.slot, entry.slot, attribute.id)
            XCTAssertEqual(attribute.unit, entry.unit, attribute.id)
            let limits = attribute.editable ? AttributeChecks.limits[attribute.id] ?? [] : []
            XCTAssertEqual(attribute.limits, limits, attribute.id)
        }
    }

    func test_S_PROBE_05_demoAttributeChecksRequireTheSectionsAndLimits() {
        assertDemoRejects("attribute view.tag has the section general; the list says identity (P-ATTR-08)", layer: 2) {
            for group in $0.indices {
                for index in $0[group].attributes.indices where $0[group].attributes[index].id == "view.tag" {
                    $0[group].attributes[index].section = .general
                }
            }
        }
        assertDemoRejects("attribute view.alpha has the limits []; the list says", layer: 2) {
            $0[1].attributes[0].limits = []
        }
        assertDemoRejects("attribute layer.bounds has the limits", layer: 2) {
            $0[0].attributes[1].limits = [NumberLimit(minimum: 0)]
        }
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
                "textView",
                "tableView",
                "collectionView",
                "tableViewCell",
                "collectionViewCell"
            ]
        )
        // 60 of version 0.1, the 8 layout attributes of 0.4 and the 45 of protocol 1.2, with
        // `imageView.imageSize` of 0.1 in a cluster now.
        XCTAssertEqual(AttributeChecks.list.values.reduce(0) { $0 + $1.count }, 114)
    }

    func test_S_ATTR_07_theListHasTheLayoutAttributes() {
        let all = AttributeChecks.list["view"]!
        // Before the accessibility of protocol 1.2.
        let view = all.prefix { !$0.name.hasPrefix("accessibility") }
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
        case .layerReference: .layerReference([])
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
            "layer.masksToBounds": .bool(node.masksToBounds),
            "view.isHidden": .bool(node.isHidden),
            "view.alpha": .double(Double(node.opacity)),
            "view.clipsToBounds": .bool(node.masksToBounds)
        ]
        known.merge(values) { $1 }
        let backsView = ids.contains("view")
        return ids.map { groupID in
            AttributeChecks.listedGroup(groupID, backsView: backsView) { id, entry in
                known[id] ?? self.placeholder(entry.kind)
            }
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
        var addressed = hierarchy
        Addresses.add(to: &addressed)
        return (addressed, details)
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
            title: "Content Mode",
            value: .string("99"),
            valueKind: .string,
            section: .appearance
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
            "attribute layer.borderColor has value_kind color, editable true, accepts_nil false; the list says " +
                "color, true, true",
            layer: 2
        ) { $0[0].attributes[8].acceptsNil = false }
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
        assertDemoRejects("view.clipsToBounds is bool(false), but the hierarchy says bool(true)", layer: 4) {
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

extension AttributeChecks {
    /// A group with every attribute of the list for a layer that does or does not back a view,
    /// with the fields of protocol 1.1 the list gives, and the value `value` gives each.
    static func listedGroup(
        _ groupID: String,
        backsView: Bool,
        value: (String, Entry) -> AttributeValue?
    ) -> AttributeGroup {
        let entries = list[groupID]!.filter { !backsView || !$0.onlyWithoutView }
        return AttributeGroup(
            id: groupID,
            title: groupID,
            attributes: entries.map { entry in
                let id = "\(groupID).\(entry.name)"
                return Attribute(
                    id: id,
                    title: entry.title,
                    value: value(id, entry),
                    editable: entry.editable,
                    acceptsNil: entry.acceptsNil,
                    valueKind: entry.kind,
                    section: entry.section,
                    limits: entry.editable ? limits[id] ?? [] : [],
                    cluster: entry.cluster,
                    slot: entry.slot,
                    unit: entry.unit
                )
            },
            className: classNames[groupID]
        )
    }
}
