import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// The light and dark appearances of colour values (S-ATTR-17). No server, no connection.
final class LightAndDarkColorTests: AttributeValueTestCase {
    private func lightAndDark(
        _ id: String,
        of view: UIView,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> (value: WireColor, light: WireColor?, dark: WireColor?) {
        guard case let .color(color, _, light, dark, _)? = try value(id, of: view, file: file, line: line) else {
            throw XCTSkip("\(id) is not a colour")
        }
        return (color, light, dark)
    }

    private func assertColor(
        _ color: WireColor?,
        _ components: [Float],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let color else { return XCTFail("no colour", file: file, line: line) }
        for (actual, expected) in zip([color.red, color.green, color.blue, color.alpha], components) {
            XCTAssertEqual(actual, expected, accuracy: 1 / 255, "\(color)", file: file, line: line)
        }
    }

    func test_S_ATTR_17_dynamicColorsGiveLightAndDark() throws {
        let window = try makeWindow()
        window.overrideUserInterfaceStyle = .light
        let view = UIView()
        window.addSubview(view)
        let tint = try lightAndDark("view.tintColor", of: view)
        if #available(iOS 26, *) {
            // iOS 26 changed systemBlue to #0088FF and #0091FF.
            assertColor(tint.light, [0, 0x88 / 255, 1, 1])
            assertColor(tint.dark, [0, 0x91 / 255, 1, 1])
        } else {
            // The values of the `layer-details` fixture: #007AFF and #0A84FF.
            assertColor(tint.light, [0, 0.47843137, 1, 1])
            assertColor(tint.dark, [0.039215688, 0.5176471, 1, 1])
        }
        XCTAssertEqual(tint.light, tint.value)

        // Each of the colours read from a view, with a dynamic colour.
        let label = UILabel()
        let button = UIButton(type: .system)
        let field = UITextField()
        let text = UITextView()
        for view in [label, button, field, text] as [UIView] { window.addSubview(view) }
        view.backgroundColor = .systemBackground
        label.textColor = .label
        button.setTitleColor(.label, for: .normal)
        field.textColor = .label
        text.textColor = .label
        for (id, view) in [
            ("view.backgroundColor", view),
            ("label.textColor", label),
            ("button.currentTitleColor", button),
            ("textField.textColor", field),
            ("textView.textColor", text)
        ] as [(String, UIView)] {
            let color = try lightAndDark(id, of: view)
            XCTAssertNotNil(color.light, id)
            XCTAssertNotNil(color.dark, id)
            XCTAssertNotEqual(color.light, color.dark, id)
        }
    }

    func test_S_ATTR_17_fixedColorsAndCGColorsGiveNeither() throws {
        let window = try makeWindow()
        let view = UIView()
        view.backgroundColor = UIColor(red: 0, green: 0x7A / 255, blue: 1, alpha: 1)
        window.addSubview(view)
        let background = try lightAndDark("view.backgroundColor", of: view)
        XCTAssertNil(background.light)
        XCTAssertNil(background.dark)

        let bare = CALayer()
        bare.borderColor = UIColor.systemBlue.cgColor
        window.layer.addSublayer(bare)
        let group = try XCTUnwrap(
            AttributeCatalog.standard.read(bare, reading: reading([window])).first { $0.id == "layer" }
        )
        guard case let .color(_, _, light, dark, _)? = group.attributes.first(where: { $0.id == "layer.borderColor" })?
            .value else {
            return XCTFail("layer.borderColor is not a colour")
        }
        XCTAssertNil(light)
        XCTAssertNil(dark)
    }

    /// A colour that resolves to the same 8-bit components in both gives neither.
    func test_S_ATTR_17_colorsTheSameIn8BitsGiveNeither() throws {
        let window = try makeWindow()
        let view = UIView()
        view.backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
                : UIColor(red: 0.5 + 0.0005, green: 0.5, blue: 0.5, alpha: 1)
        }
        window.addSubview(view)
        let background = try lightAndDark("view.backgroundColor", of: view)
        XCTAssertNil(background.light)
        XCTAssertNil(background.dark)
    }

    func test_S_ATTR_17_overriddenToDarkTheValueIsTheDark() throws {
        let window = try makeWindow()
        let view = UIView()
        window.addSubview(view)
        let overrides = EnvironmentOverrides()
        overrides.replace(with: Traits(userInterfaceStyle: .dark), windows: [window])
        defer { overrides.removeAll() }
        let tint = try lightAndDark("view.tintColor", of: view)
        XCTAssertEqual(tint.value, tint.dark)
        XCTAssertNotEqual(tint.value, tint.light)
    }
}
