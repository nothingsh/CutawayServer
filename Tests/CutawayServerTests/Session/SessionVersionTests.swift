import CutawayWire
import Foundation
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
        XCTAssertEqual(hello.version, ProtocolVersion(major: 1, minor: 1), file: file, line: line)
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

    /// S-REL-03: the handshake reports the pinned protocol, 1.1, and the app's information the
    /// SDK's version, which is the repository's tag: 1.0.0 until 1.1.0 is released.
    func test_S_REL_03_versionsAreProtocol1AndServer1() async throws {
        XCTAssertEqual(ProtocolVersion.current, ProtocolVersion(major: 1, minor: 1))
        XCTAssertEqual(ServerVersion.string, "1.0.0")
        let serverVersion = await MainActor.run { LiveHostApp(infoDictionary: [:]).appInfo().serverVersion }
        XCTAssertEqual(serverVersion, "1.0.0")

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

        let current = try await sections(afterHandshakeAt: version(1))
        XCTAssertEqual(current.detail, AttributeSection.allCases)
        XCTAssertEqual(current.result, [.layout])
        XCTAssertEqual(current.units, Array(repeating: .points, count: AttributeSection.allCases.count))
    }
}
