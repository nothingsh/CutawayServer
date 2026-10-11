import CutawayWire
import QuartzCore
import UIKit
import XCTest

@testable import CutawayServer

/// Ten thousand layers through the real capture, registry, screenshots and
/// compression; only the connection is fake (S-STAB-01).
final class LargeHierarchyTests: CaptureTestCase {
    /// S-STAB-01: the longest the server may hold the main thread at once, a layer's own
    /// rendering left out, and the longest the whole may take.
    static let longestMainThreadBlock = 0.150
    static let longestTotal = 30.0

    private func layerCount(under layer: CALayer) -> Int {
        1 + (layer.sublayers ?? []).reduce(0) { $0 + layerCount(under: $1) }
    }

    func test_S_STAB_01_tenThousandLayersWithShortMainThreadBlocks() async throws {
        let window = try makeWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let tree = ManyLayersView(rows: 100, columns: 50)
        tree.frame.origin = CGPoint(x: 20, y: 22)
        window.addSubview(tree)
        window.layoutIfNeeded()
        XCTAssertEqual(tree.layerCount, 10_101)
        XCTAssertEqual(tree.viewCount, 5_101)

        let clock = MainThreadClock()
        let harness = LiveSessionHarness(configuration: clock.configuration())
        try await harness.handshake()
        let start = CACurrentMediaTime()

        let answers = try await harness.exchange([Frame(requestID: 1, body: .getHierarchy)])
        guard case .hierarchy(let hierarchy)? = answers.first?.frame?.body else {
            return XCTFail("no hierarchy: \(String(describing: answers.first))")
        }
        // Counted apart from the capture.
        let expected = HostWindows.all().reduce(0) { $0 + layerCount(under: $1.layer) }
        XCTAssertEqual(hierarchy.nodes.count, expected)
        // In pre-order, a node is in the tree when its parent is.
        var inTree: Set<UInt64> = [harness.registry.register(tree.layer)]
        for node in hierarchy.nodes where inTree.contains(node.parentID) {
            inTree.insert(node.id)
        }
        let treeNodes = hierarchy.nodes.filter { inTree.contains($0.id) }
        XCTAssertEqual(treeNodes.count, 10_101)
        XCTAssertEqual(treeNodes.filter { $0.viewClassName != nil }.count, 5_101)

        let request = GetLayerDetails(
            requests: hierarchy.nodes.map {
                LayerDetailRequest(
                    layerID: $0.id,
                    wantSolo: true,
                    wantGroup: true,
                    wantAttributes: true,
                    wantConstraints: true
                )
            },
            maxTextureDimension: 0
        )
        let streams = try await harness.exchange(
            [Frame(requestID: 2, body: .getLayerDetails(request))],
            timeout: 120
        )
        let total = CACurrentMediaTime() - start

        // ResponseCheck saw every layer once, in order.
        XCTAssertEqual(streams.first?.end?.status, .completed)
        let details = streams.first?.details ?? []
        XCTAssertEqual(details.count, hierarchy.nodes.count)
        let treeDetails = details.filter { inTree.contains($0.layerID) }
        XCTAssertEqual(treeDetails.filter { $0.status != .ok }.map(\.layerID), [])
        XCTAssertEqual(treeDetails.filter { $0.group == nil }.map(\.layerID), [])
        XCTAssertEqual(details.filter { $0.status == .layerNotFound }.map(\.layerID), [])
        let cellIDs = Set(tree.rowViews.flatMap(\.subviews).map { harness.registry.register($0.layer) })
        XCTAssertEqual(cellIDs.count, 5_000)
        XCTAssertEqual(
            details.filter { cellIDs.contains($0.layerID) && $0.constraints.count != 4 }.map(\.layerID),
            [],
            "every cell has its four constraints"
        )

        // The hierarchy and every detail were timed.
        let blocks = clock.all
        XCTAssertEqual(blocks.count, 1 + hierarchy.nodes.count)
        let longest = try XCTUnwrap(clock.longest)
        let summary = String(
            format: "%d layers; longest main-thread block %.1f ms (%@); longest render %.1f ms; total %.2f s",
            hierarchy.nodes.count,
            longest.seconds * 1000,
            longest.what,
            clock.longestRender * 1000,
            total
        )
        print("S-STAB-01: \(summary)")
        XCTAssertLessThanOrEqual(longest.seconds, Self.longestMainThreadBlock, summary)
        XCTAssertLessThanOrEqual(total, Self.longestTotal, summary)
    }
}
