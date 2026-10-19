import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// The handshake, and the one-client rule.
final class HandshakeTests: ServerTestCase {
    func test_S_CONN_04_answersTheHandshakeFixture() async throws {
        let server = makeServer()
        let port = try await server.start()
        let client = try await connect(to: port)
        try await client.send(Fixtures.data("handshake/c2s.stream"))

        let frame = try await client.nextFrame()
        XCTAssertEqual(frame?.requestID, 0)
        guard case .hello(let hello)? = frame?.body else {
            return XCTFail("expected Hello, got \(String(describing: frame))")
        }
        // The same shape as the fixture's server hello.
        XCTAssertEqual(hello.role, .server)
        XCTAssertEqual(hello.version, ProtocolVersion(major: 1, minor: 2))
        XCTAssertNil(hello.client)

        // The app's fields are the real ones: read here independently of the server.
        let expected = await MainActor.run {
            let info = Bundle.main.infoDictionary ?? [:]
            return AppInfo(
                name: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "",
                bundleID: Bundle.main.bundleIdentifier ?? "",
                appVersion: info["CFBundleShortVersionString"] as? String ?? "",
                deviceName: ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"]
                    ?? UIDevice.current.name,
                deviceKind: UIDevice.current.userInterfaceIdiom == .pad ? .pad : .phone,
                isSimulator: true,
                osName: UIDevice.current.systemName,
                osVersion: UIDevice.current.systemVersion,
                screenSize: WireSize(
                    width: Double(UIScreen.main.bounds.width),
                    height: Double(UIScreen.main.bounds.height)
                ),
                screenScale: Float(UIScreen.main.scale),
                serverVersion: "1.1.0"
            )
        }
        let app = try XCTUnwrap(hello.app)
        XCTAssertEqual(app, expected)
        // And they are not empty or made up.
        XCTAssertEqual(app.bundleID, "dev.cutaway.testhost")
        XCTAssertEqual(app.name, "TestHost")
        XCTAssertEqual(app.appVersion, "0.1.0")
        XCTAssertFalse(app.deviceName.isEmpty)
        XCTAssertFalse(app.osVersion.isEmpty)
        XCTAssertGreaterThan(app.screenSize.width, 0)
        XCTAssertGreaterThan(app.screenSize.height, 0)
        XCTAssertGreaterThan(app.screenScale, 0)
    }

    func test_S_CONN_04_acceptsAHandshakeThatArrivesInPieces() async throws {
        let server = makeServer()
        let port = try await server.start()
        let client = try await connect(to: port)

        // TCP may deliver the client's hello in any number of pieces: here, one byte at a time.
        for byte in try Fixtures.data("handshake/c2s.stream") {
            try await client.send(Data([byte]))
        }
        let first = try await client.nextFrame()
        guard case .hello? = first?.body else {
            return XCTFail("expected Hello, got \(String(describing: first))")
        }
        let second = try await client.nextFrame()
        XCTAssertEqual(second, Frame(requestID: 0, body: .appStateChanged(.active)))
    }

    func test_S_CONN_04_mapsTheDeviceIdiom() {
        XCTAssertEqual(LiveHostApp.deviceKind(for: .phone), .phone)
        XCTAssertEqual(LiveHostApp.deviceKind(for: .pad), .pad)
        XCTAssertEqual(LiveHostApp.deviceKind(for: .mac), .mac)
        XCTAssertEqual(LiveHostApp.deviceKind(for: .tv), .unknown)
        XCTAssertEqual(LiveHostApp.deviceKind(for: .carPlay), .unknown)
        XCTAssertEqual(LiveHostApp.deviceKind(for: .unspecified), .unknown)
    }

    func test_S_CONN_04_versionMismatchGetsHelloThenClose() async throws {
        let server = makeServer()
        let port = try await server.start()
        let client = try await connect(to: port)
        // Since protocol 1.0 the fixture is a 1.0 client at a 0.5 server, so the client here is
        // the other way round: one of protocol 0 (P-HELLO-03).
        try await client.send(SessionHarness.clientHello(version: ProtocolVersion(major: 0, minor: 5)))

        // Our own hello, with our version, exactly as after a successful handshake...
        let frame = try await client.nextFrame()
        XCTAssertEqual(frame?.requestID, 0)
        guard case .hello(let hello)? = frame?.body else {
            return XCTFail("expected Hello, got \(String(describing: frame))")
        }
        XCTAssertEqual(hello.role, .server)
        XCTAssertEqual(hello.version, ProtocolVersion(major: 1, minor: 2))
        XCTAssertEqual(hello.app?.bundleID, "dev.cutaway.testhost")
        // ...then the end of the connection, with no state event or anything else before it.
        try await assertClosed(client)

        // The failed handshake does not keep the server busy.
        _ = try await connectAndHandshake(port: port)
    }

    func test_S_CONN_04_nonHelloBeforeHandshakeIsRejected() async throws {
        let server = makeServer()
        let port = try await server.start()

        let notHandshakes: [Frame] = [
            Frame(requestID: 1, body: .getAppIcon),
            Frame(requestID: 2, body: nil),
            // A hello, but not a client's.
            Frame(requestID: 0, body: .hello(Hello(version: .current, role: .server))),
            // A hello without a version.
            Frame(requestID: 0, body: .hello(Hello(version: nil, role: .client)))
        ]
        for first in notHandshakes {
            let client = try await connect(to: port)
            // Two frames in one write: the server must not act on the second one.
            try await client.send(
                FrameCodec.framed(FrameCodec.encode(first))
                    + FrameCodec.framed(FrameCodec.encode(Frame(requestID: 9, body: .getAppIcon)))
            )
            let frame = try await client.nextFrame()
            XCTAssertEqual(frame?.requestID, first.requestID, "\(first)")
            guard case .error(let error)? = frame?.body else {
                XCTFail("expected Error for \(first), got \(String(describing: frame))")
                continue
            }
            XCTAssertEqual(error.code, .unexpectedMessage, "\(first)")
            try await assertClosed(client)
        }

        _ = try await connectAndHandshake(port: port)
    }

    func test_S_CONN_04_closesWhenNoHandshakeArrives() async throws {
        XCTAssertEqual(ServerConfiguration().handshakeTimeout, 5, "P-HELLO-06 says five seconds")

        let server = makeServer { $0.handshakeTimeout = 0.4 }
        let port = try await server.start()

        // A silent client.
        let started = Date()
        let silent = try await connect(to: port)
        try await assertClosed(silent)
        let elapsed = Date().timeIntervalSince(started)
        XCTAssertGreaterThan(elapsed, 0.3, "closed before the timeout")
        XCTAssertLessThan(elapsed, 3, "closed long after the timeout")

        // A client that sends only part of a frame is no better. (The silent client's session
        // ended on the server's side, so the server is free again.)
        let partial = try await connect(to: port)
        try await partial.send(Data(Fixtures.data("handshake/c2s.stream").prefix(7)))
        try await assertClosed(partial)

        // A client that shook hands is not cut off by the timer.
        let (client, _) = try await connectAndHandshake(port: port)
        try await Task.sleep(nanoseconds: 700_000_000)
        try await client.send(Frame(requestID: 1, body: .getAppIcon))
        let answer = try await client.nextFrame()
        XCTAssertEqual(answer?.requestID, 1)
    }

    func test_S_CONN_02_secondClientIsRejected() async throws {
        let server = makeServer()
        let port = try await server.start()
        let first = try await connect(to: port)
        try await handshake(first)

        // The second client writes before it reads, as a real client would.
        let second = try await connect(to: port)
        try await second.send(Fixtures.data("handshake/c2s.stream"))
        let only = try await second.nextFrame()
        XCTAssertEqual(only, try Fixtures.frame("busy/01-s2c-error.bin"))
        try await assertClosed(second)

        // A third one, silent this time, is told the same.
        let third = try await connect(to: port)
        let again = try await third.nextFrame()
        XCTAssertEqual(again, try Fixtures.frame("busy/01-s2c-error.bin"))
        try await assertClosed(third)

        // Many more: none of them takes the session away or wears the server out.
        for _ in 0..<20 {
            let extra = try await connect(to: port)
            let rejection = try await extra.nextFrame()
            XCTAssertEqual(rejection, try Fixtures.frame("busy/01-s2c-error.bin"))
            extra.close()
        }

        // The first client is not disturbed.
        try await first.send(Frame(requestID: 1, body: .getAppIcon))
        let answer = try await first.nextFrame()
        XCTAssertEqual(answer?.requestID, 1)
        guard case .appIcon? = answer?.body else {
            return XCTFail("expected AppIcon, got \(String(describing: answer))")
        }
    }
}
