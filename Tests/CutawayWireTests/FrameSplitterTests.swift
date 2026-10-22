import CutawayWire
import Foundation
import XCTest

/// The byte stream of P-FRAME-01 is cut into frame payloads.
final class FrameSplitterTests: XCTestCase {
    func test_S_CONN_05_splitterWaitsForACompleteFrame() throws {
        var splitter = FrameSplitter()
        XCTAssertNil(try splitter.next())
        splitter.append(Data([0x08, 0x00, 0x00]))
        XCTAssertNil(try splitter.next(), "the length field is incomplete")
        splitter.append(Data([0x00, 1, 2, 3]))
        XCTAssertNil(try splitter.next(), "the payload is incomplete")
        splitter.append(Data([4, 5, 6, 7, 8, 0xFF]))
        XCTAssertEqual(try splitter.next(), Data([1, 2, 3, 4, 5, 6, 7, 8]))
        XCTAssertNil(try splitter.next(), "one byte of the next length is not a frame")
    }

    func test_S_CONN_05_splitterRejectsAnOversizedLength() throws {
        XCTAssertEqual(FrameCodec.maximumFrameLength, 268_435_456)

        // 268435457 = 0x10000001: rejected from the length alone, before any payload arrives.
        var over = FrameSplitter()
        over.append(Data([0x01, 0x00, 0x00, 0x10]))
        XCTAssertThrowsError(try over.next()) { error in
            XCTAssertEqual(error as? WireFailure, .lengthExceedsLimit(268_435_457))
        }

        var huge = FrameSplitter()
        huge.append(Data([0xFF, 0xFF, 0xFF, 0xFF]))
        XCTAssertThrowsError(try huge.next())

        // Exactly the limit is allowed: the splitter waits for the payload.
        var atLimit = FrameSplitter()
        atLimit.append(Data([0x00, 0x00, 0x00, 0x10]))
        XCTAssertNil(try atLimit.next())
    }

    // MARK: - However the bytes arrive

    /// Feeds `stream` in pieces of the given sizes, taking every frame after each piece. The
    /// error, if one is thrown, ends the feeding.
    private func split(
        _ stream: Data,
        pieces: [Int]
    ) -> (payloads: [Data], error: WireFailure?, leftOver: Bool) {
        var splitter = FrameSplitter()
        var result: [Data] = []
        var offset = 0
        var pieceIndex = 0
        do {
            while offset < stream.count {
                let end = min(offset + pieces[pieceIndex % pieces.count], stream.count)
                splitter.append(stream.subdata(in: offset..<end))
                offset = end
                pieceIndex += 1
                while let payload = try splitter.next() {
                    result.append(payload)
                }
            }
            return (result, nil, (try? splitter.next()) == nil ? false : true)
        } catch {
            return (result, error as? WireFailure, false)
        }
    }

    /// Three ways for the same bytes to arrive: at once, one at a time, in seeded pieces that
    /// cross the length fields and the 64 KiB a connection reads at most.
    private func feedings(of stream: Data) -> [(String, [Int])] {
        var generator = SeededGenerator(seed: 0x5917)
        let random = (0..<4096).map { _ in Int.random(in: 1...9000, using: &generator) }
        return [("whole", [max(1, stream.count)]), ("byte by byte", [1]), ("random pieces", random)]
    }

    private func sampleStream() throws -> (stream: Data, payloads: [Data]) {
        var payloads: [Data] = []
        var stream = Data()
        for scenario in WireTestSupport.scenarios {
            for direction in ["c2s", "s2c"] {
                let expected = try WireTestSupport.fixtureFrames(scenario: scenario, direction: direction)
                guard !expected.isEmpty else { continue }
                stream += try RepositoryFiles.fixture("\(scenario)/\(direction).stream")
                payloads += expected
            }
        }
        var generator = SeededGenerator(seed: 15)
        let image = WireImage(
            pixelWidth: 512,
            pixelHeight: 512,
            bytesPerRow: 2048,
            scale: 1,
            data: generator.bytes(count: 1_048_576)
        )
        let extra = [
            FrameCodec.encode(Frame(requestID: 3, body: .appIcon(AppIcon(image: image)))),
            Data()
        ] + WireTestSupport.messageSamples.map { FrameCodec.encode(Frame(requestID: 4, body: $0)) }
        for payload in extra {
            stream += FrameCodec.framed(payload)
            payloads.append(payload)
        }
        return (stream, payloads)
    }

    func test_S_CONN_15_splitterYieldsTheSameFramesHoweverTheBytesArrive() throws {
        // Every `.stream` fixture yields its `.bin` frames, and framed output its payloads,
        // empty ones included (S-CONN-05).
        let (stream, expected) = try sampleStream()
        XCTAssertGreaterThan(stream.count, 1_048_576)
        for (name, pieces) in feedings(of: stream) {
            let result = split(stream, pieces: pieces)
            XCTAssertNil(result.error, name)
            XCTAssertFalse(result.leftOver, name)
            XCTAssertEqual(result.payloads.count, expected.count, name)
            XCTAssertTrue(result.payloads == expected, "\(name): the frames differ")
        }
    }

    func test_S_CONN_15_splitterThrowsAtTheSamePlaceHoweverTheBytesArrive() throws {
        let (valid, expected) = try sampleStream()
        // A length over the limit, then bytes that must never be read as a frame.
        let stream = valid + Data([0x01, 0x00, 0x00, 0x10]) + FrameCodec.framed(expected[0])
        for (name, pieces) in feedings(of: stream) {
            let result = split(stream, pieces: pieces)
            XCTAssertEqual(result.error, .lengthExceedsLimit(268_435_457), name)
            XCTAssertTrue(result.payloads == expected, "\(name): the frames before the error differ")
        }
    }

    func test_S_CONN_15_manySmallFramesInOneReadSplitQuickly() throws {
        // A client can fill each 64 KiB read with the smallest frames. Taking one must not copy
        // what is left of the read.
        let payload = FrameCodec.encode(Frame(requestID: 1, body: .getAppIcon))
        let framed = FrameCodec.framed(payload)
        let count = 4 * 1_048_576 / framed.count
        var stream = Data(capacity: framed.count * count)
        for _ in 0..<count { stream += framed }
        var splitter = FrameSplitter()
        splitter.append(stream)
        let start = Date()
        var taken = 0
        while try splitter.next() != nil { taken += 1 }
        XCTAssertEqual(taken, count)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1, "\(count) frames from 4 MiB")
    }
}
