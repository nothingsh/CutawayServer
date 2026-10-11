import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// Malformed frames, and frames that should not appear.
final class FramingTests: ServerTestCase {
    /// Byte sequences that are not a valid frame, each for a different reason.
    private func malformedInputs() throws -> [(name: String, bytes: Data)] {
        let hello = try Fixtures.data("handshake/01-c2s-hello.bin")
        var wrongIdentifier = hello
        wrongIdentifier[4] = UInt8(ascii: "X")
        let unknownMember = settingBodyType(
            200,
            in: FrameCodec.encode(Frame(requestID: 1, body: .getAppIcon))
        )
        return [
            // 268435457 bytes announced: one more than P-FRAME-03 allows. No payload follows.
            ("a length over the limit", Data([0x01, 0x00, 0x00, 0x10])),
            ("a wrong file identifier", FrameCodec.framed(wrongIdentifier)),
            ("a payload that fails verification", FrameCodec.framed(Data(repeating: 0xEE, count: 40))),
            ("an empty payload", FrameCodec.framed(Data())),
            ("an unknown union member", FrameCodec.framed(unknownMember))
        ]
    }

    /// Reads until the connection ends. The server may send one `MalformedFrame` error first.
    private func assertRejected(_ client: TestClient, _ name: String) async throws {
        var frames: [Frame] = []
        while let frame = try await client.nextFrame() {
            frames.append(frame)
        }
        XCTAssertEqual(
            frames,
            [
                Frame(
                    requestID: 0,
                    body: .error(WireError(code: .malformedFrame, message: "the frame is malformed"))
                )
            ],
            name
        )
    }

    func test_S_CONN_05_malformedFramesCloseTheConnection() async throws {
        let server = makeServer()
        let port = try await server.start()

        for (name, bytes) in try malformedInputs() {
            // As the first thing a client sends...
            let early = try await connect(to: port)
            try await early.send(bytes)
            try await assertRejected(early, "\(name), before the handshake")

            // ...and after a handshake.
            let (late, _) = try await connectAndHandshake(port: port)
            try await late.send(bytes)
            try await assertRejected(late, "\(name), after the handshake")
        }

        // The server still serves.
        let (client, _) = try await connectAndHandshake(port: port)
        try await client.send(Frame(requestID: 1, body: .getAppIcon))
        let answer = try await client.nextFrame()
        XCTAssertEqual(answer?.requestID, 1)
    }

    func test_S_CONN_05_randomBytesDoNotCrashTheServer() async throws {
        let server = makeServer()
        let port = try await server.start()
        var generator = SeededGenerator(seed: 0xC07A_0002)

        for round in 0..<40 {
            // Half of the rounds shake hands first, so that the noise meets a ready session.
            let client: TestClient
            if round % 2 == 0 {
                client = try await connect(to: port)
            } else {
                (client, _) = try await connectAndHandshake(port: port)
            }
            var noise = generator.bytes(count: Int.random(in: 1...2000, using: &generator))
            if round % 4 < 2 {
                // A small length, so that the server goes on to verify the bytes after it.
                noise.replaceSubrange(0..<min(4, noise.count), with: [UInt8(noise.count % 200), 0, 0, 0])
            }
            // The server may close while we are still sending.
            try? await client.send(noise)
            client.close()
        }

        // A crash would have ended this test process. The server still serves.
        let (client, _) = try await connectAndHandshake(port: port)
        try await client.send(Frame(requestID: 1, body: .getAppIcon))
        let answer = try await client.nextFrame()
        XCTAssertEqual(answer?.requestID, 1)
    }

    func test_S_CONN_05_sentBytesUseTheStreamFormat() async throws {
        let server = makeServer()
        let port = try await server.start()
        let client = try await connect(to: port)
        try await client.send(Fixtures.data("handshake/c2s.stream"))

        // Read the raw bytes of the server's two frames, the way `.stream` fixtures lay them out.
        var bodies: [Message?] = []
        for _ in 0..<2 {
            let prefix = try await client.read(exactly: 4)
            let length = prefix.enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
            XCTAssertGreaterThanOrEqual(length, 8)
            let payload = try await client.read(exactly: length)
            // A plain buffer: the root offset, then the file identifier. Not size-prefixed.
            XCTAssertEqual(Array(payload[4..<8]), Array("CTWY".utf8))
            bodies.append(try FrameCodec.decode(payload).body)
        }
        guard case .hello? = bodies[0], case .appStateChanged? = bodies[1] else {
            return XCTFail("expected Hello and AppStateChanged, got \(bodies)")
        }

        // The fixture's own bytes have the same layout.
        let fixture = try Fixtures.data("handshake/s2c.stream")
        XCTAssertEqual(Array(fixture[8..<12]), Array("CTWY".utf8))
    }

    func test_S_CONN_09_unexpectedFramesKeepTheConnection() async throws {
        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        let unexpected: [Message?] = [
            .hello(Hello(version: .current, role: .client, client: ClientInfo(name: "x", version: "1"))),
            nil,
            .appStateChanged(.active),
            .appIcon(AppIcon(image: nil)),
            .hierarchy(Hierarchy(nodes: [], keyWindowID: 0)),
            .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: [])),
            .streamEnd(StreamEnd(status: .completed, chunkCount: 0)),
            .error(WireError(code: .unknown, message: ""))
        ]
        for (index, body) in unexpected.enumerated() {
            let requestID = UInt32(index + 1)
            try await client.send(Frame(requestID: requestID, body: body))
            let answer = try await client.nextFrame()
            XCTAssertEqual(answer?.requestID, requestID, "\(String(describing: body))")
            guard case .error(let error)? = answer?.body else {
                XCTFail("expected Error for \(String(describing: body)), got \(String(describing: answer))")
                continue
            }
            XCTAssertEqual(error.code, .unexpectedMessage, "\(String(describing: body))")
        }

        // The connection is still good for a normal request.
        try await client.send(Frame(requestID: 100, body: .getAppIcon))
        let answer = try await client.nextFrame()
        XCTAssertEqual(answer?.requestID, 100)
        guard case .appIcon? = answer?.body else {
            return XCTFail("expected AppIcon, got \(String(describing: answer))")
        }
    }
}
