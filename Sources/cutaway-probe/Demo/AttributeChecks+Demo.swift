import CutawayWire
import Foundation

// The checks of `--expect-demo`: what the demo app's screen has to look like.
extension AttributeChecks {
    // MARK: - The demo app's screen

    /// What the attributes of the demo app's screen have to be
    /// (Demo/CutawayDemo/DemoViewController.swift). Call it after `DetailChecks.stream` and
    /// `HierarchyChecks.demoScene`, with the details of a request for the attributes of every
    /// layer.
    static func demo(_ details: [LayerDetail], hierarchy: Hierarchy, scene: DemoScene) throws {
        var byID: [UInt64: LayerDetail] = [:]
        for detail in details { byID[detail.layerID] = detail }

        try checkDemoLayers(hierarchy.nodes, byID: byID)

        let known: [(what: String, node: LayerNode, groups: [String])] = [
            ("the key window", scene.window, ["layer", "view"]),
            ("the label CutawayDemo", scene.titleLabel, ["layer", "view", "label"]),
            ("CardView", scene.card, ["layer", "view"]),
            ("the CAShapeLayer", scene.badge, ["layer"]),
            ("the scroll view", scene.scrollView, ["layer", "view", "scrollView"]),
            ("the label Scrolled", scene.scrolledLabel, ["layer", "view", "label"]),
            ("the bare layer", scene.bareLayer, ["layer"]),
            ("the empty view", scene.emptyView, ["layer", "view"]),
            ("the stack view", scene.pushStack, ["layer", "view", "stackView"]),
            ("the label Push", scene.pushLabel, ["layer", "view", "label"]),
            ("the label Layout", scene.layoutLabel, ["layer", "view", "label"])
        ]
        for (what, node, expected) in known {
            let ids = byID[node.id]?.attributeGroups.map(\.id) ?? []
            guard ids == expected else {
                throw ProbeFailure("demo: \(what) has the groups \(ids), expected \(expected)")
            }
        }

        func expect(_ what: String, _ node: LayerNode, _ id: String, _ expected: AttributeValue) throws {
            let actual = value(id, in: byID[node.id]?.attributeGroups ?? [])
            let matches: Bool
            if case let .color(actualColor, _, _, _, _)? = actual,
               case let .color(expectedColor, _, _, _, _) = expected {
                // Colours went through a colour space conversion.
                matches = zip(
                    [actualColor.red, actualColor.green, actualColor.blue, actualColor.alpha],
                    [expectedColor.red, expectedColor.green, expectedColor.blue, expectedColor.alpha]
                )
                .allSatisfy { abs($0 - $1) <= 1 / 255 }
            } else {
                matches = actual == expected
            }
            guard matches else {
                throw ProbeFailure("demo: \(id) of \(what) is \(describe(actual)), expected \(describe(expected))")
            }
        }
        // The labels the editing and the constraint steps work on are each the only one with
        // their text.
        for text in ["Push", "Layout"] {
            let labels = details.filter { value("label.text", in: $0.attributeGroups) == .string(text) }.count
            guard labels == 1 else {
                throw ProbeFailure("demo: expected one label with the text \"\(text)\", found \(labels)")
            }
        }
        try expect("the label CutawayDemo", scene.titleLabel, "label.text", .string("CutawayDemo"))
        try expect(
            "the label CutawayDemo",
            scene.titleLabel,
            "label.textColor",
            .color(WireColor(red: 0, green: 0, blue: 0, alpha: 1))
        )
        try expect("the label Scrolled", scene.scrolledLabel, "label.text", .string("Scrolled"))
        try expect("CardView", scene.card, "view.clipsToBounds", .bool(true))
        try expect("CardView", scene.card, "view.clipsToBounds", .bool(true))
        try expect("the CAShapeLayer", scene.badge, "layer.hidden", .bool(true))
        try expect("the CAShapeLayer", scene.badge, "layer.opacity", .double(0.5))
        try expect("the scroll view", scene.scrollView, "scrollView.contentOffset", .point(WirePoint(x: 0, y: 100)))
        try expect(
            "the scroll view",
            scene.scrollView,
            "scrollView.contentSize",
            .size(WireSize(width: 300, height: 600))
        )
        try expect(
            "the scroll view",
            scene.scrollView,
            "scrollView.contentInset",
            .insets(WireInsets(top: 0, left: 0, bottom: 0, right: 0))
        )
        try expect(
            "the bare layer",
            scene.bareLayer,
            "layer.backgroundColor",
            .color(WireColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        )
        try expect("the bare layer", scene.bareLayer, "layer.anchorPoint", .point(WirePoint(x: 0, y: 0)))
        // The labels the editing and the constraint steps work on.
        try expect("the label Push", scene.pushLabel, "label.text", .string("Push"))
        try expect("the label Layout", scene.layoutLabel, "label.text", .string("Layout"))
    }

    /// Every layer of one of the demo app's pages: the groups of the list, `layer` first and
    /// `view` second for a view, and geometry that agrees with the hierarchy. The host app's
    /// groups follow, and virtual nodes have only those: the demo's checks of its Extensions
    /// page look at them.
    static func checkDemoLayers(_ nodes: [LayerNode], byID: [UInt64: LayerDetail]) throws {
        for node in nodes where node.nodeKind == .layer {
            let name = "demo: layer \(node.id) (\(node.viewClassName ?? node.className))"
            guard let groups = byID[node.id]?.attributeGroups.filter({ !$0.fromApp }) else {
                throw ProbeFailure("\(name) has no detail")
            }
            let ids = groups.map(\.id)
            if node.viewClassName == nil {
                guard ids == ["layer"] else {
                    throw ProbeFailure("\(name) backs no view and has the groups \(ids), expected [\"layer\"]")
                }
            } else {
                guard ids.count >= 2, ids[0] == "layer", ids[1] == "view" else {
                    throw ProbeFailure(
                        "\(name) backs a view and has the groups \(ids); they must begin with layer, view"
                    )
                }
            }
            for group in groups { try matchesList(group, name: name, backsView: node.viewClassName != nil) }
            let geometry: [(String, AttributeValue)] = [
                ("layer.bounds", .rect(node.bounds)),
                ("layer.position", .point(node.position)),
                ("layer.anchorPoint", .point(node.anchorPoint)),
                ("layer.transform", .transform(node.transform)),
                ("layer.zPosition", .double(node.zPosition))
            ] + (
                // P-ATTR-11: a view's attribute of each pair stands for its layer's.
                node.viewClassName == nil
                    ? [
                        ("layer.hidden", .bool(node.isHidden)),
                        ("layer.opacity", .double(Double(node.opacity))),
                        ("layer.masksToBounds", .bool(node.masksToBounds))
                    ]
                    : [
                        ("view.isHidden", .bool(node.isHidden)),
                        ("view.alpha", .double(Double(node.opacity))),
                        ("view.clipsToBounds", .bool(node.masksToBounds))
                    ]
            )
            for (id, expected) in geometry {
                let actual = value(id, in: groups)
                guard actual == expected else {
                    throw ProbeFailure(
                        "\(name): \(id) is \(describe(actual)), but the hierarchy says \(describe(expected))"
                    )
                }
            }
        }
    }

    static func describe(_ value: AttributeValue?) -> String {
        value.map { "\($0)" } ?? "nil"
    }
}
