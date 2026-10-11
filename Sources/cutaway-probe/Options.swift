import Foundation

/// The command line.
struct Options {
    var host = "127.0.0.1"
    var port: UInt16?
    var bundleID: String?
    var wait: TimeInterval = 0
    var requiresIcon = false
    var expectDemo = false
    /// The pause after each chunk of the layer details, in seconds; `nil` reads at full speed.
    var slowRead: TimeInterval?

    static let usage = """
        usage: cutaway-probe [--host ADDRESS] [--port N] [--bundle-id ID] [--wait SECONDS] [--require-icon] [--expect-demo] [--slow-read MILLISECONDS]

          --host ADDRESS   IPv4 address to connect to (default 127.0.0.1)
          --port N         check this port only (default: scan 48160-48167)
          --bundle-id ID   pick the server of the app with this bundle identifier
          --wait SECONDS   keep looking for the server for this long (default 0)
          --require-icon   fail when the app has no icon
          --expect-demo    also check the hierarchy, the screenshots, the attributes and the
                           constraints for what the demo app shows
          --slow-read MILLISECONDS
                           read the layer details slowly: a small receive buffer, and a pause
                           after each chunk, so that the server has to hold back (S-CONN-13)
        """

    init(arguments: [String]) throws {
        var rest = arguments[...]
        func value(of option: String) throws -> String {
            guard let value = rest.popFirst() else { throw ProbeFailure("\(option) needs a value") }
            return value
        }
        while let argument = rest.popFirst() {
            switch argument {
            case "--host":
                host = try value(of: argument)
            case "--port":
                guard let port = UInt16(try value(of: argument)), port != 0 else {
                    throw ProbeFailure("--port needs a number between 1 and 65535")
                }
                self.port = port
            case "--bundle-id":
                bundleID = try value(of: argument)
            case "--wait":
                guard let wait = TimeInterval(try value(of: argument)), wait >= 0 else {
                    throw ProbeFailure("--wait needs a number of seconds")
                }
                self.wait = wait
            case "--require-icon":
                requiresIcon = true
            case "--expect-demo":
                expectDemo = true
            case "--slow-read":
                guard let milliseconds = UInt32(try value(of: argument)) else {
                    throw ProbeFailure("--slow-read needs a whole number of milliseconds")
                }
                slowRead = TimeInterval(milliseconds) / 1000
            default:
                throw ProbeFailure("unknown argument \(argument)")
            }
        }
    }
}
