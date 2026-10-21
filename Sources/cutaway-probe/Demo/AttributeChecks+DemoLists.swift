import CutawayWire
import Foundation

// The checks of `--expect-demo` on the demo app's Lists page: the attributes of protocol 1.2.
extension AttributeChecks {
    /// What the attributes of the Lists page have to be
    /// (Demo/CutawayDemo/DemoListsViewController.swift). Call it after
    /// `DetailChecks.stream`, with the details of a request for the attributes of every layer.
    static func demoLists(_ details: [LayerDetail], hierarchy: Hierarchy, scene: DemoListsScene) throws {
        var byID: [UInt64: LayerDetail] = [:]
        for detail in details { byID[detail.layerID] = detail }

        try checkDemoLayers(hierarchy.nodes, byID: byID)

        let known: [(what: String, node: LayerNode, groups: [String])] = [
            ("the table", scene.table, ["layer", "view", "scrollView", "tableView"]),
            ("the collection view", scene.collection, ["layer", "view", "scrollView", "collectionView"]),
            ("the stack view", scene.stack, ["layer", "view", "stackView"]),
            ("the symbol", scene.symbol, ["layer", "view", "imageView"]),
            ("the Dynamic Type label", scene.dynamicLabel, ["layer", "view", "label"]),
            ("the truncated label", scene.truncatedLabel, ["layer", "view", "label"]),
            ("the button Close", scene.closeButton, ["layer", "view", "control", "button"])
        ]
        for (what, node, expected) in known {
            let ids = byID[node.id]?.attributeGroups.map(\.id) ?? []
            guard ids == expected else {
                throw ProbeFailure("demo: \(what) has the groups \(ids), expected \(expected)")
            }
        }

        func expect(_ what: String, _ node: LayerNode, _ id: String, _ expected: AttributeValue) throws {
            let actual = value(id, in: byID[node.id]?.attributeGroups ?? [])
            guard actual == expected else {
                throw ProbeFailure("demo: \(id) of \(what) is \(describe(actual)), expected \(describe(expected))")
            }
        }
        let page = ObjectReference(
            layerID: scene.page.id,
            className: "\(DemoScene.module).\(DemoListsScene.controller)",
            displayClassName: DemoListsScene.controller
        )
        // The lists, with the page's controller as their data source (P-ATTR-18).
        try expect("the table", scene.table, "tableView.dataSource", .layerReference([page]))
        try expect("the table", scene.table, "tableView.numberOfSections", .int(2))
        try expect("the table", scene.table, "tableView.numberOfRows", .int(8))
        try expect("the table", scene.table, "tableView.rowsPerSection", .string("3, 5"))
        try expect("the collection view", scene.collection, "collectionView.dataSource", .layerReference([page]))
        try expect("the collection view", scene.collection, "collectionView.numberOfSections", .int(2))
        try expect("the collection view", scene.collection, "collectionView.numberOfItems", .int(6))
        try expect("the collection view", scene.collection, "collectionView.itemsPerSection", .string("4, 2"))
        for (what, node, id) in [
            ("the table", scene.table, "tableView.visibleIndexPaths"),
            ("the collection view", scene.collection, "collectionView.visibleIndexPaths")
        ] {
            let visible = value(id, in: byID[node.id]?.attributeGroups ?? [])
            guard case .string(let text)? = visible, text.hasPrefix("0.0") else {
                throw ProbeFailure("demo: \(id) of \(what) is \(describe(visible)), expected it to begin with 0.0")
            }
        }
        // The stack view's arranged subviews are its three labels, in order.
        guard scene.arranged.count == 3 else {
            throw ProbeFailure("demo: the stack view has \(scene.arranged.count) subviews, expected 3")
        }
        let labels = scene.arranged.map {
            ObjectReference(layerID: $0.id, className: "UILabel", displayClassName: "UILabel")
        }
        try expect("the stack view", scene.stack, "stackView.arrangedSubviews", .layerReference(labels))
        try expect("the stack view", scene.stack, "stackView.customSpacing", .string("after 0: 12"))
        // An image, a font, lines and accessibility.
        try expect("the symbol", scene.symbol, "imageView.imageName", .string("star.fill"))
        try expect("the Dynamic Type label", scene.dynamicLabel, "label.fontTextStyle", .string("body"))
        try expect(
            "the Dynamic Type label",
            scene.dynamicLabel,
            "label.adjustsFontForContentSizeCategory",
            .bool(true)
        )
        try expect("the truncated label", scene.truncatedLabel, "label.drawnLineCount", .int(2))
        try expect("the truncated label", scene.truncatedLabel, "label.isTruncated", .bool(true))
        try expect("the button Close", scene.closeButton, "view.accessibilityLabel", .string("Close the lists"))
    }
}
