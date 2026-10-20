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

/// A view controller that is a table's data source, with two sections of 3 and 5 rows.
private final class SourceController: UIViewController, UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { [3, 5][section] }

    func numberOfSections(in tableView: UITableView) -> Int { 2 }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
    }
}

/// The values of the attributes of protocol 1.2 (S-ATTR-16 to 22). No server, no connection.
final class AttributeValuesV12Tests: CaptureTestCase {
    private var registry = LayerRegistry()
    /// Data sources and delegates are held weakly.
    private var retained: [AnyObject] = []

    private func reading(_ windows: [UIWindow]) -> AttributeReading {
        AttributeReading(registry: registry, windows: windows)
    }

    private func value(
        _ id: String,
        of view: UIView,
        in windows: [UIWindow]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> AttributeValue? {
        let groupID = String(id.prefix { $0 != "." })
        let groups = AttributeCatalog.standard.read(view.layer, reading: reading(windows ?? HostWindows.all()))
        let group = try XCTUnwrap(groups.first { $0.id == groupID }, "no group \(groupID)", file: file, line: line)
        let attribute = try XCTUnwrap(
            group.attributes.first { $0.id == id },
            "no attribute \(id)",
            file: file,
            line: line
        )
        return attribute.value
    }

    private func string(_ id: String, of view: UIView, file: StaticString = #filePath, line: UInt = #line) throws
        -> String? {
        switch try value(id, of: view, file: file, line: line) {
        case nil: return nil
        case .string(let text): return text
        case let other?:
            XCTFail("\(id) is \(other), not a string", file: file, line: line)
            return nil
        }
    }

    private func int(_ id: String, of view: UIView, file: StaticString = #filePath, line: UInt = #line) throws
        -> Int64? {
        switch try value(id, of: view, file: file, line: line) {
        case nil: return nil
        case .int(let number): return number
        case let other?:
            XCTFail("\(id) is \(other), not an integer", file: file, line: line)
            return nil
        }
    }

    private func bool(_ id: String, of view: UIView, file: StaticString = #filePath, line: UInt = #line) throws
        -> Bool? {
        switch try value(id, of: view, file: file, line: line) {
        case nil: return nil
        case .bool(let flag): return flag
        case let other?:
            XCTFail("\(id) is \(other), not a Boolean", file: file, line: line)
            return nil
        }
    }

    private func references(
        _ id: String,
        of view: UIView,
        in windows: [UIWindow]? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [ObjectReference]? {
        switch try value(id, of: view, in: windows, file: file, line: line) {
        case nil: return nil
        case .layerReference(let references): return references
        case let other?:
            XCTFail("\(id) is \(other), not references", file: file, line: line)
            return nil
        }
    }

    // MARK: - S-ATTR-16

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
    }

    func test_S_ATTR_16_traitsAreNamedAndUnknownBitsAreHex() {
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

    // MARK: - S-ATTR-17

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

    // MARK: - S-ATTR-18

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
        let hierarchy = HierarchyCapture.capture(windows: [window], registry: registry)
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

    // MARK: - S-ATTR-19

    private func makeTable(in window: UIWindow) -> (UITableView, SourceController) {
        let controller = SourceController()
        retained.append(controller)
        let table = UITableView(frame: CGRect(x: 0, y: 0, width: 320, height: 300), style: .plain)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.rowHeight = 44
        table.dataSource = controller
        window.addSubview(table)
        window.layoutIfNeeded()
        return (table, controller)
    }

    func test_S_ATTR_19_tableCountsAndVisibleRows() throws {
        let window = try makeWindow()
        let (table, _) = makeTable(in: window)
        XCTAssertEqual(try int("tableView.numberOfSections", of: table), 2)
        XCTAssertEqual(try int("tableView.numberOfRows", of: table), 8)
        XCTAssertEqual(try string("tableView.rowsPerSection", of: table), "3, 5")
        let visible = (table.indexPathsForVisibleRows ?? []).sorted()
        XCTAssertFalse(visible.isEmpty)
        XCTAssertEqual(
            try string("tableView.visibleIndexPaths", of: table),
            visible.map { "\($0.section).\($0.row)" }.joined(separator: ", ")
        )
    }

    func test_S_ATTR_19_cellsKnowWhereTheyAre() throws {
        let window = try makeWindow()
        let (table, _) = makeTable(in: window)
        let paths = try XCTUnwrap(table.indexPathsForVisibleRows)
        for path in paths {
            let cell = try XCTUnwrap(table.cellForRow(at: path))
            XCTAssertEqual(try int("tableViewCell.section", of: cell), Int64(path.section))
            XCTAssertEqual(try int("tableViewCell.row", of: cell), Int64(path.row))
            XCTAssertEqual(try string("tableViewCell.reuseIdentifier", of: cell), "row")
        }
        let loose = UITableViewCell(style: .default, reuseIdentifier: nil)
        window.addSubview(loose)
        XCTAssertNil(try int("tableViewCell.section", of: loose))
        XCTAssertNil(try int("tableViewCell.row", of: loose))
        XCTAssertNil(try string("tableViewCell.reuseIdentifier", of: loose))
    }

    private func makeCollection(in window: UIWindow) -> (UICollectionView, CountingDataSource) {
        let source = CountingDataSource()
        retained.append(source)
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 60, height: 40)
        let collection = UICollectionView(frame: window.bounds, collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "item")
        collection.dataSource = source
        window.addSubview(collection)
        window.layoutIfNeeded()
        return (collection, source)
    }

    func test_S_ATTR_19_collectionCountsVisibleItemsAndCells() throws {
        let window = try makeWindow()
        let (collection, _) = makeCollection(in: window)
        XCTAssertEqual(try int("collectionView.numberOfSections", of: collection), 2)
        XCTAssertEqual(try int("collectionView.numberOfItems", of: collection), 8)
        XCTAssertEqual(try string("collectionView.itemsPerSection", of: collection), "3, 5")
        let visible = collection.indexPathsForVisibleItems.sorted()
        XCTAssertFalse(visible.isEmpty)
        XCTAssertEqual(
            try string("collectionView.visibleIndexPaths", of: collection),
            visible.map { "\($0.section).\($0.item)" }.joined(separator: ", ")
        )
        for path in visible {
            let cell = try XCTUnwrap(collection.cellForItem(at: path))
            XCTAssertEqual(try int("collectionViewCell.section", of: cell), Int64(path.section))
            XCTAssertEqual(try int("collectionViewCell.item", of: cell), Int64(path.item))
            XCTAssertEqual(try string("collectionViewCell.reuseIdentifier", of: cell), "item")
        }
    }

    /// S-D-184: between `reloadData()` and the next layout the counts would ask the data
    /// source, so they are not read.
    func test_S_ATTR_19_reloadedCollectionGivesNoCounts() throws {
        let window = try makeWindow()
        let (collection, source) = makeCollection(in: window)
        source.items = [1, 2]
        collection.reloadData()
        let calls = source.calls
        XCTAssertNil(try int("collectionView.numberOfSections", of: collection))
        XCTAssertNil(try int("collectionView.numberOfItems", of: collection))
        XCTAssertNil(try string("collectionView.itemsPerSection", of: collection))
        XCTAssertNotNil(try string("collectionView.visibleIndexPaths", of: collection))
        XCTAssertEqual(source.calls, calls)
        window.layoutIfNeeded()
        XCTAssertEqual(try string("collectionView.itemsPerSection", of: collection), "1, 2")
    }

    func test_S_ATTR_19_longListsAreCut() {
        XCTAssertEqual(AttributeTexts.list([]), "None")
        XCTAssertEqual(AttributeTexts.list(["a", "b"]), "a, b")
        let long = (0..<150).map(String.init)
        let text = AttributeTexts.list(long)
        XCTAssertTrue(text.hasPrefix("0, 1, 2, "), text)
        XCTAssertTrue(text.hasSuffix(", 99, … (50 more)"), text)
        XCTAssertEqual(AttributeTexts.list(Array(long.prefix(100))).components(separatedBy: ", ").count, 100)
    }

    func test_S_ATTR_19_customSpacingListsWhatWasSet() throws {
        let window = try makeWindow()
        let views = [UIView(), UIView(), UIView()]
        let stack = UIStackView(arrangedSubviews: views)
        window.addSubview(stack)
        XCTAssertNil(try string("stackView.customSpacing", of: stack))
        stack.setCustomSpacing(12, after: views[0])
        stack.setCustomSpacing(UIStackView.spacingUseSystem, after: views[2])
        XCTAssertEqual(try string("stackView.customSpacing", of: stack), "after 0: 12, after 2: system")
        stack.setCustomSpacing(4.5, after: views[1])
        XCTAssertEqual(try string("stackView.customSpacing", of: stack), "after 0: 12, after 1: 4.5, after 2: system")
    }

    // MARK: - S-ATTR-20

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
        // This system's words (H4): iOS 15 says `scale=L`, iOS 26 `scale=Large`.
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

/// A scroll view delegate that is not a view controller.
private final class ScrollDelegate: NSObject, UIScrollViewDelegate {}
