import CraCore
import UIKit

/// The bar under a page: the tab stack, the pill that opens search, and the menu button.
/// Frames come from `MobileBottomBar`; this view covers the whole screen width and is as tall
/// as the bar plus the bottom safe area.
final class BottomBar: UIView {
    let tabsButton = TabStackButton()
    /// The plus keeps one size in the page's bar and the tab row's: only the row's Spaces and
    /// Settings shrink, so the new tab button does not grow as the row opens.
    let pill = BarButton(symbol: "plus", pointSize: 20, weight: .semibold)
    let menuButton = BarButton(symbol: "chevron.up", pointSize: 16, weight: .semibold)
    /// In the tab switcher the tab stack gives way to Spaces, and the menu to Settings.
    // Over the tab row (IMG_1896): the monitor 19 pt wide, the plus 16.3 pt (drawn 4 pt larger
    // since), and the gear is the spoked one, 18 pt across.
    let spacesButton = BarButton(symbol: "desktopcomputer", pointSize: 16, weight: .semibold)
    let settingsButton = BarButton(symbol: "gear", pointSize: 17, weight: .medium)

    enum Mode { case page, tabs }
    var mode: Mode = .page { didSet { if mode != oldValue { applyMode() } } }
    /// Over the empty home screen's dots: no slab, the buttons float as they do over the tab row.
    var overBackdrop = false {
        didSet { if overBackdrop != oldValue { applyMode() } }
    }
    /// The bar's material (`MobileBottomBar.material`). Its hairline and incognito's black lie in
    /// it, so they take its frame, its rounded top and its opacity: where the bar has no slab (the
    /// home, the tab row), neither do they.
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterial))
    private var material = MobileBottomBar.Material.page
    private let hairline = UIView()
    /// Near-black over the material in incognito, as no material is that dark.
    private let incognitoTint = UIView()
    /// The drawer's hairline edge, a shade lighter than its fill.
    private let drawerEdge = UIView()
    /// The white ring Arc Search draws round the menu button while its blocker tip points at it.
    private let menuRing = UIView()
    /// Whether the slab was last hidden for the tab row or the home screen, rather than faded by
    /// the search sheet: coming back from those, it has to appear whole.
    private var wasFloating = false
    var ringsMenu = false {
        didSet { applyFade() }
    }

    /// How far the new tab drawer's top edge has risen above the bar, in points. The tabs and menu
    /// buttons ride that edge and leave; the material and its colour carry it up too.
    var drawerRise: CGFloat = 0 {
        didSet {
            guard drawerRise != oldValue else { return }
            setNeedsLayout()
            applyFade()
        }
    }

    /// 1 with the drawer's material and edge in, 0 with the bar's own.
    var drawerAppearance: CGFloat = 0 {
        didSet { if drawerAppearance != oldValue { applyDrawer() } }
    }

    /// 0 at the bar, 1 with the drawer fully open. Its top corners reach the sheet's radius only at 1.
    var drawerOpenness: CGFloat = 0 {
        didSet {
            guard drawerOpenness != oldValue else { return }
            setNeedsLayout()
            // Set inside the close's own animation, so a let-go drawer's material goes down with it.
            if drawerLetGo { blur.alpha = slabAlpha }
        }
    }

    /// The drawer has been let go and is on its way back into the bar: over the home or the tab
    /// row it takes the bar's material down with it (`MobileNewTabDrawer.materialOpacity`).
    var drawerLetGo = false {
        didSet { if drawerLetGo != oldValue { applyDrawer() } }
    }

    /// The drawer is on screen, from the first touch until it has sunk back. The bar's own hairline
    /// stays hidden the whole time: the material's top edge is the drawer's, not the bar's.
    var drawerActive = false {
        didSet {
            guard drawerActive != oldValue else { return }
            applyFade()
            // Gone, the drawer hands the material back to the bar. A let-go drawer has already taken
            // it down over the home or the tab row; this only catches a close that never let go.
            guard !drawerActive else { return }
            UIView.animate(withDuration: MobileNewTabDrawer.materialFade, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.blur.alpha = self.slabAlpha
            }
        }
    }

    /// The bar carries an incognito tab or search: the whole bar is dark, drawer or not.
    var isIncognito = false {
        didSet {
            guard isIncognito != oldValue else { return }
            overrideUserInterfaceStyle = isIncognito ? .dark : .unspecified
            applyDrawer()
            applyPageChrome()
            applyIncognitoTint()
        }
    }

    /// Swaps the material only when the bar's state calls for another one. Inside an animation
    /// block the swap crossfades.
    private func applyMaterial() {
        let wanted = MobileBottomBar.material(drawerShowing: drawerAppearance > 0, pageIsLight: pageIsLight,
                                              incognito: isIncognito)
        guard wanted != material else { return }
        material = wanted
        blur.effect = UIBlurEffect(style: wanted.style)
    }

    /// For the new tab drawer's UI test: the bar material's own opacity behind the drawer.
    var materialAlpha: CGFloat { blur.alpha }

    /// Whether the page's status bar text is dark, meaning a light page: the bar takes a light
    /// material then, crossfaded so switching tabs is smooth.
    var pageIsLight = false {
        didSet {
            guard pageIsLight != oldValue else { return }
            UIView.animate(withDuration: MobileBottomBar.materialFade, delay: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
                self.applyMaterial()
            }
            applyPageChrome()
        }
    }

    /// The material's own visibility: the bar's slab, or the drawer's while it is out.
    private var slabAlpha: CGFloat {
        let floats = mode == .tabs || overBackdrop
        guard drawerActive else { return floats ? 0 : controlsVisibility }
        return MobileNewTabDrawer.materialOpacity(floats: floats, letGo: drawerLetGo, openness: drawerOpenness)
    }

    /// 1 with every control showing; 0 while the search sheet is open and only the pill's place
    /// is kept (the sheet's field stands in for it).
    var controlsVisibility: CGFloat = 1 {
        didSet { if controlsVisibility != oldValue { applyMode() } }
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
        didSet {
            if pillVisibility <= 0.001 { pillRevealing = false }
            applyFade()
        }
    }

    /// The pill is fading in as the sheet leaves; `applyFade` must leave its alpha to that animation.
    private var pillRevealing = false

    /// Fades the plus back in as the address field closes, instead of letting it appear at full once
    /// the sheet is gone.
    func revealPill(over duration: TimeInterval) {
        pillRevealing = true
        pillVisibility = 1
        pill.alpha = 0
        UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.pill.alpha = 1
        } completion: { _ in
            self.pillRevealing = false
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(blur)
        // The material rounds its top corners as the drawer rises; the strip along the bottom
        // stays square, as the bar always has.
        configureDrawerSurface(blur)
        hairline.backgroundColor = Palette.dynamic(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.12))
        // The bar's hairline, then incognito's black over it, inside the material.
        incognitoTint.backgroundColor = Palette.incognitoBar
        incognitoTint.alpha = 0
        incognitoTint.frame = blur.contentView.bounds
        incognitoTint.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        [hairline, incognitoTint].forEach(blur.contentView.addSubview)
        // The drawer's own hairline: white over the fill, so it reads a shade lighter than it in
        // either appearance.
        drawerEdge.isUserInteractionEnabled = false
        drawerEdge.backgroundColor = .clear
        drawerEdge.alpha = 0
        drawerEdge.layer.borderWidth = 0.5
        drawerEdge.layer.borderColor = Palette.raisedHairline.cgColor
        addSubview(drawerEdge)
        configureDrawerSurface(drawerEdge)
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
        // The buttons keep one centre; the right side button's glyph reads a point high in its
        // circle, and its blocker ring stays on the button.
        menuButton.glyphRise = 1
        settingsButton.glyphRise = 1
        spacesButton.chrome = .switcherRound
        settingsButton.chrome = .switcherRound
        [tabsButton, spacesButton, pill, menuButton, settingsButton].forEach(addSubview)
        menuRing.isUserInteractionEnabled = false
        menuRing.layer.borderColor = UIColor.white.cgColor
        menuRing.layer.borderWidth = 3
        menuRing.alpha = 0
        menuRing.accessibilityIdentifier = "bar-menu-ring"
        addSubview(menuRing)
        applyMode()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (bar: BottomBar, _) in
            bar.applyPageChrome()
        }
    }

    /// The controls' opacity, faded as the bar slides away, and whether they take touches. The
    /// only part of the bar's look that its slide changes.
    private func applyFade() {
        let visible = controlsVisibility
        let fade = 1 - collapseProgress
        // The drawer's own fade is the whole story while it is out; `visible` covers the address
        // editor, where the sheet is not the bar and the bar's controls still leave with it.
        let sideVisible = drawerActive ? MobileNewTabDrawer.controlsOpacity(reach: drawerRise) : visible
        let tabs = mode == .tabs
        tabsButton.alpha = (tabs ? 0 : sideVisible) * fade
        menuButton.alpha = (tabs ? 0 : sideVisible) * fade
        spacesButton.alpha = (tabs ? sideVisible : 0) * fade
        settingsButton.alpha = (tabs ? sideVisible : 0) * fade
        // The pill has its own visibility: it is the search field's starting point, and the field
        // stands in for it while the sheet is open. While it fades back in, leave the animation to it.
        if !pillRevealing { pill.alpha = pillVisibility * fade }
        menuRing.alpha = (ringsMenu ? 1 : 0) * fade * (drawerActive ? sideVisible : 1)
        // The hairline belongs to the bar's own slab: under the drawer there is no edge to draw.
        hairline.alpha = drawerActive ? 0 : 1
        // Faded or away, the controls take no touches: the strip along the safe area is the way
        // back, not a half-faded button. The side buttons also let go as soon as the drawer starts
        // to rise: they are on their way out, and the drag owns the finger.
        let live = visible > 0.01 && collapseProgress < 0.01
        let sideLive = live && drawerRise <= 0.01
        [tabsButton, menuButton, spacesButton, settingsButton].forEach { $0.isUserInteractionEnabled = sideLive }
        pill.isUserInteractionEnabled = live
    }

    /// The drawer's material and edge once it shows. Over the home or the switcher the bar has no
    /// slab of its own; the drawer brings the material back with it.
    private func applyDrawer() {
        applyMaterial()
        drawerEdge.alpha = drawerAppearance
        blur.alpha = slabAlpha
        setNeedsLayout()
    }

    /// Incognito's black fades in and out over the material.
    private func applyIncognitoTint() {
        let alpha: CGFloat = isIncognito ? 1 : 0
        UIView.animate(withDuration: MobileSearchMotion.incognitoCloseFade, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            self.incognitoTint.alpha = alpha
        }
    }

    /// The pill's ink and glass follow the page's bar: dark grey over a light page, the app's own
    /// pair over a dark one; incognito's dark bar takes the latter too.
    private func applyPageChrome() {
        let tabs = mode == .tabs
        // The bar's own pill and menu button keep the bar's chrome while they ride the drawer out;
        // the sheet's plus is the one that turns with the drawer's colour.
        let light = MobileBottomBar.lightChrome(darkMode: traitCollection.userInterfaceStyle == .dark,
                                                pageIsLight: pageIsLight, incognito: isIncognito,
                                                floats: tabs || overBackdrop, overDrawer: false)
        let onBar: BarButton.Chrome = overBackdrop ? .home : light ? .lightBar : .bar
        pill.chrome = tabs ? .switcherPill : onBar
        // The menu button sits on the same bar and follows it.
        menuButton.chrome = onBar
    }

    /// Shows the page's controls or the tab switcher's, faded as the bar slides away. Animates
    /// inside an animation block.
    private func applyMode() {
        applyFade()
        let tabs = mode == .tabs
        // Over the switcher the bar has no slab of its own: the buttons float on the backdrop,
        // tinted with its lavender (Arc Search: pill #dfddf2, circles #f0effd on #fcfafd). The
        // empty home screen's bar floats the same way. The blur goes with the bar, not the fade:
        // its strip is all that is left of the bar when it is closed.
        let floats = tabs || overBackdrop
        // The drawer brings the bar's material with it and keeps it for as long as it is out, even
        // over the home's dots or the switcher, and while its colour fades back on the way down.
        let slabAlpha = self.slabAlpha
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
        applyPageChrome()
        let small = CGAffineTransform(scaleX: 0.6, y: 0.6)
        tabsButton.transform = tabs ? small : .identity
        menuButton.transform = tabs ? small : .identity
        spacesButton.transform = tabs ? .identity : small
        settingsButton.transform = tabs ? .identity : small
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The pill's frame in this view, for the search field to grow out of.
    var pillFrame: CGRect { pill.frame }

    /// The layers that carry the bar and its drawer: they all reach the drawer's top edge and
    /// round its two top corners with it, leaving the bottom strip square.
    private func configureDrawerSurface(_ surface: UIView) {
        surface.clipsToBounds = true
        surface.layer.cornerCurve = .continuous
        surface.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The bar's material and colour reach as far up as the new tab drawer has. The strip at
        // the screen's bottom stays where it was; only the top edge moves.
        let rise = max(0, drawerRise)
        let radius = MobileNewTabDrawer.cornerRadius(openness: drawerOpenness)
        let drawer = CGRect(x: 0, y: -rise, width: bounds.width, height: bounds.height + rise)
        for surface in [blur, drawerEdge] as [UIView] {
            surface.frame = drawer
            surface.layer.cornerRadius = radius
        }
        // The hairline stays on the bar's own top edge, not the drawer's, and fades out under the
        // drawer's colour.
        hairline.frame = CGRect(x: 0, y: rise, width: bounds.width, height: 1 / UIScreen.main.scale)
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
        // The tabs and menu buttons ride the drawer's top edge, keeping their inset from it; the
        // new tab pill is drawn by the sheet at the same edge, so the three stay in line.
        [tabsButton, menuButton, spacesButton, settingsButton].forEach { $0.center.y -= rise }
        menuRing.frame = frames.menu.insetBy(dx: -4, dy: -4).offsetBy(dx: 0, dy: -rise)
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
        layer.cornerCurve = .circular
        layer.borderWidth = 1 / UIScreen.main.scale
        glyph.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: pointSize, weight: weight))
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

    /// What the button sits on, which sets its glass, glyph ink and rim.
    enum Chrome: Equatable {
        /// The page's bar.
        case bar
        /// A light page's bar: dark grey ink and rim on a darker glass.
        case lightBar
        /// Floating over the empty home's dots.
        case home
        /// The tab row's pill and round buttons, tinted with its backdrop's lavender.
        case switcherPill, switcherRound
    }

    var chrome: Chrome = .bar {
        didSet { if chrome != oldValue { applyColors() } }
    }

    var glyphAlpha: CGFloat {
        get { glyph.alpha }
        set { glyph.alpha = newValue }
    }

    /// The glyph's own lift inside the button, leaving the button and its ring where they are.
    var glyphRise: CGFloat = 0 { didSet { if glyphRise != oldValue { setNeedsLayout() } } }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
        glyph.frame = bounds.offsetBy(dx: 0, dy: -glyphRise)
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
        let fill: UIColor, ink: UIColor, rim: UIColor
        switch chrome {
        case .bar: (fill, ink, rim) = (Palette.barControlFill, Palette.glyph, Palette.barControlBorder)
        case .lightBar: (fill, ink, rim) = (Palette.lightBarControlFill, Palette.lightBarGlyph, Palette.lightBarBorder)
        case .home: (fill, ink, rim) = (Palette.homeButtonFill, Palette.glyph, Palette.barControlBorder)
        case .switcherPill: (fill, ink, rim) = (Palette.switcherPillFill, Palette.switcherGlyph, Palette.barControlBorder)
        case .switcherRound: (fill, ink, rim) = (Palette.switcherButtonFill, Palette.switcherGlyph, Palette.barControlBorder)
        }
        backgroundColor = fill
        glyph.tintColor = ink
        layer.borderColor = rim.resolvedColor(with: traitCollection).cgColor
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

private extension MobileBottomBar.Material {
    var style: UIBlurEffect.Style {
        switch self {
        case .page: .systemUltraThinMaterial
        case .lightPage: .systemThickMaterialLight
        case .drawer: .systemThinMaterial
        }
    }
}
