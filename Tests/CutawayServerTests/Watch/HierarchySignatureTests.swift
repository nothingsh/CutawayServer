import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// What a comparison of signatures reports (PROTOCOL.md, P-WATCH-03, P-WATCH-06, P-WATCH-07):
/// the node a change is reported on, roots that do not contain each other, the whole when the
/// windows changed, nothing when nothing did.
final class HierarchySignatureTests: CaptureTestCase {
    private let registry = LayerRegistry()

    /// A window with two branches of two leaves each.
    private func makeTree() throws -> (window: UIWindow, branches: [UIView], leaves: [[UIView]]) {
        let window = try makeWindow()
        var branches: [UIView] = []
        var leaves: [[UIView]] = []
        for index in 0..<2 {
            let branch = UIView(frame: CGRect(x: 10, y: 10 + CGFloat(index) * 100, width: 200, height: 80))
            window.addSubview(branch)
            leaves.append((0..<2).map { leafIndex in
                let leaf = UIView(frame: CGRect(x: 10 + CGFloat(leafIndex) * 50, y: 10, width: 40, height: 40))
                branch.addSubview(leaf)
                return leaf
            })
            branches.append(branch)
        }
        window.layoutIfNeeded()
        return (window, branches, leaves)
    }

    private func snapshot(_ windows: UIWindow...) -> HierarchySignature.Snapshot {
        HierarchySignature.snapshot(of: windows, registry: registry)
    }

    private func roots(_ layers: CALayer...) -> HierarchyChanged {
        HierarchyChanged(roots: layers.map(registry.register), whole: false)
    }

    func test_S_WATCH_03_nothingChangedReportsNothing() throws {
        let (window, _, _) = try makeTree()
        let baseline = snapshot(window)
        XCTAssertNil(HierarchySignature.changes(from: baseline, to: snapshot(window)))
    }

    /// A node's own fields, each of P-WATCH-07: reported on the node itself.
    func test_S_WATCH_03_ownFieldsAreReportedOnTheNode() throws {
        let (window, _, leaves) = try makeTree()
        let layer = leaves[1][0].layer
        let changes: [(String, () -> Void)] = [
            ("bounds", { layer.bounds.size.width += 1 }),
            ("position", { layer.position.x += 1 }),
            ("anchorPoint", { layer.anchorPoint.x = 0.25 }),
            ("transform", { layer.transform = CATransform3DMakeScale(2, 2, 1) }),
            ("hidden", { layer.isHidden.toggle() }),
            ("opacity", { layer.opacity = 0.5 }),
            ("masksToBounds", { layer.masksToBounds.toggle() }),
            ("contents", { layer.contents = UIImage.checkmark.cgImage })
        ]
        for (name, change) in changes {
            let baseline = snapshot(window)
            change()
            XCTAssertEqual(HierarchySignature.changes(from: baseline, to: snapshot(window)), roots(layer), name)
        }
    }

    /// Drawn and committed again with nothing changed, after turns of the main run loop: the
    /// contents are the same objects, so a check reports nothing.
    func test_S_WATCH_03_redrawingNothingReportsNothing() throws {
        let window = try makeWindow()
        let label = UILabel(frame: CGRect(x: 10, y: 10, width: 200, height: 30))
        label.text = "Hello"
        let imageView = UIImageView(frame: CGRect(x: 10, y: 50, width: 40, height: 40))
        imageView.image = UIImage.checkmark
        for view in [label, imageView] {
            window.addSubview(view)
        }
        window.layoutIfNeeded()
        label.layer.displayIfNeeded()
        CATransaction.flush()
        let baseline = snapshot(window)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        label.setNeedsDisplay()
        label.layer.displayIfNeeded()
        CATransaction.flush()
        XCTAssertNil(HierarchySignature.changes(from: baseline, to: snapshot(window)))
    }

    /// Added, removed, moved and reordered nodes, and `zPosition`: reported on the parents; a
    /// moved node on both, a node that is gone never.
    func test_S_WATCH_03_structureIsReportedOnTheParent() throws {
        let (window, branches, leaves) = try makeTree()
        var baseline = snapshot(window)
        branches[0].addSubview(UIView())
        XCTAssertEqual(HierarchySignature.changes(from: baseline, to: snapshot(window)), roots(branches[0].layer))

        baseline = snapshot(window)
        branches[1].addSubview(leaves[0][0])
        XCTAssertEqual(
            HierarchySignature.changes(from: baseline, to: snapshot(window)),
            roots(branches[0].layer, branches[1].layer)
        )

        baseline = snapshot(window)
        branches[1].exchangeSubview(at: 0, withSubviewAt: 1)
        XCTAssertEqual(HierarchySignature.changes(from: baseline, to: snapshot(window)), roots(branches[1].layer))

        baseline = snapshot(window)
        leaves[1][1].layer.zPosition = -1
        XCTAssertEqual(HierarchySignature.changes(from: baseline, to: snapshot(window)), roots(branches[1].layer))

        baseline = snapshot(window)
        leaves[1][1].removeFromSuperview()
        XCTAssertEqual(HierarchySignature.changes(from: baseline, to: snapshot(window)), roots(branches[1].layer))
    }

    /// A node moved under a new node: the new node is not in the baseline, so the change is on
    /// the nearest node above it that is, which also holds the node's old place.
    func test_S_WATCH_03_aChangeBelowANewNodeIsReportedHigher() throws {
        let (window, branches, leaves) = try makeTree()
        let baseline = snapshot(window)
        let wrapper = UIView(frame: branches[0].bounds)
        branches[0].addSubview(wrapper)
        wrapper.addSubview(leaves[0][1])
        XCTAssertEqual(HierarchySignature.changes(from: baseline, to: snapshot(window)), roots(branches[0].layer))
    }

    /// A change inside a subtree that is also reported: only the top one.
    func test_S_WATCH_03_rootsDoNotContainEachOther() throws {
        let (window, branches, leaves) = try makeTree()
        let baseline = snapshot(window)
        branches[0].frame.origin.y += 1
        leaves[0][0].alpha = 0.5
        XCTAssertEqual(HierarchySignature.changes(from: baseline, to: snapshot(window)), roots(branches[0].layer))
    }

    /// A window more, a window less, their order, the key window: the whole.
    func test_S_WATCH_03_windowsAreTheWhole() throws {
        let (window, _, _) = try makeTree()
        let other = try makeWindow()
        let both = snapshot(window, other)
        XCTAssertEqual(HierarchySignature.changes(from: both, to: snapshot(window)), .everything)
        XCTAssertEqual(HierarchySignature.changes(from: snapshot(window), to: both), .everything)
        XCTAssertEqual(HierarchySignature.changes(from: both, to: snapshot(other, window)), .everything)
        var key = both
        key.keyWindowID = registry.register(other.layer)
        XCTAssertEqual(HierarchySignature.changes(from: both, to: key), .everything)
    }

    /// P-WATCH-09: an absorbed window is not compared; the others are.
    func test_S_WATCH_06_absorbedWindowsAreNotCompared() throws {
        let (window, _, leaves) = try makeTree()
        let other = try makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        other.addSubview(view)
        let baseline = snapshot(window, other)
        leaves[0][0].frame.origin.x += 3
        view.frame.origin.x += 3
        XCTAssertEqual(
            HierarchySignature.changes(
                from: baseline,
                to: snapshot(window, other),
                absorbing: [registry.register(window.layer)]
            ),
            roots(view.layer)
        )
    }

    /// P-WATCH-06: a subtree's entries renew only its nodes; the stale signatures above it are
    /// gone through, and its root's place among its siblings is still reported on the parent.
    func test_S_WATCH_04_aSubtreeRenewsOnlyItsNodes() throws {
        let (window, branches, leaves) = try makeTree()
        var baseline = snapshot(window)
        leaves[0][0].frame.origin.x += 3
        branches[0].exchangeSubview(at: 0, withSubviewAt: 1)
        // The client gets the subtree of the leaf, which tells it the leaf's new frame but not
        // its new place.
        baseline.entries.merge(HierarchySignature.entries(ofSubtree: leaves[0][0].layer, registry: registry)) { $1 }
        XCTAssertEqual(HierarchySignature.changes(from: baseline, to: snapshot(window)), roots(branches[0].layer))

        // Told of the parent too: nothing left.
        baseline.entries.merge(HierarchySignature.entries(ofSubtree: branches[0].layer, registry: registry)) { $1 }
        XCTAssertNil(HierarchySignature.changes(from: baseline, to: snapshot(window)))
    }
}
