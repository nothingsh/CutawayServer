#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import CutawayWire
import UIKit

// Geometry in both directions: Core Graphics and Core Animation values to wire values, and
// wire values back to what UIKit and Core Animation take.

/// Converts Core Graphics and Core Animation values into wire values.
/// PROTOCOL.md, P-HIER-05: a number that is not finite is sent as 0. This is the only place
/// that does it.
enum WireGeometry {
    static func finite(_ value: CGFloat) -> Double {
        value.isFinite ? Double(value) : 0
    }

    static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }

    static func point(_ point: CGPoint) -> WirePoint {
        WirePoint(x: finite(point.x), y: finite(point.y))
    }

    /// The rectangle's stored values, not standardized: a negative size stays negative.
    static func rect(_ rect: CGRect) -> WireRect {
        WireRect(
            x: finite(rect.origin.x),
            y: finite(rect.origin.y),
            width: finite(rect.size.width),
            height: finite(rect.size.height)
        )
    }

    static func transform(_ transform: CATransform3D) -> WireTransform {
        WireTransform(
            m11: finite(transform.m11),
            m12: finite(transform.m12),
            m13: finite(transform.m13),
            m14: finite(transform.m14),
            m21: finite(transform.m21),
            m22: finite(transform.m22),
            m23: finite(transform.m23),
            m24: finite(transform.m24),
            m31: finite(transform.m31),
            m32: finite(transform.m32),
            m33: finite(transform.m33),
            m34: finite(transform.m34),
            m41: finite(transform.m41),
            m42: finite(transform.m42),
            m43: finite(transform.m43),
            m44: finite(transform.m44)
        )
    }
}

// Geometry from the wire as UIKit and Core Animation take it. The numbers were checked to be
// finite before a writer sees them (P-SET-03).

extension CGPoint {
    init(_ point: WirePoint) {
        self.init(x: point.x, y: point.y)
    }
}

extension CGSize {
    init(_ size: WireSize) {
        self.init(width: size.width, height: size.height)
    }
}

extension CGRect {
    init(_ rect: WireRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, width: rect.size.width, height: rect.size.height)
    }
}

extension UIEdgeInsets {
    init(_ insets: WireInsets) {
        self.init(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
    }
}

extension CATransform3D {
    init(_ transform: WireTransform) {
        self.init(
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
}
#endif
