import CutawayWire
import Foundation

@testable import CutawayServer

/// Holds an object weakly, so that a test can ask whether it is gone.
final class WeakBox<Object: AnyObject>: @unchecked Sendable {
    weak var object: Object?

    init(_ object: Object?) {
        self.object = object
    }
}
