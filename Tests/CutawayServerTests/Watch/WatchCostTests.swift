import CutawayWire
import QuartzCore
import UIKit
import XCTest

@testable import CutawayServer

/// S-WATCH-07: what notifications cost on the ten thousand layers of S-STAB-01, and that they
/// cost nothing while off.
final class WatchCostTests: CaptureTestCase {
    /// The clock, the work scheduled and the events, all on the main thread.
    private final class Box: @unchecked Sendable {
        var now: TimeInterval = 0
        var wakes: [@MainActor @Sendable () -> Void] = []
        var events: [HierarchyChanged] = []
    }

    private func makeLargeTree() throws -> (window: UIWindow, cell: UIView) {
        let window = try makeWindow()
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let tree = ManyLayersView(rows: 100, columns: 50)
        tree.frame.origin = CGPoint(x: 20, y: 22)
        window.addSubview(tree)
        window.layoutIfNeeded()
        CATransaction.flush()
        XCTAssertEqual(tree.layerCount, 10_101)
        return (window, tree.rowViews[73].subviews[31])
    }

    /// One check, and a hierarchy with its baseline in one block of the main thread, each within
    /// the 150 ms of S-STAB-01.
    func test_S_WATCH_07_aCheckAndAHierarchyFitTheBlock() throws {
        let (_, cell) = try makeLargeTree()
        let registry = LayerRegistry()
        let box = Box()
        var surroundings = HierarchyWatch.Surroundings()
        surroundings.now = { box.now }
        surroundings.schedule = { _, work in box.wakes.append(work) }
        surroundings.makeActivity = { nil }
        let watch = HierarchyWatch(registry: registry, surroundings: surroundings)
        watch.setEnabled(true, isActive: true) { changed in box.events.append(changed) }

        let context = RequestContext.testing(windows: HostWindows.all(), registry: registry)
        let start = CACurrentMediaTime()
        let hierarchy = HierarchyCapture.capture(context)
        let candidate = watch.candidate()
        let block = CACurrentMediaTime() - start
        XCTAssertGreaterThan(hierarchy.nodes.count, 10_101)
        watch.didAnswerHierarchy(candidate)

        cell.layer.position.x += 1
        watch.noteActivity(tracking: false)
        box.now += 0.31
        let checkStart = CACurrentMediaTime()
        while let wake = box.wakes.first {
            box.wakes.removeFirst()
            wake()
        }
        let check = CACurrentMediaTime() - checkStart
        XCTAssertEqual(box.events, [HierarchyChanged(roots: [registry.register(cell.layer)], whole: false)])
        print(String(format: "S-WATCH-07: hierarchy and baseline %.1f ms, check %.1f ms", block * 1000, check * 1000))
        XCTAssertLessThanOrEqual(block, LargeHierarchyTests.longestMainThreadBlock)
        XCTAssertLessThanOrEqual(check, LargeHierarchyTests.longestMainThreadBlock)
    }

    /// Off: no observer is made, no baseline read, nothing scheduled.
    func test_S_WATCH_07_offCostsNothing() throws {
        _ = try makeLargeTree()
        final class Counts: @unchecked Sendable {
            var activities = 0
            var schedules = 0
        }
        let counts = Counts()
        var surroundings = HierarchyWatch.Surroundings()
        surroundings.makeActivity = {
            counts.activities += 1
            return nil
        }
        surroundings.schedule = { _, _ in counts.schedules += 1 }
        let watch = HierarchyWatch(registry: LayerRegistry(), surroundings: surroundings)
        XCTAssertNil(watch.candidate())
        watch.didAnswerHierarchy(nil)
        watch.noteActivity(tracking: false)
        watch.setActive(false)
        watch.setActive(true)
        XCTAssertEqual([counts.activities, counts.schedules], [0, 0])
        XCTAssertNil(watch.baseline)
    }
}
