import CraCore
import UIKit

/// What shows when no page is open, behind the search sheet, under the dots (`DotFieldView`, `MobileEmptyHome`,
/// PR #708): near-black with soft warm patches, as in the reference recording of 23 November 2026, where the screen
/// runs from #101010 to #272727 at the patches; light mode mirrors it. (Arc Search's lavender gradient with its pink
/// bloom was the default until 25 Nov 2026, when Victor made the dots the only look.)
final class BackdropView: UIView {
    private let base = CAGradientLayer()
    /// The dots' patches: a tall one high on the right, one low on the left, one along the bottom.
    private let patches = [CAGradientLayer(), CAGradientLayer(), CAGradientLayer()]
    /// Where each patch is centred and how far it reaches, as fractions of the screen.
    private let placements: [(center: CGPoint, reach: CGSize)] = [
        (CGPoint(x: 0.66, y: 0.24), CGSize(width: 0.34, height: 0.2)),
        (CGPoint(x: 0.2, y: 0.66), CGSize(width: 0.36, height: 0.13)),
        (CGPoint(x: 0.48, y: 0.93), CGSize(width: 0.5, height: 0.12)),
    ]
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        base.startPoint = CGPoint(x: 0, y: 0)
        base.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(base)
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
        patches.forEach { $0.frame = bounds }
        CATransaction.commit()
    }

    private func applyColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        base.colors = dark ? [Palette.rgb(0x101010).cgColor, Palette.rgb(0x141313).cgColor]
            : [Palette.rgb(0xf5f4f2).cgColor, Palette.rgb(0xf0eeeb).cgColor]
        let patch: UIColor = dark ? Palette.rgb(0x2a2624) : Palette.rgb(0xebe7e3)
        for layer in patches {
            layer.colors = [patch.cgColor, patch.withAlphaComponent(0).cgColor]
        }
        CATransaction.commit()
    }
}
