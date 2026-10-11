import CutawayServer
import UIKit
import XCTest

/// The SDK builds for iOS and runs inside a host app in the simulator.
final class ToolchainHostTests: XCTestCase {
    @MainActor
    func test_S_API_03_serverLinksIntoAnIOSHost() {
        XCTAssertEqual(
            Bundle.main.bundleIdentifier,
            "dev.cutaway.testhost",
            "these tests must run inside TestHost"
        )
        XCTAssertNotNil(UIApplication.shared.delegate)
        CutawayServer.start()
        CutawayServer.start()
    }
}
