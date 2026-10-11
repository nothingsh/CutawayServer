#if !canImport(UIKit) || DEBUG || ReleaseEnabled
import Foundation

public struct WireSize: Sendable, Equatable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct WirePoint: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct WireRect: Sendable, Equatable {
    public var origin: WirePoint
    public var size: WireSize

    public init(origin: WirePoint, size: WireSize) {
        self.origin = origin
        self.size = size
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.init(origin: WirePoint(x: x, y: y), size: WireSize(width: width, height: height))
    }
}

/// A 4x4 matrix with the layout of `CATransform3D`. Points are row vectors:
/// (x, y) becomes (x·m11 + y·m21 + m41, x·m12 + y·m22 + m42).
public struct WireTransform: Sendable, Equatable {
    public var m11: Double, m12: Double, m13: Double, m14: Double
    public var m21: Double, m22: Double, m23: Double, m24: Double
    public var m31: Double, m32: Double, m33: Double, m34: Double
    public var m41: Double, m42: Double, m43: Double, m44: Double

    public init(
        m11: Double,
        m12: Double,
        m13: Double,
        m14: Double,
        m21: Double,
        m22: Double,
        m23: Double,
        m24: Double,
        m31: Double,
        m32: Double,
        m33: Double,
        m34: Double,
        m41: Double,
        m42: Double,
        m43: Double,
        m44: Double
    ) {
        self.m11 = m11; self.m12 = m12; self.m13 = m13; self.m14 = m14
        self.m21 = m21; self.m22 = m22; self.m23 = m23; self.m24 = m24
        self.m31 = m31; self.m32 = m32; self.m33 = m33; self.m34 = m34
        self.m41 = m41; self.m42 = m42; self.m43 = m43; self.m44 = m44
    }

    public static let identity = Self(
        m11: 1,
        m12: 0,
        m13: 0,
        m14: 0,
        m21: 0,
        m22: 1,
        m23: 0,
        m24: 0,
        m31: 0,
        m32: 0,
        m33: 1,
        m34: 0,
        m41: 0,
        m42: 0,
        m43: 0,
        m44: 1
    )

    /// The 16 components, row by row: m11, m12, ..., m44.
    public var components: [Double] {
        [m11, m12, m13, m14, m21, m22, m23, m24, m31, m32, m33, m34, m41, m42, m43, m44]
    }
}
#endif
