import CutawayWire
import UIKit

@testable import CutawayServer

/// A host app whose work tests replace one piece at a time. Each closure starts as the
/// base's, so that a test can wrap it.
struct TestHostApp: HostApp {
    private let base: any HostApp
    var appState: @MainActor @Sendable () -> AppState
    var environmentControl: @Sendable () -> any EnvironmentControl
    var captureHierarchy: @MainActor @Sendable (RequestContext) -> Hierarchy
    var captureSubtree: @MainActor @Sendable (UInt64, RequestContext) -> Hierarchy?
    var setAttribute:
        @MainActor @Sendable (SetAttribute, RequestContext) -> Result<SetAttributeResult, WireError>
    var captureDetail:
        @MainActor @Sendable (LayerDetailRequest, UInt32, RequestContext, StopFlag) -> CapturedDetail?

    init(_ base: any HostApp = LiveHostApp()) {
        self.base = base
        appState = { base.currentAppState() }
        environmentControl = { base.makeEnvironmentControl() }
        captureHierarchy = { base.captureHierarchy(in: $0) }
        captureSubtree = { base.captureSubtree(of: $0, in: $1) }
        setAttribute = { base.setAttribute($0, in: $1) }
        captureDetail = {
            base.captureDetail($0, maxTextureDimension: $1, in: $2, stopFlag: $3)
        }
    }

    // No test replaces these.

    @MainActor
    func appInfo() -> AppInfo {
        base.appInfo()
    }

    @MainActor
    func iconImage() -> UIImage? {
        base.iconImage()
    }

    @MainActor
    func makeRequestContext(
        for connection: ConnectionContext,
        version: ProtocolVersion,
        memo: RequestMemo
    ) -> RequestContext {
        base.makeRequestContext(for: connection, version: version, memo: memo)
    }

    // These call the closures above.

    @MainActor
    func currentAppState() -> AppState {
        appState()
    }

    func makeEnvironmentControl() -> any EnvironmentControl {
        environmentControl()
    }

    @MainActor
    func captureHierarchy(in context: RequestContext) -> Hierarchy {
        captureHierarchy(context)
    }

    @MainActor
    func captureSubtree(of rootID: UInt64, in context: RequestContext) -> Hierarchy? {
        captureSubtree(rootID, context)
    }

    @MainActor
    func setAttribute(_ change: SetAttribute, in context: RequestContext)
        -> Result<SetAttributeResult, WireError> {
        setAttribute(change, context)
    }

    @MainActor
    func captureDetail(
        _ request: LayerDetailRequest,
        maxTextureDimension: UInt32,
        in context: RequestContext,
        stopFlag: StopFlag
    ) -> CapturedDetail? {
        captureDetail(request, maxTextureDimension, context, stopFlag)
    }
}
