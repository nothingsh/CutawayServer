import QuartzCore
import UIKit
import XCTest

@testable import CutawayServer

/// Layer IDs (PROTOCOL.md, P-HIER-03). No server, no connection.
@MainActor
final class LayerRegistryTests: XCTestCase {
    func test_S_HIER_02_idsStartAtOneAndStayWithTheLayer() {
        let registry = LayerRegistry()
        let first = CALayer()
        let second = CALayer()
        XCTAssertEqual(registry.register(first), 1)
        XCTAssertEqual(registry.register(second), 2)
        // Asking again, in any order, changes nothing.
        XCTAssertEqual(registry.register(second), 2)
        XCTAssertEqual(registry.register(first), 1)
        XCTAssertEqual(registry.count, 2)

        // Another connection has another registry, and its IDs are its own.
        let other = LayerRegistry()
        XCTAssertEqual(other.register(second), 1)

        // An ID leads back to its layer; 0 and an ID never given out lead nowhere.
        XCTAssertTrue(registry.layer(for: 1) === first)
        XCTAssertNil(registry.layer(for: 0))
        XCTAssertNil(registry.layer(for: 3))
    }

    func test_S_STAB_02_theRegistryTellsReleasedEntriesApart() {
        let registry = LayerRegistry()
        let kept = CALayer()
        _ = registry.register(kept)
        var releasedIDs: Set<UInt64> = []
        autoreleasepool {
            let layer = CALayer()
            let constraint = NSLayoutConstraint()
            releasedIDs = [registry.register(layer), registry.register(constraint)]
            XCTAssertEqual(registry.releasedIDs, [])
            XCTAssertEqual(registry.liveCount, 3)
        }
        XCTAssertEqual(registry.count, 3)
        XCTAssertEqual(registry.liveCount, 1)
        XCTAssertEqual(registry.releasedIDs, releasedIDs)

        registry.removeReleased()
        XCTAssertEqual(registry.count, 1)
        XCTAssertEqual(registry.liveCount, 1)
        XCTAssertEqual(registry.releasedIDs, [])
    }

    func test_S_HIER_17_virtualNodesShareTheCounterAndKeepTheirIDs() {
        let registry = LayerRegistry()
        let first = CALayer()
        let second = CALayer()
        let firstID = registry.register(first)
        let secondID = registry.register(second)
        let bar = registry.register(virtual: "bar", under: firstID)
        XCTAssertEqual(bar, 3)
        // The same identity under the same layer keeps its ID; under another layer it is
        // another node.
        XCTAssertEqual(registry.register(virtual: "bar", under: firstID), bar)
        let otherBar = registry.register(virtual: "bar", under: secondID)
        XCTAssertEqual(otherBar, 4)
        XCTAssertEqual(registry.register(virtual: AnyHashable(7), under: firstID), 5)
        // Layers and virtual nodes are told apart by their IDs.
        XCTAssertEqual(registry.virtualNode(for: bar), LayerRegistry.VirtualKey(layerID: firstID, identity: "bar"))
        XCTAssertNil(registry.virtualNode(for: firstID))
        XCTAssertNil(registry.layer(for: bar))
        XCTAssertEqual(registry.register(CALayer()), 6)
    }

    func test_S_HIER_17_virtualNodesAreForgottenWithTheirLayer() {
        let registry = LayerRegistry()
        let kept = CALayer()
        let keptID = registry.register(kept)
        let keptBar = registry.register(virtual: "bar", under: keptID)
        var releasedBar: UInt64 = 0
        autoreleasepool {
            let layer = CALayer()
            releasedBar = registry.register(virtual: "bar", under: registry.register(layer))
        }
        registry.removeReleased()
        XCTAssertNil(registry.virtualNode(for: releasedBar))
        XCTAssertEqual(registry.virtualIDs.count, 1)
        XCTAssertEqual(registry.virtualNode(for: keptBar)?.layerID, keptID)
        // A new node never takes an ID that was given out.
        XCTAssertGreaterThan(registry.register(virtual: "new", under: keptID), releasedBar)
    }

    func test_S_HIER_02_registryHoldsLayersWeakly() {
        let registry = LayerRegistry()
        let kept = CALayer()
        let keptID = registry.register(kept)
        weak var released: CALayer?
        var releasedID: UInt64 = 0
        autoreleasepool {
            let layer = CALayer()
            released = layer
            releasedID = registry.register(layer)
            XCTAssertTrue(registry.layer(for: releasedID) === layer)
        }
        XCTAssertNil(released, "the registry kept the layer alive")
        XCTAssertNil(registry.layer(for: releasedID))

        // The entry of a released layer goes away when asked, and only that one.
        XCTAssertEqual(registry.count, 2)
        registry.removeReleased()
        XCTAssertEqual(registry.count, 1)
        XCTAssertTrue(registry.layer(for: keptID) === kept)
        XCTAssertEqual(registry.register(kept), keptID)
        XCTAssertNil(registry.layer(for: releasedID))
        // The next new layer continues the count: the released ID is not handed out again.
        XCTAssertEqual(registry.register(CALayer()), releasedID + 1)
    }

    func test_S_HIER_02_anAddressTakenOverByANewLayerGetsANewID() throws {
        let registry = LayerRegistry()
        var oldID: UInt64 = 0
        var address: ObjectIdentifier?
        autoreleasepool {
            let old = CALayer()
            oldID = registry.register(old)
            address = ObjectIdentifier(old)
        }
        // Allocate until the allocator hands the old layer's address out again. The registry
        // still has the old entry: nothing asked it to clean up.
        var others: [CALayer] = []
        var reused: CALayer?
        for _ in 0..<100_000 {
            let layer = CALayer()
            if ObjectIdentifier(layer) == address {
                reused = layer
                break
            }
            others.append(layer)
        }
        let layer = try XCTUnwrap(reused, "the allocator never handed the address out again")

        let newID = registry.register(layer)
        XCTAssertNotEqual(newID, oldID)
        XCTAssertGreaterThan(newID, oldID)
        XCTAssertNil(registry.layer(for: oldID), "the old ID must not lead to the new layer")
        XCTAssertTrue(registry.layer(for: newID) === layer)
        XCTAssertEqual(registry.register(layer), newID)
    }

    // MARK: - S-LAYOUT-03 (P-LAYOUT-03)

    func test_S_LAYOUT_03_constraintsAndGuidesShareTheCounterAndLeadToNoLayer() {
        let registry = LayerRegistry()
        let view = UIView()
        let layer = CALayer()
        let constraint = view.widthAnchor.constraint(equalToConstant: 1)
        let guide = UILayoutGuide()
        XCTAssertEqual(registry.register(layer), 1)
        XCTAssertEqual(registry.register(constraint), 2)
        XCTAssertEqual(registry.register(guide), 3)
        XCTAssertEqual(registry.register(constraint), 2)
        XCTAssertEqual(registry.count, 3)
        // Only a layer's ID leads to a layer.
        XCTAssertTrue(registry.layer(for: 1) === layer)
        XCTAssertNil(registry.layer(for: 2))
        XCTAssertNil(registry.layer(for: 3))

        // Held weakly, and forgotten once released.
        weak var released: NSLayoutConstraint?
        autoreleasepool {
            let made = view.heightAnchor.constraint(equalToConstant: 1)
            released = made
            _ = registry.register(made)
        }
        XCTAssertNil(released, "the registry kept the constraint alive")
        XCTAssertEqual(registry.count, 4)
        registry.removeReleased()
        XCTAssertEqual(registry.count, 3)
    }
}
