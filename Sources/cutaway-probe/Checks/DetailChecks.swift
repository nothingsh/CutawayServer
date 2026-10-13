import CutawayWire
import Foundation

/// What the answer to a `GetLayerDetails` has to look like. Every function throws a
/// `ProbeFailure` naming the first thing that is wrong.
enum DetailChecks {
    /// P-DET-06: the uncompressed pixels of all images of one chunk.
    static let chunkBudget = ProtocolLimits.chunkPixelBudget
    /// P-DET-08: the uncompressed pixels of one image.
    static let imageBudget = ProtocolLimits.maximumImageByteCount

    /// What a stream delivered, for the probe's report.
    struct Summary: Equatable {
        var layers = 0
        var chunks = 0
        var images = 0
        var captureFailed = 0
        var notFound = 0
        var attributeGroups = 0
        var attributes = 0
    }

    /// Checks the frames that answered `request`, from the first one to the `StreamEnd`, and
    /// returns the details in the order they arrived.
    ///
    /// - Parameter hierarchy: Where the requested layers come from; it says how large each
    ///   image has to be and which layers have sublayers.
    static func stream(
        _ frames: [Frame],
        answering requestID: UInt32,
        request: GetLayerDetails,
        hierarchy: Hierarchy,
        version: ProtocolVersion = .current
    ) throws -> [LayerDetail] {
        let (chunks, streamEnd) = try collect(frames, answering: requestID)
        try check(streamEnd, chunkCount: chunks.count)

        // P-DET-01, P-DET-06: every requested layer once, in the order of the request.
        let details = chunks.flatMap(\.details)
        try checkOrder(of: details, request: request)

        var nodes: [UInt64: LayerNode] = [:]
        var parents = Set<UInt64>()
        for node in hierarchy.nodes {
            nodes[node.id] = node
            parents.insert(node.parentID)
        }
        var tables = ConstraintChecks.Tables()
        for (item, detail) in zip(request.requests, details) {
            try check(
                detail,
                for: item,
                node: nodes[detail.layerID],
                hasSublayers: parents.contains(detail.layerID),
                maxTextureDimension: request.maxTextureDimension,
                version: version
            )
            try ConstraintChecks.structure(
                detail,
                for: item,
                node: nodes[detail.layerID],
                nodes: nodes,
                tables: &tables
            )
        }

        try checkBudgets(of: chunks)
        return details
    }

    /// The chunks of the stream that answered `requestID`, in order, and its `StreamEnd`.
    private static func collect(
        _ frames: [Frame],
        answering requestID: UInt32
    ) throws -> (chunks: [LayerDetailsChunk], end: StreamEnd) {
        var chunks: [LayerDetailsChunk] = []
        var streamEnd: StreamEnd?
        for frame in frames {
            guard streamEnd == nil else {
                throw ProbeFailure("\(Checks.describe(frame)) follows the StreamEnd (P-REQ-03)")
            }
            guard frame.requestID == requestID else {
                throw ProbeFailure(
                    "expected a frame of stream \(requestID), got \(Checks.describe(frame)) (P-REQ-03)"
                )
            }
            switch frame.body {
            case .layerDetailsChunk(let chunk):
                guard chunk.sequence == UInt32(chunks.count) else {
                    throw ProbeFailure(
                        "LayerDetailsChunk has sequence \(chunk.sequence), expected \(chunks.count) (P-REQ-03)"
                    )
                }
                chunks.append(chunk)
            case .streamEnd(let end):
                streamEnd = end
            default:
                throw ProbeFailure(
                    "expected LayerDetailsChunk or StreamEnd, got \(Checks.describe(frame)) (P-REQ-03)"
                )
            }
        }
        guard let streamEnd else {
            throw ProbeFailure("the stream has no StreamEnd (P-REQ-03)")
        }
        return (chunks, streamEnd)
    }

    /// P-REQ-03, P-REQ-05: a stream that completed, with `chunkCount` chunks.
    private static func check(_ streamEnd: StreamEnd, chunkCount: Int) throws {
        guard streamEnd.status == .completed else {
            let reason = streamEnd.error.map { ": \($0.code), \($0.message)" } ?? ""
            throw ProbeFailure("the stream ended with status \(streamEnd.status)\(reason), expected completed")
        }
        guard streamEnd.error == nil else {
            throw ProbeFailure("StreamEnd has status completed and an error (P-REQ-05)")
        }
        guard streamEnd.chunkCount == UInt32(chunkCount) else {
            throw ProbeFailure(
                "StreamEnd.chunk_count is \(streamEnd.chunkCount), but \(chunkCount) chunks arrived (P-REQ-03)"
            )
        }
    }

    /// P-DET-01, P-DET-06: every requested layer once, in the order of the request.
    private static func checkOrder(of details: [LayerDetail], request: GetLayerDetails) throws {
        let wanted = request.requests.map(\.layerID)
        let got = details.map(\.layerID)
        guard got == wanted else {
            if let index = zip(got, wanted).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                throw ProbeFailure(
                    "detail \(index) is for layer \(got[index]), but the request's item \(index) is layer \(wanted[index]) (P-DET-01, P-DET-06)"
                )
            }
            throw ProbeFailure(
                "\(got.count) details arrived for \(wanted.count) requested layers (P-DET-01)"
            )
        }
    }

    /// P-DET-06: the pixels of a chunk with more than one detail stay within the budget.
    private static func checkBudgets(of chunks: [LayerDetailsChunk]) throws {
        for chunk in chunks where chunk.details.count > 1 {
            let bytes = chunk.details.flatMap { [$0.solo, $0.group] }.compactMap { $0 }
                .reduce(0) { $0 + Int($1.bytesPerRow) * Int($1.pixelHeight) }
            guard bytes <= chunkBudget else {
                throw ProbeFailure(
                    "chunk \(chunk.sequence) holds \(chunk.details.count) details with \(bytes) bytes of pixels, above \(chunkBudget) (P-DET-06)"
                )
            }
        }
    }

    private static func check(
        _ detail: LayerDetail,
        for request: LayerDetailRequest,
        node: LayerNode?,
        hasSublayers: Bool,
        maxTextureDimension: UInt32,
        version: ProtocolVersion
    ) throws {
        let name = "the detail of layer \(detail.layerID)"
        let wantsImage = request.wantSolo || request.wantGroup
        try checkAttributes(of: detail, for: request, name: name, version: version)
        switch detail.status {
        case .layerNotFound:
            guard detail.solo == nil, detail.group == nil else {
                throw ProbeFailure("\(name) is LayerNotFound and has an image (P-DET-02)")
            }
            return
        case .captureFailed:
            guard detail.solo == nil, detail.group == nil else {
                throw ProbeFailure("\(name) is CaptureFailed and has an image (P-DET-03)")
            }
            return
        case .ok:
            break
        }

        guard let node else {
            throw ProbeFailure("\(name) is Ok, but the hierarchy has no such layer")
        }
        let size = node.bounds.size
        if wantsImage {
            guard size.width > 0, size.height > 0 else {
                throw ProbeFailure(
                    "\(name) is Ok, but the layer is \(size.width) x \(size.height) points: expected CaptureFailed (P-DET-03)"
                )
            }
        }
        guard request.wantSolo || detail.solo == nil, request.wantGroup || detail.group == nil else {
            throw ProbeFailure("\(name) has an image that was not requested")
        }
        if request.wantGroup {
            guard detail.group != nil else { throw ProbeFailure("\(name) is Ok and has no group image") }
        }
        if request.wantSolo, detail.solo == nil {
            // P-DET-04: the solo may be left out when the group stands for it.
            guard request.wantGroup, !hasSublayers else {
                throw ProbeFailure(
                    "\(name) has no solo image: it may only be left out when the group was requested too and the layer has no sublayers (P-DET-04)"
                )
            }
        }
        for (kind, image) in [("solo", detail.solo), ("group", detail.group)] {
            guard let image else { continue }
            try check(image, name: "\(name): \(kind)", bounds: size, maxTextureDimension: maxTextureDimension)
        }
    }

    /// P-DET-02: the attributes of a detail, as its status and the request say.
    private static func checkAttributes(
        of detail: LayerDetail,
        for request: LayerDetailRequest,
        name: String,
        version: ProtocolVersion
    ) throws {
        if detail.status == .layerNotFound {
            guard detail.attributeGroups.isEmpty else {
                throw ProbeFailure("\(name) is LayerNotFound and has attributes (P-DET-02)")
            }
        } else if !request.wantAttributes {
            guard detail.attributeGroups.isEmpty else {
                throw ProbeFailure("\(name) has attributes, but the request did not want them")
            }
        } else {
            guard !detail.attributeGroups.isEmpty else {
                throw ProbeFailure("\(name) has no attributes, but the request wanted them")
            }
            try AttributeChecks.structure(detail.attributeGroups, name: name, version: version)
        }
    }

    /// One image of a detail that is Ok, of a layer whose bounds are `size`.
    private static func check(
        _ image: WireImage,
        name imageName: String,
        bounds size: WireSize,
        maxTextureDimension: UInt32
    ) throws {
        try Checks.image(image, name: imageName)
        let bytes = Int(image.bytesPerRow) * Int(image.pixelHeight)
        guard bytes <= imageBudget else {
            throw ProbeFailure("\(imageName) has \(bytes) bytes of pixels, above \(imageBudget) (P-DET-08)")
        }
        if maxTextureDimension != 0 {
            guard max(image.pixelWidth, image.pixelHeight) <= maxTextureDimension else {
                throw ProbeFailure(
                    "\(imageName) is \(image.pixelWidth) x \(image.pixelHeight) pixels, above max_texture_dimension \(maxTextureDimension) (P-DET-05)"
                )
            }
        }
        // P-DET-07: the image covers the bounds, so its size is the bounds times the scale,
        // within the pixel that rounding costs. `scale` is a Float, exact to about one part
        // in ten million: for a long image that alone is a few thousandths of a pixel more.
        let scale = Double(image.scale)
        func isClose(_ pixels: UInt32, to points: Double) -> Bool {
            abs(Double(pixels) - points * scale) <= 1 + Double(pixels) * 1e-6
        }
        guard isClose(image.pixelWidth, to: size.width), isClose(image.pixelHeight, to: size.height)
        else {
            throw ProbeFailure(
                "\(imageName) is \(image.pixelWidth) x \(image.pixelHeight) pixels at scale \(image.scale), but the layer's bounds are \(size.width) x \(size.height) points (P-DET-07)"
            )
        }
    }

    static func summary(of details: [LayerDetail], chunks: Int) -> Summary {
        Summary(
            layers: details.count,
            chunks: chunks,
            images: details.reduce(0) { $0 + ($1.solo == nil ? 0 : 1) + ($1.group == nil ? 0 : 1) },
            captureFailed: details.filter { $0.status == .captureFailed }.count,
            notFound: details.filter { $0.status == .layerNotFound }.count,
            attributeGroups: details.reduce(0) { $0 + $1.attributeGroups.count },
            attributes: details.reduce(0) { $0 + $1.attributeGroups.reduce(0) { $0 + $1.attributes.count } }
        )
    }
}
