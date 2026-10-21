import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// The attributes of the image an image view or a button shows (S-ATTR-20). No server, no
/// connection.
final class ImageAttributeTests: AttributeValueTestCase {
    func test_S_ATTR_20_namedImage() throws {
        let window = try makeWindow()
        let image = try XCTUnwrap(UIImage(named: "Swatch"))
        let view = UIImageView(image: image)
        window.addSubview(view)
        XCTAssertEqual(try string("imageView.imageName", of: view), "Swatch")
        XCTAssertEqual(try value("imageView.imageSize", of: view), .size(WireSize(width: 4, height: 3)))
        XCTAssertEqual(try value("imageView.imageScale", of: view), .double(2))
        guard case .enumeration(_, let cases, let name, _)? = try value("imageView.imageRenderingMode", of: view) else {
            return XCTFail("the rendering mode is not an enumeration")
        }
        XCTAssertEqual(cases, ["automatic", "alwaysOriginal", "alwaysTemplate"])
        XCTAssertEqual(name, "automatic")
        XCTAssertNil(try string("imageView.symbolConfiguration", of: view))

        view.image = image.withRenderingMode(.alwaysTemplate)
        XCTAssertNil(try string("imageView.imageName", of: view))
        guard case .enumeration(_, _, let template, _)? = try value("imageView.imageRenderingMode", of: view) else {
            return XCTFail("the rendering mode is not an enumeration")
        }
        XCTAssertEqual(template, "alwaysTemplate")
    }

    func test_S_ATTR_20_symbols() throws {
        let window = try makeWindow()
        let configuration = UIImage.SymbolConfiguration(pointSize: 24, weight: .bold, scale: .large)
        let symbol = try XCTUnwrap(UIImage(systemName: "heart", withConfiguration: configuration))
        let view = UIImageView(image: symbol)
        window.addSubview(view)
        XCTAssertEqual(try string("imageView.imageName", of: view), "heart")
        let text = try XCTUnwrap(try string("imageView.symbolConfiguration", of: view))
        // The system's own words: iOS 15 says `scale=L`, iOS 26 `scale=Large`.
        XCTAssertTrue(text.hasPrefix("pointSize=24, weight=Bold, scale="), text)
        XCTAssertFalse(text.contains("traits"), text)
        XCTAssertFalse(text.contains("(null)"), text)
        XCTAssertEqual(try value("imageView.imageScale", of: view), .double(Double(symbol.scale)))

        view.image = UIImage(systemName: "star.fill")
        XCTAssertEqual(try string("imageView.imageName", of: view), "star.fill")
        XCTAssertNil(try string("imageView.symbolConfiguration", of: view))
    }

    func test_S_ATTR_20_noImageGivesNothing() throws {
        let window = try makeWindow()
        let view = UIImageView()
        let button = UIButton(type: .custom)
        window.addSubview(view)
        window.addSubview(button)
        for (group, view) in [("imageView", view), ("button", button)] as [(String, UIView)] {
            for name in ["imageName", "imageSize", "imageScale", "imageRenderingMode", "symbolConfiguration"] {
                XCTAssertNil(try value("\(group).\(name)", of: view), "\(group).\(name)")
            }
        }
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        view.image = drawn
        XCTAssertNil(try string("imageView.imageName", of: view))
        XCTAssertEqual(try value("imageView.imageSize", of: view), .size(WireSize(width: 4, height: 4)))
    }

    func test_S_ATTR_20_buttonsReadTheCurrentImage() throws {
        let window = try makeWindow()
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "star.fill"), for: .normal)
        button.setImage(UIImage(named: "Swatch"), for: .selected)
        window.addSubview(button)
        XCTAssertEqual(try string("button.imageName", of: button), "star.fill")
        button.isSelected = true
        XCTAssertEqual(try string("button.imageName", of: button), "Swatch")
        XCTAssertEqual(try value("button.imageSize", of: button), .size(WireSize(width: 4, height: 3)))
    }

    func test_S_ATTR_20_namesComeFromTheDescription() {
        XCTAssertEqual(
            AttributeTexts.imageName(inDescription: "<UIImage:0x1 named(main: Swatch) {4, 3} renderingMode=automatic>"),
            "Swatch"
        )
        XCTAssertEqual(
            AttributeTexts.imageName(inDescription: "<UIImage:0x1 symbol(system: star.fill) {22, 20} baseline=3>"),
            "star.fill"
        )
        XCTAssertEqual(
            AttributeTexts.imageName(inDescription: "<UIImage:0x1 named(com.example.kit: Icon Name) {4, 3}>"),
            "Icon Name"
        )
        XCTAssertNil(AttributeTexts.imageName(inDescription: "<UIImage:0x1 anonymous {4, 3}>"))
        XCTAssertNil(AttributeTexts.imageName(inDescription: "something else"))
        XCTAssertEqual(
            AttributeTexts.symbolConfiguration(
                inDescription: "pointSize=24, weight=Bold, scale=L, (null), traits=(DisplayScale = 3, Style = Dark)"
            ),
            "pointSize=24, weight=Bold, scale=L"
        )
        XCTAssertNil(AttributeTexts.symbolConfiguration(inDescription: "traits=(DisplayScale = 3, Style = Dark)"))
        XCTAssertNil(AttributeTexts.symbolConfiguration(inDescription: ""))
    }
}
