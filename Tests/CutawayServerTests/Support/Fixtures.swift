import CutawayWire
import Foundation

/// Reads the protocol fixtures straight from the repository. The simulator shares the Mac's
/// file system, so the path of this source file leads there.
enum Fixtures {
    /// Tests/CutawayServerTests/Support/Fixtures.swift -> the repository root.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Reads a file below Protocol/fixtures/bin, for example "handshake/c2s.stream".
    static func data(_ path: String) throws -> Data {
        try Data(
            contentsOf: root.appendingPathComponent("Protocol/fixtures/bin").appendingPathComponent(path)
        )
    }

    /// Decodes a `.bin` fixture.
    static func frame(_ path: String) throws -> Frame {
        try FrameCodec.decode(data(path))
    }
}

/// A small deterministic generator, so that "random" inputs are the same on every run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    mutating func bytes(count: Int) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &self) })
    }
}

/// Overwrites the `body_type` byte of an encoded frame that has a body.
/// It walks the buffer by hand: root offset, vtable, then the second field's offset.
func settingBodyType(_ value: UInt8, in payload: Data) -> Data {
    var bytes = [UInt8](payload)
    func int32(at index: Int) -> Int {
        Int(Int32(bitPattern: UInt32(bytes[index]) | UInt32(bytes[index + 1]) << 8
                | UInt32(bytes[index + 2]) << 16 | UInt32(bytes[index + 3]) << 24))
    }
    let table = int32(at: 0)
    let vtable = table - int32(at: table)
    let fieldOffset = Int(bytes[vtable + 6]) | Int(bytes[vtable + 7]) << 8
    precondition(fieldOffset != 0, "the frame has no body_type field")
    bytes[table + fieldOffset] = value
    return Data(bytes)
}
