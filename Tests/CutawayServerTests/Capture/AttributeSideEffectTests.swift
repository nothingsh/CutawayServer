import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// S-ATTR-02: reading attributes leaves the app as it was. No server, no
/// connection.
final class AttributeSideEffectTests: CaptureTestCase {
    /// What layout and display would change, for every layer of a tree.
    private struct TreeState: Equatable {
        /// The layers in pre-order: a layer added or removed shows here.
        var layers: [ObjectIdentifier]
        var needsLayout: [Bool]
        var needsDisplay: [Bool]
    }

    private func allLayers(_ root: CALayer) -> [CALayer] {
        [root] + (root.sublayers ?? []).flatMap(allLayers)
    }

    private func state(of root: CALayer) -> TreeState {
        let layers = allLayers(root)
        return TreeState(
            layers: layers.map(ObjectIdentifier.init),
            needsLayout: layers.map { $0.needsLayout() },
            needsDisplay: layers.map { $0.needsDisplay() }
        )
    }

    private func readAll(_ root: CALayer) -> [[AttributeGroup]] {
        allLayers(root).map(AttributeCatalog.standard.read)
    }

    /// A window with one view of every kind the attribute list tells apart, inside a container
    /// that counts its layouts.
    private func screen() throws -> (window: UIWindow, container: CountingView) {
        let window = try makeWindow()
        let container = CountingView(frame: window.bounds)
        window.addSubview(container)
        let label = UILabel()
        label.text = "Label"
        let button = UIButton(type: .system)
        button.setTitle("Button", for: .normal)
        var configuration = UIButton.Configuration.filled()
        configuration.title = "Configured"
        let scrollView = UIScrollView()
        scrollView.contentSize = CGSize(width: 100, height: 1000)
        let stack = UIStackView(arrangedSubviews: [UILabel(), UIView()])
        let field = UITextField()
        field.text = "Field"
        let textView = UITextView()
        textView.text = String(repeating: "Lorem ipsum ", count: 100)
        let views: [UIView] = [
            label,
            button,
            UIButton(configuration: configuration),
            UIImageView(image: UIImage(systemName: "star")),
            UISwitch(),
            scrollView,
            UITableView(),
            stack,
            field,
            textView,
            UIView()
        ]
        for (index, view) in views.enumerated() {
            view.frame = CGRect(x: 10, y: 10 + 40 * index, width: 200, height: 36)
            container.addSubview(view)
        }
        container.layer.addSublayer(CALayer())
        return (window, container)
    }

    func test_S_ATTR_02_readingMarksNothingForLayout() throws {
        // Laid out and settled, as an idle app is: a read that marks a view for layout would
        // cause a layout pass at the next commit.
        let (window, container) = try screen()
        window.layoutIfNeeded()
        CATransaction.flush()
        let layouts = container.layoutCount
        let before = state(of: window.layer)
        XCTAssertFalse(before.needsLayout.contains(true), "the screen did not settle")
        _ = readAll(window.layer)
        XCTAssertEqual(state(of: window.layer), before)
        window.layoutIfNeeded()
        XCTAssertEqual(container.layoutCount, layouts)
    }

    func test_S_ATTR_02_readingDoesNotLayOut() throws {
        // Before the first layout: reading must not be what lays the views out.
        let fresh = try screen()
        let freshBefore = state(of: fresh.window.layer)
        _ = readAll(fresh.window.layer)
        XCTAssertEqual(state(of: fresh.window.layer), freshBefore)
        XCTAssertEqual(fresh.container.layoutCount, 0)

        // Laid out, then marked for layout: reading must not be what lays them out again.
        let laidOut = try screen()
        laidOut.window.layoutIfNeeded()
        CATransaction.flush()
        let layouts = laidOut.container.layoutCount
        XCTAssertGreaterThan(layouts, 0)
        for layer in allLayers(laidOut.window.layer) { layer.setNeedsLayout() }
        let before = state(of: laidOut.window.layer)
        XCTAssertTrue(before.needsLayout.allSatisfy { $0 })
        _ = readAll(laidOut.window.layer)
        XCTAssertEqual(state(of: laidOut.window.layer), before)
        XCTAssertEqual(laidOut.container.layoutCount, layouts)
    }

    func test_S_ATTR_02_readingChangesNothingVisible() throws {
        let (window, _) = try screen()
        window.layoutIfNeeded()
        CATransaction.flush()
        let registry = LayerRegistry()
        let hierarchy = HierarchyCapture.capture(windows: [window], registry: registry)
        let pixels = try render(window)

        let first = readAll(window.layer)
        XCTAssertEqual(HierarchyCapture.capture(windows: [window], registry: registry), hierarchy)
        XCTAssertEqual(try render(window), pixels)
        XCTAssertEqual(readAll(window.layer), first)
    }
}
