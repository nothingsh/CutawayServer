import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Counts how often it is rendered, and tells the test when.
private final class SpyLayer: CALayer {
    var renderCount = 0
    var onRender: (() -> Void)?

    override func render(in context: CGContext) {
        renderCount += 1
        onRender?()
        super.render(in: context)
    }
}

/// Answering one `LayerDetailRequest`. No server, no connection.
final class DetailCaptureTests: CaptureTestCase {
    private let registry = LayerRegistry()
    private let red = pixelBytes(red: 1, green: 0, blue: 0)

    /// Captures at 2 pixels per point, without attributes unless a reader is given. The
    /// layer exists only in `windows`, by default the app's (P-HIER-12).
    private func capture(
        _ layerID: UInt64,
        solo: Bool = false,
        group: Bool = false,
        attributes: Bool = false,
        constraints: Bool = false,
        max: UInt32 = 0,
        windows: [UIWindow] = HostWindows.all(),
        stopFlag: StopFlag = StopFlag(),
        readAttributes: (CALayer) -> [AttributeGroup] = { _ in [] }
    ) -> CapturedDetail? {
        DetailCapture.capture(
            LayerDetailRequest(
                layerID: layerID,
                wantSolo: solo,
                wantGroup: group,
                wantAttributes: attributes,
                wantConstraints: constraints
            ),
            maxTextureDimension: max,
            in: .testing(windows: windows, registry: registry),
            stopFlag: stopFlag,
            screenScale: 2,
            readAttributes: readAttributes
        )
    }

    /// A red 40 x 30 view in a window, and its layer's ID.
    private func redView() throws -> (view: UIView, id: UInt64) {
        let window = try makeWindow()
        let view = colorView(CGRect(x: 0, y: 0, width: 40, height: 30), red: 1, green: 0, blue: 0)
        window.addSubview(view)
        return (view, registry.register(view.layer))
    }

    /// The groups the `layer-details-edge` fixture gives its layer 9.
    private func fixtureDetailOfLayer9() throws -> LayerDetail {
        guard
            case .layerDetailsChunk(let chunk)? = try Fixtures.frame(
                "layer-details-edge/02-s2c-chunk-0.bin"
            ).body
        else { throw TestClientError(description: "the fixture is not a chunk") }
        return try XCTUnwrap(chunk.details.first { $0.layerID == 9 })
    }

    // MARK: - S-STAB-01

    func test_S_STAB_01_anInjectedRendererMakesBothImages() throws {
        let window = try makeWindow()
        let view = colorView(CGRect(x: 0, y: 0, width: 40, height: 30), red: 1, green: 0, blue: 0)
        view.layer.addSublayer(CALayer())
        window.addSubview(view)
        let id = registry.register(view.layer)

        var rendered: [(CALayer, LayerRenderer.Mode)] = []
        let detail = try XCTUnwrap(
            DetailCapture.capture(
                LayerDetailRequest(
                    layerID: id,
                    wantSolo: true,
                    wantGroup: true,
                    wantAttributes: false,
                    wantConstraints: false
                ),
                maxTextureDimension: 0,
                in: .testing(windows: HostWindows.all(), registry: registry),
                stopFlag: StopFlag(),
                screenScale: 2,
                readAttributes: { _ in [] },
                render: { layer, mode, plan in
                    rendered.append((layer, mode))
                    return LayerRenderer.render(layer, mode: mode, plan: plan)
                }
            )
        )

        XCTAssertEqual(rendered.map { $0.0 }, [view.layer, view.layer])
        XCTAssertEqual(rendered.map { $0.1 }, [.solo, .group])
        XCTAssertEqual(detail.status, .ok)
        assertPixel(try XCTUnwrap(detail.solo).pixel(atPoint: 20, 15), red)
        assertPixel(try XCTUnwrap(detail.group).pixel(atPoint: 20, 15), red)
    }

    // MARK: - S-SHOT-02 (P-DET-04)

    func test_S_SHOT_02_soloIsOmittedForALayerWithoutSublayers() throws {
        let (view, id) = try redView()

        // Both wanted, no sublayers: the group alone stands for both.
        let both = try XCTUnwrap(capture(id, solo: true, group: true))
        XCTAssertEqual(both.status, .ok)
        XCTAssertNil(both.solo)
        assertPixel(try XCTUnwrap(both.group).pixel(atPoint: 20, 15), red)

        // Only the solo wanted: it is given.
        let onlySolo = try XCTUnwrap(capture(id, solo: true))
        XCTAssertEqual(onlySolo.status, .ok)
        XCTAssertNil(onlySolo.group)
        assertPixel(try XCTUnwrap(onlySolo.solo).pixel(atPoint: 20, 15), red)

        // With a sublayer, both are given and they differ where the sublayer is.
        view.addSubview(colorView(CGRect(x: 10, y: 10, width: 10, height: 10), red: 0, green: 0, blue: 1))
        let withChild = try XCTUnwrap(capture(id, solo: true, group: true))
        XCTAssertEqual(withChild.status, .ok)
        assertPixel(try XCTUnwrap(withChild.solo).pixel(atPoint: 15, 15), red)
        assertPixel(try XCTUnwrap(withChild.group).pixel(atPoint: 15, 15), pixelBytes(red: 0, green: 0, blue: 1))
        XCTAssertEqual(withChild.pixelByteCount, 2 * 80 * 60 * 4)

        // Only the group wanted: no solo, sublayers or not.
        let onlyGroup = try XCTUnwrap(capture(id, group: true))
        XCTAssertNil(onlyGroup.solo)
        XCTAssertNotNil(onlyGroup.group)
        XCTAssertEqual(onlyGroup.pixelByteCount, 80 * 60 * 4)
    }

    // MARK: - S-SHOT-03

    func test_S_SHOT_03_theRequestsLimitReachesTheImages() throws {
        let (view, id) = try redView()
        view.addSubview(UIView())
        let limited = try XCTUnwrap(capture(id, solo: true, group: true, max: 20))
        for image in [try XCTUnwrap(limited.solo), try XCTUnwrap(limited.group)] {
            XCTAssertEqual([image.pixelWidth, image.pixelHeight], [20, 15])
            XCTAssertEqual(image.scale, 0.5)
            assertPixel(image.pixel(atPoint: 39, 29), red)
        }
    }

    // MARK: - S-SHOT-04

    func test_S_SHOT_04_impossibleSizesFailWithoutCrashing() throws {
        let window = try makeWindow()
        let empty = UIView(frame: CGRect(x: 300, y: 700, width: 0, height: 0))
        let flat = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 0))
        window.addSubview(empty)
        window.addSubview(flat)
        // Values that should not reach the render server stay off screen.
        let detached = makeDetachedWindow()
        let endless = CALayer()
        endless.bounds = CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)
        let nowhere = CALayer()
        nowhere.bounds = CGRect(x: CGFloat.infinity, y: 0, width: 10, height: 10)
        detached.layer.addSublayer(endless)
        detached.layer.addSublayer(nowhere)
        XCTAssertFalse(endless.bounds.width.isFinite)
        XCTAssertFalse(nowhere.bounds.origin.x.isFinite)

        for layer in [empty.layer, flat.layer, endless, nowhere] {
            let id = registry.register(layer)
            for (solo, group) in [(true, false), (false, true), (true, true)] {
                let detail = try XCTUnwrap(
                    capture(id, solo: solo, group: group, windows: HostWindows.all() + [detached])
                )
                XCTAssertEqual(
                    detail,
                    CapturedDetail(
                        layerID: id,
                        status: .captureFailed,
                        solo: nil,
                        group: nil,
                        attributeGroups: []
                    ),
                    "\(layer.bounds)"
                )
            }
        }
    }

    func test_S_SHOT_04_attributesSurviveAFailedCapture() throws {
        let window = try makeWindow()
        let empty = UIView(frame: CGRect(x: 300, y: 700, width: 0, height: 0))
        window.addSubview(empty)
        let id = registry.register(empty.layer)
        let fixture = try fixtureDetailOfLayer9()
        XCTAssertEqual(fixture.attributeGroups.flatMap(\.attributes).count, 2)

        var asked: [CALayer] = []
        let captured = try XCTUnwrap(
            capture(id, group: true, attributes: true) { layer in
                asked.append(layer)
                return fixture.attributeGroups
            }
        )
        XCTAssertTrue(asked.count == 1 && asked[0] === empty.layer)

        // On the wire it is the fixture's detail, but for the layer's ID.
        var expected = fixture
        expected.layerID = id
        XCTAssertEqual(captured.compressed(), expected)
        XCTAssertEqual(expected.status, .captureFailed)
        XCTAssertNil(expected.group)

        // Attributes that were not asked for are not read.
        let without = try XCTUnwrap(
            capture(id, group: true) { _ in
                XCTFail("attributes were read although the request did not want them")
                return fixture.attributeGroups
            }
        )
        XCTAssertEqual(without.compressed(), LayerDetail(layerID: id, status: .captureFailed))
    }

    func test_S_SHOT_04_nothingWantedIsAnswered() throws {
        let (view, id) = try redView()
        let nothing = try XCTUnwrap(capture(id))
        XCTAssertEqual(nothing.compressed(), LayerDetail(layerID: id, status: .ok))
        XCTAssertEqual(nothing.pixelByteCount, 0)

        // Attributes alone: no image is made, even of a layer that could not be captured.
        let groups = try fixtureDetailOfLayer9().attributeGroups
        let onlyAttributes = try XCTUnwrap(capture(id, attributes: true) { _ in groups })
        XCTAssertEqual(
            onlyAttributes.compressed(),
            LayerDetail(layerID: id, status: .ok, attributeGroups: groups)
        )
        let empty = UIView()
        view.window?.addSubview(empty)
        let emptyID = registry.register(empty.layer)
        XCTAssertEqual(capture(emptyID, attributes: true) { _ in groups }?.status, .ok)
    }

    // MARK: - S-ATTR-01

    /// Captures with the default configuration's host app, each request with a context of its
    /// own, as a session's would be.
    private func defaultCapture() -> @MainActor (LayerDetailRequest) -> CapturedDetail? {
        let app = ServerConfiguration().hostApp
        let registry = self.registry
        return { request in
            app.captureDetail(
                request,
                maxTextureDimension: 0,
                in: app.makeRequestContext(registry: registry, version: .current),
                stopFlag: StopFlag()
            )
        }
    }

    func test_S_ATTR_01_theDefaultConfigurationReadsAttributes() throws {
        let window = try makeWindow()
        let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        label.text = "Attributes"
        window.addSubview(label)
        let id = registry.register(label.layer)
        let capture = defaultCapture()

        let wanted = try XCTUnwrap(
            capture(LayerDetailRequest(layerID: id, wantSolo: false, wantGroup: false, wantAttributes: true))
        )
        XCTAssertEqual(wanted.attributeGroups.map(\.id), ["layer", "view", "label"])
        XCTAssertEqual(wanted.attributeGroups, AttributeCatalog.standard.read(label.layer))

        let unwanted = try XCTUnwrap(
            capture(LayerDetailRequest(layerID: id, wantSolo: false, wantGroup: false, wantAttributes: false))
        )
        XCTAssertEqual(unwanted.attributeGroups, [])
    }

    // MARK: - S-SHOT-05

    func test_S_SHOT_05_encodedDetailsCarryTheCompressedImages() throws {
        let (view, id) = try redView()
        view.addSubview(colorView(CGRect(x: 0, y: 0, width: 10, height: 10), red: 0, green: 0, blue: 1))
        let captured = try XCTUnwrap(capture(id, solo: true, group: true))
        let encoded = captured.compressed()

        XCTAssertEqual(encoded.layerID, id)
        XCTAssertEqual(encoded.status, .ok)
        for (wire, raw) in [(encoded.solo, captured.solo), (encoded.group, captured.group)] {
            let wire = try XCTUnwrap(wire)
            let raw = try XCTUnwrap(raw)
            XCTAssertEqual([wire.pixelWidth, wire.pixelHeight, wire.bytesPerRow], [80, 60, 320])
            XCTAssertEqual(wire.scale, 2)
            XCTAssertEqual(try (wire.data as NSData).decompressed(using: .lzfse) as Data, raw.pixels)
        }
        XCTAssertNotEqual(encoded.solo, encoded.group)

        // The frame it travels in passes the verifier.
        let frame = Frame(
            requestID: 3,
            body: .layerDetailsChunk(LayerDetailsChunk(sequence: 0, details: [encoded]))
        )
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)

        // An image that cannot be compressed fails the capture and keeps the attributes.
        var broken = captured
        broken.group?.pixels.removeLast()
        broken.attributeGroups = try fixtureDetailOfLayer9().attributeGroups
        XCTAssertEqual(
            broken.compressed(),
            LayerDetail(layerID: id, status: .captureFailed, attributeGroups: broken.attributeGroups)
        )
    }

    // MARK: - S-SHOT-07

    func test_S_SHOT_07_aSetStopFlagPreventsTheCapture() throws {
        let window = try makeWindow()
        let spy = SpyLayer()
        spy.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        spy.addSublayer(CALayer())
        window.layer.addSublayer(spy)
        let id = registry.register(spy)

        let stopped = StopFlag()
        XCTAssertFalse(stopped.isSet)
        stopped.set()
        XCTAssertTrue(stopped.isSet)
        XCTAssertNil(capture(id, solo: true, group: true, stopFlag: stopped))
        XCTAssertEqual(spy.renderCount, 0, "a layer was rendered for a stream that was stopped")
        // The flag is looked at before the registry: a stopped stream gets nothing at all.
        XCTAssertNil(capture(9999, group: true, stopFlag: stopped))

        // Without the flag both images are rendered.
        XCTAssertNotNil(capture(id, solo: true, group: true))
        XCTAssertEqual(spy.renderCount, 2)
    }

    func test_S_SHOT_07_aFlagSetBetweenTheTwoImagesStopsTheCapture() throws {
        let window = try makeWindow()
        let spy = SpyLayer()
        spy.frame = CGRect(x: 0, y: 0, width: 10, height: 10)
        let child = CALayer()
        spy.addSublayer(child)
        window.layer.addSublayer(spy)
        let id = registry.register(spy)

        // The cancel arrives while the solo image is being rendered.
        let flag = StopFlag()
        spy.onRender = { flag.set() }
        XCTAssertNil(capture(id, solo: true, group: true, stopFlag: flag))
        XCTAssertEqual(spy.renderCount, 1, "the group image was rendered after the stream was stopped")
        XCTAssertFalse(child.isHidden)
    }

    // MARK: - S-SHOT-08

    func test_S_SHOT_08_unknownAndReleasedLayersAreNotFound() throws {
        let window = try makeWindow()
        var releasedID: UInt64 = 0
        autoreleasepool {
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
            window.addSubview(view)
            releasedID = registry.register(view.layer)
            XCTAssertEqual(capture(releasedID, group: true)?.status, .ok)
            view.removeFromSuperview()
        }
        // Core Animation's open transaction holds on to removed layers until it is committed.
        CATransaction.flush()
        XCTAssertNil(registry.layer(for: releasedID))

        for id in [releasedID, 0, 12345, .max] {
            let detail = capture(id, solo: true, group: true, attributes: true) { _ in
                XCTFail("attributes were read for a layer that does not exist")
                return []
            }
            XCTAssertEqual(
                detail,
                CapturedDetail(
                    layerID: id,
                    status: .layerNotFound,
                    solo: nil,
                    group: nil,
                    attributeGroups: []
                )
            )
            XCTAssertEqual(
                detail.map { $0.compressed() },
                LayerDetail(layerID: id, status: .layerNotFound)
            )
        }
    }

    func test_S_SHOT_08_captureDoesNotExtendLifetimes() throws {
        let window = try makeWindow()
        weak var view: UIView?
        weak var backingLayer: CALayer?
        weak var sublayer: CALayer?
        var detail: CapturedDetail?
        autoreleasepool {
            let strongView = colorView(CGRect(x: 0, y: 0, width: 20, height: 20), red: 1, green: 0, blue: 0)
            let strongSublayer = CALayer()
            strongView.layer.addSublayer(strongSublayer)
            window.addSubview(strongView)
            view = strongView
            backingLayer = strongView.layer
            sublayer = strongSublayer
            detail = capture(registry.register(strongView.layer), solo: true, group: true, attributes: true)
            strongView.removeFromSuperview()
        }
        // Core Animation's open transaction holds on to removed layers until it is committed.
        CATransaction.flush()
        // The captured detail is still held here, and so is the registry.
        XCTAssertEqual(detail?.status, .ok)
        XCTAssertNotNil(detail?.solo)
        XCTAssertNil(view, "the capture kept the view alive")
        XCTAssertNil(backingLayer, "the capture kept the view's layer alive")
        XCTAssertNil(sublayer, "the capture kept the sublayer alive")
    }

    // MARK: - S-SHOT-11 (P-HIER-12)

    func test_S_SHOT_11_layersOutsideEveryWindowAreNotFound() throws {
        let window = try makeWindow()
        let parent = colorView(CGRect(x: 0, y: 0, width: 40, height: 30), red: 1, green: 0, blue: 0)
        let child = colorView(CGRect(x: 0, y: 0, width: 10, height: 10), red: 0, green: 1, blue: 0)
        parent.addSubview(child)
        window.addSubview(parent)
        let bare = CALayer()
        bare.bounds = CGRect(x: 0, y: 0, width: 10, height: 10)
        window.layer.addSublayer(bare)
        let ids = [parent.layer, child.layer, bare].map(registry.register)
        for id in ids {
            XCTAssertEqual(capture(id, group: true)?.status, .ok)
        }

        // Still alive, held here, but in no window: the view with its child, and a bare layer.
        parent.removeFromSuperview()
        bare.removeFromSuperlayer()
        for id in ids {
            let detail = capture(id, solo: true, group: true, attributes: true, constraints: true) { _ in
                XCTFail("attributes were read for a layer that is in no window")
                return []
            }
            XCTAssertEqual(
                detail,
                CapturedDetail(
                    layerID: id,
                    status: .layerNotFound,
                    solo: nil,
                    group: nil,
                    attributeGroups: []
                )
            )
            XCTAssertEqual(
                detail.map { $0.compressed() },
                LayerDetail(layerID: id, status: .layerNotFound)
            )
        }
        XCTAssertNotNil(registry.layer(for: ids[0]), "the layer is alive; only its window is gone")
    }

    func test_S_SHOT_11_aWindowThatIsNotTheAppsDoesNotCount() throws {
        // A window outside the list the server is given, such as one of no scene.
        let detached = makeDetachedWindow()
        let view = colorView(CGRect(x: 0, y: 0, width: 10, height: 10), red: 1, green: 0, blue: 0)
        detached.addSubview(view)
        let id = registry.register(view.layer)
        XCTAssertEqual(capture(id, group: true)?.status, .layerNotFound)
        XCTAssertEqual(capture(id, group: true, windows: [detached])?.status, .ok)
    }

    func test_S_SHOT_11_layerPutBackIsFoundAgain() throws {
        let (view, id) = try redView()
        let window = try XCTUnwrap(view.window)
        view.removeFromSuperview()
        XCTAssertEqual(capture(id, group: true)?.status, .layerNotFound)
        window.addSubview(view)
        let detail = try XCTUnwrap(capture(id, group: true))
        XCTAssertEqual(detail.status, .ok)
        XCTAssertNotNil(detail.group)
        XCTAssertEqual(registry.register(view.layer), id, "the layer kept its ID")
    }

    func test_S_SHOT_11_theDefaultConfigurationLooksAtTheAppsWindows() throws {
        let (view, id) = try redView()
        let capture = defaultCapture()
        let request = LayerDetailRequest(layerID: id, wantSolo: false, wantGroup: false, wantAttributes: true)
        XCTAssertEqual(capture(request)?.status, .ok)
        view.removeFromSuperview()
        XCTAssertEqual(capture(request)?.status, .layerNotFound)
    }
}
