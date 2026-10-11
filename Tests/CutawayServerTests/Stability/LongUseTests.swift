import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// One session used for a long time while the screen changes, through the real
/// capture; only the connection is fake (S-STAB-02).
final class LongUseTests: CaptureTestCase {
    static let rounds = 200
    /// S-STAB-02: how much the app's memory may grow after the tenth round.
    static let memoryGrowthLimit = 4 * 1_048_576
    /// Small images keep a round short; S-STAB-01 covers large ones.
    static let maxTextureDimension: UInt32 = 512

    private var window: UIWindow!
    private var tree: ManyLayersView!
    private var nextRequestID: UInt32 = 0

    override func setUp() async throws {
        try await super.setUp()
        window = try makeWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        tree = ManyLayersView(rows: 20, columns: 9)
        tree.frame.origin = CGPoint(x: 20, y: 22)
        window.addSubview(tree)
        window.layoutIfNeeded()
    }

    override func tearDown() async throws {
        tree = nil
        window = nil
        try await super.tearDown()
    }

    private func requestID() -> UInt32 {
        nextRequestID += 1
        return nextRequestID
    }

    private func details(of hierarchy: Hierarchy, times: Int = 1) -> Frame {
        let requests = hierarchy.nodes.map {
            LayerDetailRequest(
                layerID: $0.id,
                wantSolo: true,
                wantGroup: true,
                wantAttributes: true,
                wantConstraints: true
            )
        }
        return Frame(
            requestID: requestID(),
            body: .getLayerDetails(
                GetLayerDetails(
                    requests: Array(repeating: requests, count: times).flatMap { $0 },
                    maxTextureDimension: Self.maxTextureDimension
                )
            )
        )
    }

    /// Takes the hierarchy, the details of all its layers, changes an attribute and takes a
    /// subtree, checking each answer. A function of its own, so that the answers are gone
    /// before memory is read.
    private func round(_ round: Int, on harness: LiveSessionHarness) async throws {
        let answers = try await harness.exchange([Frame(requestID: requestID(), body: .getHierarchy)])
        guard case .hierarchy(let hierarchy)? = answers.first?.frame?.body else {
            throw TestClientError(description: "round \(round): no hierarchy")
        }

        let streams = try await harness.exchange([details(of: hierarchy)], timeout: 60)
        let details = streams.first?.details ?? []
        guard streams.first?.end?.status == .completed, details.count == hierarchy.nodes.count else {
            throw TestClientError(description: "round \(round): the details did not complete")
        }

        let row = harness.registry.register(tree.rowViews[0].layer)
        let change = SetAttribute(
            layerID: row,
            attributeID: "layer.opacity",
            value: .double(round.isMultiple(of: 2) ? 0.5 : 1)
        )
        let changed = try await harness.exchange(
            [Frame(requestID: requestID(), body: .setAttribute(change))]
        )
        guard case .setAttributeResult? = changed.first?.frame?.body else {
            throw TestClientError(description: "round \(round): \(String(describing: changed.first))")
        }

        let subtrees = try await harness.exchange(
            [Frame(requestID: requestID(), body: .getSubtree(rootID: row))]
        )
        guard case .hierarchy(let subtree)? = subtrees.first?.frame?.body,
              subtree.nodes.count == 1 + 2 * tree.columns
        else {
            throw TestClientError(description: "round \(round): \(String(describing: subtrees.first))")
        }
    }

    func test_S_STAB_02_twoHundredRoundsDoNotGrow() async throws {
        let harness = LiveSessionHarness()
        try await harness.handshake()
        var previouslyReleased: Set<UInt64> = []
        var firstLiveCount = 0
        var footprints: [Int] = []

        for round in 0..<Self.rounds {
            try await self.round(round, on: harness)
            // A quarter of the rows go, with their cells and constraints; new ones take their
            // places.
            tree.replaceRows(5)
            window.layoutIfNeeded()
            CATransaction.flush()
            await drain(DispatchQueue.main)

            // An object released before this round's hierarchy was forgotten by it: what the
            // registry still holds of released objects was released within this round.
            let released = harness.registry.releasedIDs
            let stale = released.intersection(previouslyReleased)
            guard stale.isEmpty else {
                return XCTFail("round \(round): \(stale.count) released objects outlived a hierarchy")
            }
            previouslyReleased = released
            // UIKit holds rows it took out for a few rounds; the registry follows what is
            // alive, so it may grow by that much, and no more.
            let liveCount = harness.registry.liveCount
            if round == 0 { firstLiveCount = liveCount }
            guard liveCount <= 3 * firstLiveCount else {
                return XCTFail("round \(round): \(liveCount) live objects, \(firstLiveCount) after the first")
            }
            footprints.append(physicalFootprint())
        }

        XCTAssertEqual(harness.endedCount, 0)
        let afterTenth = footprints[9]
        let growth = try XCTUnwrap(footprints[10...].max()) - afterTenth
        let summary = String(
            format: "growth after round 10: %.2f MiB (end %.2f MiB); registry %d entries, %d alive",
            Double(growth) / 1_048_576,
            Double(footprints[footprints.count - 1] - afterTenth) / 1_048_576,
            harness.registry.count,
            harness.registry.liveCount
        )
        print("S-STAB-02: \(summary)")
        XCTAssertLessThanOrEqual(growth, Self.memoryGrowthLimit, summary)
    }

    func test_S_STAB_02_aSessionIsReleasedWhenThePeerLeaves() async throws {
        var harness: LiveSessionHarness? = LiveSessionHarness()
        try await harness!.handshake()
        let answers = try await harness!.exchange([Frame(requestID: requestID(), body: .getHierarchy)])
        guard case .hierarchy(let hierarchy)? = answers.first?.frame?.body else {
            return XCTFail("no hierarchy: \(String(describing: answers.first))")
        }
        let queue = harness!.queue
        let encodeQueue = harness!.encodeQueue
        let transport = harness!.transport
        weak let session = harness!.session
        weak let registry = harness!.registry

        // Long enough to be under way when the peer leaves.
        harness!.receive(details(of: hierarchy, times: 20))
        try await waitUntil("some chunks") { transport.sent.count >= 10 }
        weak var stream: LayerDetailsStream?
        do {
            let session = harness!.session
            stream = queue.sync { session.currentStream }
        }
        XCTAssertNotNil(stream, "the stream ended before the peer left")
        queue.async { transport.closeFromThePeer() }
        harness = nil

        // What is still on the queues runs; the main queue may hold a layer's capture, the
        // compressor a detail.
        for _ in 0..<8 {
            await drain(queue)
            await drain(encodeQueue)
            await drain(DispatchQueue.main)
        }
        XCTAssertNil(session, "the session outlived its connection")
        XCTAssertNil(registry, "the registry outlived its connection")
        XCTAssertNil(stream, "the stream outlived its connection")
    }
}
