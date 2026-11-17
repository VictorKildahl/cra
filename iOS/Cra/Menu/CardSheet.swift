import SwiftUI
import UIKit

/// Arc Search's sheets (Victor's screenshots IMG_1897–1904, 13 Nov, iPhone 16 Pro Max on iOS 26):
/// a card from the top of the safe area to the bottom edge, continuous 38.5 pt corners at the top
/// (the Spaces list rounds its own bottom: "Connecting" runs square to the edge), over the tab row dimmed to #100E18 from #1C1B2F and not pushed back. A sheet opened
/// from that card (the share how-to, IMG_1899) starts 10 pt lower with round 35 pt top corners
/// and bottom corners that follow the screen's (continuous 63.5 pt), and pushes the card back: shrunk to 91 % about its
/// top, darkened. A drag down from anywhere not mid-scroll puts either away.
final class CardSheet: NSObject, UIViewControllerTransitioningDelegate {
    struct Style {
        var topInset: CGFloat
        var topRadius: CGFloat
        var topStyle: RoundedCornerStyle
        var bottomRadius: CGFloat
        /// The sheet underneath shrinks back as in a system page sheet.
        var pushesBack: Bool

        /// The Spaces card. The radius fitted to the edge's inset at nine heights (0.3 pt below
        /// the top it is 46.7 pt in, 38 pt below 0.3 pt).
        static let card = Style(topInset: 0, topRadius: 38.5, topStyle: .continuous, bottomRadius: 0, pushesBack: false)
        /// A sheet over the card: top 10 pt lower, its corners fitted the same way.
        static let stacked = Style(topInset: 10, topRadius: 35, topStyle: .circular, bottomRadius: 63.5, pushesBack: true)
    }

    static let dim: CGFloat = 0.45
    static let pushedScale: CGFloat = 0.91
    static let pushedDim: CGFloat = 0.3

    private let style: Style
    private let onDismiss: (() -> Void)?

    private init(style: Style, onDismiss: (() -> Void)?) {
        self.style = style
        self.onDismiss = onDismiss
    }

    /// Presents `controller` as a card from `presenter`; `onDismiss` runs once it is gone,
    /// however it was put away.
    static func present(_ controller: UIViewController, from presenter: UIViewController, style: Style = .card, onDismiss: (() -> Void)? = nil) {
        let delegate = CardSheet(style: style, onDismiss: onDismiss)
        controller.modalPresentationStyle = .custom
        controller.transitioningDelegate = delegate
        // The transitioning delegate is held weakly by UIKit.
        objc_setAssociatedObject(controller, &delegateKey, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        presenter.present(controller, animated: true)
    }

    func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
        CardPresentationController(presentedViewController: presented, presenting: presenting, style: style, onDismiss: onDismiss)
    }

    func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        CardAnimator(presenting: true)
    }

    func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        CardAnimator(presenting: false)
    }
}

private var delegateKey: UInt8 = 0

private final class CardPresentationController: UIPresentationController, UIGestureRecognizerDelegate {
    private let style: CardSheet.Style
    private let onDismiss: (() -> Void)?
    private let dimView = UIView()
    /// Darkens the pushed-back sheet underneath.
    private let shade = UIView()
    private let mask = CAShapeLayer()
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
    private var tracking = false

    init(presentedViewController: UIViewController, presenting: UIViewController?, style: CardSheet.Style, onDismiss: (() -> Void)?) {
        self.style = style
        self.onDismiss = onDismiss
        super.init(presentedViewController: presentedViewController, presenting: presenting)
    }

    override var frameOfPresentedViewInContainerView: CGRect {
        guard let container = containerView else { return .zero }
        let top = container.safeAreaInsets.top + style.topInset
        return CGRect(x: 0, y: top, width: container.bounds.width, height: container.bounds.height - top)
    }

    /// The pushed-back sheet underneath, if this one pushes it.
    private var underneath: UIView? {
        style.pushesBack && presentingViewController.presentationController is CardPresentationController ? presentingViewController.view : nil
    }

    override func presentationTransitionWillBegin() {
        guard let container = containerView else { return }
        dimView.backgroundColor = UIColor(white: 0, alpha: style.pushesBack ? 0 : CardSheet.dim)
        dimView.frame = container.bounds
        dimView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimView.alpha = 0
        dimView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))
        container.insertSubview(dimView, at: 0)
        presentedView?.layer.mask = mask
        let below = underneath
        if let below {
            shade.backgroundColor = UIColor(white: 0, alpha: CardSheet.pushedDim)
            shade.frame = below.bounds
            shade.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shade.alpha = 0
            below.addSubview(shade)
        }
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimView.alpha = 1
            self.shade.alpha = 1
            below?.transform = self.pushedTransform(for: below)
        })
    }

    /// Shrinks the sheet underneath about its own top edge, so its top stays where it was.
    private func pushedTransform(for view: UIView?) -> CGAffineTransform {
        guard let view else { return .identity }
        let scale = CardSheet.pushedScale
        let lift = view.bounds.height * (1 - scale) / 2
        return CGAffineTransform(translationX: 0, y: -lift).scaledBy(x: scale, y: scale)
    }

    override func presentationTransitionDidEnd(_ completed: Bool) {
        guard completed else {
            dimView.removeFromSuperview()
            shade.removeFromSuperview()
            underneath?.transform = .identity
            return
        }
        pan.delegate = self
        presentedView?.addGestureRecognizer(pan)
    }

    override func dismissalTransitionWillBegin() {
        let below = underneath
        presentedViewController.transitionCoordinator?.animate(alongsideTransition: { _ in
            self.dimView.alpha = 0
            self.shade.alpha = 0
            below?.transform = .identity
        })
    }

    override func dismissalTransitionDidEnd(_ completed: Bool) {
        guard completed else { return }
        dimView.removeFromSuperview()
        shade.removeFromSuperview()
        onDismiss?()
    }

    override func containerViewDidLayoutSubviews() {
        super.containerViewDidLayoutSubviews()
        guard let view = presentedView else { return }
        if !tracking, view.transform.isIdentity { view.frame = frameOfPresentedViewInContainerView }
        mask.path = outline(view.bounds.size)
    }

    /// Top corners of one radius, bottom corners of another: two rounded rectangles that overlap
    /// in the middle.
    private func outline(_ size: CGSize) -> CGPath {
        var path = Path(roundedRect: CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.6), cornerRadius: style.topRadius, style: style.topStyle)
        path.addPath(Path(roundedRect: CGRect(x: 0, y: size.height * 0.4, width: size.width, height: size.height * 0.6), cornerRadius: style.bottomRadius, style: .continuous))
        return path.cgPath
    }

    @objc private func dimTapped() {
        presentedViewController.dismiss(animated: true)
    }

    /// A drag down moves the card with the finger; let go past a quarter of its height, or
    /// flicked, it goes away; otherwise it springs back. Inside a list scrolled down, the
    /// list scrolls instead.
    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        guard let view = presentedView else { return }
        let frame = frameOfPresentedViewInContainerView
        let distance = max(0, pan.translation(in: view.superview).y)
        switch pan.state {
        case .began:
            tracking = !scrolledDown(at: pan.location(in: view), in: view)
        case .changed:
            guard tracking else { return }
            view.frame.origin.y = frame.minY + distance
            dimView.alpha = 1 - min(1, distance / frame.height)
        case .ended, .cancelled:
            guard tracking else { return }
            tracking = false
            let velocity = pan.velocity(in: view.superview).y
            if pan.state == .ended, distance > frame.height / 4 || velocity > 900 {
                presentedViewController.dismiss(animated: true)
            } else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0) {
                    view.frame = frame
                    self.dimView.alpha = 1
                }
            }
        default:
            tracking = false
        }
    }

    private func scrolledDown(at point: CGPoint, in view: UIView) -> Bool {
        var hit = view.hitTest(point, with: nil)
        while let current = hit, current !== view {
            if let scroll = current as? UIScrollView, scroll.contentSize.height > scroll.bounds.height, scroll.contentOffset.y > -scroll.adjustedContentInset.top + 0.5 {
                return true
            }
            hit = current.superview
        }
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = pan.view else { return true }
        let velocity = pan.velocity(in: view)
        return velocity.y > abs(velocity.x)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}

/// Slides the card up from the bottom edge, and back down.
private final class CardAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let presenting: Bool

    init(presenting: Bool) { self.presenting = presenting }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval { presenting ? 0.5 : 0.35 }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let container = context.containerView
        if presenting {
            guard let view = context.view(forKey: .to), let controller = context.viewController(forKey: .to) else { return context.completeTransition(false) }
            let final = context.finalFrame(for: controller)
            view.frame = final.offsetBy(dx: 0, dy: container.bounds.height - final.minY)
            container.addSubview(view)
            UIView.animate(withDuration: transitionDuration(using: context), delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
                view.frame = final
            } completion: { _ in
                context.completeTransition(!context.transitionWasCancelled)
            }
        } else {
            guard let view = context.view(forKey: .from) else { return context.completeTransition(false) }
            UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: [.curveEaseIn]) {
                view.frame.origin.y = container.bounds.height
            } completion: { _ in
                context.completeTransition(!context.transitionWasCancelled)
            }
        }
    }
}
