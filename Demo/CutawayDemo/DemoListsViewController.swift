import UIKit

/// The page of the attributes of protocol 1.2, opened with "Lists" on the detail page and
/// closed with "Close": lists and their cells, a stack view with a custom spacing, a symbol,
/// Dynamic Type, a truncated label and a button with an accessibility label.
/// `cutaway-probe --expect-demo` checks it when it is open (Sources/cutaway-probe/Demo/).
///
/// As on the main screen, everything the probe looks at is held in a property and has a fixed
/// frame.
final class DemoListsViewController: UIViewController, UITableViewDataSource, UICollectionViewDataSource {
    /// The rows of the table's sections, and the items of the collection view's.
    static let rows = [3, 5]
    static let items = [4, 2]
    static let truncatedText = String(repeating: "A label cut to two lines, however long its text is. ", count: 4)

    private let closeButton = UIButton(type: .system)
    private let listsTable = UITableView(frame: CGRect(x: 16, y: 100, width: 170, height: 200), style: .plain)
    private let listsCollection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 36, height: 36)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        return UICollectionView(frame: CGRect(x: 200, y: 100, width: 170, height: 200), collectionViewLayout: layout)
    }()

    private let spacedStack = UIStackView(frame: CGRect(x: 16, y: 316, width: 300, height: 30))
    private let symbolView = UIImageView(frame: CGRect(x: 16, y: 362, width: 30, height: 30))
    private let dynamicLabel = UILabel(frame: CGRect(x: 60, y: 362, width: 300, height: 30))
    private let truncatedLabel = UILabel(frame: CGRect(x: 16, y: 408, width: 300, height: 44))

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        closeButton.setTitle("Close", for: .normal)
        closeButton.accessibilityLabel = "Close the lists"
        closeButton.frame = CGRect(x: 16, y: 50, width: 80, height: 30)
        closeButton.addTarget(self, action: #selector(closePage), for: .touchUpInside)
        view.addSubview(closeButton)

        listsTable.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        listsTable.rowHeight = 44
        listsTable.dataSource = self
        view.addSubview(listsTable)

        listsCollection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "item")
        listsCollection.backgroundColor = UIColor(white: 0.95, alpha: 1)
        listsCollection.dataSource = self
        view.addSubview(listsCollection)

        for title in ["One", "Two", "Three"] {
            let label = UILabel()
            label.text = title
            label.textColor = .black
            spacedStack.addArrangedSubview(label)
        }
        spacedStack.spacing = 4
        spacedStack.setCustomSpacing(12, after: spacedStack.arrangedSubviews[0])
        view.addSubview(spacedStack)

        symbolView.image = UIImage(systemName: "star.fill")
        view.addSubview(symbolView)

        dynamicLabel.font = .preferredFont(forTextStyle: .body)
        dynamicLabel.adjustsFontForContentSizeCategory = true
        dynamicLabel.text = "Dynamic Type"
        dynamicLabel.textColor = .black
        view.addSubview(dynamicLabel)

        truncatedLabel.font = .systemFont(ofSize: 15)
        truncatedLabel.numberOfLines = 2
        truncatedLabel.text = Self.truncatedText
        truncatedLabel.textColor = .black
        view.addSubview(truncatedLabel)
    }

    @objc private func closePage() {
        dismiss(animated: true)
    }

    // MARK: - Data sources

    func numberOfSections(in tableView: UITableView) -> Int {
        Self.rows.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Self.rows[section]
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        cell.textLabel?.text = "Row \(indexPath.section).\(indexPath.row)"
        return cell
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        Self.items.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        Self.items[section]
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "item", for: indexPath)
        cell.backgroundColor = indexPath.section == 0 ? .systemBlue : .systemOrange
        return cell
    }
}
