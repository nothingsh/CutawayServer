import CutawayWire
import Foundation
import XCTest

/// Attributes and the messages that change them decode into the project's value types and
/// encode back.
final class AttributesCodecTests: XCTestCase {
    private func fixture(_ path: String) throws -> Frame {
        try FrameCodec.decode(RepositoryFiles.fixture(path))
    }

    /// The chunk in a fixture frame.
    private func chunk(_ path: String, file: StaticString = #filePath, line: UInt = #line) throws -> LayerDetailsChunk {
        guard case .layerDetailsChunk(let chunk)? = try fixture(path).body else {
            XCTFail("\(path) is not a LayerDetailsChunk", file: file, line: line)
            return LayerDetailsChunk(sequence: 0, details: [])
        }
        return chunk
    }

    func test_S_SHOT_06_decodesEveryKindOfAttributeValue() throws {
        let groups = try chunk("layer-details/02-s2c-chunk-0.bin").details[0].attributeGroups
        // P-ATTR-06: every attribute says what it takes and whether it can be changed;
        // P-ATTR-08 to 10 (1.1): where it is shown, and the values a change may have; P-ATTR-12
        // to 16 (1.1): its cluster, unit and inactive cause, a system color's name, and the
        // class that declares each group. P-ATTR-02: no value means nil (the background).
        XCTAssertEqual(
            groups,
            [
                AttributeGroup(
                    id: "layer",
                    title: "Layer",
                    attributes: [
                        Attribute(
                            id: "layer.frame",
                            title: "Frame",
                            value: .rect(WireRect(x: 96.5, y: 108, width: 200, height: 24)),
                            valueKind: .rect,
                            section: .layout,
                            cluster: "geometry",
                            slot: "frame",
                            unit: .points
                        ),
                        Attribute(
                            id: "layer.bounds",
                            title: "Bounds",
                            value: .rect(WireRect(x: 0, y: 0, width: 200, height: 24)),
                            editable: true,
                            valueKind: .rect,
                            section: .layout,
                            limits: [.free, .free, NumberLimit(minimum: 0), NumberLimit(minimum: 0)],
                            cluster: "geometry",
                            slot: "bounds",
                            unit: .points
                        ),
                        Attribute(
                            id: "layer.position",
                            title: "Position",
                            value: .point(WirePoint(x: 196.5, y: 120)),
                            editable: true,
                            valueKind: .point,
                            section: .layout,
                            cluster: "geometry",
                            slot: "position",
                            unit: .points
                        ),
                        Attribute(
                            id: "layer.shadowOpacity",
                            title: "Shadow Opacity",
                            value: .double(0),
                            editable: true,
                            valueKind: .double,
                            section: .appearance,
                            limits: [NumberLimit(minimum: 0, maximum: 1)],
                            cluster: "shadow",
                            slot: "opacity",
                            unit: .fraction
                        ),
                        Attribute(
                            id: "layer.shadowOffset",
                            title: "Shadow Offset",
                            value: .size(WireSize(width: 0, height: -3)),
                            editable: true,
                            valueKind: .size,
                            section: .appearance,
                            cluster: "shadow",
                            slot: "offset",
                            inactiveCause: "layer.shadowOpacity",
                            unit: .points
                        ),
                        Attribute(
                            id: "layer.borderWidth",
                            title: "Border Width",
                            value: .double(0),
                            editable: true,
                            valueKind: .double,
                            section: .appearance,
                            limits: [NumberLimit(minimum: 0)],
                            cluster: "border",
                            slot: "width",
                            unit: .points
                        ),
                        Attribute(
                            id: "layer.borderColor",
                            title: "Border Color",
                            value: .color(WireColor(red: 0, green: 0, blue: 0, alpha: 1)),
                            editable: true,
                            acceptsNil: true,
                            valueKind: .color,
                            section: .appearance,
                            cluster: "border",
                            slot: "color",
                            inactiveCause: "layer.borderWidth"
                        ),
                        Attribute(
                            id: "layer.transform",
                            title: "Transform",
                            value: .transform(.identity),
                            editable: true,
                            valueKind: .transform,
                            section: .layout,
                            cluster: "geometry",
                            slot: "transform"
                        )
                    ],
                    className: "CALayer"
                ),
                AttributeGroup(
                    id: "label",
                    title: "Label",
                    attributes: [
                        Attribute(
                            id: "label.text",
                            title: "Text",
                            value: .string("Hello"),
                            editable: true,
                            acceptsNil: true,
                            valueKind: .string,
                            section: .content
                        ),
                        Attribute(
                            id: "label.fontSize",
                            title: "Font Size",
                            value: .double(17),
                            editable: true,
                            valueKind: .double,
                            section: .content,
                            limits: [NumberLimit(minimum: 0, minimumIsExclusive: true)],
                            cluster: "font",
                            slot: "size",
                            unit: .points
                        ),
                        Attribute(
                            id: "label.fontTextStyle",
                            title: "Text Style",
                            value: .string("body"),
                            valueKind: .string,
                            section: .content,
                            cluster: "font",
                            slot: "textStyle"
                        ),
                        Attribute(
                            id: "label.adjustsFontForContentSizeCategory",
                            title: "Adjusts to Text Size",
                            value: .bool(true),
                            editable: true,
                            valueKind: .bool,
                            section: .content,
                            cluster: "font",
                            slot: "scalable"
                        ),
                        Attribute(
                            id: "label.numberOfLines",
                            title: "Lines",
                            value: .int(1),
                            editable: true,
                            valueKind: .int,
                            section: .content,
                            limits: [NumberLimit(minimum: 0)],
                            cluster: "lines",
                            slot: "count"
                        ),
                        Attribute(
                            id: "label.textAlignment",
                            title: "Text Alignment",
                            value: .enumeration(
                                value: 1,
                                cases: ["left", "center", "right", "justified", "natural"],
                                caseName: "center",
                                caseValues: [0, 1, 2, 3, 4]
                            ),
                            editable: true,
                            valueKind: .enumeration,
                            section: .content
                        )
                    ],
                    className: "UILabel"
                ),
                AttributeGroup(
                    id: "view",
                    title: "View",
                    attributes: [
                        Attribute(
                            id: "view.tag",
                            title: "Tag",
                            value: .int(0),
                            editable: true,
                            valueKind: .int,
                            section: .identity
                        ),
                        Attribute(
                            id: "view.isHidden",
                            title: "Hidden",
                            value: .bool(false),
                            editable: true,
                            valueKind: .bool,
                            section: .appearance,
                            cluster: "visibility",
                            slot: "hidden"
                        ),
                        Attribute(
                            id: "view.alpha",
                            title: "Opacity",
                            value: .double(1),
                            editable: true,
                            valueKind: .double,
                            section: .appearance,
                            limits: [NumberLimit(minimum: 0, maximum: 1)],
                            cluster: "visibility",
                            slot: "opacity",
                            unit: .fraction
                        ),
                        Attribute(
                            id: "view.backgroundColor",
                            title: "Background",
                            value: nil,
                            editable: true,
                            acceptsNil: true,
                            valueKind: .color,
                            section: .appearance
                        ),
                        Attribute(
                            id: "view.tintColor",
                            title: "Tint",
                            value: .color(
                                WireColor(red: 0, green: 0.47843137, blue: 1, alpha: 1),
                                systemName: "systemBlue",
                                light: WireColor(red: 0, green: 0.47843137, blue: 1, alpha: 1),
                                dark: WireColor(red: 0.039215688, green: 0.5176471, blue: 1, alpha: 1)
                            ),
                            editable: true,
                            acceptsNil: true,
                            valueKind: .color,
                            section: .appearance
                        ),
                        Attribute(
                            id: "view.isUserInteractionEnabled",
                            title: "User Interaction",
                            value: .bool(false),
                            editable: true,
                            valueKind: .bool,
                            section: .behavior
                        ),
                        Attribute(
                            id: "view.layoutMargins",
                            title: "Layout Margins",
                            value: .insets(WireInsets(top: 8, left: 8, bottom: 8, right: 8)),
                            editable: true,
                            valueKind: .insets,
                            section: .layout,
                            unit: .points
                        ),
                        Attribute(
                            id: "view.accessibilityLabel",
                            title: "Label",
                            value: .string("Welcome"),
                            editable: true,
                            acceptsNil: true,
                            valueKind: .string,
                            section: .accessibility
                        )
                    ],
                    className: "UIView"
                )
            ]
        )
    }

    func test_S_CONN_12_decodesObjectReferences() throws {
        // Layer 6 of `layer-details` (1.2, P-ATTR-18): a view controller by its root view's
        // layer, and two objects that are not views.
        let layer6 = try XCTUnwrap(try chunk("layer-details/03-s2c-chunk-1.bin").details.first { $0.layerID == 6 })
        XCTAssertEqual(layer6.layerID, 6)
        XCTAssertEqual(
            layer6.attributeGroups,
            [
                AttributeGroup(
                    id: "scrollView",
                    title: "Scroll View",
                    attributes: [
                        Attribute(
                            id: "scrollView.delegate",
                            title: "Delegate",
                            value: .layerReference([
                                ObjectReference(
                                    layerID: 2,
                                    className: "Demo.HomeViewController",
                                    displayClassName: "HomeViewController"
                                )
                            ]),
                            valueKind: .layerReference,
                            section: .content
                        )
                    ],
                    className: "UIScrollView"
                ),
                AttributeGroup(
                    id: "view",
                    title: "View",
                    attributes: [
                        Attribute(
                            id: "view.gestureRecognizers",
                            title: "Gesture Recognizers",
                            value: .layerReference([
                                ObjectReference(
                                    layerID: 0,
                                    className: "UIScrollViewDelayedTouchesBeganGestureRecognizer",
                                    displayClassName: "UIScrollViewDelayedTouchesBeganGestureRecognizer"
                                ),
                                ObjectReference(
                                    layerID: 0,
                                    className: "UIScrollViewPanGestureRecognizer",
                                    displayClassName: "UIScrollViewPanGestureRecognizer"
                                )
                            ]),
                            valueKind: .layerReference,
                            section: .behavior
                        )
                    ],
                    className: "UIView"
                )
            ]
        )
    }

    func test_S_ATTR_05_decodesTheSetAttributeFixture() throws {
        func color(_ red: Float, _ green: Float, _ blue: Float) -> AttributeValue {
            .color(WireColor(red: red, green: green, blue: blue, alpha: 1))
        }
        XCTAssertEqual(
            try fixture("set-attribute/01-c2s-set-text.bin"),
            Frame(
                requestID: 1,
                body: .setAttribute(
                    SetAttribute(layerID: 3, attributeID: "label.text", value: .string("Welcome back"))
                )
            )
        )
        // P-SET-02: an enumeration may carry only its value.
        XCTAssertEqual(
            try fixture("set-attribute/03-c2s-set-alignment.bin"),
            Frame(
                requestID: 2,
                body: .setAttribute(
                    SetAttribute(
                        layerID: 3,
                        attributeID: "label.textAlignment",
                        value: .enumeration(value: 2, cases: [], caseName: "", caseValues: [])
                    )
                )
            )
        )
        XCTAssertEqual(
            try fixture("set-attribute/05-c2s-set-background.bin"),
            Frame(
                requestID: 3,
                body: .setAttribute(
                    SetAttribute(layerID: 4, attributeID: "view.backgroundColor", value: color(0.2, 0.4, 0.8))
                )
            )
        )
        // No value sets nil.
        XCTAssertEqual(
            try fixture("set-attribute/09-c2s-clear-background.bin"),
            Frame(
                requestID: 5,
                body: .setAttribute(SetAttribute(layerID: 4, attributeID: "view.backgroundColor", value: nil))
            )
        )

        // P-SET-01: the whole layer's attributes, read after the change.
        guard case .setAttributeResult(let text)? = try fixture("set-attribute/02-s2c-result.bin").body
        else { return XCTFail("expected SetAttributeResult") }
        XCTAssertEqual(text.layerID, 3)
        XCTAssertEqual(text.attributeGroups.map(\.id), ["layer", "label", "view"])
        XCTAssertEqual(
            text.attributeGroups[1].attributes[0],
            Attribute(
                id: "label.text",
                title: "Text",
                value: .string("Welcome back"),
                editable: true,
                acceptsNil: true,
                valueKind: .string,
                section: .content
            )
        )

        // P-ATTR-11 (1.1): layer 4 backs a view, so it has the view's side of each pair.
        guard case .setAttributeResult(let alpha)? = try fixture("set-attribute/08-s2c-result.bin").body
        else { return XCTFail("expected SetAttributeResult") }
        let attributes = alpha.attributeGroups.flatMap(\.attributes)
        XCTAssertEqual(attributes.first { $0.id == "view.alpha" }?.value, .double(0.5))
        XCTAssertFalse(attributes.contains { $0.id == "layer.opacity" })
        // P-ATTR-20 (1.2): the value set equals the color the host app registered as brandBlue.
        XCTAssertEqual(
            attributes.first { $0.id == "view.backgroundColor" }?.value,
            .color(WireColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), name: "brandBlue")
        )
        XCTAssertFalse(attributes.contains { $0.id == "layer.backgroundColor" })
        // P-ATTR-12 (1.1): one cluster across two groups.
        XCTAssertEqual(
            attributes.filter { $0.cluster == "corners" }.map { [$0.id, $0.slot] },
            [["layer.cornerRadius", "radius"], ["view.clipsToBounds", "clip"]]
        )

        guard case .setAttributeResult(let cleared)? = try fixture("set-attribute/10-s2c-result.bin").body
        else { return XCTFail("expected SetAttributeResult") }
        let background = cleared.attributeGroups.flatMap(\.attributes).first {
            $0.id == "view.backgroundColor"
        }
        XCTAssertEqual(
            background,
            Attribute(
                id: "view.backgroundColor",
                title: "Background",
                value: nil,
                editable: true,
                acceptsNil: true,
                valueKind: .color,
                section: .appearance
            )
        )
    }

    func test_S_ATTR_05_decodesTheRejectedFixture() throws {
        let expected: [(String, ErrorCode)] = [
            ("02-s2c-error.bin", .layerNotFound),
            ("04-s2c-error.bin", .attributeNotEditable),
            ("06-s2c-error.bin", .invalidAttributeValue),
            ("08-s2c-error.bin", .invalidAttributeValue),
            ("10-s2c-error.bin", .invalidAttributeValue),
            ("12-s2c-error.bin", .invalidAttributeValue),
            // P-ATTR-11 (1.1): the attribute of a pair that is left out.
            ("14-s2c-error.bin", .attributeNotEditable)
        ]
        for (file, code) in expected {
            guard case .error(let error)? = try fixture("set-attribute-rejected/\(file)").body else {
                return XCTFail("\(file) is not an Error")
            }
            XCTAssertEqual(error.code, code, file)
        }
        XCTAssertEqual(
            try fixture("set-attribute-rejected/07-c2s-set-nil.bin").body,
            .setAttribute(SetAttribute(layerID: 3, attributeID: "label.numberOfLines", value: nil))
        )
        XCTAssertEqual(
            try fixture("set-attribute-rejected/13-c2s-set-paired-layer-attribute.bin").body,
            .setAttribute(SetAttribute(layerID: 3, attributeID: "layer.opacity", value: .double(0.5)))
        )
    }

    func test_S_ATTR_06_editingMessagesRoundTrip() throws {
        let groups = [
            AttributeGroup(
                id: "view",
                title: "View",
                attributes: [
                    Attribute(
                        id: "view.contentMode",
                        title: "Content Mode",
                        value: .enumeration(
                            value: -7,
                            cases: ["a", "b"],
                            caseName: "a",
                            caseValues: [-7, .max]
                        ),
                        editable: true,
                        valueKind: .enumeration
                    ),
                    Attribute(
                        id: "view.tintColor",
                        title: "Tint Color",
                        value: nil,
                        editable: true,
                        acceptsNil: true,
                        valueKind: .color
                    ),
                    Attribute(id: "view.odd", title: "Odd", value: .string("99"), valueKind: .string)
                ]
            )
        ]
        let frames = [
            Frame(requestID: 1, body: .setAttribute(SetAttribute(layerID: .max, attributeID: "", value: nil))),
            Frame(
                requestID: 2,
                body: .setAttribute(
                    SetAttribute(layerID: 1, attributeID: "view.alpha", value: .double(-0.5))
                )
            ),
            Frame(requestID: 3, body: .setAttributeResult(SetAttributeResult(layerID: 4, attributeGroups: groups))),
            Frame(requestID: 4, body: .setAttributeResult(SetAttributeResult(layerID: 0, attributeGroups: [])))
        ]
        for frame in frames {
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
        }
    }

    func test_S_ATTR_09_numberLimitAdmitsByItsBounds() {
        let unit = NumberLimit(minimum: 0, maximum: 1)
        XCTAssertTrue(unit.admits(0))
        XCTAssertTrue(unit.admits(1))
        XCTAssertFalse(unit.admits(-0.000_001))
        XCTAssertFalse(unit.admits(1.000_001))

        let positive = NumberLimit(minimum: 0, minimumIsExclusive: true)
        XCTAssertFalse(positive.admits(0))
        XCTAssertTrue(positive.admits(0.000_001))
        XCTAssertTrue(positive.admits(1e300))

        let belowTen = NumberLimit(maximum: 10, maximumIsExclusive: true)
        XCTAssertTrue(belowTen.admits(-1e300))
        XCTAssertFalse(belowTen.admits(10))

        XCTAssertTrue(NumberLimit.free.admits(-1e300))
        XCTAssertTrue(NumberLimit.free.admits(1e300))
    }

    func test_S_ATTR_09_limitsApplyToEveryComponentOrOneEach() {
        let atLeastZero = NumberLimit(minimum: 0)
        // P-ATTR-09: one entry for every component; one per component; any other count is none.
        XCTAssertEqual(NumberLimit.perComponent([atLeastZero], count: 4), Array(repeating: atLeastZero, count: 4))
        XCTAssertEqual(
            NumberLimit.perComponent([.free, .free, atLeastZero, atLeastZero], count: 4),
            [.free, .free, atLeastZero, atLeastZero]
        )
        XCTAssertNil(NumberLimit.perComponent([], count: 4))
        XCTAssertNil(NumberLimit.perComponent([atLeastZero, atLeastZero], count: 4))
        XCTAssertNil(NumberLimit.perComponent([atLeastZero, atLeastZero], count: 1))
    }

    func test_S_ATTR_09_componentsFollowTheKindAndTheOrderOfTheFields() {
        XCTAssertEqual(AttributeValue.int(3).components, [3])
        XCTAssertEqual(AttributeValue.point(WirePoint(x: 1, y: 2)).components, [1, 2])
        XCTAssertEqual(AttributeValue.size(WireSize(width: 1, height: 2)).components, [1, 2])
        XCTAssertEqual(AttributeValue.rect(WireRect(x: 1, y: 2, width: 3, height: 4)).components, [1, 2, 3, 4])
        XCTAssertEqual(
            AttributeValue.insets(WireInsets(top: 1, left: 2, bottom: 3, right: 4)).components,
            [1, 2, 3, 4]
        )
        XCTAssertEqual(AttributeValue.transform(.identity).components.count, 16)
        XCTAssertEqual(AttributeValue.bool(true).components, [])
        XCTAssertEqual(AttributeValue.string("1").components, [])

        // The count and names of the components follow the kind.
        let samples: [AttributeValue] = [
            .bool(true),
            .int(3),
            .double(0.5),
            .string("1"),
            .color(WireColor(red: 1, green: 0, blue: 0, alpha: 1)),
            .point(WirePoint(x: 1, y: 2)),
            .size(WireSize(width: 1, height: 2)),
            .rect(WireRect(x: 1, y: 2, width: 3, height: 4)),
            .insets(WireInsets(top: 1, left: 2, bottom: 3, right: 4)),
            .transform(.identity),
            .enumeration(value: 0, cases: ["a"], caseName: "a", caseValues: [0]),
            .layerReference([])
        ]
        for value in samples {
            let kind = value.kind
            // P-ATTR-09: limits apply to the numbers of the numeric kinds only, so a colour's
            // channels are not components here.
            XCTAssertEqual(kind.componentCount, kind.isNumeric ? value.components.count : 0, "\(kind)")
            XCTAssertEqual(kind.componentNames.count, kind.componentCount, "\(kind)")
        }
        XCTAssertEqual(AttributeValueKind.none.componentCount, 0)
        XCTAssertEqual(AttributeValueKind.none.componentNames, [])
        XCTAssertEqual(AttributeValueKind.int.componentNames, ["value"])
        XCTAssertEqual(AttributeValueKind.double.componentNames, ["value"])
        XCTAssertEqual(AttributeValueKind.point.componentNames, ["x", "y"])
        XCTAssertEqual(AttributeValueKind.size.componentNames, ["width", "height"])
        XCTAssertEqual(AttributeValueKind.rect.componentNames, ["x", "y", "width", "height"])
        XCTAssertEqual(AttributeValueKind.insets.componentNames, ["top", "left", "bottom", "right"])
        XCTAssertEqual(AttributeValueKind.transform.componentCount, 16)
        XCTAssertEqual(AttributeValueKind.transform.componentNames.prefix(5), ["m11", "m12", "m13", "m14", "m21"])
        XCTAssertEqual(AttributeValueKind.transform.componentNames.last, "m44")
    }

    func test_S_ATTR_08_sectionsAndLimitsRoundTrip() throws {
        let attributes = AttributeSection.allCases.map { section in
            Attribute(
                id: "layer.zPosition",
                title: "Z Position",
                value: .double(0),
                editable: true,
                valueKind: .double,
                section: section,
                limits: [NumberLimit(minimum: -1, minimumIsExclusive: true, maximum: 1, maximumIsExclusive: true)]
            )
        }
        let frame = Frame(
            requestID: 2,
            body: .setAttributeResult(
                SetAttributeResult(
                    layerID: 1,
                    attributeGroups: [AttributeGroup(id: "layer", title: "Layer", attributes: attributes)]
                )
            )
        )
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
    }
}
