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

    func test_S_CONN_12_excludedIsCaptureFailedOrOkBefore1_2() {
        let excluded = LayerDetail(layerID: 4, status: .excluded)
        let image = LayerDetailRequest(layerID: 4, wantSolo: false, wantGroup: true, wantAttributes: true)
        let solo = LayerDetailRequest(layerID: 4, wantSolo: true, wantGroup: false, wantAttributes: false)
        let attributes = LayerDetailRequest(layerID: 4, wantSolo: false, wantGroup: false, wantAttributes: true)
        for minor: UInt16 in [0, 1] {
            XCTAssertEqual(excluded.adapted(to: version(minor), for: image).status, .captureFailed)
            XCTAssertEqual(excluded.adapted(to: version(minor), for: solo).status, .captureFailed)
            XCTAssertEqual(excluded.adapted(to: version(minor), for: attributes).status, .ok)
        }
        XCTAssertEqual(excluded.adapted(to: version(2), for: image).status, .excluded)
        XCTAssertEqual(excluded.adapted(to: version(2), for: attributes).status, .excluded)
        // Other statuses are left alone.
        XCTAssertEqual(LayerDetail(layerID: 4, status: .ok).adapted(to: version(1), for: image).status, .ok)
    }

    func test_S_CONN_12_negotiatedVersionIsTheLowerMinor() {
        let current = ProtocolVersion.current
        XCTAssertEqual(current, version(2))
        XCTAssertEqual(current.negotiated(with: version(0)), version(0))
        XCTAssertEqual(current.negotiated(with: version(1)), version(1))
        XCTAssertEqual(current.negotiated(with: version(2)), version(2))
        XCTAssertEqual(current.negotiated(with: version(3)), version(2))
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
        // Protocol 1.1 added every section but the default, 1.2 `Accessibility` (P-ATTR-08).
        XCTAssertEqual(AttributeSection.unspecified.minorVersion, 0)
        XCTAssertEqual(AttributeSection.accessibility.minorVersion, 2)
        for section in AttributeSection.allCases where ![.unspecified, .accessibility].contains(section) {
            XCTAssertEqual(section.minorVersion, 1, "\(section)")
        }
    }

    func test_S_CONN_12_everyUnitAndGuideKindHasItsMinorVersion() {
        // Protocol 1.1 added every unit and guide kind but the defaults (P-ATTR-14, P-LAYOUT-04).
        XCTAssertEqual(AttributeUnit.unspecified.minorVersion, 0)
        for unit in AttributeUnit.allCases where unit != .unspecified {
            XCTAssertEqual(unit.minorVersion, 1, "\(unit)")
        }
        XCTAssertEqual(LayoutGuideKind.unknown.minorVersion, 0)
        for kind in LayoutGuideKind.allCases where kind != .unknown {
            XCTAssertEqual(kind.minorVersion, 1, "\(kind)")
        }
        // P-HIER-17: every entry of the tables came with 1.1, so a 1.0 peer knows none.
        for entry in KnownClasses.views + KnownClasses.layers {
            XCTAssertEqual(entry.minorVersion, 1, entry.name)
        }
        XCTAssertTrue(KnownClasses.names(of: KnownClasses.views, at: version(0)).isEmpty)
        XCTAssertEqual(KnownClasses.names(of: KnownClasses.views, at: version(1)).count, KnownClasses.views.count)
    }

    func test_S_LAYOUT_06_aProtocol1_0PeerGetsOtherGuideKinds() {
        let guide = LayoutItem(kind: .layoutGuide, layerID: 2, guideID: 1, guideKind: .safeArea)
        let detail = LayerDetail(
            layerID: 3,
            status: .ok,
            constraints: [
                LayoutConstraint(
                    id: 1,
                    className: "NSLayoutConstraint",
                    firstItem: LayoutItem(kind: .view, layerID: 3),
                    firstAttribute: .top,
                    relation: .equal,
                    secondItem: guide,
                    secondAttribute: .top,
                    multiplier: 1,
                    constant: 0,
                    priority: 1000,
                    status: .satisfied,
                    origin: .app
                )
            ]
        )
        // P-LAYOUT-04: 1.0 has no kinds; the guide becomes `other`, a view stays without one.
        let adapted = detail.adapted(to: version(0)).constraints[0]
        XCTAssertEqual(adapted.secondItem?.guideKind, .other)
        XCTAssertEqual(adapted.firstItem?.guideKind, .unknown)
        XCTAssertEqual(adapted.origin, .app)
        XCTAssertEqual(detail.adapted(to: version(1)), detail)
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
                        limits: limits,
                        cluster: "sizing",
                        slot: "intrinsic.width",
                        unit: .points
                    )
                },
                className: "UIView"
            )
        ]
    }

    func test_S_ATTR_08_aProtocol1_0PeerGetsUnspecifiedSections() {
        let detail = LayerDetail(layerID: 9, status: .ok, attributeGroups: sectionedGroups)
        let result = SetAttributeResult(layerID: 9, attributeGroups: sectionedGroups)

        // 1.0 has no sections, no units and no clusters: every section and unit becomes
        // unspecified, and the cluster and slot go (1.2, P-ATTR-12); the limits and the other
        // fields of 1.1 stay.
        let count = AttributeSection.allCases.count
        for groups in [detail.adapted(to: version(0)).attributeGroups, result.adapted(to: version(0)).attributeGroups] {
            let attributes = groups.flatMap(\.attributes)
            XCTAssertEqual(attributes.map(\.section), Array(repeating: .unspecified, count: count))
            XCTAssertEqual(attributes.map(\.unit), Array(repeating: .unspecified, count: count))
            XCTAssertEqual(attributes.map(\.limits), Array(repeating: [NumberLimit(minimum: 0)], count: count))
            XCTAssertEqual(attributes.map(\.cluster), Array(repeating: nil, count: count))
            XCTAssertEqual(attributes.map(\.slot), Array(repeating: nil, count: count))
            XCTAssertEqual(groups.map(\.className), ["UIView"])
        }
        // 1.1 gets them as they are but `Accessibility`; 1.2 all of them.
        for groups in [detail.adapted(to: version(1)).attributeGroups, result.adapted(to: version(1)).attributeGroups] {
            XCTAssertEqual(
                groups.flatMap(\.attributes).map(\.section),
                AttributeSection.allCases.map { $0 == .accessibility ? .unspecified : $0 }
            )
            XCTAssertEqual(groups.flatMap(\.attributes).map(\.cluster), Array(repeating: "sizing", count: count))
        }
        XCTAssertEqual(detail.adapted(to: version(2)), detail)
        XCTAssertEqual(result.adapted(to: version(2)), result)
    }

    // MARK: - Protocol 1.2

    private func attribute(
        _ id: String,
        _ value: AttributeValue?,
        kind: AttributeValueKind,
        cluster: String? = nil,
        slot: String? = nil
    ) -> Attribute {
        Attribute(id: id, title: id, value: value, valueKind: kind, section: .content, cluster: cluster, slot: slot)
    }

    func test_S_CONN_12_clustersAndSlotsFollowTheNegotiatedTable() {
        let groups = [
            AttributeGroup(
                id: "label",
                title: "Label",
                attributes: [
                    attribute("label.fontSize", .double(17), kind: .double, cluster: "font", slot: "size"),
                    attribute(
                        "label.fontTextStyle",
                        .string("body"),
                        kind: .string,
                        cluster: "font",
                        slot: "textStyle"
                    ),
                    attribute("tableView.numberOfRows", .int(8), kind: .int, cluster: "listCounts", slot: "items"),
                    attribute("other", .int(1), kind: .int, cluster: "nowhere", slot: "at.all")
                ]
            )
        ]
        let adapted = { (minor: UInt16) in
            LayerDetail(layerID: 1, status: .ok, attributeGroups: groups).adapted(to: self.version(minor))
                .attributeGroups.flatMap(\.attributes)
        }
        // 1.2 knows the new slot and cluster; a slot of no table goes at every version.
        XCTAssertEqual(adapted(2).map(\.cluster), ["font", "font", "listCounts", nil])
        XCTAssertEqual(adapted(2).map(\.slot), ["size", "textStyle", "items", nil])
        // 1.1 knows `font` but not its slot `textStyle`, and not `listCounts`.
        XCTAssertEqual(adapted(1).map(\.cluster), ["font", nil, nil, nil])
        XCTAssertEqual(adapted(1).map(\.slot), ["size", nil, nil, nil])
        // 1.0 knows no clusters.
        XCTAssertEqual(adapted(0).map(\.cluster), [nil, nil, nil, nil])
        XCTAssertEqual(AttributeTables.clusters(at: version(0)), [:])
        XCTAssertEqual(AttributeTables.clusters(at: version(1))["font"], ["name", "size"])
        XCTAssertEqual(AttributeTables.clusters["font"], ["name", "size", "textStyle", "scalable"])
        XCTAssertNil(AttributeTables.clusters(at: version(1))["image"])
    }

    func test_S_CONN_12_objectReferencesAreTextBefore1_2() {
        let references: AttributeValue = .layerReference([
            ObjectReference(layerID: 2, className: "Demo.HomeViewController", displayClassName: "HomeViewController"),
            ObjectReference(layerID: 0, className: "NSObject", displayClassName: "NSObject")
        ])
        let groups = [
            AttributeGroup(
                id: "stackView",
                title: "Stack View",
                attributes: [
                    attribute("stackView.arrangedSubviews", references, kind: .layerReference),
                    attribute("tableView.dataSource", .layerReference([]), kind: .layerReference),
                    attribute("tableView.delegate", nil, kind: .layerReference)
                ]
            )
        ]
        let detail = LayerDetail(layerID: 1, status: .ok, attributeGroups: groups)
        let result = SetAttributeResult(layerID: 1, attributeGroups: groups)
        for adapted in [
            detail.adapted(to: version(1)).attributeGroups,
            result.adapted(to: version(1)).attributeGroups
        ] {
            let attributes = adapted.flatMap(\.attributes)
            XCTAssertEqual(attributes.map(\.valueKind), [.string, .string, .string])
            XCTAssertEqual(attributes.map(\.value), [.string("HomeViewController, NSObject"), .string("None"), nil])
            XCTAssertTrue(attributes.allSatisfy { !$0.editable })
        }
        XCTAssertEqual(
            detail.adapted(to: version(0)).attributeGroups.flatMap(\.attributes).map(\.valueKind),
            [.string, .string, .string]
        )
        XCTAssertEqual(detail.adapted(to: version(2)), detail)
        XCTAssertEqual(AttributeValueKind.layerReference.minorVersion, 2)
    }
}
