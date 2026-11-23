import CraCore
import UIKit

/// What shows when no page is open, behind the search sheet. Arc Search's soft gradient by default, lavender from the
/// top left with a pink bloom on the right. With Rippling Dots on (`MobileEmptyHome`, PR #708) it lies under the dots
/// (`DotFieldView`): near-black with soft warm patches, as in the reference recording of 23 November 2026, where the
/// screen runs from #101010 to #272727 at the patches; light mode mirrors it.
final class BackdropView: UIView {
    private let base = CAGradientLayer()
    /// Arc Search's bloom.
    private let bloom = CAGradientLayer()
    /// The dots' patches: a tall one high on the right, one low on the left, one along the bottom.
    private let patches = [CAGradientLayer(), CAGradientLayer(), CAGradientLayer()]
    /// Where each patch is centred and how far it reaches, as fractions of the screen.
    private let placements: [(center: CGPoint, reach: CGSize)] = [
        (CGPoint(x: 0.66, y: 0.24), CGSize(width: 0.34, height: 0.2)),
        (CGPoint(x: 0.2, y: 0.66), CGSize(width: 0.36, height: 0.13)),
        (CGPoint(x: 0.48, y: 0.93), CGSize(width: 0.5, height: 0.12)),
    ]
    /// Incognito drains the colour: Arc Search's backdrop turns a flat grey-lavender.
    var isIncognito = false { didSet { if isIncognito != oldValue { applyColors() } } }
    /// Which backdrop: Arc Search's, or the dots' (App Settings ▸ Rippling Dots).
    var style: MobileEmptyHome.Backdrop = .arcSearch { didSet { if style != oldValue { applyColors() } } }

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
        for (patch, placement) in zip(patches, placements) {
            patch.type = .radial
            patch.startPoint = placement.center
            patch.endPoint = CGPoint(x: placement.center.x + placement.reach.width, y: placement.center.y + placement.reach.height)
            layer.addSublayer(patch)
        }
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
        patches.forEach { $0.frame = bounds }
        CATransaction.commit()
    }

    private func applyColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var bloomColor: UIColor = .clear, patch: UIColor = .clear
        if isIncognito {
            base.colors = [Palette.rgb(0xb0aec5).cgColor, Palette.rgb(0xaaa8bd).cgColor]
        } else if style == .dots {
            base.colors = dark ? [Palette.rgb(0x101010).cgColor, Palette.rgb(0x141313).cgColor]
                : [Palette.rgb(0xf5f4f2).cgColor, Palette.rgb(0xf0eeeb).cgColor]
            patch = dark ? Palette.rgb(0x2a2624) : Palette.rgb(0xebe7e3)
        } else if dark {
            base.colors = [Palette.rgb(0x25233a).cgColor, Palette.rgb(0x1d1b2b).cgColor]
            bloomColor = Palette.rgb(0x4a2f44, alpha: 0.9)
        } else {
            base.colors = [Palette.rgb(0xbdb9d3).cgColor, Palette.rgb(0xb9b3c7).cgColor]
            bloomColor = Palette.rgb(0xdcc8d0)
        }
        bloom.colors = [bloomColor.cgColor, bloomColor.withAlphaComponent(0).cgColor]
        for layer in patches {
            layer.colors = [patch.cgColor, patch.withAlphaComponent(0).cgColor]
        }
        CATransaction.commit()
    }
}
