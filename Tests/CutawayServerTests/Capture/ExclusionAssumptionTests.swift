import UIKit
import XCTest

@testable import CutawayServer

/// What leaving excluded layers out of images rests on (assumption H7): UIKit's own behavior,
/// tested without the server.
final class ExclusionAssumptionTests: CaptureTestCase {
    private let white = pixelBytes(red: 1, green: 1, blue: 1)
    private let red = pixelBytes(red: 1, green: 0, blue: 0)

    /// A white view with a horizontal stack of four counting views, each 75 points wide; the
    /// second holds a red 20 x 20 subview at (10, 10), which holds a blue one.
    @MainActor
    private struct Scene {
        let window: UIWindow
        let container: UIView
        let arranged: [CountingView]
        let deep: CountingView

        var views: [UIView] { [container] + arranged + [deep] }
        var layoutCounts: [Int] { arranged.map(\.layoutCount) + [deep.layoutCount] }
    }

    private func makeScene() throws -> Scene {
        let window = try makeWindow()
        let container = colorView(CGRect(x: 10, y: 10, width: 300, height: 100), red: 1, green: 1, blue: 1)
        let stack = UIStackView(frame: container.bounds)
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        let arranged = (0..<4).map { _ -> CountingView in
            let view = CountingView()
            view.backgroundColor = .white
            stack.addArrangedSubview(view)
            return view
        }
        let deep = CountingView(frame: CGRect(x: 10, y: 10, width: 20, height: 20))
        deep.backgroundColor = .red
        deep.addSubview(colorView(CGRect(x: 5, y: 5, width: 5, height: 5), red: 0, green: 0, blue: 1))
        arranged[1].addSubview(deep)
        container.addSubview(stack)
        window.addSubview(container)
        window.layoutIfNeeded()
        CATransaction.flush()
        return Scene(window: window, container: container, arranged: arranged, deep: deep)
    }

    /// Renders the group of `layer` with `hidden` hidden the way the server plans to: on the
    /// layer, with actions disabled, put back before the transaction is committed.
    private func group(of layer: CALayer, hiding hidden: [CALayer]) throws -> RawImage {
        let plan = try XCTUnwrap(ImageSizing.plan(bounds: layer.bounds, screenScale: 1, maxTextureDimension: 0))
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer {
            for layer in hidden { layer.isHidden = false }
            CATransaction.commit()
        }
        for layer in hidden { layer.isHidden = true }
        return try XCTUnwrap(LayerRenderer.render(layer, mode: .group, plan: plan))
    }

    /// H7: hiding a layer deep inside a stack view for the time of one capture leaves it out of
    /// the image, lays nothing out, starts no animation, and leaves every state as it was.
    func test_S_SHOT_13_H7_hidingADeepLayerLeavesNoTrace() throws {
        let scene = try makeScene()
        try assertNoTrace(scene) {
            let image = try group(of: scene.container.layer, hiding: [scene.deep.layer])
            // The red view sits at (75 + 10, 10) in the container; white where it was.
            assertPixel(image.pixel(atPoint: 90, 15), white)
        }
    }

    /// H7: hiding the layer of an arranged subview itself, which the stack view watches through
    /// `isHidden` of the view, does not make it rearrange.
    func test_S_SHOT_13_H7_hidingAnArrangedSubviewsLayerLeavesNoTrace() throws {
        let scene = try makeScene()
        scene.arranged[1].backgroundColor = .red
        CATransaction.flush()
        try assertNoTrace(scene) {
            let image = try group(of: scene.container.layer, hiding: [scene.arranged[1].layer])
            assertPixel(image.pixel(atPoint: 110, 50), white)
            // Without hiding it, the arranged view is there.
            let plain = try group(of: scene.container.layer, hiding: [])
            assertPixel(plain.pixel(atPoint: 110, 50), red)
        }
    }

    private func assertNoTrace(
        _ scene: Scene,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ capture: () throws -> Void
    ) throws {
        let frames = scene.views.map(\.frame)
        let layouts = scene.layoutCounts
        let needsLayout = scene.views.map { $0.layer.needsLayout() }
        let picture = try render(scene.window)

        try capture()

        XCTAssertEqual(scene.layoutCounts, layouts, "laid out", file: file, line: line)
        XCTAssertEqual(scene.views.map { $0.layer.needsLayout() }, needsLayout, "needs layout", file: file, line: line)
        XCTAssertEqual(scene.views.map(\.isHidden), scene.views.map { _ in false }, file: file, line: line)
        for view in scene.views {
            XCTAssertEqual(view.layer.animationKeys() ?? [], [], "\(view)", file: file, line: line)
        }
        scene.window.layoutIfNeeded()
        CATransaction.flush()
        XCTAssertEqual(scene.layoutCounts, layouts, "laid out later", file: file, line: line)
        XCTAssertEqual(scene.views.map(\.frame), frames, file: file, line: line)
        XCTAssertEqual(try render(scene.window), picture, file: file, line: line)
    }
}
