import CutawayWire
import Foundation
import XCTest

/// What a peer that works at an older minor version may receive
/// (S-CONN-12; PROTOCOL.md, P-HELLO-04, P-LAYOUT-08). The versions are those of
/// protocol 1, and every value is named from 1.0 on.
final class VersionAdaptationTests: XCTestCase {
    private func version(_ minor: UInt16) -> ProtocolVersion {
        ProtocolVersion(major: 1, minor: minor)
    }

    private func view(_ layerID: UInt64) -> LayoutItem { LayoutItem(kind: .view, layerID: layerID) }

    private func constraint(
        _ id: UInt64,
        _ first: UInt64,
        _ firstAttribute: LayoutAttribute,
        _ second: UInt64?,
        _ secondAttribute: LayoutAttribute,
        constant: Double
    ) -> LayoutConstraint {
        LayoutConstraint(
            id: id,
            className: "NSAutoresizingMaskLayoutConstraint",
            identifier: "c\(id)",
            firstItem: view(first),
            firstAttribute: firstAttribute,
            relation: .lessThanOrEqual,
            secondItem: second.map(view),
            secondAttribute: secondAttribute,
            multiplier: 2,
            constant: constant,
            priority: 750,
            status: .unknown
        )
    }

    /// UIKit's shapes, and one with public attributes only.
    private var detail: LayerDetail {
        LayerDetail(
            layerID: 9,
            status: .ok,
            group: WireImage(pixelWidth: 1, pixelHeight: 1, bytesPerRow: 4, scale: 1, data: Data([1, 2, 3, 4])),
            attributeGroups: [AttributeGroup(id: "layer", title: "Layer", attributes: [])],
            constraints: [
                constraint(1, 9, .minX, nil, .notAnAttribute, constant: 300),
                constraint(2, 9, .minY, nil, .notAnAttribute, constant: 700),
                constraint(3, 2, .width, 9, .maxX, constant: 93),
                constraint(4, 2, .height, 9, .maxY, constant: 40),
                constraint(5, 9, .leading, 2, .trailingMargin, constant: 8),
                constraint(6, 9, .width, nil, .notAnAttribute, constant: 0)
            ]
        )
    }

    func test_S_CONN_12_negotiatedVersionIsTheLowerMinor() {
        let current = ProtocolVersion.current
        XCTAssertEqual(current, version(1))
        XCTAssertEqual(current.negotiated(with: version(0)), version(0))
        XCTAssertEqual(current.negotiated(with: version(1)), version(1))
        XCTAssertEqual(current.negotiated(with: version(2)), version(1))
        XCTAssertEqual(version(2).negotiated(with: version(1)), version(1))
        XCTAssertEqual(version(1).negotiated(with: version(3)), version(1))
    }

    func test_S_CONN_12_everyAttributeHasItsMinorVersion() {
        // Protocol 1.0 names all of them, the autoresizing mask's included.
        for attribute in LayoutAttribute.allCases {
            XCTAssertEqual(attribute.minorVersion, 0, "\(attribute)")
        }
        XCTAssertEqual(LayoutAttribute.allCases.count, 25)
    }

    func test_S_CONN_12_everyPeerOfProtocol1GetsTheAttributes() {
        let original = detail
        // Every field, the autoresizing mask's attributes included, stays as it was.
        for minor: UInt16 in [0, 1, 2] {
            XCTAssertEqual(original.adapted(to: version(minor)), original, "1.\(minor)")
        }
        XCTAssertEqual(original.constraints[0].firstAttribute, .minX)

        let plain = LayerDetail(layerID: 3, status: .layerNotFound)
        XCTAssertEqual(plain.adapted(to: version(0)), plain)
    }

    func test_S_CONN_12_everySectionHasItsMinorVersion() {
        // Protocol 1.1 added every section but the default (P-ATTR-08).
        XCTAssertEqual(AttributeSection.unspecified.minorVersion, 0)
        for section in AttributeSection.allCases where section != .unspecified {
            XCTAssertEqual(section.minorVersion, 1, "\(section)")
        }
    }

    /// One attribute of each section, with limits.
    private var sectionedGroups: [AttributeGroup] {
        let limits = [NumberLimit(minimum: 0)]
        return [
            AttributeGroup(
                id: "view",
                title: "View",
                attributes: AttributeSection.allCases.map { section in
                    Attribute(
                        id: "view.tag",
                        title: "Tag",
                        value: .int(0),
                        editable: true,
                        valueKind: .int,
                        section: section,
                        limits: limits
                    )
                }
            )
        ]
    }

    func test_S_ATTR_08_aProtocol1_0PeerGetsUnspecifiedSections() {
        let detail = LayerDetail(layerID: 9, status: .ok, attributeGroups: sectionedGroups)
        let result = SetAttributeResult(layerID: 9, attributeGroups: sectionedGroups)

        // 1.0 has no sections: every one becomes unspecified; the limits stay.
        for groups in [detail.adapted(to: version(0)).attributeGroups, result.adapted(to: version(0)).attributeGroups] {
            let attributes = groups.flatMap(\.attributes)
            XCTAssertEqual(attributes.map(\.section), Array(repeating: .unspecified, count: 4))
            XCTAssertEqual(attributes.map(\.limits), Array(repeating: [NumberLimit(minimum: 0)], count: 4))
        }
        // 1.1 and later get them as they are.
        for minor: UInt16 in [1, 2] {
            XCTAssertEqual(detail.adapted(to: version(minor)), detail, "1.\(minor)")
            XCTAssertEqual(result.adapted(to: version(minor)), result, "1.\(minor)")
        }
    }
}
