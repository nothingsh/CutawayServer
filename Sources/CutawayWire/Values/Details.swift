#if !canImport(UIKit) || DEBUG || ReleaseEnabled

// The value types of layer details (PROTOCOL.md, "Layer details"). Images are in Images.swift,
// attributes in Attributes.swift, constraints in Layout.swift.

/// What a client wants to know about one layer.
public struct LayerDetailRequest: Sendable, Equatable {
    public var layerID: UInt64
    public var wantSolo: Bool
    public var wantGroup: Bool
    public var wantAttributes: Bool
    /// The constraints that refer to the layer's view (P-LAYOUT-01, protocol 0.4).
    public var wantConstraints: Bool

    public init(
        layerID: UInt64,
        wantSolo: Bool,
        wantGroup: Bool,
        wantAttributes: Bool,
        wantConstraints: Bool = false
    ) {
        self.layerID = layerID
        self.wantSolo = wantSolo
        self.wantGroup = wantGroup
        self.wantAttributes = wantAttributes
        self.wantConstraints = wantConstraints
    }
}

public struct GetLayerDetails: Sendable, Equatable {
    public var requests: [LayerDetailRequest]
    /// In pixels; 0 means no limit (P-DET-05).
    public var maxTextureDimension: UInt32

    public init(requests: [LayerDetailRequest], maxTextureDimension: UInt32) {
        self.requests = requests
        self.maxTextureDimension = maxTextureDimension
    }
}

public enum DetailStatus: Sendable, Equatable {
    case ok
    case layerNotFound
    case captureFailed
    /// The host app excludes the node from images (P-DET-10, protocol 1.2).
    case excluded
}

/// What a server knows about one requested layer. Absent groups read as an empty array.
public struct LayerDetail: Sendable, Equatable {
    public var layerID: UInt64
    public var status: DetailStatus
    /// The layer without its sublayers.
    public var solo: WireImage?
    /// The layer with its whole subtree.
    public var group: WireImage?
    public var attributeGroups: [AttributeGroup]
    /// Absent on the wire reads as empty; P-LAYOUT-01 allows either.
    public var constraints: [LayoutConstraint]

    public init(
        layerID: UInt64,
        status: DetailStatus,
        solo: WireImage? = nil,
        group: WireImage? = nil,
        attributeGroups: [AttributeGroup] = [],
        constraints: [LayoutConstraint] = []
    ) {
        self.layerID = layerID
        self.status = status
        self.solo = solo
        self.group = group
        self.attributeGroups = attributeGroups
        self.constraints = constraints
    }
}

extension LayerDetail {
    /// P-HELLO-04, P-LAYOUT-08, P-ATTR-08, P-ATTR-14, P-LAYOUT-04: the detail as a peer working
    /// at `version` may receive it. Every layout attribute that `version` does not name becomes
    /// `notAnAttribute`, every section and unit it does not have `unspecified`, and every guide
    /// kind it does not have `other`; nothing else changes.
    public func adapted(to version: ProtocolVersion) -> LayerDetail {
        var detail = self
        detail.attributeGroups = attributeGroups.map { $0.adapted(to: version) }
        detail.constraints = constraints.map { $0.adapted(to: version) }
        return detail
    }
}

extension LayerDetail {
    /// The same for the detail that answers `request`: before 1.2 there is no `excluded`, and a
    /// node excluded from images is `captureFailed` when an image was requested and `ok`
    /// otherwise (P-DET-10).
    public func adapted(to version: ProtocolVersion, for request: LayerDetailRequest) -> LayerDetail {
        var detail = adapted(to: version)
        if detail.status == .excluded, !version.supportsExcludedStatus {
            detail.status = request.wantSolo || request.wantGroup ? .captureFailed : .ok
        }
        return detail
    }
}

public struct LayerDetailsChunk: Sendable, Equatable {
    /// Starts at 0 and grows by 1 (P-REQ-03).
    public var sequence: UInt32
    public var details: [LayerDetail]

    public init(sequence: UInt32, details: [LayerDetail]) {
        self.sequence = sequence
        self.details = details
    }
}
#endif
