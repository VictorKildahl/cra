import AppKit

/// Arc 1.171's Library ▸ Spaces, which "Manage Spaces…" opens (spaceManager). Measured from a 2x
/// capture of Arc's window (1 Nov): every space is a 240 pt card in its own theme, 24 pt apart,
/// starting 27 pt right of the rail, 48 pt below the window top and above its bottom. A card has
/// the space's icon, name and a brush (Edit Theme Color…) on a row 25 pt down, its pinned and
/// Today lists from 64 pt down, and a move handle and a ••• menu 21 pt above its bottom. A blue +
/// (New Space) sits 34 pt after the last card, centred.
enum SpacesManagerMetrics {
    static let card: CGFloat = 240
    static let gap: CGFloat = 24
    static let lead: CGFloat = 27
    static let inset: CGFloat = 48
    static let plus: CGFloat = 29
    static let plusGap: CGFloat = 34
    static let trail: CGFloat = 37.5

    /// The Library's width on this page: Arc widens the sidebar to fit every card.
    static func width(spaces n: Int) -> CGFloat {
        LibraryMetrics.rail + lead + CGFloat(n) * card + CGFloat(max(0, n - 1)) * gap + plusGap + plus + trail
    }
}

@MainActor
final class SpacesManagerView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let favicons: FaviconCache
    private let scroll = SpacesStripScrollView()
    private let document = FlippedView()
    private var cards: [UUID: SpaceManagerCard] = [:]
    private var order: [UUID] = []
    private lazy var plus: NSButton = {
        let b = NSButton(image: SidebarSymbols.image("plus", size: 14, weight: .bold) ?? NSImage(), target: self, action: #selector(newSpace))
        b.isBordered = false
        b.wantsLayer = true
        b.layer?.cornerRadius = SpacesManagerMetrics.plus / 2
        b.layer?.backgroundColor = accent.fill.cgColor
        b.contentTintColor = accent.ink
        b.toolTip = "New Space"
        b.setAccessibilityLabel("New Space")
        return b
    }()

    /// The + takes the window's space colours (Arc 1.172.1, 8 Nov 2026: a cream disc with a dark +
    /// in an olive space; the blue one measured 1 Nov was a blue space's).
    var accent: (fill: NSColor, ink: NSColor) = (NSColor(hex: "#2147F5"), .white) {
        didSet { plus.layer?.backgroundColor = accent.fill.cgColor; plus.contentTintColor = accent.ink }
    }

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        super.init(frame: .zero)
        scroll.drawsBackground = false
        // The window's full-size content would otherwise push the cards down by the title bar.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsetsZero
        scroll.hasHorizontalScroller = true
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        scroll.horizontalScrollElasticity = .allowed
        scroll.verticalScrollElasticity = .none
        scroll.documentView = document
        addSubview(scroll)
        document.addSubview(plus)
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func sync() {
        let ids = withObservationTracking { store.orderedSpaces.filter { !store.isIncognito(space: $0.id) }.map(\.id) } onChange: { [weak self] in
            Task { @MainActor in self?.sync() }
        }
        for id in cards.keys where !ids.contains(id) { cards.removeValue(forKey: id)?.removeFromSuperview() }
        for id in ids where cards[id] == nil {
            let c = SpaceManagerCard(spaceID: id, store: store, ui: ui, actions: actions, favicons: favicons)
            c.onMove = { [weak self] dx in self?.drag(id, by: dx) }
            c.onMoveEnd = { [weak self] in self?.drop(id) }
            cards[id] = c
            document.addSubview(c)
        }
        order = ids
        needsLayout = true
    }

    @objc private func newSpace() { actions.editSpace(nil) }

    private var dragging: (id: UUID, dx: CGFloat)?

    private func drag(_ id: UUID, by dx: CGFloat) {
        dragging = (id, dx)
        if let c = cards[id] { document.addSubview(c, positioned: .above, relativeTo: nil) }
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    /// Where the dragged card's centre is, among the others, is its new place.
    private func drop(_ id: UUID) {
        guard let d = dragging, let from = order.firstIndex(of: id) else { return }
        dragging = nil
        let pitch = SpacesManagerMetrics.card + SpacesManagerMetrics.gap
        let to = min(max(0, from + Int((d.dx / pitch).rounded())), order.count - 1)
        if to != from, let target = store.spaceOrder.firstIndex(of: order[to]) { store.moveSpace(id, to: target) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.allowsImplicitAnimation = true
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }

    override func layout() {
        super.layout()
        typealias M = SpacesManagerMetrics
        scroll.frame = bounds
        let h = bounds.height
        let cardH = max(0, h - 2 * M.inset)
        var x = M.lead
        for id in order {
            let dx = dragging?.id == id ? dragging?.dx ?? 0 : 0
            cards[id]?.frame = NSRect(x: x + dx, y: M.inset, width: M.card, height: cardH)
            x += M.card + M.gap
        }
        x += M.plusGap - M.gap
        plus.frame = NSRect(x: x, y: (h - M.plus) / 2, width: M.plus, height: M.plus)
        document.frame = NSRect(x: 0, y: 0, width: x + M.plus + M.trail, height: h)
    }
}

/// One space's card: its theme behind its header row, tab list and footer.
@MainActor
private final class SpaceManagerCard: NSView {
    private let spaceID: UUID
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let background: PaletteBackgroundView
    private let emoji = NSTextField.sidebarLabel(size: 14.5)
    private let symbol = NSImageView()
    private let title = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let list: SpaceListView
    private lazy var brush = SidebarGlyphButton(symbol: "paintbrush.pointed.fill", size: 26, iconSize: 13, help: "Edit Theme Color",
                                                colors: colors) { [weak self] in
        guard let self, let s = self.store.space(self.spaceID) else { return }
        self.actions.editSpaceThemeBeside(s, self)
    }
    /// Dragging it carries the card along the row; where it is let go is the space's new place.
    private let move = SpaceMoveHandle()
    var onMove: ((CGFloat) -> Void)?
    var onMoveEnd: (() -> Void)?
    private lazy var more = SidebarGlyphButton(symbol: "ellipsis", size: 26, iconSize: 13, help: "", colors: colors) { [weak self] in
        self?.showMenu()
    }
    private var colors = SidebarColors()

    init(spaceID: UUID, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.spaceID = spaceID
        self.store = store
        self.ui = ui
        self.actions = actions
        let palette = store.space(spaceID)?.theme.palette ?? SpaceTheme.presets[0].palette
        background = PaletteBackgroundView(palette: palette)
        list = SpaceListView(spaceID: spaceID, store: store, ui: ui, actions: actions, favicons: favicons)
        list.showsNewTab = false
        super.init(frame: .zero)
        move.onDrag = { [weak self] dx in self?.onMove?(dx) }
        move.onEnd = { [weak self] in self?.onMoveEnd?() }
        wantsLayer = true
        layer?.cornerRadius = 14
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        symbol.imageScaling = .scaleNone
        for v in [background, emoji, symbol, title, list, brush, move, more] as [NSView] { addSubview(v) }
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func sync() {
        withObservationTracking {
            guard let s = store.space(spaceID) else { return }
            emoji.stringValue = s.emoji
            symbol.image = s.symbol.flatMap { SidebarSymbols.image($0, size: 13, weight: .medium) }
            title.stringValue = s.title
            background.palette = s.theme.palette
            colors = SidebarColors(s.theme.palette)
        } onChange: { [weak self] in
            Task { @MainActor in self?.sync() }
        }
        title.textColor = colors.textSecondary
        symbol.contentTintColor = colors.textSecondary
        for b in [brush, more] { b.colors = colors }
        move.tint = colors.isDark ? NSColor.white.withAlphaComponent(0.55) : colors.glyph
        needsLayout = true
    }

    private func showMenu() {
        guard let event = NSApp.currentEvent,
              let down = NSEvent.mouseEvent(with: .rightMouseDown, location: event.locationInWindow, modifierFlags: [],
                                            timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                            eventNumber: 0, clickCount: 1, pressure: 1),
              let m = SpaceMenu.make(spaceID: spaceID, store: store, ui: ui, actions: actions, anchor: self, rename: {}) else { return }
        NSMenu.popUpContextMenu(m, with: down, for: self)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        SpaceMenu.make(spaceID: spaceID, store: store, ui: ui, actions: actions, anchor: self, rename: {})
    }

    override func layout() {
        super.layout()
        let w = bounds.width, h = bounds.height
        background.frame = bounds
        let es = emoji.intrinsicContentSize
        let ew = ceil(emoji.attributedStringValue.size().width)
        emoji.frame = NSRect(x: 25.5 - ew / 2 - SidebarText.inset, y: 25 - es.height / 2, width: ew + 2 * SidebarText.inset, height: es.height)
        symbol.frame = NSRect(x: 12.5, y: 12, width: 26, height: 26)
        let th = title.intrinsicContentSize.height
        title.frame = NSRect(x: 44 - SidebarText.inset, y: 25 - th / 2, width: max(0, 213 - 13 - 44) + 2 * SidebarText.inset, height: th)
        brush.frame = NSRect(x: 213 - 13, y: 12, width: 26, height: 26)
        // The first pinned row is centred 64 pt down: rows are 41 pt, 3 pt into the list.
        list.frame = NSRect(x: 0, y: 40.5, width: w, height: max(0, h - 40.5 - 42))
        move.frame = NSRect(x: 22 - 13, y: h - 21 - 13, width: 26, height: 26)
        more.frame = NSRect(x: 217.5 - 13, y: h - 21 - 13, width: 26, height: 26)
    }
}

/// The card's move handle (Arc's four-way arrow): reports how far it has been dragged.
private final class SpaceMoveHandle: NSView {
    var onDrag: (CGFloat) -> Void = { _ in }
    var onEnd: () -> Void = {}
    var tint: NSColor = .secondaryLabelColor { didSet { glyph.contentTintColor = tint } }
    private let glyph = NSImageView()
    private var start: CGFloat?

    override init(frame: NSRect) {
        super.init(frame: frame)
        glyph.image = SidebarSymbols.image("arrow.up.and.down.and.arrow.left.and.right", size: 13, weight: .medium)
        glyph.imageScaling = .scaleNone
        glyph.autoresizingMask = [.width, .height]
        addSubview(glyph)
        setAccessibilityLabel("Move Space")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        glyph.frame = bounds
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow.x
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        if let start { onDrag(event.locationInWindow.x - start) }
    }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        start = nil
        NSCursor.pop()
        onEnd()
    }
}

/// The cards' row. Like the tab lists (SidebarListScrollView) it stays off responsive scrolling,
/// which would take a gesture's events past the window's scroll monitor once it starts here:
/// a swipe that starts with the cards at their end has to reach the monitor to leave the Library.
final class SpacesStripScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool { false }
}
