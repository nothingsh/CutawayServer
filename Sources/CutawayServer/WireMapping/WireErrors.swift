#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation

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

    // MARK: - Attributes (P-SET-03)

    /// The attribute `id` is none of `what`'s: "this layer", "layer 7", "virtual node 9".
    static func notAnAttribute(_ id: String, of what: String) -> WireError {
        WireError(code: .attributeNotEditable, message: "\(id) is not an attribute of \(what)")
    }

    /// P-ATTR-11: the layer's side of a pair, of a layer that backs a view.
    static func backsAView(_ layerID: UInt64, set viewID: String, insteadOf id: String) -> WireError {
        WireError(code: .attributeNotEditable, message: "layer \(layerID) backs a view; set \(viewID) instead of \(id)")
    }

    /// P-DET-09: a virtual node has the host app's attributes only.
    static func onlyAppAttributes(_ id: String, of what: String) -> WireError {
        WireError(code: .attributeNotEditable, message: "\(id) is not an attribute of \(what); it has the app's only")
    }

    /// P-ATTR-06: the attribute cannot be changed, or not while it reads as it does now.
    static func readOnly(_ id: String) -> WireError {
        WireError(code: .attributeNotEditable, message: "\(id) is read-only")
    }

    /// P-SET-02, P-SET-07: the value breaks a rule of the attribute `id`, for `reason`.
    static func invalidValue(_ id: String, _ reason: String) -> WireError {
        WireError(code: .invalidAttributeValue, message: "\(id) \(reason)")
    }

    /// The host app's `set` threw `error`: its description is the message.
    static func refused(by error: any Error) -> WireError {
        WireError(
            code: .invalidAttributeValue,
            message: (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        )
    }

    // MARK: - Environment

    /// P-ENV-04: the client sent a value of this kind that the pinned schema does not name.
    static func unknownTraitValue(_ kind: TraitKind) -> WireError {
        WireError(code: .notSupported, message: "the \(kind.title) has a value this server does not know")
    }

    /// P-ENV-04: this kind cannot be overridden on the system the app runs on.
    static func traitNotOverridable(_ kind: TraitKind) -> WireError {
        WireError(code: .notSupported, message: "the \(kind.title) cannot be overridden on this device")
    }
}

extension TraitKind {
    /// For the messages of `NotSupported`.
    var title: String {
        switch self {
        case .userInterfaceStyle: "appearance"
        case .contentSizeCategory: "content size category"
        case .layoutDirection: "layout direction"
        case .horizontalSizeClass: "horizontal size class"
        case .verticalSizeClass: "vertical size class"
        }
    }
}
#endif
