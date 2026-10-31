import AppKit
import SwiftUI

/// One space's page in the pager: Arc's favorites grid and space header, fixed, over the
/// space's tab list, which scrolls (Arc 1.170). All AppKit: a space switch or swipe moves this
/// view's layer and nothing in it lays out or re-renders.
@MainActor
final class SpaceColumnView: NSView {
    let spaceID: UUID
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let favicons: FaviconCache
    private let favorites: FavoritesGridView
    private let header: SpaceHeaderView
    private let list: SpaceListView

    init(spaceID: UUID, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.spaceID = spaceID
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        favorites = FavoritesGridView(spaceID: spaceID, store: store, ui: ui, actions: actions, favicons: favicons)
        header = SpaceHeaderView(spaceID: spaceID, store: store, actions: actions)
        list = SpaceListView(spaceID: spaceID, store: store, ui: ui, actions: actions, favicons: favicons)
        super.init(frame: .zero)
        favorites.onHeightChange = { [weak self] animated in self?.relayout(animated: animated) }
        header.onHiddenChange = { [weak self] in self?.relayout(animated: true) }
        addSubview(list)
        addSubview(favorites)
        addSubview(header)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func relayout(animated: Bool) {
        guard animated, window != nil else { needsLayout = true; return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            place(animated: true)
        }
    }

    override func layout() {
        super.layout()
        place(animated: false)
    }

    /// Arc 1.171 (one space, live, 31 Oct) places everything under the favorites from the tiles'
    /// bottom, or with no favorites from the URL field's (the column starts 8 pt under it, where
    /// the first tile's top goes): the header 10 pt below, the divider line 54.5 pt below. With
    /// the header hidden the line is 18.5 pt under the tiles, 15.5 pt under the URL field.
    private func place(animated: Bool) {
        let w = bounds.width
        let fh = favorites.height(forWidth: w - 16)
        let set = { (v: NSView, f: NSRect) in if v.frame != f { animated ? (v.animator().frame = f) : (v.frame = f) } }
        set(favorites, NSRect(x: 8, y: 0, width: w - 16, height: fh))
        let tiles = favorites.tilesBottom(forWidth: w - 16)
        let base = tiles ?? -8
        set(header, NSRect(x: 10, y: base + 10, width: w - 20, height: header.isHidden ? 0 : 31))
        // The list's line sits 11.5 pt into it (3 pt inset, then halfway down the 18 pt divider).
        let top = base + (!header.isHidden ? 43 : tiles == nil ? 4 : 7)
        set(list, NSRect(x: 0, y: top, width: w, height: max(0, bounds.height - top)))
    }
}

// MARK: - Space header

/// The space's emoji and name. Arc: a click collapses or expands the pinned tabs; the menu is
/// on right-click; the chevron shows on hover.
final class SpaceHeaderView: NSView {
    private let spaceID: UUID
    private let store: SidebarStore
    private let actions: SidebarActions
    private let emoji = NSTextField.sidebarLabel(size: 12)
    private let title = NSTextField.sidebarLabel(size: 14, weight: .medium)
    private let chevron = NSImageView()
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }
    private var collapsed = false
    private var colors = SidebarColors()
    private var syncQueued = false
    /// The column lays out again when Arc's single-space mode hides or shows the header.
    var onHiddenChange: (() -> Void)?

    init(spaceID: UUID, store: SidebarStore, actions: SidebarActions) {
        self.spaceID = spaceID
        self.store = store
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        chevron.image = SidebarSymbols.image("chevron.down", size: 8, weight: .bold)
        chevron.imageScaling = .scaleNone
        chevron.wantsLayer = true
        for v in [emoji, title, chevron] { addSubview(v) }
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func sync() {
        syncQueued = false
        var hide = false
        withObservationTracking {
            guard let space = store.space(spaceID) else { return }
            emoji.stringValue = space.emoji
            title.stringValue = space.title
            colors = SidebarColors(space.theme.palette)
            collapsed = store.isPinnedCollapsed(spaceID)
            hide = store.hidesSpaceHeader(spaceID)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.syncQueued else { return }
                self.syncQueued = true
                self.sync()
            }
        }
        refresh()
        if hide != isHidden {
            isHidden = hide
            onHiddenChange?()
        }
    }

    private func refresh() {
        title.textColor = colors.textSecondary
        chevron.contentTintColor = colors.textTertiary
        chevron.alphaValue = hovering ? 1 : 0
        layer?.backgroundColor = (hovering ? colors.hoverFill : .clear).cgColor
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        // HStack(spacing: 8), 7 pt in.
        let es = emoji.intrinsicContentSize
        let ew = ceil(emoji.attributedStringValue.size().width)
        emoji.frame = NSRect(x: 7 - SidebarText.inset, y: (h - es.height) / 2, width: ew + 2 * SidebarText.inset, height: es.height)
        var x = 7 + ew + 8
        let tw = min(ceil(title.attributedStringValue.size().width), max(0, bounds.width - x - 30))
        let th = title.intrinsicContentSize.height
        title.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: tw + 2 * SidebarText.inset, height: th)
        x += tw + 8
        chevron.frame = NSRect(x: x, y: (h - 10) / 2, width: 10, height: 10)
        chevron.layer?.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        chevron.layer?.position = CGPoint(x: chevron.frame.midX, y: chevron.frame.midY)
        chevron.layer?.setAffineTransform(CGAffineTransform(rotationAngle: collapsed ? .pi / 2 : 0))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { store.togglePinnedCollapsed(spaceID) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let space = store.space(spaceID) else { return nil }
        let store = self.store, actions = self.actions, id = spaceID
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, collapsed ? "Expand Pinned Tabs" : "Collapse Pinned Tabs") { store.togglePinnedCollapsed(id) }
        // Arc offers this only while there is one space; Show Space Header brings it back.
        if store.orderedSpaces.count == 1 {
            MenuItems.add(m, "Hide Space Header") { store.settings.showSpaceHeaderOnSingleSpace = false }
        }
        m.addItem(.separator())
        MenuItems.add(m, "Edit Space…") { actions.editSpace(space) }
        MenuItems.add(m, "New Folder") { actions.performAction("newFolder") }
        MenuItems.add(m, "New GitHub Live Folder", enabled: store.liveFolder(.github, inSpace: id) == nil) { actions.performAction("newGitHubLiveFolder") }
        m.addItem(.separator())
        MenuItems.add(m, "Clear Today") { store.clearToday(id) }
        m.addItem(.separator())
        MenuItems.add(m, "New Space…") { actions.editSpace(nil) }
        MenuItems.add(m, "Delete Space…") { actions.performAction("deleteSpace") }
        return m
    }
}

/// Closure-backed menu items for AppKit menus.
@MainActor
enum MenuItems {
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    @discardableResult
    static func add(_ menu: NSMenu, _ title: String, enabled: Bool = true, on: Bool? = nil, image: NSImage? = nil, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = Action(run)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        item.target = a
        item.representedObject = a
        item.isEnabled = enabled
        item.image = image
        if let on { item.state = on ? .on : .off }
        menu.addItem(item)
        return item
    }

    static func submenu(_ menu: NSMenu, _ title: String) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
        menu.addItem(item)
        return sub
    }
}

// MARK: - Favorites

/// Arc's "top apps": a 4-wide grid of favorite tiles, 8 pt apart, and under it a strip that
/// opens into "Add to Favorites" while a tab is dragged over it. Arc shares them between
/// spaces; in Cra every space has its own.
final class FavoritesGridView: NSView {
    private let spaceID: UUID
    let store: SidebarStore
    let ui: SidebarUIState
    let actions: SidebarActions
    let favicons: FaviconCache
    var onHeightChange: (Bool) -> Void = { _ in }
    private var tiles: [UUID: FavoriteTileView] = [:]
    private var order: [UUID] = []
    private let strip = FavoritesDropStrip()
    private(set) var palette: SpacePalette?
    private var syncQueued = false

    init(spaceID: UUID, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.spaceID = spaceID
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        super.init(frame: .zero)
        strip.onDrop = { [weak self] id in
            guard let self else { return false }
            self.store.addToFavorites(id, in: self.spaceID)
            return true
        }
        strip.onTargetChange = { [weak self] _ in self?.onHeightChange(true) }
        addSubview(strip)
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func sync() {
        syncQueued = false
        var models: [(UUID, FavoriteTileModel)] = []
        var palette: SpacePalette?
        withObservationTracking {
            guard let space = store.space(spaceID) else { return }
            palette = space.theme.palette
            // A favorite split is one tile with a cell per pane (Arc: AppItem.childItems).
            for item in store.children(of: space.favoritesContainerID) where item.isTab || item.isSplit {
                let panes = item.isSplit ? store.children(of: item.id).filter(\.isTab) : [item]
                guard !panes.isEmpty else { continue }
                let cells = panes.map { p in
                    let key = p.tab?.iconKey
                    let icon = favicons.image(forKey: key)
                    return FavoriteTileModel.Cell(id: p.id, title: p.displayTitle, icon: icon,
                                                  glyphDark: icon == nil ? nil : favicons.glyphIsDark(forKey: key))
                }
                let open = panes.first { store.isSelected($0.id, inSpace: spaceID, window: ui.windowID) }?.id
                let title = item.isSplit && item.title == nil ? panes.map(\.displayTitle).joined(separator: " | ") : item.displayTitle
                models.append((item.id, FavoriteTileModel(title: title, cells: cells, vertical: item.split?.orientation == .vertical,
                                                          tileColor: item.tab?.tileColor, selected: open != nil, openCell: open,
                                                          unread: panes.contains(where: \.isUnread), focus: ui.keyboardFocusID == item.id)))
            }
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.syncQueued else { return }
                self.syncQueued = true
                self.sync()
            }
        }
        self.palette = palette
        let ids = models.map(\.0)
        let countChanged = ids.count != order.count
        for (id, t) in tiles where !ids.contains(id) {
            t.removeFromSuperview()
            tiles[id] = nil
        }
        for (id, m) in models {
            let t = tiles[id] ?? {
                let t = FavoriteTileView(itemID: id, spaceID: spaceID, grid: self)
                tiles[id] = t
                addSubview(t)
                return t
            }()
            if let palette { t.show(m, palette: palette) }
        }
        order = ids
        if let palette { strip.palette = palette }
        strip.hasFavorites = !ids.isEmpty
        needsLayout = true
        if countChanged { onHeightChange(false) }
    }

    /// Arc 1.171 (AX frames, 1–9 favorites at sidebar widths 100–347, 31 Oct): at most as many
    /// columns (up to four) as keep a tile at least as wide as it is tall (47 pt), then the fewest
    /// that need no more rows: one favorite fills the row, five go 3 + 2, nine 3 × 3, four at
    /// 200 pt 2 × 2 (#29). A short last row keeps the tile width, from the left.
    private func columns(forWidth w: CGFloat) -> Int {
        let widest = (1...4).last { (w - CGFloat($0 - 1) * 8) / CGFloat($0) >= 47 } ?? 1
        guard !order.isEmpty else { return widest }
        let rows = (order.count + widest - 1) / widest
        return (order.count + rows - 1) / rows
    }

    private func rows(forWidth w: CGFloat) -> Int {
        let c = columns(forWidth: w)
        return (order.count + c - 1) / c
    }

    func height(forWidth w: CGFloat) -> CGFloat {
        let rows = rows(forWidth: w)
        let grid = rows == 0 ? 0 : CGFloat(rows) * 47 + CGFloat(rows - 1) * 8
        return grid + (order.isEmpty ? 0 : 4) + strip.height
    }

    /// Where the header and list are placed from: the tiles' bottom, the open "Add to Favorites"
    /// strip's while a tab is dragged over it, nil with no favorites.
    func tilesBottom(forWidth w: CGFloat) -> CGFloat? {
        if strip.targeted { return height(forWidth: w) }
        let rows = rows(forWidth: w)
        return rows == 0 ? nil : CGFloat(rows) * 47 + CGFloat(rows - 1) * 8
    }

    /// The resting strip only takes drops (AppKit finds drop targets apart from hitTest). With
    /// the header hidden and no favorites the divider sits under it, and its Clear gets the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let v = super.hitTest(point)
        return v === self || v === strip ? nil : v
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let n = columns(forWidth: w)
        let cw = (w - CGFloat(n - 1) * 8) / CGFloat(n)
        for (i, id) in order.enumerated() {
            let r = i / n, c = i % n
            // Arc puts each tile on a half point (84.75 → 85 at 347 pt).
            let x = (CGFloat(c) * (cw + 8) * 2).rounded() / 2
            tiles[id]?.frame = NSRect(x: x, y: CGFloat(r) * (47 + 8), width: cw, height: 47)
        }
        let rows = rows(forWidth: w)
        let grid = rows == 0 ? 0 : CGFloat(rows) * 47 + CGFloat(rows - 1) * 8
        strip.frame = NSRect(x: 0, y: grid + (order.isEmpty ? 0 : 4), width: w, height: strip.height)
    }

    func moveFavorite(_ dragged: UUID, before target: UUID, after: Bool) {
        guard dragged != target, let space = store.space(spaceID),
              let idx = store.item(space.favoritesContainerID)?.children.firstIndex(of: target) else { return }
        store.moveItem(dragged, to: space.favoritesContainerID, index: idx + (after ? 1 : 0))
    }

    func spaceFavoriteIDs() -> [UUID] {
        guard let space = store.space(spaceID) else { return [] }
        return store.favoriteTabs(in: space).map(\.id)
    }
}

/// The drop strip under the grid: 6–8 pt of nothing, 36 pt "Add to Favorites" while targeted.
final class FavoritesDropStrip: NSView {
    var onDrop: (UUID) -> Bool = { _ in false }
    var onTargetChange: (Bool) -> Void = { _ in }
    var palette: SpacePalette? { didSet { refresh() } }
    var hasFavorites = true
    private(set) var targeted = false { didSet { if targeted != oldValue { refresh(); onTargetChange(targeted) } } }
    private let border = CAShapeLayer()
    private let label = NSTextField.sidebarLabel(size: 11, weight: .medium)

    var height: CGFloat { targeted ? 36 : (hasFavorites ? 6 : 8) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        border.fillColor = nil
        border.lineWidth = 1
        border.lineDashPattern = [4, 3]
        layer?.addSublayer(border)
        label.stringValue = "Add to Favorites"
        label.alignment = .center
        addSubview(label)
        registerForDraggedTypes([.craSidebarItem])
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func refresh() {
        guard let p = palette else { return }
        let colors = SidebarColors(p)
        border.strokeColor = colors.textTertiary.withAlphaComponent(targeted ? 0.6 : 0).cgColor
        layer?.backgroundColor = (targeted ? colors.hoverFill : .clear).cgColor
        label.textColor = colors.textSecondary
        label.isHidden = !targeted
    }

    override func layout() {
        super.layout()
        border.frame = bounds
        border.path = CGPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 10, cornerHeight: 10, transform: nil)
        let lh = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (bounds.height - lh) / 2, width: bounds.width, height: lh)
    }

    private func draggedID(_ info: NSDraggingInfo) -> UUID? {
        guard let data = info.draggingPasteboard.data(forType: .craSidebarItem),
              let d = try? JSONDecoder().decode(SidebarDragItem.self, from: data) else { return nil }
        return d.id
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedID(sender) != nil else { return [] }
        targeted = true
        return sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedID(sender) == nil ? [] : (sender.draggingSourceOperationMask.contains(.move) ? .move : .copy)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { targeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { targeted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targeted = false
        guard let id = draggedID(sender) else { return false }
        return onDrop(id)
    }
}

/// What a favorite tile shows: one page, or a split's panes. Arc keeps a split in its top apps as
/// one tile cut into a cell per pane (AppItem.childItems, AppTrayItemMaskShape), side by side or,
/// for a vertical split, stacked.
struct FavoriteTileModel: Equatable {
    struct Cell: Equatable {
        var id: UUID
        var title: String
        var icon: NSImage?
        var glyphDark: Bool?
    }
    var title: String
    var cells: [Cell]
    var vertical: Bool
    var tileColor: String?
    var selected: Bool
    /// The pane open in the window while this favorite is the open one.
    var openCell: UUID?
    var unread: Bool
    var focus: Bool
}

enum FavoriteTileMetrics {
    static let corner: CGFloat = 13
    /// The cut between a split's cells (AppTrayItemMaskShape.lineWidth).
    static let cut: CGFloat = 2

    /// Cell frames along the tile, whole points, the last cell taking what rounding leaves.
    static func cellFrames(in bounds: CGRect, count n: Int, vertical: Bool) -> [CGRect] {
        guard n > 1 else { return [bounds] }
        let length = vertical ? bounds.height : bounds.width
        let each = (length - CGFloat(n - 1) * cut) / CGFloat(n)
        var start: CGFloat = 0
        return (0..<n).map { i in
            let end = i == n - 1 ? length : (start + each).rounded()
            defer { start = end + cut }
            return vertical ? CGRect(x: 0, y: start, width: bounds.width, height: end - start)
                            : CGRect(x: start, y: 0, width: end - start, height: bounds.height)
        }
    }
}

/// A favorite tile. Arc 1.170: 13 pt circular corners; the active tile is the hover fill with a
/// 2 pt darker rim; inactive tiles sit ~4.5% darker than the sidebar. A picked tile colour keeps
/// its hue in every state; hover and selection shade it.
final class FavoriteTileView: NSView, ArcTooltipTarget, NSDraggingSource {
    let itemID: UUID
    private let spaceID: UUID
    private weak var grid: FavoritesGridView?
    private let shade = CALayer()
    /// The selected tile's 2 pt rim, under the focus ring (a layer border would draw over it).
    private let rim = CALayer()
    private var favicons: [SidebarFaviconView] = []
    /// Cuts a split's tile into its cells.
    private let cutMask = CAShapeLayer()
    private let unreadDot = CALayer()
    private var focusRing: FocusRingLayer?
    private var model: FavoriteTileModel?
    private var palette: SpacePalette?
    private var hoveredCell: Int? { didSet { if hoveredCell != oldValue { ArcTooltipController.shared.mouseExited(self) } } }
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }
    private var targeted = false { didSet { if targeted != oldValue { refresh() } } }
    private var press: NSEvent?

    init(itemID: UUID, spaceID: UUID, grid: FavoritesGridView) {
        self.itemID = itemID
        self.spaceID = spaceID
        self.grid = grid
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = FavoriteTileMetrics.corner
        shade.cornerRadius = FavoriteTileMetrics.corner
        layer?.addSublayer(shade)
        rim.cornerRadius = FavoriteTileMetrics.corner
        rim.zPosition = 5
        layer?.addSublayer(rim)
        cutMask.fillRule = .evenOdd
        unreadDot.cornerRadius = 3
        layer?.addSublayer(unreadDot)
        registerForDraggedTypes([.craSidebarItem])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func show(_ m: FavoriteTileModel, palette: SpacePalette) {
        model = m
        self.palette = palette
        setAccessibilityLabel(m.title)
        while favicons.count < m.cells.count {
            let f = SidebarFaviconView(size: 20)
            favicons.append(f)
            addSubview(f)
        }
        while favicons.count > m.cells.count { favicons.removeLast().removeFromSuperview() }
        // Arc 1.171: the open split's tile is one selected tile; the cut shows while it is closed.
        layer?.mask = m.cells.count > 1 && !m.selected ? cutMask : nil
        refresh()
    }

    private var tileIsDark: Bool {
        guard let m = model, let palette else { return false }
        return m.tileColor.flatMap(HexColor.luminance).map { $0 < 0.5 } ?? palette.isDark
    }

    private func refresh() {
        guard let m = model, let palette else { return }
        let dark = tileIsDark
        let colors = SidebarColors(palette)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let hex = m.tileColor {
            layer?.backgroundColor = NSColor(hex: hex).cgColor
            shade.backgroundColor = (m.selected || hovering || targeted ? (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.07)) : .clear).cgColor
        } else {
            let fill: NSColor = m.selected ? (palette.isDark ? NSColor.white.withAlphaComponent(0.13) : NSColor.white.withAlphaComponent(0.38))
                : (hovering || targeted ? (palette.isDark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.09)) : NSColor(palette.pillFill))
            layer?.backgroundColor = fill.cgColor
            shade.backgroundColor = NSColor.clear.cgColor
        }
        rim.borderWidth = m.selected ? 2 : 0
        rim.borderColor = (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.17)).cgColor
        var faviconColors = colors
        faviconColors.isDark = dark
        for (f, c) in zip(favicons, m.cells) { f.show(c.icon, flip: c.icon != nil && c.glyphDark == dark, colors: faviconColors) }
        unreadDot.isHidden = !(m.unread && !m.selected)
        unreadDot.backgroundColor = (m.tileColor == nil ? colors.textPrimary : (dark ? NSColor.white : NSColor.black)).withAlphaComponent(0.6).cgColor
        if m.focus != (focusRing != nil) {
            if m.focus {
                let r = FocusRingLayer(radius: FavoriteTileMetrics.corner)
                r.zPosition = 10
                layer?.addSublayer(r)
                focusRing = r
            } else {
                focusRing?.removeFromSuperlayer()
                focusRing = nil
            }
        }
        CATransaction.commit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shade.frame = bounds
        rim.frame = bounds
        let cells = cellFrames
        for (f, r) in zip(favicons, cells) { f.frame = NSRect(x: (r.midX - 10).rounded(), y: (r.midY - 10).rounded(), width: 20, height: 20) }
        if cells.count > 1, layer?.mask != nil {
            // The cuts are holes in the tile (even-odd), so fill, rim and focus ring all stop at them.
            let path = CGMutablePath()
            path.addRoundedRect(in: bounds, cornerWidth: FavoriteTileMetrics.corner, cornerHeight: FavoriteTileMetrics.corner)
            let vertical = model?.vertical == true
            for (a, b) in zip(cells, cells.dropFirst()) {
                path.addRect(vertical ? CGRect(x: 0, y: a.maxY, width: bounds.width, height: b.minY - a.maxY)
                                      : CGRect(x: a.maxX, y: 0, width: b.minX - a.maxX, height: bounds.height))
            }
            cutMask.frame = bounds
            cutMask.path = path
        }
        unreadDot.frame = CGRect(x: bounds.width - 5 - 6, y: 5, width: 6, height: 6)
        focusRing?.frame = bounds
        CATransaction.commit()
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    private var cellFrames: [CGRect] {
        FavoriteTileMetrics.cellFrames(in: bounds, count: model?.cells.count ?? 1, vertical: model?.vertical == true)
    }

    /// The cell under a point; a cut belongs to the cell before it.
    private func cellIndex(at p: NSPoint) -> Int {
        let vertical = model?.vertical == true
        return cellFrames.lastIndex { vertical ? $0.minY <= p.y : $0.minX <= p.x } ?? 0
    }

    private func trackPointer(_ event: NSEvent) {
        hoveredCell = cellIndex(at: convert(event.locationInWindow, from: nil))
        ArcTooltipController.shared.mouseMoved(in: self)
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; trackPointer(event) }
    override func mouseMoved(with event: NSEvent) { trackPointer(event) }
    override func mouseExited(with event: NSEvent) { hovering = false; hoveredCell = nil; ArcTooltipController.shared.mouseExited(self) }

    override func mouseDown(with event: NSEvent) { press = event }
    override func mouseDragged(with event: NSEvent) {
        guard let p = press, let grid else { return }
        guard hypot(event.locationInWindow.x - p.locationInWindow.x, event.locationInWindow.y - p.locationInWindow.y) > 3 else { return }
        press = nil
        grid.ui.draggingID = itemID
        let pb = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(SidebarDragItem(id: itemID)) { pb.setData(data, forType: .craSidebarItem) }
        let item = NSDraggingItem(pasteboardWriter: pb)
        let rep = bitmapImageRepForCachingDisplay(in: bounds)
        if let rep { cacheDisplay(in: bounds, to: rep) }
        let fill = layer?.backgroundColor.flatMap { NSColor(cgColor: $0) } ?? .clear
        let image = NSImage(size: bounds.size, flipped: false) { r in
            fill.setFill()
            NSBezierPath(roundedRect: r, xRadius: FavoriteTileMetrics.corner, yRadius: FavoriteTileMetrics.corner).fill()
            rep?.draw(in: r)
            return true
        }
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: p, source: self)
    }
    override func mouseUp(with event: NSEvent) {
        guard let p = press, let grid else { return }
        press = nil
        grid.ui.keyboardFocusID = nil
        // A split opens with the pressed pane focused.
        let cells = model?.cells ?? []
        let i = cellIndex(at: convert(p.locationInWindow, from: nil))
        grid.store.selectTab(cells.indices.contains(i) ? cells[i].id : itemID, window: grid.ui.windowID)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy, .generic, .private] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        grid?.ui.draggingID = nil
        if grid?.ui.listDrop != nil { grid?.ui.listDrop = nil }
    }

    // MARK: Drops (reorder)

    private func draggedID(_ info: NSDraggingInfo) -> UUID? {
        guard let data = info.draggingPasteboard.data(forType: .craSidebarItem),
              let d = try? JSONDecoder().decode(SidebarDragItem.self, from: data), d.id != itemID else { return nil }
        return d.id
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedID(sender) != nil else { return [] }
        targeted = true
        return sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedID(sender) == nil ? [] : (sender.draggingSourceOperationMask.contains(.move) ? .move : .copy)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { targeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { targeted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targeted = false
        guard let id = draggedID(sender) else { return false }
        grid?.moveFavorite(id, before: itemID, after: convert(sender.draggingLocation, from: nil).x > 30)
        return true
    }

    // MARK: Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let grid, let item = grid.store.item(itemID) else { return nil }
        let store = grid.store, ui = grid.ui, actions = grid.actions, favicons = grid.favicons
        let id = itemID
        if item.isSplit, let m = model {
            return SidebarMenus.split(id, panes: m.cells.map { ($0.id, $0.title) }, open: m.selected, store: store, ui: ui, actions: actions) {
                MenuItems.add($0, "Remove from Favorites") { store.removeFromFavorites(id) }
                $0.addItem(.separator())
            }
        }
        let tileColor = item.tab?.tileColor
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, "Remove from Favorites") { store.removeFromFavorites(id) }
        MenuItems.add(m, "Rename…") { ui.renamingID = id }
        MenuItems.add(m, "Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.tab?.url ?? "", forType: .string)
        }
        if let t = item.tab, t.url != t.savedURL { MenuItems.add(m, "Back to Pinned Page") { actions.resetPinnedTab(id) } }
        MenuItems.add(m, "Make This the Pinned Page") { store.setPinnedHomeToCurrent(id) }
        m.addItem(.separator())
        MenuItems.add(m, "Change Icon…") { [weak self] in self?.pickIcon() }
        if let key = item.tab?.customIconKey {
            MenuItems.add(m, "Use Site Icon") {
                store.setCustomIcon(nil, for: id)
                favicons.removeCustomIcon(key)
            }
        }
        let colors = MenuItems.submenu(m, "Tile Color")
        MenuItems.add(colors, "Default", on: tileColor == nil, image: TileColor.swatch(nil)) { store.setTileColor(nil, for: [id]) }
        for p in TileColor.presets {
            MenuItems.add(colors, p.name, on: tileColor == p.hex, image: TileColor.swatch(p.hex)) { store.setTileColor(p.hex, for: [id]) }
        }
        if let tileColor, !TileColor.presets.contains(where: { $0.hex == tileColor }) {
            MenuItems.add(colors, "Custom", on: true, image: TileColor.swatch(tileColor)) { store.setTileColor(tileColor, for: [id]) }
        }
        MenuItems.add(colors, "Other Color…") {
            TileColorPanel.shared.show(tileColor) { hex in store.setTileColor(hex, for: [id]) }
        }
        colors.addItem(.separator())
        MenuItems.add(colors, "Use This Color for All Favorites") { [weak grid] in
            guard let grid else { return }
            store.setTileColor(tileColor, for: grid.spaceFavoriteIDs())
        }
        m.addItem(.separator())
        MenuItems.add(m, "Close") { actions.closeTab(id) }
        MenuItems.add(m, "Archive") { store.archiveTab(id, reason: .manual) }
        return m
    }

    private func pickIcon() {
        guard let grid, let item = grid.store.item(itemID) else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Icon"
        panel.message = "Choose an image for \(item.displayTitle)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let key = grid.favicons.importCustomIcon(from: url) else { NSSound.beep(); return }
        let old = item.tab?.customIconKey
        grid.store.setCustomIcon(key, for: itemID)
        if let old { grid.favicons.removeCustomIcon(old) }
    }

    // ArcTooltipTarget: the title by the pointer.
    var text: String {
        guard let m = model else { return "" }
        if let i = hoveredCell, m.cells.count > 1, m.cells.indices.contains(i) { return m.cells[i].title }
        return m.title
    }
    var keys: [String] { [] }
    var followsCursor: Bool { true }
    var subtitle: String? { nil }
    var optionText: String? { nil }
    var onShow: (() -> Void)? { nil }
    var screenFrame: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    var hostWindow: NSWindow? { window }
}
