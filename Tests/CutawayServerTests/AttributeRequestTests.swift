import CutawayWire
import Foundation
import UIKit
import XCTest

@testable import CutawayServer

/// A window of the test's own and its label. Touched on the main thread only.
@MainActor
private final class LabelBox {
    var window: UIWindow?
    var label: UILabel?

    nonisolated init() {}
}

/// `SetAttribute` over a connection. The checks and the change are tested
/// without one (AttributeEditingTests, SessionRequestTests); this covers the whole path.
final class AttributeRequestTests: ServerTestCase {
    func test_S_SET_01_S_SET_02_setAttributeOverTheConnection() async throws {
        let box = LabelBox()
        try await MainActor.run {
            let scene = try XCTUnwrap(
                UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            )
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
            let label = UILabel(frame: CGRect(x: 20, y: 40, width: 219, height: 27))
            label.text = "Before"
            window.addSubview(label)
            window.isHidden = false
            box.window = window
            box.label = label
        }
        addTeardownBlock {
            await MainActor.run {
                box.window?.isHidden = true
                box.window?.windowScene = nil
            }
        }

        let server = makeServer()
        let port = try await server.start()
        let (client, _) = try await connectAndHandshake(port: port)
        try await client.send(Frame(requestID: 1, body: .getHierarchy))
        guard case .hierarchy(let hierarchy)? = try await client.nextFrame()?.body else {
            return XCTFail("expected Hierarchy")
        }
        // The test's label, told apart by its unusual size.
        let node = try XCTUnwrap(
            hierarchy.nodes.first {
                $0.viewClassName == "UILabel" && $0.bounds.size == WireSize(width: 219, height: 27)
            }
        )

        // P-SET-01: the change is made and the layer's attributes come back.
        try await client.send(
            Frame(
                requestID: 2,
                body: .setAttribute(SetAttribute(
                    layerID: node.id,
                    attributeID: "label.text",
                    value: .string("After")
                ))
            )
        )
        let answer = try await client.nextFrame()
        let (text, expected) = await MainActor.run {
            (box.label?.text, AttributeCatalog.standard.read(box.label!.layer))
        }
        XCTAssertEqual(text, "After")
        XCTAssertEqual(
            answer,
            Frame(
                requestID: 2,
                body: .setAttributeResult(SetAttributeResult(layerID: node.id, attributeGroups: expected))
            )
        )

        // P-SET-03: the first three requests of the `set-attribute-rejected` fixture, byte for byte.
        // They do not depend on what layer 3 is; this connection has given out that ID.
        XCTAssertGreaterThanOrEqual(hierarchy.nodes.count, 3)
        for (request, error) in [
            ("01-c2s-set-missing-layer", "02-s2c-error"),
            ("03-c2s-set-read-only", "04-s2c-error"),
            ("05-c2s-set-wrong-kind", "06-s2c-error")
        ] {
            try await client.send(FrameCodec.framed(try Fixtures.data("set-attribute-rejected/\(request).bin")))
            let reply = try await client.nextFrame()
            XCTAssertEqual(reply, try Fixtures.frame("set-attribute-rejected/\(error).bin"), request)
        }
        // The connection is good for more.
        try await client.send(Frame(requestID: 9, body: .getAppIcon))
        let icon = try await client.nextFrame()
        XCTAssertEqual(icon?.requestID, 9)
    }
}
