#if !canImport(UIKit) || DEBUG || ReleaseEnabled
internal import CutawayFlatBuffers

// Each enumeration of the project next to its generated counterpart, both directions
// together, so that a case added to one is seen missing from the other.

extension ErrorCode {
    init(_ generated: Cutaway_Wire_ErrorCode) {
        switch generated {
        case .unknown: self = .unknown
        case .malformedframe: self = .malformedFrame
        case .unexpectedmessage: self = .unexpectedMessage
        case .busy: self = .busy
        case .appnotactive: self = .appNotActive
        case .internal_: self = .internalError
        case .layernotfound: self = .layerNotFound
        case .attributenoteditable: self = .attributeNotEditable
        case .invalidattributevalue: self = .invalidAttributeValue
        }
    }

    var generated: Cutaway_Wire_ErrorCode {
        switch self {
        case .unknown: return .unknown
        case .malformedFrame: return .malformedframe
        case .unexpectedMessage: return .unexpectedmessage
        case .busy: return .busy
        case .appNotActive: return .appnotactive
        case .internalError: return .internal_
        case .layerNotFound: return .layernotfound
        case .attributeNotEditable: return .attributenoteditable
        case .invalidAttributeValue: return .invalidattributevalue
        }
    }
}

extension AttributeSection {
    init(_ generated: Cutaway_Wire_AttributeSection) {
        switch generated {
        case .unspecified: self = .unspecified
        case .identity: self = .identity
        case .general: self = .general
        case .layout: self = .layout
        case .content: self = .content
        case .appearance: self = .appearance
        case .behavior: self = .behavior
        }
    }

    var generated: Cutaway_Wire_AttributeSection {
        switch self {
        case .unspecified: return .unspecified
        case .identity: return .identity
        case .general: return .general
        case .layout: return .layout
        case .content: return .content
        case .appearance: return .appearance
        case .behavior: return .behavior
        }
    }
}

extension AttributeUnit {
    init(_ generated: Cutaway_Wire_AttributeUnit) {
        switch generated {
        case .unspecified: self = .unspecified
        case .points: self = .points
        case .fraction: self = .fraction
        }
    }

    var generated: Cutaway_Wire_AttributeUnit {
        switch self {
        case .unspecified: return .unspecified
        case .points: return .points
        case .fraction: return .fraction
        }
    }
}

extension Origin {
    init(_ generated: Cutaway_Wire_Origin) {
        switch generated {
        case .unknown: self = .unknown
        case .system: self = .system
        case .app: self = .app
        }
    }

    var generated: Cutaway_Wire_Origin {
        switch self {
        case .unknown: return .unknown
        case .system: return .system
        case .app: return .app
        }
    }
}

extension ViewControllerVisibility {
    init(_ generated: Cutaway_Wire_ViewControllerVisibility) {
        switch generated {
        case .unknown: self = .unknown
        case .shown: self = .shown
        case .notshown: self = .notShown
        }
    }

    var generated: Cutaway_Wire_ViewControllerVisibility {
        switch self {
        case .unknown: return .unknown
        case .shown: return .shown
        case .notShown: return .notshown
        }
    }
}

extension LayoutGuideKind {
    init(_ generated: Cutaway_Wire_LayoutGuideKind) {
        switch generated {
        case .unknown: self = .unknown
        case .other: self = .other
        case .safearea: self = .safeArea
        case .layoutmargins: self = .layoutMargins
        case .readablecontent: self = .readableContent
        case .keyboard: self = .keyboard
        }
    }

    var generated: Cutaway_Wire_LayoutGuideKind {
        switch self {
        case .unknown: return .unknown
        case .other: return .other
        case .safeArea: return .safearea
        case .layoutMargins: return .layoutmargins
        case .readableContent: return .readablecontent
        case .keyboard: return .keyboard
        }
    }
}

extension StreamStatus {
    init(_ generated: Cutaway_Wire_StreamStatus) {
        switch generated {
        case .completed: self = .completed
        case .cancelled: self = .cancelled
        case .failed: self = .failed
        }
    }

    var generated: Cutaway_Wire_StreamStatus {
        switch self {
        case .completed: return .completed
        case .cancelled: return .cancelled
        case .failed: return .failed
        }
    }
}

extension AppState {
    init(_ generated: Cutaway_Wire_AppState) {
        switch generated {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        }
    }

    var generated: Cutaway_Wire_AppState {
        switch self {
        case .active: return .active
        case .inactive: return .inactive
        case .background: return .background
        }
    }
}

extension DeviceKind {
    init(_ generated: Cutaway_Wire_DeviceKind) {
        switch generated {
        case .unknown: self = .unknown
        case .phone: self = .phone
        case .pad: self = .pad
        case .mac: self = .mac
        }
    }

    var generated: Cutaway_Wire_DeviceKind {
        switch self {
        case .unknown: return .unknown
        case .phone: return .phone
        case .pad: return .pad
        case .mac: return .mac
        }
    }
}

extension DetailStatus {
    init(_ generated: Cutaway_Wire_DetailStatus) {
        switch generated {
        case .ok: self = .ok
        case .layernotfound: self = .layerNotFound
        case .capturefailed: self = .captureFailed
        }
    }

    var generated: Cutaway_Wire_DetailStatus {
        switch self {
        case .ok: return .ok
        case .layerNotFound: return .layernotfound
        case .captureFailed: return .capturefailed
        }
    }
}

extension AttributeValueKind {
    /// A value the running FlatBuffers does not know reads as `None` (P-ATTR-06).
    init(_ generated: Cutaway_Wire_AttributeValueKind) {
        switch generated {
        case .none_: self = .none
        case .boolvalue: self = .bool
        case .intvalue: self = .int
        case .doublevalue: self = .double
        case .stringvalue: self = .string
        case .colorvalue: self = .color
        case .pointvalue: self = .point
        case .sizevalue: self = .size
        case .rectvalue: self = .rect
        case .insetsvalue: self = .insets
        case .transformvalue: self = .transform
        case .enumvalue: self = .enumeration
        }
    }

    var generated: Cutaway_Wire_AttributeValueKind {
        switch self {
        case .none: return .none_
        case .bool: return .boolvalue
        case .int: return .intvalue
        case .double: return .doublevalue
        case .string: return .stringvalue
        case .color: return .colorvalue
        case .point: return .pointvalue
        case .size: return .sizevalue
        case .rect: return .rectvalue
        case .insets: return .insetsvalue
        case .transform: return .transformvalue
        case .enumeration: return .enumvalue
        }
    }
}

/// The two enumerations share their raw values.
extension LayoutAttribute {
    init(_ generated: Cutaway_Wire_LayoutAttribute) {
        self = LayoutAttribute(rawValue: generated.rawValue) ?? .notAnAttribute
    }

    var generated: Cutaway_Wire_LayoutAttribute {
        Cutaway_Wire_LayoutAttribute(rawValue: rawValue) ?? .notanattribute
    }
}

extension LayoutRelation {
    init(_ generated: Cutaway_Wire_LayoutRelation) {
        switch generated {
        case .equal: self = .equal
        case .lessthanorequal: self = .lessThanOrEqual
        case .greaterthanorequal: self = .greaterThanOrEqual
        }
    }

    var generated: Cutaway_Wire_LayoutRelation {
        switch self {
        case .equal: return .equal
        case .lessThanOrEqual: return .lessthanorequal
        case .greaterThanOrEqual: return .greaterthanorequal
        }
    }
}

extension LayoutItemKind {
    init(_ generated: Cutaway_Wire_LayoutItemKind) {
        switch generated {
        case .view: self = .view
        case .layoutguide: self = .layoutGuide
        case .other: self = .other
        }
    }

    var generated: Cutaway_Wire_LayoutItemKind {
        switch self {
        case .view: return .view
        case .layoutGuide: return .layoutguide
        case .other: return .other
        }
    }
}

extension ConstraintStatus {
    init(_ generated: Cutaway_Wire_ConstraintStatus) {
        switch generated {
        case .unknown: self = .unknown
        case .satisfied: self = .satisfied
        case .unsatisfied: self = .unsatisfied
        }
    }

    var generated: Cutaway_Wire_ConstraintStatus {
        switch self {
        case .unknown: return .unknown
        case .satisfied: return .satisfied
        case .unsatisfied: return .unsatisfied
        }
    }
}
#endif
