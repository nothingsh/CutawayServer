import CutawayWire
import Foundation

@testable import CutawayServer

/// Stands in for the main-thread capture and the compressor: every layer is captured at
/// once, unless the test holds it back, as if the main thread were busy.
final class ScriptedCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var capturedIDs: [UInt64] = []
    private var held: Set<UInt64> = []
    private var waiting: [UInt64: @Sendable () -> Void] = [:]

    /// Layers the registry does not know.
    let missing: Set<UInt64>
    /// The side, in pixels, of the square group image each layer gets.
    let side: (UInt64) -> Int
    /// The constraints each layer gets.
    let constraints: (UInt64) -> [LayoutConstraint]
    /// Pixels LZFSE cannot make smaller, so that a compressed image is as large as its pixels.
    let incompressible: Bool
    /// Layers whose capture gives `nil` although the stop flag is not set, which the real
    /// capture never does.
    let givesNil: Set<UInt64>
    /// The attributes of each layer that is found.
    let attributeGroups: (UInt64) -> [AttributeGroup]
    private var compressedIDs: [UInt64] = []

    init(
        missing: Set<UInt64> = [],
        side: @escaping (UInt64) -> Int = { _ in 2 },
        constraints: @escaping (UInt64) -> [LayoutConstraint] = { _ in [] },
        incompressible: Bool = false,
        givesNil: Set<UInt64> = [],
        attributeGroups: @escaping (UInt64) -> [AttributeGroup] = { _ in [] }
    ) {
        self.attributeGroups = attributeGroups
        self.missing = missing
        self.side = side
        self.constraints = constraints
        self.incompressible = incompressible
        self.givesNil = givesNil
    }

    /// The layers whose images were compressed, in order.
    var compressed: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return compressedIDs
    }

    /// The same noise for every layer of a size, from a fixed seed.
    private static func noise(count: Int) -> Data {
        var data = Data(count: count)
        data.withUnsafeMutableBytes { raw in
            var state: UInt64 = 0x9E37_79B9_7F4A_7C15
            for offset in stride(from: 0, to: raw.count - 7, by: 8) {
                state ^= state << 13
                state ^= state >> 7
                state ^= state << 17
                raw.storeBytes(of: state, toByteOffset: offset, as: UInt64.self)
            }
        }
        return data
    }

    /// The layers that were captured, in order. A capture that found the stop flag set is
    /// not among them.
    var captured: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return capturedIDs
    }

    /// Whether the capture of this layer was asked for and is being held back.
    func isWaiting(_ layerID: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return waiting[layerID] != nil
    }

    /// From now on the capture of this layer waits for `release(_:)`.
    func hold(_ layerID: UInt64) {
        lock.lock()
        held.insert(layerID)
        lock.unlock()
    }

    func release(_ layerID: UInt64) {
        lock.lock()
        held.remove(layerID)
        let run = waiting.removeValue(forKey: layerID)
        lock.unlock()
        run?()
    }

    func detail(for layerID: UInt64) -> CapturedDetail {
        guard !missing.contains(layerID) else {
            return CapturedDetail(
                layerID: layerID,
                status: .layerNotFound,
                solo: nil,
                group: nil,
                attributeGroups: []
            )
        }
        let side = side(layerID)
        let count = side * side * 4
        let image = RawImage(
            pixelWidth: side,
            pixelHeight: side,
            bytesPerRow: side * 4,
            scale: 1,
            pixels: incompressible ? Self.noise(count: count) : Data(count: count)
        )
        return CapturedDetail(
            layerID: layerID,
            status: .ok,
            solo: nil,
            group: image,
            attributeGroups: attributeGroups(layerID),
            constraints: constraints(layerID)
        )
    }

    /// Captures a layer a moment later, on `queue`, unless the test holds it back.
    func capture(
        _ request: LayerDetailRequest,
        stopFlag: StopFlag,
        on queue: DispatchQueue,
        then answer: @escaping @Sendable (CapturedDetail?) -> Void
    ) {
        let run: @Sendable () -> Void = {
            queue.async {
                guard !stopFlag.isSet, !self.givesNil.contains(request.layerID) else {
                    return answer(nil)
                }
                self.lock.lock()
                self.capturedIDs.append(request.layerID)
                self.lock.unlock()
                answer(self.detail(for: request.layerID))
            }
        }
        lock.lock()
        let isHeld = held.contains(request.layerID)
        if isHeld { waiting[request.layerID] = run }
        lock.unlock()
        if !isHeld { run() }
    }

    /// Compresses a detail a moment later, on `queue`; nothing once the stop flag is set.
    func encode(
        _ detail: CapturedDetail,
        stopFlag: StopFlag,
        on queue: DispatchQueue,
        then answer: @escaping @Sendable (LayerDetail) -> Void
    ) {
        queue.async {
            guard !stopFlag.isSet else { return }
            self.lock.lock()
            self.compressedIDs.append(detail.layerID)
            self.lock.unlock()
            answer(detail.compressed())
        }
    }
}
