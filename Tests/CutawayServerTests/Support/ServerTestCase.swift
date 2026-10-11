import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// The ports test servers listen on: outside the protocol's range (P-TRANS-02), so that a
/// client scanning that range, such as Cutaway on the Mac, never takes a test server's only
/// session. Only tests that assert the protocol's range itself use that range.
let kTestPorts: ClosedRange<UInt16> = 48260...48267

/// A server of its own for one test, with its own notification center: tests announce
/// state changes there, and UIKit never hears them.
final class TestServer: Sendable {
    let controller: ServerController
    let center: NotificationCenter

    /// By default the app counts as active from the start and the server uses `kTestPorts`.
    init(_ configure: (inout ServerConfiguration) -> Void = { _ in }) {
        let center = NotificationCenter()
        var configuration = ServerConfiguration()
        configuration.ports = kTestPorts
        configuration.initialAppState = .active
        // Set before `configure`, so that it can hand the center to closures of its own.
        configuration.notificationCenter = center
        configure(&configuration)
        configuration.notificationCenter = center
        self.center = center
        controller = ServerController(configuration: configuration)
    }

    /// Polls the server until `condition` holds.
    func waitForStatus(
        _ what: String,
        timeout: TimeInterval = 5,
        until condition: (ServerController.ListeningStatus) -> Bool
    ) async throws -> ServerController.ListeningStatus {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let status = await controller.listeningStatus()
            if condition(status) { return status }
            guard Date() < deadline else {
                throw TestClientError(description: "timed out waiting for \(what); status: \(status)")
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    /// Starts the server and returns the port it listens on.
    func start() async throws -> UInt16 {
        controller.start()
        return try await waitForPort()
    }

    func waitForPort() async throws -> UInt16 {
        let status = try await waitForStatus("the server to listen") { $0.port != nil }
        return try XCTUnwrap(status.port)
    }

    /// Announces a state change the way UIKit would, and waits until the server has seen it.
    func post(_ name: Notification.Name, expecting state: AppState) async throws {
        center.post(name: name, object: nil)
        _ = try await waitForStatus("the app state \(state)") { $0.appState == state }
    }
}

/// The base class of the server tests: it stops servers and closes clients after each test.
class ServerTestCase: XCTestCase {
    private var servers: [TestServer] = []
    private var clients: [TestClient] = []

    override func tearDown() async throws {
        clients.forEach { $0.close() }
        clients = []
        for server in servers {
            await server.controller.stop()
        }
        servers = []
        try await super.tearDown()
    }

    func makeServer(_ configure: (inout ServerConfiguration) -> Void = { _ in }) -> TestServer {
        let server = TestServer(configure)
        servers.append(server)
        return server
    }

    func connect(to port: UInt16, host: String = "127.0.0.1") async throws -> TestClient {
        let client = try await TestClient.connect(port: port, host: host)
        clients.append(client)
        return client
    }

    /// Sends the client's hello of the `handshake` fixture and returns the server's two frames.
    @discardableResult
    func handshake(_ client: TestClient) async throws -> (hello: Hello, state: AppState) {
        try await client.send(Fixtures.data("handshake/c2s.stream"))
        let first = try await client.nextFrame()
        guard case .hello(let hello)? = first?.body else {
            throw TestClientError(description: "expected the server's Hello, got \(String(describing: first))")
        }
        let second = try await client.nextFrame()
        guard case .appStateChanged(let state)? = second?.body else {
            throw TestClientError(description: "expected AppStateChanged, got \(String(describing: second))")
        }
        return (hello, state)
    }

    /// Connects and completes the handshake, retrying while the server still holds the
    /// previous connection (it answers `Busy` until it has noticed that the client left).
    func connectAndHandshake(
        port: UInt16,
        within timeout: TimeInterval = 2
    ) async throws -> (client: TestClient, state: AppState) {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let client = try await connect(to: port)
            try await client.send(Fixtures.data("handshake/c2s.stream"))
            let first = try await client.nextFrame()
            if case .hello? = first?.body {
                let second = try await client.nextFrame()
                guard case .appStateChanged(let state)? = second?.body else {
                    throw TestClientError(
                        description: "expected AppStateChanged, got \(String(describing: second))"
                    )
                }
                return (client, state)
            }
            client.close()
            guard Date() < deadline else {
                throw TestClientError(
                    description: "no handshake within \(timeout) s; last answer: \(String(describing: first))"
                )
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Asserts that the server closed the connection without sending anything more.
    func assertClosed(_ client: TestClient, file: StaticString = #filePath, line: UInt = #line) async throws {
        let frame = try await client.nextFrame()
        XCTAssertNil(frame, "expected the connection to end", file: file, line: line)
    }
}
