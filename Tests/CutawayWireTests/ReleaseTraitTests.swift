import Foundation
import XCTest

/// The package declares the trait that lets a Release build contain the server.
final class ReleaseTraitTests: XCTestCase {
    func test_S_API_02_manifestDeclaresTheReleaseTrait() throws {
        let manifest = try String(
            contentsOf: RepositoryFiles.root.appendingPathComponent("Package.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(manifest.contains("swift-tools-version: 6.1"), "traits need tools version 6.1")
        XCTAssertTrue(
            manifest.contains(".trait(name: \"ReleaseEnabled\""),
            "the ReleaseEnabled trait is missing"
        )
    }
}
