import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// The app icon.
final class AppIconTests: ServerTestCase {
    /// Sends `GetAppIcon` and returns the image of the response.
    private func requestIcon(_ client: TestClient, requestID: UInt32) async throws -> WireImage? {
        try await client.send(Frame(requestID: requestID, body: .getAppIcon))
        let answer = try await client.nextFrame()
        XCTAssertEqual(answer?.requestID, requestID)
        guard case .appIcon(let icon)? = answer?.body else {
            throw TestClientError(description: "expected AppIcon, got \(String(describing: answer))")
        }
        return icon.image
    }

    func test_S_CONN_08_returnsTheMainIcon() async throws {
        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        let icon = try await requestIcon(client, requestID: 7)
        let image = try XCTUnwrap(icon, "TestHost has an icon")
        XCTAssertEqual(image.encoding, .bgra8PremultipliedLZFSE)
        XCTAssertGreaterThan(image.pixelWidth, 0)
        XCTAssertEqual(image.pixelWidth, image.pixelHeight, "an app icon is square")
        XCTAssertGreaterThanOrEqual(image.bytesPerRow, image.pixelWidth * 4)
        XCTAssertGreaterThan(image.scale, 0)

        let pixels = try (image.data as NSData).decompressed(using: .lzfse) as Data
        XCTAssertEqual(pixels.count, Int(image.bytesPerRow) * Int(image.pixelHeight))

        // TestHost's icon is four plain quadrants. Rows run top to bottom; a pixel is B, G, R, A.
        let width = Int(image.pixelWidth)
        let height = Int(image.pixelHeight)
        func assertPixel(
            _ x: Int,
            _ y: Int,
            bgra expected: [UInt8],
            _ name: String,
            line: UInt = #line
        ) {
            let offset = y * Int(image.bytesPerRow) + x * 4
            let actual = Array(pixels[offset..<(offset + 4)])
            for channel in 0..<4 {
                XCTAssertLessThanOrEqual(
                    abs(Int(actual[channel]) - Int(expected[channel])),
                    2,
                    "\(name): got \(actual), expected \(expected)",
                    line: line
                )
            }
        }
        assertPixel(width / 4, height / 4, bgra: [0, 0, 255, 255], "top left is red")
        assertPixel(3 * width / 4, height / 4, bgra: [0, 255, 0, 255], "top right is green")
        assertPixel(width / 4, 3 * height / 4, bgra: [255, 0, 0, 255], "bottom left is blue")
        assertPixel(3 * width / 4, 3 * height / 4, bgra: [255, 255, 255, 255], "bottom right is white")
    }

    func test_S_CONN_08_imageIsAbsentWithoutAnIcon() async throws {
        let server = makeServer { configuration in
            var info = Bundle.main.infoDictionary ?? [:]
            info["CFBundleIcons"] = nil
            info["CFBundleIcons~ipad"] = nil
            configuration.hostApp = LiveHostApp(infoDictionary: info)
        }
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)
        let image = try await requestIcon(client, requestID: 1)
        XCTAssertNil(image)

        // An icon entry that names a file the bundle does not have is no icon either.
        let broken = makeServer { configuration in
            configuration.hostApp = LiveHostApp(
                infoDictionary: [
                    "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["NoSuchIcon"]]]
                ]
            )
        }
        let brokenPort = try await broken.start()
        let (brokenClient, _) = try await connectAndHandshake(port: brokenPort)
        let brokenImage = try await requestIcon(brokenClient, requestID: 1)
        XCTAssertNil(brokenImage)
    }

    func test_S_CONN_08_findsTheIconNamesInTheInfoDictionary() {
        let info: [String: Any] = [
            "CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["Small", "Large"]]],
            "CFBundleIcons~ipad": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["Pad"]]]
        ]
        XCTAssertEqual(LiveHostApp.iconNames(infoDictionary: info, isPad: false), ["Large", "Small"])
        XCTAssertEqual(LiveHostApp.iconNames(infoDictionary: info, isPad: true), ["Pad"])
        XCTAssertEqual(
            LiveHostApp.iconNames(
                infoDictionary: ["CFBundleIcons": info["CFBundleIcons"]!],
                isPad: true
            ),
            ["Large", "Small"],
            "an iPad falls back to the common entry"
        )
        XCTAssertEqual(LiveHostApp.iconNames(infoDictionary: [:], isPad: false), [])
        XCTAssertEqual(
            LiveHostApp.iconNames(infoDictionary: ["CFBundleIcons": "nonsense"], isPad: false),
            []
        )
    }

    func test_S_CONN_08_answersWhileNotActive() async throws {
        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)

        server.center.post(name: UIApplication.willResignActiveNotification, object: nil)
        server.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        let inactive = try await client.nextFrame()
        XCTAssertEqual(inactive, Frame(requestID: 0, body: .appStateChanged(.inactive)))
        let background = try await client.nextFrame()
        XCTAssertEqual(background, Frame(requestID: 0, body: .appStateChanged(.background)))

        let image = try await requestIcon(client, requestID: 3)
        XCTAssertNotNil(image)
    }
}
