import CutawayWire
import UIKit
import XCTest

@testable import CutawayServer

/// A data source of the tests' own, private so that its runtime name is mangled.
private final class PlainSource: NSObject, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 0 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        UITableViewCell()
    }
}

/// Attributes that refer to other objects (S-ATTR-18). No server, no connection.
final class ReferenceAttributeTests: AttributeValueTestCase {
    func test_S_ATTR_18_arrangedSubviewsAreReferredToInOrder() throws {
        let window = try makeWindow()
        let first = UILabel()
        let second = UIView()
        let third = UIButton(type: .system)
        let stack = UIStackView(arrangedSubviews: [first, second, third])
        stack.frame = CGRect(x: 0, y: 0, width: 300, height: 40)
        window.addSubview(stack)
        let references = try XCTUnwrap(try references("stackView.arrangedSubviews", of: stack))
        XCTAssertEqual(references, [first, second, third].map {
            ObjectReference(
                layerID: registry.register($0.layer),
                className: NSStringFromClass(type(of: $0)),
                displayClassName: String(describing: type(of: $0))
            )
        })
        XCTAssertFalse(references.contains { $0.layerID == 0 })
        // The IDs are the hierarchy's.
        let hierarchy = HierarchyCapture.capture(.testing(windows: [window], registry: registry))
        for (view, reference) in zip([first, second, third], references) {
            XCTAssertEqual(try node(of: view.layer, in: hierarchy, registry: registry).id, reference.layerID)
        }

        let empty = UIStackView()
        window.addSubview(empty)
        XCTAssertEqual(try self.references("stackView.arrangedSubviews", of: empty), [])
    }

    func test_S_ATTR_18_viewsInNoWindowAreZero() throws {
        let window = try makeWindow()
        let stack = UIStackView(arrangedSubviews: [UIView()])
        window.addSubview(stack)
        // Read with windows that do not include the stack's.
        let references = try XCTUnwrap(try references("stackView.arrangedSubviews", of: stack, in: []))
        XCTAssertEqual(references.map(\.layerID), [0])
        XCTAssertEqual(references.map(\.className), ["UIView"])
    }

    func test_S_ATTR_18_aControllerIsReferredToByItsRootView() throws {
        let window = try makeWindow()
        let controller = SourceController()
        window.rootViewController = controller
        window.isHidden = false
        controller.view.frame = window.bounds
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.dataSource = controller
        controller.view.addSubview(table)
        let reference = try XCTUnwrap(try references("tableView.dataSource", of: table)?.first)
        XCTAssertEqual(reference.layerID, registry.register(controller.view.layer))
        XCTAssertEqual(reference.className, NSStringFromClass(SourceController.self))
        XCTAssertEqual(reference.displayClassName, "SourceController")
    }

    func test_S_ATTR_18_aControllerWhoseViewIsNotLoadedIsZeroAndStaysUnloaded() throws {
        let window = try makeWindow()
        let controller = SourceController()
        retained.append(controller)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300))
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.dataSource = controller
        window.addSubview(table)
        let reference = try XCTUnwrap(try references("tableView.dataSource", of: table)?.first)
        XCTAssertEqual(reference.layerID, 0)
        XCTAssertEqual(reference.displayClassName, "SourceController")
        XCTAssertFalse(controller.isViewLoaded, "reading loaded the controller's view")
    }

    func test_S_ATTR_18_otherObjectsAreZeroWithTheirClass() throws {
        let window = try makeWindow()
        let source = PlainSource()
        retained.append(source)
        let table = UITableView()
        table.dataSource = source
        window.addSubview(table)
        let reference = try XCTUnwrap(try references("tableView.dataSource", of: table)?.first)
        XCTAssertEqual(reference.layerID, 0)
        XCTAssertEqual(reference.className, NSStringFromClass(PlainSource.self))
        XCTAssertEqual(reference.displayClassName, "PlainSource")
    }

    func test_S_ATTR_18_nilPropertiesHaveNoValue() throws {
        let window = try makeWindow()
        let scroll = UIScrollView()
        let table = UITableView()
        window.addSubview(scroll)
        window.addSubview(table)
        XCTAssertNil(try references("scrollView.delegate", of: scroll))
        XCTAssertNil(try references("tableView.dataSource", of: table))

        let delegate = ScrollDelegate()
        retained.append(delegate)
        scroll.delegate = delegate
        XCTAssertEqual(try references("scrollView.delegate", of: scroll)?.map(\.displayClassName), ["ScrollDelegate"])
    }
}

/// A scroll view delegate that is not a view controller.
private final class ScrollDelegate: NSObject, UIScrollViewDelegate {}
