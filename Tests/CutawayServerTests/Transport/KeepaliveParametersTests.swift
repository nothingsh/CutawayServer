import Network
import XCTest

@testable import CutawayServer

/// The parameters the server listens with. Builds them only: no port is opened.
final class KeepaliveParametersTests: XCTestCase {
    func test_S_CONN_11_listenerParametersEnableKeepalive() throws {
        let parameters = Listener.parameters(port: 48263, keepalive: ServerConfiguration().keepalive)
        let tcp = try XCTUnwrap(
            parameters.defaultProtocolStack.transportProtocol as? NWProtocolTCP.Options
        )
        XCTAssertTrue(tcp.enableKeepalive)
        XCTAssertEqual(tcp.keepaliveIdle, 10)
        XCTAssertEqual(tcp.keepaliveInterval, 5)
        XCTAssertEqual(tcp.keepaliveCount, 3)
        XCTAssertTrue(parameters.defaultProtocolStack.applicationProtocols.isEmpty, "no TLS")
        XCTAssertEqual(
            parameters.requiredLocalEndpoint,
            .hostPort(host: .ipv4(.loopback), port: 48263)
        )
    }
}
