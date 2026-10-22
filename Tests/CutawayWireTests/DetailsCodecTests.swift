import CutawayWire
import Foundation
import XCTest

/// Layer details decode into the project's value types and encode back. Their attributes are
/// in AttributesCodecTests, their constraints in LayoutCodecTests.
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
                            request(99),
                            request(6, group: false, attributes: true),
                            request(10, solo: true, attributes: true),
                            request(13, attributes: true)
                        ],
                        maxTextureDimension: 16384
                    )
                )
            )
        )

        // Two chunks, numbered from 0; six details in the order of the request.
        XCTAssertEqual(try fixture("layer-details/02-s2c-chunk-0.bin").requestID, 3)
        let first = try chunk("layer-details/02-s2c-chunk-0.bin")
        let second = try chunk("layer-details/03-s2c-chunk-1.bin")
        XCTAssertEqual([first.sequence, second.sequence], [0, 1])
        XCTAssertEqual(first.details.map(\.layerID), [3])
        XCTAssertEqual(second.details.map(\.layerID), [4, 99, 6, 10, 13])
        XCTAssertEqual(
            (first.details + second.details).map(\.status),
            [.ok, .ok, .layerNotFound, .ok, .ok, .excluded]
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

    func test_S_SHOT_12_decodesTheVirtualNodeAndTheExcludedLayer() throws {
        // Protocol 1.2 (Protocol/fixtures/README.md, "The host app's group and registered colors").
        let details = try chunk("layer-details/03-s2c-chunk-1.bin").details
        let row = try XCTUnwrap(details.first { $0.layerID == 10 })
        XCTAssertEqual(row.status, .ok)
        XCTAssertNil(row.solo)
        XCTAssertNil(row.group)
        XCTAssertEqual(row.attributeGroups.map(\.id), ["app.row"])
        XCTAssertEqual(row.attributeGroups.map(\.fromApp), [true])
        XCTAssertEqual(row.attributeGroups.first?.className, "Demo.CardRow")
        XCTAssertEqual(
            row.attributeGroups.first?.attributes.last?.value,
            .color(WireColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1), name: "brandBlue")
        )
        let excluded = try XCTUnwrap(details.first { $0.layerID == 13 })
        XCTAssertEqual(excluded.status, .excluded)
        XCTAssertNil(excluded.group)
        XCTAssertEqual(excluded.attributeGroups.map(\.id), ["view"])
        XCTAssertEqual(excluded.attributeGroups.map(\.fromApp), [false])
    }

    func test_S_SHOT_13_newDetailFieldsRoundTrip() throws {
        let detail = LayerDetail(
            layerID: 5,
            status: .excluded,
            attributeGroups: [
                AttributeGroup(
                    id: "app.chart",
                    title: "Chart",
                    attributes: [
                        Attribute(
                            id: "app.chart.color",
                            title: "Color",
                            value: .color(WireColor(red: 1, green: 0, blue: 0, alpha: 1), name: "brand"),
                            valueKind: .color
                        )
                    ],
                    className: "Demo.Chart",
                    fromApp: true
                )
            ]
        )
        let frame = Frame(requestID: 2, body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: [detail])))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
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
}
