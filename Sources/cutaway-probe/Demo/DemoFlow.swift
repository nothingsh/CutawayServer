import CutawayWire
import Foundation

// The pages `--expect-demo` knows, and its steps that change the demo app and change it back.

/// What `--expect-demo` checks: the demo app's main screen, or its Lists or Extensions page
/// when that is open.
enum DemoPage {
    case screen(DemoScene)
    case lists(DemoListsScene)
    case extensions(DemoExtensionsScene)
}

/// GetSubtree and SetAttribute on the demo app's screen (PROTOCOL.md, P-HIER-10,
/// P-SET-01 to P-SET-05): the subtree of the card, and the text of the label "Push" in the
/// stack view, which pushes the block below it down. The text is changed back before the end,
/// also when a check fails on the way, so that the demo app is left as it was.
func checkDemoEditing(scene: DemoScene, hierarchy: Hierarchy, on connection: ProbeConnection) throws {
    let subtree = try HierarchyChecks.subtree(
        try request(.getSubtree(rootID: scene.card.id), id: ProbeRequestID.cardSubtree, on: connection),
        rootID: scene.card.id,
        hierarchy: hierarchy
    )
    let descendants = subtree.nodes.count - 1
    print("subtree: CardView and its \(descendants) descendant\(descendants == 1 ? "" : "s") match the hierarchy")

    let label = scene.pushLabel
    let original = AttributeValue.string("Push")
    let longer = AttributeValue.string("Pushed further down")
    func change(to value: AttributeValue, id: UInt32) throws -> Frame {
        try request(
            .setAttribute(SetAttribute(layerID: label.id, attributeID: "label.text", value: value)),
            id: id,
            on: connection
        )
    }
    var changed = true
    defer {
        // Best effort: the check that failed has already been reported.
        if changed { _ = try? change(to: original, id: ProbeRequestID.restoreTextAfterFailure) }
    }
    _ = try EditChecks.result(
        try change(to: longer, id: ProbeRequestID.lengthenText),
        layerID: label.id,
        attributeID: "label.text",
        value: longer
    )
    _ = try EditChecks.movedDown(
        try request(.getSubtree(rootID: scene.pushStack.id), id: ProbeRequestID.stackAfterLengthening, on: connection),
        rootID: scene.pushStack.id,
        movedID: scene.pushedView.id,
        hierarchy: hierarchy
    )
    _ = try EditChecks.result(
        try change(to: original, id: ProbeRequestID.restoreText),
        layerID: label.id,
        attributeID: "label.text",
        value: original
    )
    changed = false
    // Changed back, the stack view is as the hierarchy showed it.
    _ = try HierarchyChecks.subtree(
        try request(.getSubtree(rootID: scene.pushStack.id), id: ProbeRequestID.stackAfterRestoring, on: connection),
        rootID: scene.pushStack.id,
        hierarchy: hierarchy
    )
    print("set attribute: label.text changed, pushed its sibling down, and changed back")

    let frame = AttributeValue.rect(WireRect(x: 0, y: 0, width: 10, height: 10))
    try EditChecks.refusal(
        try request(
            .setAttribute(SetAttribute(layerID: label.id, attributeID: "layer.frame", value: frame)),
            id: ProbeRequestID.setReadOnlyFrame,
            on: connection
        ),
        code: .attributeNotEditable
    )
    print("set attribute: the read-only layer.frame was refused")
}

/// Lowers the compression resistance of the demo's label "Layout" so that its losing width
/// wins, then changes it back (PROTOCOL.md, P-SET-05, P-LAYOUT-03, P-LAYOUT-06).
/// The resistance is changed back before the end, also when a check fails on the way.
func checkDemoConstraints(
    _ demo: ConstraintChecks.DemoConstraints,
    hierarchy: Hierarchy,
    on connection: ProbeConnection
) throws {
    let original = AttributeValue.double(demo.compressionResistance)
    let lowered = AttributeValue.double(250)
    func change(to value: AttributeValue, id: UInt32) throws -> Frame {
        try request(
            .setAttribute(
                SetAttribute(layerID: demo.labelID, attributeID: ConstraintChecks.resistanceID, value: value)
            ),
            id: id,
            on: connection
        )
    }
    // The label's constraints alone, checked like every detail.
    func labelConstraints(id: UInt32) throws -> LayerDetail {
        let wanted = GetLayerDetails(
            requests: [
                LayerDetailRequest(
                    layerID: demo.labelID,
                    wantSolo: false,
                    wantGroup: false,
                    wantAttributes: false,
                    wantConstraints: true
                )
            ],
            maxTextureDimension: 0
        )
        let frames = try stream(.getLayerDetails(wanted), id: id, on: connection)
        return try DetailChecks.stream(frames, answering: id, request: wanted, hierarchy: hierarchy)[0]
    }
    var changed = true
    defer {
        // Best effort: the check that failed has already been reported.
        if changed { _ = try? change(to: original, id: ProbeRequestID.restoreResistanceAfterFailure) }
    }
    _ = try EditChecks.result(
        try change(to: lowered, id: ProbeRequestID.lowerResistance),
        layerID: demo.labelID,
        attributeID: ConstraintChecks.resistanceID,
        value: lowered
    )
    try ConstraintChecks.lowered(try labelConstraints(id: ProbeRequestID.constraintsLowered), demo: demo)
    _ = try EditChecks.result(
        try change(to: original, id: ProbeRequestID.restoreResistance),
        layerID: demo.labelID,
        attributeID: ConstraintChecks.resistanceID,
        value: original
    )
    changed = false
    try ConstraintChecks.restored(try labelConstraints(id: ProbeRequestID.constraintsRestored), demo: demo)
    print(
        "constraints: lowering the label's compression resistance let width == 30 win, "
            + "and changing it back restored the layout"
    )
}

/// Overrides the appearance to dark and removes the override again (PROTOCOL.md, P-ENV-01,
/// P-ENV-02). The override is removed before the end, also when a check fails on the
/// way, so that the demo app is left as it was.
func checkDemoEnvironment(_ before: Environment, on connection: ProbeConnection) throws {
    guard before.overridable.contains(.userInterfaceStyle) else {
        throw ProbeFailure("demo: the appearance cannot be overridden; every server can (P-ENV-01)")
    }
    func set(_ overrides: Traits?, id: UInt32, what: String) throws -> Environment {
        try EnvironmentChecks.environment(
            try request(.setEnvironment(overrides: overrides), id: id, on: connection),
            answering: what
        )
    }
    var changed = true
    defer {
        // Best effort: the check that failed has already been reported.
        if changed { _ = try? set(nil, id: ProbeRequestID.removeOverridesAfterFailure, what: "SetEnvironment") }
    }
    try EnvironmentChecks.dark(
        try set(Traits(userInterfaceStyle: .dark), id: ProbeRequestID.darkAppearance, what: "SetEnvironment to dark")
    )
    let restored = try set(nil, id: ProbeRequestID.removeOverrides, what: "SetEnvironment without overrides")
    changed = false
    try EnvironmentChecks.restored(restored, before: before)
    print("environment: overridden to dark, then back to the app's own")
}
