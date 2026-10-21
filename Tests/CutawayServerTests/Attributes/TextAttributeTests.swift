import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Fonts, text styles and the lines a label draws (S-ATTR-21, S-ATTR-22). No server, no
/// connection.
final class TextAttributeTests: AttributeValueTestCase {
    // MARK: - S-ATTR-21

    func test_S_ATTR_21_fontsOfLabelsFieldsAndTextViews() throws {
        let window = try makeWindow()
        let label = UILabel()
        let field = UITextField()
        let text = UITextView()
        for view in [label, field, text] as [UIView] { window.addSubview(view) }
        let body = UIFont.preferredFont(forTextStyle: .body)
        label.font = body
        field.font = body
        text.font = body
        label.adjustsFontForContentSizeCategory = true
        field.adjustsFontForContentSizeCategory = true
        text.adjustsFontForContentSizeCategory = true
        for (group, view) in [("label", label), ("textField", field), ("textView", text)] as [(String, UIView)] {
            XCTAssertEqual(try string("\(group).fontTextStyle", of: view), "body", group)
            XCTAssertEqual(try bool("\(group).adjustsFontForContentSizeCategory", of: view), true, group)
            let description = try XCTUnwrap(try string("\(group).fontDescription", of: view), group)
            XCTAssertFalse(description.contains("0x"), description)
            XCTAssertTrue(description.hasSuffix("\(AttributeTexts.number(body.pointSize)) pt"), description)
        }
        label.font = .systemFont(ofSize: 17, weight: .semibold)
        label.adjustsFontForContentSizeCategory = false
        XCTAssertNil(try string("label.fontTextStyle", of: label))
        XCTAssertEqual(try bool("label.adjustsFontForContentSizeCategory", of: label), false)
        XCTAssertEqual(try string("label.fontDescription", of: label), "System, Semibold, 17 pt")
    }

    func test_S_ATTR_21_fontDescriptionsAndTextStyles() throws {
        XCTAssertEqual(AttributeTexts.font(.systemFont(ofSize: 12)), "System, Regular, 12 pt")
        XCTAssertEqual(AttributeTexts.font(.italicSystemFont(ofSize: 12.5)), "System, Regular, Italic, 12.5 pt")
        XCTAssertEqual(
            AttributeTexts.font(.monospacedDigitSystemFont(ofSize: 10, weight: .bold)),
            "System, Bold, 10 pt"
        )
        let helvetica = try XCTUnwrap(UIFont(name: "Helvetica-Bold", size: 14))
        XCTAssertEqual(AttributeTexts.font(helvetica), "Helvetica, Bold, 14 pt")
        let courier = try XCTUnwrap(UIFont(name: "Courier", size: 9))
        XCTAssertEqual(AttributeTexts.font(courier), "Courier, Regular, Monospaced, 9 pt")

        XCTAssertEqual(AttributeTexts.textStyle(of: .preferredFont(forTextStyle: .title1)), "title1")
        XCTAssertEqual(AttributeTexts.textStyle(of: .preferredFont(forTextStyle: .caption2)), "caption2")
        XCTAssertEqual(AttributeTexts.textStyle(of: .preferredFont(forTextStyle: .largeTitle)), "largeTitle")
        XCTAssertNil(AttributeTexts.textStyle(of: .systemFont(ofSize: 17)))
        XCTAssertEqual(AttributeTexts.textStyleName(UIFont.TextStyle(rawValue: "SomethingNew")), "SomethingNew")
    }

    // MARK: - S-ATTR-22

    private func label(text: String?, lines: Int, height: CGFloat, in window: UIWindow) -> UILabel {
        let label = UILabel(frame: CGRect(x: 10, y: 40, width: 200, height: height))
        label.font = .systemFont(ofSize: 17)
        label.numberOfLines = lines
        label.text = text
        window.addSubview(label)
        return label
    }

    func test_S_ATTR_22_drawnLinesAndTruncation() throws {
        let window = try makeWindow()
        let long = AttributeAssumptionTests.longText
        let short = label(text: "Short", lines: 1, height: 30, in: window)
        XCTAssertEqual(try int("label.drawnLineCount", of: short), 1)
        XCTAssertEqual(try bool("label.isTruncated", of: short), false)

        let two = label(text: long, lines: 2, height: 60, in: window)
        XCTAssertEqual(try int("label.drawnLineCount", of: two), 2)
        XCTAssertEqual(try bool("label.isTruncated", of: two), true)

        let unlimited = label(text: long, lines: 0, height: 400, in: window)
        let font = try XCTUnwrap(unlimited.font)
        let rect = unlimited.textRect(forBounds: unlimited.bounds, limitedToNumberOfLines: 0)
        XCTAssertEqual(try int("label.drawnLineCount", of: unlimited), Int64((rect.height / font.lineHeight).rounded()))
        XCTAssertEqual(try bool("label.isTruncated", of: unlimited), false)

        let empty = label(text: nil, lines: 1, height: 30, in: window)
        XCTAssertEqual(try int("label.drawnLineCount", of: empty), 0)
        XCTAssertEqual(try bool("label.isTruncated", of: empty), false)

        let shrinking = label(text: long, lines: 1, height: 30, in: window)
        shrinking.adjustsFontSizeToFitWidth = true
        XCTAssertNil(try int("label.drawnLineCount", of: shrinking))
        XCTAssertNil(try bool("label.isTruncated", of: shrinking))
    }
}
