import UIKit

/// Voice search on screen, as Arc Search draws it: the page dimmed and blurred, a glow of blue,
/// purple and pink rising from the bottom, a white smiley, "Hi! How can I help?" until words
/// arrive, then the words in a capsule, and a row of dots that moves with the voice.
final class VoiceOverlayView: UIView {
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let glow = CAGradientLayer()
    private let face = CAShapeLayer()
    private let greeting = UILabel()
    private let caption = PaddedLabel()
    private var dots: [CALayer] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(blur)
        glow.colors = [UIColor.clear.cgColor, Palette.rgb(0x3a2bd8, alpha: 0.75).cgColor, Palette.rgb(0x9a2bd0, alpha: 0.85).cgColor, Palette.rgb(0xff4f8b, alpha: 0.9).cgColor]
        glow.locations = [0, 0.4, 0.72, 1]
        layer.addSublayer(glow)

        face.strokeColor = UIColor.white.cgColor
        face.fillColor = UIColor.clear.cgColor
        face.lineWidth = 9
        face.lineCap = .round
        layer.addSublayer(face)

        greeting.text = "Hi! How can I help?"
        greeting.font = .systemFont(ofSize: 22, weight: .semibold)
        greeting.textColor = .white
        greeting.textAlignment = .center
        greeting.accessibilityIdentifier = "voice-greeting"
        addSubview(greeting)

        caption.font = .systemFont(ofSize: 20, weight: .medium)
        caption.textColor = .white
        caption.numberOfLines = 3
        caption.textAlignment = .center
        caption.backgroundColor = UIColor(white: 1, alpha: 0.16)
        caption.layer.cornerRadius = 22
        caption.layer.cornerCurve = .continuous
        caption.clipsToBounds = true
        caption.alpha = 0
        caption.accessibilityIdentifier = "voice-caption"
        addSubview(caption)

        for _ in 0..<21 {
            let dot = CALayer()
            dot.backgroundColor = UIColor(white: 1, alpha: 0.85).cgColor
            dot.cornerRadius = 2.5
            layer.addSublayer(dot)
            dots.append(dot)
        }
        accessibilityIdentifier = "voice-overlay"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = CGRect(x: 0, y: bounds.height * 0.42, width: bounds.width, height: bounds.height * 0.58)
        // The smiley: two upright bars for eyes over a curved mouth.
        let centre = CGPoint(x: bounds.midX, y: bounds.height * 0.36)
        let path = UIBezierPath()
        for x in [centre.x - 17, centre.x + 17] {
            path.move(to: CGPoint(x: x, y: centre.y - 26))
            path.addLine(to: CGPoint(x: x, y: centre.y - 4))
        }
        path.move(to: CGPoint(x: centre.x - 34, y: centre.y + 16))
        path.addQuadCurve(to: CGPoint(x: centre.x + 34, y: centre.y + 16), controlPoint: CGPoint(x: centre.x, y: centre.y + 46))
        face.path = path.cgPath
        face.frame = bounds
        layoutDots(level: 0)
        CATransaction.commit()
        greeting.frame = CGRect(x: 24, y: centre.y + 64, width: bounds.width - 48, height: 30)
        let size = caption.sizeThatFits(CGSize(width: bounds.width - 64, height: 200))
        caption.frame = CGRect(x: (bounds.width - size.width) / 2, y: centre.y + 58, width: size.width, height: size.height)
    }

    private func layoutDots(level: Float) {
        let spacing: CGFloat = 11, y = bounds.height * 0.82
        let start = bounds.midX - spacing * CGFloat(dots.count - 1) / 2
        for (index, dot) in dots.enumerated() {
            // Taller towards the middle, and with the voice.
            let middle = 1 - abs(CGFloat(index) - CGFloat(dots.count - 1) / 2) / (CGFloat(dots.count) / 2)
            let wobble = CGFloat((index * 37 % 11)) / 11
            let height = 5 + CGFloat(level) * 46 * middle * (0.55 + 0.45 * wobble)
            dot.frame = CGRect(x: start + CGFloat(index) * spacing - 2.5, y: y - height / 2, width: 5, height: height)
        }
    }

    func setLevel(_ level: Float) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.08)
        layoutDots(level: level)
        CATransaction.commit()
    }

    func setTranscript(_ text: String) {
        caption.text = text
        setNeedsLayout()
        UIView.animate(withDuration: 0.2) {
            self.caption.alpha = text.isEmpty ? 0 : 1
            self.greeting.alpha = text.isEmpty ? 1 : 0
            self.layoutIfNeeded()
        }
    }

    func setMessage(_ text: String) {
        greeting.text = text
        greeting.alpha = 1
        caption.alpha = 0
    }

    /// Comes in the way Arc Search's does: scaling up and fading in with a little bounce.
    func appear() {
        alpha = 0
        transform = CGAffineTransform(scaleX: 1.08, y: 1.08)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0, options: []) {
            self.alpha = 1
            self.transform = .identity
        }
    }

    func disappear() {
        UIView.animate(withDuration: 0.22) { self.alpha = 0 } completion: { _ in self.removeFromSuperview() }
    }
}

private final class PaddedLabel: UILabel {
    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.insetBy(dx: 18, dy: 10))
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let inner = super.sizeThatFits(CGSize(width: size.width - 36, height: size.height - 20))
        return CGSize(width: inner.width + 36, height: inner.height + 20)
    }
}
