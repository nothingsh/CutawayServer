import CutawayWire
import Foundation
import XCTest

/// Layer details decode into the project's value types and encode back.
final class DetailsCodecTests: XCTestCase {
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

    /// The pixels of an image, decompressed.
    private func pixels(of image: WireImage) throws -> [UInt8] {
        [UInt8](try (image.data as NSData).decompressed(using: .lzfse) as Data)
    }

    private func request(_ id: UInt64, solo: Bool = false, group: Bool = true, attributes: Bool = false)
        -> LayerDetailRequest {
        LayerDetailRequest(layerID: id, wantSolo: solo, wantGroup: group, wantAttributes: attributes)
    }

    func test_S_SHOT_06_decodesTheLayerDetailsFixture() throws {
        XCTAssertEqual(
            try fixture("layer-details/01-c2s-get-layer-details.bin"),
            Frame(
                requestID: 3,
                body: .getLayerDetails(
                    GetLayerDetails(
                        requests: [
                            request(3, attributes: true),
                            request(4, solo: true),
                            request(99)
                        ],
                        maxTextureDimension: 16384
                    )
                )
            )
        )

        // Two chunks, numbered from 0; three details in the order of the request.
        XCTAssertEqual(try fixture("layer-details/02-s2c-chunk-0.bin").requestID, 3)
        let first = try chunk("layer-details/02-s2c-chunk-0.bin")
        let second = try chunk("layer-details/03-s2c-chunk-1.bin")
        XCTAssertEqual([first.sequence, second.sequence], [0, 1])
        XCTAssertEqual(first.details.map(\.layerID), [3])
        XCTAssertEqual(second.details.map(\.layerID), [4, 99])
        XCTAssertEqual(
            (first.details + second.details).map(\.status),
            [.ok, .ok, .layerNotFound]
        )

        XCTAssertEqual(
            try fixture("layer-details/04-s2c-stream-end.bin"),
            Frame(requestID: 3, body: .streamEnd(StreamEnd(status: .completed, chunkCount: 2)))
        )
    }

    func test_S_SHOT_05_decodesTheFixtureImages() throws {
        let layer3 = try chunk("layer-details/02-s2c-chunk-0.bin").details[0]
        let layer4 = try chunk("layer-details/03-s2c-chunk-1.bin").details[0]

        // Layer 3: only the group, 200x24, opaque red.
        XCTAssertNil(layer3.solo)
        let red = try XCTUnwrap(layer3.group)
        XCTAssertEqual(red.encoding, .bgra8PremultipliedLZFSE)
        XCTAssertEqual([red.pixelWidth, red.pixelHeight, red.bytesPerRow], [200, 24, 800])
        XCTAssertEqual(red.scale, 1)
        let redPixels = try pixels(of: red)
        XCTAssertEqual(redPixels.count, 800 * 24)
        XCTAssertEqual(Array(redPixels[0..<4]), [0x00, 0x00, 0xFF, 0xFF])
        XCTAssertEqual(Array(redPixels.suffix(4)), [0x00, 0x00, 0xFF, 0xFF])

        // Layer 4: both images, 300x180, opaque green.
        let solo = try XCTUnwrap(layer4.solo)
        let group = try XCTUnwrap(layer4.group)
        XCTAssertEqual(solo, group)
        XCTAssertEqual([group.pixelWidth, group.pixelHeight, group.bytesPerRow], [300, 180, 1200])
        let greenPixels = try pixels(of: group)
        XCTAssertEqual(greenPixels.count, 1200 * 180)
        XCTAssertEqual(Array(greenPixels[0..<4]), [0x00, 0xFF, 0x00, 0xFF])
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
                                systemName: "systemBlue"
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
        XCTAssertEqual(attributes.first { $0.id == "view.backgroundColor" }?.value, color(0.2, 0.4, 0.8))
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

    func test_S_SHOT_08_layerNotFoundCarriesNothingElse() throws {
        let missing = try chunk("layer-details/03-s2c-chunk-1.bin").details[1]
        XCTAssertEqual(missing, LayerDetail(layerID: 99, status: .layerNotFound))
        XCTAssertNil(missing.solo)
        XCTAssertNil(missing.group)
        XCTAssertTrue(missing.attributeGroups.isEmpty)
    }

    func test_S_SHOT_04_decodesTheEdgeFixture() throws {
        XCTAssertEqual(
            try fixture("layer-details-edge/01-c2s-get-layer-details.bin"),
            Frame(
                requestID: 4,
                body: .getLayerDetails(
                    GetLayerDetails(
                        requests: [
                            request(3, solo: true),
                            request(8, attributes: true),
                            request(9, attributes: true),
                            request(7, group: false)
                        ],
                        maxTextureDimension: 16384
                    )
                )
            )
        )

        let details = try chunk("layer-details-edge/02-s2c-chunk-0.bin").details
        XCTAssertEqual(details.map(\.layerID), [3, 8, 9, 7])
        XCTAssertEqual(details.map(\.status), [.ok, .ok, .captureFailed, .ok])

        // Layer 3 has no sublayers: the solo was asked for and left out (P-DET-04).
        XCTAssertNil(details[0].solo)
        XCTAssertNotNil(details[0].group)

        // Layer 8: rows are padded (P-IMG-02). 60 pixels are 240 bytes; the row has 256.
        let padded = try XCTUnwrap(details[1].group)
        XCTAssertEqual([padded.pixelWidth, padded.pixelHeight, padded.bytesPerRow], [60, 30, 256])
        let bytes = try pixels(of: padded)
        XCTAssertEqual(bytes.count, 256 * 30)
        XCTAssertEqual(Array(bytes[0..<4]), [0x00, 0x80, 0xFF, 0xFF])
        XCTAssertEqual(Array(bytes[240..<256]), [UInt8](repeating: 0xAA, count: 16))
        // A layer that backs no view: its own attributes of the pairs (P-ATTR-11, 1.1).
        XCTAssertEqual(
            details[1].attributeGroups,
            [
                AttributeGroup(
                    id: "layer",
                    title: "Layer",
                    attributes: [
                        Attribute(
                            id: "layer.hidden",
                            title: "Hidden",
                            value: .bool(false),
                            editable: true,
                            valueKind: .bool,
                            section: .appearance,
                            cluster: "visibility",
                            slot: "hidden"
                        ),
                        Attribute(
                            id: "layer.opacity",
                            title: "Opacity",
                            value: .double(1),
                            editable: true,
                            valueKind: .double,
                            section: .appearance,
                            limits: [NumberLimit(minimum: 0, maximum: 1)],
                            cluster: "visibility",
                            slot: "opacity",
                            unit: .fraction
                        )
                    ],
                    className: "CALayer"
                )
            ]
        )

        // Layer 9 has no size: no image, but the attributes that were asked for (P-DET-03).
        XCTAssertEqual(
            details[2],
            LayerDetail(
                layerID: 9,
                status: .captureFailed,
                attributeGroups: [
                    AttributeGroup(
                        id: "layer",
                        title: "Layer",
                        attributes: [
                            Attribute(
                                id: "layer.frame",
                                title: "Frame",
                                value: .rect(WireRect(x: 300, y: 700, width: 0, height: 0)),
                                valueKind: .rect,
                                section: .layout,
                                cluster: "geometry",
                                slot: "frame",
                                unit: .points
                            )
                        ],
                        className: "CALayer"
                    ),
                    AttributeGroup(
                        id: "view",
                        title: "View",
                        attributes: [
                            Attribute(
                                id: "view.isHidden",
                                title: "Hidden",
                                value: .bool(false),
                                editable: true,
                                valueKind: .bool,
                                section: .appearance,
                                cluster: "visibility",
                                slot: "hidden"
                            )
                        ],
                        className: "UIView"
                    )
                ]
            )
        )

        // Layer 7: nothing was wanted.
        XCTAssertEqual(details[3], LayerDetail(layerID: 7, status: .ok))

        XCTAssertEqual(
            try fixture("layer-details-edge/03-s2c-stream-end.bin"),
            Frame(requestID: 4, body: .streamEnd(StreamEnd(status: .completed, chunkCount: 1)))
        )
    }

    func test_S_SHOT_07_decodesTheCancelledFixture() throws {
        guard
            case .getLayerDetails(let get)? = try fixture(
                "layer-details-cancelled/01-c2s-get-layer-details.bin"
            ).body
        else { return XCTFail("expected GetLayerDetails") }
        XCTAssertEqual(get.requests.map(\.layerID), [2, 3, 4])

        // The cancel has a request_id of its own and names the stream's (P-REQ-01).
        XCTAssertEqual(
            try fixture("layer-details-cancelled/03-c2s-cancel.bin"),
            Frame(requestID: 6, body: .cancel(targetRequestID: 5))
        )
        // One chunk was sent before it.
        let sent = try chunk("layer-details-cancelled/02-s2c-chunk-0.bin")
        XCTAssertEqual(sent.sequence, 0)
        XCTAssertEqual(sent.details.map(\.layerID), [2])
        XCTAssertEqual(
            try fixture("layer-details-cancelled/04-s2c-stream-end.bin"),
            Frame(requestID: 5, body: .streamEnd(StreamEnd(status: .cancelled, chunkCount: 1)))
        )

        // Half-transparent blue, premultiplied: B and A are 0x80.
        let image = try XCTUnwrap(sent.details[0].group)
        XCTAssertEqual(Array(try pixels(of: image)[0..<4]), [0x80, 0x00, 0x00, 0x80])
    }

    func test_S_SHOT_10_decodesTheFailedFixture() throws {
        XCTAssertEqual(
            try fixture("layer-details-failed/02-s2c-app-state.bin"),
            Frame(requestID: 0, body: .appStateChanged(.inactive))
        )
        XCTAssertEqual(
            try fixture("layer-details-failed/03-s2c-stream-end.bin"),
            Frame(
                requestID: 8,
                body: .streamEnd(
                    StreamEnd(
                        status: .failed,
                        chunkCount: 0,
                        error: WireError(
                            code: .appNotActive,
                            message: "the app left the active state during capture"
                        )
                    )
                )
            )
        )
    }

    func test_S_SHOT_06_detailsRoundTrip() throws {
        // Every frame of the four scenarios, decoded, encoded and decoded again.
        for scenario in [
            "layer-details",
            "layer-details-edge",
            "layer-details-cancelled",
            "layer-details-failed"
        ] {
            for direction in ["c2s", "s2c"] {
                for payload in try WireTestSupport.fixtureFrames(scenario: scenario, direction: direction) {
                    let frame = try FrameCodec.decode(payload)
                    XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame, scenario)
                }
            }
        }

        // What the fixtures do not have: a solo without a group, empty lists, an empty string,
        // an enumeration without cases, a request without a limit.
        let image = WireImage(pixelWidth: 1, pixelHeight: 1, bytesPerRow: 4, scale: 3, data: Data([1, 2]))
        let frames = [
            Frame(
                requestID: 9,
                body: .layerDetailsChunk(
                    LayerDetailsChunk(
                        sequence: 41,
                        details: [
                            LayerDetail(layerID: 1, status: .ok, solo: image),
                            LayerDetail(layerID: 2, status: .ok),
                            LayerDetail(
                                layerID: .max,
                                status: .captureFailed,
                                attributeGroups: [
                                    AttributeGroup(id: "empty", title: "Empty", attributes: []),
                                    AttributeGroup(
                                        id: "odd",
                                        title: "",
                                        attributes: [
                                            Attribute(id: "odd.text", title: "Text", value: .string("")),
                                            Attribute(id: "odd.int", title: "Int", value: .int(.min)),
                                            Attribute(
                                                id: "odd.enum",
                                                title: "Enum",
                                                value: .enumeration(
                                                    value: -1,
                                                    cases: [],
                                                    caseName: "",
                                                    caseValues: []
                                                )
                                            )
                                        ]
                                    )
                                ]
                            )
                        ]
                    )
                )
            ),
            Frame(requestID: 10, body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: []))),
            Frame(
                requestID: 11,
                body: .getLayerDetails(GetLayerDetails(requests: [], maxTextureDimension: 0))
            )
        ]
        for frame in frames {
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
        }
    }

    func test_S_SHOT_06_aDetailLargerThanAChunksBudgetRoundTrips() throws {
        // P-DET-06 lets one detail exceed 16 MiB: it travels alone, in one frame. Incompressible
        // data stands in for the worst case.
        var generator = SeededGenerator(seed: 3)
        let block = generator.bytes(count: 64 * 1024)
        var data = Data(capacity: 20 * 1024 * 1024)
        for _ in 0..<320 { data.append(block) }
        let image = WireImage(
            pixelWidth: 2560,
            pixelHeight: 2048,
            bytesPerRow: 10240,
            scale: 2,
            data: data
        )
        let frame = Frame(
            requestID: 7,
            body: .layerDetailsChunk(
                LayerDetailsChunk(
                    sequence: 0,
                    details: [LayerDetail(layerID: 5, status: .ok, solo: image, group: image)]
                )
            )
        )
        let payload = FrameCodec.encode(frame)
        XCTAssertGreaterThan(payload.count, 40 * 1024 * 1024)
        XCTAssertLessThan(UInt32(payload.count), FrameCodec.maximumFrameLength)
        XCTAssertEqual(try FrameCodec.decode(payload), frame)
    }

    // MARK: - Protocol 0.4: constraints (decoded here; cutaway-probe checks them, S-PROBE-04)

    func test_S_PROBE_04_decodesTheLayoutConstraintsFixture() throws {
        let constraintsOnly = { (id: UInt64) in
            LayerDetailRequest(
                layerID: id,
                wantSolo: false,
                wantGroup: false,
                wantAttributes: false,
                wantConstraints: true
            )
        }
        XCTAssertEqual(
            try fixture("layout-constraints/01-c2s-get-layer-details.bin"),
            Frame(
                requestID: 1,
                body: .getLayerDetails(
                    GetLayerDetails(
                        requests: [3, 4, 9, 8, 99].map(constraintsOnly),
                        maxTextureDimension: 16384
                    )
                )
            )
        )

        func view(_ layerID: UInt64) -> LayoutItem { LayoutItem(kind: .view, layerID: layerID) }
        func constraint(
            _ id: UInt64,
            _ first: UInt64,
            _ firstAttribute: LayoutAttribute,
            _ second: LayoutItem?,
            _ secondAttribute: LayoutAttribute,
            constant: Double,
            priority: Float = 1000,
            status: ConstraintStatus = .satisfied,
            className: String = "NSLayoutConstraint",
            identifier: String? = nil
        ) -> LayoutConstraint {
            // P-LAYOUT-09 (1.1): the constraints UIKit generates for an autoresizing mask are the
            // system's; the others the app's.
            LayoutConstraint(
                id: id,
                className: className,
                identifier: identifier,
                firstItem: view(first),
                firstAttribute: firstAttribute,
                relation: .equal,
                secondItem: second,
                secondAttribute: secondAttribute,
                multiplier: 1,
                constant: constant,
                priority: priority,
                status: status,
                origin: className == "NSAutoresizingMaskLayoutConstraint" ? .system : .app
            )
        }
        let safeArea = LayoutItem(
            kind: .layoutGuide,
            layerID: 2,
            guideID: 1,
            className: "UILayoutGuide",
            displayClassName: "UILayoutGuide",
            identifier: "UIViewSafeAreaLayoutGuide",
            guideFrame: WireRect(
                origin: WirePoint(x: 0, y: 59),
                size: WireSize(width: 393, height: 759)
            ),
            guideKind: .safeArea
        )
        let shared = constraint(4, 4, .top, view(3), .bottom, constant: 78)
        let autoresizing = "NSAutoresizingMaskLayoutConstraint"

        XCTAssertEqual(
            try fixture("layout-constraints/02-s2c-chunk-0.bin"),
            Frame(
                requestID: 1,
                body: .layerDetailsChunk(
                    LayerDetailsChunk(
                        sequence: 0,
                        details: [
                            LayerDetail(
                                layerID: 3,
                                status: .ok,
                                constraints: [
                                    constraint(1, 3, .centerX, view(2), .centerX, constant: 0),
                                    constraint(2, 3, .top, safeArea, .top, constant: 49),
                                    constraint(
                                        3,
                                        3,
                                        .width,
                                        nil,
                                        .notAnAttribute,
                                        constant: 240,
                                        priority: 250,
                                        status: .unsatisfied,
                                        identifier: "titleLabel.preferredWidth"
                                    ),
                                    shared
                                ]
                            ),
                            LayerDetail(
                                layerID: 4,
                                status: .ok,
                                constraints: [
                                    shared,
                                    constraint(5, 4, .width, nil, .notAnAttribute, constant: 300),
                                    constraint(6, 4, .height, nil, .notAnAttribute, constant: 180),
                                    constraint(7, 4, .centerX, view(2), .centerX, constant: 0)
                                ]
                            ),
                            LayerDetail(
                                layerID: 9,
                                status: .ok,
                                constraints: [
                                    // UIKit's own shape (P-LAYOUT-07, 0.5): the flexible left margin from
                                    // the superview's side, the fixed top margin without a second item.
                                    constraint(8, 2, .width, view(9), .maxX, constant: 93, className: autoresizing),
                                    constraint(
                                        9,
                                        9,
                                        .width,
                                        nil,
                                        .notAnAttribute,
                                        constant: 0,
                                        className: autoresizing
                                    ),
                                    constraint(
                                        10,
                                        9,
                                        .minY,
                                        nil,
                                        .notAnAttribute,
                                        constant: 700,
                                        className: autoresizing
                                    ),
                                    constraint(
                                        11,
                                        9,
                                        .height,
                                        nil,
                                        .notAnAttribute,
                                        constant: 0,
                                        className: autoresizing
                                    )
                                ]
                            ),
                            LayerDetail(layerID: 8, status: .ok),
                            LayerDetail(layerID: 99, status: .layerNotFound)
                        ]
                    )
                )
            )
        )
        XCTAssertEqual(
            try fixture("layout-constraints/03-s2c-stream-end.bin"),
            Frame(requestID: 1, body: .streamEnd(StreamEnd(status: .completed, chunkCount: 1)))
        )
    }

    func test_S_PROBE_04_constraintsRoundTrip() throws {
        for direction in ["c2s", "s2c"] {
            for payload in try WireTestSupport.fixtureFrames(
                scenario: "layout-constraints",
                direction: direction
            ) {
                let frame = try FrameCodec.decode(payload)
                XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
            }
        }

        // What the fixture does not have: every attribute, relation, kind and status; an
        // `Other` item; a constraint without a first item; empty strings; extreme numbers.
        let other = LayoutItem(kind: .other, className: "_Odd", displayClassName: "Odd")
        let guide = LayoutItem(
            kind: .layoutGuide,
            layerID: .max,
            guideID: .max,
            className: "",
            displayClassName: "",
            identifier: "",
            guideFrame: WireRect(origin: WirePoint(x: -1, y: -2), size: WireSize(width: 0, height: 0))
        )
        let relations: [LayoutRelation] = [.equal, .lessThanOrEqual, .greaterThanOrEqual]
        let statuses: [ConstraintStatus] = [.unknown, .satisfied, .unsatisfied]
        var constraints = LayoutAttribute.allCases.enumerated().map { index, attribute in
            LayoutConstraint(
                id: UInt64(index + 1),
                className: "C",
                identifier: index.isMultiple(of: 2) ? nil : "id",
                firstItem: index.isMultiple(of: 3) ? other : guide,
                firstAttribute: attribute,
                relation: relations[index % 3],
                secondItem: LayoutItem(kind: .view, layerID: 7),
                secondAttribute: LayoutAttribute.allCases.reversed()[index],
                multiplier: -0.5,
                constant: -.greatestFiniteMagnitude,
                priority: 1,
                status: statuses[index % 3]
            )
        }
        constraints.append(
            LayoutConstraint(
                id: .max,
                className: nil,
                firstItem: nil,
                firstAttribute: .notAnAttribute,
                relation: .equal,
                multiplier: 0,
                constant: 0,
                priority: 0,
                status: .unknown
            )
        )
        let frames = [
            Frame(
                requestID: 12,
                body: .layerDetailsChunk(
                    LayerDetailsChunk(
                        sequence: 0,
                        details: [LayerDetail(layerID: 1, status: .ok, constraints: constraints)]
                    )
                )
            ),
            Frame(
                requestID: 13,
                body: .getLayerDetails(
                    GetLayerDetails(
                        requests: [
                            LayerDetailRequest(
                                layerID: 1,
                                wantSolo: true,
                                wantGroup: false,
                                wantAttributes: true,
                                wantConstraints: true
                            ),
                            LayerDetailRequest(layerID: 2, wantSolo: false, wantGroup: true, wantAttributes: false)
                        ],
                        maxTextureDimension: 0
                    )
                )
            )
        ]
        for frame in frames {
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
        }
        XCTAssertEqual(LayoutAttribute.allCases.count, 25)
        XCTAssertEqual(LayoutAttribute.centerYWithinMargins.rawValue, 20)
        // 0.5 (P-LAYOUT-07).
        XCTAssertEqual(LayoutAttribute.minX.rawValue, 32)
        XCTAssertEqual(LayoutAttribute.maxY.rawValue, 37)
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

    func test_S_ATTR_09_componentsFollowTheOrderOfTheFields() {
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
