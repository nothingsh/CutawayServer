import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// A window of the test's own. Touched on the main thread only.
@MainActor
private final class WindowBox {
    var window: UIWindow?
    var view: UIView?

    nonisolated init() {}
}

/// `GetLayerDetails` and `Cancel` over a connection. The session's logic is
/// tested without one (SessionStreamTests); these tests cover what only a real connection
/// shows: the fixtures' bytes going in, and large frames coming out whole.
final class LayerDetailsRequestTests: ServerTestCase {
    /// What a stream sent, read to its `StreamEnd`. Events in between are kept apart.
    private struct ReadStream {
        var chunks: [LayerDetailsChunk] = []
        var end = StreamEnd(status: .failed, chunkCount: .max)
        /// The events, each with the number of chunks that had arrived before it.
        var events: [(state: AppState, afterChunks: Int)] = []
        /// The size of the largest chunk frame, in bytes.
        var largestPayload = 0
    }

    /// - Parameter alreadyRead: How many chunks of the stream the test has read itself.
    private func readStream(
        _ client: TestClient,
        requestID: UInt32,
        alreadyRead: Int = 0,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> ReadStream {
        var stream = ReadStream()
        while true {
            guard let payload = try await client.nextPayload(timeout: 30) else {
                throw TestClientError(description: "the connection ended in the middle of stream \(requestID)")
            }
            let frame = try FrameCodec.decode(payload)
            switch frame.body {
            case .appStateChanged(let state):
                XCTAssertEqual(frame.requestID, 0, file: file, line: line)
                stream.events.append((state, stream.chunks.count))
            case .layerDetailsChunk(let chunk):
                XCTAssertEqual(frame.requestID, requestID, file: file, line: line)
                XCTAssertEqual(
                    chunk.sequence,
                    UInt32(alreadyRead + stream.chunks.count),
                    file: file,
                    line: line
                )
                stream.chunks.append(chunk)
                stream.largestPayload = max(stream.largestPayload, payload.count)
            case .streamEnd(let end):
                XCTAssertEqual(frame.requestID, requestID, file: file, line: line)
                stream.end = end
                return stream
            default:
                throw TestClientError(description: "unexpected frame in stream \(requestID): \(frame)")
            }
        }
    }

    /// A view that shows random pixels, two per point.
    @MainActor
    static func noiseView(frame: CGRect) -> UIView {
        let width = Int(frame.width) * 2
        let height = Int(frame.height) * 2
        var generator = SeededGenerator(seed: 7)
        let noise = generator.bytes(count: width * height * 4)
        let view = UIImageView(frame: frame)
        if let provider = CGDataProvider(data: noise as CFData),
           let image = CGImage(
               width: width,
               height: height,
               bitsPerComponent: 8,
               bitsPerPixel: 32,
               bytesPerRow: width * 4,
               space: CGColorSpace(name: CGColorSpace.sRGB)!,
               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
               provider: provider,
               decode: nil,
               shouldInterpolate: false,
               intent: .defaultIntent
           ) {
            view.image = UIImage(cgImage: image, scale: 2, orientation: .up)
        }
        return view
    }

    /// A server whose captures take a while, as those of a large screen do.
    private func makeSlowServer() -> TestServer {
        makeServer { configuration in
            var app = TestHostApp()
            let capture = app.captureDetail
            app.captureDetail = { request, limit, context, stopFlag in
                Thread.sleep(forTimeInterval: 0.02)
                return capture(request, limit, context, stopFlag)
            }
            configuration.hostApp = app
        }
    }

    /// A request for the group images of `count` layers that do not exist.
    private func manyLayers(_ count: Int) -> Message {
        .getLayerDetails(
            GetLayerDetails(
                requests: (0..<count).map {
                    LayerDetailRequest(
                        layerID: UInt64(1_000_000 + $0),
                        wantSolo: false,
                        wantGroup: true,
                        wantAttributes: false
                    )
                },
                maxTextureDimension: 0
            )
        )
    }

    func test_S_SHOT_06_getLayerDetailsStreamsTheLayers() async throws {
        // A window with noise: its screenshot does not compress, so its frame is megabytes.
        let box = WindowBox()
        try await MainActor.run {
            let scene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            window.addSubview(Self.noiseView(frame: window.bounds))
            window.isHidden = false
            box.window = window
        }
        addTeardownBlock {
            await MainActor.run {
                box.window?.isHidden = true
                box.window?.windowScene = nil
            }
        }

        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)
        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        guard case .hierarchy(let hierarchy)? = try await client.nextFrame()?.body else {
            return XCTFail("expected Hierarchy")
        }

        // Both images of every layer of the app.
        let wanted = GetLayerDetails(
            requests: hierarchy.nodes.map {
                LayerDetailRequest(layerID: $0.id, wantSolo: true, wantGroup: true, wantAttributes: false)
            },
            maxTextureDimension: 16384
        )
        try await client.send(Frame(requestID: 2, body: .getLayerDetails(wanted)))
        let stream = try await readStream(client, requestID: 2)

        // P-REQ-03, P-DET-01, P-DET-06: one detail per chunk, every layer once, in order.
        XCTAssertEqual(stream.end, StreamEnd(status: .completed, chunkCount: UInt32(hierarchy.nodes.count)))
        XCTAssertEqual(stream.chunks.map { $0.details.map(\.layerID) }, hierarchy.nodes.map { [$0.id] })
        XCTAssertTrue(stream.events.isEmpty)
        for (node, chunk) in zip(hierarchy.nodes, stream.chunks) {
            let detail = chunk.details[0]
            let size = node.bounds.size
            guard size.width > 0, size.height > 0 else {
                XCTAssertEqual(detail, LayerDetail(layerID: node.id, status: .captureFailed))
                continue
            }
            XCTAssertEqual(detail.status, .ok, "layer \(node.id), \(node.className)")
            XCTAssertTrue(detail.attributeGroups.isEmpty)
            for image in [detail.solo, detail.group].compactMap({ $0 }) {
                // P-DET-07, P-IMG-01: the bounds at the image's scale, and pixels of that size.
                // Within the pixel that rounding costs, plus the precision of a Float scale.
                XCTAssertEqual(
                    Double(image.pixelWidth),
                    size.width * Double(image.scale),
                    accuracy: 1 + Double(image.pixelWidth) * 1e-6
                )
                XCTAssertEqual(
                    Double(image.pixelHeight),
                    size.height * Double(image.scale),
                    accuracy: 1 + Double(image.pixelHeight) * 1e-6
                )
                let pixels = try (image.data as NSData).decompressed(using: .lzfse)
                XCTAssertEqual(pixels.length, Int(image.bytesPerRow) * Int(image.pixelHeight))
            }
            XCTAssertNotNil(detail.group)
        }
        // The noise arrived whole, in a frame of more than a megabyte.
        XCTAssertGreaterThan(stream.largestPayload, 1024 * 1024)

        // The connection is good for more.
        try await client.send(Frame(requestID: 3, body: .getAppIcon))
        let icon = try await client.nextFrame()
        XCTAssertEqual(icon?.requestID, 3)
    }

    func test_S_ATTR_01_attributesOverTheConnection() async throws {
        let box = WindowBox()
        try await MainActor.run {
            let scene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            let label = UILabel(frame: CGRect(x: 20, y: 40, width: 217, height: 23))
            label.text = "Attributes"
            window.addSubview(label)
            window.isHidden = false
            box.window = window
            box.view = label
        }
        addTeardownBlock {
            await MainActor.run {
                box.window?.isHidden = true
                box.window?.windowScene = nil
            }
        }

        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)
        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        guard case .hierarchy(let hierarchy)? = try await client.nextFrame()?.body else {
            return XCTFail("expected Hierarchy")
        }
        // The test's label, told apart by its unusual size.
        let node = try XCTUnwrap(
            hierarchy.nodes.first {
                $0.viewClassName == "UILabel" && $0.bounds.size == WireSize(width: 217, height: 23)
            }
        )

        let wanted = GetLayerDetails(
            requests: [
                LayerDetailRequest(layerID: node.id, wantSolo: false, wantGroup: false, wantAttributes: true)
            ],
            maxTextureDimension: 0
        )
        try await client.send(Frame(requestID: 2, body: .getLayerDetails(wanted)))
        let stream = try await readStream(client, requestID: 2)

        XCTAssertEqual(stream.end, StreamEnd(status: .completed, chunkCount: 1))
        let expected = await MainActor.run { AttributeCatalog.standard.read(box.view!.layer) }
        XCTAssertEqual(expected.map(\.id), ["layer", "view", "label"])
        XCTAssertEqual(
            stream.chunks.map(\.details),
            [[LayerDetail(layerID: node.id, status: .ok, attributeGroups: expected)]]
        )
    }

    func test_S_SHOT_11_aLayerOutOfItsWindowIsNotFoundOverTheConnection() async throws {
        let box = WindowBox()
        try await MainActor.run {
            let scene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            let view = UIView(frame: CGRect(x: 20, y: 40, width: 219, height: 21))
            view.backgroundColor = .red
            window.addSubview(view)
            window.isHidden = false
            box.window = window
            box.view = view
        }
        addTeardownBlock {
            await MainActor.run {
                box.window?.isHidden = true
                box.window?.windowScene = nil
            }
        }

        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)
        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        guard case .hierarchy(let hierarchy)? = try await client.nextFrame()?.body else {
            return XCTFail("expected Hierarchy")
        }
        // The test's view, told apart by its unusual size.
        let node = try XCTUnwrap(
            hierarchy.nodes.first {
                $0.viewClassName == "UIView" && $0.bounds.size == WireSize(width: 219, height: 21)
            }
        )
        // Still alive, held by the box, but in no window (P-HIER-12).
        await MainActor.run { box.view?.removeFromSuperview() }

        let wanted = GetLayerDetails(
            requests: [
                LayerDetailRequest(
                    layerID: node.id,
                    wantSolo: true,
                    wantGroup: true,
                    wantAttributes: true,
                    wantConstraints: true
                ),
                LayerDetailRequest(layerID: node.parentID, wantSolo: false, wantGroup: false, wantAttributes: true)
            ],
            maxTextureDimension: 0
        )
        try await client.send(Frame(requestID: 2, body: .getLayerDetails(wanted)))
        let stream = try await readStream(client, requestID: 2)

        XCTAssertEqual(stream.end.status, .completed)
        let details = stream.chunks.flatMap(\.details)
        XCTAssertEqual(details.map(\.layerID), [node.id, node.parentID])
        XCTAssertEqual(details.first, LayerDetail(layerID: node.id, status: .layerNotFound))
        XCTAssertEqual(details.last?.status, .ok)
        XCTAssertFalse(details.last?.attributeGroups.isEmpty ?? true)
    }

    func test_S_LAYOUT_01_constraintsOverTheConnection() async throws {
        let box = WindowBox()
        let expected: [(constant: Double, className: String)] = try await MainActor.run {
            let scene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            let view = UIView()
            view.translatesAutoresizingMaskIntoConstraints = false
            window.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: window.leadingAnchor, constant: 13),
                view.topAnchor.constraint(equalTo: window.topAnchor, constant: 17),
                view.widthAnchor.constraint(equalToConstant: 223),
                view.heightAnchor.constraint(equalToConstant: 19)
            ])
            window.isHidden = false
            window.layoutIfNeeded()
            box.window = window
            box.view = view
            return [
                (13, "NSLayoutConstraint"),
                (17, "NSLayoutConstraint"),
                (223, "NSLayoutConstraint"),
                (19, "NSLayoutConstraint")
            ]
        }
        addTeardownBlock {
            await MainActor.run {
                box.window?.isHidden = true
                box.window?.windowScene = nil
            }
        }

        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)
        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        guard case .hierarchy(let hierarchy)? = try await client.nextFrame()?.body else {
            return XCTFail("expected Hierarchy")
        }
        // The test's view, told apart by its unusual size.
        let node = try XCTUnwrap(
            hierarchy.nodes.first {
                $0.viewClassName == "UIView" && $0.bounds.size == WireSize(width: 223, height: 19)
            }
        )
        let wanted = GetLayerDetails(
            requests: [
                LayerDetailRequest(
                    layerID: node.id,
                    wantSolo: false,
                    wantGroup: false,
                    wantAttributes: false,
                    wantConstraints: true
                )
            ],
            maxTextureDimension: 0
        )
        try await client.send(Frame(requestID: 2, body: .getLayerDetails(wanted)))
        let stream = try await readStream(client, requestID: 2)

        XCTAssertEqual(stream.end, StreamEnd(status: .completed, chunkCount: 1))
        let detail = try XCTUnwrap(stream.chunks.first?.details.first)
        XCTAssertEqual(detail.status, .ok)
        XCTAssertNil(detail.group)
        XCTAssertEqual(
            detail.constraints.map(\.constant).sorted(),
            expected.map(\.constant).sorted()
        )
        XCTAssertTrue(detail.constraints.allSatisfy { $0.className == "NSLayoutConstraint" })
        XCTAssertTrue(detail.constraints.allSatisfy { $0.firstItem?.layerID == node.id })
        // The window is laid out, so all four hold (S-LAYOUT-04).
        XCTAssertTrue(detail.constraints.allSatisfy { $0.status == .satisfied })
        // The other end of the two position constraints is the window's layer, a node too.
        let others = detail.constraints.compactMap(\.secondItem).map(\.layerID)
        XCTAssertEqual(others.count, 2)
        XCTAssertTrue(others.allSatisfy { id in hierarchy.nodes.contains { $0.id == id } })
    }

    func test_S_SHOT_07_cancelOverTheConnection() async throws {
        let server = makeSlowServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        // 200 layers at 20 ms each would take four seconds. The cancel comes after the first chunk.
        try await client.send(Frame(requestID: 5, body: manyLayers(200)))
        let first = try await client.nextFrame()
        XCTAssertEqual(first?.requestID, 5)
        guard case .layerDetailsChunk(let chunk)? = first?.body, chunk.sequence == 0 else {
            return XCTFail("expected the first chunk, got \(String(describing: first))")
        }
        // The fixture's cancel: request_id 6, naming stream 5.
        try await client.send(Fixtures.data("layer-details-cancelled/03-c2s-cancel.bin").framedForTheWire)
        let stream = try await readStream(client, requestID: 5, alreadyRead: 1)

        XCTAssertEqual(stream.end.status, .cancelled)
        XCTAssertNil(stream.end.error)
        XCTAssertEqual(stream.end.chunkCount, UInt32(1 + stream.chunks.count))
        XCTAssertLessThan(stream.end.chunkCount, 200, "the stream ran to its end although it was cancelled")
        XCTAssertTrue(stream.events.isEmpty)

        // The cancel has no response of its own; the next request is answered.
        try await client.send(Frame(requestID: 7, body: .getAppIcon))
        let icon = try await client.nextFrame()
        XCTAssertEqual(icon?.requestID, 7)
        guard case .appIcon? = icon?.body else {
            return XCTFail("expected AppIcon, got \(String(describing: icon))")
        }
    }

    func test_S_SHOT_10_failsOverTheConnectionWhenTheAppIsNotActive() async throws {
        let server = makeSlowServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        // The app leaves while a stream is running: the event, then the end (P-REQ-05).
        try await client.send(Frame(requestID: 1, body: manyLayers(200)))
        let first = try await client.nextFrame()
        guard case .layerDetailsChunk? = first?.body else {
            return XCTFail("expected the first chunk, got \(String(describing: first))")
        }
        try await server.post(UIApplication.willResignActiveNotification, expecting: .inactive)
        // Chunk 0 was read above. More may follow before the event; none after it.
        var received = 1
        var afterEvent: Frame?
        while let frame = try await client.nextFrame() {
            if case .layerDetailsChunk? = frame.body {
                received += 1
                continue
            }
            XCTAssertEqual(frame, Frame(requestID: 0, body: .appStateChanged(.inactive)))
            afterEvent = try await client.nextFrame()
            break
        }
        // The fixture's end of the stream, with this stream's request_id and count.
        guard
            case .streamEnd(var expected)? = try Fixtures.frame(
                "layer-details-failed/03-s2c-stream-end.bin"
            ).body
        else { return XCTFail("the fixture is not a StreamEnd") }
        expected.chunkCount = UInt32(received)
        XCTAssertEqual(afterEvent, Frame(requestID: 1, body: .streamEnd(expected)))
        XCTAssertLessThan(received, 200)

        // Not active when the request arrives: the fixture's request is refused at once.
        let request = try Fixtures.frame("layer-details-failed/01-c2s-get-layer-details.bin")
        try await client.send(Fixtures.data("layer-details-failed/c2s.stream"))
        let refused = try await readStream(client, requestID: request.requestID)
        XCTAssertEqual(
            refused.end,
            StreamEnd(
                status: .failed,
                chunkCount: 0,
                error: WireError(code: .appNotActive, message: "the app is not active")
            )
        )
        XCTAssertTrue(refused.chunks.isEmpty)

        // Active again: the same request is served.
        try await server.post(UIApplication.didBecomeActiveNotification, expecting: .active)
        try await client.send(request)
        let served = try await readStream(client, requestID: request.requestID)
        XCTAssertEqual(served.events.map(\.state), [.active])
        XCTAssertEqual(served.end, StreamEnd(status: .completed, chunkCount: 1))
    }
}

private extension Data {
    /// A `.bin` fixture as it travels: with its length in front (P-FRAME-01).
    var framedForTheWire: Data { FrameCodec.framed(self) }
}
