import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// `GetSubtree` and `SetAttribute` in the session, over a fake transport.
final class SessionRequestTests: XCTestCase {
    private static let active = Frame(requestID: 0, body: .appStateChanged(.active))

    private func subtree(_ requestID: UInt32, _ rootID: UInt64) -> Frame {
        Frame(requestID: requestID, body: .getSubtree(rootID: rootID))
    }

    private func error(_ requestID: UInt32, _ code: ErrorCode, _ message: String) -> Frame {
        Frame(requestID: requestID, body: .error(WireError(code: code, message: message)))
    }

    func test_S_HIER_11_subtreeIsAnsweredWithAHierarchy() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        harness.receive(subtree(3, 4))
        let frames = try await harness.frames(3)
        XCTAssertEqual(
            frames[2],
            Frame(requestID: 3, body: .hierarchy(try XCTUnwrap(SessionHarness.subtree(of: 4))))
        )
        XCTAssertEqual(harness.subtreeRoots, [4])
    }

    func test_S_HIER_12_missingRootIsLayerNotFound() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        // The same words as the `subtree` fixture; the connection stays and serves what follows.
        harness.receive(subtree(2, 99), Frame(requestID: 3, body: .getHierarchy))
        let frames = try await harness.frames(4)
        XCTAssertEqual(frames[2], error(2, .layerNotFound, "no layer with id 99"))
        XCTAssertEqual(frames[3], Frame(requestID: 3, body: .hierarchy(SessionHarness.hierarchy)))
        XCTAssertEqual(harness.endedCount, 0)
    }

    func test_S_HIER_11_subtreeNeedsAnActiveApp() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        harness.setAppState(.background)
        harness.receive(subtree(5, 4))
        let frames = try await harness.frames(4)
        XCTAssertEqual(frames[2], Frame(requestID: 0, body: .appStateChanged(.background)))
        XCTAssertEqual(frames[3], error(5, .appNotActive, "the app is not active"))
        XCTAssertEqual(harness.subtreeRoots, [], "nothing is read while the app is not active")
    }

    func test_S_HIER_11_subtreeReadWhileTheAppLeftIsNotSent() async throws {
        let harness = SessionHarness()
        try await harness.handshake()
        harness.leaveActiveStateWhileReadingSubtrees()

        // P-APP-01: the client was told first, and gets no subtree after that.
        harness.receive(subtree(6, 4))
        let frames = try await harness.frames(4)
        XCTAssertEqual(frames[2], Frame(requestID: 0, body: .appStateChanged(.background)))
        XCTAssertEqual(frames[3], error(6, .appNotActive, "the app is not active"))
    }

    func test_S_HIER_11_subtreeWaitsForTheStreamInHand() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        // P-REQ-06: requests are answered one at a time, in order.
        let details = Frame(
            requestID: 7,
            body: .getLayerDetails(
                GetLayerDetails(
                    requests: [1, 2].map {
                        LayerDetailRequest(layerID: $0, wantSolo: false, wantGroup: true, wantAttributes: false)
                    },
                    maxTextureDimension: 0
                )
            )
        )
        harness.receive(details, subtree(8, 4))
        let frames = try await harness.frames(6)
        XCTAssertEqual(frames[2...].map(\.requestID), [7, 7, 7, 8])
        XCTAssertEqual(frames[4], Frame(requestID: 7, body: .streamEnd(StreamEnd(status: .completed, chunkCount: 2))))
        guard case .hierarchy? = frames[5].body else { return XCTFail("expected Hierarchy, got \(frames[5])") }
    }

    private func change(_ requestID: UInt32, layer layerID: UInt64) -> Frame {
        Frame(
            requestID: requestID,
            body: .setAttribute(SetAttribute(layerID: layerID, attributeID: "label.text", value: .string("Hi")))
        )
    }

    func test_S_SET_01_setAttributeIsAnsweredWithTheResult() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        harness.receive(change(4, layer: 3))
        let frames = try await harness.frames(3)
        let expected = try SessionHarness.result(
            of: SetAttribute(layerID: 3, attributeID: "label.text", value: .string("Hi"))
        ).get()
        XCTAssertEqual(frames[2], Frame(requestID: 4, body: .setAttributeResult(expected)))
        XCTAssertEqual(harness.changes.map(\.layerID), [3])
    }

    func test_S_SET_02_rejectionsAreAnsweredWithErrors() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        // The connection stays and serves what follows.
        harness.receive(change(4, layer: 99), Frame(requestID: 5, body: .getHierarchy))
        let frames = try await harness.frames(4)
        XCTAssertEqual(frames[2], error(4, .layerNotFound, "no layer with id 99"))
        XCTAssertEqual(frames[3], Frame(requestID: 5, body: .hierarchy(SessionHarness.hierarchy)))
        XCTAssertEqual(harness.endedCount, 0)
    }

    func test_S_SET_05_setAttributeNeedsAnActiveApp() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        harness.setAppState(.inactive)
        harness.receive(change(6, layer: 3))
        let frames = try await harness.frames(4)
        XCTAssertEqual(frames[2], Frame(requestID: 0, body: .appStateChanged(.inactive)))
        XCTAssertEqual(frames[3], error(6, .appNotActive, "the app is not active"))
        XCTAssertEqual(harness.changes, [], "nothing is changed while the app is not active")
    }

    func test_S_SET_01_setAttributeWaitsForTheStreamInHand() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        // P-REQ-06: requests are answered one at a time, in order.
        let details = Frame(
            requestID: 7,
            body: .getLayerDetails(
                GetLayerDetails(
                    requests: [1, 2].map {
                        LayerDetailRequest(layerID: $0, wantSolo: false, wantGroup: true, wantAttributes: false)
                    },
                    maxTextureDimension: 0
                )
            )
        )
        harness.receive(details, change(8, layer: 3))
        let frames = try await harness.frames(6)
        XCTAssertEqual(frames[2...].map(\.requestID), [7, 7, 7, 8])
        guard case .setAttributeResult? = frames[5].body else {
            return XCTFail("expected SetAttributeResult, got \(frames[5])")
        }
    }

    func test_S_CONN_09_setAttributeResultIsUnexpected() async throws {
        let harness = SessionHarness()
        try await harness.handshake()

        // P-REQ-08: only a server sends it.
        harness.receive(
            Frame(requestID: 6, body: .setAttributeResult(SetAttributeResult(layerID: 1, attributeGroups: [])))
        )
        let frames = try await harness.frames(3)
        XCTAssertEqual(frames[2], error(6, .unexpectedMessage, "this message is not expected here"))
        XCTAssertEqual(harness.endedCount, 0)
    }
}
