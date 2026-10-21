import CutawayWire
import Foundation
import XCTest

/// Constraints (protocol 0.4) decode into the project's value types and encode back;
/// cutaway-probe checks what they say.
final class LayoutCodecTests: XCTestCase {
    private func fixture(_ path: String) throws -> Frame {
        try FrameCodec.decode(RepositoryFiles.fixture(path))
    }

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
}
