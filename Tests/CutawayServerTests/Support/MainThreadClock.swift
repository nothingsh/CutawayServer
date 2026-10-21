import CutawayWire
import QuartzCore
import UIKit

@testable import CutawayServer

/// Times what the server does on the main thread (S-STAB-01). Every piece of that work is
/// one call of a `HostApp` method; the clock wraps those it is given and times
/// each call on its own. The rendering of an image is timed apart and left out of its
/// detail's time: the requirement does not count a layer's own rendering (S-SHOT-09).
final class MainThreadClock: @unchecked Sendable {
    struct Block: Equatable {
        /// What the main thread did, such as "the detail of layer 42".
        var what: String
        var seconds: Double
    }

    private let lock = NSLock()
    private var blocks: [Block] = []
    private var renders: [Double] = []

    /// The real configuration, with the main thread's work timed.
    func configuration(_ base: ServerConfiguration = ServerConfiguration()) -> ServerConfiguration {
        var configuration = base
        var app = TestHostApp(base.hostApp)
        app.captureHierarchy = { context in
            self.time("the hierarchy") { base.hostApp.captureHierarchy(in: context) }
        }
        app.captureSubtree = { rootID, context in
            self.time("the subtree of layer \(rootID)") {
                base.hostApp.captureSubtree(of: rootID, in: context)
            }
        }
        app.setAttribute = { request, context in
            self.time("setting \(request.attributeID)") {
                base.hostApp.setAttribute(request, in: context)
            }
        }
        // As the default, with the renderer timed.
        app.captureDetail = { request, maxTextureDimension, context, stopFlag in
            var rendering = 0.0
            return self.time(
                "the detail of layer \(request.layerID)",
                leavingOut: { rendering },
                {
                    DetailCapture.capture(
                        request,
                        maxTextureDimension: maxTextureDimension,
                        in: context,
                        stopFlag: stopFlag,
                        readAttributes: AttributeCatalog.standard.read,
                        render: { layer, mode, plan in
                            let start = CACurrentMediaTime()
                            let image = LayerRenderer.render(layer, mode: mode, plan: plan)
                            let seconds = CACurrentMediaTime() - start
                            rendering += seconds
                            self.record(render: seconds)
                            return image
                        }
                    )
                }
            )
        }
        configuration.hostApp = app
        return configuration
    }

    /// Every call timed so far, in order.
    var all: [Block] {
        lock.lock()
        defer { lock.unlock() }
        return blocks
    }

    /// The longest call so far.
    var longest: Block? { all.max { $0.seconds < $1.seconds } }

    /// The longest rendering of one image so far; not part of any block.
    var longestRender: Double {
        lock.lock()
        defer { lock.unlock() }
        return renders.max() ?? 0
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        blocks = []
        renders = []
    }

    private func time<T>(
        _ what: String,
        leavingOut excluded: () -> Double = { 0 },
        _ work: () -> T
    ) -> T {
        let start = CACurrentMediaTime()
        let result = work()
        let seconds = CACurrentMediaTime() - start - excluded()
        lock.lock()
        blocks.append(Block(what: what, seconds: seconds))
        lock.unlock()
        return result
    }

    private func record(render seconds: Double) {
        lock.lock()
        renders.append(seconds)
        lock.unlock()
    }
}
