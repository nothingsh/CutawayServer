import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// The probe's checks of the demo app's Lists page: they accept the page as a
/// correct server reports it and name what is wrong with anything else.
final class AttributeChecksDemoListsTests: XCTestCase {
    private func reference(_ name: String) -> MemberReference {
        DemoReferences.reference(name, owner: DemoListsScene.controller)
    }

    private func node(
        _ id: UInt64,
        in parentID: UInt64,
        _ viewClass: String,
        held name: String? = nil,
        layerClass: String = "CALayer"
    ) -> LayerNode {
        var node = LayerNode(
            id: id,
            parentID: parentID,
            className: layerClass,
            displayClassName: layerClass,
            viewClassName: viewClass,
            viewDisplayClassName: viewClass,
            bounds: WireRect(x: 0, y: 0, width: 100, height: 40),
            position: WirePoint(x: 50, y: 50)
        )
        if let name { node.memberReferences = [reference(name)] }
        return node
    }

    private struct Page {
        var hierarchy: Hierarchy
        var details: [LayerDetail]
    }

    /// The Lists page as a correct server reports it.
    private func page(_ change: (inout [UInt64: [String: AttributeValue]]) -> Void = { _ in }) -> Page {
        var root = node(2, in: 1, "UIView")
        root.viewControllerClassName = "CutawayDemo.DemoListsViewController"
        root.viewControllerDisplayClassName = "DemoListsViewController"
        let nodes = [
            node(1, in: 0, "UIWindow", layerClass: "UIWindowLayer"),
            root,
            node(3, in: 2, "UIButton", held: "closeButton"),
            node(4, in: 2, "UITableView", held: "listsTable"),
            node(5, in: 2, "UICollectionView", held: "listsCollection"),
            node(6, in: 2, "UIStackView", held: "spacedStack", layerClass: "CATransformLayer"),
            node(7, in: 6, "UILabel"),
            node(8, in: 6, "UILabel"),
            node(9, in: 6, "UILabel"),
            node(10, in: 2, "UIImageView", held: "symbolView"),
            node(11, in: 2, "UILabel", held: "dynamicLabel"),
            node(12, in: 2, "UILabel", held: "truncatedLabel")
        ]
        let controller = ObjectReference(
            layerID: 2,
            className: "CutawayDemo.DemoListsViewController",
            displayClassName: "DemoListsViewController"
        )
        var values: [UInt64: [String: AttributeValue]] = [
            3: ["view.accessibilityLabel": .string("Close the lists")],
            4: [
                "tableView.dataSource": .layerReference([controller]),
                "tableView.numberOfSections": .int(2),
                "tableView.numberOfRows": .int(8),
                "tableView.rowsPerSection": .string("3, 5"),
                "tableView.visibleIndexPaths": .string("0.0, 0.1, 0.2, 1.0")
            ],
            5: [
                "collectionView.dataSource": .layerReference([controller]),
                "collectionView.numberOfSections": .int(2),
                "collectionView.numberOfItems": .int(6),
                "collectionView.itemsPerSection": .string("4, 2"),
                "collectionView.visibleIndexPaths": .string("0.0, 0.1, 0.2, 0.3, 1.0, 1.1")
            ],
            6: [
                "stackView.arrangedSubviews": .layerReference([7, 8, 9].map {
                    ObjectReference(layerID: $0, className: "UILabel", displayClassName: "UILabel")
                }),
                "stackView.customSpacing": .string("after 0: 12")
            ],
            10: ["imageView.imageName": .string("star.fill")],
            11: ["label.fontTextStyle": .string("body"), "label.adjustsFontForContentSizeCategory": .bool(true)],
            12: ["label.drawnLineCount": .int(2), "label.isTruncated": .bool(true)]
        ]
        change(&values)
        let groupIDs: [String: [String]] = [
            "UIButton": ["layer", "view", "control", "button"],
            "UITableView": ["layer", "view", "scrollView", "tableView"],
            "UICollectionView": ["layer", "view", "scrollView", "collectionView"],
            "UIStackView": ["layer", "view", "stackView"],
            "UIImageView": ["layer", "view", "imageView"],
            "UILabel": ["layer", "view", "label"]
        ]
        let details = nodes.map { node in
            var known: [String: AttributeValue] = [
                "layer.bounds": .rect(node.bounds),
                "layer.position": .point(node.position),
                "layer.anchorPoint": .point(node.anchorPoint),
                "layer.transform": .transform(node.transform),
                "layer.zPosition": .double(node.zPosition),
                "view.isHidden": .bool(node.isHidden),
                "view.alpha": .double(Double(node.opacity)),
                "view.clipsToBounds": .bool(node.masksToBounds)
            ]
            known.merge(values[node.id] ?? [:]) { $1 }
            let ids = groupIDs[node.viewClassName ?? ""] ?? ["layer", "view"]
            return LayerDetail(
                layerID: node.id,
                status: .ok,
                attributeGroups: ids.map { groupID in
                    AttributeChecks.listedGroup(groupID, backsView: true) { id, entry in
                        known[id] ?? (entry.nullable ? nil : Self.placeholder(entry.kind))
                    }
                }
            )
        }
        return Page(hierarchy: Hierarchy(nodes: nodes, keyWindowID: 1), details: details)
    }

    private static func placeholder(_ kind: AttributeValueKind) -> AttributeValue {
        switch kind {
        case .bool: .bool(false)
        case .int: .int(0)
        case .double: .double(1)
        case .color: .color(WireColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        case .point: .point(WirePoint(x: 1, y: 2))
        case .size: .size(WireSize(width: 3, height: 4))
        case .rect: .rect(WireRect(x: 1, y: 2, width: 3, height: 4))
        case .insets: .insets(WireInsets(top: 1, left: 2, bottom: 3, right: 4))
        case .transform: .transform(.identity)
        case .enumeration: .enumeration(value: 0, cases: ["only"], caseName: "only", caseValues: [0])
        case .layerReference: .layerReference([])
        case .none, .string: .string("text")
        }
    }

    private func check(_ page: Page) throws {
        try AttributeChecks.demoLists(
            page.details,
            hierarchy: page.hierarchy,
            scene: try DemoListsScene(page.hierarchy)
        )
    }

    private func assertRejects(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: (inout [UInt64: [String: AttributeValue]]) -> Void
    ) {
        XCTAssertThrowsError(try check(page(change)), file: file, line: line) { error in
            XCTAssertTrue(
                "\(error)".contains(expected),
                "\"\(error)\" does not mention \"\(expected)\"",
                file: file,
                line: line
            )
        }
    }

    func test_S_PROBE_07_theListsPageIsFoundAndAccepted() throws {
        let page = page()
        XCTAssertTrue(DemoListsScene.isShown(in: page.hierarchy))
        let scene = try DemoListsScene(page.hierarchy)
        XCTAssertEqual(scene.arranged.map(\.id), [7, 8, 9])
        XCTAssertNoThrow(try check(page))
    }

    func test_S_PROBE_07_theListsPageChecksItsValues() {
        assertRejects("tableView.numberOfRows of the table is int(7), expected int(8)") {
            $0[4]?["tableView.numberOfRows"] = .int(7)
        }
        assertRejects("collectionView.itemsPerSection of the collection view") {
            $0[5]?["collectionView.itemsPerSection"] = .string("4")
        }
        assertRejects("tableView.dataSource of the table") {
            $0[4]?["tableView.dataSource"] = .layerReference([
                ObjectReference(
                    layerID: 0,
                    className: "CutawayDemo.DemoListsViewController",
                    displayClassName: "DemoListsViewController"
                )
            ])
        }
        assertRejects("stackView.arrangedSubviews of the stack view") {
            $0[6]?["stackView.arrangedSubviews"] = .layerReference([9, 8, 7].map {
                ObjectReference(layerID: $0, className: "UILabel", displayClassName: "UILabel")
            })
        }
        assertRejects("tableView.visibleIndexPaths of the table") {
            $0[4]?["tableView.visibleIndexPaths"] = .string("None")
        }
        assertRejects("imageView.imageName of the symbol") { $0[10]?["imageView.imageName"] = nil }
        assertRejects("label.fontTextStyle of the Dynamic Type label") { $0[11]?["label.fontTextStyle"] = nil }
        assertRejects("label.isTruncated of the truncated label") { $0[12]?["label.isTruncated"] = .bool(false) }
        assertRejects("view.accessibilityLabel of the button Close") { $0[3]?["view.accessibilityLabel"] = nil }
    }

    func test_S_PROBE_07_theMainScreenIsNotTheListsPage() throws {
        var hierarchy = page().hierarchy
        hierarchy.nodes[1].viewControllerClassName = "CutawayDemo.DemoViewController"
        XCTAssertFalse(DemoListsScene.isShown(in: hierarchy))
        hierarchy = page().hierarchy
        hierarchy.nodes[3].memberReferences = []
        XCTAssertThrowsError(try DemoListsScene(hierarchy)) {
            XCTAssertTrue("\($0)".contains("listsTable"), "\($0)")
        }
    }
}
