import AppKit
import QuartzCore

/// 5-Second Previews: the card over a hovered link (Arc's HoverCardWindow). After the pointer
/// rests on a link for LinkSummaryPolicy.rest, the page says which link it is and whether it is
/// one of Arc's; LinkSummaryPolicy.kind picks the card. The card opens as a loading card and
/// fills in. It closes as soon as the pointer leaves the link, unless the pointer is on the card.
@MainActor
final class LinkSummaryPreviewController {
    static let shared = LinkSummaryPreviewController()

    /// What the window controller knows about a hovered link.
    struct Hover {
        var link: URL
        var page: URL?
        weak var window: NSWindow?
        var profilePath: String?
        var httpsOnly: Bool
        var theme: SpaceTheme
        /// Shift as the pointer reached the link (Arc: "hold Shift while hovering").
        var shiftHeld: Bool
        var favicon: NSImage?
        /// Asks the page about the link under the pointer: its frame on screen and whether it is
        /// one of Arc's links. Nil when the page can't say (no link there).
        var inspect: (@escaping @MainActor (Inspection?) -> Void) -> Void
    }

    struct Inspection {
        var rect: NSRect?
        var arcLink: Bool
    }

    private var hover: Hover?
    private var shown: URL?
    private var panel: LinkSummaryPanel?
    private var resting: Task<Void, Never>?
    private var loading: Task<Void, Never>?

    private init() {}

    /// The status bubble's text changed: a link's URL, or "" when the pointer left it. `hover` is nil
    /// when the feature is off or the link can't be previewed.
    func linkHoverChanged(_ new: Hover?) {
        guard let new else {
            hover = nil
            resting?.cancel()
            if panel?.containsPointer != true { stop() }
            return
        }
        if new.link == hover?.link { return }
        hover = new
        resting?.cancel()
        if shown != nil { hide() }
        guard LinkSummaryPolicy.mayOpen(page: new.page, shiftHeld: new.shiftHeld) else { return }
        resting = Task { @MainActor [weak self] in
            try? await Task.sleep(for: LinkSummaryPolicy.rest)
            guard !Task.isCancelled, let self, self.hover?.link == new.link else { return }
            new.inspect { [weak self] found in
                guard let self, let found, self.hover?.link == new.link,
                      let kind = LinkSummaryPolicy.kind(link: new.link, page: new.page, shiftHeld: new.shiftHeld, arcLink: found.arcLink)
                else { return }
                self.open(kind, for: new, at: found.rect)
            }
        }
    }

    private func open(_ kind: LinkSummaryPolicy.Kind, for h: Hover, at rect: NSRect?) {
        guard let parent = h.window, parent.isVisible else { return }
        loading?.cancel()
        shown = h.link
        let p = panel ?? LinkSummaryPanel()
        panel = p
        p.anchor = rect
        p.pointer = NSEvent.mouseLocation
        p.cardView.favicon = h.favicon
        let theme = h.theme
        CraLog.note("5-Second Previews: \(kind == .summary ? "answer" : "small") card opens\(rect == nil ? " by the pointer" : "")")
        switch kind {
        case .summary:
            if let card = LinkSummaryService.shared.cached(h.link) {
                p.cardView.show(.summary(card), theme: theme)
                p.open(over: parent)
                return
            }
            p.cardView.show(.loading, theme: theme)
            p.open(over: parent)
            let query = LinkSummaryPolicy.searchQuery(page: h.page)
            loading = Task { @MainActor [weak self, weak p] in
                await LinkSummaryService.shared.load(link: h.link, profilePath: h.profilePath, httpsOnly: h.httpsOnly, searchQuery: query) { card in
                    guard let self, let p, self.shown == h.link else { return }
                    // The loading card stays until the answer starts: the page alone shows nothing new.
                    guard card.result != nil || card.finished else { return }
                    p.cardView.show(.summary(card), theme: theme)
                    p.fit()
                }
            }
        case .link:
            p.cardView.show(.loading, theme: theme)
            p.open(over: parent)
            loading = Task { @MainActor [weak self, weak p] in
                let title = await LinkSummaryService.shared.title(link: h.link, profilePath: h.profilePath, httpsOnly: h.httpsOnly)
                guard !Task.isCancelled, let self, let p, self.shown == h.link else { return }
                p.cardView.show(.link(title: title ?? LinkSummaryPrompt.displayHost(h.link), address: LinkSummaryPolicy.displayAddress(h.link)), theme: theme)
                p.fit()
            }
        }
    }

    /// The pointer left the card; with no link under it either, the card goes.
    func pointerLeftCard() {
        if hover == nil { stop() }
    }

    /// Closes the card and forgets the hover.
    func stop() {
        hover = nil
        resting?.cancel()
        hide()
    }

    private func hide() {
        loading?.cancel()
        loading = nil
        shown = nil
        panel?.closeCard()
    }
}

// MARK: - Panel

final class LinkSummaryPanel: NSPanel {
    private typealias L = LinkSummaryCardLayout
    let cardView = LinkSummaryCardView()
    /// Holds the card and its shadow, so both squash together: a window shadow is drawn once
    /// for the window and stays behind, full size, while the card animates.
    private let shell = LinkSummaryShellView()
    /// Room around the card for its shadow, except on the link's side: the window there would
    /// cover the link, and the pointer on it would leave the link and close the card.
    private static let margin: CGFloat = 20
    private static let linkSideMargin: CGFloat = 2
    private var insets = NSEdgeInsets(top: 2, left: 20, bottom: 20, right: 20)
    /// The link's frame on screen (nil: the card goes by the pointer).
    var anchor: NSRect?
    var pointer: NSPoint = .zero
    /// Shown and not closing: a card that is fading out opens again from the link.
    private(set) var isOpen = false

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: L.width, height: L.loadingHeight),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        ignoresMouseEvents = false
        collectionBehavior = [.fullScreenAuxiliary, .transient, .ignoresCycle]
        let root = NSView()
        root.wantsLayer = true
        shell.wantsLayer = true
        shell.layer?.shadowColor = NSColor.black.cgColor
        shell.layer?.shadowOpacity = 0.3
        shell.layer?.shadowRadius = 10
        shell.layer?.shadowOffset = CGSize(width: 0, height: -4)
        shell.autoresizingMask = [.width, .height]
        cardView.autoresizingMask = [.width, .height]
        shell.addSubview(cardView)
        root.addSubview(shell)
        contentView = root
    }

    /// The card's own frame on screen (the window is larger, for the shadow).
    var cardFrame: NSRect {
        NSRect(x: frame.minX + insets.left, y: frame.minY + insets.bottom,
               width: frame.width - insets.left - insets.right, height: frame.height - insets.top - insets.bottom)
    }

    /// The pointer on the card, or in the gap it crosses from the link to the card.
    var containsPointer: Bool { isOpen && cardFrame.insetBy(dx: -2, dy: -10).contains(NSEvent.mouseLocation) }

    private func targetFrame() -> NSRect {
        let size = cardView.fittingCardSize()
        // The screen the window is on; a window on none (moved off every display) keeps its card
        // around it. NSWindow.screen answers the main screen for such a window.
        let screen = parent.map { w in NSScreen.screens.first { $0.frame.intersects(w.frame) }?.visibleFrame ?? w.frame.insetBy(dx: -2000, dy: -2000) }
            ?? NSScreen.main?.visibleFrame ?? .zero
        let card = NSRect(origin: LinkSummaryCardLayout.origin(size: size, link: anchor, pointer: pointer, screen: screen), size: size)
        let link = anchor ?? NSRect(x: pointer.x, y: pointer.y, width: 0, height: 0)
        let below = card.maxY <= link.minY + 0.5
        insets = NSEdgeInsets(top: below ? Self.linkSideMargin : Self.margin, left: Self.margin,
                              bottom: below ? Self.margin : Self.linkSideMargin, right: Self.margin)
        return NSRect(x: card.minX - insets.left, y: card.minY - insets.bottom,
                      width: card.width + insets.left + insets.right, height: card.height + insets.top + insets.bottom)
    }

    private func layoutShell() {
        let bounds = contentView?.bounds ?? .zero
        shell.frame = NSRect(x: insets.left, y: insets.bottom, width: max(0, bounds.width - insets.left - insets.right),
                             height: max(0, bounds.height - insets.top - insets.bottom))
        cardView.frame = shell.bounds
    }

    /// Whether the card hangs above its link (no room under it): it then grows and squashes
    /// toward its bottom edge, the link's side.
    private var above: Bool { anchor.map { cardFrame.minY >= $0.maxY } ?? false }

    /// Arc's card grows down from its top edge (from about a tenth of its height), opaque after
    /// its first frames.
    func open(over parent: NSWindow) {
        if self.parent !== parent {
            self.parent?.removeChildWindow(self)
            parent.addChildWindow(self, ordered: .above)
        }
        setFrame(targetFrame(), display: true)
        layoutShell()
        isOpen = true
        alphaValue = 1
        orderFront(nil)
        squash(from: 0.1, to: 1, opacity: [0, 1, 1], at: [0, Double(L.openFade / L.openDuration), 1],
               duration: L.openDuration, timing: .easeOut, completion: nil)
    }

    /// New content: the card takes its new height, its link-side edge staying put.
    func fit() {
        guard isOpen else { return }
        let target = targetFrame()
        guard abs(target.height - frame.height) > 0.5 || abs(target.minY - frame.minY) > 0.5 else { return }
        // The shell keeps its margins by autoresizing while the window animates. (An NSWindow
        // setFrame override runs on the animator proxy here, not the window, and crashed.)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.layoutShell() }
        }
    }

    /// Arc's card squashes toward its top edge to about a third, still nearly opaque, and fades
    /// in the last part (60 fps recording: opaque at 0.6 of its height, gone at 0.14 s).
    func closeCard() {
        guard isOpen else { return }
        isOpen = false
        squash(from: 1, to: L.closeScale, opacity: [1, 1, 0], at: [0, 0.5, 1], duration: L.closeDuration, timing: .easeIn) { [weak self] in
            guard let self, !self.isOpen else { return }
            self.parent?.removeChildWindow(self)
            self.orderOut(nil)
            self.shell.layer?.removeAllAnimations()
        }
    }

    /// A vertical scale of the card and its shadow about the card's top (or bottom, when above
    /// its link) edge.
    private func squash(from: CGFloat, to: CGFloat, opacity: [Float], at times: [Double], duration: Double,
                        timing: CAMediaTimingFunctionName, completion: (() -> Void)?) {
        guard let layer = shell.layer else { completion?(); return }
        let h = shell.bounds.height
        let edge: CGFloat = above ? -1 : 1  // layer y is up: +1 keeps the top edge, -1 the bottom
        func transform(_ s: CGFloat) -> CATransform3D {
            CATransform3DConcat(CATransform3DMakeScale(1, s, 1), CATransform3DMakeTranslation(0, edge * h * (1 - s) / 2, 0))
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion?() } }
        let scale = CABasicAnimation(keyPath: "transform")
        scale.fromValue = transform(from)
        scale.toValue = transform(to)
        scale.timingFunction = CAMediaTimingFunction(name: timing)
        let fade = CAKeyframeAnimation(keyPath: "opacity")
        fade.values = opacity
        fade.keyTimes = times.map { NSNumber(value: $0) }
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = duration
        group.fillMode = .forwards
        group.isRemovedOnCompletion = false
        layer.add(group, forKey: "squash")
        CATransaction.commit()
    }
}

/// The card's holder: its shadow follows its size.
final class LinkSummaryShellView: NSView {
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        // CGPath(roundedRect:) traps on corners larger than half the rect.
        let r = NSRect(origin: .zero, size: newSize)
        let radius = LinkSummaryCardLayout.cornerRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.shadowPath = r.width > 0 && r.height > 0
            ? CGPath(roundedRect: r, cornerWidth: min(radius, r.width / 2), cornerHeight: min(radius, r.height / 2), transform: nil)
            : nil
        CATransaction.commit()
    }
}

// MARK: - Card

/// Arc's hover card. The answer card: the page's picture across the top when it has one, the
/// quick summary in bold, then a row per detail with the model's SF Symbol, a bold label and the
/// info, and a share button in the corner. The small card: the page's title in bold and its address.
/// The loading card: two grey bars. The fill is the space's dark tooltip tone (black mixed with its
/// shaded colour at 30 %) at 90 %: sampled #322c15 over Hacker News in a beige space, where
/// TooltipTones gives #302913.
final class LinkSummaryCardView: NSView {
    enum Content {
        case loading
        case summary(LinkSummaryService.Card)
        case link(title: String, address: String)
    }

    private typealias L = LinkSummaryCardLayout
    private let banner = CALayer()
    private let summary = NSTextField(wrappingLabelWithString: "")
    private let empty = NSTextField(labelWithString: "No preview available")
    private let title = NSTextField(wrappingLabelWithString: "")
    private let address = NSTextField(labelWithString: "")
    private var rows: [(icon: NSImageView, text: NSTextField)] = []
    private var bars: [CALayer] = []
    private let share = LinkSummaryShareButton()
    private var link: URL?
    private var shown: (result: LinkSummaryResult, image: NSImage?)?
    /// The site's favicon, for the copied image's footer.
    var favicon: NSImage?
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
        for label in [summary, empty, title, address] {
            label.isSelectable = false
            label.textColor = .white
            addSubview(label)
        }
        summary.font = .systemFont(ofSize: 13, weight: .bold)
        summary.maximumNumberOfLines = 2
        summary.cell?.truncatesLastVisibleLine = true
        summary.preferredMaxLayoutWidth = L.width - 2 * L.margin
        empty.font = .systemFont(ofSize: 13, weight: .medium)
        empty.textColor = NSColor.white.withAlphaComponent(0.55)
        title.maximumNumberOfLines = 2
        title.preferredMaxLayoutWidth = L.width - 2 * L.margin
        address.font = .systemFont(ofSize: 13)
        address.textColor = NSColor.white.withAlphaComponent(0.85)
        address.lineBreakMode = .byTruncatingMiddle
        for _ in 0..<2 {
            let bar = CALayer()
            bar.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
            bar.cornerRadius = L.barThickness / 2
            layer?.addSublayer(bar)
            bars.append(bar)
        }
        share.onPress = { [weak self] event in self?.showShareMenu(event) }
        addSubview(share)
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ content: Content, theme: SpaceTheme) {
        let tones = TooltipTones(theme: theme)
        var image: NSImage?
        var result: LinkSummaryResult?
        var finished = false
        var isLoading = false
        var small: (String, String)?
        switch content {
        case .loading: isLoading = true
        case .summary(let card):
            image = card.image
            result = card.result
            finished = card.finished
            link = result.flatMap { URL(string: $0.url) } ?? link
            shown = result.map { ($0, card.image) }
        case .link(let t, let a): small = (t, a)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.backgroundColor = NSColor(srgbRed: tones.fill.r, green: tones.fill.g, blue: tones.fill.b, alpha: 0.9).cgColor
        banner.contents = image
        banner.isHidden = image == nil
        bars.forEach { $0.isHidden = !isLoading }
        CATransaction.commit()
        summary.stringValue = result?.quickSummary ?? ""
        summary.isHidden = summary.stringValue.isEmpty
        empty.isHidden = !(finished && result == nil)
        let para = NSMutableParagraphStyle()
        para.minimumLineHeight = L.titleLineHeight
        para.maximumLineHeight = L.titleLineHeight
        title.attributedStringValue = NSAttributedString(string: small?.0 ?? "", attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.white, .paragraphStyle: para])
        address.stringValue = small?.1 ?? ""
        title.isHidden = small == nil
        address.isHidden = small == nil
        setRows(result?.details ?? [])
        share.isHidden = !finished || result == nil
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
            text.cell?.truncatesLastVisibleLine = true
            text.preferredMaxLayoutWidth = L.width - L.rowIndent - L.margin
            addSubview(icon)
            addSubview(text)
            // A streamed row fades in, as Arc's do.
            for v in [icon, text] as [NSView] {
                v.wantsLayer = true
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = 0.2
                v.layer?.add(fade, forKey: "fadeIn")
            }
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

    /// Lays the card out from the top and returns its height.
    @discardableResult
    private func place() -> CGFloat {
        let w = L.width, inner = w - 2 * L.margin
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if !bars[0].isHidden {
            let top = (L.loadingHeight - L.barPitch - L.barThickness) / 2
            for (i, bar) in bars.enumerated() {
                bar.frame = CGRect(x: L.margin, y: top + CGFloat(i) * L.barPitch, width: inner, height: L.barThickness)
            }
            return L.loadingHeight
        }
        if !title.isHidden {
            let th = title.fittingSize.height
            title.frame = NSRect(x: L.margin, y: L.margin, width: inner, height: th)
            address.frame = NSRect(x: L.margin, y: L.margin + th + L.addressGap, width: inner, height: 16)
            return (L.margin + th + L.addressGap + 16 + L.margin).rounded()
        }
        var y: CGFloat = 0
        if !banner.isHidden {
            banner.frame = CGRect(x: 0, y: 0, width: w, height: L.bannerHeight)
            y = L.bannerHeight
        }
        y += 12
        if !summary.isHidden {
            let h = summary.fittingSize.height
            summary.frame = NSRect(x: L.margin, y: y, width: inner, height: h)
            y += h + L.rowGap
        }
        if !empty.isHidden {
            empty.frame = NSRect(x: L.margin, y: y, width: inner, height: 17)
            y += 17 + L.rowGap
        }
        for row in rows {
            let h = max(L.lineHeight, row.text.fittingSize.height)
            row.icon.frame = NSRect(x: L.margin, y: y, width: 18, height: L.lineHeight)
            row.text.frame = NSRect(x: L.rowIndent, y: y, width: w - L.rowIndent - L.margin, height: h)
            y += h + L.rowGap
        }
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

    /// Arc's share menu: Copy as Text, Copy as Image, Share ▸, opened where the button was clicked.
    private func showShareMenu(_ event: NSEvent) {
        guard let link else { return }
        let menu = NSMenu()
        menu.appearance = NSAppearance(named: .darkAqua)
        for (title, symbol, action) in [("Copy as Text", "doc.on.doc", #selector(copyAsText)), ("Copy as Image", "photo.on.rectangle", #selector(copyAsImage))] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        // Arc's Share is a submenu of the share services, not the share sheet.
        let shareItem = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
        shareItem.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        let services = NSMenu()
        for service in Self.shareServices(for: [link]) {
            let item = NSMenuItem(title: service.menuItemTitle, action: #selector(shareWithService(_:)), keyEquivalent: "")
            item.target = self
            item.image = service.image
            item.representedObject = service
            services.addItem(item)
        }
        shareItem.submenu = services
        menu.addItem(shareItem)
        menu.popUp(positioning: nil, at: share.convert(event.locationInWindow, from: nil), in: share)
    }

    /// The services that can share the link. NSSharingServicePicker only offers a sheet or its own
    /// "Share…" item; Arc lists the services in its menu, which only the older
    /// sharingServices(forItems:) gives (called through a protocol, as it is deprecated).
    private static func shareServices(for items: [Any]) -> [NSSharingService] {
        (NSSharingService.self as SharingServiceListing.Type).sharingServices(forItems: items)
    }

    @objc private func shareWithService(_ sender: NSMenuItem) {
        guard let link, let service = sender.representedObject as? NSSharingService else { return }
        service.perform(withItems: [link])
    }

    /// Plain text and rich text (bold labels), as Arc puts both on the pasteboard.
    @objc private func copyAsText() {
        guard let r = shown?.result else { return }
        let text = LinkSummaryShare.text(r, attribution: "AI Summary by \(LinkSummaryShareImage.brand)")
        let rich = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13)])
        for d in r.details where !d.label.isEmpty {
            let range = (text as NSString).range(of: d.label + ":")
            if range.location != NSNotFound { rich.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .bold), range: range) }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        if let rtfd = rich.rtfd(from: NSRange(location: 0, length: rich.length)) { pb.setData(rtfd, forType: .rtfd) }
        pb.setString(text, forType: .string)
    }

    @objc private func copyAsImage() {
        guard let shown,
              let image = LinkSummaryShareImage.render(shown.result, image: shown.image, favicon: favicon) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }
}

/// Arc's share button: a 32 pt grey circle with the share glyph.
final class LinkSummaryShareButton: NSView {
    var onPress: ((NSEvent) -> Void)?
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
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?(event) }
    }
}

private protocol SharingServiceListing {
    static func sharingServices(forItems items: [Any]) -> [NSSharingService]
}
extension NSSharingService: SharingServiceListing {}
