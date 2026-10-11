import CutawayWire
import Foundation

// Finding a server: every port of the range, or one, handshaken with once.

/// A server that answered the handshake, with the connection still open.
struct FoundServer {
    var connection: ProbeConnection
    var port: UInt16
    var app: AppInfo
}

enum ScanResult {
    case found(FoundServer)
    /// `busyPorts`: servers that answered with `Busy`. `notes`: ports where something
    /// accepted the connection but did not answer like a server.
    case notFound(busyPorts: [UInt16], notes: [String])
}

let kClientHello = Frame(
    requestID: 0,
    body: .hello(
        Hello(
            version: .current,
            role: .client,
            client: ClientInfo(name: "cutaway-probe", version: "0.1.0")
        )
    )
)

/// Handshakes with every port once.
///
/// While scanning the range, a port that does not answer like a server is noted and skipped:
/// something else may be listening there. With `--port`, the same thing is a failure.
func scan(_ options: Options) throws -> ScanResult {
    let ports = options.port.map { [$0] } ?? Array(ProtocolLimits.portRange)
    var busyPorts: [UInt16] = []
    var notes: [String] = []
    for port in ports {
        // A slow reader's small buffer fills soon, so the server feels it at once.
        let receiveBuffer = options.slowRead == nil ? nil : 65536
        guard
            let connection = ProbeConnection(
                host: options.host,
                port: port,
                timeout: 5,
                receiveBuffer: receiveBuffer
            )
        else {
            continue
        }
        do {
            try connection.send(kClientHello)
            let first = try connection.nextFrame()
            if case .error(let error)? = first?.body, error.code == .busy {
                guard first?.requestID == 0 else {
                    throw ProbeFailure(
                        "Busy has request_id \(first?.requestID ?? 0), expected 0 (P-TRANS-03)"
                    )
                }
                busyPorts.append(port)
                continue
            }
            let app = try Checks.serverHello(first)
            if let bundleID = options.bundleID, app.bundleID != bundleID {
                continue  // Another app's server; closing the connection frees it.
            }
            return .found(FoundServer(connection: connection, port: port, app: app))
        } catch let failure as ProbeFailure {
            if options.port != nil { throw failure }
            notes.append("port \(port): \(failure)")
        }
    }
    return .notFound(busyPorts: busyPorts, notes: notes)
}

func findServer(_ options: Options) throws -> FoundServer {
    let deadline = Date().addingTimeInterval(options.wait)
    while true {
        switch try scan(options) {
        case .found(let server):
            return server
        case let .notFound(busyPorts, notes):
            if Date() < deadline {
                Thread.sleep(forTimeInterval: 0.5)
                continue
            }
            if let port = busyPorts.first {
                throw ProbeFailure("Server is busy: another client is connected (port \(port))")
            }
            let target = options.bundleID.map { "of \($0) " } ?? ""
            let details = notes.isEmpty ? "" : "; " + notes.joined(separator: "; ")
            throw ProbeFailure("no server \(target)found on \(options.host)\(details)")
        }
    }
}
