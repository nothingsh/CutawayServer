#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import Foundation

/// How a session reaches the host app: UIKit on the main thread, compression on
/// `encodeQueue`, every answer back on `queue`, a moment later. Tests replace the app
/// (`TestHostApp`) and, for a stream, the pipeline (`DetailPipeline`).
struct HostAccess: Sendable {
    let app: any HostApp
    /// The connection's registry (P-HIER-03). Main thread only.
    let registry: LayerRegistry
    let queue: DispatchQueue
    let encodeQueue: DispatchQueue

    /// Works out a value from the app on the main thread and hands it to `answer` on `queue`.
    func perform<Value: Sendable>(
        _ work: @escaping @MainActor @Sendable (any HostApp, LayerRegistry) -> Value,
        then answer: @escaping @Sendable (Value) -> Void
    ) {
        onMain(answeringOn: queue, to: answer) { [app, registry] in work(app, registry) }
    }

    /// Finds the icon on the main thread and compresses it on `encodeQueue`, like a detail.
    func loadAppIcon(then answer: @escaping @Sendable (WireImage?) -> Void) {
        let queue = self.queue
        let encodeQueue = self.encodeQueue
        perform(
            { app, _ in app.iconImage().flatMap { icon in icon.cgImage.map { ($0, Float(icon.scale)) } } },
            then: { found in
                guard let found else { return answer(nil) }
                // Drawing and compressing stay off the main thread.
                encodeQueue.async {
                    let image = ImageEncoder.encode(found.0, scale: found.1)
                    queue.async { answer(image) }
                }
            }
        )
    }
}

extension HostAccess: DetailPipeline {
    func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        stopFlag: StopFlag,
        then answer: @escaping @Sendable (CapturedDetail?) -> Void
    ) {
        perform(
            { app, registry in
                app.captureDetail(
                    request,
                    maxTextureDimension: maxTextureDimension,
                    registry: registry,
                    stopFlag: stopFlag
                )
            },
            then: answer
        )
    }

    func encodeDetail(
        _ detail: CapturedDetail,
        stopFlag: StopFlag,
        then answer: @escaping @Sendable (LayerDetail) -> Void
    ) {
        let queue = self.queue
        encodeQueue.async {
            // A stopped stream drops its details: compressing them would only cost time and
            // memory.
            guard !stopFlag.isSet else { return }
            let encoded = detail.compressed()
            queue.async { answer(encoded) }
        }
    }
}
#endif
