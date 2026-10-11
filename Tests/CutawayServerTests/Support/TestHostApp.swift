import CutawayWire
import UIKit

@testable import CutawayServer

/// A host app whose work tests replace one piece at a time. Each closure starts as the
/// base's, so that a test can wrap it.
struct TestHostApp: HostApp {
    private let base: any HostApp
    var captureHierarchy: @MainActor @Sendable (LayerRegistry) -> Hierarchy
    var captureSubtree: @MainActor @Sendable (UInt64, LayerRegistry) -> Hierarchy?
    var setAttribute:
        @MainActor @Sendable (SetAttribute, LayerRegistry) -> Result<SetAttributeResult, WireError>
    var captureDetail:
        @MainActor @Sendable (LayerDetailRequest, UInt32, LayerRegistry, StopFlag) -> CapturedDetail?

    init(_ base: any HostApp = LiveHostApp()) {
        self.base = base
        captureHierarchy = { base.captureHierarchy(registry: $0) }
        captureSubtree = { base.captureSubtree(of: $0, registry: $1) }
        setAttribute = { base.setAttribute($0, registry: $1) }
        captureDetail = {
            base.captureDetail($0, maxTextureDimension: $1, registry: $2, stopFlag: $3)
        }
    }

    // No test replaces these two.

    @MainActor
    func appInfo() -> AppInfo {
        base.appInfo()
    }

    @MainActor
    func iconImage() -> UIImage? {
        base.iconImage()
    }

    @MainActor
    func captureHierarchy(registry: LayerRegistry) -> Hierarchy {
        captureHierarchy(registry)
    }

    @MainActor
    func captureSubtree(of rootID: UInt64, registry: LayerRegistry) -> Hierarchy? {
        captureSubtree(rootID, registry)
    }

    @MainActor
    func setAttribute(_ change: SetAttribute, registry: LayerRegistry)
        -> Result<SetAttributeResult, WireError> {
        setAttribute(change, registry)
    }

    @MainActor
    func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        registry: LayerRegistry,
        stopFlag: StopFlag
    ) -> CapturedDetail? {
        captureDetail(request, maxTextureDimension, registry, stopFlag)
    }
}
