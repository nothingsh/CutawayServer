import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// The accessibility attributes (S-ATTR-16). No server, no connection.
final class AccessibilityAttributeTests: AttributeValueTestCase {
    func test_S_ATTR_16_accessibilityIsRead() throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        window.addSubview(view)
        XCTAssertNil(try string("view.accessibilityLabel", of: view))
        XCTAssertNil(try string("view.accessibilityHint", of: view))
        XCTAssertNil(try string("view.accessibilityValue", of: view))
        XCTAssertNil(try string("view.accessibilityIdentifier", of: view))
        XCTAssertEqual(try bool("view.isAccessibilityElement", of: view), false)
        XCTAssertEqual(try string("view.accessibilityTraits", of: view), "None")

        view.accessibilityLabel = "Save"
        view.accessibilityHint = "Saves the page"
        view.accessibilityValue = "3"
        view.accessibilityIdentifier = "save"
        view.isAccessibilityElement = true
        view.accessibilityTraits = [.button, .selected]
        XCTAssertEqual(try string("view.accessibilityLabel", of: view), "Save")
        XCTAssertEqual(try string("view.accessibilityHint", of: view), "Saves the page")
        XCTAssertEqual(try string("view.accessibilityValue", of: view), "3")
        XCTAssertEqual(try string("view.accessibilityIdentifier", of: view), "save")
        XCTAssertEqual(try bool("view.isAccessibilityElement", of: view), true)
        XCTAssertEqual(try string("view.accessibilityTraits", of: view), "Button, Selected")
        // Every trait by its name; bits without one as a hexadecimal number.
        XCTAssertEqual(AttributeTexts.traits(.none), "None")
        XCTAssertEqual(AttributeTexts.traits([.header, .staticText]), "Static Text, Header")
        XCTAssertEqual(
            AttributeTexts.traits(UIAccessibilityTraits(rawValue: UIAccessibilityTraits.link.rawValue | 1 << 50)),
            "Link, 0x4000000000000"
        )
    }

    func test_S_ATTR_16_accessibilityIsInItsSection() throws {
        let window = try makeWindow()
        let view = UIView()
        window.addSubview(view)
        let group = try XCTUnwrap(
            AttributeCatalog.standard.read(view.layer, reading: reading([window])).first { $0.id == "view" }
        )
        let ids = group.attributes.filter { $0.section == .accessibility }.map(\.id)
        XCTAssertEqual(ids, [
            "view.accessibilityLabel",
            "view.accessibilityHint",
            "view.accessibilityValue",
            "view.accessibilityIdentifier",
            "view.isAccessibilityElement",
            "view.accessibilityTraits"
        ])
    }
}
