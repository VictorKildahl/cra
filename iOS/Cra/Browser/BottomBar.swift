import CraCore
import UIKit

/// The bar under a page: the tab stack, the pill that opens search, and the menu button.
/// Frames come from `MobileBottomBar`; this view covers the whole screen width and is as tall
/// as the bar plus the bottom safe area.
final class BottomBar: UIView {
    let tabsButton = TabStackButton()
    let pill = BarButton(symbol: "plus", pointSize: 16, weight: .semibold)
    let menuButton = BarButton(symbol: "chevron.up", pointSize: 16, weight: .semibold)
    /// In the tab switcher the tab stack gives way to Spaces, and the menu to Settings.
    // Over the tab row (IMG_1896): the monitor 19 pt wide, the plus 16.3 pt, and the gear is
    // the spoked one, 18 pt across.
    let spacesButton = BarButton(symbol: "desktopcomputer", pointSize: 16, weight: .semibold)
    let settingsButton = BarButton(symbol: "gear", pointSize: 17, weight: .medium)

    enum Mode { case page, tabs }
    var mode: Mode = .page { didSet { applyMode() } }
    /// Over the empty home screen's dots: no slab, the buttons float as they do over the tab row.
    var overBackdrop = false {
        didSet { if overBackdrop != oldValue { applyMode() } }
    }
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterial))
    private let hairline = UIView()
    /// The white ring Arc Search draws round the menu button while its blocker tip points at it.
    private let menuRing = UIView()
    /// Whether the slab was last hidden for the tab row or the home screen, rather than faded by
    /// the search sheet: coming back from those, it has to appear whole.
    private var wasFloating = false
    var ringsMenu = false {
        didSet { applyFade() }
    }

    /// 1 with every control showing; 0 while the search sheet is open and only the pill's place
    /// is kept (the sheet's field stands in for it).
    var controlsVisibility: CGFloat = 1 {
        didSet {
            applyMode()
        }
    }

    /// 0 with the bar open, 1 with it closed away along the safe area. Its controls fade out with
    /// it and stop taking touches, so the strip it leaves is only the way back.
    var collapseProgress: CGFloat = 0 {
        didSet {
            guard collapseProgress != oldValue else { return }
            // Set on every frame of the bar's slide: only the fade changes.
            applyFade()
        }
    }

    /// 1 while the pill is the page's, 0 while the search sheet's field stands in for it.
    var pillVisibility: CGFloat = 1 {
        didSet { applyFade() }
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
        spacesButton.accessibilityIdentifier = "bar-spaces"
        spacesButton.accessibilityLabel = "Spaces"
        settingsButton.accessibilityIdentifier = "bar-settings"
        settingsButton.accessibilityLabel = "Settings"
        [tabsButton, spacesButton, pill, menuButton, settingsButton].forEach(addSubview)
        menuRing.isUserInteractionEnabled = false
        menuRing.layer.borderColor = UIColor.white.cgColor
        menuRing.layer.borderWidth = 3
        menuRing.alpha = 0
        menuRing.accessibilityIdentifier = "bar-menu-ring"
        addSubview(menuRing)
        applyMode()
    }

    /// The controls' opacity, faded as the bar slides away, and whether they take touches. The
    /// only part of the bar's look that its slide changes.
    private func applyFade() {
        let visible = controlsVisibility
        let fade = 1 - collapseProgress
        let tabs = mode == .tabs
        tabsButton.alpha = (tabs ? 0 : visible) * fade
        menuButton.alpha = (tabs ? 0 : visible) * fade
        spacesButton.alpha = (tabs ? visible : 0) * fade
        settingsButton.alpha = (tabs ? visible : 0) * fade
        // The pill has its own visibility: it is the search field's starting point, and the field
        // stands in for it while the sheet is open.
        pill.alpha = pillVisibility * fade
        menuRing.alpha = (ringsMenu ? 1 : 0) * fade
        // Faded or away, the controls take no touches: the strip along the safe area is the way
        // back, not a half-faded button.
        let live = visible > 0.01 && collapseProgress < 0.01
        // The slide sets this every frame; the controls only change at its ends.
        guard live != pill.isUserInteractionEnabled else { return }
        [tabsButton, spacesButton, pill, menuButton, settingsButton].forEach { $0.isUserInteractionEnabled = live }
    }

    /// Shows the page's controls or the tab switcher's, faded as the bar slides away. Animates
    /// inside an animation block.
    private func applyMode() {
        applyFade()
        let visible = controlsVisibility
        let tabs = mode == .tabs
        // Over the switcher the bar has no slab of its own: the buttons float on the backdrop,
        // tinted with its lavender (Arc Search: pill #dfddf2, circles #f0effd on #fcfafd). The
        // empty home screen's bar floats the same way. The blur goes with the bar, not the fade:
        // its strip is all that is left of the bar when it is closed.
        let floats = tabs || overBackdrop
        let slabAlpha = floats ? 0 : visible
        if wasFloating, !floats {
            // The slab comes back with the page, whole: animating its opacity up from the row's
            // no-slab state leaves the material see-through for the length of the close.
            blur.layer.removeAnimation(forKey: "opacity")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            blur.layer.opacity = Float(slabAlpha)
            CATransaction.commit()
        } else {
            blur.alpha = slabAlpha
        }
        wasFloating = floats
        pill.backgroundColor = tabs ? Palette.switcherPillFill : overBackdrop ? Palette.homeButtonFill : Palette.barControlFill
        menuButton.backgroundColor = overBackdrop ? Palette.homeButtonFill : Palette.barControlFill
        pill.setSymbol("plus", pointSize: tabs ? 20.5 : 16, weight: .semibold)
        pill.glyphTint = tabs ? Palette.switcherGlyph : Palette.glyph
        spacesButton.glyphTint = Palette.switcherGlyph
        settingsButton.glyphTint = Palette.switcherGlyph
        spacesButton.backgroundColor = Palette.switcherButtonFill
        settingsButton.backgroundColor = Palette.switcherButtonFill
        let small = CGAffineTransform(scaleX: 0.6, y: 0.6)
        tabsButton.transform = tabs ? small : .identity
        menuButton.transform = tabs ? small : .identity
        spacesButton.transform = tabs ? .identity : small
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
        let transforms = [tabsButton, menuButton, spacesButton, settingsButton].map(\.transform)
        [tabsButton, menuButton, spacesButton, settingsButton].forEach { $0.transform = .identity }
        tabsButton.frame = frames.tabs.insetBy(dx: -6, dy: -6)
        // By bounds and centre, which its scale leaves alone: the bar is laid out again during a press, and a frame set
        // while the pill was pressed in (BarButton) grew its bounds to make up for the scale, so it swelled back under
        // the finger and puffed up past its size on a tap.
        pill.bounds = CGRect(origin: .zero, size: frames.pill.size)
        pill.center = CGPoint(x: frames.pill.midX, y: frames.pill.midY)
        menuButton.frame = frames.menu
        // The switcher's round buttons are 33.5 pt (IMG_1896), a little smaller than the page's
        // menu button.
        spacesButton.frame = frames.tabs.insetBy(dx: 0.75, dy: 0.75)
        settingsButton.frame = frames.menu.insetBy(dx: 0.75, dy: 0.75)
        zip([tabsButton, menuButton, spacesButton, settingsButton], transforms).forEach { $0.transform = $1 }
        menuRing.frame = frames.menu.insetBy(dx: -4, dy: -4)
        menuRing.layer.cornerRadius = menuRing.bounds.width / 2
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

    var glyphTint: UIColor {
        get { glyph.tintColor }
        set { glyph.tintColor = newValue }
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
            PressHaptics.highlightChanged(for: self, from: oldValue, to: isHighlighted)
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
    private var frontImage: UIImage?
    private var showsFront = true
    /// A page card that flew into the button, standing in for the front card until a snapshot
    /// takes its place.
    private var keptFront: UIView?

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

    /// The tabs the button previews: the previous tab in front, the one behind it under.
    func setSnapshots(front: UIImage?, back: UIImage?) {
        frontImage = front
        self.back.image = back
        // A picture of its own takes the slot back from a card that landed there.
        if front != nil {
            keptFront?.removeFromSuperview()
            keptFront = nil
            self.front.isHidden = false
        }
        self.front.image = showsFront ? frontImage : nil
    }

    /// Keeps the page card that flew into the button as the front picture, until a snapshot
    /// takes its place. The card is already the size and shape of the slot.
    func keepFrontCard(_ card: UIView) {
        guard let holder = front.superview else { return }
        keptFront?.removeFromSuperview()
        card.transform = .identity
        card.frame = holder.bounds
        card.layer.cornerRadius = 5
        holder.addSubview(card)
        keptFront = card
        front.isHidden = true
    }

    /// While a flick up has the front card's tab in hand, its frame is hidden too: the tab is
    /// out of the button. It comes back when that tab returns to it.
    func setFrontEmpty(_ empty: Bool) {
        showsFront = !empty
        if empty {
            keptFront?.removeFromSuperview()
            keptFront = nil
            front.image = nil
        } else {
            front.image = frontImage
        }
        front.isHidden = empty
    }

    /// The card in front, unturned and in `view`'s coordinates: the previous tab, where a flick
    /// up starts and where the page left behind lands.
    func frontCard(in view: UIView) -> CGRect {
        guard let holder = front.superview else { return convert(bounds, to: view) }
        let center = convert(holder.center, to: view)
        return CGRect(x: center.x - holder.bounds.width / 2, y: center.y - holder.bounds.height / 2,
                      width: holder.bounds.width, height: holder.bounds.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Arc Search's stack, relative to the button's centre: a 26 pt card leaning left behind,
        // a 26.5 × 30 pt card leaning right in front, up and to the right of it.
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        for (card, size, offset, angle) in [(back, CGSize(width: 26, height: 26), CGPoint(x: 1, y: 5.5), -14 * CGFloat.pi / 180),
                                            (front, CGSize(width: 26.5, height: 30), CGPoint(x: 15.5, y: -4.5), MobileMotion.frontCardTilt)] {
            guard let holder = card.superview else { continue }
            holder.transform = .identity
            holder.bounds = CGRect(origin: .zero, size: size)
            holder.center = CGPoint(x: center.x + offset.x, y: center.y + offset.y)
            card.frame = holder.bounds
            holder.transform = CGAffineTransform(rotationAngle: angle)
        }
    }

    override var isHighlighted: Bool {
        didSet {
            PressHaptics.highlightChanged(for: self, from: oldValue, to: isHighlighted)
            alpha = isHighlighted ? 0.6 : 1
        }
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        bounds.insetBy(dx: -6, dy: -6).contains(point)
    }
}
