#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire

/// The two steps a stream of layer details drives, one layer at a time: capture on the main
/// thread, compression off it. Called on the server queue; every answer arrives there, a
/// moment later. `HostAccess` is the real one; tests script one that holds a layer back.
protocol DetailPipeline {
    /// Captures one layer on the main thread, for a client at `version`, with the stream's
    /// `memo`. The result is `nil` when the stop flag was set before the capture was done.
    func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        version: ProtocolVersion,
        memo: RequestMemo,
        stopFlag: StopFlag,
        then answer: @escaping @Sendable (CapturedDetail?) -> Void
    )
    /// Compresses the images off the main thread. Details complete in the order they were
    /// handed in. Once the stop flag is set, nothing more is compressed and `answer` may not
    /// be called.
    func encodeDetail(
        _ detail: CapturedDetail,
        stopFlag: StopFlag,
        then answer: @escaping @Sendable (LayerDetail) -> Void
    )
}
#endif
