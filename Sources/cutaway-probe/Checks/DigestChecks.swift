import CutawayWire
import Foundation

/// The digests of images and unchanged images (protocol 1.3; P-DET-11, P-IMG-04, P-IMG-05).
/// Every function throws a `ProbeFailure` naming the first thing that is wrong.
enum DigestChecks {
    /// Checks an image's digest against what the request held for its kind; returns whether
    /// the image has pixels to check further (an unchanged one has none).
    static func digest(of image: WireImage, name: String, known: Data?, version: ProtocolVersion) throws -> Bool {
        if image.isUnchanged {
            guard version.supportsImageDigests else {
                throw ProbeFailure("\(name) is unchanged, but the negotiated version is below 1.3 (P-IMG-05)")
            }
            guard let known, image.digest == known else {
                throw ProbeFailure("\(name) is unchanged, but its digest is not the one the request gave (P-IMG-05)")
            }
            guard image.data.isEmpty, image.pixelWidth == 0, image.pixelHeight == 0, image.bytesPerRow == 0,
                  !image.isComposited else {
                throw ProbeFailure("\(name) is unchanged, but has fields other than its digest (P-IMG-05)")
            }
            return false
        }
        if version.supportsImageDigests {
            guard let digest = image.digest, (1...32).contains(digest.count) else {
                throw ProbeFailure("\(name) has no digest of 1 to 32 bytes (P-IMG-04)")
            }
        } else if image.isComposited {
            throw ProbeFailure("\(name) is composited, but the negotiated version is below 1.3 (P-IMG-07)")
        }
        return true
    }

    /// P-IMG-04: two images with the same digest have the same size, scale, `composited` and
    /// pixels, padding left out; returns how many digests there are.
    static func sameDigestsSamePixels(_ details: [LayerDetail]) throws -> Int {
        var seen: [Data: (content: Content, name: String)] = [:]
        for detail in details {
            for (kind, image) in [("solo", detail.solo), ("group", detail.group)] {
                guard let image, !image.isUnchanged, let digest = image.digest else { continue }
                let name = "the \(kind) of layer \(detail.layerID)"
                let content = try Content(image, name: name)
                if let earlier = seen[digest] {
                    guard earlier.content == content else {
                        throw ProbeFailure("\(name) has the digest of \(earlier.name), but other content (P-IMG-04)")
                    }
                } else {
                    seen[digest] = (content, name)
                }
            }
        }
        return seen.count
    }

    /// The images of `request` again, each with the digest just received for it.
    static func request(holding details: [LayerDetail], of request: GetLayerDetails) -> GetLayerDetails {
        let byID = Dictionary(details.map { ($0.layerID, $0) }, uniquingKeysWith: { first, _ in first })
        let items = request.requests.compactMap { item -> LayerDetailRequest? in
            guard let detail = byID[item.layerID], detail.solo != nil || detail.group != nil else { return nil }
            return LayerDetailRequest(
                layerID: item.layerID,
                wantSolo: item.wantSolo,
                wantGroup: item.wantGroup,
                wantAttributes: false,
                knownSoloDigest: detail.solo?.digest,
                knownGroupDigest: detail.group?.digest
            )
        }
        return GetLayerDetails(requests: items, maxTextureDimension: request.maxTextureDimension)
    }

    /// Every image answering `request`, which held them all, is unchanged; returns how many.
    static func allUnchanged(_ details: [LayerDetail], request: GetLayerDetails) throws -> Int {
        var count = 0
        for detail in details {
            for (kind, image) in [("solo", detail.solo), ("group", detail.group)] {
                guard let image else { continue }
                guard image.isUnchanged else {
                    throw ProbeFailure(
                        "the \(kind) of layer \(detail.layerID) came back in full although nothing changed (P-IMG-05)"
                    )
                }
                count += 1
            }
        }
        return count
    }

    /// What P-IMG-04 compares: the size, the scale, `composited` and the pixels without their
    /// padding.
    private struct Content: Equatable {
        let width: UInt32
        let height: UInt32
        let scale: Float
        let isComposited: Bool
        let pixels: Data

        init(_ image: WireImage, name: String) throws {
            guard let decompressed = try? (image.data as NSData).decompressed(using: .lzfse) as Data else {
                throw ProbeFailure("\(name): data is not LZFSE (P-IMG-01)")
            }
            let row = Int(image.pixelWidth) * 4
            let stride = Int(image.bytesPerRow)
            var pixels = Data(capacity: row * Int(image.pixelHeight))
            for start in Swift.stride(from: 0, to: stride * Int(image.pixelHeight), by: stride) {
                pixels.append(decompressed[start..<start + row])
            }
            width = image.pixelWidth
            height = image.pixelHeight
            scale = image.scale
            isComposited = image.isComposited
            self.pixels = pixels
        }
    }
}
