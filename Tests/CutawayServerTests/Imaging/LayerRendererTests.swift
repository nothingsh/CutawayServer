import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Rendering one layer into a bitmap. No server, no connection: every test
/// calls the renderer on the main thread and samples pixels of known colours.
final class LayerRendererTests: CaptureTestCase {
    private let red = pixelBytes(red: 1, green: 0, blue: 0)
    private let green = pixelBytes(red: 0, green: 1, blue: 0)
    private let blue = pixelBytes(red: 0, green: 0, blue: 1)
    private let clear: [UInt8] = [0, 0, 0, 0]

    /// Renders at 2 pixels per point unless told otherwise.
    private func image(
        of layer: CALayer,
        _ mode: LayerRenderer.Mode,
        scale: CGFloat = 2,
        max: UInt32 = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> RawImage {
        let plan = try XCTUnwrap(
            ImageSizing.plan(bounds: layer.bounds, screenScale: scale, maxTextureDimension: max),
            file: file,
            line: line
        )
        return try XCTUnwrap(LayerRenderer.render(layer, mode: mode, plan: plan), file: file, line: line)
    }

    /// A red view of 100 x 60 at (30, 40) in a window, with a blue 20 x 20 child at (10, 10).
    private func parentAndChild() throws -> (parent: UIView, child: UIView) {
        let window = try makeWindow()
        let parent = colorView(CGRect(x: 30, y: 40, width: 100, height: 60), red: 1, green: 0, blue: 0)
        let child = colorView(CGRect(x: 10, y: 10, width: 20, height: 20), red: 0, green: 0, blue: 1)
        parent.addSubview(child)
        window.addSubview(parent)
        return (parent, child)
    }

    // MARK: - S-SHOT-01

    func test_S_SHOT_01_groupCoversTheBoundsAndShowsTheSubtree() throws {
        let (parent, _) = try parentAndChild()
        // Sticks out of the parent at the bottom right; the parent does not clip.
        parent.addSubview(colorView(CGRect(x: 90, y: 50, width: 40, height: 40), red: 0, green: 1, blue: 0))

        let group = try image(of: parent.layer, .group)

        // Exactly the bounds: 100 x 60 points at 2x, whatever sticks out.
        XCTAssertEqual([group.pixelWidth, group.pixelHeight, group.bytesPerRow], [200, 120, 800])
        XCTAssertEqual(group.scale, 2)
        XCTAssertEqual(group.pixels.count, 800 * 120)
        // The parent and the children, each in its own colour, at the places they have in the
        // parent's coordinates. Where the parent is in the window does not matter.
        assertPixel(group.pixel(atPoint: 50, 30), red)
        assertPixel(group.pixel(atPoint: 1, 1), red)
        assertPixel(group.pixel(atPoint: 11, 11), blue)
        assertPixel(group.pixel(atPoint: 29, 29), blue)
        assertPixel(group.pixel(atPoint: 31, 31), red)
        assertPixel(group.pixel(atPoint: 95, 55), green)
        assertPixel(group.pixel(atPoint: 99.5, 59.5), green)

        // The same picture at another scale.
        let single = try image(of: parent.layer, .group, scale: 1)
        XCTAssertEqual([single.pixelWidth, single.pixelHeight], [100, 60])
        assertPixel(single.pixel(atPoint: 15, 15), blue)
        assertPixel(single.pixel(atPoint: 50, 30), red)
    }

    func test_S_SHOT_01_ownOpacityTransformAndHiddenAreLeftOut() throws {
        let window = try makeWindow()
        let view = colorView(CGRect(x: 50, y: 50, width: 80, height: 40), red: 0, green: 1, blue: 0)
        view.alpha = 0.5
        let rotation = CGAffineTransform(rotationAngle: .pi / 6)
        view.transform = rotation
        window.addSubview(view)

        // Opaque and upright: all four corners and the centre are the view's colour.
        for mode in [LayerRenderer.Mode.group, .solo] {
            let image = try image(of: view.layer, mode)
            XCTAssertEqual([image.pixelWidth, image.pixelHeight], [160, 80])
            for (x, y) in [(0.0, 0.0), (79.5, 0), (0, 39.5), (79.5, 39.5), (40, 20)] {
                assertPixel(image.pixel(atPoint: x, y), green, "at (\(x), \(y))")
            }
        }
        XCTAssertEqual(view.alpha, 0.5)
        XCTAssertEqual(view.layer.opacity, 0.5)
        XCTAssertEqual(view.transform, rotation)
        XCTAssertFalse(view.isHidden)

        // A hidden layer is rendered as if it were visible, and is still hidden afterwards.
        view.isHidden = true
        assertPixel(try image(of: view.layer, .group).pixel(atPoint: 40, 20), green)
        assertPixel(try image(of: view.layer, .solo).pixel(atPoint: 40, 20), green)
        XCTAssertTrue(view.isHidden)
        XCTAssertTrue(view.layer.isHidden)
        XCTAssertEqual(view.layer.opacity, 0.5)

        // A layer that backs no view is treated the same.
        let bare = CALayer()
        bare.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        bare.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1).cgColor
        bare.opacity = 0.25
        bare.isHidden = true
        bare.transform = CATransform3DMakeScale(3, 3, 1)
        window.layer.addSublayer(bare)
        let bareImage = try image(of: bare, .group)
        XCTAssertEqual([bareImage.pixelWidth, bareImage.pixelHeight], [20, 20])
        assertPixel(bareImage.pixel(atPoint: 5, 5), blue)
        XCTAssertEqual(bare.opacity, 0.25)
        XCTAssertTrue(bare.isHidden)
    }

    func test_S_SHOT_01_sublayersKeepTheirOwnProperties() throws {
        let (parent, child) = try parentAndChild()
        let hidden = colorView(CGRect(x: 40, y: 10, width: 20, height: 20), red: 0, green: 1, blue: 0)
        hidden.isHidden = true
        parent.addSubview(hidden)
        // Scaled to twice its size about its centre (80, 30): it covers 60...100 x 10...50.
        let scaled = colorView(CGRect(x: 70, y: 20, width: 20, height: 20), red: 0, green: 1, blue: 0)
        scaled.transform = CGAffineTransform(scaleX: 2, y: 2)
        parent.addSubview(scaled)
        child.alpha = 0.5

        let group = try image(of: parent.layer, .group)
        // Half blue over red.
        assertPixel(group.pixel(atPoint: 20, 20), pixelBytes(red: 0.5, green: 0, blue: 0.5))
        assertPixel(group.pixel(atPoint: 50, 20), red, "a hidden sublayer is not drawn")
        assertPixel(group.pixel(atPoint: 62, 12), green, "a sublayer is drawn with its transform")
        assertPixel(group.pixel(atPoint: 98, 48), green)
        assertPixel(group.pixel(atPoint: 58, 30), red)
    }

    func test_S_SHOT_01_imageStartsAtTheBoundsOrigin() throws {
        let window = try makeWindow()
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 100, height: 300)
        scrollView.addSubview(colorView(CGRect(x: 0, y: 0, width: 100, height: 100), red: 1, green: 0, blue: 0))
        scrollView.addSubview(colorView(CGRect(x: 0, y: 100, width: 100, height: 100), red: 0, green: 0, blue: 1))
        scrollView.addSubview(colorView(CGRect(x: 0, y: 200, width: 100, height: 100), red: 0, green: 1, blue: 0))
        window.addSubview(scrollView)
        scrollView.contentOffset = CGPoint(x: 0, y: 150)
        XCTAssertEqual(scrollView.layer.bounds.origin, CGPoint(x: 0, y: 150))

        // The image's top left corner is the point (0, 150) of the content (P-DET-07).
        let group = try image(of: scrollView.layer, .group)
        XCTAssertEqual([group.pixelWidth, group.pixelHeight], [200, 200])
        assertPixel(group.pixel(atPoint: 50, 1), blue)
        assertPixel(group.pixel(atPoint: 50, 49), blue)
        assertPixel(group.pixel(atPoint: 50, 51), green)
        assertPixel(group.pixel(atPoint: 50, 99), green)
        XCTAssertEqual(scrollView.contentOffset, CGPoint(x: 0, y: 150))
    }

    func test_S_SHOT_01_rendersTextAndShapes() throws {
        let window = try makeWindow()
        // What the demo app shows, and what `cutaway-probe --expect-demo` samples.
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        label.backgroundColor = .white
        label.textColor = .black
        label.font = .boldSystemFont(ofSize: 30)
        label.text = "MMMMMMMM"
        window.addSubview(label)
        let text = try image(of: label.layer, .group, scale: 1)
        let dark = stride(from: 0, to: text.pixels.count, by: 4).filter { text.pixels[$0] < 64 }.count
        XCTAssertGreaterThan(dark, 200, "the label's text was not drawn")
        assertPixel(text.pixel(x: 199, y: 0), [255, 255, 255, 255])

        let shape = CAShapeLayer()
        shape.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        shape.position = CGPoint(x: 100, y: 100)
        shape.path = CGPath(ellipseIn: shape.bounds, transform: nil)
        shape.fillColor = UIColor(red: 1, green: 1, blue: 0, alpha: 1).cgColor
        window.layer.addSublayer(shape)
        let circle = try image(of: shape, .group)
        assertPixel(circle.pixel(atPoint: 20, 20), pixelBytes(red: 1, green: 1, blue: 0))
        assertPixel(circle.pixel(atPoint: 0.5, 0.5), clear, "outside the circle")
    }

    // MARK: - S-SHOT-02

    func test_S_SHOT_02_soloLeavesTheSublayersOut() throws {
        let (parent, _) = try parentAndChild()
        let bare = CALayer()
        bare.frame = CGRect(x: 60, y: 30, width: 20, height: 20)
        bare.backgroundColor = UIColor(red: 0, green: 1, blue: 0, alpha: 1).cgColor
        parent.layer.addSublayer(bare)

        let solo = try image(of: parent.layer, .solo)
        XCTAssertEqual([solo.pixelWidth, solo.pixelHeight], [200, 120])
        // Where the child view and the bare sublayer are, the parent's own colour shows.
        assertPixel(solo.pixel(atPoint: 20, 20), red)
        assertPixel(solo.pixel(atPoint: 70, 40), red)
        assertPixel(solo.pixel(atPoint: 50, 30), red)

        // The group still has them.
        let group = try image(of: parent.layer, .group)
        assertPixel(group.pixel(atPoint: 20, 20), blue)
        assertPixel(group.pixel(atPoint: 70, 40), green)
    }

    func test_S_SHOT_02_soloRestoresEverySublayer() throws {
        let (parent, child) = try parentAndChild()
        let hiddenView = colorView(CGRect(x: 40, y: 10, width: 20, height: 20), red: 0, green: 1, blue: 0)
        hiddenView.isHidden = true
        parent.addSubview(hiddenView)
        let bare = CALayer()
        bare.frame = CGRect(x: 60, y: 30, width: 20, height: 20)
        parent.layer.addSublayer(bare)
        let hiddenBare = CALayer()
        hiddenBare.isHidden = true
        parent.layer.addSublayer(hiddenBare)

        let sublayers = try XCTUnwrap(parent.layer.sublayers)
        XCTAssertEqual(sublayers.count, 4)
        let before = sublayers.map(\.isHidden)
        XCTAssertEqual(before, [false, true, false, true])

        _ = try image(of: parent.layer, .solo)

        XCTAssertEqual(parent.layer.sublayers?.map(\.isHidden), before)
        XCTAssertFalse(child.isHidden)
        XCTAssertTrue(hiddenView.isHidden)
        XCTAssertEqual(parent.layer.sublayers?.count, 4)
    }

    func test_S_SHOT_02_restoresWhenTheRenderingFails() throws {
        let (parent, child) = try parentAndChild()
        parent.alpha = 0.5
        parent.isHidden = true
        let plan = try XCTUnwrap(
            ImageSizing.plan(bounds: parent.layer.bounds, screenScale: 2, maxTextureDimension: 0)
        )

        // The drawing step fails half way, while the layers are changed for the screenshot.
        var statesWhileDrawing: [Bool] = []
        let image = LayerRenderer.render(parent.layer, mode: .solo, plan: plan) { layer, _ in
            statesWhileDrawing = [layer.isHidden, layer.opacity == 1, child.layer.isHidden]
            return false
        }

        XCTAssertNil(image)
        XCTAssertEqual(statesWhileDrawing, [false, true, true], "the layers were not changed for the screenshot")
        XCTAssertFalse(child.layer.isHidden)
        XCTAssertTrue(parent.layer.isHidden)
        XCTAssertEqual(parent.layer.opacity, 0.5)
    }

    func test_S_SHOT_02_capturingLeavesNoTrace() throws {
        let window = try makeWindow()
        window.backgroundColor = .white
        let stack = UIStackView(frame: CGRect(x: 10, y: 10, width: 300, height: 100))
        stack.axis = .horizontal
        stack.distribution = .fillEqually
        let arranged = (0..<4).map { index -> CountingView in
            let view = CountingView()
            view.backgroundColor = UIColor(red: CGFloat(index) / 4, green: 0.5, blue: 1, alpha: 1)
            stack.addArrangedSubview(view)
            return view
        }
        arranged[1].alpha = 0.5
        arranged[2].isHidden = true
        window.addSubview(stack)
        // Layers that back no view animate a change of `isHidden` or `opacity` on their own,
        // unless the change is made with actions disabled.
        let bare = CALayer()
        bare.frame = CGRect(x: 10, y: 150, width: 100, height: 50)
        bare.backgroundColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1).cgColor
        bare.opacity = 0.5
        let bareChild = CALayer()
        bareChild.frame = CGRect(x: 10, y: 10, width: 20, height: 20)
        bareChild.backgroundColor = UIColor(red: 0, green: 0, blue: 1, alpha: 1).cgColor
        bare.addSublayer(bareChild)
        let bareHidden = CALayer()
        bareHidden.frame = CGRect(x: 120, y: 150, width: 50, height: 50)
        bareHidden.isHidden = true
        window.layer.addSublayer(bare)
        window.layer.addSublayer(bareHidden)
        window.layoutIfNeeded()
        // Committed: the layers are on screen, and changes to them from here on count.
        CATransaction.flush()

        var layers: [CALayer] = []
        var stackOfLayers = [window.layer]
        while let layer = stackOfLayers.popLast() {
            layers.append(layer)
            stackOfLayers += layer.sublayers ?? []
        }
        let pictureBefore = try render(window)
        let framesBefore = arranged.map(\.frame)
        let layoutBefore = arranged.map(\.layoutCount)
        let hiddenBefore = layers.map(\.isHidden)
        let opacityBefore = layers.map(\.opacity)
        XCTAssertTrue(layers.allSatisfy { ($0.animationKeys() ?? []).isEmpty })

        // Both images of every layer of the window.
        for layer in layers {
            guard
                let plan = ImageSizing.plan(bounds: layer.bounds, screenScale: 1, maxTextureDimension: 0)
            else { continue }
            XCTAssertNotNil(LayerRenderer.render(layer, mode: .solo, plan: plan))
            XCTAssertNotNil(LayerRenderer.render(layer, mode: .group, plan: plan))
        }

        // Nothing was laid out, and nothing is waiting to be: the stack view saw no change.
        XCTAssertEqual(arranged.map(\.layoutCount), layoutBefore)
        window.layoutIfNeeded()
        CATransaction.flush()
        XCTAssertEqual(arranged.map(\.layoutCount), layoutBefore)
        XCTAssertEqual(arranged.map(\.frame), framesBefore)
        XCTAssertEqual(layers.map(\.isHidden), hiddenBefore)
        XCTAssertEqual(layers.map(\.opacity), opacityBefore)
        XCTAssertEqual(arranged.map(\.isHidden), [false, false, true, false])
        XCTAssertEqual(arranged[1].alpha, 0.5)
        // No implicit animation was started by hiding and showing layers.
        for layer in layers {
            XCTAssertEqual(layer.animationKeys() ?? [], [], "\(layer)")
        }
        XCTAssertEqual(try render(window), pictureBefore)
    }

    // MARK: - S-SHOT-03

    func test_S_SHOT_03_largeLayersAreScaledDown() throws {
        let window = try makeWindow()
        // 2000 x 1000 points: red, with the right half blue.
        let large = colorView(CGRect(x: 0, y: 0, width: 2000, height: 1000), red: 1, green: 0, blue: 0)
        large.addSubview(colorView(CGRect(x: 1000, y: 0, width: 1000, height: 1000), red: 0, green: 0, blue: 1))
        window.addSubview(large)

        let reduced = try image(of: large.layer, .group, scale: 2, max: 1024)
        XCTAssertEqual([reduced.pixelWidth, reduced.pixelHeight, reduced.bytesPerRow], [1024, 512, 4096])
        XCTAssertEqual(reduced.scale, 0.512)
        // The whole layer is in the smaller image, not a corner of it.
        assertPixel(reduced.pixel(atPoint: 500, 500), red)
        assertPixel(reduced.pixel(atPoint: 1500, 500), blue)
        assertPixel(reduced.pixel(atPoint: 990, 990), red)
        assertPixel(reduced.pixel(atPoint: 1010, 10), blue)
        assertPixel(reduced.pixel(x: 1023, y: 511), blue)
    }

    // MARK: - S-SHOT-05

    func test_S_SHOT_05_pixelsArePremultipliedBGRA() throws {
        let window = try makeWindow()
        let view = colorView(
            CGRect(x: 0, y: 0, width: 30, height: 20),
            red: 1,
            green: 0.5,
            blue: 0.25,
            alpha: 0.5
        )
        window.addSubview(view)

        let raw = try image(of: view.layer, .group)
        // Each colour component is multiplied by the alpha of 0.5; the bytes are B, G, R, A.
        let expected = pixelBytes(red: 1, green: 0.5, blue: 0.25, alpha: 0.5)
        XCTAssertEqual(expected, [32, 64, 128, 128])
        assertPixel(raw.pixel(x: 0, y: 0), expected)
        assertPixel(raw.pixel(x: 59, y: 39), expected)
        XCTAssertEqual(raw.bytesPerRow, raw.pixelWidth * 4)

        // P-IMG-01: `data` decompresses to bytes_per_row x pixel_height bytes, these pixels.
        let wire = try XCTUnwrap(ImageEncoder.compress(raw))
        XCTAssertEqual(wire.encoding, .bgra8PremultipliedLZFSE)
        XCTAssertEqual([wire.pixelWidth, wire.pixelHeight, wire.bytesPerRow], [60, 40, 240])
        XCTAssertEqual(wire.scale, 2)
        let pixels = try (wire.data as NSData).decompressed(using: .lzfse) as Data
        XCTAssertEqual(pixels.count, 240 * 40)
        XCTAssertEqual(pixels, raw.pixels)
        XCTAssertLessThan(wire.data.count, pixels.count)

        // A bitmap that is not what it says is not sent.
        var broken = raw
        broken.pixels.removeLast()
        XCTAssertNil(ImageEncoder.compress(broken))
    }

    func test_S_SHOT_05_transparentPixelsCompressLikeAnyOther() throws {
        let zeros = RawImage(pixelWidth: 60, pixelHeight: 40, bytesPerRow: 240, scale: 2, pixels: Data(count: 240 * 40))
        var lastNotZero = zeros
        lastNotZero.pixels[lastNotZero.pixels.count - 1] = 1
        XCTAssertTrue(ImageEncoder.isZero(zeros.pixels))
        XCTAssertFalse(ImageEncoder.isZero(lastNotZero.pixels))
        XCTAssertFalse(ImageEncoder.isZero(Data()))

        // The second time the zeros come from the cache; both are the bytes LZFSE gives.
        let direct = try (zeros.pixels as NSData).compressed(using: .lzfse) as Data
        for raw in [zeros, zeros, lastNotZero] {
            let wire = try XCTUnwrap(ImageEncoder.compress(raw))
            XCTAssertEqual([wire.pixelWidth, wire.pixelHeight, wire.bytesPerRow], [60, 40, 240])
            XCTAssertEqual(try (wire.data as NSData).decompressed(using: .lzfse) as Data, raw.pixels)
            if raw == zeros { XCTAssertEqual(wire.data, direct) }
        }
    }
}
