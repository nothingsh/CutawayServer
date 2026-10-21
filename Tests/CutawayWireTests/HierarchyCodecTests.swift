import CutawayWire
import Foundation
import XCTest

/// The hierarchy decodes into the project's value types and encodes back.
final class HierarchyCodecTests: XCTestCase {
    /// The whole fixture: nodes 1 to 9, and the virtual and excluded nodes 10 to 14 of 1.2.
    private func fullFixtureHierarchy() throws -> Hierarchy {
        let frame = try FrameCodec.decode(RepositoryFiles.fixture("hierarchy/02-s2c-hierarchy.bin"))
        XCTAssertEqual(frame.requestID, 2)
        guard case .hierarchy(let hierarchy)? = frame.body else {
            XCTFail("the fixture is not a Hierarchy: \(frame)")
            return Hierarchy(nodes: [], keyWindowID: 0)
        }
        return hierarchy
    }

    /// Nodes 1 to 9 of the fixture, the layers before 1.2, in order.
    private func fixtureHierarchy() throws -> Hierarchy {
        var hierarchy = try fullFixtureHierarchy()
        hierarchy.nodes.removeAll { $0.id > 9 }
        return hierarchy
    }

    func test_S_HIER_01_decodesTheHierarchyFixture() throws {
        XCTAssertEqual(
            try FrameCodec.decode(RepositoryFiles.fixture("hierarchy/01-c2s-get-hierarchy.bin")),
            Frame(requestID: 2, body: .getHierarchy)
        )

        // Pre-order, siblings back to front, virtual children first (Protocol/fixtures/README.md).
        let full = try fullFixtureHierarchy()
        XCTAssertEqual(full.nodes.map(\.id), [1, 2, 3, 4, 10, 11, 12, 5, 6, 7, 8, 9, 13, 14])
        XCTAssertEqual(full.nodes.map(\.parentID), [0, 1, 2, 2, 4, 10, 4, 4, 2, 6, 2, 2, 2, 13])
        let hierarchy = try fixtureHierarchy()
        XCTAssertEqual(hierarchy.keyWindowID, 1)
        XCTAssertEqual(hierarchy.nodes.map(\.id), [1, 2, 3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(hierarchy.nodes.map(\.parentID), [0, 1, 2, 2, 4, 2, 6, 2, 2])
        XCTAssertEqual(
            hierarchy.nodes.map(\.className),
            [
                "UIWindowLayer",
                "CALayer",
                "_UILabelLayer",
                "CALayer",
                "CAShapeLayer",
                "CALayer",
                "_UILabelLayer",
                "CALayer",
                "CALayer"
            ]
        )
        XCTAssertEqual(hierarchy.nodes.map(\.displayClassName), hierarchy.nodes.map(\.className))
    }

    func test_S_HIER_03_absentViewClassNamesDecodeAsNil() throws {
        let nodes = try fixtureHierarchy().nodes
        XCTAssertEqual(
            nodes.map(\.viewClassName),
            ["UIWindow", "UIView", "UILabel", "Demo.CardView", nil, "UIScrollView", "UILabel", nil, "UIView"]
        )
        XCTAssertEqual(
            nodes.map(\.viewDisplayClassName),
            ["UIWindow", "UIView", "UILabel", "CardView", nil, "UIScrollView", "UILabel", nil, "UIView"]
        )
    }

    func test_S_HIER_08_decodesViewControllersAndMemberReferences() throws {
        // Protocol 0.2 (Protocol/fixtures/README.md, "View controllers and member variables").
        let nodes = try fixtureHierarchy().nodes
        XCTAssertEqual(
            nodes.map(\.viewControllerClassName),
            [nil, "Demo.HomeViewController", nil, nil, nil, nil, nil, nil, nil]
        )
        XCTAssertEqual(
            nodes.map(\.viewControllerDisplayClassName),
            [nil, "HomeViewController", nil, nil, nil, nil, nil, nil, nil]
        )

        func home(_ name: String) -> MemberReference {
            MemberReference(
                ownerClassName: "Demo.HomeViewController",
                ownerDisplayClassName: "HomeViewController",
                name: name
            )
        }
        XCTAssertEqual(
            nodes.map(\.memberReferences),
            [
                [],
                [],
                [home("titleLabel")],
                [home("cardView")],
                [
                    MemberReference(
                        ownerClassName: "Demo.CardView",
                        ownerDisplayClassName: "CardView",
                        name: "badgeLayer"
                    ),
                    home("cardBadge")
                ],
                [home("scrollView")],
                [],
                [
                    MemberReference(
                        ownerClassName: "DMBaseViewController",
                        ownerDisplayClassName: "DMBaseViewController",
                        name: "_dividerLayer"
                    )
                ],
                []
            ]
        )
    }

    func test_S_HIER_05_decodesTheFixtureGeometry() throws {
        let nodes = try fixtureHierarchy().nodes
        let half = WirePoint(x: 0.5, y: 0.5)

        // The window's root layer, in full.
        XCTAssertEqual(
            nodes[0],
            LayerNode(
                id: 1,
                parentID: 0,
                className: "UIWindowLayer",
                displayClassName: "UIWindowLayer",
                viewClassName: "UIWindow",
                viewDisplayClassName: "UIWindow",
                bounds: WireRect(x: 0, y: 0, width: 393, height: 852),
                position: WirePoint(x: 196.5, y: 426),
                anchorPoint: half,
                transform: .identity,
                zPosition: 0,
                isHidden: false,
                opacity: 1,
                masksToBounds: false,
                layerAddress: 0x6000_03B4_C000,
                viewAddress: 0x1_0380_6A00,
                layerClassOrigin: .system,
                viewClassOrigin: .system,
                viewBaseClassName: "UIWindow"
            )
        )

        // Node 4: rotated by 30 degrees about z, clipping.
        var rotation = WireTransform.identity
        rotation.m11 = 0.8660254037844387
        rotation.m12 = 0.5
        rotation.m21 = -0.5
        rotation.m22 = 0.8660254037844387
        XCTAssertEqual(nodes[3].transform, rotation)
        XCTAssertTrue(nodes[3].masksToBounds)
        XCTAssertEqual(nodes[3].bounds, WireRect(x: 0, y: 0, width: 300, height: 180))
        XCTAssertEqual(nodes[3].position, WirePoint(x: 196.5, y: 300))

        // Node 5: hidden, half transparent.
        XCTAssertTrue(nodes[4].isHidden)
        XCTAssertEqual(nodes[4].opacity, 0.5)

        // Node 6: a scroll view scrolled down by 100 points.
        XCTAssertEqual(nodes[5].bounds, WireRect(x: 0, y: 100, width: 300, height: 200))
        XCTAssertTrue(nodes[5].masksToBounds)

        // Node 8: anchored at its corner. Node 9: no size.
        XCTAssertEqual(nodes[7].anchorPoint, WirePoint(x: 0, y: 0))
        XCTAssertEqual(nodes[8].bounds, WireRect(x: 0, y: 0, width: 0, height: 0))
        XCTAssertEqual(nodes[8].position, WirePoint(x: 300, y: 700))

        // Everything not singled out above has the usual values.
        for node in nodes where node.id != 4 { XCTAssertEqual(node.transform, .identity, "\(node.id)") }
        for node in nodes where node.id != 8 { XCTAssertEqual(node.anchorPoint, half, "\(node.id)") }
        for node in nodes where node.id != 5 {
            XCTAssertFalse(node.isHidden, "\(node.id)")
            XCTAssertEqual(node.opacity, 1, "\(node.id)")
        }
        XCTAssertEqual(nodes.map(\.zPosition), Array(repeating: 0, count: 9))
    }

    func test_S_HIER_01_hierarchyRoundTrips() throws {
        // The fixture survives being encoded by this codec.
        let fixture = Frame(requestID: 2, body: .hierarchy(try fixtureHierarchy()))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(fixture)), fixture)

        // Every field set to something that is not its default.
        let transform = WireTransform(
            m11: 1,
            m12: 2,
            m13: 3,
            m14: 4,
            m21: 5,
            m22: 6,
            m23: 7,
            m24: 8,
            m31: 9,
            m32: 10,
            m33: 11,
            m34: 12,
            m41: 13,
            m42: 14,
            m43: 15,
            m44: 16
        )
        XCTAssertEqual(transform.components, (1...16).map(Double.init))
        let backed = LayerNode(
            id: .max,
            parentID: 0,
            className: "_TtC4Demo8CardView",
            displayClassName: "CardView",
            viewClassName: "Demo.Cell<Swift.Int>",
            viewDisplayClassName: "Cell<Int>",
            bounds: WireRect(x: -1.5, y: 2.5, width: 3.5, height: 4.5),
            position: WirePoint(x: 5.5, y: -6.5),
            anchorPoint: WirePoint(x: 0.25, y: 0.75),
            transform: transform,
            zPosition: -7.5,
            isHidden: true,
            opacity: 0.25,
            masksToBounds: true,
            viewControllerClassName: "_TtC4Demo14HomeController",
            viewControllerDisplayClassName: "HomeController",
            memberReferences: [
                MemberReference(ownerClassName: "Demo.CardView", ownerDisplayClassName: "CardView", name: "badge"),
                MemberReference(ownerClassName: "Base", ownerDisplayClassName: "Base", name: "_divider")
            ]
        )
        let bare = LayerNode(
            id: 2,
            parentID: .max,
            className: "CALayer",
            displayClassName: "CALayer",
            bounds: WireRect(x: 0, y: 0, width: 0, height: 0),
            position: WirePoint(x: 0, y: 0)
        )
        let frame = Frame(
            requestID: 9,
            body: .hierarchy(Hierarchy(nodes: [backed, bare], keyWindowID: .max))
        )
        let decoded = try FrameCodec.decode(FrameCodec.encode(frame))
        XCTAssertEqual(decoded, frame)
        guard case .hierarchy(let hierarchy)? = decoded.body else { return XCTFail("\(decoded)") }
        XCTAssertNil(hierarchy.nodes[1].viewClassName)
        XCTAssertNil(hierarchy.nodes[1].viewDisplayClassName)
        XCTAssertNil(hierarchy.nodes[1].viewControllerClassName)
        XCTAssertNil(hierarchy.nodes[1].viewControllerDisplayClassName)
        XCTAssertEqual(hierarchy.nodes[1].memberReferences, [])

        // An app without windows.
        let empty = Frame(requestID: 3, body: .hierarchy(Hierarchy(nodes: [], keyWindowID: 0)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(empty)), empty)
    }

    func test_S_HIER_01_aLargeHierarchyRoundTrips() throws {
        // 20,000 layers in one chain: far more than a real screen has.
        let nodes = (1...20_000).map { index in
            LayerNode(
                id: UInt64(index),
                parentID: UInt64(index - 1),
                className: "CALayer",
                displayClassName: "CALayer",
                viewClassName: "UIView",
                viewDisplayClassName: "UIView",
                bounds: WireRect(x: 0, y: 0, width: 10, height: 10),
                position: WirePoint(x: 5, y: 5)
            )
        }
        let frame = Frame(requestID: 4, body: .hierarchy(Hierarchy(nodes: nodes, keyWindowID: 1)))
        let payload = FrameCodec.encode(frame)
        XCTAssertLessThan(payload.count, Int(FrameCodec.maximumFrameLength))
        XCTAssertEqual(try FrameCodec.decode(payload), frame)
    }

    func test_S_HIER_11_decodesTheSubtreeFixture() throws {
        func frame(_ file: String) throws -> Frame {
            try FrameCodec.decode(RepositoryFiles.fixture("subtree/\(file)"))
        }
        XCTAssertEqual(try frame("01-c2s-get-subtree.bin"), Frame(requestID: 1, body: .getSubtree(rootID: 4)))
        // P-HIER-10: node 4 and its descendant, exactly as in the hierarchy; node 4 keeps its parent.
        guard case .hierarchy(let whole)? = try FrameCodec.decode(
            RepositoryFiles.fixture("hierarchy/02-s2c-hierarchy.bin")
        ).body
        else { return XCTFail("expected Hierarchy") }
        XCTAssertEqual(
            try frame("02-s2c-hierarchy.bin"),
            Frame(
                requestID: 1,
                body: .hierarchy(
                    Hierarchy(nodes: whole.nodes.filter { [4, 10, 11, 12, 5].contains($0.id) }, keyWindowID: 1)
                )
            )
        )
        // P-HIER-10, 22 (1.2): the subtree of a virtual node; its root keeps its parent node.
        XCTAssertEqual(try frame("05-c2s-get-subtree.bin"), Frame(requestID: 3, body: .getSubtree(rootID: 10)))
        XCTAssertEqual(
            try frame("06-s2c-hierarchy.bin"),
            Frame(
                requestID: 3,
                body: .hierarchy(Hierarchy(nodes: whole.nodes.filter { [10, 11].contains($0.id) }, keyWindowID: 1))
            )
        )
    }

    func test_S_HIER_17_decodesTheFixtureVirtualNodes() throws {
        // Protocol 1.2 (Protocol/fixtures/README.md, "Virtual nodes and excluded subtrees").
        let nodes = try fullFixtureHierarchy().nodes
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        XCTAssertEqual(nodes.filter { $0.nodeKind == .virtual }.map(\.id), [10, 11, 12])
        XCTAssertEqual(nodes.compactMap(\.name), ["Total", "New", "Tax"])
        let row = try XCTUnwrap(byID[10])
        XCTAssertEqual(row.className, "Demo.CardRow")
        XCTAssertEqual(row.displayClassName, "CardRow")
        XCTAssertEqual(row.layerClassOrigin, .app)
        XCTAssertEqual(row.bounds, WireRect(x: 0, y: 0, width: 300, height: 40))
        XCTAssertEqual(row.position, WirePoint(x: 150, y: 20))
        XCTAssertEqual(row.layerAddress, 0)
        XCTAssertNil(row.viewClassName)
        XCTAssertEqual(byID[11]?.position, WirePoint(x: 270, y: 20))
    }

    func test_S_HIER_18_decodesTheFixtureFlags() throws {
        let nodes = try fullFixtureHierarchy().nodes
        XCTAssertEqual(nodes.filter(\.isCollapsedByDefault).map(\.id), [10])
        XCTAssertEqual(nodes.filter(\.isCaptureExcluded).map(\.id), [13, 14])
    }

    func test_S_HIER_17_newNodeFieldsRoundTrip() throws {
        var node = LayerNode(
            id: 21,
            parentID: 4,
            className: "Demo.Bar",
            displayClassName: "Bar",
            bounds: WireRect(x: 0, y: 0, width: 10, height: 30),
            position: WirePoint(x: 5, y: 15),
            layerClassOrigin: .app,
            nodeKind: .virtual,
            name: "March",
            isCollapsedByDefault: true,
            isCaptureExcluded: true
        )
        func roundTrip(_ node: LayerNode) throws -> LayerNode? {
            let frame = Frame(requestID: 1, body: .hierarchy(Hierarchy(nodes: [node], keyWindowID: 0)))
            guard case .hierarchy(let decoded)? = try FrameCodec.decode(FrameCodec.encode(frame)).body else {
                return nil
            }
            return decoded.nodes.first
        }
        XCTAssertEqual(try roundTrip(node), node)
        node.nodeKind = .layer
        node.name = nil
        node.isCollapsedByDefault = false
        node.isCaptureExcluded = false
        XCTAssertEqual(try roundTrip(node), node)
    }

    func test_S_HIER_13_decodesTheFixtureAddresses() throws {
        // Protocol 1.1 (Protocol/fixtures/README.md, "Addresses (1.1)").
        let nodes = try fixtureHierarchy().nodes
        for node in nodes {
            XCTAssertEqual(node.layerAddress, 0x6000_03B4_C000 + 0x40 * (node.id - 1), "\(node.id)")
            // P-HIER-14: exactly when the class names are given.
            XCTAssertEqual(
                node.viewAddress,
                node.viewClassName == nil ? nil : 0x1_0380_6800 + 0x200 * node.id,
                "\(node.id)"
            )
            XCTAssertEqual(node.viewControllerAddress, node.id == 2 ? 0x1_0300_7A00 : nil, "\(node.id)")
            XCTAssertEqual(node.viewControllerAddress != nil, node.viewControllerClassName != nil, "\(node.id)")
        }
        XCTAssertEqual(nodes.filter { $0.viewAddress == nil }.map(\.id), [5, 8])
    }

    func test_S_HIER_14_decodesTheFixtureOriginsBaseClassesAndVisibility() throws {
        // Protocol 1.1 (Protocol/fixtures/README.md, "Origins, base classes and visibility").
        let nodes = try fixtureHierarchy().nodes
        for node in nodes {
            // P-HIER-16, 18: given exactly when the class names are.
            XCTAssertEqual(node.layerClassOrigin, .system, "\(node.id)")
            XCTAssertEqual(
                node.viewClassOrigin,
                node.viewClassName == nil ? .unknown : node.id == 4 ? .app : .system,
                "\(node.id)"
            )
            XCTAssertEqual(node.viewControllerClassOrigin, node.id == 2 ? .app : .unknown, "\(node.id)")
            XCTAssertEqual(node.viewControllerVisibility, node.id == 2 ? .shown : .unknown, "\(node.id)")
        }
        // P-HIER-17.
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: nodes.compactMap { node in node.viewBaseClassName.map { (node.id, $0) } }),
            [1: "UIWindow", 3: "UILabel", 6: "UIScrollView", 7: "UILabel"]
        )
        XCTAssertEqual(nodes.compactMap(\.layerBaseClassName), ["CAShapeLayer"])
        XCTAssertEqual(nodes.first { $0.layerBaseClassName != nil }?.id, 5)
    }

    func test_S_HIER_14_newNodeFieldsRoundTripAndUnknownMeansAbsent() throws {
        var node = LayerNode(
            id: 7,
            parentID: 1,
            className: "CALayer",
            displayClassName: "CALayer",
            viewClassName: "Demo.CardView",
            viewDisplayClassName: "CardView",
            bounds: WireRect(x: 0, y: 0, width: 1, height: 1),
            position: WirePoint(x: 0, y: 0),
            viewControllerClassName: "UINavigationController",
            viewControllerDisplayClassName: "UINavigationController",
            layerClassOrigin: .system,
            viewClassOrigin: .app,
            viewControllerClassOrigin: .system,
            layerBaseClassName: "CAShapeLayer",
            viewBaseClassName: "UIHostingView",
            viewControllerVisibility: .notShown
        )
        for _ in 0..<2 {
            let frame = Frame(requestID: 1, body: .hierarchy(Hierarchy(nodes: [node], keyWindowID: 0)))
            XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)
            // A 1.0 server sends none of them.
            node.layerClassOrigin = .unknown
            node.viewClassOrigin = .unknown
            node.viewControllerClassOrigin = .unknown
            node.layerBaseClassName = nil
            node.viewBaseClassName = nil
            node.viewControllerVisibility = .unknown
        }
    }

    func test_S_HIER_13_addressesRoundTripAndZeroMeansAbsent() throws {
        let node = LayerNode(
            id: 7,
            parentID: 0,
            className: "CALayer",
            displayClassName: "CALayer",
            bounds: WireRect(x: 0, y: 0, width: 1, height: 1),
            position: WirePoint(x: 0, y: 0),
            layerAddress: .max,
            viewAddress: 0x1_0000_0010,
            viewControllerAddress: 0x1_0000_0020
        )
        let frame = Frame(requestID: 1, body: .hierarchy(Hierarchy(nodes: [node], keyWindowID: 0)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(frame)), frame)

        // A 1.0 server sends none: they read as 0 and nil.
        var plain = node
        plain.layerAddress = 0
        plain.viewAddress = nil
        plain.viewControllerAddress = nil
        let plainFrame = Frame(requestID: 1, body: .hierarchy(Hierarchy(nodes: [plain], keyWindowID: 0)))
        XCTAssertEqual(try FrameCodec.decode(FrameCodec.encode(plainFrame)), plainFrame)
    }

    func test_S_HIER_12_decodesTheSubtreeNotFoundFixture() throws {
        XCTAssertEqual(
            try FrameCodec.decode(RepositoryFiles.fixture("subtree/03-c2s-get-subtree.bin")),
            Frame(requestID: 2, body: .getSubtree(rootID: 99))
        )
        XCTAssertEqual(
            try FrameCodec.decode(RepositoryFiles.fixture("subtree/04-s2c-error.bin")),
            Frame(requestID: 2, body: .error(WireError(code: .layerNotFound, message: "no layer with id 99")))
        )
    }

    func test_S_HIER_07_decodesTheAppNotActiveFixture() throws {
        XCTAssertEqual(
            try FrameCodec.decode(RepositoryFiles.fixture("app-not-active/02-c2s-get-hierarchy.bin")),
            Frame(requestID: 7, body: .getHierarchy)
        )
        XCTAssertEqual(
            try FrameCodec.decode(RepositoryFiles.fixture("app-not-active/03-s2c-error.bin")),
            Frame(
                requestID: 7,
                body: .error(WireError(code: .appNotActive, message: "the app is not active"))
            )
        )
    }
}
