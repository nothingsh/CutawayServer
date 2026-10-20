#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

internal import CutawayFlatBuffers

// Values to generated types, for the object API.
extension FrameCodec {
    static func union(for message: Message) -> Cutaway_Wire_BodyUnion {
        switch message {
        case .hello(let hello):
            let object = Cutaway_Wire_HelloT()
            object.protocol_ = hello.version.map { Cutaway_Wire_Version(major: $0.major, minor: $0.minor) }
            object.role = hello.role == .server ? .server : .client
            object.client = hello.client.map { client in
                let info = Cutaway_Wire_ClientInfoT()
                info.name = client.name
                info.version = client.version
                return info
            }
            object.app = hello.app.map(appInfoObject(for:))
            return Cutaway_Wire_BodyUnion(object, type: .hello)
        case .getAppIcon:
            return Cutaway_Wire_BodyUnion(Cutaway_Wire_GetAppIconT(), type: .getappicon)
        case .appIcon(let icon):
            let object = Cutaway_Wire_AppIconT()
            object.image = icon.image.map(imageObject(for:))
            return Cutaway_Wire_BodyUnion(object, type: .appicon)
        case .getHierarchy:
            return Cutaway_Wire_BodyUnion(Cutaway_Wire_GetHierarchyT(), type: .gethierarchy)
        case .hierarchy(let hierarchy):
            let object = Cutaway_Wire_HierarchyT()
            object.nodes = hierarchy.nodes.map(layerNodeObject(for:))
            object.keyWindowId = hierarchy.keyWindowID
            return Cutaway_Wire_BodyUnion(object, type: .hierarchy)
        case .getLayerDetails(let get):
            let object = Cutaway_Wire_GetLayerDetailsT()
            object.requests = get.requests.map { request in
                let item = Cutaway_Wire_LayerDetailRequestT()
                item.layerId = request.layerID
                item.wantSolo = request.wantSolo
                item.wantGroup = request.wantGroup
                item.wantAttributes = request.wantAttributes
                item.wantConstraints = request.wantConstraints
                return item
            }
            object.maxTextureDimension = get.maxTextureDimension
            return Cutaway_Wire_BodyUnion(object, type: .getlayerdetails)
        case .layerDetailsChunk(let chunk):
            let object = Cutaway_Wire_LayerDetailsChunkT()
            object.sequence = chunk.sequence
            object.details = chunk.details.map(layerDetailObject(for:))
            return Cutaway_Wire_BodyUnion(object, type: .layerdetailschunk)
        case .streamEnd(let end):
            let object = Cutaway_Wire_StreamEndT()
            object.status = end.status.generated
            object.chunkCount = end.chunkCount
            object.error = end.error.map(errorObject(for:))
            return Cutaway_Wire_BodyUnion(object, type: .streamend)
        case .cancel(let targetRequestID):
            let object = Cutaway_Wire_CancelT()
            object.targetRequestId = targetRequestID
            return Cutaway_Wire_BodyUnion(object, type: .cancel)
        case .error(let error):
            return Cutaway_Wire_BodyUnion(errorObject(for: error), type: .error)
        case .appStateChanged(let state):
            let object = Cutaway_Wire_AppStateChangedT()
            object.state = state.generated
            return Cutaway_Wire_BodyUnion(object, type: .appstatechanged)
        case .setAttribute(let set):
            let object = Cutaway_Wire_SetAttributeT()
            object.layerId = set.layerID
            object.attributeId = set.attributeID
            object.value = set.value.map(attributeValueUnion(for:))
            return Cutaway_Wire_BodyUnion(object, type: .setattribute)
        case .setAttributeResult(let result):
            let object = Cutaway_Wire_SetAttributeResultT()
            object.layerId = result.layerID
            object.attributeGroups = result.attributeGroups.map(attributeGroupObject(for:))
            return Cutaway_Wire_BodyUnion(object, type: .setattributeresult)
        case .getSubtree(let rootID):
            let object = Cutaway_Wire_GetSubtreeT()
            object.rootId = rootID
            return Cutaway_Wire_BodyUnion(object, type: .getsubtree)
        case .getEnvironment, .setEnvironment, .environment:
            return environmentUnion(for: message)
        }
    }

    /// The messages of protocol 1.2's environment.
    private static func environmentUnion(for message: Message) -> Cutaway_Wire_BodyUnion {
        switch message {
        case .getEnvironment:
            return Cutaway_Wire_BodyUnion(Cutaway_Wire_GetEnvironmentT(), type: .getenvironment)
        case .setEnvironment(let overrides):
            let object = Cutaway_Wire_SetEnvironmentT()
            object.overrides = overrides.map(traitsObject(for:))
            return Cutaway_Wire_BodyUnion(object, type: .setenvironment)
        case .environment(let environment):
            let object = Cutaway_Wire_EnvironmentT()
            // P-ENV-01: absent is the same as every trait unspecified, as the fixtures write it.
            // Unknown values are not written, so they do not count.
            object.overrides = environment.overrides.hasKnownValues ? traitsObject(for: environment.overrides) : nil
            object.current = environment.current.hasKnownValues ? traitsObject(for: environment.current) : nil
            object.overridable = environment.overridable.map(\.generated)
            return Cutaway_Wire_BodyUnion(object, type: .environment)
        default:
            preconditionFailure("not a message of the environment: \(message)")
        }
    }

    /// `unknownKinds` is not written: a value this build does not know cannot be (P-ENV-04).
    private static func traitsObject(for traits: Traits) -> Cutaway_Wire_TraitsT {
        let object = Cutaway_Wire_TraitsT()
        object.userInterfaceStyle = traits.userInterfaceStyle.generated
        object.contentSizeCategory = traits.contentSizeCategory.generated
        object.layoutDirection = traits.layoutDirection.generated
        object.horizontalSizeClass = traits.horizontalSizeClass.generated
        object.verticalSizeClass = traits.verticalSizeClass.generated
        return object
    }

    private static func appInfoObject(for app: AppInfo) -> Cutaway_Wire_AppInfoT {
        let object = Cutaway_Wire_AppInfoT()
        object.name = app.name
        object.bundleId = app.bundleID
        object.appVersion = app.appVersion
        object.deviceName = app.deviceName
        object.deviceKind = app.deviceKind.generated
        object.isSimulator = app.isSimulator
        object.osName = app.osName
        object.osVersion = app.osVersion
        object.screenSize = Cutaway_Wire_Size(width: app.screenSize.width, height: app.screenSize.height)
        object.screenScale = app.screenScale
        object.serverVersion = app.serverVersion
        return object
    }

    private static func layerNodeObject(for node: LayerNode) -> Cutaway_Wire_LayerNodeT {
        let object = Cutaway_Wire_LayerNodeT()
        object.id = node.id
        object.parentId = node.parentID
        object.className = node.className
        object.displayClassName = node.displayClassName
        object.viewClassName = node.viewClassName
        object.viewDisplayClassName = node.viewDisplayClassName
        object.bounds = rectStruct(for: node.bounds)
        object.position = pointStruct(for: node.position)
        object.anchorPoint = pointStruct(for: node.anchorPoint)
        object.transform = transformStruct(for: node.transform)
        object.zPosition = node.zPosition
        object.hidden = node.isHidden
        object.opacity = node.opacity
        object.masksToBounds = node.masksToBounds
        object.viewControllerClassName = node.viewControllerClassName
        object.viewControllerDisplayClassName = node.viewControllerDisplayClassName
        object.memberReferences = node.memberReferences.map { reference in
            let referenceObject = Cutaway_Wire_MemberReferenceT()
            referenceObject.ownerClassName = reference.ownerClassName
            referenceObject.ownerDisplayClassName = reference.ownerDisplayClassName
            referenceObject.name = reference.name
            return referenceObject
        }
        object.layerAddress = node.layerAddress
        object.viewAddress = node.viewAddress ?? 0
        object.viewControllerAddress = node.viewControllerAddress ?? 0
        object.layerClassOrigin = node.layerClassOrigin.generated
        object.viewClassOrigin = node.viewClassOrigin.generated
        object.viewControllerClassOrigin = node.viewControllerClassOrigin.generated
        object.layerBaseClassName = node.layerBaseClassName
        object.viewBaseClassName = node.viewBaseClassName
        object.viewControllerVisibility = node.viewControllerVisibility.generated
        object.nodeKind = node.nodeKind.generated
        object.name = node.name
        object.collapsedByDefault = node.isCollapsedByDefault
        object.captureExcluded = node.isCaptureExcluded
        return object
    }

    private static func imageObject(for image: WireImage) -> Cutaway_Wire_ImageT {
        let object = Cutaway_Wire_ImageT()
        object.encoding = .bgra8premultipliedlzfse
        object.pixelWidth = image.pixelWidth
        object.pixelHeight = image.pixelHeight
        object.bytesPerRow = image.bytesPerRow
        object.scale = image.scale
        object.data = [UInt8](image.data)
        return object
    }

    private static func layerDetailObject(for detail: LayerDetail) -> Cutaway_Wire_LayerDetailT {
        let object = Cutaway_Wire_LayerDetailT()
        object.layerId = detail.layerID
        object.status = detail.status.generated
        // The generated initializer puts empty images there; an absent image has to be nil.
        object.solo = detail.solo.map(imageObject(for:))
        object.group = detail.group.map(imageObject(for:))
        object.attributeGroups = detail.attributeGroups.map(attributeGroupObject(for:))
        object.constraints = detail.constraints.map(layoutConstraintObject(for:))
        return object
    }

    private static func layoutConstraintObject(
        for constraint: LayoutConstraint
    ) -> Cutaway_Wire_LayoutConstraintT {
        let object = Cutaway_Wire_LayoutConstraintT()
        object.id = constraint.id
        object.className = constraint.className
        object.identifier = constraint.identifier
        object.firstItem = constraint.firstItem.map(layoutItemObject(for:))
        object.firstAttribute = constraint.firstAttribute.generated
        object.relation = constraint.relation.generated
        object.secondItem = constraint.secondItem.map(layoutItemObject(for:))
        object.secondAttribute = constraint.secondAttribute.generated
        object.multiplier = constraint.multiplier
        object.constant = constraint.constant
        object.priority = constraint.priority
        object.status = constraint.status.generated
        object.origin = constraint.origin.generated
        return object
    }

    private static func layoutItemObject(for item: LayoutItem) -> Cutaway_Wire_LayoutItemT {
        let object = Cutaway_Wire_LayoutItemT()
        object.kind = item.kind.generated
        object.layerId = item.layerID
        object.guideId = item.guideID
        object.className = item.className
        object.displayClassName = item.displayClassName
        object.identifier = item.identifier
        object.guideFrame = item.guideFrame.map(rectStruct(for:))
        object.guideKind = item.guideKind.generated
        return object
    }

    private static func attributeGroupObject(for group: AttributeGroup) -> Cutaway_Wire_AttributeGroupT {
        let object = Cutaway_Wire_AttributeGroupT()
        object.id = group.id
        object.title = group.title
        object.className = group.className
        object.fromApp = group.fromApp
        object.attributes = group.attributes.map { attribute in
            let attributeObject = Cutaway_Wire_AttributeT()
            attributeObject.id = attribute.id
            attributeObject.title = attribute.title
            attributeObject.value = attribute.value.map(attributeValueUnion(for:))
            attributeObject.editable = attribute.editable
            attributeObject.acceptsNil = attribute.acceptsNil
            attributeObject.valueKind = attribute.valueKind.generated
            attributeObject.section = attribute.section.generated
            attributeObject.limits = attribute.limits.map { limit in
                // An unused side keeps its defaults (P-ATTR-10).
                let limitObject = Cutaway_Wire_NumberLimitT()
                limitObject.minimum = limit.minimum ?? 0
                limitObject.hasMinimum = limit.minimum != nil
                limitObject.minimumExclusive = limit.minimumIsExclusive
                limitObject.maximum = limit.maximum ?? 0
                limitObject.hasMaximum = limit.maximum != nil
                limitObject.maximumExclusive = limit.maximumIsExclusive
                return limitObject
            }
            attributeObject.cluster = attribute.cluster
            attributeObject.slot = attribute.slot
            attributeObject.inactiveCause = attribute.inactiveCause
            attributeObject.unit = attribute.unit.generated
            return attributeObject
        }
        return object
    }

    private static func attributeValueUnion(
        for value: AttributeValue
    ) -> Cutaway_Wire_AttributeValueUnion {
        switch value {
        case .bool(let value):
            let object = Cutaway_Wire_BoolValueT()
            object.value = value
            return Cutaway_Wire_AttributeValueUnion(object, type: .boolvalue)
        case .int(let value):
            let object = Cutaway_Wire_IntValueT()
            object.value = value
            return Cutaway_Wire_AttributeValueUnion(object, type: .intvalue)
        case .double(let value):
            let object = Cutaway_Wire_DoubleValueT()
            object.value = value
            return Cutaway_Wire_AttributeValueUnion(object, type: .doublevalue)
        case .string(let value):
            let object = Cutaway_Wire_StringValueT()
            object.value = value
            return Cutaway_Wire_AttributeValueUnion(object, type: .stringvalue)
        case let .color(color, systemName, light, dark, name):
            let object = Cutaway_Wire_ColorValueT()
            object.systemName = systemName
            object.name = name
            object.value = colorStruct(for: color)
            object.light = light.map(colorStruct(for:))
            object.dark = dark.map(colorStruct(for:))
            return Cutaway_Wire_AttributeValueUnion(object, type: .colorvalue)
        case .point(let point):
            let object = Cutaway_Wire_PointValueT()
            object.value = pointStruct(for: point)
            return Cutaway_Wire_AttributeValueUnion(object, type: .pointvalue)
        case .size(let size):
            let object = Cutaway_Wire_SizeValueT()
            object.value = Cutaway_Wire_Size(width: size.width, height: size.height)
            return Cutaway_Wire_AttributeValueUnion(object, type: .sizevalue)
        case .rect(let rect):
            let object = Cutaway_Wire_RectValueT()
            object.value = rectStruct(for: rect)
            return Cutaway_Wire_AttributeValueUnion(object, type: .rectvalue)
        case .insets(let insets):
            let object = Cutaway_Wire_InsetsValueT()
            // The generated names carry an underscore: `left` and `right` are keywords to flatc.
            object.value = Cutaway_Wire_Insets(
                top: insets.top,
                left_: insets.left,
                bottom: insets.bottom,
                right_: insets.right
            )
            return Cutaway_Wire_AttributeValueUnion(object, type: .insetsvalue)
        case .transform(let transform):
            let object = Cutaway_Wire_TransformValueT()
            object.value = transformStruct(for: transform)
            return Cutaway_Wire_AttributeValueUnion(object, type: .transformvalue)
        case let .enumeration(value, cases, caseName, caseValues):
            let object = Cutaway_Wire_EnumValueT()
            object.value = value
            object.cases = cases
            object.caseName = caseName
            object.caseValues = caseValues
            return Cutaway_Wire_AttributeValueUnion(object, type: .enumvalue)
        case .layerReference(let references):
            let object = Cutaway_Wire_LayerReferenceValueT()
            object.references = references.map { reference in
                let referenceObject = Cutaway_Wire_ObjectReferenceT()
                referenceObject.layerId = reference.layerID
                referenceObject.className = reference.className
                referenceObject.displayClassName = reference.displayClassName
                return referenceObject
            }
            return Cutaway_Wire_AttributeValueUnion(object, type: .layerreferencevalue)
        }
    }

    private static func colorStruct(for color: WireColor) -> Cutaway_Wire_Color {
        Cutaway_Wire_Color(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }

    private static func pointStruct(for point: WirePoint) -> Cutaway_Wire_Point {
        Cutaway_Wire_Point(x: point.x, y: point.y)
    }

    private static func rectStruct(for rect: WireRect) -> Cutaway_Wire_Rect {
        Cutaway_Wire_Rect(
            origin: pointStruct(for: rect.origin),
            size: Cutaway_Wire_Size(width: rect.size.width, height: rect.size.height)
        )
    }

    private static func transformStruct(for transform: WireTransform) -> Cutaway_Wire_Transform3D {
        Cutaway_Wire_Transform3D(
            m11: transform.m11,
            m12: transform.m12,
            m13: transform.m13,
            m14: transform.m14,
            m21: transform.m21,
            m22: transform.m22,
            m23: transform.m23,
            m24: transform.m24,
            m31: transform.m31,
            m32: transform.m32,
            m33: transform.m33,
            m34: transform.m34,
            m41: transform.m41,
            m42: transform.m42,
            m43: transform.m43,
            m44: transform.m44
        )
    }

    private static func errorObject(for error: WireError) -> Cutaway_Wire_ErrorT {
        let object = Cutaway_Wire_ErrorT()
        object.code = error.code.generated
        object.message = error.message
        return object
    }
}
#endif
