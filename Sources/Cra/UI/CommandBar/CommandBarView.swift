import AppKit
import SwiftUI

/// Arc's command bar: a wide translucent panel, input row with the top match's favicon,
/// single-line rows "Title — url", the selected row tinted with the space color, "Switch to
/// Tab" + arrow for open tabs. AppKit: the rows are reused views that change only what changed,
/// so a keystroke costs the search and a few labels, not a SwiftUI pass over the bar.
@MainActor
final class CommandBarView: NSView {
    static let rowHeight: CGFloat = 46
    static let fieldHeight: CGFloat = 64
    static func height(forRows n: Int) -> CGFloat { fieldHeight + (n == 0 ? 0 : CGFloat(n) * rowHeight + CGFloat(n - 1) * 4 + 18) }

    private let controller: CommandBarController
    private let favicons: FaviconCache
    private let material = NSVisualEffectView()
    private let tint = NSView()
    private let border = CAShapeLayer()
    private let shape = CAShapeLayer()
    private let leadingIcon = NSImageView()
    private let text: CommandTextField
    /// Arc's (i) at the field's end: it opens the search-suggestions notice (#314).
    private let info = CommandBarBadge()
    /// Arc's SearchSuggestionsPrivacyView, in the bottom row's place.
    private let notice = SearchSuggestionsBannerView()
    /// Scoped search: the scope's pill before the field, and "Search YouTube  Tab" at the end of
    /// the row while the typed text would enter it (Arc 1.170, measured at 2x).
    private let pill = NSView()
    private let pillLabel = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let hint = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let keycap = NSView()
    private let keycapLabel = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let divider = NSView()
    private var rows: [CommandBarRowView] = []
    private var syncQueued = false
    private var attached = false
    /// The card ⌥⌘N opens (#337): the bar is the whole Little Window, with a ✕ at the field's end.
    var card: CommandBarCard? { didSet { scheduleSync(); needsLayout = true } }
    /// The card's ✕: closes the bar, and with it the card.
    private let closeTile = CommandBarBadge()
    /// The scope shown last, to bounce when Tab enters one or Backspace leaves it.
    private var shownScope: CommandBarScope?
    private var splash: NSPanel?
    private var innerSplash: NSView?

    init(controller: CommandBarController, favicons: FaviconCache) {
        self.controller = controller
        self.favicons = favicons
        text = CommandTextField(controller: controller)
        super.init(frame: .zero)
        wantsLayer = true
        material.blendingMode = .behindWindow
        material.state = .active
        tint.wantsLayer = true
        layer?.mask = shape
        border.fillColor = nil
        border.lineWidth = 1
        leadingIcon.imageScaling = .scaleProportionallyUpOrDown
        leadingIcon.wantsLayer = true
        leadingIcon.layer?.cornerCurve = .continuous
        info.image = SidebarSymbols.image("info.circle", size: 15, weight: .medium)
        info.wantsLayer = true
        info.layer?.cornerRadius = 12
        info.imageScaling = .scaleNone
        info.contentTintColor = .secondaryLabelColor
        info.onPress = { [weak controller] in controller?.showNotice() }
        closeTile.image = SidebarSymbols.image("xmark", size: 11, weight: .semibold)
        closeTile.label = "Close"
        closeTile.wantsLayer = true
        closeTile.layer?.cornerRadius = LittleCard.closeRadius
        closeTile.layer?.cornerCurve = .continuous
        closeTile.imageScaling = .scaleNone
        closeTile.isHidden = true
        closeTile.onPress = { [weak controller] in controller?.close() }
        notice.onSettings = { [weak controller] in controller?.openNoticeSettings() }
        notice.onDismiss = { [weak controller] in controller?.dismissNotice() }
        notice.onLearnMore = { [weak controller] in controller?.openNoticeLearnMore() }
        divider.wantsLayer = true
        pill.wantsLayer = true
        pill.layer?.cornerCurve = .continuous
        pill.layer?.shadowOpacity = 0.3
        pill.layer?.shadowRadius = 8
        pill.layer?.shadowOffset = .zero
        pillLabel.textColor = .white
        pill.addSubview(pillLabel)
        keycap.wantsLayer = true
        keycap.layer?.cornerRadius = 6
        keycap.layer?.cornerCurve = .continuous
        keycapLabel.stringValue = "Tab"
        keycap.addSubview(keycapLabel)
        for v in [material, tint, leadingIcon, text.field, info, closeTile, pill, hint, keycap, divider, notice] as [NSView] { addSubview(v) }
        layer?.addSublayer(border)
        border.zPosition = 10
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    private var shownTones: (SpaceTheme?, Bool, CommandBarTones)?

    /// The space's palette in the bar's own appearance (CraCore CommandBarTones), worked out once per
    /// theme and appearance rather than on every keystroke.
    private func tones(dark: Bool) -> CommandBarTones {
        if let t = shownTones, t.0 == controller.theme, t.1 == dark { return t.2 }
        let tones = CommandBarTones(theme: controller.theme ?? SpaceTheme(colors: ["#010220"], intensity: 1, noise: 0, appearance: "dark"), dark: dark)
        shownTones = (controller.theme, dark, tones)
        return tones
    }

    static func ink(_ c: RGB, _ alpha: Double = 1) -> NSColor { NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: alpha) }

    var debugBadgeShown: Bool { !info.isHidden }
    var debugNoticeShown: Bool { !notice.isHidden }
    func debugPressBadge() -> Bool { info.accessibilityPerformPress() }
    func debugPressNotice(_ button: String) -> Bool { notice.debugPress(button) }

    override var isFlipped: Bool { true }

    private var dark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        sync()
    }

    private func scheduleSync() {
        guard !syncQueued else { return }
        syncQueued = true
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    private func sync() {
        syncQueued = false
        withObservationTracking { apply() } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleSync() }
        }
    }

    /// Colours turned into CGColors resolve against the current drawing appearance, which is the
    /// app's (macOS') unless set: a light bar on a dark Mac got white fills and hints.
    private func apply() {
        effectiveAppearance.performAsCurrentDrawingAppearance { applyResolved() }
    }

    private func applyResolved() {
        let c = controller
        let items = c.result.items
        let dark = self.dark
        text.update()
        attached = c.attached
        // Arc 1.172.1 live: a neutral dark panel, (48,48,48)–(51,50,50) over light pages; Cra's hudWindow
        // material under this tint (white ≈ 0.5 through 3 %) comes to ≈ (48,47,47).
        material.material = dark ? .hudWindow : .popover
        tint.layer?.backgroundColor = (dark ? NSColor(srgbRed: 46 / 255, green: 45 / 255, blue: 45 / 255, alpha: 0.97) : NSColor.white.withAlphaComponent(0.94)).cgColor
        // Arc 1.172.1 live: the badge is the space's backgroundExtra, its glyph (148,146,140) on a gold space.
        let tones = self.tones(dark: dark)
        info.layer?.backgroundColor = Self.ink(tones.badge).cgColor
        info.contentTintColor = dark ? NSColor.white.withAlphaComponent(0.55) : NSColor.labelColor.withAlphaComponent(0.55)
        border.strokeColor = NSColor.labelColor.withAlphaComponent(dark ? 0.12 : 0.08).cgColor
        divider.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        // The card's bar is Little Arc's own: opaque, a light hairline round it, a ✕ tile (Arc 1.172.1, #337).
        material.isHidden = card != nil
        closeTile.isHidden = card == nil
        if card != nil {
            tint.layer?.backgroundColor = LittlePalette.cardBar.cgColor
            border.strokeColor = LittlePalette.cardBarBorder.cgColor
            divider.layer?.backgroundColor = LittlePalette.cardDivider.cgColor
            closeTile.layer?.backgroundColor = LittlePalette.cardClose.cgColor
            closeTile.contentTintColor = LittlePalette.cardCloseGlyph
        }
        let scope = c.scope
        if c.isOpen, (scope == nil) != (shownScope == nil) {
            let site: SiteSearch? = if case .site(let site) = scope { site } else { nil }
            scopeChanged(color: site?.color.map { NSColor(hex: $0) })
        }
        shownScope = c.isOpen ? scope : nil
        // A site's brand colour; the tabs scope and Chromium's other keywords take the space's, the
        // colour of its rows (Arc's rows take theirs from the theme's palette, CommandBar.SuggestionsView).
        let highlight: NSColor
        if case .site(let site) = scope, let hex = site.color { highlight = NSColor(hex: hex) } else { highlight = Self.ink(tones.selection.rgb, tones.selection.alpha) }
        divider.isHidden = items.isEmpty && !c.showsNoticeBanner
        pill.isHidden = scope == nil
        if let scope {
            let color = highlight.withAlphaComponent(1)
            pill.layer?.backgroundColor = color.cgColor
            pill.layer?.shadowColor = color.cgColor
            pillLabel.stringValue = scope.name
        }
        // Arc shows no hint for the actions Tab offers on the empty field.
        let offered = scope == nil && c.previewText == nil && c.result.scope != .actions ? c.result.scope : nil
        hint.isHidden = offered == nil
        // Arc keeps the badge while typing ("alpha", "golf"); a site's "Search …  Tab" takes its place,
        // and so does the banner it opens (CraCore SearchSuggestionsNotice).
        info.isHidden = !c.showsNoticeBadge
        notice.isHidden = !c.showsNoticeBanner
        if !notice.isHidden { notice.apply(tones: tones) }
        keycap.isHidden = offered == nil
        if let offered {
            hint.stringValue = "Search \(offered.name)"
            hint.textColor = NSColor.labelColor.withAlphaComponent(0.33)
            keycapLabel.textColor = NSColor.labelColor.withAlphaComponent(0.67)
            keycap.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.04).cgColor
        }

        // Follows the row the arrows moved to; otherwise the top one.
        let previewing = c.previewText != nil && items.indices.contains(c.selectedIndex)
        let row = previewing ? items[c.selectedIndex] : items.first
        let typed = c.query.trimmingCharacters(in: .whitespaces)
        let glyph = CommandBarGlyph.resolve(
            editingURL: c.mode == .editURL && scope == nil, untouched: !previewing && (typed.isEmpty || typed == c.openedPrefill),
            // Actions run the row, not a search: Arc shows the row's glyph once something is typed.
            scoped: scope != nil && scope != .actions, pageFaviconKey: c.openedPrefill.flatMap(FaviconKey.key(for:)),
            row: row.map { ($0.faviconKey, $0.symbol) }, hasFavicon: { [favicons] in favicons.image(forKey: $0) != nil })
        if case .favicon(let key) = glyph, let img = favicons.image(forKey: key) {
            leadingIcon.imageScaling = .scaleProportionallyUpOrDown
            leadingIcon.image = img
            leadingIcon.contentTintColor = nil
            leadingIcon.layer?.cornerRadius = 5
            leadingIcon.layer?.masksToBounds = true
            leadingIcon.frame.size = NSSize(width: 20, height: 20)
        } else {
            leadingIcon.imageScaling = .scaleNone
            if case .symbol(let name) = glyph { leadingIcon.image = SidebarSymbols.image(name, size: 12, weight: .medium) }
            leadingIcon.contentTintColor = NSColor.labelColor.withAlphaComponent(0.85)
            leadingIcon.layer?.masksToBounds = false
            leadingIcon.frame.size = NSSize(width: 22, height: 22)
        }

        while rows.count < items.count {
            let r = CommandBarRowView()
            r.onHover = { [weak self, weak r] in
                guard let self, let r, let i = self.rows.firstIndex(where: { $0 === r }) else { return }
                if self.controller.selectedIndex != i { self.controller.selectedIndex = i }
            }
            r.onClick = { [weak self, weak r] in
                guard let self, let r, let i = self.rows.firstIndex(where: { $0 === r }), self.controller.result.items.indices.contains(i) else { return }
                self.controller.commit(self.controller.result.items[i])
            }
            rows.append(r)
            addSubview(r)
        }
        for (i, r) in rows.enumerated() {
            guard i < items.count else { r.isHidden = true; continue }
            r.isHidden = false
            let s = items[i]
            r.show(s, icon: s.faviconKey.flatMap { favicons.image(forKey: $0) }, selected: i == c.selectedIndex, highlight: highlight,
                   otherSpace: s.spaceID.flatMap { $0 != c.focusedSpaceID && s.tabID != nil ? c.spaceName($0) : nil },
                   dark: dark)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let b = bounds
        // Tab into a scope empties the list and the panel shrinks to the field after the glow
        // started: the glow follows, or it stays centred on the old list below the bar.
        if let splash, let window { splash.setFrame(window.frame.insetBy(dx: -Self.splashMargin, dy: -Self.splashMargin), display: false) }
        material.frame = b
        tint.frame = b
        let top: CGFloat = card?.top ?? (attached ? 10 : 12)
        let path = Self.path(b, top: top, bottom: card?.bottom ?? 12)
        shape.frame = b
        shape.path = path
        border.frame = b
        border.path = path
        // The magnifier and row favicons share a centre; input and result titles align.
        let fh = Self.fieldHeight
        let icon = leadingIcon.frame.size
        leadingIcon.frame = NSRect(x: 21 + (22 - icon.width) / 2, y: (fh - icon.height) / 2, width: icon.width, height: icon.height)
        var right = b.width - 22
        var end = b.width
        if let card {
            let s = LittleCard.closeSize
            closeTile.frame = NSRect(x: b.width - card.closeTrailing - s, y: (fh - s) / 2, width: s, height: s)
            right = closeTile.frame.minX - 14
            end = closeTile.frame.minX - 8 + 21
        }
        if !info.isHidden {
            // Arc: a 24 pt circle 21 pt from the edge (in a card, 8 pt before the ✕).
            info.frame = NSRect(x: end - 21 - 24, y: (fh - 24) / 2, width: 24, height: 24)
            right = info.frame.minX - 14
        }
        if !keycap.isHidden {
            // Key cap 23 tall, 4 pt around "Tab", 10 pt after the hint.
            let kw = ceil(keycapLabel.attributedStringValue.size().width), kh = keycapLabel.intrinsicContentSize.height
            keycap.frame = NSRect(x: right - kw - 8, y: (fh - 23) / 2, width: kw + 8, height: 23)
            keycapLabel.frame = NSRect(x: 4 - SidebarText.inset, y: (23 - kh) / 2, width: kw + 2 * SidebarText.inset, height: kh)
            right = keycap.frame.minX - 10
            let hw = ceil(hint.attributedStringValue.size().width), hh = hint.intrinsicContentSize.height
            hint.frame = NSRect(x: right - hw - SidebarText.inset, y: (fh - hh) / 2, width: hw + 2 * SidebarText.inset, height: hh)
            right -= hw + 14
        }
        var x: CGFloat = 10 + 10 + 24 + 8
        if !pill.isHidden {
            // 23 tall, fully round, 10.5 pt around the name; the field starts 11 pt after it.
            let lw = ceil(pillLabel.attributedStringValue.size().width), lh = pillLabel.intrinsicContentSize.height
            pill.frame = NSRect(x: x, y: (fh - 23) / 2, width: lw + 21, height: 23)
            pill.layer?.cornerRadius = 11.5
            pillLabel.frame = NSRect(x: 10.5 - SidebarText.inset, y: (23 - lh) / 2, width: lw + 2 * SidebarText.inset, height: lh)
            x = pill.frame.maxX + 11
        }
        text.field.frame = NSRect(x: x - 1.5, y: (fh - 30) / 2 + 3, width: max(0, right - x), height: 30)
        if let card {
            // A hairline: one pixel.
            let px = 1 / (window?.backingScaleFactor ?? 2)
            divider.frame = NSRect(x: card.dividerInset, y: fh - px, width: max(0, b.width - 2 * card.dividerInset), height: px)
        } else {
            divider.frame = NSRect(x: 16, y: fh, width: max(0, b.width - 32), height: 1)
        }
        var y: CGFloat = fh + 6
        for r in rows where !r.isHidden {
            r.frame = NSRect(x: 10, y: y, width: b.width - 20, height: Self.rowHeight)
            y += Self.rowHeight + 4
        }
        // Arc: 60 pt at the bottom, edge to edge under the outline, in the last row's place.
        let nh = CGFloat(SearchSuggestionsNotice.bannerHeight)
        notice.frame = NSRect(x: 0, y: b.height - nh, width: b.width, height: nh)
    }

    // MARK: Entering a scope (Arc's CommandBarContainer, 1.171)

    /// Tab into a scope and Backspace out of it: the bar bounces, and a site's colour washes
    /// through it (Arc's arc_commandBarBounce and SplashView, read from its binary).
    private func scopeChanged(color: NSColor?) {
        bounce()
        splash?.parent?.removeChildWindow(splash!)
        splash?.orderOut(nil)
        splash = nil
        innerSplash?.removeFromSuperview()
        innerSplash = nil
        if let color { showSplash(color) }
    }

    /// A spring toward 0.95 (damping ratio 0.9, response 0.7) cut off after 0.1 s and played
    /// back: the bar dips about 1% and returns within 0.2 s.
    private func bounce() {
        guard let layer else { return }
        let w = layer.bounds.width, h = layer.bounds.height
        // About the bar's centre, whatever anchor AppKit gave the layer.
        let dx = (0.5 - layer.anchorPoint.x) * w, dy = (0.5 - layer.anchorPoint.y) * h
        let scaled = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(dx, dy, 0), 0.95, 0.95, 1), -dx, -dy, 0)
        let a = CASpringAnimation(keyPath: "transform")
        a.mass = 1
        a.stiffness = pow(2 * .pi / 0.7, 2)
        a.damping = 4 * .pi * 0.9 / 0.7
        a.fromValue = layer.presentation()?.transform ?? CATransform3DIdentity
        a.toValue = scaled
        a.autoreverses = true
        a.repeatCount = 1
        a.fillMode = .forwards
        a.duration = 0.1
        layer.add(a, forKey: "arc_commandBarBounce")
    }

    /// The site's colour as a 12 pt rounded rectangle under the bar, blurring to 150 and fading
    /// out over 1.2 s (ease-out). It spreads past the bar, so it gets a panel of its own below the
    /// bar's. Arc's sits under the bar's background in the same window and shows through it: the
    /// inside turns dark red at once ((47, 20, 19) over (26, 26, 26) for YouTube), holds for 0.17 s
    /// and is gone after a second (measured at 100 fps, 3 Nov). The bar's material can't see the
    /// panel below, so the inside is the colour under the bar's tint, following that curve.
    private func showSplash(_ color: NSColor) {
        guard let window else { return }
        let inner = NSView(frame: bounds)
        inner.autoresizingMask = [.width, .height]
        inner.wantsLayer = true
        inner.layer?.backgroundColor = color.cgColor
        inner.layer?.opacity = 0
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.keyTimes = Self.innerSplashCurve.map { NSNumber(value: $0.time) }
        fade.values = Self.innerSplashCurve.map { 0.42 * $0.level }
        fade.duration = 1
        inner.layer?.add(fade, forKey: "splash")
        addSubview(inner, positioned: .above, relativeTo: material)
        innerSplash = inner
        let margin = Self.splashMargin
        let panel = SplashPanel(contentRect: window.frame.insetBy(dx: -margin, dy: -margin), styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = window.collectionBehavior
        panel.contentView = NSHostingView(rootView: CommandBarSplash(color: Color(nsColor: color), margin: margin))
        window.addChildWindow(panel, ordered: .below)
        splash = panel
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) { [weak self, weak panel] in
            guard let self, let panel, self.splash === panel else { return }
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            self.splash = nil
            self.innerSplash?.removeFromSuperview()
            self.innerSplash = nil
        }
    }

    /// Room around the bar for the glow's blur.
    private static let splashMargin: CGFloat = 420

    /// How much of the site's colour shows inside Arc's bar after Tab, relative to the start (red
    /// over green, sampled off a 100 fps recording of Arc 1.171).
    private static let innerSplashCurve: [(time: Double, level: Double)] = [
        (0, 1), (0.17, 1), (0.21, 0.89), (0.27, 0.67), (0.33, 0.52), (0.39, 0.36), (0.45, 0.30), (0.51, 0.23),
        (0.57, 0.185), (0.69, 0.107), (0.75, 0.078), (0.87, 0.06), (0.93, 0.026), (1, 0),
    ]

    /// UnevenRoundedRectangle: smaller top corners while the bar hangs from the toolbar.
    private static func path(_ r: CGRect, top: CGFloat, bottom: CGFloat) -> CGPath {
        let p = CGMutablePath()
        // Flipped view: minY is the top edge.
        p.move(to: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + top), radius: top)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottom))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - bottom, y: r.maxY), radius: bottom)
        p.addLine(to: CGPoint(x: r.minX + bottom, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bottom), radius: bottom)
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + top))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + top, y: r.minY), radius: top)
        p.closeSubpath()
        return p
    }
}

/// The card ⌥⌘N opens (#337), as the Little Window lays it out: the bar's corners (the window's at
/// the top, and at the bottom while the bar fills the card), and where the ✕ and the divider go, from
/// the bar's own edges.
struct CommandBarCard: Equatable {
    var top: CGFloat
    var bottom: CGFloat
    var closeTrailing: CGFloat
    var dividerInset: CGFloat
}

/// The glow's panel reaches 420 pt past the bar, so near the top of the screen it crosses the
/// menu bar, and AppKit moves a window that does down below it: the glow sat under the bar, not
/// around it (a Little Window's bar is a third of the way down a small window). Its frame is
/// left as asked.
private final class SplashPanel: NSPanel {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Arc's SplashView: `Color(nsColor:)` clipped to a 12 pt continuous rounded rectangle, blurred and
/// faded by one ease-out animation of 1.2 s that starts as it appears.
private struct CommandBarSplash: View {
    let color: Color
    /// The bar is the panel less this on every side.
    let margin: CGFloat
    @State private var blurRadius: CGFloat = 0
    @State private var opacity: Double = 1

    var body: some View {
        color
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(margin)
            .blur(radius: blurRadius, opaque: false)
            .opacity(opacity)
            .animation(.easeOut(duration: 1.2), value: blurRadius)
            .onAppear {
                blurRadius = 150
                opacity = 0
            }
    }
}

/// One suggestion: icon, "Title — detail", and "Switch to Tab" + arrow for open tabs.
final class CommandBarRowView: NSView {
    var onHover: () -> Void = {}
    var onClick: () -> Void = {}
    private let iconBox = NSView()
    private let icon = NSImageView()
    private let emoji = NSTextField.sidebarLabel(size: 16)
    private let label = NSTextField.sidebarLabel(size: 14)
    private let trailing = NSTextField.sidebarLabel(size: 14, weight: .semibold)
    private let arrowBox = NSView()
    private let arrow = NSImageView()
    private var shown: (Suggestion, NSImage?, Bool, NSColor, String?, Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        iconBox.wantsLayer = true
        iconBox.layer?.cornerRadius = 4
        iconBox.layer?.cornerCurve = .continuous
        icon.imageScaling = .scaleProportionallyUpOrDown
        arrowBox.wantsLayer = true
        arrowBox.layer?.cornerRadius = 4
        arrowBox.layer?.cornerCurve = .continuous
        arrow.image = SidebarSymbols.image("arrow.right", size: 17, weight: .medium)
        arrow.imageScaling = .scaleNone
        label.lineBreakMode = .byTruncatingTail
        trailing.textColor = .secondaryLabelColor
        for v in [iconBox, icon, emoji, label, trailing, arrowBox, arrow] as [NSView] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ s: Suggestion, icon image: NSImage?, selected: Bool, highlight: NSColor, otherSpace: String?, dark: Bool) {
        if let o = shown, o.0 == s, o.1 === image, o.2 == selected, o.3 == highlight, o.4 == otherSpace, o.5 == dark { return }
        shown = (s, image, selected, highlight, otherSpace, dark)
        layer?.backgroundColor = (selected ? highlight : .clear).cgColor
        // Selection changes all foregrounds too, including when reusable rows keep their content.
        // Arc 1.172.1 live (dark): titles (214,214,214), "Switch to Tab" and URLs (117,117,117), white when selected.
        let ink: NSColor = selected ? .white : (dark ? NSColor(white: 0.84, alpha: 1) : NSColor.black.withAlphaComponent(0.85))
        let secondaryInk = selected ? NSColor.white.withAlphaComponent(0.85) : (dark ? NSColor(white: 0.46, alpha: 1) : NSColor.black.withAlphaComponent(0.40))
        if let image {
            icon.isHidden = false
            emoji.isHidden = true
            iconBox.isHidden = !selected
            icon.image = image
            icon.imageScaling = .scaleProportionallyUpOrDown
            icon.contentTintColor = nil
            iconBox.layer?.backgroundColor = NSColor.white.cgColor
        } else if case .switchSpace = s.kind, let t = s.trailing {
            icon.isHidden = true
            iconBox.isHidden = true
            emoji.isHidden = false
            emoji.stringValue = t
        } else {
            if case .command = s.kind {
                iconBox.isHidden = false
                iconBox.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.05).cgColor
            } else {
                iconBox.isHidden = true
            }
            emoji.isHidden = true
            icon.isHidden = false
            icon.image = SidebarSymbols.image(s.symbol ?? "globe", size: 14, weight: .medium)
            icon.imageScaling = .scaleNone
            icon.contentTintColor = selected ? .white : ink
        }
        let t = NSMutableAttributedString(string: s.title, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .semibold), .foregroundColor: ink])
        t.append(NSAttributedString(string: Self.detail(s), attributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: secondaryInk]))
        label.attributedStringValue = t
        let isTab = s.tabID != nil
        if isTab {
            trailing.font = .systemFont(ofSize: 14, weight: .semibold)
            trailing.stringValue = otherSpace ?? "Switch to Tab"
        } else {
            trailing.font = .systemFont(ofSize: 13, weight: .medium)
            trailing.stringValue = s.trailing ?? ""
        }
        arrowBox.isHidden = !isTab
        arrow.isHidden = !isTab
        trailing.textColor = selected ? .white : secondaryInk
        // Arc: the arrow (189,189,189) on a white-5 % tile; selected, the row's colour on a white tile.
        arrow.contentTintColor = selected ? highlight.withAlphaComponent(1) : (dark ? NSColor.white.withAlphaComponent(0.72) : NSColor.labelColor.withAlphaComponent(0.65))
        arrowBox.layer?.backgroundColor = (selected ? NSColor.white : NSColor.labelColor.withAlphaComponent(0.05)).cgColor
        needsLayout = true
    }

    private static func detail(_ s: Suggestion) -> String {
        switch s.kind {
        case .switchToTab, .search, .command, .switchSpace, .moveToSpace, .moveToFolder: return ""
        case .archived: return s.subtitle.isEmpty ? "" : " — \(s.subtitle)"
        default:
            guard let url = s.url else { return "" }
            let human = SuggestionEngine.humanURL(url)
            return human.lowercased() == s.title.lowercased() ? "" : " — \(human)"
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        // 10 pt padding, a 24 pt favicon tile, 8 pt to the title, and a 24 pt arrow tile.
        iconBox.frame = NSRect(x: 10, y: (h - 24) / 2, width: 24, height: 24)
        icon.frame = iconBox.frame.insetBy(dx: 4, dy: 4)
        let es = emoji.intrinsicContentSize
        emoji.frame = NSRect(x: 10 + (24 - es.width) / 2, y: (h - es.height) / 2, width: es.width, height: es.height)
        var right = bounds.width - 12
        if !arrowBox.isHidden {
            arrowBox.frame = NSRect(x: right - 24, y: (h - 24) / 2, width: 24, height: 24)
            arrow.frame = arrowBox.frame
            right -= 24 + 10
        }
        if !trailing.stringValue.isEmpty {
            let tw = ceil(trailing.attributedStringValue.size().width)
            let th = trailing.intrinsicContentSize.height
            trailing.frame = NSRect(x: right - tw - SidebarText.inset, y: (h - th) / 2, width: tw + 2 * SidebarText.inset, height: th)
            right -= tw + 14
        } else if !arrowBox.isHidden {
            // The empty label still takes its spacing in the HStack.
            right -= 14
        }
        let x: CGFloat = 10 + 24 + 8
        let ls = label.intrinsicContentSize
        label.frame = NSRect(x: x - SidebarText.inset, y: (h - ls.height) / 2, width: max(0, right - 8 - x) + 2 * SidebarText.inset, height: ls.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { onHover() }
    override func mouseMoved(with event: NSEvent) { onHover() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

/// The info badge: a click (or an accessibility press) runs `onPress`, as the bar's rows do.
private final class CommandBarBadge: NSImageView {
    var onPress: () -> Void = {}
    var label = "About search suggestions"

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress() }
    }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { label }
    override func accessibilityPerformPress() -> Bool {
        onPress()
        return true
    }
}

/// Arc's search-suggestions banner (CommandBar.SearchSuggestionsPrivacyView, Arc 1.172.1 at 2x, #314): black,
/// a 13 pt (i) centred 24 pt in, "We talk to your search engine to help us suggest results." in 13 pt bold
/// from 46.5 pt with "Learn more about your data on … here." under it in 12 pt grey, and Search Settings…
/// (130.5 pt) and Dismiss (71 pt), 37 pt tall, 10 pt apart and 10 pt from the edge.
private final class SearchSuggestionsBannerView: NSView {
    var onSettings: () -> Void = {}
    var onDismiss: () -> Void = {}
    var onLearnMore: () -> Void = {}

    private let icon = NSImageView()
    private let title = NSTextField.sidebarLabel(size: 13, weight: .bold)
    private let subtitle = NSTextField.sidebarLabel(size: 12, weight: .regular)
    private let link = NoticeLinkLabel()
    private let settings = NoticeButton(title: "Search Settings…")
    private let dismiss = NoticeButton(title: "Dismiss")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        icon.image = SidebarSymbols.image("info.circle", size: 13, weight: .regular)
        icon.imageScaling = .scaleNone
        icon.contentTintColor = NSColor(white: 115 / 255, alpha: 1)
        title.stringValue = "We talk to your search engine to help us suggest results."
        title.textColor = NSColor(white: 237 / 255, alpha: 1)
        let ink = NSColor(white: 126 / 255, alpha: 1), font = NSFont.systemFont(ofSize: 12)
        let text = NSMutableAttributedString(string: Self.lead, attributes: [.font: font, .foregroundColor: ink])
        text.append(NSAttributedString(string: "here", attributes: [.font: font, .foregroundColor: ink, .underlineStyle: NSUnderlineStyle.single.rawValue]))
        text.append(NSAttributedString(string: ".", attributes: [.font: font, .foregroundColor: ink]))
        subtitle.attributedStringValue = text
        link.onClick = { [weak self] in self?.onLearnMore() }
        settings.onClick = { [weak self] in self?.onSettings() }
        dismiss.onClick = { [weak self] in self?.onDismiss() }
        for v in [icon, title, subtitle, link, settings, dismiss] as [NSView] { addSubview(v) }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(title.stringValue)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func apply(tones: CommandBarTones) {
        for b in [settings, dismiss] { b.set(fill: CommandBarView.ink(tones.noticeButtonFill), outline: CommandBarView.ink(tones.noticeButtonOutline)) }
    }

    private static let lead = "Learn more about your data on Cra "

    func debugPress(_ name: String) -> Bool {
        switch name {
        case "settings": return settings.accessibilityPerformPress()
        case "dismiss": return dismiss.accessibilityPerformPress()
        case "learnMore": return link.accessibilityPerformPress()
        default: return false
        }
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        icon.frame = NSRect(x: 24 - 8, y: (h - 16) / 2, width: 16, height: 16)
        let dw: CGFloat = 71, sw: CGFloat = 130.5, bh: CGFloat = 37
        dismiss.frame = NSRect(x: bounds.width - 10 - dw, y: (h - bh) / 2, width: dw, height: bh)
        settings.frame = NSRect(x: dismiss.frame.minX - 10 - sw, y: (h - bh) / 2, width: sw, height: bh)
        let x: CGFloat = 46.5 - SidebarText.inset
        let maxW = max(0, settings.frame.minX - 12 - x)
        let th = title.intrinsicContentSize.height, sh = subtitle.intrinsicContentSize.height
        let top = (h - th - sh - 1) / 2
        title.frame = NSRect(x: x, y: top, width: maxW, height: th)
        subtitle.frame = NSRect(x: x, y: top + th + 1, width: maxW, height: sh)
        // The click target over "here".
        let font = NSFont.systemFont(ofSize: 12)
        let lead = ceil((Self.lead as NSString).size(withAttributes: [.font: font]).width)
        let here = ceil(("here" as NSString).size(withAttributes: [.font: font]).width)
        link.frame = NSRect(x: x + SidebarText.inset + lead - 1, y: subtitle.frame.minY, width: here + 2, height: sh)
    }
}

/// The click target over the subtitle's "here": it opens Cra's privacy page.
private final class NoticeLinkLabel: NSView {
    var onClick: () -> Void = {}

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .link }
    override func accessibilityLabel() -> String? { "here" }
    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }
}

/// The banner's buttons: the space's focus colour over black, a 1 pt outline, 5 pt corners, 13 pt white.
private final class NoticeButton: NSView {
    var onClick: () -> Void = {}
    private let label = NSTextField.sidebarLabel(size: 13, weight: .medium)

    init(title: String) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        label.stringValue = title
        label.textColor = NSColor(srgbRed: 235 / 255, green: 235 / 255, blue: 239 / 255, alpha: 1)
        label.alignment = .center
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func set(fill: NSColor, outline: NSColor) {
        layer?.backgroundColor = fill.cgColor
        layer?.borderColor = outline.cgColor
    }

    override func layout() {
        super.layout()
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
    }

    override var isFlipped: Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { label.stringValue }
    override func accessibilityPerformPress() -> Bool {
        onClick()
        return true
    }
}
