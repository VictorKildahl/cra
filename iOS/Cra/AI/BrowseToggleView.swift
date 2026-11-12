import CraCore
import UIKit

/// The floating switch on a Browse for Me page and on the search engine's results: Browse for Me
/// on the left, the engine on the right, laid out to `MobileBrowseToggle`. The side on screen is
/// filled: Browse for Me with its purple-to-pink gradient (TapSmart's screenshot), the engine with
/// a white pill (not seen in any picture; Cra's own).
final class BrowseToggleView: UIView {
    var onPick: ((MobileBrowseToggle.Side) -> Void)?

    private(set) var side: MobileBrowseToggle.Side = .browseForMe
    private let browseSegment = UIView()
    private let browseGradient = CAGradientLayer()
    private let engineSegment = UIView()
    private let browseButton = UIButton(type: .custom)
    private let engineButton = UIButton(type: .custom)
    private let browseGlyph = UIImageView()
    private let engineLetter = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Palette.dynamic(light: Palette.rgb(0xf7f7f8), dark: Palette.rgb(0x2c2c2e))
        layer.cornerCurve = .continuous
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: 3)
        accessibilityIdentifier = "browse-toggle"

        // Measured across the filled part: #583dae at its left end to #c3699d at its right.
        browseGradient.colors = [Palette.rgb(0x583dae).cgColor, Palette.rgb(0xc3699d).cgColor]
        browseGradient.startPoint = CGPoint(x: 0, y: 0.5)
        browseGradient.endPoint = CGPoint(x: 1, y: 0.5)
        browseSegment.layer.addSublayer(browseGradient)
        browseSegment.clipsToBounds = true
        browseSegment.isUserInteractionEnabled = false
        addSubview(browseSegment)

        engineSegment.backgroundColor = Palette.dynamic(light: .white, dark: Palette.rgb(0x48484a))
        engineSegment.layer.shadowColor = UIColor.black.cgColor
        engineSegment.layer.shadowOpacity = 0.1
        engineSegment.layer.shadowRadius = 3
        engineSegment.layer.shadowOffset = CGSize(width: 0, height: 1)
        engineSegment.isUserInteractionEnabled = false
        addSubview(engineSegment)

        browseGlyph.image = UIImage(systemName: "sparkles", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        browseGlyph.contentMode = .center
        browseGlyph.isUserInteractionEnabled = false
        addSubview(browseGlyph)
        engineLetter.font = UIFont.systemFont(ofSize: 22, weight: .bold).rounded
        engineLetter.textAlignment = .center
        engineLetter.isUserInteractionEnabled = false
        addSubview(engineLetter)

        browseButton.accessibilityLabel = "Browse for Me"
        browseButton.accessibilityIdentifier = "toggle-browse"
        browseButton.addTarget(self, action: #selector(browseTapped), for: .touchUpInside)
        engineButton.accessibilityIdentifier = "toggle-engine"
        engineButton.addTarget(self, action: #selector(engineTapped), for: .touchUpInside)
        addSubview(browseButton)
        addSubview(engineButton)
        apply()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(side: MobileBrowseToggle.Side, engine: MobileSearch) {
        self.side = side
        engineLetter.text = String(engine.label.prefix(1))
        engineButton.accessibilityLabel = engine.label
        apply()
    }

    private func apply() {
        let onBrowse = side == .browseForMe
        browseSegment.isHidden = !onBrowse
        engineSegment.isHidden = onBrowse
        browseGlyph.tintColor = onBrowse ? .white : Palette.rgb(0x6b42a9)
        // The engine's letter in Arc Search's grey (#7f7f7f) while Browse for Me is on.
        engineLetter.textColor = onBrowse ? Palette.rgb(0x7f7f7f) : Palette.primaryText
        browseButton.accessibilityTraits = onBrowse ? [.button, .selected] : .button
        engineButton.accessibilityTraits = onBrowse ? .button : [.button, .selected]
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).cgPath
        let left = MobileBrowseToggle.segmentFrame(for: .browseForMe)
        let right = MobileBrowseToggle.segmentFrame(for: .engine)
        browseSegment.frame = left
        browseSegment.layer.cornerRadius = left.height / 2
        browseGradient.frame = browseSegment.bounds
        engineSegment.frame = right
        engineSegment.layer.cornerRadius = right.height / 2
        browseGlyph.frame = left
        engineLetter.frame = right
        browseButton.frame = CGRect(x: 0, y: 0, width: bounds.width / 2, height: bounds.height)
        engineButton.frame = CGRect(x: bounds.width / 2, y: 0, width: bounds.width / 2, height: bounds.height)
    }

    @objc private func browseTapped() {
        guard side != .browseForMe else { return }
        onPick?(.browseForMe)
    }

    @objc private func engineTapped() {
        guard side != .engine else { return }
        onPick?(.engine)
    }
}

private extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
