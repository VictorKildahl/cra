import CraCore
import UIKit

/// Browse for Me at work, as Arc Search shows it: the query at the top, a vivid gradient that
/// rises from the bottom and sinks as the work gets done, "Reading N web pages" with the sites
/// one after another, then "Making a website for you".
final class BrowseLoadingView: UIView {
    private let gradient = CAGradientLayer()
    private let queryLabel = UILabel()
    private let readingLabel = UILabel()
    private var siteLabels: [UILabel] = []
    private let makingLabel = UILabel()
    private var gradientTop: CGFloat = 0.18
    /// The tab this is loading for, so it only shows over that tab.
    var tabID: UUID?

    private static func font(_ weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: 20, weight: weight)
        return base.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 20) } ?? base
    }

    init(query: String) {
        super.init(frame: .zero)
        backgroundColor = Palette.dynamic(light: .white, dark: Palette.rgb(0x16151c))
        // Arc Search's loader: white fading into violet, blue, purple, magenta and red.
        gradient.colors = [UIColor.white.withAlphaComponent(0).cgColor, Palette.rgb(0x6a5cf0).cgColor, Palette.rgb(0x2a12c8).cgColor,
                           Palette.rgb(0x8a1fc0).cgColor, Palette.rgb(0xe0187a).cgColor, Palette.rgb(0xff5a5f).cgColor]
        gradient.locations = [0, 0.14, 0.42, 0.66, 0.86, 1]
        layer.addSublayer(gradient)

        queryLabel.text = query
        queryLabel.font = Self.font(.medium)
        queryLabel.textColor = Palette.dynamic(light: Palette.rgb(0x4a2fd0), dark: Palette.rgb(0xa99cff))
        queryLabel.numberOfLines = 2
        queryLabel.accessibilityIdentifier = "browse-query"
        addSubview(queryLabel)

        readingLabel.font = Self.font(.semibold)
        readingLabel.textColor = Palette.dynamic(light: Palette.rgb(0x7a3fc0), dark: Palette.rgb(0xd0a8ff))
        readingLabel.alpha = 0
        readingLabel.accessibilityIdentifier = "browse-reading"
        addSubview(readingLabel)

        makingLabel.text = MobileBrowseForMe.makingLabel
        makingLabel.font = Self.font(.semibold)
        makingLabel.textColor = Palette.rgb(0xc0308f)
        makingLabel.alpha = 0
        makingLabel.accessibilityIdentifier = "browse-making"
        addSubview(makingLabel)

        let pulse = CABasicAnimation(keyPath: "locations")
        pulse.fromValue = gradient.locations
        pulse.toValue = [0, 0.2, 0.5, 0.72, 0.9, 1]
        pulse.duration = 1.6
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        gradient.add(pulse, forKey: "pulse")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width - 64
        // Measured from Arc Search on a 852 pt tall screen: query 107 pt down, the reading line
        // at 335 pt with a site every 32 pt, the making line at 600 pt.
        let scale = bounds.height / 852
        queryLabel.frame = CGRect(x: 32, y: 94 * scale, width: width, height: 56)
        queryLabel.sizeToFit()
        queryLabel.frame.size.width = width
        readingLabel.frame = CGRect(x: 32, y: 322 * scale, width: width, height: 26)
        for (index, label) in siteLabels.enumerated() {
            label.frame = CGRect(x: 32, y: 322 * scale + 32 * CGFloat(index + 1), width: width, height: 26)
        }
        makingLabel.frame = CGRect(x: 32, y: 587 * scale, width: width, height: 26)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = CGRect(x: 0, y: bounds.height * gradientTop, width: bounds.width, height: bounds.height * (1 - gradientTop) + 40)
        CATransaction.commit()
    }

    private func sink(to top: CGFloat) {
        gradientTop = top
        UIView.animate(withDuration: 0.9, delay: 0, options: [.curveEaseInOut]) {
            // Layers don't animate with UIView blocks; move the frame in a transaction of the same length.
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.9)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            self.gradient.frame = CGRect(x: 0, y: self.bounds.height * top, width: self.bounds.width, height: self.bounds.height * (1 - top) + 40)
            CATransaction.commit()
        }
    }

    /// "Reading N web pages", then each site a moment after the one before.
    func showReading(_ sites: [String]) {
        readingLabel.text = MobileBrowseForMe.readingLabel(sites.count)
        siteLabels.forEach { $0.removeFromSuperview() }
        siteLabels = sites.map { site in
            let label = UILabel()
            label.text = site
            label.font = Self.font(.medium)
            label.textColor = Palette.dynamic(light: Palette.rgb(0xc9b6ee), dark: Palette.rgb(0x8a78c8))
            label.alpha = 0
            addSubview(label)
            return label
        }
        setNeedsLayout()
        layoutIfNeeded()
        UIView.animate(withDuration: 0.35) { self.readingLabel.alpha = 1 }
        for (index, label) in siteLabels.enumerated() {
            UIView.animate(withDuration: 0.3, delay: 0.12 + 0.11 * Double(index), options: []) { label.alpha = 1 }
        }
        sink(to: 0.6)
    }

    func showMaking() {
        UIView.animate(withDuration: 0.35) { self.makingLabel.alpha = 1 }
        sink(to: 0.76)
    }
}
