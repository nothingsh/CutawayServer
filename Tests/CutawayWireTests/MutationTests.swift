import CutawayWire
import Foundation
import XCTest

/// Damaged frames decode into a value or throw, never trap (S-CONN-15).
final class MutationTests: XCTestCase {
    /// The fixture frames and an encoded sample of every message kind.
    private func seeds() throws -> [Data] {
        let samples = WireTestSupport.messageSamples.enumerated().map { index, message in
            FrameCodec.encode(Frame(requestID: UInt32(index + 1), body: message))
        }
        return try WireTestSupport.allFixtureFrames() + samples
    }

    func test_S_CONN_15_seedsCoverEveryMessageKind() throws {
        let kinds = Set(WireTestSupport.messageSamples.map(WireTestSupport.kind(of:)))
        XCTAssertEqual(kinds, WireTestSupport.messageKinds)
        for message in WireTestSupport.messageSamples {
            let frame = Frame(requestID: 1, body: message)
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
        }
        XCTAssertGreaterThanOrEqual(try WireTestSupport.allFixtureFrames().count, 52)
    }

    func test_S_CONN_15_mutatedFramesDecodeOrThrow() throws {
        // A trap inside the decoder ends the test process, which fails the run.
        var mutator = FrameMutator(seed: 0xC07A_0017, seeds: try seeds())
        let total = 100_000
        var decoded = 0
        var rejected = 0
        var kinds: [FrameMutator.Kind: Int] = [:]
        for _ in 0..<total {
            let (kind, bytes) = mutator.next()
            kinds[kind, default: 0] += 1
            let frame: Frame
            do {
                frame = try FrameCodec.decode(bytes)
            } catch {
                XCTAssertEqual(error as? WireFailure, .malformed)
                rejected += 1
                continue
            }
            decoded += 1
            // What was read can be written back, and reads back the same. Bytes, not values, are
            // compared: a damaged double may be NaN, which is not equal to itself.
            let once = FrameCodec.encode(frame)
            let again = try FrameCodec.decode(once)
            XCTAssertEqual(FrameCodec.encode(again), once, "a decoded frame did not survive a round trip")
        }
        XCTAssertEqual(decoded + rejected, total)
        // Both outcomes, often: the mutations neither always break the frame nor never do.
        XCTAssertGreaterThan(decoded, 10_000)
        XCTAssertGreaterThan(rejected, 10_000)
        XCTAssertEqual(Set(kinds.keys), Set(FrameMutator.Kind.allCases))
    }
}
