import AppKit
import SwiftUI

/// Arc's Peek card bar (1.171, 3 Nov 2026): the page card's own 32 pt toolbar, not Little Arc's
/// strip. Back, forward and refresh from the card's edge as on a browser window's bar, the
/// address centred with its copy-link glyph, in the page's colour (white until it reports one).
@MainActor
final class PeekBarView: NSView {
    var onBack: () -> Void = {}
    var onForward: () -> Void = {}
    var onReload: () -> Void = {}
    var onEditURL: () -> Void = {}
    var onCopy: () -> Void = {}

    private let state: LittleWindowState
    private let back = ToolbarGlyphButton()
    private let forward = ToolbarGlyphButton()
    private let reload = ToolbarGlyphButton()
    private let url = ToolbarURLButton()

    init(state: LittleWindowState) {
        self.state = state
        super.init(frame: .zero)
        wantsLayer = true
        for b in [back, forward, reload] { addSubview(b) }
        addSubview(url)
        back.action = { [weak self] in self?.onBack() }
        forward.action = { [weak self] in self?.onForward() }
        reload.action = { [weak self] in self?.onReload() }
        url.action = { [weak self] in self?.onEditURL() }
        url.onCopy = { [weak self] in self?.onCopy() }
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private struct Shown: Equatable {
        var url = "", themeColor = ""
        var canGoBack = false, canGoForward = false, isLoading = false
    }

    private func observe() {
        observeChanges(of: { [weak state] in
            state.map { Shown(url: $0.url, themeColor: $0.themeColor, canGoBack: $0.canGoBack, canGoForward: $0.canGoForward, isLoading: $0.isLoading) }
        }, apply: { [weak self] shown in
            if let shown { self?.apply(shown) }
        })
    }

    /// PaneToolbarView's colours for a page card: the page's report, else white.
    private func apply(_ state: Shown) {
        let hex = ToolbarColor.hex(reported: state.themeColor, remembered: nil)
        let light = (hex.flatMap(HexColor.luminance) ?? 1) > 0.6
        let fill = hex.map { NSColor(hex: $0) } ?? .white
        let fg = light ? NSColor.black.withAlphaComponent(0.8) : NSColor(hex: "#E4E0D4")
        let fgDim = light ? NSColor.black.withAlphaComponent(0.6) : NSColor(hex: "#F0E6CC").withAlphaComponent(0.9)
        let hover = NSColor.white.withAlphaComponent(0.1)
        layer?.backgroundColor = fill.cgColor
        back.configure(symbol: "arrow.left", image: nil, help: "Go Back (⌘[)", enabled: state.canGoBack, width: 37, iconSize: 15, tint: fgDim, hover: hover)
        forward.configure(symbol: "arrow.right", image: nil, help: "Go Forward (⌘])", enabled: state.canGoForward, width: 37, iconSize: 15,
                          tint: fgDim, hover: hover)
        reload.configure(symbol: state.isLoading ? "xmark" : "arrow.clockwise", image: nil, help: "Refresh (⌘R)", enabled: true, width: 37,
                         iconSize: 15, tint: fgDim, hover: hover, animated: true)
        let human = SuggestionEngine.humanURL(state.url)
        let host = AppSettings.siteKey(for: state.url) ?? human
        // Arc's Peek shows the path too ("example.com/peek"), dimmed after the host.
        url.isHidden = state.url.isEmpty
        url.show(host: host, path: human.hasPrefix(host) ? String(human.dropFirst(host.count)) : "", url: state.url, developer: false,
                 fg: fg, fgDim: fgDim, hover: NSColor.white.withAlphaComponent(0.08), copyHover: hover)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        var x: CGFloat = 2.5
        for b in [back, forward, reload] {
            b.iconRowHeight = 26
            b.frame = NSRect(x: x, y: (h - 26) / 2, width: b.width, height: 26)
            x += b.width
        }
        // Centred on the card, clear of the buttons on either side.
        let room = max(0, bounds.width - 2 * (x + 6 + 8))
        let uw = min(url.idealWidth, room)
        url.frame = NSRect(x: (bounds.width - uw) / 2, y: (h - 28) / 2, width: uw, height: 28)
    }
}

/// Close, Expand and Add To Split beside the Peek card (Arc's confirmCloseModal,
/// openInSpaceExpander and openInSplit): round buttons in the space's darkest tone with its light
/// foreground for the glyph, each with Arc's tip.
@MainActor
final class PeekControlsPanel: NSPanel {
    struct Button {
        let symbol: String
        let help: String
        let run: () -> Void
    }

    private let views: [PeekControlButton]

    init(buttons: [Button]) {
        views = buttons.map { PeekControlButton(symbol: $0.symbol, help: $0.help, run: $0.run) }
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        let content = NSView()
        for v in views { content.addSubview(v) }
        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// `frames`: each button's screen frame, top first.
    func place(_ frames: [NSRect], theme: SpaceTheme) {
        let margin: CGFloat = 8  // room for the buttons' shadows
        let all = frames.reduce(NSRect.null) { $0.union($1) }.insetBy(dx: -margin, dy: -margin)
        setFrame(all, display: false)
        let tones = TooltipTones(theme: theme)
        let fill = NSColor(srgbRed: tones.fill.r, green: tones.fill.g, blue: tones.fill.b, alpha: 1)
        let ink = NSColor(LittlePalette.spaceName(theme))
        for (v, f) in zip(views, frames) {
            v.frame = NSRect(x: f.minX - all.minX, y: f.minY - all.minY, width: f.width, height: f.height)
            v.paint(fill: fill, ink: ink)
        }
    }
}

final class PeekControlButton: NSView {
    private let run: () -> Void
    private let glyph = NSImageView()
    private let symbol: String
    private var pressed = false

    init(symbol: String, help: String, run: @escaping () -> Void) {
        self.run = run
        self.symbol = symbol
        super.init(frame: .zero)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        glyph.imageScaling = .scaleNone
        addSubview(glyph)
        _ = ArcTooltipAnchorView.attach(to: self, help: help)
    }

    required init?(coder: NSCoder) { fatalError() }

    func paint(fill: NSColor, ink: NSColor) {
        layer?.backgroundColor = fill.cgColor
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        glyph.image = SidebarSymbols.image(symbol, size: 15, weight: .semibold)
        glyph.contentTintColor = ink
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        glyph.frame = bounds
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        pressed = true
        alphaValue = 0.8
    }
    override func mouseUp(with event: NSEvent) {
        alphaValue = 1
        guard pressed, bounds.contains(convert(event.locationInWindow, from: nil)) else { pressed = false; return }
        pressed = false
        run()
    }
}
