import CutawayWire
import Foundation
import XCTest

@testable import CutawayServer

/// The server lets go of a session once its connection is gone, even in the
/// middle of a stream (S-STAB-02). Without a connection this is `LongUseTests`; this test
/// adds the controller's part.
final class SessionReleaseTests: ServerTestCase {
    func test_S_STAB_02_theServerLetsGoOfAClosedConnectionsSession() async throws {
        let server = makeServer()
        let port = try await server.start()
        let client = try await connect(to: port)
        try await handshake(client)
        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        guard case .hierarchy(let hierarchy)? = try await client.nextFrame()?.body else {
            return XCTFail("no hierarchy")
        }
        weak let session = await server.controller.currentSession()
        XCTAssertNotNil(session)

        // Every layer many times over, so that the stream is under way when the client leaves.
        let requests = hierarchy.nodes.map {
            LayerDetailRequest(
                layerID: $0.id,
                wantSolo: true,
                wantGroup: true,
                wantAttributes: true,
                wantConstraints: true
            )
        }
        try await client.send(
            Frame(
                requestID: 2,
                body: .getLayerDetails(
                    GetLayerDetails(
                        requests: Array(repeating: requests, count: 200).flatMap { $0 },
                        maxTextureDimension: 0
                    )
                )
            )
        )
        guard case .layerDetailsChunk? = try await client.nextFrame()?.body else {
            return XCTFail("no chunk")
        }
        client.close()

        let deadline = Date().addingTimeInterval(10)
        while session != nil {
            guard Date() < deadline else {
                return XCTFail("the session outlived its connection")
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        // And the next client is served, not told the server is busy.
        _ = try await connectAndHandshake(port: port)
    }
}
