import CutawayWire
import Foundation
import XCTest

/// Frames decode into the project's value types and encode back.
final class FrameCodecTests: XCTestCase {
    private let demoApp = AppInfo(
        name: "Demo",
        bundleID: "dev.cutaway.demo",
        appVersion: "1.0",
        deviceName: "iPhone 16",
        deviceKind: .phone,
        isSimulator: true,
        osName: "iOS",
        osVersion: "18.0",
        screenSize: WireSize(width: 393, height: 852),
        screenScale: 3,
        serverVersion: "0.4.0"
    )

    private func decodedFixture(_ path: String) throws -> Frame {
        try FrameCodec.decode(RepositoryFiles.fixture(path))
    }

    func test_S_CONN_04_decodesTheHandshakeFixtures() throws {
        let client = ClientInfo(name: "Cutaway", version: "0.4.0")
        XCTAssertEqual(
            try decodedFixture("handshake/01-c2s-hello.bin"),
            Frame(
                requestID: 0,
                body: .hello(Hello(version: ProtocolVersion(major: 1, minor: 2), role: .client, client: client))
            )
        )
        XCTAssertEqual(
            try decodedFixture("handshake/02-s2c-hello.bin"),
            Frame(
                requestID: 0,
                body: .hello(Hello(version: ProtocolVersion(major: 1, minor: 2), role: .server, app: demoApp))
            )
        )
        XCTAssertEqual(
            try decodedFixture("handshake-version-mismatch/01-c2s-hello.bin"),
            Frame(
                requestID: 0,
                body: .hello(
                    Hello(
                        version: ProtocolVersion(major: 1, minor: 0),
                        role: .client,
                        client: ClientInfo(name: "Cutaway", version: "0.1.0")
                    )
                )
            )
        )
        // Since protocol 1.0 the fixture is a 1.0 client at a server still at 0.5.
        XCTAssertEqual(
            try decodedFixture("handshake-version-mismatch/02-s2c-hello.bin"),
            Frame(
                requestID: 0,
                body: .hello(Hello(version: ProtocolVersion(major: 0, minor: 5), role: .server, app: demoApp))
            )
        )
        XCTAssertEqual(ProtocolVersion.current, ProtocolVersion(major: 1, minor: 2))
    }

    func test_S_CONN_04_helloRoundTrips() throws {
        let server = Frame(
            requestID: 0,
            body: .hello(Hello(version: .current, role: .server, app: demoApp))
        )
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(server)), server)

        // A hello without the `protocol` field keeps it absent.
        let bare = Frame(requestID: 0, body: .hello(Hello(version: nil, role: .client)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(bare)), bare)
    }

    func test_S_CONN_02_decodesTheBusyFixture() throws {
        XCTAssertEqual(
            try decodedFixture("busy/01-s2c-error.bin"),
            Frame(
                requestID: 0,
                body: .error(WireError(code: .busy, message: "another client is connected"))
            )
        )
    }

    func test_S_CONN_06_decodesTheAppStateFixtures() throws {
        XCTAssertEqual(
            try decodedFixture("handshake/03-s2c-app-state.bin"),
            Frame(requestID: 0, body: .appStateChanged(.active))
        )
        XCTAssertEqual(
            try decodedFixture("layer-details-failed/02-s2c-app-state.bin"),
            Frame(requestID: 0, body: .appStateChanged(.inactive))
        )
        XCTAssertEqual(
            try decodedFixture("app-not-active/01-s2c-app-state.bin"),
            Frame(requestID: 0, body: .appStateChanged(.background))
        )
        for state in [AppState.active, .inactive, .background] {
            let frame = Frame(requestID: 0, body: .appStateChanged(state))
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
        }
    }

    func test_S_CONN_08_decodesTheAppIconFixture() throws {
        XCTAssertEqual(
            try decodedFixture("app-icon/01-c2s-get-app-icon.bin"),
            Frame(requestID: 1, body: .getAppIcon)
        )

        let frame = try decodedFixture("app-icon/02-s2c-app-icon.bin")
        XCTAssertEqual(frame.requestID, 1)
        guard case .appIcon(let icon)? = frame.body, let image = icon.image else {
            return XCTFail("expected an AppIcon with an image, got \(frame)")
        }
        XCTAssertEqual(image.encoding, .bgra8PremultipliedLZFSE)
        XCTAssertEqual(image.pixelWidth, 2)
        XCTAssertEqual(image.pixelHeight, 2)
        XCTAssertEqual(image.bytesPerRow, 8)
        XCTAssertEqual(image.scale, 1)
        XCTAssertEqual(image.data.count, 28)
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)

        // An app without an icon: the image stays absent.
        let empty = Frame(requestID: 9, body: .appIcon(AppIcon(image: nil)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(empty)), empty)
    }

    func test_S_CONN_09_frameWithoutABodyDecodesWithANilBody() throws {
        // Zeros with the identifier in place pass the verifier.
        var zeros = Data(count: 64)
        zeros.replaceSubrange(4..<8, with: Array("CTWY".utf8))
        XCTAssertEqual(try FrameCodec.decode(zeros), Frame(requestID: 0, body: nil))

        let bodiless = Frame(requestID: 5, body: nil)
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(bodiless)), bodiless)
    }

    func test_S_CONN_09_everyMessageKindRoundTrips() throws {
        // The session tells requests from server-only messages by their kind, so every member of
        // the union has to survive a round trip.
        let failed = StreamEnd(
            status: .failed,
            chunkCount: 0,
            error: WireError(code: .internalError, message: "x")
        )
        let messages: [Message] = [
            .getAppIcon,
            .getHierarchy,
            .hierarchy(Hierarchy(nodes: [], keyWindowID: 0)),
            .getLayerDetails(GetLayerDetails(requests: [], maxTextureDimension: 0)),
            .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: [])),
            .streamEnd(failed),
            .streamEnd(StreamEnd(status: .cancelled, chunkCount: 3)),
            .cancel(targetRequestID: 7),
            .error(WireError(code: .unexpectedMessage, message: "unexpected")),
            .error(WireError(code: .malformedFrame, message: "")),
            .error(WireError(code: .appNotActive, message: "inactive")),
            .error(WireError(code: .unknown, message: "?")),
            .error(WireError(code: .layerNotFound, message: "no layer with id 9")),
            .error(WireError(code: .attributeNotEditable, message: "read-only")),
            .error(WireError(code: .invalidAttributeValue, message: "not a number")),
            .getSubtree(rootID: 0),
            .getSubtree(rootID: .max),
            .setAttribute(SetAttribute(layerID: 3, attributeID: "view.tag", value: .int(-1))),
            .setAttributeResult(SetAttributeResult(layerID: 3, attributeGroups: []))
        ]
        for (index, message) in messages.enumerated() {
            let frame = Frame(requestID: UInt32(index + 1), body: message)
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
        }
    }

    func test_S_CONN_05_everyFixtureFrameDecodes() throws {
        for scenario in WireTestSupport.scenarios {
            for direction in ["c2s", "s2c"] {
                for payload in try WireTestSupport.fixtureFrames(scenario: scenario, direction: direction) {
                    XCTAssertNoThrow(try FrameCodec.decode(payload), "\(scenario) \(direction)")
                }
            }
        }
    }

    func test_S_CONN_05_encodedFramesUseThePlainBufferFormat() throws {
        let frame = Frame(
            requestID: 0,
            body: .error(WireError(code: .busy, message: "another client is connected"))
        )
        let payload = FrameCodec.encode(frame)
        let framed = FrameCodec.framed(payload)

        // The length is little-endian and does not count itself.
        XCTAssertEqual(framed.count, payload.count + 4)
        let length = framed.prefix(4).enumerated().reduce(0) { $0 | Int($1.element) << (8 * $1.offset) }
        XCTAssertEqual(length, payload.count)
        // A plain buffer follows: root offset, then the file identifier. A size-prefixed
        // FlatBuffer would carry the identifier four bytes later.
        XCTAssertEqual(Array(framed[8..<12]), Array("CTWY".utf8))
        XCTAssertEqual(Data(framed.dropFirst(4)), payload)
        XCTAssertEqual(try FrameCodec.decode(payload), frame)
    }

    func test_S_CONN_13_encodeFramedMatchesFramedEncode() throws {
        // The server sends with the cheaper encodeFramed; the bytes must be the same as the
        // plain encoding with its length in front.
        var frames: [Frame] = []
        for scenario in WireTestSupport.scenarios {
            for direction in ["c2s", "s2c"] {
                for payload in try WireTestSupport.fixtureFrames(scenario: scenario, direction: direction) {
                    frames.append(try FrameCodec.decode(payload))
                }
            }
        }
        var generator = SeededGenerator(seed: 16)
        let image = WireImage(
            pixelWidth: 1024,
            pixelHeight: 512,
            bytesPerRow: 4096,
            scale: 2,
            data: generator.bytes(count: 2 * 1_048_576)
        )
        frames.append(
            Frame(
                requestID: 3,
                body: .layerDetailsChunk(
                    LayerDetailsChunk(
                        sequence: 4,
                        details: [
                            LayerDetail(layerID: 9, status: .ok, solo: image, group: image),
                            LayerDetail(layerID: 10, status: .layerNotFound)
                        ]
                    )
                )
            )
        )
        frames.append(Frame(requestID: 2, body: .appIcon(AppIcon(image: image))))
        frames.append(Frame(requestID: 5, body: nil))
        XCTAssertGreaterThan(frames.count, 20)
        for frame in frames {
            XCTAssertEqual(FrameCodec.encodeFramed(frame), FrameCodec.framed(FrameCodec.encode(frame)))
        }
    }

    func test_S_CONN_05_decoderRejectsMalformedPayloads() throws {
        let valid = try RepositoryFiles.fixture("app-icon/02-s2c-app-icon.bin")

        func assertMalformed(_ payload: Data, _ what: String) {
            XCTAssertThrowsError(try FrameCodec.decode(payload), what) { error in
                XCTAssertEqual(error as? WireFailure, .malformed, what)
            }
        }

        assertMalformed(Data(), "an empty payload")
        for length in 0..<valid.count {
            assertMalformed(Data(valid.prefix(length)), "a prefix of \(length) bytes")
        }

        var wrongIdentifier = valid
        wrongIdentifier[4] = UInt8(ascii: "X")
        assertMalformed(wrongIdentifier, "a wrong file identifier")

        // P-REQ-07: a union member this version does not know.
        assertMalformed(WireTestSupport.settingBodyType(200, in: valid), "an unknown union member")

        // A payload that does not start at index 0 of its storage decodes like any other.
        let padded = Data([0xAA, 0xBB]) + valid
        XCTAssertEqual(
            try FrameCodec.decode(padded.dropFirst(2)),
            try FrameCodec.decode(valid)
        )
    }

    func test_S_CONN_05_decoderAcceptsMoreTablesThanTheRuntimeDefault() throws {
        // P-FRAME-06: the FlatBuffers runtime stops at 1,000,000 tables by default. Each detail
        // is one table, so this chunk has more than that and stays far below the length limit.
        let details = (0..<1_000_001).map { LayerDetail(layerID: UInt64($0), status: .ok) }
        let frame = Frame(
            requestID: 9,
            body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: details))
        )
        let payload = FrameCodec.encode(frame)
        XCTAssertLessThan(UInt32(payload.count), FrameCodec.maximumFrameLength)
        XCTAssertEqual(try FrameCodec.decode(payload), frame)
    }

    func test_S_CONN_05_decoderSurvivesRandomBytes() throws {
        // A trap inside the decoder would end the test process instead of failing an assertion.
        var generator = SeededGenerator(seed: 0xC07A_0001)
        let valid = try RepositoryFiles.fixture("handshake/02-s2c-hello.bin")
        for _ in 0..<2_000 {
            // Pure noise, with and without the identifier in place.
            var noise = generator.bytes(count: Int.random(in: 0...96, using: &generator))
            _ = try? FrameCodec.decode(noise)
            if noise.count >= 8 {
                noise.replaceSubrange(4..<8, with: Array("CTWY".utf8))
                _ = try? FrameCodec.decode(noise)
            }
            // A valid frame with a few bytes flipped.
            var damaged = valid
            for _ in 0..<Int.random(in: 1...4, using: &generator) {
                let index = Int.random(in: 0..<damaged.count, using: &generator)
                damaged[index] = UInt8.random(in: .min ... .max, using: &generator)
            }
            _ = try? FrameCodec.decode(damaged)
        }
    }
}
