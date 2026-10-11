#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire

/// The errors the server sends, each with its words in one place.
extension WireError {
    /// The same words as the `app-not-active` fixture.
    static let appNotActive = WireError(code: .appNotActive, message: "the app is not active")

    /// The same words as the `layer-details-failed` fixture.
    static let leftActiveState = WireError(
        code: .appNotActive,
        message: "the app left the active state during capture"
    )

    /// The same words as the `subtree` fixture.
    static func layerNotFound(_ layerID: UInt64) -> WireError {
        WireError(code: .layerNotFound, message: "no layer with id \(layerID)")
    }

    /// P-TRANS-03: one client at a time.
    static let busy = WireError(code: .busy, message: "another client is connected")

    static let malformedFrame = WireError(code: .malformedFrame, message: "the frame is malformed")

    /// P-HELLO-05.
    static let expectedClientHello = WireError(
        code: .unexpectedMessage,
        message: "expected a client Hello first"
    )

    /// P-REQ-08.
    static let unexpectedMessage = WireError(
        code: .unexpectedMessage,
        message: "this message is not expected here"
    )
}
#endif
