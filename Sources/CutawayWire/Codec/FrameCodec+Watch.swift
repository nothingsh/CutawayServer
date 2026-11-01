#if !canImport(UIKit) || DEBUG || ReleaseEnabled

// Hierarchy change notifications (protocol 1.3; PROTOCOL.md, P-WATCH-01 to 03): their messages
// to generated types for the object API, and back from a verified buffer.
extension FrameCodec {
    /// The messages of notifications, as `union(for:)` writes them.
    static func watchUnion(for message: Message) -> Cutaway_Wire_BodyUnion {
        switch message {
        case .watchHierarchy(let enabled):
            let object = Cutaway_Wire_WatchHierarchyT()
            object.enabled = enabled
            return Cutaway_Wire_BodyUnion(object, type: .watchhierarchy)
        case .watchHierarchyResult(let enabled):
            let object = Cutaway_Wire_WatchHierarchyResultT()
            object.enabled = enabled
            return Cutaway_Wire_BodyUnion(object, type: .watchhierarchyresult)
        case .hierarchyChanged(let changed):
            let object = Cutaway_Wire_HierarchyChangedT()
            object.roots = changed.roots
            object.whole = changed.whole
            return Cutaway_Wire_BodyUnion(object, type: .hierarchychanged)
        default:
            preconditionFailure("not a message of notifications: \(message)")
        }
    }

    /// The messages of notifications, as `message(of:)` reads them.
    static func watchMessage(of frame: Cutaway_Wire_Frame) throws -> Message {
        switch frame.bodyType {
        case .watchhierarchy:
            return .watchHierarchy(enabled: try body(of: frame, as: Cutaway_Wire_WatchHierarchy.self).enabled)
        case .watchhierarchyresult:
            return .watchHierarchyResult(enabled: try body(of: frame, as: Cutaway_Wire_WatchHierarchyResult.self)
                .enabled)
        case .hierarchychanged:
            let changed = try body(of: frame, as: Cutaway_Wire_HierarchyChanged.self)
            return .hierarchyChanged(HierarchyChanged(roots: Array(changed.roots), whole: changed.whole))
        default:
            preconditionFailure("not a message of notifications: \(frame.bodyType)")
        }
    }
}
#endif
