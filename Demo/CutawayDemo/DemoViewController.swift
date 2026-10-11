import UIKit

/// The screen cutaway-probe inspects. It shows what the protocol's `hierarchy` fixture
/// describes (Protocol/fixtures/README.md). Everything has a fixed frame, so that the
/// numbers are the same on every device; `cutaway-probe --expect-demo` checks them
/// (Sources/cutaway-probe/Demo/).
///
/// Everything the probe looks at is held in a property, so that the hierarchy names the
/// variable that holds it and the probe finds it by that name (P-HIER-08). The kinds of
/// property vary on purpose: constants, a weak one, a layer that backs no view, a lazy one.
/// The order of `addSubview` below is part of what the probe checks (P-HIER-01).
final class DemoViewController: UIViewController {
    // The basics: a label, a rotated card with a hidden shape layer, a scrolled scroll view, a
    // layer that backs no view, a view without a size.
    private let titleLabel = UILabel(frame: CGRect(x: 20, y: 60, width: 200, height: 24))
    private let cardView = CardView(frame: CGRect(x: 40, y: 150, width: 300, height: 180))
    private weak var scrollView: UIScrollView?
    private let bareLayer = CALayer()
    private let emptyView = UIView(frame: CGRect(x: 300, y: 700, width: 0, height: 0))
    // Drawing order and child view controllers.
    private lazy var depthView = UIView(frame: CGRect(x: 100, y: 640, width: 180, height: 40))
    // The editing corner, bottom right: views for trying attribute changes.
    private let pushStack = UIStackView()
    private let pushLabel = UILabel()
    private let pushedView = UIView()
    private let plainView = UIView(frame: CGRect(x: 290, y: 760, width: 90, height: 30))
    // The layout corner, top right: constraints and an autoresizing mask.
    private let layoutLabel = UILabel()
    private let autoresizingBox = UIView(frame: CGRect(x: 300, y: 100, width: 60, height: 24))
    private let autoresizedDot = UIView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        addBasics()
        addDepthAndChildController()
        addEditingCorner()
        addLayoutCorner()
    }

    private func addBasics() {
        let label = titleLabel
        label.text = "CutawayDemo"
        label.textColor = .black
        view.addSubview(label)

        // Rotated by 30 degrees about the z axis.
        let card = cardView
        card.transform = CGAffineTransform(rotationAngle: .pi / 6)
        view.addSubview(card)

        // Scrolled down by 100 points: the offset is the origin of the layer's bounds.
        let scrollView = UIScrollView(frame: CGRect(x: 40, y: 420, width: 300, height: 200))
        scrollView.backgroundColor = UIColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.contentSize = CGSize(width: 300, height: 600)
        let scrolled = UILabel(frame: CGRect(x: 100, y: 130, width: 100, height: 40))
        scrolled.text = "Scrolled"
        scrolled.textColor = .black
        scrollView.addSubview(scrolled)
        view.addSubview(scrollView)
        self.scrollView = scrollView
        scrollView.contentOffset = CGPoint(x: 0, y: 100)

        // A layer that backs no view, anchored at its top left corner.
        let bare = bareLayer
        bare.anchorPoint = .zero
        bare.bounds = CGRect(x: 0, y: 0, width: 60, height: 30)
        bare.position = CGPoint(x: 20, y: 650)
        bare.backgroundColor = UIColor(red: 1, green: 0.5, blue: 0, alpha: 1).cgColor
        view.layer.addSublayer(bare)

        // A view without a size.
        view.addSubview(emptyView)
    }

    private func addDepthAndChildController() {
        // Three overlapping blocks added as A, B, C with zPosition 1, -1, 0: drawn back to
        // front as B, C, A, which is the order the hierarchy lists them in (P-HIER-01).
        let depth = depthView
        let blocks: [(x: CGFloat, z: CGFloat, color: UIColor)] = [
            (0, 1, UIColor(red: 1, green: 0.3, blue: 0.3, alpha: 1)),
            (50, -1, UIColor(red: 0.3, green: 0.8, blue: 0.3, alpha: 1)),
            (100, 0, UIColor(red: 0.3, green: 0.3, blue: 1, alpha: 1))
        ]
        for block in blocks {
            let blockView = UIView(frame: CGRect(x: block.x, y: 0, width: 80, height: 40))
            blockView.backgroundColor = block.color
            blockView.layer.zPosition = block.z
            depth.addSubview(blockView)
        }
        view.addSubview(depth)

        // A child view controller: a navigation controller with a controller of its own
        // (P-HIER-07).
        let navigation = UINavigationController(rootViewController: DemoDetailViewController())
        addChild(navigation)
        navigation.view.frame = CGRect(x: 20, y: 700, width: 260, height: 110)
        view.addSubview(navigation.view)
        navigation.didMove(toParent: self)
    }

    private func addEditingCorner() {
        // A label in a vertical stack view: a longer text wraps, and the block below it moves
        // down. cutaway-probe changes the text and changes it back.
        let stack = pushStack
        stack.axis = .vertical
        let push = pushLabel
        push.text = "Push"
        push.numberOfLines = 0
        push.font = .systemFont(ofSize: 14)
        push.textColor = .black
        let pushed = pushedView
        pushed.backgroundColor = UIColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1)
        pushed.heightAnchor.constraint(equalToConstant: 20).isActive = true
        stack.addArrangedSubview(push)
        stack.addArrangedSubview(pushed)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 290),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 640),
            stack.widthAnchor.constraint(equalToConstant: 90)
        ])

        // A view without a background colour; its border shows where it is.
        let plain = plainView
        plain.layer.borderWidth = 1
        plain.layer.borderColor = UIColor.gray.cgColor
        view.addSubview(plain)
    }

    private func addLayoutCorner() {
        // A label tied to the safe area, with a width it does not get: `width == 30` at 500
        // loses to the label's horizontal compression resistance of 750. Lowering that below
        // 500 lets it win; cutaway-probe does, and changes it back.
        let layout = layoutLabel
        layout.text = "Layout"
        layout.font = .systemFont(ofSize: 14)
        layout.textColor = .black
        layout.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(layout)
        let narrow = layout.widthAnchor.constraint(equalToConstant: 30)
        narrow.priority = UILayoutPriority(500)
        NSLayoutConstraint.activate([
            layout.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            layout.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            narrow
        ])

        // A view placed by its frame and autoresizing mask, with a dot centred in it by
        // constraints. Referred to by them, the view gets constraints UIKit makes from its mask.
        let box = autoresizingBox
        box.backgroundColor = UIColor(white: 0.85, alpha: 1)
        box.autoresizingMask = [.flexibleLeftMargin, .flexibleBottomMargin]
        view.addSubview(box)
        let dot = autoresizedDot
        dot.backgroundColor = UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1)
        dot.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(dot)
        NSLayoutConstraint.activate([
            dot.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12)
        ])
    }
}

/// The controller inside the demo's navigation controller.
final class DemoDetailViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Detail"
        view.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.8, alpha: 1)

        // A page that can be closed: its layers are released when it is.
        let open = UIButton(type: .system)
        open.setTitle("Open", for: .normal)
        open.frame = CGRect(x: 16, y: 72, width: 80, height: 30)
        open.addTarget(self, action: #selector(openPage), for: .touchUpInside)
        view.addSubview(open)

        // Ten thousand layers, for trying a large hierarchy.
        let many = UIButton(type: .system)
        many.setTitle("Many layers", for: .normal)
        many.frame = CGRect(x: 104, y: 72, width: 120, height: 30)
        many.addTarget(self, action: #selector(openManyLayers), for: .touchUpInside)
        view.addSubview(many)
    }

    @objc private func openPage() {
        navigationController?.pushViewController(DemoPageViewController(), animated: true)
    }

    @objc private func openManyLayers() {
        let page = DemoManyLayersViewController()
        page.modalPresentationStyle = .fullScreen
        present(page, animated: true)
    }
}

/// The tree of the stability tests (S-STAB-01), for trying a large hierarchy by hand:
/// 10,101 layers, 5,101 of
/// them views, placed by 20,400 constraints. "Replace rows" changes the screen the way each
/// round of the long-use test does (S-STAB-02); "Close" releases it all.
final class DemoManyLayersViewController: UIViewController {
    private let tree = ManyLayersView(rows: 100, columns: 50)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        let close = UIButton(type: .system)
        close.setTitle("Close", for: .normal)
        close.addTarget(self, action: #selector(closePage), for: .touchUpInside)
        let replace = UIButton(type: .system)
        replace.setTitle("Replace rows", for: .normal)
        replace.addTarget(self, action: #selector(replaceRows), for: .touchUpInside)
        let buttons = UIStackView(arrangedSubviews: [close, replace])
        buttons.spacing = 24
        buttons.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(buttons)

        // Taller than most screens: it scrolls.
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(tree)
        scrollView.contentSize = tree.bounds.size
        view.addSubview(scrollView)

        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            buttons.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 8),
            buttons.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 16),
            scrollView.topAnchor.constraint(equalTo: buttons.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor)
        ])
    }

    @objc private func closePage() {
        dismiss(animated: true)
    }

    /// A quarter of the rows, with their cells and constraints, give way to new ones.
    @objc private func replaceRows() {
        tree.replaceRows(25)
    }
}

/// A page pushed onto the demo's navigation controller and closed with its back button.
final class DemoPageViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Page"
        view.backgroundColor = UIColor(red: 0.8, green: 0.95, blue: 0.95, alpha: 1)
        let label = UILabel(frame: CGRect(x: 16, y: 72, width: 220, height: 30))
        label.text = "Close me with Back"
        label.textColor = .black
        view.addSubview(label)
    }
}
