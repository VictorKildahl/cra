import AppKit

/// Arc 1.171's "now playing" player over the bottom of the tab list (issue #33): Arc's
/// MediaControlsFeature (MiniPlayerView in a MediaControlsHostingView), measured from window
/// captures at 2x and 120 fps recordings of a running Arc (31 Oct 2026) and read from its
/// binary (Swift metadata, the PlaybackControlForeground colour asset, tooltip strings).
///
/// Cards sit 8 pt in from the sidebar's edges with 6 pt corners, bottom where the tab list ends
/// (50 pt above the window's), filled with the window palette's `backgroundExtra`: 15 % of the
/// theme's deep shade on dark spaces, near-white on light ones. At rest only the newest card
/// shows, 33 pt tall: favicon ("Back to Tab"), previous, play/pause, next and volume, laid out
/// like an HStack (glyphs 16 / 13 / 8.5 / 13 / 19 pt wide, equal gaps, 14 pt in on the left and
/// 12.5 on the right). Up to two more peek out behind it, each 7 pt higher, 5 pt narrower a side
/// and 20 % fainter; the second shows the tops of its controls at 15 %, 7.25 pt higher than the
/// front card's. Hovering opens every card to 65.5 pt with the tab's title (13 pt, 14.5 pt in,
/// centred 16.25 pt from the top), Picture in Picture for a video and ✕, stacked upward 5 pt apart,
/// oldest on top, in 0.2 s (ease-out); leaving folds them back the same way. The volume button
/// opens a drawer, one more 32.75 pt row with a slider, and stays lit while it is open. Glyphs are
/// PlaybackControlForeground (white 66 % / black 50 %), a third of that when unavailable, with a
/// 24 × 23 pt square (white 7 % / black 8 %) on hover. The tab on screen has no card.
enum NowPlayingMetrics {
    static let inset: CGFloat = 8
    static let collapsedHeight: CGFloat = 33
    static let expandedHeight: CGFloat = 65.5
    static let drawerHeight: CGFloat = 33
    static let gap: CGFloat = 5
    static let peek: CGFloat = 7
    static let peekInset: CGFloat = 5
    static let peekFade: CGFloat = 0.2
    static let restingCards = 3
    static let ghostLift: CGFloat = 7.25
    static let ghostAlpha: CGFloat = 0.15
    static let corner: CGFloat = 6
    static let closeCentreFromRight: CGFloat = 21.75
    static let pipCentreFromRight: CGFloat = 45.5
    static let titleCentreFromTop: CGFloat = 16.25
    static let rowCentreFromBottom: CGFloat = 16.5
    static let controlWidths: [CGFloat] = [16, 13, 8.5, 13, 19]
    static let controlsLeading: CGFloat = 14
    static let controlsTrailing: CGFloat = 12.5

    /// Height the tab list gives up while the player rests (with its gap to the list).
    static func restHeight(cards: Int) -> CGFloat {
        cards == 0 ? 0 : collapsedHeight + CGFloat(min(cards, restingCards) - 1) * peek + 8
    }
}

/// The card's colours for a theme colour and scheme. Arc derives them from the window palette
/// (`backgroundExtra`, `PlaybackControlForeground`, `tintedLight`, `shadedDark`); Cra has no Arc
/// palette, so its shades are rebuilt from the theme colour: Arc's shadedDark is the theme's hue,
/// strongly saturated, at ~10 % luminance (#6F5600 for #F8D558, #1F2AFF for a deep blue).
struct NowPlayingColors {
    let isDark: Bool
    let fill: NSColor
    let foreground: NSColor
    let title: NSColor
    let hover: NSColor
    let placeholder: NSColor
    let trackFilled: NSColor
    let trackEmpty: NSColor
    let knob: NSColor

    init(themeColor hex: String?, dark: Bool) {
        let c = HexColor.components(hex ?? "") ?? (0.5, 0.5, 0.5)
        let (h, s, _) = SpaceTheme.hsb(c.r, c.g, c.b)
        let grey = s < 0.05
        func color(_ s: Double, _ v: Double) -> NSColor {
            let o = SpaceTheme.rgb(h: h, s: s, v: v)
            return NSColor(srgbRed: o.0, green: o.1, blue: o.2, alpha: 1)
        }
        // shadedDark: the brightness at which the saturated hue reaches 10 % luminance.
        func lin(_ x: Double) -> Double { x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let ds = grey ? 0 : 0.94
        var lo = 0.0, hi = 1.0
        for _ in 0..<20 {
            let v = (lo + hi) / 2, o = SpaceTheme.rgb(h: h, s: ds, v: v)
            if 0.2126 * lin(o.0) + 0.7152 * lin(o.1) + 0.0722 * lin(o.2) < 0.1 { lo = v } else { hi = v }
        }
        isDark = dark
        if dark {
            fill = color(ds, lo * 0.15)
            foreground = NSColor.white.withAlphaComponent(0.66)
            title = NSColor.white.withAlphaComponent(0.81)
            hover = NSColor.white.withAlphaComponent(0.07)
            placeholder = NSColor.white.withAlphaComponent(0.14)
            trackFilled = color(grey ? 0 : 0.25, 0.99)
            trackEmpty = NSColor.white.withAlphaComponent(0.1)
            knob = NSColor(srgbRed: 0.86, green: 0.86, blue: 0.85, alpha: 1)
        } else {
            fill = color(grey ? 0 : 0.012, 0.996)
            foreground = NSColor.black.withAlphaComponent(0.5)
            title = NSColor.black.withAlphaComponent(0.85)
            hover = NSColor.black.withAlphaComponent(0.08)
            placeholder = NSColor.black.withAlphaComponent(0.15)
            trackFilled = color(ds, lo)
            trackEmpty = NSColor.black.withAlphaComponent(0.18)
            knob = .white
        }
    }

    var disabled: NSColor { foreground.withAlphaComponent(foreground.alphaComponent / 3) }

    /// Row-button colours for the card (only the hover fill is used; glyphs take `tint`).
    var buttonColors: SidebarColors {
        var c = SidebarColors(SpaceTheme.presets[isDark ? 0 : SpaceTheme.presets.count - 1].palette)
        c.hoverFill = hover
        return c
    }
}

/// The cards, pinned to the bottom of the tab list's area. The view spans the list so the
/// stack can grow over it; points outside the cards fall through to the list.
@MainActor
final class NowPlayingTrayView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let favicons: FaviconCache
    private var cards: [UUID: NowPlayingCardView] = [:]
    private var order: [UUID] = []
    private var expanded = false
    private var drawerID: UUID?
    private var colors = NowPlayingColors(themeColor: nil, dark: true)
    /// The number of cards changed: the sidebar gives the list more or less room.
    var onCountChange: (() -> Void)?
    var shownCount: Int { order.count }

    init(store: SidebarStore, ui: SidebarUIState, favicons: FaviconCache) {
        self.store = store
        self.ui = ui
        self.favicons = favicons
        super.init(frame: .zero)
        wantsLayer = true
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    /// The space's theme colour and scheme, for the cards' palette.
    func setTheme(_ hex: String?, dark: Bool) {
        colors = NowPlayingColors(themeColor: hex, dark: dark)
        for c in cards.values { c.colors = colors }
    }

    private func observe() {
        let shown = withObservationTracking { () -> [(NowPlaying.Entry, NowPlayingCardModel)] in
            ui.nowPlaying.shown.map { e in
                let item = store.item(e.id)
                let icon = favicons.image(forKey: item?.tab?.iconKey)
                return (e, NowPlayingCardModel(title: item?.displayTitle ?? "", icon: icon, playing: e.playing,
                                               muted: item?.tab?.muted ?? false, hasPrevious: e.hasPrevious, hasNext: e.hasNext,
                                               hasVideo: e.hasVideo, volume: e.volume))
            }
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        let ids = shown.map(\.0.id)
        for (e, m) in shown {
            let card = cards[e.id] ?? makeCard(e.id)
            card.apply(m)
        }
        for (id, card) in cards where !ids.contains(id) {
            cards[id] = nil
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                card.animator().alphaValue = 0
            } completionHandler: { card.removeFromSuperview() }
        }
        let countChanged = ids.count != order.count
        order = ids
        if order.isEmpty { expanded = false }
        if let d = drawerID, !ids.contains(d) { drawerID = nil }
        place(animated: true)
        if countChanged { onCountChange?() }
    }

    private func makeCard(_ id: UUID) -> NowPlayingCardView {
        let card = NowPlayingCardView(colors: colors) { [weak self] action in
            guard let self else { return }
            if case .toggleMute = action {
                // Arc's volume button opens the volume drawer; the tab's mute stays on its row.
                self.drawerID = self.drawerID == id ? nil : id
                self.place(animated: true)
                return
            }
            self.ui.nowPlaying.perform(id, action)
        }
        card.frame = restFrame(level: 0)
        card.alphaValue = 0
        addSubview(card, positioned: .below, relativeTo: nil)
        cards[id] = card
        return card
    }

    // MARK: Layout

    /// `level` counts back from the front card.
    private func restFrame(level k: Int) -> NSRect {
        let m = NowPlayingMetrics.self
        let k = CGFloat(min(k, m.restingCards - 1))
        return NSRect(x: m.inset + k * m.peekInset, y: k * m.peek, width: bounds.width - 2 * (m.inset + k * m.peekInset),
                      height: m.collapsedHeight)
    }

    private func place(animated: Bool) {
        let m = NowPlayingMetrics.self
        var frames: [(NowPlayingCardView, NSRect, CGFloat)] = []
        var y: CGFloat = 0
        for (k, id) in order.reversed().enumerated() {
            guard let card = cards[id] else { continue }
            card.drawerOpen = expanded && drawerID == id
            if expanded {
                let h = m.expandedHeight + (card.drawerOpen ? m.drawerHeight : 0)
                let f = NSRect(x: m.inset, y: y, width: bounds.width - 2 * m.inset, height: h)
                y += h + m.gap
                frames.append((card, f, f.maxY <= bounds.height ? 1 : 0))
            } else {
                frames.append((card, restFrame(level: k), k < m.restingCards ? 1 - CGFloat(k) * m.peekFade : 0))
            }
        }
        // The front card on top. Cards behind it show only their edge, and their buttons must not
        // take the hover meant for the front card's (tracking areas don't know what covers them).
        for (card, _, _) in frames.reversed() { addSubview(card, positioned: .above, relativeTo: nil) }
        let front = frames.first?.0
        let second = frames.count > 1 ? frames[1].0 : nil
        let hideBehind = { [expanded] in
            for (card, _, _) in frames {
                card.ghostVisible = !expanded && card === second   // pictured before its controls hide
                card.contentHidden = !expanded && card !== front
            }
        }
        if expanded { hideBehind() }
        guard animated, window != nil else {
            for (card, f, a) in frames { card.frame = f; card.alphaValue = a }
            hideBehind()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.85, 0.3, 1)
            ctx.allowsImplicitAnimation = true
            for (card, f, a) in frames {
                card.animator().frame = f
                card.animator().alphaValue = a
            }
        } completionHandler: { [weak self] in
            if self?.expanded == false { hideBehind() }
        }
    }

    override func layout() {
        super.layout()
        place(animated: false)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { setHovered(overStack(convert(event.locationInWindow, from: nil))) }
    override func mouseEntered(with event: NSEvent) { setHovered(overStack(convert(event.locationInWindow, from: nil))) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    /// The whole stack, gaps between cards included, so moving from card to card keeps it open.
    private func overStack(_ p: NSPoint) -> Bool {
        cards.values.filter { $0.alphaValue > 0 }.map(\.frame).reduce(NSRect.null) { $0.union($1) }.contains(p)
    }

    private func setHovered(_ hovered: Bool) {
        let want = hovered && !order.isEmpty
        guard want != expanded else { return }
        expanded = want
        if !want { drawerID = nil }
        place(animated: true)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard cards.values.contains(where: { $0.alphaValue > 0 && $0.frame.contains(p) }) else { return nil }
        return super.hitTest(point)
    }
}

struct NowPlayingCardModel: Equatable {
    var title: String
    var icon: NSImage?
    var playing: Bool
    var muted: Bool
    var hasPrevious: Bool
    var hasNext: Bool
    var hasVideo: Bool
    var volume: Double
}

/// One card: the title row on top (shown while the stack is open), the controls, and the volume
/// drawer below them. The content stays pinned to the card's bottom, so a resting card shows only
/// the controls and opening it reveals the title from above.
@MainActor
final class NowPlayingCardView: NSView {
    private let content = NSView()
    private let title = NSTextField.sidebarLabel(size: 13)
    private let titleRow = NSView()
    private let icon = NowPlayingIconView()
    private let pip: SidebarGlyphButton
    private let close: SidebarGlyphButton
    private let previous: SidebarGlyphButton
    private let playPause: SidebarGlyphButton
    private let next: SidebarGlyphButton
    private let volume: SidebarGlyphButton
    private let slider = NowPlayingVolumeSlider()
    /// A resting card behind the front one shows a faint, inert copy of its controls (no buttons,
    /// so it can't take the front card's hover or tooltips).
    private let ghost = NowPlayingGhostRow()
    private var model: NowPlayingCardModel?
    private let perform: (NowPlaying.Action) -> Void
    var colors: NowPlayingColors { didSet { applyColors() } }
    var drawerOpen = false {
        didSet {
            guard drawerOpen != oldValue else { return }
            volume.highlighted = drawerOpen
            slider.isHidden = !drawerOpen
            needsLayout = true
        }
    }
    var contentHidden: Bool {
        get { content.isHidden }
        set { if content.isHidden != newValue { content.isHidden = newValue } }
    }
    var ghostVisible = false {
        didSet {
            guard ghostVisible != oldValue else { return }
            if ghostVisible { ghost.show(from: [icon, previous, playPause, next, volume]) }
            ghost.isHidden = !ghostVisible
            needsLayout = true
        }
    }

    init(colors: NowPlayingColors, perform: @escaping (NowPlaying.Action) -> Void) {
        self.colors = colors
        self.perform = perform
        func button(_ symbol: String, _ iconSize: CGFloat, _ help: String, _ action: NowPlaying.Action) -> SidebarGlyphButton {
            SidebarGlyphButton(symbol: symbol, size: 24, height: 23, iconSize: iconSize, help: help, colors: colors.buttonColors) { perform(action) }
        }
        pip = button("rectangle.on.rectangle", 13, "Open Picture in Picture", .pictureInPicture)
        close = button("xmark", 14, "Close Mini Player", .dismiss)
        previous = button("backward.end.fill", 13.5, "Previous Track", .previous)
        playPause = button("pause.fill", 13.5, "Pause", .togglePlayback)
        next = button("forward.end.fill", 13.5, "Next Track", .next)
        volume = button("speaker.wave.3.fill", 14, "Adjust Tab Volume", .toggleMute)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = NowPlayingMetrics.corner
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        icon.onClick = { perform(.show) }
        _ = ArcTooltipAnchorView.attach(to: icon, help: "Back to Tab")
        // Arc: clicking the title row (titleRowClicked) goes back to the tab.
        titleRow.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(titleClicked)))
        slider.isHidden = true
        slider.onChange = { v in perform(.setVolume(v)) }
        pip.isHidden = true
        titleRow.addSubview(title)
        for v in [titleRow, pip, close, icon, previous, playPause, next, volume, slider] as [NSView] { content.addSubview(v) }
        addSubview(content)
        ghost.isHidden = true
        ghost.alphaValue = NowPlayingMetrics.ghostAlpha
        addSubview(ghost)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func titleClicked() { perform(.show) }

    private func applyColors() {
        layer?.backgroundColor = colors.fill.cgColor
        title.textColor = colors.title
        icon.placeholder = colors.placeholder
        slider.colors = colors
        for b in [pip, close, playPause, volume] { b.colors = colors.buttonColors; b.tint = colors.foreground }
        refreshTrackButtons()
    }

    /// Previous/next without a media session handler are dimmed, with no hover and no tooltip.
    private func refreshTrackButtons() {
        for (b, on, help) in [(previous, model?.hasPrevious ?? false, "Previous Track"), (next, model?.hasNext ?? false, "Next Track")] {
            b.colors = colors.buttonColors
            b.enabled = on
            b.tint = on ? colors.foreground : colors.disabled
            b.setHelp(on ? help : "")
        }
    }

    func apply(_ m: NowPlayingCardModel) {
        guard m != model else { return }
        let old = model
        model = m
        title.stringValue = m.title
        icon.image = m.icon
        if old?.playing != m.playing {
            playPause.setSymbol(m.playing ? "pause.fill" : "play.fill", iconSize: 13.5, help: m.playing ? "Pause" : "Play")
        }
        // Arc: three waves, one wave below half volume, none at zero; a muted tab shows the slash.
        if old.map({ $0.muted != m.muted || $0.volume != m.volume }) ?? true {
            let symbol = m.muted ? "speaker.slash.fill" : m.volume <= 0 ? "speaker.fill" : m.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"
            volume.setSymbol(symbol, iconSize: 14, help: "Adjust Tab Volume")
        }
        if !slider.isTracking { slider.value = m.volume }
        pip.isHidden = !m.hasVideo
        refreshTrackButtons()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let m = NowPlayingMetrics.self
        let w = bounds.width
        let drawer = drawerOpen ? m.drawerHeight : 0
        let h = m.expandedHeight + drawer
        content.frame = NSRect(x: 0, y: 0, width: w, height: h)
        if drawerOpen {
            slider.frame = NSRect(x: 8, y: m.rowCentreFromBottom + 0.25 - 10, width: w - 16, height: 20)
        }
        let row = m.rowCentreFromBottom + drawer
        let gap = (w - m.controlsLeading - m.controlsTrailing - m.controlWidths.reduce(0, +)) / 4
        var x = m.controlsLeading
        for (v, glyphWidth) in zip([icon, previous, playPause, next, volume] as [NSView], m.controlWidths) {
            let s = v.frame.size == .zero ? NSSize(width: 24, height: 23) : v.frame.size
            let cx = x + glyphWidth / 2
            v.frame = NSRect(x: cx - s.width / 2, y: (row - s.height / 2).rounded(), width: s.width, height: s.height)
            x += glyphWidth + gap
        }
        let top = h - m.titleCentreFromTop
        close.frame = NSRect(x: w - m.closeCentreFromRight - 12, y: (top - 11.5).rounded(), width: 24, height: 23)
        pip.frame = NSRect(x: w - m.pipCentreFromRight - 12, y: (top - 11.5).rounded(), width: 24, height: 23)
        ghost.frame = NSRect(x: 0, y: (m.rowCentreFromBottom + m.ghostLift - 11.5).rounded(), width: w, height: 23)
        let titleRight = (pip.isHidden ? close.frame.minX : pip.frame.minX) - 4
        titleRow.frame = NSRect(x: 0, y: h - 32.75, width: titleRight, height: 32.75)
        let th = title.intrinsicContentSize.height
        title.frame = NSRect(x: 14.5 - SidebarText.inset, y: (titleRow.bounds.height - m.titleCentreFromTop - th / 2).rounded(),
                             width: max(0, titleRight - 4 - 14.5 + SidebarText.inset), height: th)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // The title row is above the visible part of a resting card.
        guard frame.contains(point) else { return nil }
        return super.hitTest(point)
    }
}

/// The tab's favicon on the card ("Back to Tab"); a click goes back to the tab.
final class NowPlayingIconView: NSView {
    private let imageView = NSImageView()
    var onClick: () -> Void = {}
    var placeholder = NSColor.white.withAlphaComponent(0.14) { didSet { refresh() } }
    var image: NSImage? { didSet { imageView.image = image; refresh() } }

    override init(frame: NSRect) {
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        wantsLayer = true
        layer?.cornerRadius = 3
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.frame = bounds
        imageView.autoresizingMask = [.width, .height]
        addSubview(imageView)
        refresh()
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    private func refresh() { layer?.backgroundColor = image == nil ? placeholder.cgColor : nil }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

/// Arc's tab volume slider: a 6 pt rounded track 8 pt in from the card's sides, filled up to a
/// 20 × 16 pt pill knob (the theme's light tint on dark cards, its deep shade on light ones).
final class NowPlayingVolumeSlider: NSView {
    var colors = NowPlayingColors(themeColor: nil, dark: true) { didSet { needsDisplay = true } }
    var value = 1.0 { didSet { if value != oldValue { needsDisplay = true } } }
    var onChange: (Double) -> Void = { _ in }
    private(set) var isTracking = false
    private static let knob = NSSize(width: 20, height: 16)

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let k = Self.knob
        let track = NSRect(x: 0, y: (bounds.height - 6) / 2, width: bounds.width, height: 6)
        colors.trackEmpty.setFill()
        NSBezierPath(roundedRect: track, xRadius: 3, yRadius: 3).fill()
        let knobX = (bounds.width - k.width) * value
        colors.trackFilled.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: track.minY, width: knobX + k.width / 2, height: 6), xRadius: 3, yRadius: 3).fill()
        let knob = NSBezierPath(roundedRect: NSRect(x: knobX, y: (bounds.height - k.height) / 2, width: k.width, height: k.height),
                                xRadius: k.height / 2, yRadius: k.height / 2)
        NSGraphicsContext.saveGraphicsState()
        if !colors.isDark {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 3
            shadow.shadowOffset = NSSize(width: 0, height: -0.5)
            shadow.set()
        }
        colors.knob.setFill()
        knob.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func set(from event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        value = max(0, min(1, (p.x - Self.knob.width / 2) / max(1, bounds.width - Self.knob.width)))
        onChange(value)
    }

    override func mouseDown(with event: NSEvent) { isTracking = true; set(from: event) }
    override func mouseDragged(with event: NSEvent) { set(from: event) }
    override func mouseUp(with event: NSEvent) { set(from: event); isTracking = false }
}

/// Inert pictures of a card's controls, for the faint row a resting back card shows.
final class NowPlayingGhostRow: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(from controls: [NSView]) {
        subviews.forEach { $0.removeFromSuperview() }
        for v in controls {
            guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
            v.cacheDisplay(in: v.bounds, to: rep)
            let image = NSImage(size: v.bounds.size)
            image.addRepresentation(rep)
            let iv = NSImageView(image: image)
            iv.frame = NSRect(x: v.frame.minX, y: 0, width: v.frame.width, height: v.frame.height)
            addSubview(iv)
        }
    }
}
