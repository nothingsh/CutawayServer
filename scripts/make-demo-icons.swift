// Writes the app icons of the two apps in Demo/. Run from the repository root:
//
//   DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift scripts/make-demo-icons.swift
//
// The PNG files are checked in; run this again only to change the icons.
import CoreGraphics
import Foundation
import ImageIO

let kSide = 1024

/// Draws into an opaque sRGB bitmap whose origin is the top-left corner, and writes a PNG.
func writeIcon(to path: String, draw: (CGContext) -> Void) {
    guard
        let space = CGColorSpace(name: CGColorSpace.sRGB),
        let context = CGContext(
            data: nil,
            width: kSide,
            height: kSide,
            bitsPerComponent: 8,
            bytesPerRow: kSide * 4,
            space: space,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
    else { fatalError("could not create a bitmap context") }
    context.translateBy(x: 0, y: CGFloat(kSide))
    context.scaleBy(x: 1, y: -1)
    draw(context)
    let url = URL(fileURLWithPath: path)
    do {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    } catch {
        fatalError("could not create the directory of \(path): \(error)")
    }
    guard
        let image = context.makeImage(),
        let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)
    else { fatalError("could not create \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(path)") }
    print("wrote \(path)")
}

func fill(_ context: CGContext, _ rect: CGRect, red: CGFloat, green: CGFloat, blue: CGFloat) {
    context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
    context.fill(rect)
}

let kHalf = CGFloat(kSide / 2)

// TestHost: four opaque quadrants with known colours, for pixel sampling (S-CONN-08).
writeIcon(to: "Demo/TestHost/Assets.xcassets/AppIcon.appiconset/icon.png") { context in
    fill(context, CGRect(x: 0, y: 0, width: kHalf, height: kHalf), red: 1, green: 0, blue: 0)
    fill(context, CGRect(x: kHalf, y: 0, width: kHalf, height: kHalf), red: 0, green: 1, blue: 0)
    fill(context, CGRect(x: 0, y: kHalf, width: kHalf, height: kHalf), red: 0, green: 0, blue: 1)
    fill(context, CGRect(x: kHalf, y: kHalf, width: kHalf, height: kHalf), red: 1, green: 1, blue: 1)
}

// CutawayDemo: three stacked layers pulled apart, easy to recognise in a list.
writeIcon(to: "Demo/CutawayDemo/Assets.xcassets/AppIcon.appiconset/icon.png") { context in
    let full = CGFloat(kSide)
    fill(context, CGRect(x: 0, y: 0, width: full, height: full), red: 0.11, green: 0.13, blue: 0.22)
    fill(context, CGRect(x: 160, y: 160, width: 520, height: 520), red: 0.25, green: 0.47, blue: 0.96)
    fill(context, CGRect(x: 252, y: 252, width: 520, height: 520), red: 0.38, green: 0.80, blue: 0.75)
    fill(context, CGRect(x: 344, y: 344, width: 520, height: 520), red: 0.98, green: 0.73, blue: 0.25)
}
