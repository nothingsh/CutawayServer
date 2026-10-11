import Foundation

/// Locates files of this repository from a test, relative to this source file.
enum RepositoryFiles {
    /// Tests/CutawayWireTests/RepositoryFiles.swift -> the repository root.
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// Reads a file below Protocol/fixtures/bin, for example "handshake/01-c2s-hello.bin".
    static func fixture(_ path: String) throws -> Data {
        try Data(
            contentsOf: root.appendingPathComponent("Protocol/fixtures/bin").appendingPathComponent(path)
        )
    }
}
