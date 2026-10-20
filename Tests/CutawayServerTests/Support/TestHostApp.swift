import CutawayWire
import UIKit

@testable import CutawayServer

/// A host app whose work tests replace one piece at a time. Each closure starts as the
/// base's, so that a test can wrap it.
struct TestHostApp: HostApp {
    private let base: any HostApp
    var captureHierarchy: @MainActor @Sendable (LayerRegistry, ProtocolVersion) -> Hierarchy
    var captureSubtree: @MainActor @Sendable (UInt64, LayerRegistry, ProtocolVersion) -> Hierarchy?
    var setAttribute:
        @MainActor @Sendable (SetAttribute, LayerRegistry) -> Result<SetAttributeResult, WireError>
    var captureDetail:
        @MainActor @Sendable (LayerDetailRequest, UInt32, LayerRegistry, StopFlag) -> CapturedDetail?
    var setEnvironment: @MainActor @Sendable (Traits, EnvironmentOverrides) -> WireError?
    var settleEnvironment: @MainActor @Sendable (EnvironmentOverrides) -> Environment

    init(_ base: any HostApp = LiveHostApp()) {
        self.base = base
        captureHierarchy = { base.captureHierarchy(registry: $0, version: $1) }
        captureSubtree = { base.captureSubtree(of: $0, registry: $1, version: $2) }
        setAttribute = { base.setAttribute($0, registry: $1) }
        captureDetail = {
            base.captureDetail($0, maxTextureDimension: $1, registry: $2, stopFlag: $3)
        }
        setEnvironment = { base.setEnvironment($0, overrides: $1) }
        settleEnvironment = { base.settleEnvironment(overrides: $0) }
    }

    // No test replaces these.

    @MainActor
    func environment(overrides: EnvironmentOverrides) -> Environment {
        base.environment(overrides: overrides)
    }

    @MainActor
    func setEnvironment(_ traits: Traits, overrides: EnvironmentOverrides) -> WireError? {
        setEnvironment(traits, overrides)
    }

    @MainActor
    func settleEnvironment(overrides: EnvironmentOverrides) -> Environment {
        settleEnvironment(overrides)
    }

    @MainActor
    func removeOverrides(_ overrides: EnvironmentOverrides) {
        base.removeOverrides(overrides)
    }

    @MainActor
    func appInfo() -> AppInfo {
        base.appInfo()
    }

    @MainActor
    func iconImage() -> UIImage? {
        base.iconImage()
    }

    @MainActor
    func captureHierarchy(registry: LayerRegistry, version: ProtocolVersion) -> Hierarchy {
        captureHierarchy(registry, version)
    }

    @MainActor
    func captureSubtree(of rootID: UInt64, registry: LayerRegistry, version: ProtocolVersion) -> Hierarchy? {
        captureSubtree(rootID, registry, version)
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
