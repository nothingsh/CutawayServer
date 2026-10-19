import UIKit
import XCTest

@testable import CutawayServer

/// What the attributes of protocol 1.2 rest on (assumptions H3 to H5): UIKit's own behavior,
/// tested without the server.
final class AttributeAssumptionTests: CaptureTestCase {
    // MARK: - H3: lists are read without layout and without asking the data source

    /// H3: a laid-out table answers its counts and visible rows from what it has.
    func test_S_ATTR_19_H3_tableIsReadWithoutLayoutOrDataSource() throws {
        let (table, source) = try makeTable()
        let before = (table.layouts, source.calls)
        let counts = (0..<table.numberOfSections).map(table.numberOfRows(inSection:))
        let visible = table.indexPathsForVisibleRows ?? []
        XCTAssertEqual(counts, [3, 5])
        XCTAssertFalse(visible.isEmpty)
        XCTAssertEqual(table.layouts, before.0, "reading laid the table out")
        XCTAssertEqual(source.calls, before.1, "reading asked the data source")
        XCTAssertFalse(table.layer.needsLayout())
    }

    /// H3: after `reloadData()` and before the next layout, reading still lays nothing out and
    /// asks the data source nothing.
    func test_S_ATTR_19_H3_reloadedTableIsReadWithoutLayoutOrDataSource() throws {
        let (table, source) = try makeTable()
        source.rows = [2, 4, 1]
        table.reloadData()
        let before = (table.layouts, source.calls)
        let needsLayout = table.layer.needsLayout()
        _ = (0..<table.numberOfSections).map(table.numberOfRows(inSection:))
        _ = table.indexPathsForVisibleRows
        XCTAssertEqual(table.layouts, before.0, "reading laid the table out")
        XCTAssertEqual(source.calls, before.1, "reading asked the data source")
        XCTAssertEqual(table.layer.needsLayout(), needsLayout)
    }

    /// H3: a laid-out collection view answers its counts and visible items from what it has.
    func test_S_ATTR_19_H3_collectionViewIsReadWithoutLayoutOrDataSource() throws {
        let (collection, source) = try makeCollection()
        let before = (collection.layouts, source.calls)
        XCTAssertFalse(collection.layer.needsLayout())
        let counts = (0..<collection.numberOfSections).map(collection.numberOfItems(inSection:))
        XCTAssertEqual(counts, [3, 5])
        XCTAssertFalse(collection.indexPathsForVisibleItems.isEmpty)
        XCTAssertEqual(collection.layouts, before.0, "reading laid the collection view out")
        XCTAssertEqual(source.calls, before.1, "reading asked the data source")
    }

    /// H3 does not hold for a collection view between `reloadData()` and the next layout: its
    /// counts ask the data source again (S-D-184). It needs layout then, which is how the
    /// catalog tells; its visible items are still read without asking.
    func test_S_ATTR_19_H3_reloadedCollectionViewNeedsLayoutAndAsksForCounts() throws {
        let (collection, source) = try makeCollection()
        source.items = [2, 4, 1]
        collection.reloadData()
        XCTAssertTrue(collection.layer.needsLayout())
        var calls = source.calls
        _ = collection.indexPathsForVisibleItems
        XCTAssertEqual(source.calls, calls, "the visible items asked the data source")
        let layouts = collection.layouts
        _ = collection.numberOfSections
        XCTAssertGreaterThan(source.calls, calls, "the counts no longer ask the data source")
        XCTAssertEqual(collection.layouts, layouts, "reading laid the reloaded collection view out")
        calls = source.calls
        _ = collection.numberOfItems(inSection: 1)
        XCTAssertEqual(source.calls, calls)
    }

    // MARK: - H4: image names and symbol configurations from descriptions

    /// H4: the description of an image from an asset catalog names it, and that of a symbol
    /// names the symbol; one made otherwise is anonymous. The format is this system's.
    func test_S_ATTR_20_H4_descriptionsNameImagesAndSymbols() throws {
        let named = try XCTUnwrap(UIImage(named: "Swatch"))
        XCTAssertTrue(named.description.contains(" named(main: Swatch) "), named.description)
        let symbol = try XCTUnwrap(UIImage(systemName: "star.fill"))
        XCTAssertTrue(symbol.description.contains(" symbol(system: star.fill) "), symbol.description)
        let drawn = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        XCTAssertTrue(drawn.description.contains(" anonymous "), drawn.description)
        // A copy made with another rendering mode loses the name.
        let template = named.withRenderingMode(.alwaysTemplate)
        XCTAssertTrue(template.description.contains(" anonymous "), template.description)
    }

    /// H4: a symbol configuration describes its point size, weight and scale, then the traits it
    /// was resolved with; one without any of the three describes only the traits. The words
    /// differ between systems: iOS 15 writes `scale=L, (null)`, iOS 26 `scale=Large`.
    func test_S_ATTR_20_H4_descriptionsGiveSymbolConfigurations() throws {
        let configured = try XCTUnwrap(UIImage(
            systemName: "heart",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 24, weight: .bold, scale: .large)
        ))
        let description = try XCTUnwrap(configured.symbolConfiguration?.description)
        XCTAssertTrue(description.hasPrefix("pointSize=24, weight=Bold, scale="), description)
        XCTAssertTrue(description.contains("traits=("), description)
        let plain = try XCTUnwrap(UIImage(systemName: "star.fill")?.symbolConfiguration?.description)
        XCTAssertTrue(plain.hasPrefix("traits=("), plain)
    }

    // MARK: - H5: lines measured with TextKit

    /// H5: one line of short text, not truncated.
    func test_S_ATTR_22_H5_shortTextIsOneLine() throws {
        let label = try makeLabel(text: "Short", lines: 1, height: 30)
        let measured = measure(label)
        XCTAssertEqual(measured.lines, 1)
        XCTAssertFalse(measured.truncated)
        XCTAssertEqual(measured.lines, drawnLines(label))
    }

    /// H5: long text cut to two lines is two lines, truncated.
    func test_S_ATTR_22_H5_twoLinesOfLongTextAreTruncated() throws {
        let label = try makeLabel(text: Self.longText, lines: 2, height: 60)
        let measured = measure(label)
        XCTAssertEqual(measured.lines, 2)
        XCTAssertTrue(measured.truncated)
        XCTAssertEqual(measured.lines, drawnLines(label))
    }

    /// H5: long text with no limit and room enough is as many lines as UILabel draws.
    func test_S_ATTR_22_H5_unlimitedLongTextAgreesWithTheLabel() throws {
        let label = try makeLabel(text: Self.longText, lines: 0, height: 400)
        let measured = measure(label)
        XCTAssertGreaterThan(measured.lines, 2)
        XCTAssertEqual(measured.lines, drawnLines(label))
        XCTAssertFalse(measured.truncated)
    }

    /// H5: with no limit but too little height, what fits is drawn, and the rest is cut.
    func test_S_ATTR_22_H5_unlimitedTextInTooLittleHeightIsTruncated() throws {
        let label = try makeLabel(text: Self.longText, lines: 0, height: 45)
        let measured = measure(label)
        XCTAssertEqual(measured.lines, drawnLines(label))
        XCTAssertTrue(measured.truncated)
    }

    /// H5: no text is no line.
    func test_S_ATTR_22_H5_noTextIsNoLine() throws {
        let label = try makeLabel(text: nil, lines: 1, height: 30)
        let measured = measure(label)
        XCTAssertEqual(measured.lines, 0)
        XCTAssertFalse(measured.truncated)
    }

    // MARK: - Helpers

    static let longText = String(
        repeating: "The quick brown fox jumps over the lazy dog. ",
        count: 6
    )

    /// The lines UILabel lays its text out in, from the height of `textRect`.
    private func drawnLines(_ label: UILabel) -> Int {
        guard let font = label.font, label.text?.isEmpty == false else { return 0 }
        let rect = label.textRect(forBounds: label.bounds, limitedToNumberOfLines: label.numberOfLines)
        return Int((rect.height / font.lineHeight).rounded())
    }

    /// The way the catalog will measure: TextKit with the label's bounds and line limit. Lines
    /// wrap as UILabel wraps all but its last one; a truncating line break mode would cut
    /// every line in TextKit 1.
    private func measure(_ label: UILabel) -> (lines: Int, truncated: Bool) {
        guard let text = label.attributedText, text.length > 0 else { return (0, false) }
        let storage = NSTextStorage(attributedString: text)
        // Every line but the last wraps; truncation is told from the glyphs left out.
        let wrapping: NSLineBreakMode = label.lineBreakMode == .byCharWrapping ? .byCharWrapping : .byWordWrapping
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(
            location: 0,
            length: storage.length
        )) { value, range, _ in
            let style = (value as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.lineBreakMode = wrapping
            storage.addAttribute(.paragraphStyle, value: style, range: range)
        }
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: label.bounds.size)
        container.lineFragmentPadding = 0
        container.maximumNumberOfLines = label.numberOfLines
        container.lineBreakMode = wrapping
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        let glyphs = manager.glyphRange(for: container)
        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, _, _ in lines += 1 }
        return (lines, NSMaxRange(glyphs) < manager.numberOfGlyphs)
    }

    private func makeLabel(text: String?, lines: Int, height: CGFloat) throws -> UILabel {
        let window = try makeWindow()
        let label = UILabel(frame: CGRect(x: 10, y: 40, width: 200, height: height))
        label.font = .systemFont(ofSize: 17)
        label.numberOfLines = lines
        label.text = text
        window.addSubview(label)
        window.layoutIfNeeded()
        return label
    }

    private func makeTable() throws -> (CountingTableView, CountingDataSource) {
        let window = try makeWindow()
        let source = CountingDataSource()
        let table = CountingTableView(frame: window.bounds, style: .plain)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        table.dataSource = source
        window.addSubview(table)
        window.layoutIfNeeded()
        retained.append(source)
        return (table, source)
    }

    private func makeCollection() throws -> (CountingCollectionView, CountingDataSource) {
        let window = try makeWindow()
        let source = CountingDataSource()
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 60, height: 40)
        let collection = CountingCollectionView(frame: window.bounds, collectionViewLayout: layout)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "item")
        collection.dataSource = source
        window.addSubview(collection)
        window.layoutIfNeeded()
        retained.append(source)
        return (collection, source)
    }

    /// Data sources are held weakly by their lists.
    private var retained: [AnyObject] = []
}

/// Counts its layouts.
final class CountingTableView: UITableView {
    private(set) var layouts = 0

    override func layoutSubviews() {
        layouts += 1
        super.layoutSubviews()
    }
}

/// Counts its layouts.
final class CountingCollectionView: UICollectionView {
    private(set) var layouts = 0

    override func layoutSubviews() {
        layouts += 1
        super.layoutSubviews()
    }
}

/// Two sections of 3 and 5 rows or items, for a table or a collection view; counts every call.
final class CountingDataSource: NSObject, UITableViewDataSource, UICollectionViewDataSource {
    var rows = [3, 5]
    var items: [Int] {
        get { rows }
        set { rows = newValue }
    }

    private(set) var calls = 0

    func numberOfSections(in tableView: UITableView) -> Int {
        calls += 1
        return rows.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        calls += 1
        return rows[section]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        calls += 1
        return tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        calls += 1
        return rows.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        calls += 1
        return rows[section]
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        calls += 1
        return collectionView.dequeueReusableCell(withReuseIdentifier: "item", for: indexPath)
    }
}
