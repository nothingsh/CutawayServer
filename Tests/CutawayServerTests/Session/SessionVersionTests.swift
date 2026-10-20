import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// The session sends what the negotiated minor version names
/// (S-CONN-12, S-ATTR-08; PROTOCOL.md, P-HELLO-04, P-LAYOUT-08, P-ATTR-08). Over a fake transport, no
/// connection. The versions are those of protocol 1.
final class SessionVersionTests: XCTestCase {
    private func version(_ minor: UInt16) -> ProtocolVersion {
        ProtocolVersion(major: 1, minor: minor)
    }

    /// UIKit's shapes for a view with a flexible left margin, and one with public attributes.
    private static func constraints(of layerID: UInt64) -> [LayoutConstraint] {
        let view = LayoutItem(kind: .view, layerID: layerID)
        let superview = LayoutItem(kind: .view, layerID: 1)
        return [
            LayoutConstraint(
                id: 100,
                className: "NSAutoresizingMaskLayoutConstraint",
                firstItem: superview,
                firstAttribute: .width,
                relation: .equal,
                secondItem: view,
                secondAttribute: .maxX,
                multiplier: 1,
                constant: 93,
                priority: 1000,
                status: .unknown
            ),
            LayoutConstraint(
                id: 101,
                className: "NSAutoresizingMaskLayoutConstraint",
                firstItem: view,
                firstAttribute: .minY,
                relation: .equal,
                multiplier: 1,
                constant: 700,
                priority: 1000,
                status: .unknown
            ),
            LayoutConstraint(
                id: 102,
                className: "NSLayoutConstraint",
                identifier: "edge",
                firstItem: view,
                firstAttribute: .leading,
                relation: .greaterThanOrEqual,
                secondItem: superview,
                secondAttribute: .leadingMargin,
                multiplier: 1,
                constant: 8,
                priority: 250,
                status: .satisfied
            )
        ]
    }

    private static let request = Frame(
        requestID: 5,
        body: .getLayerDetails(
            GetLayerDetails(
                requests: [
                    LayerDetailRequest(
                        layerID: 9,
                        wantSolo: false,
                        wantGroup: false,
                        wantAttributes: false,
                        wantConstraints: true
                    )
                ],
                maxTextureDimension: 0
            )
        )
    )

    private func harness() -> SessionHarness {
        SessionHarness(capture: ScriptedCapture(constraints: Self.constraints(of:)))
    }

    /// The detail of the first chunk after the handshake's two frames, and what was captured.
    private func detail(
        afterHandshakeAt version: ProtocolVersion,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> (sent: LayerDetail, captured: LayerDetail) {
        let harness = harness()
        try await harness.handshake(version: version)
        harness.receive(Self.request)
        let frames = try await harness.frames(4)
        guard case .layerDetailsChunk(let chunk)? = frames[2].body, chunk.details.count == 1 else {
            XCTFail("expected a chunk, got \(frames[2])", file: file, line: line)
            throw CancellationError()
        }
        return (chunk.details[0], harness.capture.detail(for: 9).compressed())
    }

    /// The server's hello whatever the client's version (P-HELLO-02).
    private func assertServerHello(_ frame: Frame, file: StaticString = #filePath, line: UInt = #line) {
        guard case .hello(let hello)? = frame.body else {
            return XCTFail("expected Hello, got \(frame)", file: file, line: line)
        }
        XCTAssertEqual(hello.version, ProtocolVersion(major: 1, minor: 2), file: file, line: line)
    }

    func test_S_CONN_12_protocol1ClientsGetTheAttributes() async throws {
        for minor: UInt16 in [0, 1] {
            let (sent, captured) = try await detail(afterHandshakeAt: version(minor))
            XCTAssertEqual(sent, captured, "1.\(minor)")
            XCTAssertEqual(
                sent.constraints.map(\.secondAttribute),
                [.maxX, .notAnAttribute, .leadingMargin],
                "1.\(minor)"
            )
            XCTAssertEqual(sent.constraints[1].firstAttribute, .minY, "1.\(minor)")
        }
    }

    /// P-DET-10: before 1.2 an excluded layer is `CaptureFailed` when an image was requested and
    /// `Ok` otherwise.
    func test_S_CONN_12_excludedLayersBefore1_2() async throws {
        func request(_ layerID: UInt64, group: Bool) -> LayerDetailRequest {
            LayerDetailRequest(layerID: layerID, wantSolo: false, wantGroup: group, wantAttributes: true)
        }
        let frame = Frame(
            requestID: 5,
            body: .getLayerDetails(
                GetLayerDetails(requests: [request(3, group: true), request(4, group: false)], maxTextureDimension: 0)
            )
        )
        for (minor, expected) in [(UInt16(1), [DetailStatus.captureFailed, .ok]), (2, [.excluded, .excluded])] {
            let harness = SessionHarness(capture: ScriptedCapture(excluded: [3, 4]))
            try await harness.handshake(version: version(minor))
            harness.receive(frame)
            let frames = try await harness.frames(5)
            let details = frames[2...3].flatMap { frame -> [LayerDetail] in
                guard case .layerDetailsChunk(let chunk)? = frame.body else { return [] }
                return chunk.details
            }
            XCTAssertEqual(details.map(\.status), expected, "1.\(minor)")
            XCTAssertTrue(details.allSatisfy { $0.group == nil }, "1.\(minor)")
        }
    }

    /// P-ATTR-19: the host app's groups go to every protocol 1 client, adapted like the
    /// server's own; a reference becomes text before 1.2.
    func test_S_ATTR_24_theAppsGroupsReachA1_1Client() async throws {
        let reference = ObjectReference(layerID: 7, className: "Demo.ChartView", displayClassName: "ChartView")
        let group = AttributeGroup(
            id: "app.chart",
            title: "Chart",
            attributes: [
                Attribute(
                    id: "app.chart.barColor",
                    title: "Bar Color",
                    value: .color(WireColor(red: 1, green: 0, blue: 0, alpha: 1), name: "brand"),
                    valueKind: .color,
                    section: .appearance
                ),
                Attribute(
                    id: "app.chart.legend",
                    title: "Legend",
                    value: .layerReference([reference]),
                    valueKind: .layerReference,
                    section: .accessibility
                )
            ],
            className: "Demo.ChartView",
            fromApp: true
        )
        let frame = Frame(
            requestID: 5,
            body: .getLayerDetails(
                GetLayerDetails(
                    requests: [LayerDetailRequest(layerID: 3, wantSolo: false, wantGroup: false, wantAttributes: true)],
                    maxTextureDimension: 0
                )
            )
        )
        for minor: UInt16 in [1, 2] {
            let harness = SessionHarness(capture: ScriptedCapture(attributeGroups: { _ in [group] }))
            try await harness.handshake(version: version(minor))
            harness.receive(frame)
            let frames = try await harness.frames(4)
            guard case .layerDetailsChunk(let chunk)? = frames[2].body,
                  let sent = chunk.details.first?.attributeGroups.first
            else {
                return XCTFail("1.\(minor): no chunk with a group, got \(frames[2])")
            }
            XCTAssertEqual(sent.id, "app.chart", "1.\(minor)")
            XCTAssertTrue(sent.fromApp, "1.\(minor)")
            XCTAssertEqual(sent.attributes[0].value, group.attributes[0].value, "1.\(minor)")
            if minor == 1 {
                XCTAssertEqual(sent.attributes[1].value, .string("ChartView"))
                XCTAssertEqual(sent.attributes[1].section, .unspecified)
            } else {
                XCTAssertEqual(sent.attributes, group.attributes)
            }
        }
    }

    func test_S_CONN_12_versionHoldsForTheConnection() async throws {
        let harness = harness()
        try await harness.handshake(version: version(0))
        // A second hello is not a handshake (P-REQ-08), and changes nothing.
        harness.receive(SessionHarness.clientHello(version: ProtocolVersion(major: 0, minor: 5)), Self.request)
        let frames = try await harness.frames(5)
        guard case .error(let error)? = frames[2].body else {
            return XCTFail("expected an error, got \(frames[2])")
        }
        XCTAssertEqual(error.code, .unexpectedMessage)
        guard case .layerDetailsChunk(let chunk)? = frames[3].body else {
            return XCTFail("expected a chunk, got \(frames[3])")
        }
        XCTAssertEqual(chunk.details, [harness.capture.detail(for: 9).compressed()])
        XCTAssertFalse(harness.transport.isClosed)
    }

    /// P-HELLO-03: a client of protocol 0 gets the server's hello, then the end of the
    /// connection, and nothing else.
    func test_S_CONN_04_protocol0ClientGetsHelloThenClose() async throws {
        for old in [ProtocolVersion(major: 0, minor: 5), ProtocolVersion(major: 0, minor: 3)] {
            let harness = SessionHarness()
            harness.receive(SessionHarness.clientHello(version: old))
            let frames = try await harness.frames(1)
            assertServerHello(frames[0])
            await harness.settle()
            XCTAssertTrue(harness.transport.isClosed, "\(old)")
            XCTAssertEqual(harness.transport.sent.count, 1, "\(old)")
        }
    }

    /// S-REL-03: the handshake reports the pinned protocol, 1.2, and the app's information the
    /// SDK's version, which is the repository's tag: 1.1.0 until 1.2.0 is released.
    func test_S_REL_03_versionsAreProtocol1AndServer1() async throws {
        XCTAssertEqual(ProtocolVersion.current, ProtocolVersion(major: 1, minor: 2))
        XCTAssertEqual(ServerVersion.string, "1.1.0")
        let serverVersion = await MainActor.run { LiveHostApp(infoDictionary: [:]).appInfo().serverVersion }
        XCTAssertEqual(serverVersion, "1.1.0")

        let harness = SessionHarness()
        harness.receive(SessionHarness.clientHello)
        let frames = try await harness.frames(2)
        assertServerHello(frames[0])
        XCTAssertEqual(frames[1].body, .appStateChanged(.active))
    }

    /// A group with one attribute of each section, and limits.
    private static func sectioned(_ layerID: UInt64) -> [AttributeGroup] {
        [
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
                        limits: [NumberLimit(minimum: 0)],
                        unit: .points
                    )
                }
            )
        ]
    }

    private static let attributesRequest = Frame(
        requestID: 5,
        body: .getLayerDetails(
            GetLayerDetails(
                requests: [LayerDetailRequest(layerID: 9, wantSolo: false, wantGroup: false, wantAttributes: true)],
                maxTextureDimension: 0
            )
        )
    )

    private static let change = Frame(
        requestID: 6,
        body: .setAttribute(SetAttribute(layerID: 9, attributeID: "view.tag", value: .int(2)))
    )

    /// What a client at one version gets of the scripted attributes.
    private struct Received {
        /// The sections in the chunk and in the change's result.
        var detail: [AttributeSection]
        var result: [AttributeSection]
        /// The limits in both.
        var limits: [[NumberLimit]]
        /// The units in the chunk.
        var units: [AttributeUnit]
    }

    /// What the chunk and the change's result hold, after a handshake at `version`.
    private func sections(afterHandshakeAt version: ProtocolVersion) async throws -> Received {
        let harness = SessionHarness(capture: ScriptedCapture(attributeGroups: Self.sectioned(_:)))
        try await harness.handshake(version: version)
        harness.receive(Self.attributesRequest, Self.change)
        let frames = try await harness.frames(5)
        guard case .layerDetailsChunk(let chunk)? = frames[2].body,
              case .setAttributeResult(let result)? = frames[4].body else {
            XCTFail("expected a chunk and a result, got \(frames)")
            throw CancellationError()
        }
        let detailAttributes = chunk.details.flatMap(\.attributeGroups).flatMap(\.attributes)
        let resultAttributes = result.attributeGroups.flatMap(\.attributes)
        return Received(
            detail: detailAttributes.map(\.section),
            result: resultAttributes.map(\.section),
            limits: (detailAttributes + resultAttributes).map(\.limits),
            units: detailAttributes.map(\.unit)
        )
    }

    func test_S_HIER_15_hierarchiesAreReadForTheNegotiatedVersion() async throws {
        // P-HIER-17: the tables of known classes are the negotiated version's.
        for minor: UInt16 in [0, 1] {
            let harness = SessionHarness()
            try await harness.handshake(version: version(minor))
            harness.receive(
                Frame(requestID: 5, body: .getHierarchy),
                Frame(requestID: 6, body: .getSubtree(rootID: 2))
            )
            _ = try await harness.frames(4)
            XCTAssertEqual(harness.captureVersions, [version(minor), version(minor)], "1.\(minor)")
        }
    }

    func test_S_ATTR_13_aProtocol1_0ClientGetsUnspecifiedUnits() async throws {
        let old = try await sections(afterHandshakeAt: version(0))
        XCTAssertTrue(old.units.allSatisfy { $0 == .unspecified })
        let current = try await sections(afterHandshakeAt: version(1))
        XCTAssertTrue(current.units.allSatisfy { $0 == .points })
    }

    func test_S_ATTR_08_aProtocol1_0ClientGetsUnspecifiedSections() async throws {
        let old = try await sections(afterHandshakeAt: version(0))
        let count = AttributeSection.allCases.count
        XCTAssertEqual(old.detail, Array(repeating: .unspecified, count: count))
        XCTAssertEqual(old.result, [.unspecified])
        // Limits are appended fields a 1.0 client does not read: they go out as they are.
        XCTAssertEqual(old.limits, Array(repeating: [NumberLimit(minimum: 0)], count: count + 1))
        // S-ATTR-13: 1.0 has no units either (P-ATTR-14).
        XCTAssertEqual(old.units, Array(repeating: .unspecified, count: count))

        // 1.1 has every section but `Accessibility` (1.2).
        let previous = try await sections(afterHandshakeAt: version(1))
        XCTAssertEqual(previous.detail, AttributeSection.allCases.map { $0 == .accessibility ? .unspecified : $0 })
        XCTAssertEqual(previous.result, [.layout])
        XCTAssertEqual(previous.units, Array(repeating: .points, count: AttributeSection.allCases.count))

        let current = try await sections(afterHandshakeAt: version(2))
        XCTAssertEqual(current.detail, AttributeSection.allCases)
        XCTAssertEqual(current.result, [.layout])
    }

    // MARK: - Protocol 1.2

    /// What the catalog reads of a stack view holding a label with a text style and an
    /// accessibility label: attributes of the `Accessibility` section, slots of 1.2 and object
    /// references.
    @MainActor
    private static func catalogGroups() -> [AttributeGroup] {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let label = UILabel()
        label.font = .preferredFont(forTextStyle: .body)
        label.text = "Hello"
        label.accessibilityLabel = "Greeting"
        let stack = UIStackView(arrangedSubviews: [label])
        stack.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
        window.addSubview(stack)
        window.layoutIfNeeded()
        let reading = AttributeReading(registry: LayerRegistry(), windows: [window])
        return AttributeCatalog.standard.read(stack.layer, reading: reading)
            + AttributeCatalog.standard.read(label.layer, reading: reading)
    }

    /// The attributes of the chunk after a handshake at `version`, and of a change's result
    /// adapted as the session adapts it (the harness answers changes with attributes of its own).
    private func catalogAttributes(afterHandshakeAt version: ProtocolVersion) async throws
        -> (detail: [Attribute], result: [Attribute]) {
        let groups = await MainActor.run { Self.catalogGroups() }
        let harness = SessionHarness(capture: ScriptedCapture(attributeGroups: { _ in groups }))
        try await harness.handshake(version: version)
        harness.receive(Self.attributesRequest)
        let frames = try await harness.frames(4)
        guard case .layerDetailsChunk(let chunk)? = frames[2].body else {
            XCTFail("expected a chunk, got \(frames)")
            throw CancellationError()
        }
        let result = SetAttributeResult(layerID: 9, attributeGroups: groups).adapted(to: version)
        return (
            chunk.details.flatMap(\.attributeGroups).flatMap(\.attributes),
            result.attributeGroups.flatMap(\.attributes)
        )
    }

    /// S-CONN-12 (as of 1.2): a 1.1 client gets no `Accessibility` section, no slot of 1.2 and no
    /// references, in a detail and in a change's result alike.
    func test_S_CONN_12_aProtocol1_1ClientGetsNothingOf1_2() async throws {
        let table = AttributeTables.clusters(at: version(1))
        let previous = try await catalogAttributes(afterHandshakeAt: version(1))
        for (name, attributes) in [("detail", previous.detail), ("result", previous.result)] {
            XCTAssertFalse(attributes.isEmpty, name)
            XCTAssertFalse(attributes.contains { $0.section == .accessibility }, name)
            let accessibility = attributes.filter { $0.id.hasPrefix("view.accessibility") }
            XCTAssertEqual(accessibility.count, 10, "\(name): five of each view")
            XCTAssertTrue(accessibility.allSatisfy { $0.section == .unspecified }, name)
            for attribute in attributes {
                if let cluster = attribute.cluster {
                    XCTAssertTrue(table[cluster]?.contains(attribute.slot ?? "") ?? false, "\(name): \(attribute.id)")
                } else {
                    XCTAssertNil(attribute.slot, "\(name): \(attribute.id)")
                }
                XCTAssertNotEqual(attribute.valueKind, .layerReference, "\(name): \(attribute.id)")
            }
            let style = try XCTUnwrap(attributes.first { $0.id == "label.fontTextStyle" }, name)
            XCTAssertEqual(style.value, .string("body"), name)
            XCTAssertNil(style.cluster, name)
            let arranged = try XCTUnwrap(attributes.first { $0.id == "stackView.arrangedSubviews" }, name)
            XCTAssertEqual(arranged.value, .string("UILabel"), name)
            XCTAssertEqual(arranged.valueKind, .string, name)
            XCTAssertFalse(arranged.editable, name)
        }

        let current = try await catalogAttributes(afterHandshakeAt: version(2))
        let style = try XCTUnwrap(current.detail.first { $0.id == "label.fontTextStyle" })
        XCTAssertEqual(style.cluster, "font")
        XCTAssertEqual(style.slot, "textStyle")
        let arranged = try XCTUnwrap(current.result.first { $0.id == "stackView.arrangedSubviews" })
        XCTAssertEqual(arranged.valueKind, .layerReference)
        XCTAssertEqual(current.detail.filter { $0.section == .accessibility }.count, 12)
    }
}
