import UIKit

/// A sheet of Cra's own: a dimmed page above, a rounded panel rising from the bottom edge, put
/// away by a tap on the dimmed part or a drag downwards. Arc Search's page menu is one of these
/// rather than a system sheet (it has no grabber and sits at one height).
final class SheetHost: UIView, UIGestureRecognizerDelegate {
    let panel = UIView()
    private let dim = UIControl()
    private let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemThickMaterial))
    private let content: UIView
    private let panelHeight: (CGFloat) -> CGFloat
    private var shown = false
    private var dragOffset: CGFloat = 0
    var onDismiss: (() -> Void)?

    /// `height` gets the bottom safe area and returns the panel's height.
    init(content: UIView, cornerRadius: CGFloat, height: @escaping (CGFloat) -> CGFloat) {
        self.content = content
        panelHeight = height
        super.init(frame: .zero)
        dim.backgroundColor = UIColor(white: 0, alpha: 0.21)
        dim.alpha = 0
        dim.addTarget(self, action: #selector(dismissTapped), for: .touchUpInside)
        dim.accessibilityIdentifier = "sheet-dim"
        addSubview(dim)
        panel.layer.cornerRadius = cornerRadius
        panel.layer.cornerCurve = .continuous
        panel.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        panel.clipsToBounds = true
        addSubview(panel)
        panel.addSubview(material)
        // Arc Search's sheets are lighter than the system's thick material: nearly white.
        let wash = UIView()
        wash.backgroundColor = Palette.dynamic(light: UIColor(white: 1, alpha: 0.45), dark: UIColor(white: 0, alpha: 0.2))
        wash.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        material.contentView.addSubview(wash)
        panel.addSubview(content)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
        pan.delegate = self
        panel.addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        dim.frame = bounds
        let height = panelHeight(safeAreaInsets.bottom)
        let top = shown ? bounds.height - height + dragOffset : bounds.height
        panel.frame = CGRect(x: 0, y: top, width: bounds.width, height: height)
        material.frame = panel.bounds
        content.frame = panel.bounds
        dim.alpha = shown ? max(0, 1 - dragOffset / max(1, height)) : 0
    }

    func present(in parent: UIView) {
        frame = parent.bounds
        autoresizingMask = [.flexibleWidth, .flexibleHeight]
        parent.addSubview(self)
        layoutIfNeeded()
        shown = true
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.88, initialSpringVelocity: 0,
                       options: [.allowUserInteraction]) {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }

    func dismiss(animated: Bool = true, then: (() -> Void)? = nil) {
        guard shown else { return }
        shown = false
        let finish = {
            self.removeFromSuperview()
            self.onDismiss?()
            then?()
        }
        guard animated else { return finish() }
        UIView.animate(withDuration: 0.26, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.setNeedsLayout()
            self.layoutIfNeeded()
        } completion: { _ in finish() }
    }

    @objc private func dismissTapped() { dismiss() }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        return velocity.y > abs(velocity.x)
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .changed:
            dragOffset = max(0, pan.translation(in: self).y)
            setNeedsLayout()
            layoutIfNeeded()
        case .ended, .cancelled:
            let away = pan.state == .ended && (dragOffset > panel.bounds.height * 0.3 || pan.velocity(in: self).y > 800)
            if away {
                dismiss()
            } else {
                UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: []) {
                    self.dragOffset = 0
                    self.setNeedsLayout()
                    self.layoutIfNeeded()
                }
            }
            if away { dragOffset = 0 }
        default: break
        }
    }
}
