import AppKit
import CraCore
import QuartzCore

/// 5-Second Previews: the card over a hovered link (Arc's HoverCardWindow). A hover on one of
/// Arc's links (LinkSummaryPolicy.autoHovers) opens it after a short rest; Shift opens it at once
/// on any link. It goes when the pointer leaves the link and the card, on a click, a key or Escape.
@MainActor
final class LinkSummaryPreviewController {
    static let shared = LinkSummaryPreviewController()

    /// How long the pointer rests on a link before a hover alone fetches its page. Arc's own rest
    /// isn't readable (hoverCardsLLMDelayInterval is a remote flag); its first card on Hacker News
    /// came 4.1 s after the hover, most of it the page loading, so the rest here only keeps links
    /// the pointer passes over from being fetched.
    static let restBeforeFetch: Duration = .milliseconds(500)
    /// The pointer may cross the gap between the link and the card.
    static let leaveGrace: Duration = .milliseconds(300)

    /// What the window controller knows about a hovered link.
    struct Hover {
        var link: URL
        var page: URL?
        weak var window: NSWindow?
        var profilePath: String?
        var httpsOnly: Bool
        var theme: SpaceTheme
        /// The link's frame on screen, from the page (nil when the page can't say).
        var locate: (@escaping @MainActor (NSRect?) -> Void) -> Void
    }

    private var hover: Hover?
    private var shown: URL?
    private var panel: LinkSummaryPanel?
    private var pending: Task<Void, Never>?
    private var loading: Task<Void, Never>?
    private var leaving: Task<Void, Never>?
    private var monitors: [Any] = []

    private init() {}

    /// The status bubble's text changed: a link's URL, or "" when the pointer left it. `hover` is nil
    /// when the feature is off or the link can't be previewed.
    func linkHoverChanged(_ new: Hover?) {
        guard let new else {
            hover = nil
            pending?.cancel()
            if panel?.isVisible == true { leaveSoon() } else { stop() }
            return
        }
        installMonitors()
        leaving?.cancel()
        if new.link == hover?.link { return }
        hover = new
        pending?.cancel()
        if shown != nil, shown != new.link { hide() }
        if NSEvent.modifierFlags.contains(.shift) || LinkSummaryPolicy.autoHovers(link: new.link, page: new.page) {
            start(after: NSEvent.modifierFlags.contains(.shift) ? .zero : Self.restBeforeFetch)
        }
    }

    private func start(after rest: Duration) {
        guard let hover, shown != hover.link else { return }
        pending = Task { @MainActor [weak self] in
            if rest > .zero { try? await Task.sleep(for: rest) }
            guard !Task.isCancelled, let self, let h = self.hover, h.link == hover.link else { return }
            self.open(h)
        }
    }

    private func open(_ h: Hover) {
        loading?.cancel()
        shown = h.link
        if let card = LinkSummaryService.shared.cached(h.link) {
            present(card, for: h)
            return
        }
        let query = LinkSummaryPolicy.searchQuery(page: h.page)
        loading = Task { @MainActor [weak self] in
            await LinkSummaryService.shared.load(link: h.link, profilePath: h.profilePath, httpsOnly: h.httpsOnly, searchQuery: query) { card in
                guard let self, self.shown == h.link else { return }
                self.present(card, for: h)
            }
        }
    }

    private func present(_ card: LinkSummaryService.Card, for h: Hover) {
        guard let parent = h.window, parent.isVisible else { return }
        let p = panel ?? LinkSummaryPanel()
        panel = p
        p.cardView.show(card, theme: h.theme)
        let size = p.cardView.fittingCardSize()
        if p.isOpen, p.parent === parent {
            p.resize(to: size)
            return
        }
        let pointer = NSEvent.mouseLocation
        h.locate { [weak self, weak parent] rect in
            guard let self, let parent, self.shown == h.link else { return }
            let screen = (parent.screen ?? NSScreen.main)?.visibleFrame ?? parent.frame
            let origin = LinkSummaryCardLayout.origin(size: size, link: rect, pointer: pointer, screen: screen)
            p.open(at: NSRect(origin: origin, size: p.cardView.fittingCardSize()), over: parent)
        }
    }

    /// The pointer left the link: the card stays while the pointer is on it.
    private func leaveSoon() {
        leaving?.cancel()
        leaving = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.leaveGrace)
            guard !Task.isCancelled, let self, self.hover == nil, self.panel?.containsPointer != true else { return }
            self.stop()
        }
    }

    func pointerLeftCard() {
        if hover == nil { leaveSoon() }
    }

    /// Closes the card and forgets the hover.
    func stop() {
        hover = nil
        pending?.cancel()
        leaving?.cancel()
        hide()
    }

    private func hide() {
        loading?.cancel()
        loading = nil
        shown = nil
        panel?.close(animated: true)
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        // Shift pressed on a link opens its card at once (Arc: "hold Shift while hovering").
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            if event.modifierFlags.contains(.shift), let self, self.hover != nil, self.shown == nil {
                self.pending?.cancel()
                self.start(after: .zero)
            }
            return event
        }) { monitors.append(m) }
        // A click outside the card, a key or a scroll closes it.
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel], handler: { [weak self] event in
            guard let self, let panel = self.panel, panel.isOpen else { return event }
            if event.window !== panel { self.stop() }
            return event
        }) { monitors.append(m) }
    }
}

// MARK: - Panel

final class LinkSummaryPanel: NSPanel {
    let cardView = LinkSummaryCardView()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: LinkSummaryCardLayout.width, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        contentView = cardView
    }

    /// Shown and not closing: a card that is fading out opens again from the link.
    private(set) var isOpen = false

    var containsPointer: Bool { isOpen && frame.contains(NSEvent.mouseLocation) }

    /// Arc's card grows in from the link over about 0.27 s (a 60 fps recording).
    func open(at frame: NSRect, over parent: NSWindow) {
        if self.parent !== parent {
            self.parent?.removeChildWindow(self)
            parent.addChildWindow(self, ordered: .above)
        }
        let start = NSRect(x: frame.minX, y: frame.maxY - min(frame.height, LinkSummaryCardLayout.bannerHeight), width: frame.width,
                           height: min(frame.height, LinkSummaryCardLayout.bannerHeight))
        setFrame(start, display: true)
        isOpen = true
        alphaValue = 0
        orderFront(nil)
        invalidateShadow()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.27
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(frame, display: true)
        }
    }

    /// Rows arriving grow the card downward; its top stays under the link.
    func resize(to size: NSSize) {
        guard abs(size.height - frame.height) > 0.5 else { return }
        let target = NSRect(x: frame.minX, y: frame.maxY - size.height, width: size.width, height: size.height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.invalidateShadow() }
        }
    }

    func close(animated: Bool) {
        guard isOpen else { return }
        isOpen = false
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.15 : 0
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen else { return }
                self.parent?.removeChildWindow(self)
                self.orderOut(nil)
            }
        }
    }
}

// MARK: - Card

/// Arc's hover card: the page's picture across the top, the quick summary in bold, then a row per
/// detail with the model's SF Symbol, a bold label and the info, and a share button in the corner.
/// The fill is the space's dark tooltip tone (black mixed with its shaded colour at 30 %) at 90 %:
/// sampled #322c15 over Hacker News in a beige space, where TooltipTones gives #302913.
final class LinkSummaryCardView: NSView {
    private typealias L = LinkSummaryCardLayout
    private let banner = CALayer()
    private let headerTitle = NSTextField(labelWithString: "")
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let empty = NSTextField(labelWithString: "No preview available")
    private var rows: [(icon: NSImageView, text: NSTextField)] = []
    private var skeleton: [CALayer] = []
    private let share = LinkSummaryShareButton()
    private var link: URL?
    private var tracking: NSTrackingArea?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = L.cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        banner.contentsGravity = .resizeAspectFill
        banner.masksToBounds = true
        layer?.addSublayer(banner)
        for label in [headerTitle, summary, empty] {
            label.isSelectable = false
            label.textColor = .white
            addSubview(label)
        }
        headerTitle.font = .systemFont(ofSize: 13, weight: .semibold)
        headerTitle.lineBreakMode = .byTruncatingTail
        summary.font = .systemFont(ofSize: 13, weight: .bold)
        summary.maximumNumberOfLines = 2
        summary.preferredMaxLayoutWidth = L.width - 2 * L.margin
        empty.font = .systemFont(ofSize: 13, weight: .medium)
        empty.textColor = NSColor.white.withAlphaComponent(0.55)
        share.onPress = { [weak self] in self?.shareLink() }
        addSubview(share)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ card: LinkSummaryService.Card, theme: SpaceTheme) {
        link = card.result.flatMap { URL(string: $0.url) } ?? link
        let tones = TooltipTones(theme: theme)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = NSColor(srgbRed: tones.fill.r, green: tones.fill.g, blue: tones.fill.b, alpha: 0.9).cgColor
        banner.contents = card.image
        banner.isHidden = card.image == nil
        CATransaction.commit()
        headerTitle.stringValue = card.title
        headerTitle.isHidden = card.image != nil
        let result = card.result
        summary.stringValue = result?.quickSummary ?? ""
        summary.isHidden = summary.stringValue.isEmpty
        empty.isHidden = !(card.finished && result == nil)
        setRows(result?.details ?? [])
        setSkeleton(!card.finished && (result?.details.isEmpty ?? true))
        share.isHidden = !card.finished || result == nil
        needsLayout = true
    }

    private func setRows(_ details: [LinkSummaryResult.Detail]) {
        while rows.count > details.count {
            let r = rows.removeLast()
            r.icon.removeFromSuperview()
            r.text.removeFromSuperview()
        }
        while rows.count < details.count {
            let icon = NSImageView()
            icon.imageScaling = .scaleNone
            icon.contentTintColor = NSColor.white.withAlphaComponent(0.4)
            let text = NSTextField(wrappingLabelWithString: "")
            text.isSelectable = false
            text.maximumNumberOfLines = 3
            text.preferredMaxLayoutWidth = L.width - L.rowIndent - L.margin
            addSubview(icon)
            addSubview(text)
            rows.append((icon, text))
        }
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = L.lineHeight
        para.maximumLineHeight = L.lineHeight
        for (row, d) in zip(rows, details) {
            let symbol = NSImage(systemSymbolName: d.icon, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)
            row.icon.image = symbol?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            let s = NSMutableAttributedString()
            if !d.label.isEmpty {
                s.append(NSAttributedString(string: d.label + ": ", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .bold)]))
            }
            s.append(NSAttributedString(string: d.info, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
            s.addAttributes([.foregroundColor: NSColor.white, .paragraphStyle: para], range: NSRange(location: 0, length: s.length))
            row.text.attributedStringValue = s
        }
    }

    /// Grey bars where the rows will be, pulsing while the model answers (Arc's loading rows).
    private func setSkeleton(_ on: Bool) {
        guard on != !skeleton.isEmpty else { return }
        skeleton.forEach { $0.removeFromSuperlayer() }
        skeleton = []
        guard on else { return }
        for _ in 0..<3 {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.12).cgColor
            bar.cornerRadius = 4
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = 0.4
            pulse.duration = 0.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            bar.add(pulse, forKey: "pulse")
            layer?.addSublayer(bar)
            skeleton.append(bar)
        }
    }

    /// Lays the card out from the top and returns its height.
    @discardableResult
    private func place() -> CGFloat {
        let w = L.width
        var y: CGFloat = 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if !banner.isHidden {
            banner.frame = CGRect(x: 0, y: 0, width: w, height: L.bannerHeight)
            y = L.bannerHeight
        } else {
            headerTitle.frame = NSRect(x: L.margin, y: 12, width: w - 2 * L.margin, height: 17)
            y = 29
        }
        y += 12
        if !summary.isHidden {
            let h = summary.fittingSize.height
            summary.frame = NSRect(x: L.margin, y: y, width: w - 2 * L.margin, height: h)
            y += h + L.rowGap
        }
        if !empty.isHidden {
            empty.frame = NSRect(x: L.margin, y: y, width: w - 2 * L.margin, height: 17)
            y += 17 + 12
        }
        for row in rows {
            let h = max(L.lineHeight, row.text.fittingSize.height)
            row.icon.frame = NSRect(x: L.margin, y: y, width: 18, height: L.lineHeight)
            row.text.frame = NSRect(x: L.rowIndent, y: y, width: w - L.rowIndent - L.margin, height: h)
            y += h + L.rowGap
        }
        for (i, bar) in skeleton.enumerated() {
            bar.frame = CGRect(x: L.margin, y: y + 5, width: [240, 210, 160][i], height: 8)
            y += L.lineHeight + L.rowGap
        }
        CATransaction.commit()
        let height = (y - L.rowGap + (share.isHidden ? L.margin : L.bottomInset)).rounded()
        share.frame = NSRect(x: w - 24 - L.shareButton / 2, y: height - 25 - L.shareButton / 2, width: L.shareButton, height: L.shareButton)
        return height
    }

    func fittingCardSize() -> NSSize { NSSize(width: L.width, height: place()) }

    override func layout() {
        super.layout()
        place()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        tracking.map(removeTrackingArea)
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseExited(with event: NSEvent) {
        LinkSummaryPreviewController.shared.pointerLeftCard()
    }

    private func shareLink() {
        guard let link else { return }
        NSSharingServicePicker(items: [link]).show(relativeTo: share.bounds, of: share, preferredEdge: .minY)
    }
}

/// Arc's share button: a 32 pt dark circle with the share glyph.
final class LinkSummaryShareButton: NSView {
    var onPress: (() -> Void)?
    private let glyph = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        // Arc's: a grey lighter than the card, with a faint rim (2x capture).
        layer?.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        layer?.borderWidth = 0.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.3
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -1)
        glyph.contentsGravity = .center
        layer?.addSublayer(glyph)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.cornerRadius = bounds.height / 2
        glyph.frame = bounds
        let scale = window?.backingScaleFactor ?? 2
        glyph.contentsScale = scale
        // Drawn at the symbol's own size (13 pt, as Arc's measures), centred by the layer.
        let ink = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular).applying(.init(paletteColors: [NSColor(white: 0.9, alpha: 1)]))
        let symbol = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")?.withSymbolConfiguration(ink)
        var rect = NSRect(origin: .zero, size: symbol?.size ?? .zero)
        glyph.contents = symbol?.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
        CATransaction.commit()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
}
