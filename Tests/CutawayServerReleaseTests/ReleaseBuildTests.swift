import CutawayServer
import Foundation
import UIKit
import XCTest

/// S-API-02, checked from the outside: this bundle is built in the Release configuration
/// and uses nothing but the public API.
final class ReleaseBuildTests: XCTestCase {
    private static let ports: ClosedRange<UInt16> = 48160...48167

    /// The ports of the range that accept a connection on the loopback address right now.
    private func listeningPorts() -> Set<UInt16> {
        var result = Set<UInt16>()
        for port in Self.ports {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if connected == 0 { result.insert(port) }
            close(descriptor)
        }
        return result
    }

    func test_S_API_02_releaseBuildListensOnlyWhenTheTraitIsEnabled() async throws {
        #if DEBUG
        XCTFail("this bundle must be built in the Release configuration")
        #endif

        // The server only listens while the app is active, so "nothing listens" means
        // something only then.
        var isActive = false
        for _ in 0..<100 where !isActive {
            isActive = await MainActor.run { UIApplication.shared.applicationState == .active }
            if !isActive { try await Task.sleep(nanoseconds: 100_000_000) }
        }
        XCTAssertTrue(isActive, "the host app did not become active")

        let before = listeningPorts()
        CutawayServer.start()
        CutawayServer.start()

        #if EXPECT_SERVER
        // The trait is enabled: exactly one new port starts to listen.
        var after = before
        for _ in 0..<100 where after == before {
            try await Task.sleep(nanoseconds: 100_000_000)
            after = listeningPorts()
        }
        XCTAssertTrue(after.isSuperset(of: before))
        XCTAssertEqual(
            after.subtracting(before).count,
            1,
            "with the trait enabled, start() should open one port; before \(before.sorted()), after \(after.sorted())"
        )
        #else
        // No trait: start() is empty, and no port opens however long we wait.
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(
                listeningPorts(),
                before,
                "a Release build without the trait must not listen"
            )
        }
        #endif
    }

    /// S-API-04: the extension interface compiles and can be called in Release, with and
    /// without the trait; without it, registering does nothing.
    @MainActor
    func test_S_API_04_theExtensionInterfaceCanBeCalledInRelease() {
        final class ChartView: UIView {}
        var description = CutawayServer.Description<ChartView>()
        description.attributes = { _ in
            [CutawayServer.AttributeGroup("chart", [.int("bars", 3, limits: [.atLeast(0)], set: { _ in })])]
        }
        description.virtualChildren = { _ in [CutawayServer.VirtualNode(id: 1, typeName: "Bar", frame: .zero)] }
        description.isExcludedFromCapture = true
        CutawayServer.describe(ChartView.self, description)
        CutawayServer.describe(CAShapeLayer.self, CutawayServer.Description(isCollapsedByDefault: true))
        CutawayServer.registerColor(.red, named: "brand")
    }
}
