import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// Changing the attributes of protocol 1.2 (S-SET-07). No server, no connection.
final class AttributeEditingV12Tests: CaptureTestCase {
    private let registry = LayerRegistry()
    /// Data sources are held weakly.
    private var retained: [AnyObject] = []

    private func apply(
        _ id: String,
        _ value: AttributeValue?,
        on view: UIView,
        in window: UIWindow
    ) -> Result<SetAttributeResult, WireError> {
        AttributeEditing.apply(
            SetAttribute(layerID: registry.register(view.layer), attributeID: id, value: value),
            windows: [window],
            registry: registry,
            appState: .active
        )
    }

    private func readBack(
        _ id: String,
        in result: Result<SetAttributeResult, WireError>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AttributeValue? {
        let answer = try result.get()
        return try XCTUnwrap(
            answer.attributeGroups.flatMap(\.attributes).first { $0.id == id },
            "no \(id) in the answer",
            file: file,
            line: line
        ).value
    }

    func test_S_SET_07_accessibilityIsWrittenAndReadBack() throws {
        let window = try makeWindow()
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        window.addSubview(view)
        for (id, text) in [
            ("view.accessibilityLabel", "Save"),
            ("view.accessibilityHint", "Saves the page"),
            ("view.accessibilityValue", "3"),
            ("view.accessibilityIdentifier", "save")
        ] {
            XCTAssertEqual(try readBack(id, in: apply(id, .string(text), on: view, in: window)), .string(text), id)
            XCTAssertNil(try readBack(id, in: apply(id, nil, on: view, in: window)), id)
        }
        XCTAssertEqual(
            try readBack(
                "view.isAccessibilityElement",
                in: apply("view.isAccessibilityElement", .bool(true), on: view, in: window)
            ),
            .bool(true)
        )
        XCTAssertTrue(view.isAccessibilityElement)
        view.accessibilityLabel = nil
        _ = try apply("view.accessibilityLabel", .string("Save"), on: view, in: window).get()
        XCTAssertEqual(view.accessibilityLabel, "Save")
    }

    func test_S_SET_07_textSizeFollowingIsWrittenAndReadBack() throws {
        let window = try makeWindow()
        let label = UILabel()
        let field = UITextField()
        let text = UITextView()
        for view in [label, field, text] as [UIView] {
            view.frame = CGRect(x: 0, y: 0, width: 200, height: 40)
            window.addSubview(view)
        }
        for (group, view) in [("label", label), ("textField", field), ("textView", text)] as [(String, UIView)] {
            let id = "\(group).adjustsFontForContentSizeCategory"
            XCTAssertEqual(try readBack(id, in: apply(id, .bool(true), on: view, in: window)), .bool(true), id)
            XCTAssertEqual(try readBack(id, in: apply(id, .bool(false), on: view, in: window)), .bool(false), id)
        }
        _ = try apply("label.adjustsFontForContentSizeCategory", .bool(true), on: label, in: window).get()
        XCTAssertTrue(label.adjustsFontForContentSizeCategory)
    }

    func test_S_SET_07_theOtherAttributesOfProtocol12AreNotEditable() throws {
        let window = try makeWindow()
        let view = UIView()
        let scroll = UIScrollView()
        let source = CountingDataSource()
        retained.append(source)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.dataSource = source
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 40, height: 40)
        let collection = UICollectionView(
            frame: CGRect(x: 0, y: 200, width: 320, height: 200),
            collectionViewLayout: layout
        )
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "item")
        collection.dataSource = source
        let tableCell = UITableViewCell(style: .default, reuseIdentifier: "cell")
        let collectionCell = UICollectionViewCell()
        let stack = UIStackView(arrangedSubviews: [UIView()])
        let image = UIImageView(image: UIImage(systemName: "star.fill"))
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "star.fill"), for: .normal)
        let label = UILabel()
        label.text = "Label"
        let field = UITextField()
        let text = UITextView()
        let views: [String: UIView] = [
            "view": view,
            "scrollView": scroll,
            "tableView": table,
            "collectionView": collection,
            "tableViewCell": tableCell,
            "collectionViewCell": collectionCell,
            "stackView": stack,
            "imageView": image,
            "button": button,
            "label": label,
            "textField": field,
            "textView": text
        ]
        for subview in views.values {
            if subview.frame.isEmpty { subview.frame = CGRect(x: 0, y: 0, width: 200, height: 40) }
            window.addSubview(subview)
        }
        window.layoutIfNeeded()

        let readOnly = [
            "view.accessibilityTraits",
            "scrollView.delegate",
            "stackView.arrangedSubviews",
            "stackView.customSpacing",
            "label.fontDescription",
            "label.fontTextStyle",
            "label.drawnLineCount",
            "label.isTruncated",
            "textField.fontDescription",
            "textField.fontTextStyle",
            "textView.fontDescription",
            "textView.fontTextStyle"
        ]
            + ["dataSource", "numberOfSections", "numberOfRows", "rowsPerSection", "visibleIndexPaths"]
            .map { "tableView.\($0)" }
            + ["dataSource", "numberOfSections", "numberOfItems", "itemsPerSection", "visibleIndexPaths"]
            .map { "collectionView.\($0)" }
            + ["section", "row", "reuseIdentifier"].map { "tableViewCell.\($0)" }
            + ["section", "item", "reuseIdentifier"].map { "collectionViewCell.\($0)" }
            + ["imageView", "button"].flatMap { group in
                ["imageName", "imageSize", "imageScale", "imageRenderingMode", "symbolConfiguration"]
                    .map { "\(group).\($0)" }
            }
        let entries = ExpectedAttributes.groups.values.flatMap(\.attributes)
        for id in readOnly {
            let entry = try XCTUnwrap(entries.first { $0.id == id }, id)
            XCTAssertFalse(entry.editable, id)
            let value: AttributeValue = switch entry.kind {
            case .string: .string("x")
            case .int: .int(1)
            case .bool: .bool(true)
            case .double: .double(1)
            case .size: .size(WireSize(width: 1, height: 1))
            case .enumeration: .enumeration(value: 0, cases: [], caseName: "", caseValues: [])
            case .layerReference: .layerReference([])
            default: .string("x")
            }
            let target = try XCTUnwrap(views[String(id.prefix { $0 != "." })], id)
            guard case .failure(let error) = apply(id, value, on: target, in: window) else {
                XCTFail("\(id) was written")
                continue
            }
            XCTAssertEqual(error.code, .attributeNotEditable, id)
        }
    }

    /// S-ATTR-17, P-SET-02: the light and dark of a colour are ignored when it is written.
    func test_S_ATTR_17_lightAndDarkAreIgnoredWhenWritten() throws {
        let window = try makeWindow()
        let plain = UIView()
        let styled = UIView()
        window.addSubview(plain)
        window.addSubview(styled)
        let color = WireColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let other = WireColor(red: 1, green: 0, blue: 0, alpha: 1)
        let written = try readBack(
            "view.backgroundColor",
            in: apply("view.backgroundColor", .color(color), on: plain, in: window)
        )
        let withBoth = try readBack(
            "view.backgroundColor",
            in: apply("view.backgroundColor", .color(color, light: other, dark: other), on: styled, in: window)
        )
        XCTAssertEqual(written, withBoth)
        guard case let .color(_, _, light, dark)? = withBoth else { return XCTFail("not a colour") }
        XCTAssertNil(light)
        XCTAssertNil(dark)
    }
}
