#if canImport(UIKit) && (DEBUG || ReleaseEnabled)
import UIKit

/// What a change to the app touches, which decides how much of UIKit it holds back.
enum ChangeKind {
    /// Properties of views and layers (P-SET-05): implicit actions are disabled, so that no
    /// layer asks for an animation, also inside an animation block of the app's.
    case attributes
    /// The traits of windows (P-ENV-02): UIView animations are held back as well, and the
    /// windows' traits are brought up to date before they are laid out.
    case traits
}

/// Makes a change to the app the way the server makes every change (P-SET-05, P-ENV-02): in one
/// transaction with implicit animations off, as `kind` says; then `windows` are laid out,
/// `layer` is redrawn, and the transaction is committed. What is captured next shows the
/// change, and nothing animates to it.
@MainActor
func changeWithoutAnimation<Value>(
    _ kind: ChangeKind,
    layingOut windows: [UIWindow],
    redrawing layer: CALayer? = nil,
    _ change: () -> Value
) -> Value {
    func transaction() -> Value {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let value = change()
        for window in windows {
            if kind == .traits, #available(iOS 17, *) { window.updateTraitsIfNeeded() }
            window.layoutIfNeeded()
        }
        layer?.displayIfNeeded()
        CATransaction.commit()
        return value
    }
    guard kind == .traits else { return transaction() }
    var value: Value?
    UIView.performWithoutAnimation { value = transaction() }
    guard let value else { preconditionFailure("performWithoutAnimation runs its block before it returns") }
    return value
}
#endif
