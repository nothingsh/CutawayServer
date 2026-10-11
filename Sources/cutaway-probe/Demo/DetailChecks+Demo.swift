import CutawayWire
import Foundation

// The checks of `--expect-demo`: what the demo app's screen has to look like.
extension DetailChecks {
    // MARK: - The demo app's screen

    /// The four bytes of one colour as a premultiplied pixel: B, G, R, A.
    static func pixel(red: Double, green: Double, blue: Double, alpha: Double = 1) -> [UInt8] {
        [blue, green, red, 1].map { UInt8(($0 * alpha * 255).rounded()) }
    }

    /// The pixel that shows a point of the layer, given relative to the origin of its bounds.
    static func sample(_ image: WireImage, atPoint x: Double, _ y: Double, name: String) throws -> [UInt8] {
        guard let pixels = try? (image.data as NSData).decompressed(using: .lzfse) as Data else {
            throw ProbeFailure("\(name): data is not LZFSE (P-IMG-01)")
        }
        let column = Int(x * Double(image.scale))
        let row = Int(y * Double(image.scale))
        let start = row * Int(image.bytesPerRow) + column * 4
        guard column >= 0, row >= 0, column < Int(image.pixelWidth), row < Int(image.pixelHeight),
              start + 4 <= pixels.count
        else {
            throw ProbeFailure("\(name) has no pixel for the point (\(x), \(y))")
        }
        return [UInt8](pixels[start..<start + 4])
    }

    /// The layers whose pixels are sampled, as the scene found them.
    struct DemoLayers {
        var card: LayerNode
        /// The shape layer in the card.
        var shape: LayerNode
        var screen: LayerNode
        var scrollView: LayerNode
        var bareLayer: LayerNode
    }

    /// What the screenshots of the demo app's screen have to show
    /// (Demo/CutawayDemo/DemoViewController.swift). Call it after `stream` and after
    /// `HierarchyChecks.demoScene`, with the details of a request for the solo and the group
    /// image of every layer, and the layers the scene found.
    static func demoPixels(_ details: [LayerDetail], hierarchy: Hierarchy, layers: DemoLayers) throws {
        let nodes = hierarchy.nodes
        var byID: [UInt64: LayerDetail] = [:]
        for detail in details { byID[detail.layerID] = detail }

        try checkDemoStatuses(nodes, byID: byID)
        let (card, shape, screen, scrollView, bareLayer) =
            (layers.card, layers.shape, layers.screen, layers.scrollView, layers.bareLayer)

        // The card is rotated by 30 degrees and its image is not: all four corners are its colour.
        let green = pixel(red: 0, green: 0.6, blue: 0.3)
        let cardSize = card.bounds.size
        for (x, y) in [
            (0.5, 0.5),
            (cardSize.width - 0.5, 0.5),
            (0.5, cardSize.height - 0.5),
            (cardSize.width - 0.5, cardSize.height - 0.5),
            (cardSize.width / 2, cardSize.height / 2)
        ] {
            try expect(byID[card.id]?.group, "the group image of CardView", atPoint: x, y, green)
        }
        try expect(byID[card.id]?.solo, "the solo image of CardView", atPoint: 40, 40, green)

        // The shape layer is hidden and half transparent; its image shows it visible and opaque.
        try expect(
            byID[shape.id]?.group,
            "the group image of the CAShapeLayer",
            atPoint: 20,
            20,
            pixel(red: 1, green: 1, blue: 0)
        )
        try expect(
            byID[shape.id]?.group,
            "the group image of the CAShapeLayer",
            atPoint: 0.5,
            0.5,
            [0, 0, 0, 0]
        )

        // Where the bare layer lies on the screen's view: orange in the group image, the view's
        // own white in the solo image.
        let orange = pixel(red: 1, green: 0.5, blue: 0)
        let x = bareLayer.position.x - screen.bounds.origin.x + bareLayer.bounds.size.width / 2
        let y = bareLayer.position.y - screen.bounds.origin.y + bareLayer.bounds.size.height / 2
        try expect(byID[screen.id]?.group, "the group image of the screen's view", atPoint: x, y, orange)
        try expect(
            byID[screen.id]?.solo,
            "the solo image of the screen's view",
            atPoint: x,
            y,
            pixel(red: 1, green: 1, blue: 1)
        )
        try expect(
            byID[bareLayer.id]?.group,
            "the group image of the bare layer",
            atPoint: bareLayer.bounds.size.width / 2,
            bareLayer.bounds.size.height / 2,
            orange
        )

        // The scroll view's background, away from its label and its scroll indicators.
        try expect(
            byID[scrollView.id]?.group,
            "the group image of the scroll view",
            atPoint: 10,
            10,
            pixel(red: 0.85, green: 0.9, blue: 1)
        )
    }

    /// Every layer of the demo app's screen has a detail, Ok when it has a size.
    private static func checkDemoStatuses(_ nodes: [LayerNode], byID: [UInt64: LayerDetail]) throws {
        for node in nodes {
            guard let detail = byID[node.id] else {
                throw ProbeFailure("demo: there is no detail for layer \(node.id)")
            }
            let hasSize = node.bounds.size.width > 0 && node.bounds.size.height > 0
            guard detail.status == (hasSize ? .ok : .captureFailed) else {
                throw ProbeFailure(
                    "demo: the detail of layer \(node.id) (\(node.className), \(node.bounds.size.width) x \(node.bounds.size.height)) has status \(detail.status)"
                )
            }
        }
    }

    /// Fails unless the image shows `expected` at the point, within 2 per channel.
    private static func expect(
        _ image: WireImage?,
        _ what: String,
        atPoint x: Double,
        _ y: Double,
        _ expected: [UInt8]
    ) throws {
        guard let image else { throw ProbeFailure("demo: \(what) is missing") }
        let actual = try sample(image, atPoint: x, y, name: "demo: \(what)")
        guard zip(actual, expected).allSatisfy({ abs(Int($0) - Int($1)) <= 2 }) else {
            throw ProbeFailure(
                "demo: \(what) is \(actual) at the point (\(x), \(y)), expected \(expected) (B, G, R, A)"
            )
        }
    }
}
