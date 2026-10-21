import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// The base class of the tests that read layers directly, on the main thread. They start no
/// server and open no connection.
@MainActor
class CaptureTestCase: XCTestCase {
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        for window in windows {
            window.isHidden = true
            window.windowScene = nil
        }
        windows = []
        try await super.tearDown()
    }

    /// The test host's scene.
    func hostScene() throws -> UIWindowScene {
        try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
            "the test host has no window scene"
        )
    }

    /// A window of the test's own in the host's scene; on screen unless `hidden`. It is not
    /// made key. It leaves the scene when the test ends.
    func makeWindow(level: UIWindow.Level = .normal, hidden: Bool = false) throws -> UIWindow {
        let window = UIWindow(windowScene: try hostScene())
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        window.windowLevel = level
        window.isHidden = hidden
        windows.append(window)
        return window
    }

    /// A window that belongs to no scene and is never shown: for layers with values that
    /// should not reach the render server.
    func makeDetachedWindow() -> UIWindow {
        UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
    }

    /// The node of `layer`, looked up by the ID the registry gave it.
    func node(
        of layer: CALayer,
        in hierarchy: Hierarchy,
        registry: LayerRegistry,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> LayerNode {
        let id = registry.register(layer)
        return try XCTUnwrap(
            hierarchy.nodes.first { $0.id == id },
            "the hierarchy has no node for \(layer)",
            file: file,
            line: line
        )
    }

    /// Renders the window's layer tree into BGRA pixels, one byte per component, at 1x.
    func render(_ window: UIWindow) throws -> [UInt8] {
        let width = Int(window.bounds.width)
        let height = Int(window.bounds.height)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(
                CGContext(
                    data: buffer.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                        | CGBitmapInfo.byteOrder32Little.rawValue
                )
            )
            // Core Graphics counts rows from the bottom; layers count from the top.
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            window.layer.render(in: context)
        }
        return pixels
    }
}

/// The bytes of a colour as one premultiplied sRGB pixel of the wire: B, G, R, A.
func pixelBytes(red: Double, green: Double, blue: Double, alpha: Double = 1) -> [UInt8] {
    [blue, green, red, 1].map { UInt8(($0 * alpha * 255).rounded()) }
}

extension RawImage {
    /// The four bytes of the pixel in column `x` of row `y`, counted from the top left.
    func pixel(x: Int, y: Int) -> [UInt8] {
        let start = y * bytesPerRow + x * 4
        return [UInt8](pixels[start..<start + 4])
    }

    /// The pixel that shows a point of the layer, given relative to the origin of its bounds.
    func pixel(atPoint x: Double, _ y: Double) -> [UInt8] {
        pixel(x: Int(x * Double(scale)), y: Int(y * Double(scale)))
    }
}

/// A sampled pixel may differ from the expected colour by 2 per channel.
func assertPixel(
    _ actual: [UInt8],
    _ expected: [UInt8],
    _ message: String = "",
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let close =
        actual.count == expected.count
            && zip(actual, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
    XCTAssertTrue(close, "pixel \(actual) is not \(expected) (B, G, R, A) \(message)", file: file, line: line)
}

/// A view of one colour.
func colorView(_ frame: CGRect, red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) -> UIView {
    let view = UIView(frame: frame)
    view.backgroundColor = UIColor(red: red, green: green, blue: blue, alpha: alpha)
    return view
}
