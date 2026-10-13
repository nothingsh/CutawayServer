import CutawayWire
import Foundation
import XCTest

@testable import cutaway_probe

/// A bitmap in the wire's layout that tests paint and compress.
private struct Canvas {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    /// Filled with one colour: B, G, R, A.
    init(width: Int, height: Int, _ color: [UInt8]) {
        self.width = width
        self.height = height
        pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            memset_pattern4(buffer.baseAddress!, color, buffer.count)
        }
    }

    mutating func fill(x: Int, y: Int, width: Int, height: Int, _ color: [UInt8]) {
        for row in y..<y + height {
            for column in x..<x + width {
                pixels.replaceSubrange(
                    (row * self.width + column) * 4..<(row * self.width + column) * 4 + 4,
                    with: color
                )
            }
        }
    }

    func image(scale: Float = 1) -> WireImage {
        WireImage(
            pixelWidth: UInt32(width),
            pixelHeight: UInt32(height),
            bytesPerRow: UInt32(width * 4),
            scale: scale,
            data: try! (Data(pixels) as NSData).compressed(using: .lzfse) as Data
        )
    }
}

/// The probe's checks of a stream of layer details: they accept what a correct server sends
/// and name what is wrong with anything else.
final class DetailChecksTests: XCTestCase {
    /// Tests/CutawayProbeTests/DetailChecksTests.swift -> the repository root.
    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func fixture(_ path: String) throws -> Frame {
        try FrameCodec.decode(
            Data(contentsOf: Self.root.appendingPathComponent("Protocol/fixtures/bin").appendingPathComponent(path))
        )
    }

    private func fixtureHierarchy() throws -> Hierarchy {
        try HierarchyChecks.hierarchy(try fixture("hierarchy/02-s2c-hierarchy.bin"))
    }

    /// The request and the server's frames of a fixture scenario.
    private func scenario(
        _ name: String,
        _ files: [String]
    ) throws -> (request: GetLayerDetails, id: UInt32, frames: [Frame]) {
        let first = try fixture("\(name)/01-c2s-get-layer-details.bin")
        guard case .getLayerDetails(let request)? = first.body else {
            throw ProbeFailure("\(name) does not begin with GetLayerDetails")
        }
        return (request, first.requestID, try files.map { try fixture("\(name)/\($0).bin") })
    }

    private func layerDetails() throws -> (request: GetLayerDetails, id: UInt32, frames: [Frame]) {
        try scenario("layer-details", ["02-s2c-chunk-0", "03-s2c-chunk-1", "04-s2c-stream-end"])
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

    /// Changes the frames of the `layer-details` scenario and expects the stream check to object.
    private func assertStreamRejects(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: (inout [Frame]) -> Void
    ) throws {
        let scenario = try layerDetails()
        var frames = scenario.frames
        change(&frames)
        let hierarchy = try fixtureHierarchy()
        assertRejects(expected, file: file, line: line) {
            _ = try DetailChecks.stream(
                frames,
                answering: scenario.id,
                request: scenario.request,
                hierarchy: hierarchy
            )
        }
    }

    /// Rewrites the detail at `index` of the chunk in `frame`.
    private func change(_ frame: inout Frame, detail index: Int, _ body: (inout LayerDetail) -> Void) {
        guard case .layerDetailsChunk(var chunk)? = frame.body else { return XCTFail("not a chunk") }
        body(&chunk.details[index])
        frame.body = .layerDetailsChunk(chunk)
    }

    private func changeChunk(_ frame: inout Frame, _ body: (inout LayerDetailsChunk) -> Void) {
        guard case .layerDetailsChunk(var chunk)? = frame.body else { return XCTFail("not a chunk") }
        body(&chunk)
        frame.body = .layerDetailsChunk(chunk)
    }

    // MARK: - Streams

    func test_S_PROBE_01_detailChecksAcceptTheFixtures() throws {
        let hierarchy = try fixtureHierarchy()

        let (request, id, frames) = try layerDetails()
        let details = try DetailChecks.stream(frames, answering: id, request: request, hierarchy: hierarchy)
        XCTAssertEqual(details.map(\.layerID), [3, 4, 99])
        XCTAssertEqual(
            DetailChecks.summary(of: details, chunks: 2),
            DetailChecks.Summary(
                layers: 3,
                chunks: 2,
                images: 3,
                captureFailed: 0,
                notFound: 1,
                attributeGroups: 3,
                attributes: 15
            )
        )

        // The left-out solo, the padded rows, the failed capture with attributes, the request
        // that wanted nothing.
        let edge = try scenario("layer-details-edge", ["02-s2c-chunk-0", "03-s2c-stream-end"])
        let edgeDetails = try DetailChecks.stream(
            edge.frames,
            answering: edge.id,
            request: edge.request,
            hierarchy: hierarchy
        )
        XCTAssertEqual(
            DetailChecks.summary(of: edgeDetails, chunks: 1),
            DetailChecks.Summary(
                layers: 4,
                chunks: 1,
                images: 2,
                captureFailed: 1,
                notFound: 0,
                attributeGroups: 1,
                attributes: 2
            )
        )

        // One detail per chunk is as good as several.
        var oneEach = frames
        changeChunk(&oneEach[1]) { $0.details.removeLast() }
        var third = frames[1]
        changeChunk(&third) {
            $0.sequence = 2
            $0.details.removeFirst()
        }
        oneEach.insert(third, at: 2)
        oneEach[3] = Frame(requestID: id, body: .streamEnd(StreamEnd(status: .completed, chunkCount: 3)))
        XCTAssertNoThrow(
            try DetailChecks.stream(oneEach, answering: id, request: request, hierarchy: hierarchy)
        )

        // An empty request is answered by the end alone.
        XCTAssertNoThrow(
            try DetailChecks.stream(
                [Frame(requestID: 9, body: .streamEnd(StreamEnd(status: .completed, chunkCount: 0)))],
                answering: 9,
                request: GetLayerDetails(requests: [], maxTextureDimension: 0),
                hierarchy: hierarchy
            )
        )
    }

    // MARK: - Constraints (protocol 0.4)

    func test_S_PROBE_04_streamsCheckTheirConstraints() throws {
        let hierarchy = try fixtureHierarchy()
        let (request, id, frames) = try scenario(
            "layout-constraints",
            ["02-s2c-chunk-0", "03-s2c-stream-end"]
        )
        let details = try DetailChecks.stream(frames, answering: id, request: request, hierarchy: hierarchy)
        XCTAssertEqual(details.map { $0.constraints.count }, [4, 4, 4, 0, 0])

        // Constraint 4 is listed for layers 3 and 4; the two copies differ.
        var different = frames
        change(&different[0], detail: 1) { $0.constraints[0].constant += 1 }
        assertRejects("constraint 4 of layer 4 differs") {
            _ = try DetailChecks.stream(different, answering: id, request: request, hierarchy: hierarchy)
        }
        // Layer 8 backs no view.
        var onBareLayer = frames
        change(&onBareLayer[0], detail: 3) { detail in
            guard case .layerDetailsChunk(let chunk)? = frames[0].body else { return }
            detail.constraints = chunk.details[0].constraints
        }
        assertRejects("layer 8 has constraints, but the layer backs no view") {
            _ = try DetailChecks.stream(onBareLayer, answering: id, request: request, hierarchy: hierarchy)
        }
        // The layer-details scenario asks for none.
        let plain = try layerDetails()
        var unasked = plain.frames
        change(&unasked[0], detail: 0) { detail in
            guard case .layerDetailsChunk(let chunk)? = frames[0].body else { return }
            detail.constraints = chunk.details[0].constraints
        }
        assertRejects("layer 3 has constraints, but the request did not want them") {
            _ = try DetailChecks.stream(unasked, answering: plain.id, request: plain.request, hierarchy: hierarchy)
        }
    }

    func test_S_PROBE_01_detailChecksRejectStreamsThatDidNotComplete() throws {
        let hierarchy = try fixtureHierarchy()
        let cancelled = try scenario("layer-details-cancelled", ["02-s2c-chunk-0", "04-s2c-stream-end"])
        assertRejects("ended with status cancelled") {
            _ = try DetailChecks.stream(
                cancelled.frames,
                answering: cancelled.id,
                request: cancelled.request,
                hierarchy: hierarchy
            )
        }
        let failed = try scenario("layer-details-failed", ["03-s2c-stream-end"])
        assertRejects("ended with status failed: appNotActive, the app left the active state during capture") {
            _ = try DetailChecks.stream(
                failed.frames,
                answering: failed.id,
                request: failed.request,
                hierarchy: hierarchy
            )
        }
    }

    func test_S_PROBE_01_detailChecksRejectBrokenStreams() throws {
        // The frames of the stream.
        try assertStreamRejects("has sequence 1, expected 0") { $0.removeFirst() }
        try assertStreamRejects("has sequence 0, expected 1") { $0[1] = $0[0] }
        try assertStreamRejects("chunk_count is 2, but 1 chunks arrived") { $0.remove(at: 1) }
        try assertStreamRejects("chunk_count is 3") {
            $0[2] = Frame(requestID: 3, body: .streamEnd(StreamEnd(status: .completed, chunkCount: 3)))
        }
        try assertStreamRejects("has no StreamEnd") { $0.removeLast() }
        try assertStreamRejects("follows the StreamEnd") { $0.append($0[2]) }
        try assertStreamRejects("expected a frame of stream 3, got LayerDetailsChunk with request_id 4") {
            $0[1].requestID = 4
        }
        try assertStreamRejects("expected LayerDetailsChunk or StreamEnd, got AppIcon") {
            $0[1] = Frame(requestID: 3, body: .appIcon(AppIcon(image: nil)))
        }
        try assertStreamRejects("status completed and an error") {
            $0[2] = Frame(
                requestID: 3,
                body: .streamEnd(
                    StreamEnd(status: .completed, chunkCount: 2, error: WireError(code: .unknown, message: ""))
                )
            )
        }

        // Which layers, and in which order.
        try assertStreamRejects("2 details arrived for 3 requested layers") { frames in
            self.changeChunk(&frames[1]) { $0.details.removeLast() }
        }
        try assertStreamRejects("detail 1 is for layer 99, but the request's item 1 is layer 4") { frames in
            self.changeChunk(&frames[1]) { $0.details.swapAt(0, 1) }
        }
        try assertStreamRejects("detail 2 is for layer 4, but the request's item 2 is layer 99") { frames in
            self.changeChunk(&frames[1]) { $0.details[1] = $0.details[0] }
        }
        try assertStreamRejects("4 details arrived for 3 requested layers") { frames in
            self.changeChunk(&frames[1]) { $0.details.append($0.details[1]) }
        }
    }

    func test_S_PROBE_01_detailChecksRejectBrokenDetails() throws {
        let red = Canvas(width: 200, height: 24, [0, 0, 255, 255]).image()

        // Statuses.
        try assertStreamRejects("layer 99 is LayerNotFound and has an image") { frames in
            self.change(&frames[1], detail: 1) { $0.group = red }
        }
        try assertStreamRejects("layer 99 is LayerNotFound and has attributes (P-DET-02)") { frames in
            self.change(&frames[1], detail: 1) {
                $0.attributeGroups = [AttributeGroup(id: "layer", title: "Layer", attributes: [])]
            }
        }
        try assertStreamRejects("layer 4 is CaptureFailed and has an image") { frames in
            self.change(&frames[1], detail: 0) { $0.status = .captureFailed }
        }
        try assertStreamRejects("layer 99 is Ok, but the hierarchy has no such layer") { frames in
            self.change(&frames[1], detail: 1) { $0.status = .ok }
        }
        // Layer 4 was asked without attributes, layer 3 with them.
        try assertStreamRejects("layer 4 has attributes, but the request did not want them") { frames in
            self.change(&frames[1], detail: 0) {
                $0.attributeGroups = [AttributeGroup(id: "layer", title: "Layer", attributes: [])]
            }
        }
        try assertStreamRejects("layer 3 has no attributes, but the request wanted them") { frames in
            self.change(&frames[0], detail: 0) { $0.attributeGroups = [] }
        }
        // The attributes themselves are checked too.
        try assertStreamRejects("layer 3: attribute label.numberOfLines of group view") { frames in
            self.change(&frames[0], detail: 0) {
                $0.attributeGroups[2].attributes.append($0.attributeGroups[1].attributes[2])
            }
        }

        // Which images.
        try assertStreamRejects("layer 4 is Ok and has no group image") { frames in
            self.change(&frames[1], detail: 0) { $0.group = nil }
        }
        // Layer 4 has a sublayer, layer 5: its solo cannot be left out.
        try assertStreamRejects("layer 4 has no solo image") { frames in
            self.change(&frames[1], detail: 0) { $0.solo = nil }
        }
        // Layer 3 was asked for its group only.
        try assertStreamRejects("layer 3 has an image that was not requested") { frames in
            self.change(&frames[0], detail: 0) { $0.solo = red }
        }

        // The images themselves.
        try assertStreamRejects(
            "layer 4: group is 200 x 24 pixels at scale 1.0, but the layer's bounds are 300.0 x 180.0"
        ) { frames in
            self.change(&frames[1], detail: 0) { $0.group = red }
        }
        try assertStreamRejects("layer 4: solo is 300 x 180 pixels at scale 2.0") { frames in
            self.change(&frames[1], detail: 0) { $0.solo?.scale = 2 }
        }
        try assertStreamRejects("layer 4: solo: data decompresses to 19200 bytes") { frames in
            self.change(&frames[1], detail: 0) { $0.solo?.data = red.data }
        }
        try assertStreamRejects("layer 4: group: data is not LZFSE") { frames in
            self.change(&frames[1], detail: 0) { $0.group?.data = Data([1, 2, 3]) }
        }
        try assertStreamRejects("layer 3: group has bytes_per_row 799") { frames in
            self.change(&frames[0], detail: 0) { $0.group?.bytesPerRow = 799 }
        }
    }

    func test_S_PROBE_01_detailChecksEnforceTheLimits() throws {
        // Two layers of 2100 x 2100 points and one without a size, under one window.
        func node(_ id: UInt64, parent: UInt64, _ side: Double) -> LayerNode {
            LayerNode(
                id: id,
                parentID: parent,
                className: "CALayer",
                displayClassName: "CALayer",
                bounds: WireRect(x: 0, y: 0, width: side, height: side),
                position: WirePoint(x: 0, y: 0)
            )
        }
        let hierarchy = Hierarchy(
            nodes: [node(1, parent: 0, 2100), node(2, parent: 1, 2100), node(3, parent: 1, 0)],
            keyWindowID: 1
        )
        func request(_ ids: [UInt64], max: UInt32 = 0) -> GetLayerDetails {
            GetLayerDetails(
                requests: ids.map {
                    LayerDetailRequest(layerID: $0, wantSolo: false, wantGroup: true, wantAttributes: false)
                },
                maxTextureDimension: max
            )
        }
        // 2100 x 2100 pixels are 17.6 MB: more than a chunk's budget, less than an image's.
        let large = Canvas(width: 2100, height: 2100, [0, 0, 0, 255]).image()
        func frames(_ chunks: [[LayerDetail]]) -> [Frame] {
            chunks.enumerated().map { index, details in
                Frame(
                    requestID: 5,
                    body: .layerDetailsChunk(LayerDetailsChunk(sequence: UInt32(index), details: details))
                )
            } + [
                Frame(
                    requestID: 5,
                    body: .streamEnd(StreamEnd(status: .completed, chunkCount: UInt32(chunks.count)))
                )
            ]
        }
        let first = LayerDetail(layerID: 1, status: .ok, group: large)
        let second = LayerDetail(layerID: 2, status: .ok, group: large)

        // P-DET-06: each alone in its chunk is fine; both in one chunk are too much.
        XCTAssertNoThrow(
            try DetailChecks.stream(
                frames([[first], [second]]),
                answering: 5,
                request: request([1, 2]),
                hierarchy: hierarchy
            )
        )
        assertRejects("chunk 0 holds 2 details with 35280000 bytes of pixels") {
            _ = try DetailChecks.stream(
                frames([[first, second]]),
                answering: 5,
                request: request([1, 2]),
                hierarchy: hierarchy
            )
        }
        // P-DET-05: the request's limit.
        assertRejects("above max_texture_dimension 2048") {
            _ = try DetailChecks.stream(
                frames([[first]]),
                answering: 5,
                request: request([1], max: 2048),
                hierarchy: hierarchy
            )
        }
        // P-DET-08: one image of more than 64 MiB. 4100 x 4100 pixels are 67.2 MB.
        let tooLarge = Canvas(width: 4100, height: 4100, [0, 0, 0, 255]).image(scale: 4100.0 / 2100)
        assertRejects("has 67240000 bytes of pixels, above 67108864") {
            _ = try DetailChecks.stream(
                frames([[LayerDetail(layerID: 1, status: .ok, group: tooLarge)]]),
                answering: 5,
                request: request([1]),
                hierarchy: hierarchy
            )
        }

        // A layer without a size cannot have an image (P-DET-03).
        XCTAssertNoThrow(
            try DetailChecks.stream(
                frames([[LayerDetail(layerID: 3, status: .captureFailed)]]),
                answering: 5,
                request: request([3]),
                hierarchy: hierarchy
            )
        )
        assertRejects("layer 3 is Ok, but the layer is 0.0 x 0.0 points") {
            _ = try DetailChecks.stream(
                frames([[LayerDetail(layerID: 3, status: .ok)]]),
                answering: 5,
                request: request([3]),
                hierarchy: hierarchy
            )
        }
    }

    func test_S_PROBE_01_detailChecksAllowForTheScalesPrecision() throws {
        // `scale` is a Float. For a long image its rounding alone moves "bounds times scale" by
        // a few thousandths of a pixel, which must not turn a correct image into a failure:
        // 5609 points at this scale are 16384.00002 pixels, 1.00002 away from the 16383 sent.
        let hierarchy = Hierarchy(
            nodes: [
                LayerNode(
                    id: 1,
                    parentID: 0,
                    className: "CALayer",
                    displayClassName: "CALayer",
                    bounds: WireRect(x: 0, y: 0, width: 100, height: 5609),
                    position: WirePoint(x: 0, y: 0)
                )
            ],
            keyWindowID: 1
        )
        let request = GetLayerDetails(
            requests: [
                LayerDetailRequest(layerID: 1, wantSolo: false, wantGroup: true, wantAttributes: false)
            ],
            maxTextureDimension: 16384
        )
        func frames(height: Int) -> [Frame] {
            let image = Canvas(width: 292, height: height, [0, 0, 0, 255]).image(scale: 2.9210198)
            return [
                Frame(
                    requestID: 3,
                    body: .layerDetailsChunk(
                        LayerDetailsChunk(
                            sequence: 0,
                            details: [LayerDetail(layerID: 1, status: .ok, group: image)]
                        )
                    )
                ),
                Frame(requestID: 3, body: .streamEnd(StreamEnd(status: .completed, chunkCount: 1)))
            ]
        }
        XCTAssertGreaterThan(5609 * Double(Float(2.9210198)) - 16383, 1)
        XCTAssertNoThrow(
            try DetailChecks.stream(
                frames(height: 16383),
                answering: 3,
                request: request,
                hierarchy: hierarchy
            )
        )
        XCTAssertNoThrow(
            try DetailChecks.stream(
                frames(height: 16384),
                answering: 3,
                request: request,
                hierarchy: hierarchy
            )
        )
        // Two pixels off is still wrong.
        assertRejects("is 292 x 16382 pixels at scale 2.9210198") {
            _ = try DetailChecks.stream(
                frames(height: 16382),
                answering: 3,
                request: request,
                hierarchy: hierarchy
            )
        }
    }

    // MARK: - The demo app's screen

    private static let white: [UInt8] = [255, 255, 255, 255]
    private static let cardGreen = DetailChecks.pixel(red: 0, green: 0.6, blue: 0.3)
    private static let yellow = DetailChecks.pixel(red: 1, green: 1, blue: 0)
    private static let orange = DetailChecks.pixel(red: 1, green: 0.5, blue: 0)
    private static let paleBlue = DetailChecks.pixel(red: 0.85, green: 0.9, blue: 1)

    /// The demo app's screen as a correct server reports it, at 1 pixel per point: a window,
    /// the screen's view, and the five things DemoViewController adds to it.
    private func demo() -> (hierarchy: Hierarchy, details: [LayerDetail]) {
        func node(
            _ id: UInt64,
            in parentID: UInt64,
            _ viewClass: String?,
            layerClass: String = "CALayer",
            width: Double,
            height: Double,
            x: Double = 0,
            y: Double = 0
        ) -> LayerNode {
            LayerNode(
                id: id,
                parentID: parentID,
                className: layerClass,
                displayClassName: layerClass,
                viewClassName: viewClass,
                viewDisplayClassName: viewClass,
                bounds: WireRect(x: 0, y: 0, width: width, height: height),
                position: WirePoint(x: x, y: y)
            )
        }
        var card = node(4, in: 2, "CutawayDemo.CardView", width: 300, height: 180)
        card.viewDisplayClassName = "CardView"
        var scrollView = node(6, in: 2, "UIScrollView", width: 300, height: 200)
        scrollView.bounds.origin.y = 100
        var bare = node(8, in: 2, nil, width: 60, height: 30, x: 20, y: 650)
        bare.anchorPoint = WirePoint(x: 0, y: 0)
        let hierarchy = Hierarchy(
            nodes: [
                node(1, in: 0, "UIWindow", layerClass: "UIWindowLayer", width: 393, height: 852),
                node(2, in: 1, "UIView", width: 393, height: 852),
                node(3, in: 2, "UILabel", layerClass: "_UILabelLayer", width: 200, height: 24),
                card,
                node(5, in: 4, nil, layerClass: "CAShapeLayer", width: 40, height: 40, x: 40, y: 40),
                scrollView,
                node(7, in: 6, "UILabel", layerClass: "_UILabelLayer", width: 100, height: 40),
                bare,
                node(9, in: 2, "UIView", width: 0, height: 0)
            ],
            keyWindowID: 1
        )

        // The screen: white, with the bare layer's orange where it lies.
        var screen = Canvas(width: 393, height: 852, Self.white)
        screen.fill(x: 20, y: 650, width: 60, height: 30, Self.orange)
        let screenSolo = Canvas(width: 393, height: 852, Self.white)
        // The shape: a yellow square that leaves the corners clear, standing in for the circle.
        var shape = Canvas(width: 40, height: 40, [0, 0, 0, 0])
        shape.fill(x: 5, y: 5, width: 30, height: 30, Self.yellow)
        let green = Canvas(width: 300, height: 180, Self.cardGreen).image()
        let details = [
            LayerDetail(layerID: 1, status: .ok, solo: screenSolo.image(), group: screen.image()),
            LayerDetail(layerID: 2, status: .ok, solo: screenSolo.image(), group: screen.image()),
            LayerDetail(layerID: 3, status: .ok, group: Canvas(width: 200, height: 24, [0, 0, 0, 0]).image()),
            LayerDetail(layerID: 4, status: .ok, solo: green, group: green),
            LayerDetail(layerID: 5, status: .ok, group: shape.image()),
            LayerDetail(
                layerID: 6,
                status: .ok,
                solo: Canvas(width: 300, height: 200, Self.paleBlue).image(),
                group: Canvas(width: 300, height: 200, Self.paleBlue).image()
            ),
            LayerDetail(layerID: 7, status: .ok, group: Canvas(width: 100, height: 40, [0, 0, 0, 0]).image()),
            LayerDetail(layerID: 8, status: .ok, group: Canvas(width: 60, height: 30, Self.orange).image()),
            LayerDetail(layerID: 9, status: .captureFailed)
        ]
        var addressed = hierarchy
        Addresses.add(to: &addressed)
        return (addressed, details)
    }

    /// The pixel check with the nodes the scene would find: the card and its shape, the
    /// screen's view, the scroll view and the bare layer.
    private static func demoPixels(_ details: [LayerDetail], hierarchy: Hierarchy) throws {
        try DetailChecks.demoPixels(
            details,
            hierarchy: hierarchy,
            layers: DetailChecks.DemoLayers(
                card: hierarchy.nodes[3],
                shape: hierarchy.nodes[4],
                screen: hierarchy.nodes[1],
                scrollView: hierarchy.nodes[5],
                bareLayer: hierarchy.nodes[7]
            )
        )
    }

    private func assertDemoRejects(
        _ expected: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ change: (inout [LayerDetail]) -> Void
    ) {
        let (hierarchy, fixtureDetails) = demo()
        var details = fixtureDetails
        change(&details)
        assertRejects(expected, file: file, line: line) {
            try Self.demoPixels(details, hierarchy: hierarchy)
        }
    }

    func test_S_PROBE_01_demoPixelChecksAcceptTheExpectedColors() throws {
        let (hierarchy, details) = demo()
        XCTAssertNoThrow(try HierarchyChecks.structure(hierarchy))
        XCTAssertNoThrow(try Self.demoPixels(details, hierarchy: hierarchy))

        // The stream check accepts the same details, as a request for both images of every layer.
        let request = GetLayerDetails(
            requests: hierarchy.nodes.map {
                LayerDetailRequest(layerID: $0.id, wantSolo: true, wantGroup: true, wantAttributes: false)
            },
            maxTextureDimension: 16384
        )
        let frames =
            details.enumerated().map { index, detail in
                Frame(
                    requestID: 3,
                    body: .layerDetailsChunk(LayerDetailsChunk(sequence: UInt32(index), details: [detail]))
                )
            } + [Frame(requestID: 3, body: .streamEnd(StreamEnd(status: .completed, chunkCount: 9)))]
        XCTAssertEqual(
            try DetailChecks.stream(frames, answering: 3, request: request, hierarchy: hierarchy),
            details
        )

        // Colours may be off by 2 per channel, and images may have any scale.
        var close = details
        close[3].group = Canvas(width: 300, height: 180, Self.cardGreen.map { $0 == 255 ? 253 : $0 + 2 }).image()
        close[7].group = Canvas(width: 180, height: 90, Self.orange).image(scale: 3)
        XCTAssertNoThrow(try Self.demoPixels(close, hierarchy: hierarchy))
    }

    func test_S_PROBE_01_demoPixelChecksRejectChanges() {
        let clear: [UInt8] = [0, 0, 0, 0]
        // The card's rotation drawn into its image: the corners are empty.
        assertDemoRejects("the group image of CardView is [0, 0, 0, 0] at the point (0.5, 0.5)") { details in
            var rotated = Canvas(width: 300, height: 180, clear)
            rotated.fill(x: 60, y: 30, width: 180, height: 120, Self.cardGreen)
            details[3].group = rotated.image()
        }
        // The card's own opacity drawn into its image.
        assertDemoRejects("the group image of CardView") { details in
            details[3].group = Canvas(
                width: 300,
                height: 180,
                DetailChecks.pixel(red: 0, green: 0.6, blue: 0.3, alpha: 0.5)
            ).image()
        }
        assertDemoRejects("the solo image of CardView is missing") { $0[3].solo = nil }
        // The hidden shape layer rendered as nothing.
        assertDemoRejects("the group image of the CAShapeLayer is [0, 0, 0, 0] at the point (20.0, 20.0)") {
            $0[4].group = Canvas(width: 40, height: 40, clear).image()
        }
        // Its bounds filled: the circle's corners must be clear.
        assertDemoRejects("the group image of the CAShapeLayer") {
            $0[4].group = Canvas(width: 40, height: 40, Self.yellow).image()
        }
        // A solo image that shows the sublayers.
        assertDemoRejects("the solo image of the screen's view is [0, 128, 255, 255]") {
            $0[1].solo = $0[1].group
        }
        // A group image that does not.
        assertDemoRejects("the group image of the screen's view is [255, 255, 255, 255]") {
            $0[1].group = $0[1].solo
        }
        assertDemoRejects("the group image of the bare layer") {
            $0[7].group = Canvas(width: 60, height: 30, Self.white).image()
        }
        assertDemoRejects("the group image of the scroll view") {
            $0[5].group = Canvas(width: 300, height: 200, Self.white).image()
        }
        // Statuses: every layer with a size is captured, the one without is not.
        assertDemoRejects("the detail of layer 8 (CALayer, 60.0 x 30.0) has status captureFailed") {
            $0[7] = LayerDetail(layerID: 8, status: .captureFailed)
        }
        assertDemoRejects("the detail of layer 3 (_UILabelLayer, 200.0 x 24.0) has status layerNotFound") {
            $0[2] = LayerDetail(layerID: 3, status: .layerNotFound)
        }
        assertDemoRejects("the detail of layer 9 (CALayer, 0.0 x 0.0) has status ok") {
            $0[8] = LayerDetail(layerID: 9, status: .ok)
        }
        assertDemoRejects("there is no detail for layer 9") { $0.removeLast() }
    }
}
