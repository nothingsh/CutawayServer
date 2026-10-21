#if !canImport(UIKit) || DEBUG || ReleaseEnabled

// The project's own value types. Other targets use these; FlatBuffers types stay inside
// this module.

/// The body of a frame: one case per member of the schema's `Body` union.
public enum Message: Sendable, Equatable {
    case hello(Hello)
    case getAppIcon
    case appIcon(AppIcon)
    case getHierarchy
    case hierarchy(Hierarchy)
    case getLayerDetails(GetLayerDetails)
    case layerDetailsChunk(LayerDetailsChunk)
    case streamEnd(StreamEnd)
    case cancel(targetRequestID: UInt32)
    case error(WireError)
    case appStateChanged(AppState)
    case setAttribute(SetAttribute)
    case setAttributeResult(SetAttributeResult)
    /// Answered with a `Hierarchy` (P-HIER-10).
    case getSubtree(rootID: UInt64)
    /// Answered with an `Environment` (P-ENV-01). Protocol 1.2.
    case getEnvironment
    /// Replaces every override; `nil` removes them all (P-ENV-02). Protocol 1.2.
    case setEnvironment(overrides: Traits?)
    /// The answer to `getEnvironment` and `setEnvironment`. Protocol 1.2.
    case environment(Environment)
}

public struct Frame: Sendable, Equatable {
    /// 0 for the handshake, for events and for errors that answer no request.
    public var requestID: UInt32
    /// `nil` when the body is absent on the wire. A verified frame may have no body.
    public var body: Message?

    public init(requestID: UInt32, body: Message?) {
        self.requestID = requestID
        self.body = body
    }
}

public enum WireFailure: Error, Equatable {
    /// The payload is not a verified `Frame` buffer with the identifier `CTWY`.
    case malformed
    /// A frame announced a length above `FrameCodec.maximumFrameLength`.
    case lengthExceedsLimit(UInt32)
}
#endif
