import CutawayWire
import Foundation

/// The protocol's fixture frames, read from the submodule at Protocol/.
enum Fixtures {
    /// Tests/CutawayProbeTests/Fixtures.swift -> the repository root.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// The bytes of a frame; `path` is relative to Protocol/fixtures/bin.
    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: root.appendingPathComponent("Protocol/fixtures/bin").appendingPathComponent(path))
    }

    /// A frame, decoded.
    static func frame(_ path: String) throws -> Frame {
        try FrameCodec.decode(data(path))
    }
}
