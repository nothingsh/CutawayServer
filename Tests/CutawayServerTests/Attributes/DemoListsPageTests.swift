import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// The demo app's Lists page (Demo/CutawayDemo/DemoListsViewController.swift) reads as
/// `cutaway-probe --expect-demo` expects it to (Sources/cutaway-probe/Demo/AttributeChecks+DemoLists.swift),
/// without running the demo app.
final class DemoListsPageTests: CaptureTestCase {
    func test_S_PROBE_07_theListsPageReadsAsTheProbeExpects() throws {
        let window = try makeWindow()
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let page = DemoListsViewController()
        window.rootViewController = page
        window.layoutIfNeeded()
        let registry = LayerRegistry()
        let reading = AttributeReading(registry: registry, windows: [window])
        func value(_ id: String, of view: UIView) -> AttributeValue? {
            AttributeCatalog.standard.read(view.layer, reading: reading).flatMap(\.attributes).first { $0.id == id }?
                .value
        }

        let subviews = page.view.subviews
        XCTAssertEqual(subviews.count, 7)
        let close = try XCTUnwrap(subviews[0] as? UIButton)
        let table = try XCTUnwrap(subviews[1] as? UITableView)
        let collection = try XCTUnwrap(subviews[2] as? UICollectionView)
        let stack = try XCTUnwrap(subviews[3] as? UIStackView)
        let symbol = try XCTUnwrap(subviews[4] as? UIImageView)
        let dynamic = try XCTUnwrap(subviews[5] as? UILabel)
        let truncated = try XCTUnwrap(subviews[6] as? UILabel)

        let controller = ObjectReference(
            layerID: registry.register(page.view.layer),
            className: "CutawayServerTests.DemoListsViewController",
            displayClassName: "DemoListsViewController"
        )
        XCTAssertEqual(value("tableView.dataSource", of: table), .layerReference([controller]))
        XCTAssertEqual(value("tableView.numberOfSections", of: table), .int(2))
        XCTAssertEqual(value("tableView.numberOfRows", of: table), .int(8))
        XCTAssertEqual(value("tableView.rowsPerSection", of: table), .string("3, 5"))
        XCTAssertEqual(value("collectionView.dataSource", of: collection), .layerReference([controller]))
        XCTAssertEqual(value("collectionView.numberOfSections", of: collection), .int(2))
        XCTAssertEqual(value("collectionView.numberOfItems", of: collection), .int(6))
        XCTAssertEqual(value("collectionView.itemsPerSection", of: collection), .string("4, 2"))
        for (id, view) in [("tableView.visibleIndexPaths", table), ("collectionView.visibleIndexPaths", collection)]
            as [(String, UIView)] {
            guard case .string(let text)? = value(id, of: view) else { return XCTFail("\(id) is not text") }
            XCTAssertTrue(text.hasPrefix("0.0"), "\(id): \(text)")
        }
        XCTAssertEqual(
            value("stackView.arrangedSubviews", of: stack),
            .layerReference(stack.arrangedSubviews.map {
                ObjectReference(layerID: registry.register($0.layer), className: "UILabel", displayClassName: "UILabel")
            })
        )
        XCTAssertEqual(stack.arrangedSubviews, stack.subviews, "the hierarchy lists the arranged subviews in order")
        XCTAssertEqual(value("stackView.customSpacing", of: stack), .string("after 0: 12"))
        XCTAssertEqual(value("imageView.imageName", of: symbol), .string("star.fill"))
        XCTAssertEqual(value("label.fontTextStyle", of: dynamic), .string("body"))
        XCTAssertEqual(value("label.adjustsFontForContentSizeCategory", of: dynamic), .bool(true))
        XCTAssertEqual(value("label.drawnLineCount", of: truncated), .int(2))
        XCTAssertEqual(value("label.isTruncated", of: truncated), .bool(true))
        XCTAssertEqual(value("view.accessibilityLabel", of: close), .string("Close the lists"))
    }
}
