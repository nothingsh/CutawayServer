#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Values from the wire as UIKit and Core Animation take them.
enum AttributeInputs {
    static func number(_ value: AttributeValue?, _ rule: AttributeNumberRule) -> Result<Double, AttributeRejection> {
        guard case .double(let number)? = value else { return .failure(.otherKind) }
        return rule.apply(number)
    }

    /// In sRGB, each channel clamped to 0...1 (P-ATTR-04, P-SET-04). `nil` stays nil.
    static func color(_ value: AttributeValue?) -> Result<CGColor?, AttributeRejection> {
        guard let value else { return .success(nil) }
        guard case .color(let color) = value else { return .failure(.otherKind) }
        let channels = [color.red, color.green, color.blue, color.alpha].map(channel)
        return .success(
            CGColor(srgbRed: channels[0], green: channels[1], blue: channels[2], alpha: channels[3])
        )
    }

    /// One colour channel clamped to 0...1. Core Graphics clamps an sRGB colour as well, but
    /// that is not documented for every system version.
    static func channel(_ value: Float) -> CGFloat {
        CGFloat(min(max(value, 0), 1))
    }

    /// `nil` stays nil.
    static func string(_ value: AttributeValue?) -> Result<String?, AttributeRejection> {
        guard let value else { return .success(nil) }
        guard case .string(let text) = value else { return .failure(.otherKind) }
        return .success(text)
    }

    /// Every number a value holds, for the check that they are finite (P-SET-03).
    static func numbers(in value: AttributeValue) -> [Double] {
        switch value {
        case .bool, .int, .string, .enumeration:
            return []
        case .double(let number):
            return [number]
        case .color(let color):
            return [color.red, color.green, color.blue, color.alpha].map(Double.init)
        case .point(let point):
            return [point.x, point.y]
        case .size(let size):
            return [size.width, size.height]
        case .rect(let rect):
            return [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height]
        case .insets(let insets):
            return [insets.top, insets.left, insets.bottom, insets.right]
        case .transform(let transform):
            return transform.components
        }
    }
}
#endif
