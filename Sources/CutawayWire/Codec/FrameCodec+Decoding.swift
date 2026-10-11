#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

internal import CutawayFlatBuffers

// Generated types to values, from a verified buffer.
extension FrameCodec {
    static func message(of frame: Cutaway_Wire_Frame) throws -> Message? {
        switch frame.bodyType {
        case .none_:
            return nil
        case .hello:
            return .hello(try hello(of: frame))
        case .getappicon:
            return .getAppIcon
        case .appicon:
            let icon = try body(of: frame, as: Cutaway_Wire_AppIcon.self)
            return .appIcon(
                AppIcon(
                    image: icon.image.map(wireImage(of:))
                )
            )
        case .gethierarchy:
            return .getHierarchy
        case .hierarchy:
            let hierarchy = try body(of: frame, as: Cutaway_Wire_Hierarchy.self)
            return .hierarchy(
                Hierarchy(nodes: hierarchy.nodes.map(layerNode(of:)), keyWindowID: hierarchy.keyWindowId)
            )
        case .getlayerdetails:
            return .getLayerDetails(try getLayerDetails(of: frame))
        case .layerdetailschunk:
            let chunk = try body(of: frame, as: Cutaway_Wire_LayerDetailsChunk.self)
            return .layerDetailsChunk(
                LayerDetailsChunk(
                    sequence: chunk.sequence,
                    details: try chunk.details.map(layerDetail(of:))
                )
            )
        case .streamend:
            let end = try body(of: frame, as: Cutaway_Wire_StreamEnd.self)
            return .streamEnd(
                StreamEnd(
                    status: StreamStatus(end.status),
                    chunkCount: end.chunkCount,
                    error: end.error.map(wireError(of:))
                )
            )
        case .cancel:
            let cancel = try body(of: frame, as: Cutaway_Wire_Cancel.self)
            return .cancel(targetRequestID: cancel.targetRequestId)
        case .error:
            return .error(wireError(of: try body(of: frame, as: Cutaway_Wire_Error.self)))
        case .appstatechanged:
            let changed = try body(of: frame, as: Cutaway_Wire_AppStateChanged.self)
            return .appStateChanged(AppState(changed.state))
        case .setattribute:
            let set = try body(of: frame, as: Cutaway_Wire_SetAttribute.self)
            return .setAttribute(
                SetAttribute(
                    layerID: set.layerId,
                    attributeID: set.attributeId ?? "",
                    value: try attributeValue(of: set)
                )
            )
        case .setattributeresult:
            let result = try body(of: frame, as: Cutaway_Wire_SetAttributeResult.self)
            return .setAttributeResult(
                SetAttributeResult(
                    layerID: result.layerId,
                    attributeGroups: try result.attributeGroups.map(attributeGroup(of:))
                )
            )
        case .getsubtree:
            let get = try body(of: frame, as: Cutaway_Wire_GetSubtree.self)
            return .getSubtree(rootID: get.rootId)
        }
    }

    private static func hello(of frame: Cutaway_Wire_Frame) throws -> Hello {
        let hello = try body(of: frame, as: Cutaway_Wire_Hello.self)
        return Hello(
            version: hello.protocol_.map { ProtocolVersion(major: $0.major, minor: $0.minor) },
            role: hello.role == .server ? .server : .client,
            client: hello.client.map { ClientInfo(name: $0.name ?? "", version: $0.version ?? "") },
            app: hello.app.map(appInfo(of:))
        )
    }

    private static func getLayerDetails(of frame: Cutaway_Wire_Frame) throws -> GetLayerDetails {
        let get = try body(of: frame, as: Cutaway_Wire_GetLayerDetails.self)
        return GetLayerDetails(
            requests: get.requests.map { request in
                LayerDetailRequest(
                    layerID: request.layerId,
                    wantSolo: request.wantSolo,
                    wantGroup: request.wantGroup,
                    wantAttributes: request.wantAttributes,
                    wantConstraints: request.wantConstraints
                )
            },
            maxTextureDimension: get.maxTextureDimension
        )
    }

    private static func body<T: FlatbuffersInitializable>(
        of frame: Cutaway_Wire_Frame,
        as type: T.Type
    ) throws -> T {
        guard let body = frame.body(type: type) else { throw WireFailure.malformed }
        return body
    }

    private static func appInfo(of app: Cutaway_Wire_AppInfo) -> AppInfo {
        AppInfo(
            name: app.name ?? "",
            bundleID: app.bundleId ?? "",
            appVersion: app.appVersion ?? "",
            deviceName: app.deviceName ?? "",
            deviceKind: DeviceKind(app.deviceKind),
            isSimulator: app.isSimulator,
            osName: app.osName ?? "",
            osVersion: app.osVersion ?? "",
            screenSize: WireSize(
                width: app.screenSize?.width ?? 0,
                height: app.screenSize?.height ?? 0
            ),
            screenScale: app.screenScale,
            serverVersion: app.serverVersion ?? ""
        )
    }

    /// A geometry field that is absent reads as zeros.
    private static func layerNode(of node: Cutaway_Wire_LayerNode) -> LayerNode {
        LayerNode(
            id: node.id,
            parentID: node.parentId,
            className: node.className ?? "",
            displayClassName: node.displayClassName ?? "",
            viewClassName: node.viewClassName,
            viewDisplayClassName: node.viewDisplayClassName,
            bounds: wireRect(of: node.bounds),
            position: wirePoint(of: node.position),
            anchorPoint: wirePoint(of: node.anchorPoint),
            transform: wireTransform(of: node.transform),
            zPosition: node.zPosition,
            isHidden: node.hidden,
            opacity: node.opacity,
            masksToBounds: node.masksToBounds,
            viewControllerClassName: node.viewControllerClassName,
            viewControllerDisplayClassName: node.viewControllerDisplayClassName,
            memberReferences: node.memberReferences.map { reference in
                MemberReference(
                    ownerClassName: reference.ownerClassName ?? "",
                    ownerDisplayClassName: reference.ownerDisplayClassName ?? "",
                    name: reference.name ?? ""
                )
            }
        )
    }

    private static func wirePoint(of point: Cutaway_Wire_Point?) -> WirePoint {
        let point = point ?? Cutaway_Wire_Point()
        return WirePoint(x: point.x, y: point.y)
    }

    private static func wireSize(of size: Cutaway_Wire_Size?) -> WireSize {
        let size = size ?? Cutaway_Wire_Size()
        return WireSize(width: size.width, height: size.height)
    }

    private static func wireRect(of rect: Cutaway_Wire_Rect?) -> WireRect {
        let rect = rect ?? Cutaway_Wire_Rect()
        return WireRect(origin: wirePoint(of: rect.origin), size: wireSize(of: rect.size))
    }

    private static func wireTransform(of transform: Cutaway_Wire_Transform3D?) -> WireTransform {
        let matrix = transform ?? Cutaway_Wire_Transform3D()
        return WireTransform(
            m11: matrix.m11,
            m12: matrix.m12,
            m13: matrix.m13,
            m14: matrix.m14,
            m21: matrix.m21,
            m22: matrix.m22,
            m23: matrix.m23,
            m24: matrix.m24,
            m31: matrix.m31,
            m32: matrix.m32,
            m33: matrix.m33,
            m34: matrix.m34,
            m41: matrix.m41,
            m42: matrix.m42,
            m43: matrix.m43,
            m44: matrix.m44
        )
    }

    private static func wireImage(of image: Cutaway_Wire_Image) -> WireImage {
        WireImage(
            encoding: .bgra8PremultipliedLZFSE,
            pixelWidth: image.pixelWidth,
            pixelHeight: image.pixelHeight,
            bytesPerRow: image.bytesPerRow,
            scale: image.scale,
            data: Data(image.data)
        )
    }

    private static func layerDetail(of detail: Cutaway_Wire_LayerDetail) throws -> LayerDetail {
        LayerDetail(
            layerID: detail.layerId,
            status: DetailStatus(detail.status),
            solo: detail.solo.map(wireImage(of:)),
            group: detail.group.map(wireImage(of:)),
            attributeGroups: try detail.attributeGroups.map(attributeGroup(of:)),
            constraints: detail.constraints.map(layoutConstraint(of:))
        )
    }

    private static func layoutConstraint(of constraint: Cutaway_Wire_LayoutConstraint) -> LayoutConstraint {
        LayoutConstraint(
            id: constraint.id,
            className: constraint.className,
            identifier: constraint.identifier,
            firstItem: constraint.firstItem.map(layoutItem(of:)),
            firstAttribute: LayoutAttribute(constraint.firstAttribute),
            relation: LayoutRelation(constraint.relation),
            secondItem: constraint.secondItem.map(layoutItem(of:)),
            secondAttribute: LayoutAttribute(constraint.secondAttribute),
            multiplier: constraint.multiplier,
            constant: constraint.constant,
            priority: constraint.priority,
            status: ConstraintStatus(constraint.status)
        )
    }

    private static func layoutItem(of item: Cutaway_Wire_LayoutItem) -> LayoutItem {
        LayoutItem(
            kind: LayoutItemKind(item.kind),
            layerID: item.layerId,
            guideID: item.guideId,
            className: item.className,
            displayClassName: item.displayClassName,
            identifier: item.identifier,
            guideFrame: item.guideFrame.map(wireRect(of:))
        )
    }

    private static func attributeGroup(of group: Cutaway_Wire_AttributeGroup) throws -> AttributeGroup {
        AttributeGroup(
            id: group.id ?? "",
            title: group.title ?? "",
            attributes: try group.attributes.map { attribute in
                Attribute(
                    id: attribute.id ?? "",
                    title: attribute.title ?? "",
                    value: try attributeValue(of: attribute),
                    editable: attribute.editable,
                    acceptsNil: attribute.acceptsNil,
                    valueKind: AttributeValueKind(attribute.valueKind)
                )
            }
        )
    }

    /// `nil` when the holder has no value.
    private static func attributeValue<Holder: AttributeValueHolder>(
        of holder: Holder
    ) throws -> AttributeValue? {
        func member<T: FlatbuffersInitializable>(_ type: T.Type) throws -> T {
            guard let member = holder.value(type: type) else { throw WireFailure.malformed }
            return member
        }
        switch holder.valueType {
        case .none_:
            return nil
        case .boolvalue:
            return .bool(try member(Cutaway_Wire_BoolValue.self).value)
        case .intvalue:
            return .int(try member(Cutaway_Wire_IntValue.self).value)
        case .doublevalue:
            return .double(try member(Cutaway_Wire_DoubleValue.self).value)
        case .stringvalue:
            return .string(try member(Cutaway_Wire_StringValue.self).value ?? "")
        case .colorvalue:
            let color = try member(Cutaway_Wire_ColorValue.self).value ?? Cutaway_Wire_Color()
            return .color(
                WireColor(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
            )
        case .pointvalue:
            return .point(wirePoint(of: try member(Cutaway_Wire_PointValue.self).value))
        case .sizevalue:
            return .size(wireSize(of: try member(Cutaway_Wire_SizeValue.self).value))
        case .rectvalue:
            return .rect(wireRect(of: try member(Cutaway_Wire_RectValue.self).value))
        case .insetsvalue:
            let insets = try member(Cutaway_Wire_InsetsValue.self).value ?? Cutaway_Wire_Insets()
            return .insets(
                WireInsets(
                    top: insets.top,
                    left: insets.left_,
                    bottom: insets.bottom,
                    right: insets.right_
                )
            )
        case .transformvalue:
            return .transform(wireTransform(of: try member(Cutaway_Wire_TransformValue.self).value))
        case .enumvalue:
            let value = try member(Cutaway_Wire_EnumValue.self)
            return .enumeration(
                value: value.value,
                cases: value.cases.map { $0 ?? "" },
                caseName: value.caseName ?? "",
                caseValues: Array(value.caseValues)
            )
        }
    }

    private static func wireError(of error: Cutaway_Wire_Error) -> WireError {
        WireError(code: ErrorCode(error.code), message: error.message ?? "")
    }
}

/// A table with a field of the `AttributeValue` union named `value`: `Attribute` and
/// `SetAttribute`.
private protocol AttributeValueHolder {
    var valueType: Cutaway_Wire_AttributeValue { get }
    func value<T: FlatbuffersInitializable>(type: T.Type) -> T?
}

extension Cutaway_Wire_Attribute: AttributeValueHolder {}
extension Cutaway_Wire_SetAttribute: AttributeValueHolder {}
#endif
