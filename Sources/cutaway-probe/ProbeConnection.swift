import CutawayWire
import Foundation

/// A blocking TCP connection that sends and receives frames.
final class ProbeConnection {
    private let descriptor: Int32
    private var splitter = FrameSplitter()
    /// How long a read waits, unless one says otherwise.
    private let timeout: TimeInterval

    /// No frame arrived in time.
    private struct TimedOut: Error {}

    /// Returns `nil` when nothing accepts the connection.
    /// - Parameter receiveBuffer: The socket's receive buffer in bytes; the system's default
    ///   when `nil`.
    init?(host: String, port: UInt16, timeout: TimeInterval, receiveBuffer: Int? = nil) {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else { return nil }

        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { return nil }
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        Self.setTimeout(timeout, of: SO_RCVTIMEO, on: descriptor)
        Self.setTimeout(timeout, of: SO_SNDTIMEO, on: descriptor)
        if let receiveBuffer {
            // Set before connecting: the window offered to the server depends on it.
            var size = Int32(receiveBuffer)
            setsockopt(descriptor, SOL_SOCKET, SO_RCVBUF, &size, socklen_t(MemoryLayout<Int32>.size))
        }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else {
            close(descriptor)
            return nil
        }
        self.descriptor = descriptor
        self.timeout = timeout
    }

    /// 0 would mean no limit; a little more than nothing is as good as nothing here.
    private static func setTimeout(_ seconds: TimeInterval, of option: Int32, on descriptor: Int32) {
        let seconds = max(seconds, 0.001)
        var limit = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - seconds.rounded(.down)) * 1_000_000))
        setsockopt(descriptor, SOL_SOCKET, option, &limit, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit {
        close(descriptor)
    }

    func send(_ frame: Frame) throws {
        let bytes = FrameCodec.framed(FrameCodec.encode(frame))
        var sent = 0
        while sent < bytes.count {
            let count = bytes.withUnsafeBytes { buffer in
                // The buffer is not empty here, so it has a base address.
                Darwin.send(descriptor, buffer.baseAddress.map { $0 + sent }, bytes.count - sent, 0)
            }
            guard count > 0 else { throw ProbeFailure("could not send: \(String(cString: strerror(errno)))") }
            sent += count
        }
    }

    /// The next frame, verified and decoded; `nil` when the server closed the connection.
    func nextFrame() throws -> Frame? {
        do {
            return try receiveFrame()
        } catch is TimedOut {
            throw ProbeFailure("timed out waiting for a frame")
        }
    }

    /// The next frame, or `nil` when none arrives within `seconds`. A closed connection fails.
    func nextFrame(within seconds: TimeInterval) throws -> Frame? {
        Self.setTimeout(seconds, of: SO_RCVTIMEO, on: descriptor)
        defer { Self.setTimeout(timeout, of: SO_RCVTIMEO, on: descriptor) }
        do {
            guard let frame = try receiveFrame() else { throw ProbeFailure("the server closed the connection") }
            return frame
        } catch is TimedOut {
            return nil
        }
    }

    private func receiveFrame() throws -> Frame? {
        while true {
            do {
                if let payload = try splitter.next() {
                    return try FrameCodec.decode(payload)
                }
            } catch WireFailure.lengthExceedsLimit(let length) {
                throw ProbeFailure("a frame announces \(length) bytes, above the limit (P-FRAME-03)")
            } catch {
                throw ProbeFailure("a frame failed verification (P-FRAME-04)")
            }
            var chunk = [UInt8](repeating: 0, count: 65536)
            let count = recv(descriptor, &chunk, chunk.count, 0)
            if count == 0 { return nil }
            guard count > 0 else {
                if errno == EAGAIN { throw TimedOut() }
                throw ProbeFailure("could not receive: \(String(cString: strerror(errno)))")
            }
            splitter.append(Data(chunk[0..<count]))
        }
    }
}
