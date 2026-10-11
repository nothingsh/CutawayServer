#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation

/// Told about the progress of one stream, on the server queue.
protocol LayerDetailsStreamDelegate: AnyObject {
    /// The bytes the connection has not sent yet; read before each layer.
    var unsentByteCount: Int { get }
    /// Once per request, in the order of the request.
    func streamDidProduce(_ detail: LayerDetail)
    /// Once, after the last detail, unless the stream is stopped first.
    func streamDidComplete()
}

/// Works through one `GetLayerDetails`: one layer at a time on the main thread, the images
/// compressed elsewhere, the details reported in the order of the request
/// (PROTOCOL.md, P-DET-01, P-DET-06). It knows values, not frames or the network.
/// Confined to the server queue.
final class LayerDetailsStream: @unchecked Sendable {
    /// What a captured detail is counted as until it is reported: its pixels, a thirty-second
    /// more for LZFSE, which makes incompressible pixels about 1% larger, and room
    /// for the attributes and constraints.
    static func estimatedByteCount(of detail: CapturedDetail) -> Int {
        let pixels = detail.pixelByteCount
        return pixels + pixels / 32 + 65536
    }

    private let request: GetLayerDetails
    private let pipeline: any DetailPipeline
    /// No layer is rendered while more bytes than this are outstanding: not yet sent, or not
    /// yet compressed (S-CONN-13).
    private let outstandingByteLimit: Int
    private weak var delegate: LayerDetailsStreamDelegate?
    private let stopFlag = StopFlag()
    /// The index of the next request to capture.
    private var nextIndex = 0
    private var isCapturing = false
    /// Captured, not yet reported: the estimates of those details.
    private var pendingByteCount = 0
    private var reportedCount = 0
    /// Stopped from outside, or completed.
    private var isOver = false

    /// - Parameter delegate: Held weakly. Without one, nothing counts as unsent.
    init(
        request: GetLayerDetails,
        pipeline: any DetailPipeline,
        outstandingByteLimit: Int,
        delegate: LayerDetailsStreamDelegate?
    ) {
        self.request = request
        self.pipeline = pipeline
        self.outstandingByteLimit = outstandingByteLimit
        self.delegate = delegate
    }

    func start() {
        advance()
    }

    /// Goes on where it stopped, if there is room now: called when the connection sent some.
    func resume() {
        advance()
    }

    /// Nothing is reported after this returns, and no new screenshot begins.
    func stop() {
        isOver = true
        stopFlag.set()
    }

    private func advance() {
        guard !isOver else { return }
        guard reportedCount < request.requests.count else {
            isOver = true
            delegate?.streamDidComplete()
            return
        }
        // One layer at a time: the main thread returns to its run loop between two layers.
        // It never waits for the compressor or the connection; when either falls behind,
        // rendering pauses here. One more layer may go over the limit: the bound is the limit
        // and one detail.
        guard !isCapturing, nextIndex < request.requests.count,
              (delegate?.unsentByteCount ?? 0) + pendingByteCount <= outstandingByteLimit else {
            return
        }
        isCapturing = true
        let item = request.requests[nextIndex]
        nextIndex += 1
        pipeline.captureDetail(
            item,
            maxTextureDimension: request.maxTextureDimension,
            stopFlag: stopFlag
        ) { [weak self] detail in
            self?.didCapture(detail, of: item)
        }
    }

    private func didCapture(_ captured: CapturedDetail?, of item: LayerDetailRequest) {
        isCapturing = false
        guard !isOver else { return }
        // The flag is set only together with `isOver`, so a capture that gives nil now broke its
        // contract. The layer is reported as not captured rather than waited for forever
        // (P-DET-01, P-DET-03).
        let detail = captured ?? CapturedDetail(
            layerID: item.layerID,
            status: .captureFailed,
            solo: nil,
            group: nil,
            attributeGroups: []
        )
        let estimate = Self.estimatedByteCount(of: detail)
        pendingByteCount += estimate
        pipeline.encodeDetail(detail, stopFlag: stopFlag) { [weak self] encoded in
            self?.didEncode(encoded, estimate: estimate)
        }
        advance()
    }

    private func didEncode(_ detail: LayerDetail, estimate: Int) {
        guard !isOver else { return }
        pendingByteCount -= estimate
        reportedCount += 1
        delegate?.streamDidProduce(detail)
        advance()
    }
}
#endif
