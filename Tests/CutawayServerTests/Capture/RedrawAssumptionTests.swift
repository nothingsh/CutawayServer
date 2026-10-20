import UIKit
import XCTest

@testable import CutawayServer

/// A view that draws itself in one colour, as a chart draws its bars.
final class SwatchView: UIView {
    var color = UIColor.red

    override func draw(_ rect: CGRect) {
        color.setFill()
        UIRectFill(bounds)
    }
}

/// What redrawing a changed virtual node rests on (assumption H6): UIKit's own behavior,
/// tested without the server.
final class RedrawAssumptionTests: CaptureTestCase {
    private let red = pixelBytes(red: 1, green: 0, blue: 0)
    private let blue = pixelBytes(red: 0, green: 0, blue: 1)

    /// A red swatch of 40 x 40 at (10, 10) in a window, drawn once.
    private func makeSwatch() throws -> SwatchView {
        let window = try makeWindow()
        let swatch = SwatchView(frame: CGRect(x: 10, y: 10, width: 40, height: 40))
        window.addSubview(swatch)
        window.layoutIfNeeded()
        swatch.layer.displayIfNeeded()
        CATransaction.flush()
        return swatch
    }

    private func group(of layer: CALayer) throws -> RawImage {
        let plan = try XCTUnwrap(ImageSizing.plan(bounds: layer.bounds, screenScale: 1, maxTextureDimension: 0))
        return try XCTUnwrap(LayerRenderer.render(layer, mode: .group, plan: plan))
    }

    /// H6: after the model changes and `setNeedsDisplay()`, `displayIfNeeded()` in the same
    /// turn of the main thread makes the next image show the new content.
    func test_S_SET_08_H6_displayIfNeededDrawsTheChangeAtOnce() throws {
        let swatch = try makeSwatch()
        assertPixel(try group(of: swatch.layer).pixel(atPoint: 20, 20), red, "before")

        swatch.color = .blue
        swatch.setNeedsDisplay()
        // For the record only: what an image shows without it.
        let withoutRedraw = try group(of: swatch.layer).pixel(atPoint: 20, 20)
        print("H6: without displayIfNeeded the image shows \(withoutRedraw) (B, G, R, A)")

        swatch.layer.displayIfNeeded()
        assertPixel(try group(of: swatch.layer).pixel(atPoint: 20, 20), blue, "after displayIfNeeded")
        XCTAssertFalse(swatch.layer.needsDisplay())
    }

    /// H6, as a change is made: inside a transaction with actions disabled, after the window
    /// is laid out, before the transaction is committed; the image of the swatch's superview
    /// shows it too, and no animation is started.
    func test_S_SET_08_H6_redrawingInsideTheEditsTransaction() throws {
        let swatch = try makeSwatch()
        let window = try XCTUnwrap(swatch.window)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        swatch.color = .blue
        swatch.setNeedsDisplay()
        window.layoutIfNeeded()
        swatch.layer.displayIfNeeded()
        CATransaction.commit()

        assertPixel(try group(of: window.layer).pixel(atPoint: 30, 30), blue)
        XCTAssertEqual(swatch.layer.animationKeys() ?? [], [])
    }
}
