@testable import CutawayServer

// What the tests observe on a session. `activeStream` is `private(set)` for this purpose.

extension Session {
    /// The stream of the request in hand. Read on the session's queue.
    var currentStream: LayerDetailsStream? { activeStream?.stream }
}
