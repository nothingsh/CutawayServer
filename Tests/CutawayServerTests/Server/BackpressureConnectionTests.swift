import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// Backpressure over a real connection. The session's logic is tested without
/// one (SessionBackpressureTests); these tests cover what only a socket shows: a client that
/// does not read, and one that leaves while the server neither reads nor can send.
final class BackpressureConnectionTests: ServerTestCase {
    private static let mebibyte = 1_048_576
    /// K of S-CONN-13: how far above its start the footprint may go, in budgets.
    private static let footprintBudgets = 1.5

    /// 2 MiB of pixels LZFSE cannot shrink, shared by every layer.
    private static let noise: Data = {
        var generator = SeededGenerator(seed: 16)
        return generator.bytes(count: 2 * mebibyte)
    }()

    /// A server whose every layer is a 2 MiB image of noise, whatever its ID, and whose
    /// hierarchy is empty: the test needs volume, not windows.
    private func makeNoiseServer() -> TestServer {
        makeServer { configuration in
            var app = TestHostApp()
            app.captureDetail = { request, _, _, stopFlag in
                guard !stopFlag.isSet else { return nil }
                let image = RawImage(
                    pixelWidth: 1024,
                    pixelHeight: 512,
                    bytesPerRow: 4096,
                    scale: 1,
                    pixels: Self.noise
                )
                return CapturedDetail(
                    layerID: request.layerID,
                    status: .ok,
                    solo: nil,
                    group: image,
                    attributeGroups: []
                )
            }
            app.captureHierarchy = { _ in Hierarchy(nodes: [], keyWindowID: 0) }
            configuration.hostApp = app
        }
    }

    private func details(_ requestID: UInt32, count: Int) -> Frame {
        Frame(
            requestID: requestID,
            body: .getLayerDetails(
                GetLayerDetails(
                    requests: (1...count).map {
                        LayerDetailRequest(
                            layerID: UInt64($0),
                            wantSolo: false,
                            wantGroup: true,
                            wantAttributes: false
                        )
                    },
                    maxTextureDimension: 0
                )
            )
        )
    }

    /// Polls the server's unsent bytes until they stay the same for a second; returns them
    /// and the largest value seen.
    private func waitForPlateau(_ server: TestServer) async throws -> (last: Int, peak: Int) {
        var peak = 0
        var last = -1
        var steadySince = Date()
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            let now = await server.controller.connectionUnsentByteCount() ?? 0
            peak = max(peak, now)
            if now != last {
                last = now
                steadySince = Date()
            } else if now > 0, Date().timeIntervalSince(steadySince) >= 1 {
                return (now, peak)
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        throw TestClientError(description: "the server's unsent bytes never settled; last \(last)")
    }

    func test_S_CONN_13_clientThatDoesNotReadHoldsTheServerAtTheBudget() async throws {
        let server = makeNoiseServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)
        let before = physicalFootprint()

        // 100 images of 2 MiB: 200 MiB if nothing held the server back.
        try await client.send(details(1, count: 100))
        let plateau = try await waitForPlateau(server)
        let limit = ServerConfiguration().outstandingByteLimit
        // One frame: an image of 2 MiB that LZFSE made about 1% larger, and the frame around it.
        let frame = 2 * Self.mebibyte + Self.mebibyte / 16
        XCTAssertLessThanOrEqual(plateau.peak, limit + frame, "more than the budget and one frame was unsent")
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let later = await server.controller.connectionUnsentByteCount() ?? 0
        XCTAssertEqual(later, plateau.last, "the unsent bytes moved although the client read nothing")
        let growth = Double(physicalFootprint() - before) / Double(limit)
        print(
            "S-CONN-13 over a connection: unsent \(plateau.last) bytes (peak \(plateau.peak)), "
                + "footprint +\(String(format: "%.2f", growth)) budgets"
        )
        XCTAssertLessThanOrEqual(growth, Self.footprintBudgets)

        // The client reads after all: the stream is complete.
        var layers: [UInt64] = []
        while true {
            guard let frame = try await client.nextFrame(timeout: 30) else {
                throw TestClientError(description: "the connection ended in the middle of the stream")
            }
            if case .layerDetailsChunk(let chunk)? = frame.body {
                layers += chunk.details.map(\.layerID)
            } else if case .streamEnd(let end)? = frame.body {
                XCTAssertEqual(end, StreamEnd(status: .completed, chunkCount: 100))
                break
            }
        }
        XCTAssertEqual(layers, (1...100).map(UInt64.init))
    }

    func test_S_CONN_14_pausedReadingStillNoticesTheClientLeaving() async throws {
        let server = makeNoiseServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        // The stream backs up; 100 requests behind it make the server stop reading.
        var bytes = FrameCodec.encodeFramed(details(1, count: 100))
        for id in 2...101 {
            bytes += FrameCodec.encodeFramed(Frame(requestID: UInt32(id), body: .getAppIcon))
        }
        try await client.send(bytes)
        _ = try await waitForPlateau(server)

        // Closing with unread data resets the connection.
        client.close()
        let deadline = Date().addingTimeInterval(1)
        while await server.controller.connectionUnsentByteCount() != nil {
            guard Date() < deadline else {
                XCTFail("the server did not notice within a second that the client left")
                break
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        // S-CONN-03: the next client gets in.
        _ = try await connectAndHandshake(port: port)
    }
}
