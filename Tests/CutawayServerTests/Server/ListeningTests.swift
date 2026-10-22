import CutawayWire
import Foundation
import Network
import UIKit
import XCTest

@testable import CutawayServer

/// `start()`, the choice of port, and listening again after a client left.
final class ListeningTests: ServerTestCase {
    func test_S_API_01_startFromABackgroundThreadListensOnce() async throws {
        // The shared server listens on the protocol's ports: a client that scans them, such as
        // Cutaway on the Mac, can take its session while this test runs.
        let shared = ServerController.shared
        let attemptsBefore = await shared.listeningStatus().settledAttempts

        // The public entry point, called many times at once from background threads.
        DispatchQueue.concurrentPerform(iterations: 32) { _ in CutawayServer.start() }
        CutawayServer.start()

        let deadline = Date().addingTimeInterval(5)
        var status = await shared.listeningStatus()
        while status.port == nil, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
            status = await shared.listeningStatus()
        }
        let port = try XCTUnwrap(status.port, "start() did not make the server listen")
        XCTAssertTrue((48160...48167).contains(port))

        // Exactly one port of the range answers as this app.
        var ownServers = 0
        for candidate in UInt16(48160)...48167 {
            guard let client = try? await connect(to: candidate) else { continue }
            try await client.send(Fixtures.data("handshake/c2s.stream"))
            if case .hello(let hello)? = try? await client.nextFrame(timeout: 2)?.body,
               hello.app?.bundleID == "dev.cutaway.testhost" {
                ownServers += 1
            }
            client.close()
        }
        XCTAssertEqual(ownServers, 1)

        // Later calls change nothing: no second attempt to listen was made.
        CutawayServer.start()
        try await Task.sleep(nanoseconds: 200_000_000)
        status = await shared.listeningStatus()
        XCTAssertEqual(status.port, port)
        XCTAssertEqual(status.settledAttempts, attemptsBefore + 1)

        await shared.stop()
    }

    func test_S_API_01_listeningBeginsWhenTheAppBecomesActive() async throws {
        let server = makeServer { $0.initialAppState = .inactive }
        server.controller.start()

        // The server knows the state and does not listen.
        var status = try await server.waitForStatus("the first app state") { $0.appState != nil }
        XCTAssertEqual(status.appState, .inactive)
        try await Task.sleep(nanoseconds: 200_000_000)
        status = await server.controller.listeningStatus()
        XCTAssertNil(status.port)
        XCTAssertEqual(status.settledAttempts, 0, "no attempt to listen should be made while inactive")

        try await server.post(UIApplication.didBecomeActiveNotification, expecting: .active)
        let port = try await server.waitForPort()
        let client = try await connect(to: port)
        let (_, state) = try await handshake(client)
        XCTAssertEqual(state, .active)
    }

    func test_S_CONN_01_takesTheFirstFreePort() async throws {
        XCTAssertEqual(ServerConfiguration().ports, 48160...48167)

        // 48160 is taken: by this holder, or already by another process.
        let holder = PortHolder(port: 48160)
        // The expectation below needs 48161 to be free.
        try XCTSkipIf(
            PortHolder(port: 48161) == nil,
            "port 48161 is in use by another process; quit other apps that embed CutawayServer"
        )

        // The acceptance test names the protocol's ports, so this server uses them.
        let server = makeServer { $0.ports = ServerConfiguration().ports }
        let port = try await server.start()
        XCTAssertEqual(port, 48161)
        try await handshake(connect(to: port))
        withExtendedLifetime(holder) {}
    }

    func test_S_CONN_01_doesNotListenWhenEveryPortIsTaken() async throws {
        // Hold every port that is not already held by someone else.
        var holders = kTestPorts.compactMap(PortHolder.init(port:))
        XCTAssertFalse(holders.isEmpty)

        let server = makeServer()
        server.controller.start()
        let status = try await server.waitForStatus("the attempt to listen to end") {
            $0.settledAttempts == 1
        }
        XCTAssertNil(status.port, "every port is taken, so the server must not listen")

        // P-TRANS-02: it tries again the next time the app becomes active.
        holders.removeAll()
        try await server.post(UIApplication.willResignActiveNotification, expecting: .inactive)
        try await server.post(UIApplication.didBecomeActiveNotification, expecting: .active)
        let port = try await server.waitForPort()
        XCTAssertTrue(kTestPorts.contains(port))
        try await handshake(connect(to: port))
    }

    func test_S_CONN_01_listensOnLoopbackOnly() async throws {
        // An IPv4 address of this machine that is not the loopback address.
        var otherAddress: String?
        var list: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&list) == 0 {
            var entry = list
            while let current = entry {
                let flags = Int32(current.pointee.ifa_flags)
                if let address = current.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET),
                   flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(
                        address,
                        socklen_t(address.pointee.sa_len),
                        &host,
                        socklen_t(host.count),
                        nil,
                        0,
                        NI_NUMERICHOST
                    ) == 0 {
                        // Up to the terminating NUL, with invalid UTF-8 repaired.
                        otherAddress = host.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                        break
                    }
                }
                entry = current.pointee.ifa_next
            }
            freeifaddrs(list)
        }
        guard let address = otherAddress else {
            throw XCTSkip("this machine has no non-loopback IPv4 address")
        }

        let server = makeServer()
        let port = try await server.start()
        do {
            let client = try await TestClient.connect(port: port, host: address)
            client.close()
            XCTFail("the server accepted a connection on \(address):\(port)")
        } catch is TestClientError {
            // Refused, as it should be.
        }
        // The loopback address still works.
        try await handshake(connect(to: port))
    }

    func test_S_CONN_03_listensAgainAfterTheClientDisconnects() async throws {
        let server = makeServer()
        let port = try await server.start()

        let first = try await connect(to: port)
        try await handshake(first)
        first.close()

        // Within one second, on the same port.
        let started = Date()
        let (second, _) = try await connectAndHandshake(port: port, within: 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        let status = await server.controller.listeningStatus()
        XCTAssertEqual(status.port, port)

        // And again, to see that nothing is used up.
        second.close()
        _ = try await connectAndHandshake(port: port, within: 1)
    }

    func test_S_CONN_03_S_HIER_01_survivesClientsThatLeaveMidRequest() async throws {
        let server = makeServer()
        let port = try await server.start()

        // Each client asks for the icon or the hierarchy and is gone before the answer is ready.
        for round in 0..<20 {
            let (client, _) = try await connectAndHandshake(port: port)
            try await client.send(Frame(requestID: 1, body: round.isMultiple(of: 2) ? .getAppIcon : .getHierarchy))
            client.close()
        }

        let (client, _) = try await connectAndHandshake(port: port)
        try await client.send(Frame(requestID: 1, body: .getAppIcon))
        try await client.send(Frame(requestID: 2, body: .getHierarchy))
        let icon = try await client.nextFrame()
        XCTAssertEqual(icon?.requestID, 1)
        let answer = try await client.nextFrame()
        XCTAssertEqual(answer?.requestID, 2)
        guard case .hierarchy? = answer?.body else {
            return XCTFail("expected Hierarchy, got \(String(describing: answer))")
        }
    }

    /// Starts a bare listener and returns the port it settles on.
    private func settle(_ listener: Listener, on queue: DispatchQueue, preferring port: UInt16?) async -> UInt16? {
        await withCheckedContinuation { continuation in
            queue.async {
                // The waiter keeps itself alive until it hears the listener settle.
                let waiter = SettleWaiter { port in continuation.resume(returning: port) }
                listener.delegate = waiter
                listener.start(preferring: port)
            }
        }
    }

    func test_S_CONN_03_listeningAgainPrefersThePreviousPort() async throws {
        // P-TRANS-04: when the listener has to be set up again, the port it had comes first.
        let previous = kTestPorts.lowerBound + 3
        try XCTSkipIf(PortHolder(port: previous) == nil, "port \(previous) is in use by another process")
        let queue = DispatchQueue(label: "dev.cutaway.tests.listener")
        let listener = Listener(queue: queue, ports: kTestPorts)

        let preferred = await settle(listener, on: queue, preferring: previous)
        XCTAssertEqual(preferred, previous, "the previous port is free, so it is taken first")
        await withCheckedContinuation { continuation in
            queue.async { listener.cancel { continuation.resume() } }
        }

        // The previous port is gone: fall back to the first free port of the range.
        let holder = PortHolder(port: previous)
        XCTAssertNotNil(holder)
        let firstFree = kTestPorts.first { PortHolder(port: $0) != nil }
        let fallback = await settle(listener, on: queue, preferring: previous)
        XCTAssertEqual(fallback, firstFree)
        XCTAssertNotEqual(fallback, previous)
        await withCheckedContinuation { continuation in
            queue.async { listener.cancel { continuation.resume() } }
        }
        withExtendedLifetime(holder) {}
    }
}

/// Hears the first attempt of a bare listener to settle, and nothing after it. A listener
/// holds its delegate weakly, so the waiter keeps itself alive until then.
private final class SettleWaiter: ListenerDelegate, @unchecked Sendable {
    // Touched on the listener's queue only.
    private var onSettled: ((UInt16?) -> Void)?
    private var keptAlive: SettleWaiter?

    init(onSettled: @escaping (UInt16?) -> Void) {
        self.onSettled = onSettled
        keptAlive = self
    }

    func listenerDidSettle(on port: UInt16?) {
        let onSettled = self.onSettled
        self.onSettled = nil
        keptAlive = nil
        onSettled?(port)
    }

    func listenerDidAccept(_ connection: NWConnection) {}

    func listenerDidFail() {}
}
