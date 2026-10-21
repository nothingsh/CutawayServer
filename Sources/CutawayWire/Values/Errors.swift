#if !canImport(UIKit) || DEBUG || ReleaseEnabled

// Errors, and how a stream ends.

public enum ErrorCode: Sendable, Equatable {
    case unknown
    case malformedFrame
    case unexpectedMessage
    case busy
    case appNotActive
    case internalError
    /// The layer a request names does not exist (P-HIER-11, P-SET-03). Protocol 0.3.
    case layerNotFound
    /// The attribute does not exist on the layer or cannot be changed (P-SET-03). Protocol 0.3.
    case attributeNotEditable
    /// The value written is not acceptable (P-SET-03). Protocol 0.3.
    case invalidAttributeValue
    /// The server cannot apply an override the request asks for (P-ENV-04). Protocol 1.2.
    case notSupported
}

/// Also an `Error`, so that a failure can carry it in a `Result`.
public struct WireError: Error, Sendable, Equatable {
    public var code: ErrorCode
    /// For people. Never branch on it.
    public var message: String

    public init(code: ErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum StreamStatus: Sendable, Equatable {
    case completed
    case cancelled
    case failed
}

public struct StreamEnd: Sendable, Equatable {
    public var status: StreamStatus
    public var chunkCount: UInt32
    /// Set when `status` is `.failed`.
    public var error: WireError?

    public init(status: StreamStatus, chunkCount: UInt32, error: WireError? = nil) {
        self.status = status
        self.chunkCount = chunkCount
        self.error = error
    }
}
#endif
