import UIKit

/// What shows behind the search sheet when no page is open: Arc Search's soft gradient,
/// lavender from the top left with a pink bloom on the right.
final class BackdropView: UIView {
    private let base = CAGradientLayer()
    private let bloom = CAGradientLayer()
    /// Incognito drains the colour: Arc Search's backdrop turns a flat grey-lavender.
    var isIncognito = false { didSet { applyColors() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        base.startPoint = CGPoint(x: 0, y: 0)
        base.endPoint = CGPoint(x: 1, y: 1)
        bloom.type = .radial
        bloom.startPoint = CGPoint(x: 1.05, y: 0.52)
        bloom.endPoint = CGPoint(x: 0.25, y: 1.0)
        layer.addSublayer(base)
        layer.addSublayer(bloom)
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: BackdropView, _) in view.applyColors() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.frame = bounds
        bloom.frame = bounds
        CATransaction.commit()
    }

    private func applyColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isIncognito {
            base.colors = [Palette.rgb(0xb0aec5).cgColor, Palette.rgb(0xaaa8bd).cgColor]
            bloom.colors = [UIColor.clear.cgColor, UIColor.clear.cgColor]
        } else if dark {
            base.colors = [Palette.rgb(0x25233a).cgColor, Palette.rgb(0x1d1b2b).cgColor]
            bloom.colors = [Palette.rgb(0x4a2f44, alpha: 0.9).cgColor, Palette.rgb(0x4a2f44, alpha: 0).cgColor]
        } else {
            base.colors = [Palette.rgb(0xbdb9d3).cgColor, Palette.rgb(0xb9b3c7).cgColor]
            bloom.colors = [Palette.rgb(0xdcc8d0).cgColor, Palette.rgb(0xdcc8d0, alpha: 0).cgColor]
        }
        CATransaction.commit()
    }
}
