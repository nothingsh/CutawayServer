import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's checks of SetAttribute and of the subtrees around it: they accept what a
/// correct server sends and name what is wrong with anything else.
final class EditChecksTests: XCTestCase {
    /// Tests/CutawayProbeTests/EditChecksTests.swift -> the repository root.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func fixture(_ path: String) throws -> Frame {
        try FrameCodec.decode(
            Data(contentsOf: Self.root.appendingPathComponent("Protocol/fixtures/bin").appendingPathComponent(path))
        )
    }

    /// Asserts that the check fails and that its message contains `expected`.
    private func assertRejects(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ check: () throws -> Void
    ) {
        XCTAssertThrowsError(
            try check(),
            "expected a failure mentioning \"\(expected)\"",
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(
                "\(error)".contains(expected),
                "\"\(error)\" does not mention \"\(expected)\"",
                file: file,
                line: line
            )
        }
    }

    /// The groups of a label as the attribute list has them, with `text`.
    private func labelGroups(text: String) -> [AttributeGroup] {
        ["layer", "view", "label"].map { groupID in
            AttributeGroup(
                id: groupID,
                title: groupID,
                attributes: AttributeChecks.list[groupID]!.map { entry in
                    let id = "\(groupID).\(entry.name)"
                    let value: AttributeValue
                    switch entry.kind {
                    case .bool: value = .bool(false)
                    case .int: value = .int(1)
                    case .double: value = .double(1)
                    case .string: value = .string(id == "label.text" ? text : "Name")
                    case .color: value = .color(WireColor(red: 0, green: 0, blue: 0, alpha: 1))
                    case .point: value = .point(WirePoint(x: 0, y: 0))
                    case .size: value = .size(WireSize(width: 1, height: 1))
                    case .rect: value = .rect(WireRect(x: 0, y: 0, width: 1, height: 1))
                    case .insets: value = .insets(WireInsets(top: 0, left: 0, bottom: 0, right: 0))
                    case .transform: value = .transform(.identity)
                    case .enumeration: value = .enumeration(
                            value: 0,
                            cases: ["only"],
                            caseName: "only",
                            caseValues: [0]
                        )
                    case .none: fatalError("every attribute of the list has a kind")
                    }
                    return Attribute(
                        id: id,
                        title: entry.name,
                        value: value,
                        editable: entry.editable,
                        acceptsNil: entry.acceptsNil,
                        valueKind: entry.kind,
                        section: AttributeChecks.sections[id] ?? .general,
                        limits: entry.editable ? AttributeChecks.limits[id] ?? [] : []
                    )
                }
            )
        }
    }

    private func result(layer layerID: UInt64, text: String) -> Frame {
        Frame(
            requestID: 5,
            body: .setAttributeResult(SetAttributeResult(layerID: layerID, attributeGroups: labelGroups(text: text)))
        )
    }

    // MARK: - The answer to a change

    func test_S_PROBE_03_resultCheckAcceptsTheAnswer() throws {
        let answer = try EditChecks.result(
            result(layer: 18, text: "Pushed"),
            layerID: 18,
            attributeID: "label.text",
            value: .string("Pushed")
        )
        XCTAssertEqual(answer.layerID, 18)
    }

    func test_S_PROBE_03_resultCheckRejectsOtherAnswers() throws {
        let text = AttributeValue.string("Pushed")
        assertRejects(
            "expected SetAttributeResult, got Error(layerNotFound: no layer with id 99) with request_id 1 (P-SET-01)"
        ) {
            _ = try EditChecks.result(
                try self.fixture("set-attribute-rejected/02-s2c-error.bin"),
                layerID: 99,
                attributeID: "label.text",
                value: text
            )
        }
        assertRejects("SetAttributeResult is for layer 17, expected 18 (P-SET-01)") {
            _ = try EditChecks.result(
                self.result(layer: 17, text: "Pushed"),
                layerID: 18,
                attributeID: "label.text",
                value: text
            )
        }
        assertRejects(
            "SetAttributeResult for layer 18 has label.text = string(\"Push\"), expected string(\"Pushed\") (P-SET-01)"
        ) {
            _ = try EditChecks.result(
                self.result(layer: 18, text: "Push"),
                layerID: 18,
                attributeID: "label.text",
                value: text
            )
        }
        // The groups are checked as the details' are.
        var broken = labelGroups(text: "Pushed")
        broken[2].attributes.removeLast()
        assertRejects("group label has the attributes") {
            _ = try EditChecks.result(
                Frame(
                    requestID: 5,
                    body: .setAttributeResult(SetAttributeResult(layerID: 18, attributeGroups: broken))
                ),
                layerID: 18,
                attributeID: "label.text",
                value: text
            )
        }
        var unsound = labelGroups(text: "Pushed")
        unsound[0].attributes[7].valueKind = .none
        assertRejects("has no value_kind (P-ATTR-06)") {
            _ = try EditChecks.result(
                Frame(
                    requestID: 5,
                    body: .setAttributeResult(SetAttributeResult(layerID: 18, attributeGroups: unsound))
                ),
                layerID: 18,
                attributeID: "label.text",
                value: text
            )
        }
    }

    // MARK: - A refused change

    func test_S_PROBE_03_refusalCheckWantsTheCode() throws {
        XCTAssertNoThrow(
            try EditChecks.refusal(try fixture("set-attribute-rejected/04-s2c-error.bin"), code: .attributeNotEditable)
        )
        assertRejects("expected Error attributeNotEditable, got Error(invalidAttributeValue") {
            try EditChecks.refusal(
                try self.fixture("set-attribute-rejected/06-s2c-error.bin"),
                code: .attributeNotEditable
            )
        }
        assertRejects("expected Error attributeNotEditable, got SetAttributeResult") {
            try EditChecks.refusal(self.result(layer: 18, text: "x"), code: .attributeNotEditable)
        }
    }

    // MARK: - The layout after a change

    /// A stack view (1) with a label (2) and a block (3) below it.
    private func stack(blockAt y: Double) -> Hierarchy {
        func node(_ id: UInt64, in parentID: UInt64, y: Double) -> LayerNode {
            LayerNode(
                id: id,
                parentID: parentID,
                className: "CALayer",
                displayClassName: "CALayer",
                bounds: WireRect(x: 0, y: 0, width: 90, height: 20),
                position: WirePoint(x: 45, y: y)
            )
        }
        return Hierarchy(nodes: [node(1, in: 0, y: 18), node(2, in: 1, y: 8), node(3, in: 1, y: y)], keyWindowID: 1)
    }

    func test_S_PROBE_03_movedDownCheckWantsTheBlockLower() throws {
        let before = stack(blockAt: 27)
        XCTAssertNoThrow(
            try EditChecks.movedDown(
                Frame(requestID: 6, body: .hierarchy(stack(blockAt: 43.5))),
                rootID: 1,
                movedID: 3,
                hierarchy: before
            )
        )
        assertRejects(
            "layer 3 is at position.y 27.0 after the change, not below 27.0: the window was not laid out before the " +
                "answer (P-SET-05)"
        ) {
            _ = try EditChecks.movedDown(
                Frame(requestID: 6, body: .hierarchy(before)),
                rootID: 1,
                movedID: 3,
                hierarchy: before
            )
        }
        assertRejects("the subtree of 2 does not begin with it") {
            _ = try EditChecks.movedDown(
                Frame(requestID: 6, body: .hierarchy(self.stack(blockAt: 40))),
                rootID: 2,
                movedID: 3,
                hierarchy: before
            )
        }
        assertRejects("layer 4 is not in the subtree of 1") {
            _ = try EditChecks.movedDown(
                Frame(requestID: 6, body: .hierarchy(self.stack(blockAt: 40))),
                rootID: 1,
                movedID: 4,
                hierarchy: before
            )
        }
        assertRejects("expected Hierarchy for GetSubtree, got Error") {
            _ = try EditChecks.movedDown(
                try self.fixture("subtree/04-s2c-error.bin"),
                rootID: 1,
                movedID: 3,
                hierarchy: before
            )
        }
    }
}
