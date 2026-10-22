import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// Counts how often the server reads the layers. Touched on the main thread only.
@MainActor
private final class CaptureCounter {
    var count = 0

    nonisolated init() {}
}

/// `GetHierarchy` over a connection.
final class HierarchyRequestTests: ServerTestCase {
    private static let notActive = WireError(code: .appNotActive, message: "the app is not active")

    /// The hierarchy in a response to request `requestID`.
    private func hierarchy(
        in frame: Frame?,
        answering requestID: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> Hierarchy {
        XCTAssertEqual(frame?.requestID, requestID, file: file, line: line)
        guard case .hierarchy(let hierarchy)? = frame?.body else {
            throw TestClientError(description: "expected Hierarchy, got \(String(describing: frame))")
        }
        return hierarchy
    }

    func test_S_HIER_01_getHierarchyAnswersWithTheWindows() async throws {
        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        // The request of the fixture, byte for byte.
        let request = try Fixtures.frame("hierarchy/01-c2s-get-hierarchy.bin")
        try await client.send(Fixtures.data("hierarchy/c2s.stream"))
        let answer = try await client.nextFrame()
        let hierarchy = try hierarchy(in: answer, answering: request.requestID)

        // One root per window of the app, back to front; the key window is one of them.
        let windowClasses = await MainActor.run {
            HostWindows.all().map { NSStringFromClass(type(of: $0)) }
        }
        let roots = hierarchy.nodes.filter { $0.parentID == 0 }
        XCTAssertFalse(windowClasses.isEmpty)
        XCTAssertEqual(roots.map(\.viewClassName), windowClasses)
        XCTAssertTrue(roots.contains { $0.id == hierarchy.keyWindowID })

        // It is what reading the layers directly gives. A connection's first hierarchy numbers
        // the layers from 1 in the order it meets them, and so does a new registry.
        let direct = await MainActor.run {
            HierarchyCapture.capture(.testing(windows: HostWindows.all(), registry: LayerRegistry()))
        }
        XCTAssertEqual(hierarchy, direct)
    }

    func test_S_HIER_02_idsAreStableWithinAConnection() async throws {
        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        let firstAnswer = try await client.nextFrame()
        let first = try hierarchy(in: firstAnswer, answering: 1)
        try await client.send(Frame(requestID: 2, body: .getHierarchy))
        let secondAnswer = try await client.nextFrame()
        XCTAssertEqual(try hierarchy(in: secondAnswer, answering: 2), first)

        // Many requests in one write, with another kind among them: answered one by one, in
        // the order they were sent (P-REQ-06).
        var bytes = Data()
        for requestID in UInt32(10)..<40 {
            let body: Message = requestID == 20 ? .getAppIcon : .getHierarchy
            bytes += FrameCodec.framed(FrameCodec.encode(Frame(requestID: requestID, body: body)))
        }
        try await client.send(bytes)
        for requestID in UInt32(10)..<40 {
            let answer = try await client.nextFrame()
            if requestID == 20 {
                XCTAssertEqual(answer?.requestID, 20)
                guard case .appIcon? = answer?.body else {
                    return XCTFail("expected AppIcon, got \(String(describing: answer))")
                }
            } else {
                XCTAssertEqual(try hierarchy(in: answer, answering: requestID), first)
            }
        }

        // Another connection counts from 1 again; within it the IDs are stable just the same.
        client.close()
        let (next, _) = try await connectAndHandshake(port: port)
        try await next.send(Frame(requestID: 1, body: .getHierarchy))
        let nextAnswer = try await next.nextFrame()
        XCTAssertEqual(try hierarchy(in: nextAnswer, answering: 1), first)
    }

    func test_S_HIER_11_S_HIER_12_getSubtreeOverAConnection() async throws {
        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        let wholeAnswer = try await client.nextFrame()
        let whole = try hierarchy(in: wholeAnswer, answering: 1)
        // The first window's second node: a layer below the window, with a parent of its own.
        let root = try XCTUnwrap(whole.nodes.dropFirst().first, "the host shows more than a window")

        // P-HIER-10: the root and its descendants, exactly as in the hierarchy.
        try await client.send(Frame(requestID: 2, body: .getSubtree(rootID: root.id)))
        let subtreeAnswer = try await client.nextFrame()
        let subtree = try hierarchy(in: subtreeAnswer, answering: 2)
        let start = try XCTUnwrap(whole.nodes.firstIndex { $0.id == root.id })
        XCTAssertEqual(subtree.nodes.first, root)
        XCTAssertEqual(subtree.nodes, Array(whole.nodes[start..<(start + subtree.nodes.count)]))
        XCTAssertEqual(subtree.keyWindowID, whole.keyWindowID)

        // P-HIER-11: the request and the answer of the `subtree` fixture. A new connection has
        // given out an ID for each layer it read, far fewer than 99.
        XCTAssertLessThan(whole.nodes.count, 99)
        try await client.send(FrameCodec.framed(try Fixtures.data("subtree/03-c2s-get-subtree.bin")))
        let missing = try await client.nextFrame()
        XCTAssertEqual(missing, try Fixtures.frame("subtree/04-s2c-error.bin"))
        // The connection stays.
        try await client.send(Frame(requestID: 3, body: .getAppIcon))
        let icon = try await client.nextFrame()
        XCTAssertEqual(icon?.requestID, 3)
    }

    func test_S_HIER_07_answersAppNotActiveWhenNotActive() async throws {
        let captures = CaptureCounter()
        let server = makeServer { configuration in
            var app = TestHostApp()
            app.captureHierarchy = { context in
                captures.count += 1
                return HierarchyCapture.capture(context)
            }
            configuration.hostApp = app
        }
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        // The fixture's request and its answer, with the same request_id.
        let request = try Fixtures.frame("app-not-active/02-c2s-get-hierarchy.bin")
        let refusal = try Fixtures.frame("app-not-active/03-s2c-error.bin")
        XCTAssertEqual(refusal, Frame(requestID: request.requestID, body: .error(Self.notActive)))

        let changes: [(Notification.Name, AppState)] = [
            (UIApplication.willResignActiveNotification, .inactive),
            (UIApplication.didEnterBackgroundNotification, .background),
            (UIApplication.willEnterForegroundNotification, .inactive)
        ]
        for (name, state) in changes {
            try await server.post(name, expecting: state)
            let event = try await client.nextFrame()
            XCTAssertEqual(event, Frame(requestID: 0, body: .appStateChanged(state)))
            try await client.send(request)
            let answer = try await client.nextFrame()
            XCTAssertEqual(answer, refusal, "\(state)")
        }
        // Refused without looking: the layers are not read while the app is not active. A
        // capture would have run on the main thread before its answer was sent.
        let capturesWhileNotActive = await MainActor.run { captures.count }
        XCTAssertEqual(capturesWhileNotActive, 0, "the layers were read while the app was not active")

        // Active again: the same request is answered with the hierarchy.
        try await server.post(UIApplication.didBecomeActiveNotification, expecting: .active)
        let event = try await client.nextFrame()
        XCTAssertEqual(event, Frame(requestID: 0, body: .appStateChanged(.active)))
        try await client.send(request)
        let answer = try await client.nextFrame()
        XCTAssertFalse(try hierarchy(in: answer, answering: request.requestID).nodes.isEmpty)
        let capturesInAll = await MainActor.run { captures.count }
        XCTAssertEqual(capturesInAll, 1)
    }

    func test_S_HIER_07_answersAppNotActiveWhenTheAppLeavesDuringTheCapture() async throws {
        let server = makeServer { configuration in
            let center = configuration.notificationCenter
            var app = TestHostApp()
            app.captureHierarchy = { context in
                let hierarchy = HierarchyCapture.capture(context)
                // The app resigns while the layers are being read. Posted on the main thread, the
                // notification has reached the server's observer when `post` returns.
                center.post(name: UIApplication.willResignActiveNotification, object: nil)
                return hierarchy
            }
            configuration.hostApp = app
        }
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        // The event first, then the refusal: no hierarchy follows the news that the app left.
        let event = try await client.nextFrame()
        XCTAssertEqual(event, Frame(requestID: 0, body: .appStateChanged(.inactive)))
        let answer = try await client.nextFrame()
        XCTAssertEqual(answer, Frame(requestID: 1, body: .error(Self.notActive)))

        // The connection is still good.
        try await client.send(Frame(requestID: 2, body: .getAppIcon))
        let icon = try await client.nextFrame()
        XCTAssertEqual(icon?.requestID, 2)
    }
}
