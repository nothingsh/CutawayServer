import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// A server on a free port of 127.0.0.1 that reads whatever a client sends first, answers
/// with `reply` and closes. It serves `connections` clients, then stops listening.
private final class StandInServer: Sendable {
    let port: UInt16

    init(reply: Data, connections: Int) throws {
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else { throw ProbeFailure("socket: \(String(cString: strerror(errno)))") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, length) == 0 && listen(listener, 4) == 0
                    && getsockname(listener, $0, &length) == 0
            }
        }
        guard bound else {
            close(listener)
            throw ProbeFailure("could not listen on 127.0.0.1: \(String(cString: strerror(errno)))")
        }
        port = UInt16(bigEndian: address.sin_port)
        // A test that fails before its last connection must not leave the thread waiting forever.
        var limit = timeval(tv_sec: 10, tv_usec: 0)
        setsockopt(listener, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))

        Thread.detachNewThread {
            defer { close(listener) }
            for _ in 0..<connections {
                let client = accept(listener, nil, nil)
                guard client >= 0 else { return }
                var buffer = [UInt8](repeating: 0, count: 4096)
                _ = recv(client, &buffer, buffer.count, 0)
                _ = reply.withUnsafeBytes { send(client, $0.baseAddress, $0.count, 0) }
                close(client)
            }
        }
    }
}

/// A port of 127.0.0.1 that nothing listens on: bound once to learn a free number, then let
/// go. Nothing is left running, so the port is closed before the test uses it.
private func unusedPort() throws -> UInt16 {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw ProbeFailure("socket: \(String(cString: strerror(errno)))") }
    defer { close(descriptor) }
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr.s_addr = inet_addr("127.0.0.1")
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let bound = withUnsafeMutablePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(descriptor, $0, length) == 0 && getsockname(descriptor, $0, &length) == 0
        }
    }
    guard bound else { throw ProbeFailure("could not bind 127.0.0.1: \(String(cString: strerror(errno)))") }
    return UInt16(bigEndian: address.sin_port)
}

/// What the probe tells its caller, by message and by exit code.
final class ProbeRunTests: XCTestCase {
    func test_S_PROBE_01_reportsABusyServer() throws {
        let busy = try Fixtures.data("busy/01-s2c-error.bin")
        let server = try StandInServer(reply: FrameCodec.framed(busy), connections: 2)
        let options = try Options(arguments: ["--port", String(server.port)])

        XCTAssertThrowsError(try findServer(options)) { error in
            XCTAssertTrue(
                "\(error)".contains("Server is busy: another client is connected (port \(server.port))"),
                "\(error)"
            )
        }
        XCTAssertEqual(cutaway_probe.run(arguments: ["--port", String(server.port)]), 1)
    }

    func test_S_PROBE_01_failuresExitWithNonZero() throws {
        XCTAssertEqual(cutaway_probe.run(arguments: ["--no-such-option"]), 2)
        XCTAssertEqual(cutaway_probe.run(arguments: ["--port", "0"]), 2)

        // A port nothing listens on.
        let port = try unusedPort()
        let options = try Options(arguments: ["--port", String(port)])
        XCTAssertThrowsError(try findServer(options)) { error in
            XCTAssertTrue("\(error)".contains("no server found on 127.0.0.1"), "\(error)")
        }
        XCTAssertEqual(cutaway_probe.run(arguments: ["--port", String(port)]), 1)
    }
}
