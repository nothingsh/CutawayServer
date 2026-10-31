import CutawayWire
import SwiftUI
import UIKit
import XCTest

@testable import CutawayServer

private final class SecretView: UIView {}

@available(iOS 26.0, *)
private struct GlassCapsule: View {
    var body: some View {
        Text("EN").padding(20).glassEffect(.regular, in: Capsule())
    }
}

/// Layers that erase a drawn group (S-SHOT-16), and groups taken from what the app composited
/// (S-SHOT-17). No server, no connection.
final class GroupEffectsTests: CaptureTestCase {
    private let registry = LayerRegistry()
    private let white = pixelBytes(red: 1, green: 1, blue: 1)
    private let red = pixelBytes(red: 1, green: 0, blue: 0)
    private let blue = pixelBytes(red: 0, green: 0, blue: 1)
    private let clear: [UInt8] = [0, 0, 0, 0]

    private func capture(
        _ layer: CALayer,
        in window: UIWindow,
        solo: Bool = false,
        store: ExtensionStore = ExtensionStore(),
        memo: RequestMemo = RequestMemo(),
        composite: ((UIView, ImagePlan) -> RawImage?)? = nil
    ) throws -> CapturedDetail {
        let context = RequestContext.testing(windows: [window], registry: registry, extensions: store, memo: memo)
        let request = LayerDetailRequest(
            layerID: registry.register(layer),
            wantSolo: solo,
            wantGroup: true,
            wantAttributes: false,
            wantConstraints: false
        )
        return try XCTUnwrap(
            DetailCapture.capture(
                request,
                maxTextureDimension: 0,
                in: context,
                stopFlag: StopFlag(),
                screenScale: 1,
                readAttributes: { _ in [] },
                composite: composite ?? { LayerRenderer.composited($0, plan: $1) }
            )
        )
    }

    /// The group as `render(in:)` gives it.
    private func drawnGroup(
        _ layer: CALayer,
        in window: UIWindow,
        memo: RequestMemo = RequestMemo()
    ) throws -> RawImage {
        try XCTUnwrap(capture(layer, in: window, memo: memo, composite: { _, _ in nil }).group)
    }

    private func group(
        _ layer: CALayer,
        in window: UIWindow,
        store: ExtensionStore = ExtensionStore()
    ) throws -> RawImage {
        try XCTUnwrap(capture(layer, in: window, store: store).group)
    }

    private func settle() {
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    }

    /// A white 200 x 100 container in a window.
    private func makeContainer(in window: UIWindow) -> UIView {
        let container = colorView(CGRect(x: 0, y: 0, width: 200, height: 100), red: 1, green: 1, blue: 1)
        window.addSubview(container)
        return container
    }

    private func eraser(frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 100)) -> CALayer {
        let layer = CALayer()
        layer.frame = frame
        layer.compositingFilter = "destIn"
        return layer
    }

    /// A blur inside a view, the plainest effect `render(in:)` leaves out.
    private func addBlur(to view: UIView) {
        view.addSubview(UIVisualEffectView(effect: UIBlurEffect(style: .regular)))
    }

    @available(iOS 26, *)
    private func makeScrollEdgePage(in window: UIWindow) -> UIScrollView {
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let page = UIViewController()
        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        scroll.contentSize = CGSize(width: 402, height: 3000)
        scroll.addSubview(colorView(CGRect(x: 0, y: 0, width: 402, height: 3000), red: 0, green: 0.6, blue: 0))
        page.view.addSubview(scroll)
        page.title = "Page"
        window.rootViewController = UINavigationController(rootViewController: page)
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        return scroll
    }

    // MARK: - S-SHOT-16 (P-DET-04)

    func test_S_SHOT_16_emptyDestInLayerDoesNotEraseTheGroup() throws {
        let window = try makeWindow()
        let direct = makeContainer(in: window)
        direct.layer.addSublayer(eraser())
        assertPixel(try drawnGroup(direct.layer, in: window).pixel(atPoint: 50, 50), white)

        let nested = makeContainer(in: window)
        let wrapper = CALayer()
        wrapper.frame = nested.bounds
        wrapper.addSublayer(eraser())
        nested.layer.addSublayer(wrapper)
        assertPixel(try drawnGroup(nested.layer, in: window).pixel(atPoint: 150, 50), white)
    }

    func test_S_SHOT_16_scrollEdgeEffectDoesNotEraseTheDrawnGroup() throws {
        guard #available(iOS 26, *) else { return }
        let window = try makeWindow()
        let scroll = makeScrollEdgePage(in: window)
        let image = try drawnGroup(window.layer, in: window)
        XCTAssertGreaterThan(image.pixel(atPoint: 200, 500)[3], 0)
        XCTAssertGreaterThan(try drawnGroup(scroll.layer, in: window).pixel(atPoint: 200, 500)[3], 0)
    }

    func test_S_SHOT_16_destInWithContentStillMasks() throws {
        let window = try makeWindow()
        let filled = makeContainer(in: window)
        let colored = eraser()
        colored.backgroundColor = UIColor.black.cgColor
        filled.layer.addSublayer(colored)
        let image = try drawnGroup(filled.layer, in: window)
        assertPixel(image.pixel(atPoint: 50, 50), white)
        assertPixel(image.pixel(atPoint: 150, 50), clear)

        let shaped = makeContainer(in: window)
        let shape = CAShapeLayer()
        shape.frame = shaped.bounds
        shape.path = CGPath(rect: CGRect(x: 0, y: 0, width: 100, height: 100), transform: nil)
        shape.compositingFilter = "destIn"
        shaped.layer.addSublayer(shape)
        let masked = try drawnGroup(shaped.layer, in: window)
        assertPixel(masked.pixel(atPoint: 50, 50), white)
        assertPixel(masked.pixel(atPoint: 150, 50), clear)
    }

    /// One the app hid since the scan stays hidden, and the others come back.
    func test_S_SHOT_16_hiddenStateIsRestored() throws {
        let window = try makeWindow()
        let container = makeContainer(in: window)
        let visible = eraser()
        let hiddenLater = eraser()
        container.layer.addSublayer(visible)
        container.layer.addSublayer(hiddenLater)
        let memo = RequestMemo()
        _ = try drawnGroup(container.layer, in: window, memo: memo)
        XCTAssertFalse(visible.isHidden)
        XCTAssertFalse(hiddenLater.isHidden)

        hiddenLater.isHidden = true
        _ = try drawnGroup(container.layer, in: window, memo: memo)
        XCTAssertFalse(visible.isHidden)
        XCTAssertTrue(hiddenLater.isHidden)
    }

    /// The scan is made once: a layer added after it is not found within the request.
    func test_S_SHOT_16_scansOncePerRequest() throws {
        let window = try makeWindow()
        let container = makeContainer(in: window)
        // A leaf has nothing to look for, and would not make the scan.
        container.addSubview(colorView(CGRect(x: 150, y: 0, width: 10, height: 10), red: 1, green: 0, blue: 0))
        let memo = RequestMemo()
        assertPixel(try drawnGroup(container.layer, in: window, memo: memo).pixel(atPoint: 50, 50), white)

        container.layer.addSublayer(eraser())
        assertPixel(try drawnGroup(container.layer, in: window, memo: memo).pixel(atPoint: 50, 50), clear)
        assertPixel(try drawnGroup(container.layer, in: window).pixel(atPoint: 50, 50), white)
    }

    // MARK: - S-SHOT-17 (P-IMG-07)

    func test_S_SHOT_17_windowGroupIsComposited() throws {
        let window = try makeWindow()
        let container = makeContainer(in: window)
        container.addSubview(colorView(CGRect(x: 10, y: 10, width: 50, height: 50), red: 1, green: 0, blue: 0))
        settle()
        let image = try group(window.layer, in: window)
        XCTAssertTrue(image.isComposited)
        XCTAssertEqual([image.pixelWidth, image.pixelHeight], [320, 480])
        assertPixel(image.pixel(atPoint: 30, 30), red)
        assertPixel(image.pixel(atPoint: 100, 50), white)
    }

    func test_S_SHOT_17_scrollEdgeEffectStaysInTheCompositedWindow() throws {
        guard #available(iOS 26, *) else { return }
        let window = try makeWindow()
        _ = makeScrollEdgePage(in: window)
        let image = try group(window.layer, in: window)
        XCTAssertTrue(image.isComposited)
        XCTAssertGreaterThan(image.pixel(atPoint: 200, 500)[3], 0)
    }

    /// Only where drawing would leave something out, and never on a solo or a leaf.
    func test_S_SHOT_17_otherGroupsAreCompositedOnlyWithAnEffect() throws {
        let window = try makeWindow()
        let plain = makeContainer(in: window)
        plain.addSubview(colorView(CGRect(x: 10, y: 10, width: 50, height: 50), red: 1, green: 0, blue: 0))
        let leaf = colorView(CGRect(x: 0, y: 200, width: 50, height: 50), red: 1, green: 0, blue: 0)
        window.addSubview(leaf)
        let effect = colorView(CGRect(x: 0, y: 300, width: 100, height: 100), red: 0, green: 0, blue: 1)
        addBlur(to: effect)
        window.addSubview(effect)
        settle()
        XCTAssertFalse(try group(plain.layer, in: window).isComposited)
        XCTAssertFalse(try group(leaf.layer, in: window).isComposited)
        let detail = try capture(effect.layer, in: window, solo: true)
        XCTAssertTrue(try XCTUnwrap(detail.group).isComposited)
        XCTAssertFalse(try XCTUnwrap(detail.solo).isComposited)
    }

    /// P-DET-07: the image shows the view opaque and visible; a composited one cannot.
    func test_S_SHOT_17_translucentOrHiddenViewIsDrawn() throws {
        let window = try makeWindow()
        let view = colorView(CGRect(x: 0, y: 0, width: 100, height: 100), red: 1, green: 0, blue: 0)
        addBlur(to: view)
        view.alpha = 0.5
        window.addSubview(view)
        settle()
        var image = try group(view.layer, in: window)
        XCTAssertFalse(image.isComposited)
        assertPixel(image.pixel(atPoint: 50, 50), red)

        view.alpha = 1
        view.isHidden = true
        settle()
        image = try group(view.layer, in: window)
        XCTAssertFalse(image.isComposited)
        assertPixel(image.pixel(atPoint: 50, 50), red)
    }

    func test_S_SHOT_17_windowsNotShownAreDrawn() throws {
        let hidden = try makeWindow(hidden: true)
        _ = makeContainer(in: hidden)
        XCTAssertFalse(try group(hidden.layer, in: hidden).isComposited)

        // `drawHierarchy` has nothing for it, and says so.
        let detached = makeDetachedWindow()
        detached.isHidden = false
        let container = makeContainer(in: detached)
        let image = try group(detached.layer, in: detached)
        XCTAssertFalse(image.isComposited)
        assertPixel(image.pixel(atPoint: 50, 50), white)
        XCTAssertNotNil(container.superview)
    }

    /// P-DET-10: a composited image cannot leave an excluded layer out, not even where it lies
    /// outside the subtree: the whole request is drawn.
    func test_S_SHOT_17_visibleExcludedLayerIsNeverComposited() throws {
        let window = try makeWindow()
        let container = makeContainer(in: window)
        let secret = SecretView(frame: CGRect(x: 10, y: 10, width: 50, height: 50))
        secret.backgroundColor = .red
        container.addSubview(secret)
        let effect = colorView(CGRect(x: 0, y: 300, width: 100, height: 100), red: 0, green: 0, blue: 1)
        addBlur(to: effect)
        window.addSubview(effect)
        settle()
        let store = ExtensionStore()
        store.describe(SecretView.self, CutawayServer.Description(isExcludedFromCapture: true), isView: true)

        let image = try group(window.layer, in: window, store: store)
        XCTAssertFalse(image.isComposited)
        assertPixel(image.pixel(atPoint: 30, 30), white)
        XCTAssertFalse(secret.isHidden)
        XCTAssertFalse(try group(effect.layer, in: window, store: store).isComposited)

        secret.isHidden = true
        settle()
        XCTAssertTrue(try group(window.layer, in: window, store: store).isComposited)
    }

    /// What the app changed in this turn of the run loop is in the image.
    func test_S_SHOT_17_uncommittedChangesAreInTheImage() throws {
        let window = try makeWindow()
        let container = makeContainer(in: window)
        settle()
        container.backgroundColor = .blue
        assertPixel(try group(window.layer, in: window).pixel(atPoint: 50, 50), blue)
    }

    /// Liquid Glass casts its shadow past the view: cut off at the bounds, it would be a grey
    /// rectangle behind the capsule. The capsule stays.
    func test_S_SHOT_17_shadowCutAtTheBoundsIsNotInTheImage() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Liquid Glass is iOS 26") }
        let window = try makeWindow()
        let root = UIViewController()
        root.view.backgroundColor = .white
        window.rootViewController = root
        let host = UIHostingController(rootView: GlassCapsule())
        host.view.backgroundColor = .clear
        host.view.frame = root.view.bounds
        root.addChild(host)
        root.view.addSubview(host.view)
        try await Task.sleep(nanoseconds: 500_000_000)

        var stack = [host.view.layer]
        var glass: CALayer?
        while let next = stack.popLast(), glass == nil {
            if next !== host.view.layer, next.delegate is UIView, !(next.bounds.isEmpty) { glass = next }
            stack += next.sublayers ?? []
        }
        let view = try XCTUnwrap(glass?.delegate as? UIView)
        var image = try XCTUnwrap(capture(view.layer, in: window).group)
        XCTAssertTrue(image.isComposited)
        XCTAssertNotEqual(image.pixel(x: 1, y: 1), clear)

        image.clearShadowRemnants()

        XCTAssertEqual(image.pixel(x: 1, y: 1), clear)
        XCTAssertEqual(image.pixel(x: image.pixelWidth / 2, y: image.pixelHeight / 2)[3], 255)
    }

    /// Only what looks like that shadow goes.
    func test_S_SHOT_17_onlyFaintBlackIsCleared() throws {
        let kept: [[UInt8]] = [[0, 0, 0, 32], [0, 0, 0, 255], [1, 0, 0, 10], [0, 0, 1, 10], [0, 1, 0, 1]]
        let cleared: [[UInt8]] = [[0, 0, 0, 1], [0, 0, 0, 10], [0, 0, 0, 31]]
        let bytes = (kept + cleared).flatMap { $0 }
        var image = RawImage(
            pixelWidth: bytes.count / 4,
            pixelHeight: 1,
            bytesPerRow: bytes.count,
            scale: 1,
            pixels: Data(bytes),
            mayHaveCutOffShadow: true
        )
        let untouched = image

        var other = image
        other.mayHaveCutOffShadow = false
        other.clearShadowRemnants()
        XCTAssertEqual(other.pixels, untouched.pixels)

        // It goes before the digest, which is that of the image sent.
        let detail = CapturedDetail(layerID: 3, status: .ok, solo: nil, group: image, attributeGroups: [])
        let request = LayerDetailRequest(layerID: 3, wantSolo: false, wantGroup: true, wantAttributes: false)
        let digests = try XCTUnwrap(KnownDigests(request, version: ProtocolVersion(major: 1, minor: 3)))
        let sent = detail.compressed(digests: digests).group
        image.clearShadowRemnants()

        XCTAssertEqual(image.pixels, Data(kept.flatMap { $0 } + cleared.flatMap { _ in clear }))
        XCTAssertEqual(sent?.digest, ImageDigest.of(image))
        XCTAssertNotEqual(sent?.digest, ImageDigest.of(untouched))
    }

    /// A window keeps it: its image is not cut off from anything.
    func test_S_SHOT_17_windowKeepsFaintBlack() throws {
        let window = try makeWindow()
        let view = UIView(frame: window.bounds)
        window.addSubview(view)
        let plan = try XCTUnwrap(ImageSizing.plan(bounds: window.bounds, screenScale: 1, maxTextureDimension: 0))
        CATransaction.flush()

        XCTAssertFalse(try XCTUnwrap(LayerRenderer.composited(window, plan: plan)).mayHaveCutOffShadow)
        XCTAssertTrue(try XCTUnwrap(LayerRenderer.composited(view, plan: plan)).mayHaveCutOffShadow)
    }

    /// P-IMG-04, 05, 07: the flag goes with a full image of a client of 1.3, is in the digest,
    /// and not on an unchanged image; a client of 1.2 does not get it.
    func test_S_SHOT_17_flagOnTheWire() throws {
        let plain = RawImage(
            pixelWidth: 2,
            pixelHeight: 1,
            bytesPerRow: 8,
            scale: 1,
            pixels: Data(repeating: 9, count: 8)
        )
        var composited = plain
        composited.isComposited = true
        XCTAssertNotEqual(ImageDigest.of(plain), ImageDigest.of(composited))

        let detail = CapturedDetail(layerID: 3, status: .ok, solo: nil, group: composited, attributeGroups: [])
        let request = LayerDetailRequest(layerID: 3, wantSolo: false, wantGroup: true, wantAttributes: false)
        let digests = try XCTUnwrap(KnownDigests(request, version: ProtocolVersion(major: 1, minor: 3)))
        XCTAssertEqual(detail.compressed(digests: digests).group?.isComposited, true)
        XCTAssertEqual(detail.compressed(digests: nil).group?.isComposited, false)

        let held = LayerDetailRequest(
            layerID: 3,
            wantSolo: false,
            wantGroup: true,
            wantAttributes: false,
            knownGroupDigest: ImageDigest.of(composited)
        )
        let again = try XCTUnwrap(KnownDigests(held, version: ProtocolVersion(major: 1, minor: 3)))
        XCTAssertEqual(detail.compressed(digests: again).group, .unchanged(digest: ImageDigest.of(composited)))
    }
}
