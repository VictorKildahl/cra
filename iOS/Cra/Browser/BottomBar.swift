import CraCore
import UIKit

/// The bar under a page: the tab stack, the pill that opens search, and the menu button.
/// Frames come from `MobileBottomBar`; this view covers the whole screen width and is as tall
/// as the bar plus the bottom safe area.
final class BottomBar: UIView {
    let tabsButton = TabStackButton()
    let pill = BarButton(symbol: "plus", pointSize: 16, weight: .semibold)
    let menuButton = BarButton(symbol: "chevron.up", pointSize: 16, weight: .semibold)
    /// In the tab switcher the tab stack gives way to the archive, and the menu to Settings.
    let archiveButton = BarButton(symbol: "archivebox", pointSize: 14, weight: .semibold)
    let settingsButton = BarButton(symbol: "gearshape", pointSize: 15, weight: .semibold)

    enum Mode { case page, tabs }
    var mode: Mode = .page { didSet { applyMode() } }
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let hairline = UIView()

    /// 1 with every control showing; 0 while the search sheet is open and only the pill's place
    /// is kept (the sheet's field stands in for it).
    var controlsVisibility: CGFloat = 1 {
        didSet {
            applyMode()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(blur)
        hairline.backgroundColor = Palette.dynamic(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.12))
        blur.contentView.addSubview(hairline)
        tabsButton.accessibilityIdentifier = "bar-tabs"
        tabsButton.accessibilityLabel = "Tabs"
        pill.accessibilityIdentifier = "bar-search"
        pill.accessibilityLabel = "New tab"
        menuButton.accessibilityIdentifier = "bar-menu"
        menuButton.accessibilityLabel = "Menu"
        archiveButton.accessibilityIdentifier = "bar-archive"
        archiveButton.accessibilityLabel = "Archived tabs"
        settingsButton.accessibilityIdentifier = "bar-settings"
        settingsButton.accessibilityLabel = "Settings"
        [tabsButton, archiveButton, pill, menuButton, settingsButton].forEach(addSubview)
        applyMode()
    }

    /// Shows the page's controls or the tab switcher's. Animates inside an animation block.
    private func applyMode() {
        let visible = controlsVisibility
        let tabs = mode == .tabs
        tabsButton.alpha = tabs ? 0 : visible
        menuButton.alpha = tabs ? 0 : visible
        archiveButton.alpha = tabs ? visible : 0
        settingsButton.alpha = tabs ? visible : 0
        // Over the switcher the bar has no slab of its own: the buttons float on the backdrop,
        // tinted with its lavender (Arc Search: pill #dfddf2, circles #f0effd on #fcfafd).
        blur.alpha = tabs ? 0 : visible
        pill.backgroundColor = tabs ? Palette.switcherPillFill : Palette.barControlFill
        archiveButton.backgroundColor = Palette.switcherButtonFill
        settingsButton.backgroundColor = Palette.switcherButtonFill
        let small = CGAffineTransform(scaleX: 0.6, y: 0.6)
        tabsButton.transform = tabs ? small : .identity
        menuButton.transform = tabs ? small : .identity
        archiveButton.transform = tabs ? .identity : small
        settingsButton.transform = tabs ? .identity : small
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The pill's frame in this view, for the search field to grow out of.
    var pillFrame: CGRect { pill.frame }

    override func layoutSubviews() {
        super.layoutSubviews()
        blur.frame = bounds
        hairline.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1 / UIScreen.main.scale)
        // The bar's frames are worked out for a view that ends at the screen's bottom edge.
        let frames = MobileBottomBar.frames(in: bounds.size, safeBottom: bounds.height - MobileBottomBar.height)
        let transforms = [tabsButton, menuButton, archiveButton, settingsButton].map(\.transform)
        [tabsButton, menuButton, archiveButton, settingsButton].forEach { $0.transform = .identity }
        tabsButton.frame = frames.tabs.insetBy(dx: -6, dy: -6)
        pill.frame = frames.pill
        menuButton.frame = frames.menu
        // The switcher's round buttons are 32 pt, a little smaller than the page's menu button.
        archiveButton.frame = frames.tabs.insetBy(dx: 1.5, dy: 1.5)
        settingsButton.frame = frames.menu.insetBy(dx: 1.5, dy: 1.5)
        zip([tabsButton, menuButton, archiveButton, settingsButton], transforms).forEach { $0.transform = $1 }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Leaves touches to the page while the bar is faded out for the search sheet.
        controlsVisibility > 0.01 && super.point(inside: point, with: event)
    }
}

/// A capsule or circle with one glyph: the pill and the menu button.
final class BarButton: UIControl {
    private let glyph = UIImageView()

    init(symbol: String, pointSize: CGFloat, weight: UIImage.SymbolWeight) {
        super.init(frame: .zero)
        backgroundColor = Palette.barControlFill
        layer.cornerCurve = .circular
        layer.borderWidth = 1 / UIScreen.main.scale
        glyph.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
        glyph.tintColor = Palette.glyph
        glyph.contentMode = .center
        addSubview(glyph)
        isAccessibilityElement = true
        accessibilityTraits = .button
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: BarButton, _) in view.applyColors() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setSymbol(_ symbol: String, pointSize: CGFloat, weight: UIImage.SymbolWeight) {
        glyph.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
    }

    var glyphAlpha: CGFloat {
        get { glyph.alpha }
        set { glyph.alpha = newValue }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        glyph.frame = bounds
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: isHighlighted ? 0.08 : 0.25, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.94, y: 0.94) : .identity
            }
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // A 32 pt circle with a 44 pt target.
        bounds.insetBy(dx: min(0, (bounds.width - 44) / 2), dy: min(0, (bounds.height - 44) / 2)).contains(point)
    }

    private func applyColors() {
        layer.borderColor = Palette.barControlBorder.resolvedColor(with: traitCollection).cgColor
    }
}

/// The tabs button: the last two tabs as small leaning cards, the newest in front. Empty grey
/// cards when there is nothing to show.
final class TabStackButton: UIControl {
    private let back = UIImageView()
    private let front = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        for card in [back, front] {
            card.backgroundColor = Palette.dynamic(light: Palette.rgb(0xd9d9dc), dark: Palette.rgb(0x48484c))
            card.contentMode = .scaleAspectFill
            card.clipsToBounds = true
            card.layer.cornerRadius = 5
            card.layer.cornerCurve = .continuous
            card.layer.borderWidth = 1 / UIScreen.main.scale
            card.layer.borderColor = UIColor(white: 0, alpha: 0.12).cgColor
            let holder = UIView()
            holder.isUserInteractionEnabled = false
            holder.layer.shadowColor = UIColor.black.cgColor
            holder.layer.shadowOpacity = 0.12
            holder.layer.shadowRadius = 2
            holder.layer.shadowOffset = CGSize(width: 0, height: 1)
            holder.addSubview(card)
            addSubview(holder)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The newest tab's picture in front, the one before it behind.
    func setSnapshots(front: UIImage?, back: UIImage?) {
        self.front.image = front
        self.back.image = back
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Arc Search's stack, relative to the button's centre: a 26 pt card leaning left behind,
        // a 26.5 × 30 pt card leaning right in front, up and to the right of it.
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (card, size, offset, degrees) in [(back, CGSize(width: 26, height: 26), CGPoint(x: 1, y: 5.5), CGFloat(-14)),
                                              (front, CGSize(width: 26.5, height: 30), CGPoint(x: 15.5, y: -4.5), 8)] {
            guard let holder = card.superview else { continue }
            holder.transform = .identity
            holder.bounds = CGRect(origin: .zero, size: size)
            holder.center = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
            card.frame = holder.bounds
            holder.transform = CGAffineTransform(rotationAngle: degrees * .pi / 180)
        }
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }
}
