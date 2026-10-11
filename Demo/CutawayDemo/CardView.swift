import UIKit

/// A view class of the demo's own, so that the hierarchy has a Swift class name to make
/// readable. It clips a shape layer that it adds by hand.
final class CardView: UIView {
    /// Not a view's layer: hidden and half transparent.
    let badge = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        backgroundColor = UIColor(red: 0, green: 0.6, blue: 0.3, alpha: 1)
        clipsToBounds = true
        badge.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
        badge.position = CGPoint(x: 40, y: 40)
        badge.path = CGPath(ellipseIn: badge.bounds, transform: nil)
        badge.fillColor = UIColor(red: 1, green: 1, blue: 0, alpha: 1).cgColor
        badge.isHidden = true
        badge.opacity = 0.5
        layer.addSublayer(badge)
    }
}
