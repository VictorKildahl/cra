import AppKit

/// Discussion #761, Settings ▸ Tabs ▸ "Player with artwork" (NowPlayingStyle.island), not in Arc: the player as
/// a slim bar with the artwork, after Yab's (yetanotherbrowser/yab, Apache-2.0, PlayerBand.swift; drawn here from
/// its measurements, none of its code), in Arc's card's own colours (NowPlayingColors: its fill, which "Player in
/// the space's colour" also sets, its title and glyph colours) where Yab tints glass with the cover, and with the
/// sidebar's own corners: a tab
/// row's 10 pt (CraMetrics.rowCorner) where Yab's is a capsule, the artwork's 6 pt inside it, and the sidebar's
/// 7 pt hover squares on the buttons (Victor, 26 Nov 2026). At rest, 30 pt tall: the artwork, 22 pt, 4 pt in, the title and artist on one line from 34 pt, fading out where they don't fit, and four
/// level bars in the player's glyph colour 6 pt from the right end (a play glyph while paused; pause on hover). Hovering
/// opens it upward to 144 pt with Arc's own motion (0.2 s, its ease-out, no spring): 48 pt artwork 12 pt in, the title (13.5 pt
/// semibold) and artist, a 5 pt progress bar to drag with the times under it, and previous · play · next (15-second
/// skips when the page has no tracks) between the tab's icon and the volume button. Arc's close, Picture in Picture
/// and volume drawer stay (Victor, 26 Nov 2026), and so does Arc's stack for several players. In a sidebar too
/// narrow for that (under 220 pt of card) the open card stacks and its buttons row gives way (openLayout). It sits 8 pt in from
/// the sidebar's sides like Arc's cards: Yab's 3 pt was reported as cramped (its #312, #918).
enum NowPlayingIslandMetrics {
    static let collapsedHeight: CGFloat = 30
    static let expandedHeight: CGFloat = 144
    /// A tab row's corners, at rest and open alike.
    static let corner: CGFloat = CraMetrics.rowCorner
    /// The artwork's, concentric with the card's at rest (10 − 4 pt in).
    static let coverCorner: CGFloat = 6
    static let cover: CGFloat = 22
    static let coverInset: CGFloat = 4
    static let textLeading: CGFloat = 34
    static let padding: CGFloat = 12
    static let barRowCentreFromBottom: CGFloat = 26

    /// How the tray stacks and moves these cards (NowPlayingTrayLayout).
    /// Arc's motion, not Yab's spring (Victor, 26 Nov 2026): open at once on hover, 0.2 s on Arc's ease-out both
    /// ways, and the open card as tall as its width needs (NowPlayingIsland.openLayout).
    static let tray = NowPlayingTrayLayout(collapsedHeight: collapsedHeight, expandedHeight: expandedHeight, drawerHeight: 33,
                                           gap: 6, peek: 6, peekInset: 5, inset: 8, ghostRow: false,
                                           openDuration: 0.2, openCurve: (0.15, 0.85, 0.3, 1), closeDuration: 0.2,
                                           closeCurve: (0.15, 0.85, 0.3, 1), hoverDelay: 0,
                                           openHeight: { CGFloat(NowPlayingIsland.openLayout(width: Double($0)).height) })
}

@MainActor
final class NowPlayingIslandCardView: NSView, NowPlayingCard {
    private typealias M = NowPlayingIslandMetrics
    private let rest = NSView()
    private let restCover = NowPlayingCoverView(radius: M.coverCorner)
    private let line = NSTextField(labelWithString: "")
    private let lineMask = CAGradientLayer()
    private let lineBox = NSView()
    private let end = NowPlayingIslandEndButton()
    private let open = IslandFlippedView()
    private let cover = NowPlayingCoverView(radius: M.coverCorner)
    private let title = NSTextField.sidebarLabel(size: 13.5, weight: .semibold)
    private let artist = NSTextField.sidebarLabel(size: 12)
    private let scrubber = NowPlayingIslandScrubber()
    private let elapsed = NSTextField(labelWithString: "")
    private let remaining = NSTextField(labelWithString: "")
    private let pip: SidebarGlyphButton
    private let close: SidebarGlyphButton
    private let back: SidebarGlyphButton
    private let leading: SidebarGlyphButton
    private let playPause: SidebarGlyphButton
    private let trailing: SidebarGlyphButton
    private let volume: SidebarGlyphButton
    private let slider = NowPlayingVolumeSlider()
    private let perform: (NowPlaying.Action) -> Void
    private var model: NowPlayingCardModel?
    private var transport: (leading: NowPlayingIsland.Transport, trailing: NowPlayingIsland.Transport) = (.previousTrack, .nextTrack)
    private var opened = false
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
        get { rest.isHidden && open.isHidden }
        set {
            rest.isHidden = newValue
            open.isHidden = newValue
        }
    }
    var ghostVisible = false

    init(colors: NowPlayingColors, perform: @escaping (NowPlaying.Action) -> Void) {
        self.colors = colors
        self.perform = perform
        func button(_ symbol: String, _ size: CGFloat, _ iconSize: CGFloat, _ help: String, _ action: @escaping () -> Void) -> SidebarGlyphButton {
            SidebarGlyphButton(symbol: symbol, size: size, height: size, iconSize: iconSize, help: help, colors: colors.buttonColors, action: action)
        }
        var forward: (NowPlaying.Action) -> Void = { _ in }
        pip = button("pip", 24, 12, "Open Picture in Picture") { forward(.pictureInPicture) }
        close = button("xmark", 24, 12, "Close Mini Player") { forward(.dismiss) }
        back = button("globe", 28, 16, "Back to Tab") { forward(.show) }
        leading = button("backward.end.fill", 36, 17, "Previous Track") { forward(.previous) }
        playPause = button("pause.fill", 36, 20, "Pause") { forward(.togglePlayback) }
        trailing = button("forward.end.fill", 36, 17, "Next Track") { forward(.next) }
        volume = button("speaker.wave.3.fill", 28, 13, "Adjust Tab Volume") { forward(.toggleMute) }
        super.init(frame: .zero)
        forward = { [weak self] action in self?.act(action) }
        wantsLayer = true
        layer?.cornerRadius = M.corner
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        // At rest.
        restCover.onClick = { [weak self] in self?.act(.show) }
        line.lineBreakMode = .byClipping
        line.usesSingleLineMode = true
        line.maximumNumberOfLines = 1
        lineBox.wantsLayer = true
        lineMask.startPoint = CGPoint(x: 0, y: 0.5)
        lineMask.endPoint = CGPoint(x: 1, y: 0.5)
        lineBox.addSubview(line)
        lineBox.addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(lineClicked)))
        end.onClick = { [weak self] in self?.act(.togglePlayback) }
        for v in [restCover, lineBox, end] as [NSView] { rest.addSubview(v) }
        addSubview(rest)

        // Open.
        cover.onClick = { [weak self] in self?.act(.show) }
        let titleClick = NSClickGestureRecognizer(target: self, action: #selector(lineClicked))
        title.addGestureRecognizer(titleClick)
        scrubber.onSeek = { [weak self] fraction in
            guard let self, let d = self.model?.media?.duration else { return }
            self.act(.seek(NowPlayingIsland.seekTarget(fraction: fraction, duration: d)))
        }
        for l in [elapsed, remaining] {
            l.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            l.isBordered = false
            l.drawsBackground = false
        }
        remaining.alignment = .right
        slider.isHidden = true
        slider.onChange = { [weak self] v in self?.act(.setVolume(v)) }
        pip.isHidden = true
        for v in [cover, title, artist, scrubber, elapsed, remaining, pip, close, back, leading, playPause, trailing, volume, slider] as [NSView] {
            open.addSubview(v)
        }
        open.alphaValue = 0
        addSubview(open)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func lineClicked() { act(.show) }

    private func act(_ action: NowPlaying.Action) {
        switch action {
        case .previous where transport.leading == .skipBack: perform(.skip(-NowPlayingIsland.skipSeconds))
        case .next where transport.trailing == .skipAhead: perform(.skip(NowPlayingIsland.skipSeconds))
        default: perform(action)
        }
    }

    // MARK: Colour

    /// Arc's card colours throughout: its fill, the title's white 81 % / black 85 %, and the glyphs' 66 % / 50 %
    /// for the artist, the times, the buttons and the level bars.
    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = colors.fill.cgColor
        CATransaction.commit()
        refreshLine()
        title.textColor = colors.title
        artist.textColor = colors.foreground
        elapsed.textColor = colors.foreground
        remaining.textColor = colors.foreground
        restCover.placeholder = colors.placeholder
        cover.placeholder = colors.placeholder
        end.colors = (bars: colors.foreground, ink: colors.foreground, hover: colors.hover)
        scrubber.colors = (track: colors.trackEmpty, fill: colors.trackFilled)
        slider.colors = colors
        for b in [pip, close, back, playPause, volume] {
            b.colors = colors.buttonColors
            b.tint = colors.foreground
        }
        refreshTransport()
    }

    private func refreshLine() {
        let s = NSMutableAttributedString(string: NowPlayingIsland.title(model?.media, tabTitle: model?.title ?? ""),
                                          attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: colors.title])
        if let a = model?.media?.artist, !a.isEmpty {
            s.append(NSAttributedString(string: "  " + a, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: colors.foreground]))
        }
        line.attributedStringValue = s
        needsLayout = true
    }

    // MARK: Model

    func apply(_ m: NowPlayingCardModel) {
        guard m != model else { return }
        let old = model
        model = m
        let name = NowPlayingIsland.title(m.media, tabTitle: m.title)
        title.stringValue = name
        artist.stringValue = m.media?.artist ?? ""
        restCover.image = m.artwork
        restCover.fallback = m.icon
        cover.image = m.artwork
        cover.fallback = m.icon
        back.setGlyph(m.icon.map(Self.iconImage) ?? SidebarSymbols.image("globe", size: 14, weight: .medium), help: "Back to Tab")
        restCover.alphaValue = m.playing ? 1 : 0.55
        end.playing = m.playing
        if old?.playing != m.playing {
            playPause.setSymbol(m.playing ? "pause.fill" : "play.fill", iconSize: 20, help: m.playing ? "Pause" : "Play")
        }
        if old.map({ $0.muted != m.muted || $0.volume != m.volume }) ?? true {
            let symbol = m.muted ? "speaker.slash.fill" : m.volume <= 0 ? "speaker.fill" : m.volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.3.fill"
            volume.setSymbol(symbol, iconSize: 13, help: "Adjust Tab Volume")
        }
        if !slider.isTracking { slider.value = m.volume }
        pip.isHidden = !m.hasVideo
        applyColors()
        tick(now: Date().timeIntervalSinceReferenceDate)
        needsLayout = true
    }

    /// The tab's icon drawn 16 pt with Yab's 5 pt corners, for the back-to-tab button.
    private static func iconImage(_ icon: NSImage) -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in
            NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).addClip()
            icon.draw(in: r)
            return true
        }
    }

    private func refreshTransport() {
        guard let m = model else { return }
        transport = NowPlayingIsland.transport(hasPrevious: m.hasPrevious, hasNext: m.hasNext, canSeek: NowPlayingIsland.canSeek(m.media))
        func show(_ b: SidebarGlyphButton, _ t: NowPlayingIsland.Transport, enabled: Bool) {
            switch t {
            case .skipBack: b.setSymbol("gobackward.15", iconSize: 18, help: "Back 15 Seconds")
            case .skipAhead: b.setSymbol("goforward.15", iconSize: 18, help: "Ahead 15 Seconds")
            case .previousTrack: b.setSymbol("backward.end.fill", iconSize: 16, help: enabled ? "Previous Track" : "")
            case .nextTrack: b.setSymbol("forward.end.fill", iconSize: 16, help: enabled ? "Next Track" : "")
            }
            b.colors = colors.buttonColors
            b.enabled = enabled
            b.tint = enabled ? colors.foreground : colors.disabled
        }
        show(leading, transport.leading, enabled: transport.leading == .skipBack || m.hasPrevious)
        show(trailing, transport.trailing, enabled: transport.trailing == .skipAhead || m.hasNext)
    }

    /// The progress row from the clock, moved on to `now` (the tray ticks it while the card is open).
    func tick(now: TimeInterval) {
        switch NowPlayingIsland.progress(model?.clock, at: now) {
        case .hidden:
            scrubber.isHidden = true
            elapsed.isHidden = true
            remaining.isHidden = true
        case .live:
            scrubber.isHidden = true
            elapsed.isHidden = false
            remaining.isHidden = true
            elapsed.stringValue = "Live"
        case .times(let e, let r, let fraction):
            scrubber.isHidden = false
            elapsed.isHidden = false
            remaining.isHidden = false
            elapsed.stringValue = e
            remaining.stringValue = r
            scrubber.fraction = fraction
        }
    }

    // MARK: Open and rest

    /// The tray opened or folded the stack: the rest row fades out as the shape grows, then the open card's
    /// parts come in; folding, they go first.
    func setOpened(_ open: Bool, animated: Bool) {
        guard open != opened else { return }
        opened = open
        guard animated, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            rest.alphaValue = open ? 0 : 1
            self.open.alphaValue = open ? 1 : 0
            return
        }
        // One crossfade with the shape's 0.2 s, as Arc's title row fades in and out.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.15, 0.85, 0.3, 1)
            rest.animator().alphaValue = open ? 0 : 1
            self.open.animator().alphaValue = open ? 1 : 0
        }
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let w = bounds.width
        rest.frame = NSRect(x: 0, y: 0, width: w, height: M.collapsedHeight)
        restCover.frame = NSRect(x: M.coverInset, y: M.coverInset, width: M.cover, height: M.cover)
        end.frame = NSRect(x: w - 6 - 22, y: 4, width: 22, height: 22)
        let lineRight = end.frame.minX - 4
        lineBox.frame = NSRect(x: M.textLeading, y: 0, width: max(0, lineRight - M.textLeading), height: M.collapsedHeight)
        let lh = line.intrinsicContentSize.height
        line.frame = NSRect(x: -SidebarText.inset, y: ((M.collapsedHeight - lh) / 2).rounded(), width: max(lineBox.bounds.width, line.intrinsicContentSize.width) + 4, height: lh)
        let overflows = line.intrinsicContentSize.width > lineBox.bounds.width
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        lineMask.frame = lineBox.bounds
        let fade = lineBox.bounds.width > 0 ? max(0, 1 - 22 / lineBox.bounds.width) : 1
        lineMask.colors = [NSColor.black.cgColor, NSColor.black.cgColor, NSColor.black.withAlphaComponent(overflows ? 0 : 1).cgColor]
        lineMask.locations = [0, NSNumber(value: fade), 1]
        lineBox.layer?.mask = lineMask
        CATransaction.commit()

        // The open card, top down, pinned to the card's bottom with the drawer under the buttons; laid out for
        // its width (NowPlayingIsland.openLayout): narrower than 220 pt the title goes under the artwork.
        let fit = NowPlayingIsland.openLayout(width: Double(w))
        let full = CGFloat(fit.height)
        let drawer = drawerOpen ? NowPlayingIslandMetrics.tray.drawerHeight : 0
        open.frame = NSRect(x: 0, y: 0, width: w, height: full + drawer)
        let p = M.padding, art = CGFloat(fit.cover)
        cover.frame = NSRect(x: p, y: p, width: art, height: art)
        close.frame = NSRect(x: w - 8 - 24, y: 9, width: 24, height: 24)
        pip.frame = NSRect(x: close.frame.minX - 26, y: 9, width: 24, height: 24)
        let th = title.intrinsicContentSize.height, ah = artist.intrinsicContentSize.height
        let textX: CGFloat, textTop: CGFloat, textRight: CGFloat
        if fit.stacked {
            textX = p - SidebarText.inset
            textTop = p + art + 7
            textRight = w - p
        } else {
            textX = p + art + p - SidebarText.inset
            textTop = 15
            textRight = (pip.isHidden ? close.frame.minX : pip.frame.minX) - 4
        }
        title.frame = NSRect(x: textX, y: textTop, width: max(0, textRight - textX), height: th)
        artist.frame = NSRect(x: textX, y: textTop + th + 1, width: max(0, textRight - textX), height: ah)
        let scrubTop = fit.stacked ? textTop + th + ah + 4 : 66
        scrubber.frame = NSRect(x: p, y: scrubTop, width: w - 2 * p, height: 19)
        let eh = elapsed.intrinsicContentSize.height
        elapsed.frame = NSRect(x: p - SidebarText.inset, y: scrubTop + 20, width: (w - 2 * p) / 2, height: eh)
        remaining.frame = NSRect(x: w / 2, y: scrubTop + 20, width: (w - 2 * p) / 2 + SidebarText.inset, height: eh)
        let row = full - M.barRowCentreFromBottom
        back.isHidden = !fit.showsBack
        volume.isHidden = !fit.showsVolume
        back.frame = NSRect(x: 10, y: row - 14, width: 28, height: 28)
        volume.frame = NSRect(x: w - 10 - 28, y: row - 14, width: 28, height: 28)
        let size = CGFloat(fit.button)
        for (i, b) in [leading, playPause, trailing].enumerated() {
            let cx = CGFloat(fit.transportCentre) + CGFloat(i - 1) * CGFloat(fit.pitch)
            b.frame = NSRect(x: (cx - size / 2).rounded(), y: (row - size / 2).rounded(), width: size, height: size)
        }
        if drawerOpen { slider.frame = NSRect(x: 8, y: full + 6.5, width: w - 16, height: 20) }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        let p = convert(point, from: superview)
        // At rest only the rest row answers; the open card's controls under it are faded out.
        if !opened, rest.frame.contains(p), !rest.isHidden { return rest.hitTest(convert(p, to: rest.superview)) ?? self }
        return super.hitTest(point)
    }

    /// cra://debug's readout of the card: what it shows and its colour.
    var debugReadout: String {
        let left = transport.leading, right = transport.trailing
        return "island h=\(Int(frame.height.rounded())) open=\(opened ? 1 : 0) line=\"\(line.stringValue)\" art=\(model?.artwork.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "none") fill=\(colors.fillHex) times=\(elapsed.isHidden ? "-" : elapsed.stringValue)/\(remaining.isHidden ? "-" : remaining.stringValue) buttons=\(left)/\(right)"
    }
}

/// The open card's contents are placed top down.
private final class IslandFlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The artwork, cropped to fill its 6 pt rounded square. Without artwork, the site's
/// icon on a plate of ink at 12 % (Yab's plate). A click goes back to the tab.
final class NowPlayingCoverView: NSView {
    var onClick: () -> Void = {}
    var placeholder = NSColor.white.withAlphaComponent(0.12) { didSet { refresh() } }
    var image: NSImage? { didSet { if image !== oldValue { refresh() } } }
    var fallback: NSImage? { didSet { if fallback !== oldValue { refresh() } } }
    private let iconLayer = CALayer()

    init(radius: CGFloat) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = radius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.contentsGravity = .resizeAspectFill
        iconLayer.contentsGravity = .resizeAspect
        iconLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(iconLayer)
        _ = ArcTooltipAnchorView.attach(to: self, help: "Back to Tab")
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        layer?.backgroundColor = image == nil ? placeholder.cgColor : nil
        iconLayer.contents = image == nil ? fallback : nil
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        let s = min(16, bounds.width * 0.6)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        iconLayer.frame = NSRect(x: (bounds.width - s) / 2, y: (bounds.height - s) / 2, width: s, height: s)
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

/// The resting island's right end: the level bars while it plays (pause on hover, on the player's hover fill), a
/// play glyph while paused. A click plays or pauses without opening the card.
final class NowPlayingIslandEndButton: NSView {
    var onClick: () -> Void = {}
    var playing = false { didSet { if playing != oldValue { refresh() } } }
    var colors: (bars: NSColor, ink: NSColor, hover: NSColor) = (.white, .white, .clear) { didSet { refresh() } }
    private let bars = NowPlayingBarsView()
    private let glyph = NSImageView()
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }
    private var tip: ArcTooltipAnchorView?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6
        tip = ArcTooltipAnchorView.attach(to: self, help: "Play")
        glyph.imageScaling = .scaleNone
        addSubview(bars)
        addSubview(glyph)
        refresh()
    }

    convenience init() { self.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22)) }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }

    private func refresh() {
        let showsGlyph = !playing || hovering
        bars.isHidden = showsGlyph
        bars.playing = playing
        bars.color = colors.bars
        glyph.isHidden = !showsGlyph
        glyph.image = SidebarSymbols.image(playing ? "pause.fill" : "play.fill", size: 11, weight: .semibold)
        glyph.contentTintColor = colors.ink
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = hovering ? colors.hover.cgColor : nil
        CATransaction.commit()
        tip?.text = playing ? "Pause" : "Play"
        needsLayout = true
    }

    override func layout() {
        super.layout()
        bars.frame = NSRect(x: (bounds.width - 15) / 2, y: (bounds.height - 11) / 2, width: 15, height: 11)
        glyph.frame = bounds
    }
}

/// Four level bars, 2.4 pt wide on a 4.2 pt pitch, each running through its own heights (1.1 s + 0.17 s a bar,
/// as Yab's) while it plays, and dropped to dots while paused or with Reduce Motion held still.
final class NowPlayingBarsView: NSView {
    var color = NSColor.white { didSet { refreshColor() } }
    var playing = false { didSet { if playing != oldValue { refreshMotion() } } }
    private var bars: [CALayer] = []
    private static let heights: [[CGFloat]] = [[0.35, 1, 0.55, 0.85, 0.4], [0.8, 0.45, 1, 0.3, 0.7], [0.5, 0.9, 0.35, 0.65, 1], [0.95, 0.4, 0.75, 0.5, 0.6]]

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for _ in 0..<4 {
            let b = CALayer()
            b.anchorPoint = CGPoint(x: 0.5, y: 0)
            b.cornerRadius = 1.2
            b.actions = ["bounds": NSNull(), "position": NSNull(), "backgroundColor": NSNull()]
            layer?.addSublayer(b)
            bars.append(b)
        }
        refreshColor()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refreshColor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for b in bars { b.backgroundColor = color.cgColor }
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        refreshMotion()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshMotion()
    }

    private func refreshMotion() {
        let h = bounds.height
        let still = !playing || window == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, b) in bars.enumerated() {
            let resting = playing ? h * Self.heights[i][0] : 2.4
            b.bounds = CGRect(x: 0, y: 0, width: 2.4, height: max(2.4, resting))
            b.position = CGPoint(x: 1.2 + CGFloat(i) * 4.2, y: 0)
            b.removeAnimation(forKey: "level")
            guard !still else { continue }
            let a = CAKeyframeAnimation(keyPath: "bounds.size.height")
            a.values = (Self.heights[i] + [Self.heights[i][0]]).map { max(2.4, h * $0) }
            a.duration = 1.1 + 0.17 * Double(i)
            a.repeatCount = .infinity
            a.calculationMode = .cubic
            b.add(a, forKey: "level")
        }
        CATransaction.commit()
    }
}

/// The open island's progress bar: a 5 pt capsule (ink 12 %, filled to where it is at 78 %), dragged or
/// clicked anywhere within 7 pt above and below it to seek; the seek goes out when the press ends.
final class NowPlayingIslandScrubber: NSView {
    var colors: (track: NSColor, fill: NSColor) = (.clear, .clear) { didSet { needsDisplay = true } }
    var fraction: Double = 0 { didSet { if dragging == nil, fraction != oldValue { needsDisplay = true } } }
    var onSeek: (Double) -> Void = { _ in }
    private var dragging: Double?

    override var mouseDownCanMoveWindow: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let track = NSRect(x: 0, y: (bounds.height - 5) / 2, width: bounds.width, height: 5)
        colors.track.setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
        let f = min(1, max(0, dragging ?? fraction))
        guard f > 0 else { return }
        colors.fill.setFill()
        NSBezierPath(roundedRect: NSRect(x: 0, y: track.minY, width: max(5, track.width * f), height: 5), xRadius: 2.5, yRadius: 2.5).fill()
    }

    private func drag(_ event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragging = bounds.width > 0 ? Double(min(max(0, p.x / bounds.width), 1)) : 0
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) { drag(event) }
    override func mouseDragged(with event: NSEvent) { drag(event) }
    override func mouseUp(with event: NSEvent) {
        drag(event)
        if let d = dragging {
            fraction = d
            onSeek(d)
        }
        dragging = nil
        needsDisplay = true
    }
}
