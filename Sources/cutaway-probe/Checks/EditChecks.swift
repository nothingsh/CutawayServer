import CutawayWire
import Foundation

/// What the answers to `SetAttribute`, and the subtrees read around them, have to look like
/// (PROTOCOL.md, P-SET-01 to P-SET-05). Every function throws a `ProbeFailure` naming the
/// first thing that is wrong.
enum EditChecks {
    /// The answer to a change of `attributeID` on the layer `layerID`: all of the layer's
    /// groups, sound and, apart from the host app's, as the attribute list has them, with the
    /// attribute at `value` (P-SET-01).
    static func result(
        _ frame: Frame,
        layerID: UInt64,
        attributeID: String,
        value: AttributeValue
    ) throws -> SetAttributeResult {
        guard case .setAttributeResult(let result)? = frame.body else {
            throw ProbeFailure("expected SetAttributeResult, got \(Checks.describe(frame)) (P-SET-01)")
        }
        guard result.layerID == layerID else {
            throw ProbeFailure("SetAttributeResult is for layer \(result.layerID), expected \(layerID) (P-SET-01)")
        }
        let name = "SetAttributeResult for layer \(layerID)"
        try AttributeChecks.structure(result.attributeGroups, name: name)
        let backsView = result.attributeGroups.contains { $0.id == "view" }
        for group in result.attributeGroups where !group.fromApp {
            try AttributeChecks.matchesList(group, name: name, backsView: backsView)
        }
        let actual = AttributeChecks.value(attributeID, in: result.attributeGroups)
        guard actual == value else {
            throw ProbeFailure(
                "\(name) has \(attributeID) = \(actual.map { "\($0)" } ?? "nil"), expected \(value) (P-SET-01)"
            )
        }
        return result
    }

    /// The answer to a change that has to be refused with `code` (P-SET-03).
    static func refusal(_ frame: Frame, code: ErrorCode) throws {
        guard case .error(let error)? = frame.body, error.code == code else {
            throw ProbeFailure("expected Error \(code), got \(Checks.describe(frame)) (P-SET-03)")
        }
    }

    /// The subtree of `rootID` read after a change that moved the layer `movedID` down within
    /// it: the server laid the window out before it answered (P-SET-05).
    static func movedDown(
        _ frame: Frame,
        rootID: UInt64,
        movedID: UInt64,
        hierarchy: Hierarchy
    ) throws -> Hierarchy {
        guard case .hierarchy(let subtree)? = frame.body else {
            throw ProbeFailure("expected Hierarchy for GetSubtree, got \(Checks.describe(frame)) (P-HIER-10)")
        }
        guard subtree.nodes.first?.id == rootID else {
            throw ProbeFailure("the subtree of \(rootID) does not begin with it (P-HIER-10)")
        }
        guard let before = hierarchy.nodes.first(where: { $0.id == movedID }),
              let after = subtree.nodes.first(where: { $0.id == movedID })
        else { throw ProbeFailure("layer \(movedID) is not in the subtree of \(rootID) (P-HIER-10)") }
        guard after.position.y > before.position.y else {
            throw ProbeFailure(
                "layer \(movedID) is at position.y \(after.position.y) after the change, not below "
                    + "\(before.position.y): the window was not laid out before the answer (P-SET-05)"
            )
        }
        return subtree
    }
}
