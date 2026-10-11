import CoreGraphics
import XCTest

@testable import CutawayServer

/// How many pixels the image of a layer gets. Pure arithmetic.
final class ImageSizingTests: XCTestCase {
    private func plan(
        _ width: CGFloat,
        _ height: CGFloat,
        scale: CGFloat = 3,
        max: UInt32 = 0
    ) -> ImagePlan? {
        ImageSizing.plan(
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            screenScale: scale,
            maxTextureDimension: max
        )
    }

    func test_S_SHOT_03_fitsTheMaxTextureDimension() {
        // Within the limit: the layer's points times the screen's scale, rounded up.
        XCTAssertEqual(plan(393, 852), ImagePlan(pixelWidth: 1179, pixelHeight: 2556, scale: 3))
        XCTAssertEqual(plan(393, 852, max: 16384), ImagePlan(pixelWidth: 1179, pixelHeight: 2556, scale: 3))
        XCTAssertEqual(plan(100.2, 0.25), ImagePlan(pixelWidth: 301, pixelHeight: 1, scale: 3))
        XCTAssertEqual(plan(10, 20, scale: 1), ImagePlan(pixelWidth: 10, pixelHeight: 20, scale: 1))
        // Exactly at the limit is within it.
        XCTAssertEqual(plan(1024, 512, scale: 2, max: 2048), ImagePlan(pixelWidth: 2048, pixelHeight: 1024, scale: 2))

        // Above it: both sides shrink by the same factor, and the scale with them (P-DET-05).
        XCTAssertEqual(
            plan(2000, 1000, scale: 2, max: 1024),
            ImagePlan(pixelWidth: 1024, pixelHeight: 512, scale: 0.512)
        )
        XCTAssertEqual(
            plan(1000, 2000, scale: 2, max: 1024),
            ImagePlan(pixelWidth: 512, pixelHeight: 1024, scale: 0.512)
        )
        // Sides that do not divide evenly are rounded down, never above the limit.
        let odd = plan(1000, 333, scale: 3, max: 1000)
        XCTAssertEqual(odd?.pixelWidth, 1000)
        XCTAssertEqual(odd?.pixelHeight, 333)
        XCTAssertEqual(odd?.scale, 1)
        for limit in [UInt32(1), 2, 7, 100, 2000] {
            let reduced = plan(393, 852, max: limit)
            XCTAssertEqual(reduced?.pixelHeight, Int(limit), "limit \(limit)")
            XCTAssertLessThanOrEqual(reduced?.pixelWidth ?? .max, Int(limit), "limit \(limit)")
            XCTAssertGreaterThanOrEqual(reduced?.pixelWidth ?? 0, 1, "limit \(limit)")
            XCTAssertEqual(Double(reduced?.scale ?? 0), 3 * Double(limit) / 2556, accuracy: 1e-6)
        }
        // 0 means no limit.
        XCTAssertEqual(plan(3000, 10, scale: 3, max: 0), ImagePlan(pixelWidth: 9000, pixelHeight: 30, scale: 3))
    }

    func test_S_SHOT_03_theSideThatDecidesLandsOnTheLimit() throws {
        // The factor is the limit divided by the long side; multiplied back, the product can
        // come out a hair under the limit. The long side must still get every pixel it may
        // have, and both sides must stay within a pixel of the bounds at the reported scale:
        // a client lays the image over the bounds (P-DET-07).
        for limit in [UInt32(16384), 4096, 1000] {
            for length in stride(from: 5500.0, through: 20000.0, by: 1) {
                // 100 points across: the side limit decides, and the long side is exactly at it.
                // 393 across: for the largest limit the 64 MiB can decide instead.
                for (width, height) in [
                    (CGFloat(100), CGFloat(length)),
                    (CGFloat(length), CGFloat(100)),
                    (CGFloat(393), CGFloat(length))
                ] {
                    let name = "\(width) x \(height), limit \(limit)"
                    let reduced = try XCTUnwrap(plan(width, height, max: limit), name)
                    let longSide = max(reduced.pixelWidth, reduced.pixelHeight)
                    guard longSide <= Int(limit), width == 393 || longSide == Int(limit),
                          reduced.pixelWidth * reduced.pixelHeight * 4 <= ImageSizing.maximumImageBytes
                    else {
                        return XCTFail("\(name): the long side has \(longSide) pixels")
                    }
                    let scale = Double(reduced.scale)
                    // A Float scale is exact to about one part in ten million.
                    let tolerance = 1 + Double(limit) * 1e-6
                    guard abs(Double(reduced.pixelWidth) - Double(width) * scale) <= tolerance,
                          abs(Double(reduced.pixelHeight) - Double(height) * scale) <= tolerance
                    else {
                        return XCTFail("\(name): \(reduced) is more than a pixel away from the bounds at its scale")
                    }
                }
            }
        }
    }

    func test_S_SHOT_03_fitsSixtyFourMebibytes() throws {
        // 4096 x 4096 pixels are exactly 64 MiB: allowed.
        XCTAssertEqual(plan(4096, 4096, scale: 1), ImagePlan(pixelWidth: 4096, pixelHeight: 4096, scale: 1))

        // One more column is too much, whatever the texture limit says (P-DET-08).
        for limit in [UInt32(0), 16384] {
            let reduced = try XCTUnwrap(plan(4097, 4096, scale: 1, max: limit))
            XCTAssertLessThanOrEqual(reduced.pixelWidth * reduced.pixelHeight * 4, ImageSizing.maximumImageBytes)
            XCTAssertLessThan(reduced.scale, 1)
            XCTAssertGreaterThan(reduced.scale, 0.999)
        }

        // A long scrolling page: 393 x 20000 points at 3x would be 283 MiB.
        let page = try XCTUnwrap(plan(393, 20000))
        XCTAssertLessThanOrEqual(page.pixelWidth * page.pixelHeight * 4, ImageSizing.maximumImageBytes)
        // Proportional: both sides shrank by the factor the scale shrank by.
        let factor = Double(page.scale) / 3
        XCTAssertEqual(Double(page.pixelWidth), 1179 * factor, accuracy: 1)
        XCTAssertEqual(Double(page.pixelHeight), 60000 * factor, accuracy: 1)
        // Not smaller than necessary: one more pixel on each side would not fit.
        XCTAssertGreaterThan((page.pixelWidth + 1) * (page.pixelHeight + 1) * 4, ImageSizing.maximumImageBytes)

        // Both limits at once: the stricter one decides.
        let both = try XCTUnwrap(plan(393, 20000, max: 2048))
        XCTAssertEqual(both.pixelHeight, 2048)
        XCTAssertEqual(both.pixelWidth, 40)
        let bytesDecide = try XCTUnwrap(plan(5000, 5000, scale: 1, max: 4500))
        XCTAssertEqual(bytesDecide.pixelWidth, 4096)
        XCTAssertEqual(bytesDecide.pixelHeight, 4096)
    }

    func test_S_SHOT_03_extremeAspectRatiosStayWithinTheLimits() throws {
        let sizes: [(CGFloat, CGFloat)] = [
            (0.001, 1_000_000_000),
            (1_000_000_000, 0.001),
            (1e12, 1),
            (1, 1e12),
            (1e9, 1e9),
            (1e15, 1e15),
            (0.0001, 0.0001),
            (1e-30, 1e30)
        ]
        for (width, height) in sizes {
            for limit in [UInt32(0), 1, 4096, 16384] {
                let name = "\(width) x \(height), limit \(limit)"
                let reduced = try XCTUnwrap(plan(width, height, max: limit), name)
                XCTAssertGreaterThanOrEqual(reduced.pixelWidth, 1, name)
                XCTAssertGreaterThanOrEqual(reduced.pixelHeight, 1, name)
                XCTAssertLessThanOrEqual(
                    reduced.pixelWidth * reduced.pixelHeight * 4,
                    ImageSizing.maximumImageBytes,
                    name
                )
                if limit != 0 {
                    XCTAssertLessThanOrEqual(max(reduced.pixelWidth, reduced.pixelHeight), Int(limit), name)
                }
                XCTAssertTrue(reduced.scale.isFinite && reduced.scale > 0, name)
            }
        }
    }

    func test_S_SHOT_04_impossibleSizesHaveNoPlan() {
        let impossible: [(CGFloat, CGFloat)] = [
            (0, 10),
            (10, 0),
            (0, 0),
            (-10, 10),
            (10, -10),
            (-10, -10),
            (.nan, 10),
            (10, .nan),
            (.infinity, 10),
            (10, .infinity),
            (-.infinity, 10)
        ]
        for (width, height) in impossible {
            XCTAssertNil(plan(width, height), "\(width) x \(height)")
            XCTAssertNil(plan(width, height, max: 4096), "\(width) x \(height)")
        }
        // An origin that is not finite cannot be drawn from either.
        for origin in [CGPoint(x: CGFloat.nan, y: 0), CGPoint(x: 0, y: CGFloat.infinity)] {
            XCTAssertNil(
                ImageSizing.plan(
                    bounds: CGRect(origin: origin, size: CGSize(width: 10, height: 10)),
                    screenScale: 2,
                    maxTextureDimension: 0
                )
            )
        }
        // Nor with a scale that makes no sense, or with sizes so large that the area is beyond
        // every number or the reduced scale is too small for a Float.
        XCTAssertNil(plan(10, 10, scale: 0))
        XCTAssertNil(plan(10, 10, scale: -1))
        XCTAssertNil(plan(10, 10, scale: .nan))
        XCTAssertNil(plan(1e200, 1e200))
        XCTAssertNil(plan(1e100, 1e100))
        // A scrolled layer is fine: the origin is only where the image starts.
        XCTAssertEqual(
            ImageSizing.plan(
                bounds: CGRect(x: 0, y: 100, width: 300, height: 200),
                screenScale: 2,
                maxTextureDimension: 0
            ),
            ImagePlan(pixelWidth: 600, pixelHeight: 400, scale: 2)
        )
    }
}
