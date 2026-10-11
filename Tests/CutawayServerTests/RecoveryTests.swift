import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// Listening again after the listener failed, and keepalive on connections.
/// Opens ports and connects: the user runs these.
final class RecoveryTests: ServerTestCase {
    func test_S_CONN_10_listensAgainAfterTheListenerFails() async throws {
        let server = makeServer()
        let port = try await server.start()
        let attempts = await server.controller.listeningStatus().settledAttempts

        let failedAt = Date()
        await server.controller.simulateListenerFailure()
        var status = await server.controller.listeningStatus()
        XCTAssertNil(status.port)
        XCTAssertEqual(status.pendingRelistenDelay, 0.5)

        // Within one second, on the same port.
        status = try await server.waitForStatus("the server to listen again", timeout: 1) {
            $0.port != nil
        }
        XCTAssertLessThan(Date().timeIntervalSince(failedAt), 1)
        XCTAssertEqual(status.port, port)
        XCTAssertEqual(status.settledAttempts, attempts + 1)
        XCTAssertNil(status.pendingRelistenDelay)
        try await handshake(connect(to: port))
    }

    func test_S_CONN_10_backsOffWhileEveryPortIsTaken() async throws {
        let port = kTestPorts.lowerBound + 5
        let server = makeServer {
            $0.ports = port...port
            $0.relisten = .init(initialDelay: 0.25, maximumDelay: 1)
        }
        _ = try await server.start()
        let attempts = await server.controller.listeningStatus().settledAttempts

        await server.controller.simulateListenerFailure()
        var holder: PortHolder? = try await hold(port)
        let first = await server.controller.listeningStatus().pendingRelistenDelay
        XCTAssertEqual(first, 0.25)

        // Each attempt finds the port taken and waits twice as long, up to the maximum.
        var delays: [TimeInterval?] = []
        for attempt in 1...3 {
            let status = try await server.waitForStatus("attempt \(attempt)", timeout: 3) {
                $0.settledAttempts == attempts + attempt
            }
            XCTAssertNil(status.port)
            delays.append(status.pendingRelistenDelay)
        }
        XCTAssertEqual(delays, [0.5, 1, 1])

        // The port is free again: the next attempt takes it.
        holder = nil
        let listening = try await server.waitForPort()
        XCTAssertEqual(listening, port)
        try await handshake(connect(to: port))
        withExtendedLifetime(holder) {}
    }

    func test_S_CONN_10_stopsRetryingWhenTheAppIsNotActive() async throws {
        let port = kTestPorts.lowerBound + 6
        let server = makeServer {
            $0.ports = port...port
            $0.relisten = .init(initialDelay: 0.25, maximumDelay: 0.5)
        }
        _ = try await server.start()
        let attempts = await server.controller.listeningStatus().settledAttempts

        await server.controller.simulateListenerFailure()
        var holder: PortHolder? = try await hold(port)
        _ = try await server.waitForStatus("the first retry", timeout: 2) {
            $0.settledAttempts == attempts + 1
        }

        try await server.post(UIApplication.willResignActiveNotification, expecting: .inactive)
        var status = await server.controller.listeningStatus()
        XCTAssertNil(status.pendingRelistenDelay)
        try await Task.sleep(nanoseconds: 1_000_000_000)
        status = await server.controller.listeningStatus()
        XCTAssertEqual(status.settledAttempts, attempts + 1, "no attempt while the app is not active")
        XCTAssertNil(status.port)

        // P-TRANS-02: the next activation listens.
        holder = nil
        try await server.post(UIApplication.didBecomeActiveNotification, expecting: .active)
        let listening = try await server.waitForPort()
        XCTAssertEqual(listening, port)
        try await handshake(connect(to: port))
        withExtendedLifetime(holder) {}
    }

    func test_S_CONN_10_aFailureWhileInactiveWaitsForActivation() async throws {
        let server = makeServer()
        let port = try await server.start()
        let attempts = await server.controller.listeningStatus().settledAttempts
        // The server keeps listening when the app leaves the active state.
        try await server.post(UIApplication.willResignActiveNotification, expecting: .inactive)
        let stillListening = await server.controller.listeningStatus().port
        XCTAssertEqual(stillListening, port)

        await server.controller.simulateListenerFailure()
        var status = await server.controller.listeningStatus()
        XCTAssertNil(status.port)
        XCTAssertNil(status.pendingRelistenDelay, "no retry while the app is not active")
        try await Task.sleep(nanoseconds: 1_000_000_000)
        status = await server.controller.listeningStatus()
        XCTAssertNil(status.port)
        XCTAssertEqual(status.settledAttempts, attempts)

        try await server.post(UIApplication.didBecomeActiveNotification, expecting: .active)
        let listening = try await server.waitForPort()
        XCTAssertEqual(listening, port)
        try await handshake(connect(to: port))
    }

    func test_S_CONN_11_acceptedConnectionsUseKeepalive() async throws {
        let server = makeServer()
        let port = try await server.start()
        try await handshake(connect(to: port))
        let keepalive = await server.controller.connectionKeepalive()
        XCTAssertEqual(keepalive, TCPKeepalive(idle: 10, interval: 5, count: 3))
    }

    func test_S_CONN_11_aConnectionLostToKeepaliveFreesTheSession() async throws {
        let server = makeServer()
        let port = try await server.start()
        let first = try await connect(to: port)
        try await handshake(first)

        let lostAt = Date()
        await server.controller.simulateConnectionFailure()
        try await assertClosed(first)

        // The session's place is free: the next client is not told Busy.
        let second = try await connect(to: port)
        try await handshake(second)
        XCTAssertLessThan(Date().timeIntervalSince(lostAt), 1)
        try await second.send(Frame(requestID: 1, body: .getAppIcon))
        let answer = try await second.nextFrame()
        XCTAssertEqual(answer?.requestID, 1)
    }

    /// Takes `port` as soon as the server's failed listener has released it, and before the
    /// first retry, which comes after at least 0.25 s.
    private func hold(_ port: UInt16) async throws -> PortHolder {
        let deadline = Date().addingTimeInterval(0.2)
        while true {
            if let holder = PortHolder(port: port) { return holder }
            guard Date() < deadline else {
                throw TestClientError(description: "port \(port) was not released within 0.2 s")
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }
}
