import CutawayWire
import Foundation

struct TestClientError: Error, CustomStringConvertible {
    var description: String
}

private func loopbackAddress(host: String, port: UInt16) -> sockaddr_in? {
    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return nil }
    return address
}

/// A TCP client for tests. Its blocking socket calls run on a queue of its own, so that a
/// test never blocks the main thread: the server needs it to read UIKit.
final class TestClient: @unchecked Sendable {
    private let descriptor: Int32
    private let ioQueue = DispatchQueue(label: "dev.cutaway.tests.client")
    // Touched on `ioQueue` only.
    private var splitter = FrameSplitter()
    private var isClosed = false

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        if !isClosed { Darwin.close(descriptor) }
    }

    /// Throws when nothing accepts the connection.
    static func connect(port: UInt16, host: String = "127.0.0.1") async throws -> TestClient {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                guard var address = loopbackAddress(host: host, port: port) else {
                    continuation.resume(throwing: TestClientError(description: "bad address \(host)"))
                    return
                }
                let descriptor = socket(AF_INET, SOCK_STREAM, 0)
                var on: Int32 = 1
                setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
                let result = withUnsafePointer(to: &address) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                    }
                }
                if result == 0 {
                    continuation.resume(returning: TestClient(descriptor: descriptor))
                } else {
                    let reason = String(cString: strerror(errno))
                    Darwin.close(descriptor)
                    continuation.resume(
                        throwing: TestClientError(description: "connect to \(host):\(port): \(reason)")
                    )
                }
            }
        }
    }

    private func onIO<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            ioQueue.async { continuation.resume(with: Result { try work() }) }
        }
    }

    /// Sends raw bytes, exactly as given.
    func send(_ bytes: Data) async throws {
        try await onIO { [self] in
            var sent = 0
            while sent < bytes.count {
                let count = bytes.withUnsafeBytes {
                    Darwin.send(descriptor, $0.baseAddress! + sent, bytes.count - sent, 0)
                }
                guard count > 0 else {
                    throw TestClientError(description: "send: \(String(cString: strerror(errno)))")
                }
                sent += count
            }
        }
    }

    func send(_ frame: Frame) async throws {
        try await send(FrameCodec.framed(FrameCodec.encode(frame)))
    }

    /// Reads from the socket once. Returns `nil` when the server closed or reset the connection.
    private func receive(timeout: TimeInterval) throws -> Data? {
        var limit = timeval(
            tv_sec: Int(timeout),
            tv_usec: Int32((timeout - timeout.rounded(.down)) * 1_000_000)
        )
        setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, &limit, socklen_t(MemoryLayout<timeval>.size))
        var chunk = [UInt8](repeating: 0, count: 65536)
        let count = recv(descriptor, &chunk, chunk.count, 0)
        if count > 0 { return Data(chunk[0..<count]) }
        if count == 0 || errno == ECONNRESET { return nil }
        throw TestClientError(
            description: errno == EAGAIN
                ? "timed out after \(timeout) s waiting for the server"
                : "recv: \(String(cString: strerror(errno)))"
        )
    }

    /// The next frame payload, or `nil` when the server closed the connection.
    /// Throws when nothing arrives in time.
    func nextPayload(timeout: TimeInterval = 5) async throws -> Data? {
        try await onIO { [self] in
            while true {
                if let payload = try splitter.next() { return payload }
                guard let bytes = try receive(timeout: timeout) else { return nil }
                splitter.append(bytes)
            }
        }
    }

    /// The next frame, decoded; `nil` when the server closed the connection.
    func nextFrame(timeout: TimeInterval = 5) async throws -> Frame? {
        guard let payload = try await nextPayload(timeout: timeout) else { return nil }
        return try FrameCodec.decode(payload)
    }

    /// Exactly `count` raw bytes, bypassing the frame splitter. Use it before any `next…` call.
    func read(exactly count: Int, timeout: TimeInterval = 5) async throws -> Data {
        try await onIO { [self] in
            var result = Data()
            while result.count < count {
                var limit = timeval(tv_sec: Int(timeout), tv_usec: 0)
                setsockopt(
                    descriptor,
                    SOL_SOCKET,
                    SO_RCVTIMEO,
                    &limit,
                    socklen_t(MemoryLayout<timeval>.size)
                )
                var chunk = [UInt8](repeating: 0, count: count - result.count)
                let received = recv(descriptor, &chunk, chunk.count, 0)
                guard received > 0 else {
                    throw TestClientError(description: "the stream ended after \(result.count) bytes")
                }
                result.append(contentsOf: chunk[0..<received])
            }
            return result
        }
    }

    func close() {
        ioQueue.sync {
            guard !isClosed else { return }
            isClosed = true
            Darwin.close(descriptor)
        }
    }
}

/// Keeps a loopback port taken for as long as it lives.
final class PortHolder {
    private let descriptor: Int32

    /// Returns `nil` when the port cannot be bound, which means someone else holds it.
    init?(port: UInt16) {
        guard var address = loopbackAddress(host: "127.0.0.1", port: port) else { return nil }
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        // Lets the bind succeed while old connections of this port linger in TIME_WAIT.
        // It does not let two sockets listen on the same address and port.
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(descriptor, 8) == 0 else {
            Darwin.close(descriptor)
            return nil
        }
        self.descriptor = descriptor
    }

    deinit {
        Darwin.close(descriptor)
    }
}
