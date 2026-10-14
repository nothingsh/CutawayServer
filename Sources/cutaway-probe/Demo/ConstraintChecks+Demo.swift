import CutawayWire
import Foundation

// The checks of `--expect-demo`: what the demo app's screen has to look like.
extension ConstraintChecks {
    // MARK: - The demo app's screen

    /// The demo's label "Layout" as the full stream found it, for the step that changes its
    /// compression resistance (Demo/CutawayDemo/DemoViewController.swift).
    struct DemoConstraints: Equatable {
        var labelID: UInt64
        var labelConstraints: [LayoutConstraint]
        /// The constraints the demo's code makes: to the safe area's top and trailing, and
        /// `width == 30` at 500.
        var handwrittenIDs: [UInt64]
        var narrowID: UInt64
        /// The label's horizontal compression resistance.
        var compressionResistance: Double
    }

    static let resistanceID = "view.contentCompressionResistancePriority.horizontal"
    private static let autoresizing = "NSAutoresizingMaskLayoutConstraint"

    /// The demo's known constraints: the label "Layout" tied to
    /// the safe area, its losing `width == 30`, and the constraints UIKit makes from the
    /// autoresizing mask of `autoresizingBox`. Call it after `HierarchyChecks.demoScene` and
    /// `DetailChecks.stream`, with the details of a request for the attributes and the
    /// constraints of every layer, and the nodes the scene found: the screen's view, the
    /// label "Layout" and the box.
    static func demo(
        _ details: [LayerDetail],
        screen: LayerNode,
        layoutLabel: LayerNode,
        box: LayerNode
    ) throws -> DemoConstraints {
        guard let label = details.first(where: { $0.layerID == layoutLabel.id }) else {
            throw ProbeFailure("demo: there is no detail for the label \"Layout\" (layer \(layoutLabel.id))")
        }
        guard let boxDetail = details.first(where: { $0.layerID == box.id }) else {
            throw ProbeFailure("demo: there is no detail for autoresizingBox (layer \(box.id))")
        }
        guard case .double(let resistance)? = AttributeChecks.value(resistanceID, in: label.attributeGroups)
        else { throw ProbeFailure("demo: the label \"Layout\" has no \(resistanceID)") }

        let (top, trailing, narrow) = try demoLabelConstraints(of: label, screen: screen)

        // P-LAYOUT-01: also listed for the guide's owner.
        let screenIDs = Set(details.first(where: { $0.layerID == screen.id })?.constraints.map(\.id) ?? [])
        guard screenIDs.contains(top.id), screenIDs.contains(trailing.id) else {
            throw ProbeFailure(
                "demo: the label's constraints to the safe area are not also in the detail of the screen's view, "
                    + "which owns the guide (P-LAYOUT-01)"
            )
        }

        try checkDemoAutoresizing(of: box, detail: boxDetail, screen: screen)

        return DemoConstraints(
            labelID: label.layerID,
            labelConstraints: label.constraints,
            handwrittenIDs: [top.id, trailing.id, narrow.id],
            narrowID: narrow.id,
            compressionResistance: resistance
        )
    }

    /// The constraints the demo's code makes on the label "Layout": to the safe area's top and
    /// trailing, and `width == 30` at 500.
    private static func demoLabelConstraints(
        of label: LayerDetail,
        screen: LayerNode
    ) throws -> (top: LayoutConstraint, trailing: LayoutConstraint, narrow: LayoutConstraint) {
        let labelItem = LayoutItem(kind: .view, layerID: label.layerID)
        // The one constraint of the label that `matches`, compared with what the demo makes.
        func expect(
            _ what: String,
            _ status: ConstraintStatus,
            expected: (LayoutConstraint) -> LayoutConstraint,
            matches: (LayoutConstraint) -> Bool
        ) throws -> LayoutConstraint {
            let found = label.constraints.filter(matches)
            guard found.count == 1, let constraint = found.first else {
                throw ProbeFailure("demo: the label \"Layout\" has \(found.count) constraints like \(what), expected 1")
            }
            guard constraint == expected(constraint) else {
                throw ProbeFailure(
                    "demo: \(what) is \(describe(constraint)), expected \(describe(expected(constraint)))"
                )
            }
            guard constraint.status == status else {
                throw ProbeFailure("demo: \(what) has status \(constraint.status), expected \(status) (P-LAYOUT-06)")
            }
            return constraint
        }
        func isSafeArea(_ item: LayoutItem?) -> Bool {
            item?.kind == .layoutGuide && item?.layerID == screen.id && item?.className == "UILayoutGuide"
                && item?.identifier == "UIViewSafeAreaLayoutGuide" && item?.guideKind == .safeArea
        }
        func toSafeArea(_ attribute: LayoutAttribute, _ constant: Double) -> (LayoutConstraint) -> LayoutConstraint {
            { found in
                LayoutConstraint(
                    id: found.id,
                    className: "NSLayoutConstraint",
                    firstItem: labelItem,
                    firstAttribute: attribute,
                    relation: .equal,
                    secondItem: isSafeArea(found.secondItem) ? found.secondItem : nil,
                    secondAttribute: attribute,
                    multiplier: 1,
                    constant: constant,
                    priority: 1000,
                    status: found.status,
                    // The demo's own (P-LAYOUT-09).
                    origin: .app
                )
            }
        }
        let top = try expect("layoutLabel.top == safe area.top + 8", .satisfied, expected: toSafeArea(.top, 8)) {
            $0.firstItem == labelItem && $0.firstAttribute == .top
        }
        let trailing = try expect(
            "layoutLabel.trailing == safe area.trailing - 16",
            .satisfied,
            expected: toSafeArea(.trailing, -16)
        ) { $0.firstItem == labelItem && $0.firstAttribute == .trailing }
        let narrow = try expect(
            "layoutLabel.width == 30 @500",
            .unsatisfied,
            expected: { found in
                LayoutConstraint(
                    id: found.id,
                    className: "NSLayoutConstraint",
                    firstItem: labelItem,
                    firstAttribute: .width,
                    relation: .equal,
                    multiplier: 1,
                    constant: 30,
                    priority: 500,
                    status: found.status,
                    origin: .app
                )
            },
            matches: { constraint in
                constraint.firstItem == labelItem && constraint.firstAttribute == .width
                    && constraint.className == "NSLayoutConstraint"
            }
        )
        return (top, trailing, narrow)
    }

    /// UIKit's constraints for the mask of the demo's `autoresizingBox`, a flexible left and
    /// bottom margin (P-LAYOUT-07).
    private static func checkDemoAutoresizing(
        of box: LayerNode,
        detail boxDetail: LayerDetail,
        screen: LayerNode
    ) throws {
        let boxItem = LayoutItem(kind: .view, layerID: box.id)
        func made(
            _ first: LayoutItem,
            _ attribute: LayoutAttribute,
            _ second: LayoutItem?,
            _ secondAttribute: LayoutAttribute,
            _ constant: Double,
            _ status: ConstraintStatus
        ) -> LayoutConstraint {
            LayoutConstraint(
                id: 0,
                className: autoresizing,
                firstItem: first,
                firstAttribute: attribute,
                relation: .equal,
                secondItem: second,
                secondAttribute: secondAttribute,
                multiplier: 1,
                constant: constant,
                priority: 1000,
                status: status,
                // UIKit's (P-LAYOUT-09).
                origin: .system
            )
        }
        let expected = [
            made(
                LayoutItem(kind: .view, layerID: screen.id),
                .width,
                boxItem,
                .maxX,
                screen.bounds.size.width - 360,
                .unknown
            ),
            made(boxItem, .minY, nil, .notAnAttribute, 100, .unknown),
            made(boxItem, .width, nil, .notAnAttribute, 60, .satisfied),
            made(boxItem, .height, nil, .notAnAttribute, 24, .satisfied)
        ]
        let actual = boxDetail.constraints.filter { $0.className == autoresizing }.map(withoutID)
        guard sameElements(actual, expected) else {
            throw ProbeFailure(
                "demo: the autoresizing mask constraints of autoresizingBox are [\(actual.map(describe).joined(separator: "; "))], "
                    + "expected [\(expected.map(describe).joined(separator: "; "))] (P-LAYOUT-07)"
            )
        }
    }

    /// The label's constraints after its compression resistance was lowered below 500: the
    /// width it did not get wins, under the same ID (P-SET-05, P-LAYOUT-03, P-LAYOUT-06).
    static func lowered(_ detail: LayerDetail, demo: DemoConstraints) throws {
        guard let narrow = detail.constraints.first(where: { $0.id == demo.narrowID }) else {
            throw ProbeFailure(
                "demo: after lowering the compression resistance, the label has no width == 30 @500 with id \(demo.narrowID) (P-LAYOUT-03)"
            )
        }
        guard narrow.status == .satisfied else {
            throw ProbeFailure(
                "demo: after lowering the compression resistance, width == 30 @500 has status \(narrow.status), expected Satisfied (P-SET-05, P-LAYOUT-06)"
            )
        }
    }

    /// The label's constraints after its compression resistance was changed back: as before,
    /// in any order. UIKit replaces its content size constraints, so only the constraints the
    /// demo's code makes have to keep their IDs.
    static func restored(_ detail: LayerDetail, demo: DemoConstraints) throws {
        let ids = Set(detail.constraints.map(\.id))
        for id in demo.handwrittenIDs where !ids.contains(id) {
            throw ProbeFailure(
                "demo: after changing back the compression resistance, constraint \(id) is missing (P-LAYOUT-03)"
            )
        }
        guard sameElements(detail.constraints.map(withoutID), demo.labelConstraints.map(withoutID)) else {
            throw ProbeFailure(
                "demo: after changing back the compression resistance, the label's constraints are "
                    + "[\(detail.constraints.map(describe).joined(separator: "; "))], expected those from before: "
                    + "[\(demo.labelConstraints.map(describe).joined(separator: "; "))]"
            )
        }
    }

    private static func withoutID(_ constraint: LayoutConstraint) -> LayoutConstraint {
        var copy = constraint
        copy.id = 0
        return copy
    }

    /// Whether both hold the same constraints, each as often, in any order.
    private static func sameElements(_ one: [LayoutConstraint], _ other: [LayoutConstraint]) -> Bool {
        var rest = other
        for constraint in one {
            guard let index = rest.firstIndex(of: constraint) else { return false }
            rest.remove(at: index)
        }
        return rest.isEmpty
    }

    /// "first.attribute relation second.attribute * multiplier + constant @priority, status".
    static func describe(_ constraint: LayoutConstraint) -> String {
        func item(_ item: LayoutItem?) -> String {
            guard let item else { return "nil" }
            switch item.kind {
            case .view: return "layer \(item.layerID)"
            case .layoutGuide: return "guide \(item.identifier ?? "\(item.guideID)") of layer \(item.layerID)"
            case .other: return item.displayClassName ?? "?"
            }
        }
        var text = "\(item(constraint.firstItem)).\(constraint.firstAttribute) \(constraint.relation)"
        if constraint.secondItem != nil {
            text += " \(item(constraint.secondItem)).\(constraint.secondAttribute) * \(constraint.multiplier) +"
        }
        return text + " \(constraint.constant) @\(constraint.priority), \(constraint.status)"
    }
}
