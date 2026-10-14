#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

/// Converts UIKit and Core Animation values into attribute values.
///
/// Numbers that are not finite are sent as 0, as in the hierarchy (PROTOCOL.md, P-HIER-05).
/// A value that no member of the agreed `AttributeValue` union can express is sent as a
/// `StringValue` describing it (P-ATTR-03).
enum AttributeOutputs {
    static func double(_ value: CGFloat) -> AttributeValue {
        .double(WireGeometry.finite(value))
    }

    static func double(_ value: Float) -> AttributeValue {
        .double(Double(WireGeometry.finite(value)))
    }

    /// One dimension of an intrinsic content size; `nil` when the view has none in it.
    @MainActor static func intrinsicDimension(_ value: CGFloat) -> AttributeValue? {
        value == UIView.noIntrinsicMetric ? nil : double(value)
    }

    static func point(_ point: CGPoint) -> AttributeValue {
        .point(WireGeometry.point(point))
    }

    static func size(_ size: CGSize) -> AttributeValue {
        .size(WireSize(width: WireGeometry.finite(size.width), height: WireGeometry.finite(size.height)))
    }

    static func rect(_ rect: CGRect) -> AttributeValue {
        .rect(WireGeometry.rect(rect))
    }

    static func transform(_ transform: CATransform3D) -> AttributeValue {
        .transform(WireGeometry.transform(transform))
    }

    static func insets(_ insets: UIEdgeInsets) -> AttributeValue {
        .insets(
            WireInsets(
                top: WireGeometry.finite(insets.top),
                left: WireGeometry.finite(insets.left),
                bottom: WireGeometry.finite(insets.bottom),
                right: WireGeometry.finite(insets.right)
            )
        )
    }

    /// In sRGB, each channel within 0...1 (P-ATTR-04). `nil` stays `nil`.
    static func color(_ color: CGColor?) -> AttributeValue? {
        guard let color else { return nil }
        if color.colorSpace?.model == .pattern { return .string("pattern") }
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count == 4 else {
            let name = color.colorSpace?.name.map { $0 as String }
            return .string(name.map { "color in \($0)" } ?? "color in an unknown color space")
        }
        let channels = components.map(channel)
        return .color(WireColor(red: channels[0], green: channels[1], blue: channels[2], alpha: channels[3]))
    }

    /// One colour channel as it is sent: NaN and infinities become 0 (P-ATTR-05), the rest is
    /// clamped to 0...1 (P-ATTR-04). Core Graphics already clips when it converts a colour, but
    /// that is not documented for every system version.
    static func channel(_ value: CGFloat) -> Float {
        Float(min(max(WireGeometry.finite(value), 0), 1))
    }

    /// A dynamic colour is taken as it looks in `view`: in its light or dark appearance. A
    /// system colour is named (P-ATTR-15), before resolving, which makes it a colour of its own.
    @MainActor
    static func color(_ color: UIColor?, in view: UIView) -> AttributeValue? {
        guard let color else { return nil }
        let value = self.color(color.resolvedColor(with: view.traitCollection).cgColor)
        guard case .color(let resolved, _)? = value else { return value }
        return .color(resolved, systemName: SystemColors.name(of: color))
    }

    /// `names` are the enumeration's cases in declaration order; a case's index is its raw
    /// value (P-ATTR-07). A raw value without a name is sent as its decimal text.
    static func enumeration(_ rawValue: Int, names: [String]) -> AttributeValue {
        guard names.indices.contains(rawValue) else { return .string(String(rawValue)) }
        return .enumeration(
            value: Int64(rawValue),
            cases: names,
            caseName: names[rawValue],
            caseValues: names.indices.map(Int64.init)
        )
    }

    // MARK: - The names of the cases

    static let contentModeNames = [
        "scaleToFill",
        "scaleAspectFit",
        "scaleAspectFill",
        "redraw",
        "center",
        "top",
        "bottom",
        "left",
        "right",
        "topLeft",
        "topRight",
        "bottomLeft",
        "bottomRight"
    ]
    static let textAlignmentNames = ["left", "center", "right", "justified", "natural"]
    static let lineBreakModeNames = [
        "byWordWrapping",
        "byCharWrapping",
        "byClipping",
        "byTruncatingHead",
        "byTruncatingTail",
        "byTruncatingMiddle"
    ]
    static let axisNames = ["horizontal", "vertical"]
    static let distributionNames = [
        "fill",
        "fillEqually",
        "fillProportionally",
        "equalSpacing",
        "equalCentering"
    ]

    /// `top` and `leading` share a raw value, as do `bottom` and `trailing`. Alignment works
    /// across the axis, so a horizontal stack aligns to the top and a vertical one to the
    /// leading edge.
    static func stackAlignmentNames(axis: NSLayoutConstraint.Axis) -> [String] {
        axis == .horizontal
            ? ["fill", "top", "firstBaseline", "center", "bottom", "lastBaseline"]
            : ["fill", "leading", "firstBaseline", "center", "trailing", "lastBaseline"]
    }
}
#endif
