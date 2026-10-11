import CutawayFlatBuffers
import Foundation
import XCTest

@testable import CutawayWire

/// The vendored runtime and the generated code work together.
final class ToolchainTests: XCTestCase {
    private func checkedFrame(_ data: Data) throws -> Cutaway_Wire_Frame {
        var buffer = ByteBuffer(data: data)
        return try getCheckedRoot(byteBuffer: &buffer, fileId: "CTWY")
    }

    func test_S_API_03_manifestDeclaresNoPackageDependencies() throws {
        let manifest = try String(
            contentsOf: RepositoryFiles.root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        XCTAssertFalse(
            manifest.contains(".package("),
            "Package.swift must not declare package dependencies"
        )
        XCTAssertTrue(
            manifest.contains(".iOS(.v13)"),
            "Package.swift must keep the iOS 13 deployment target"
        )
    }

    func test_S_API_03_vendoredRuntimeVerifiesAndReadsAFixtureFrame() throws {
        let frame = try checkedFrame(RepositoryFiles.fixture("handshake/01-c2s-hello.bin"))
        XCTAssertEqual(frame.requestId, 0)
        XCTAssertEqual(frame.bodyType, .hello)
        let hello = try XCTUnwrap(frame.body(type: Cutaway_Wire_Hello.self))
        XCTAssertEqual(hello.role, .client)
        XCTAssertEqual(hello.protocol_?.major, 1)
        XCTAssertEqual(hello.protocol_?.minor, 0)
        XCTAssertEqual(hello.client?.name, "Cutaway")
        XCTAssertEqual(hello.client?.version, "0.4.0")
        XCTAssertNil(hello.app)
    }

    func test_S_API_03_objectAPIRoundTripsAFixtureFrame() throws {
        let original = try checkedFrame(RepositoryFiles.fixture("hierarchy/02-s2c-hierarchy.bin"))
        var object = original.unpack()
        var builder = FlatBufferBuilder(initialSize: 1024)
        let root = Cutaway_Wire_Frame.pack(&builder, obj: &object)
        Cutaway_Wire_Frame.finish(&builder, end: root)
        let bytes = builder.sizedByteArray

        // A plain buffer: root offset first, then the file identifier.
        XCTAssertEqual(Array(bytes[4..<8]), Array("CTWY".utf8))
        let reencoded = try checkedFrame(Data(bytes))
        XCTAssertEqual(reencoded.requestId, original.requestId)
        XCTAssertEqual(reencoded.bodyType, .hierarchy)
        let hierarchy = try XCTUnwrap(reencoded.body(type: Cutaway_Wire_Hierarchy.self))
        XCTAssertEqual(hierarchy.keyWindowId, 1)
        XCTAssertEqual(hierarchy.nodes.map(\.id), [1, 2, 3, 4, 5, 6, 7, 8, 9])
    }

    func test_S_API_03_verifierRejectsDamagedBuffersWithoutCrashing() throws {
        let valid = try RepositoryFiles.fixture("handshake/01-c2s-hello.bin")

        var wrongIdentifier = valid
        wrongIdentifier[4] = UInt8(ascii: "X")
        XCTAssertThrowsError(try checkedFrame(wrongIdentifier)) { error in
            guard case FlatbuffersErrors.bufferIdDidntMatchPassedId = error else {
                return XCTFail("expected an identifier mismatch, got \(error)")
            }
        }

        // The root offset points far outside the buffer.
        var wildRoot = valid
        wildRoot.replaceSubrange(0..<4, with: [0xFF, 0xFF, 0xFF, 0x7F])
        XCTAssertThrowsError(try checkedFrame(wildRoot))

        // Every truncation of this fixture is rejected. A trap inside the runtime would end
        // the test process instead of failing an assertion.
        for length in 0..<valid.count {
            XCTAssertThrowsError(
                try checkedFrame(Data(valid.prefix(length))),
                "a prefix of \(length) bytes verified"
            )
        }
    }

    /// What "verified" does not mean: zeros with the identifier in place pass the verifier and
    /// read as a frame without a body. Callers must check the body themselves.
    func test_S_API_03_verifierAcceptsAZeroedBufferAsAFrameWithoutABody() throws {
        var zeros = Data(count: 64)
        zeros.replaceSubrange(4..<8, with: Array("CTWY".utf8))
        let frame = try checkedFrame(zeros)
        XCTAssertEqual(frame.requestId, 0)
        XCTAssertEqual(frame.bodyType, .none_)
    }
}
