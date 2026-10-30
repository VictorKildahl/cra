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

    private func place(animated: Bool) {
        let w = bounds.width
        let fh = favorites.height(forWidth: w - 16)
        let set = { (v: NSView, f: NSRect) in if v.frame != f { animated ? (v.animator().frame = f) : (v.frame = f) } }
        set(favorites, NSRect(x: 8, y: 0, width: w - 16, height: fh))
        let hh: CGFloat = header.isHidden ? 0 : 31
        set(header, NSRect(x: 10, y: fh, width: w - 20, height: hh))
        let top = fh + hh + 3
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

    private struct TileModel: Equatable {
        var title: String
        var icon: NSImage?
        var glyphDark: Bool?
        var tileColor: String?
        var selected: Bool
        var unread: Bool
        var focus: Bool
    }

    private func sync() {
        syncQueued = false
        var models: [(UUID, TileModel)] = []
        var palette: SpacePalette?
        withObservationTracking {
            guard let space = store.space(spaceID) else { return }
            palette = space.theme.palette
            for item in store.tabs(under: space.favoritesContainerID) {
                let key = item.tab?.iconKey
                let icon = favicons.image(forKey: key)
                models.append((item.id, TileModel(title: item.displayTitle, icon: icon, glyphDark: icon == nil ? nil : favicons.glyphIsDark(forKey: key),
                                                  tileColor: item.tab?.tileColor,
                                                  selected: store.isSelected(item.id, inSpace: spaceID, window: ui.windowID),
                                                  unread: item.isUnread, focus: ui.keyboardFocusID == item.id)))
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
            if let palette {
                t.show(title: m.title, icon: m.icon, glyphDark: m.glyphDark, tileColor: m.tileColor, selected: m.selected,
                       unread: m.unread, focus: m.focus, palette: palette)
            }
        }
        order = ids
        if let palette { strip.palette = palette }
        strip.hasFavorites = !ids.isEmpty
        needsLayout = true
        if countChanged { onHeightChange(false) }
    }

    /// Arc 1.170 (AX frames at sidebar widths 100–347, 29 Oct): four columns while a tile is at
    /// least as wide as it is tall (47 pt), else two, else one; never three.
    private static func columns(forWidth w: CGFloat) -> Int {
        [4, 2].first { (w - CGFloat($0 - 1) * 8) / CGFloat($0) >= 47 } ?? 1
    }

    private func rows(forWidth w: CGFloat) -> Int {
        let c = Self.columns(forWidth: w)
        return (order.count + c - 1) / c
    }

    func height(forWidth w: CGFloat) -> CGFloat {
        let rows = rows(forWidth: w)
        let grid = rows == 0 ? 0 : CGFloat(rows) * 47 + CGFloat(rows - 1) * 8
        return grid + (order.isEmpty ? 0 : 4) + strip.height
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let n = Self.columns(forWidth: w)
        let cw = (w - CGFloat(n - 1) * 8) / CGFloat(n)
        for (i, id) in order.enumerated() {
            let r = i / n, c = i % n
            tiles[id]?.frame = NSRect(x: CGFloat(c) * (cw + 8), y: CGFloat(r) * (47 + 8), width: cw, height: 47)
        }
        let rows = rows(forWidth: w)
        let grid = rows == 0 ? 0 : CGFloat(rows) * 47 + CGFloat(rows - 1) * 8
        strip.frame = NSRect(x: 0, y: grid + (order.isEmpty ? 0 : 4), width: w, height: strip.height)
    }

    func moveFavorite(_ dragged: UUID, before target: UUID, after: Bool) {
        guard dragged != target, store.item(dragged)?.isSplit != true, let space = store.space(spaceID),
              let idx = store.item(space.favoritesContainerID)?.children.firstIndex(of: target) else { return }
        store.moveItem(dragged, to: space.favoritesContainerID, index: idx + (after ? 1 : 0))
    }

    func spaceFavoriteIDs() -> [UUID] {
        guard let space = store.space(spaceID) else { return [] }
        return store.tabs(under: space.favoritesContainerID).map(\.id)
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
    private let favicon = SidebarFaviconView(size: 20)
    private let unreadDot = CALayer()
    private var focusRing: FocusRingLayer?
    private var model: (title: String, icon: NSImage?, glyphDark: Bool?, tileColor: String?, selected: Bool, unread: Bool, focus: Bool, palette: SpacePalette)?
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }
    private var targeted = false { didSet { if targeted != oldValue { refresh() } } }
    private var press: NSEvent?

    init(itemID: UUID, spaceID: UUID, grid: FavoritesGridView) {
        self.itemID = itemID
        self.spaceID = spaceID
        self.grid = grid
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 13
        shade.cornerRadius = 13
        layer?.addSublayer(shade)
        rim.cornerRadius = 13
        rim.zPosition = 5
        layer?.addSublayer(rim)
        addSubview(favicon)
        unreadDot.cornerRadius = 3
        layer?.addSublayer(unreadDot)
        registerForDraggedTypes([.craSidebarItem])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func show(title: String, icon: NSImage?, glyphDark: Bool?, tileColor: String?, selected: Bool, unread: Bool, focus: Bool, palette: SpacePalette) {
        model = (title, icon, glyphDark, tileColor, selected, unread, focus, palette)
        setAccessibilityLabel(title)
        refresh()
    }

    private var tileIsDark: Bool {
        guard let m = model else { return false }
        return m.tileColor.flatMap(HexColor.luminance).map { $0 < 0.5 } ?? m.palette.isDark
    }

    private func refresh() {
        guard let m = model else { return }
        let dark = tileIsDark
        let colors = SidebarColors(m.palette)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let hex = m.tileColor {
            layer?.backgroundColor = NSColor(hex: hex).cgColor
            shade.backgroundColor = (m.selected || hovering || targeted ? (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.07)) : .clear).cgColor
        } else {
            let fill: NSColor = m.selected ? (m.palette.isDark ? NSColor.white.withAlphaComponent(0.13) : NSColor.white.withAlphaComponent(0.38))
                : (hovering || targeted ? (m.palette.isDark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.09)) : NSColor(m.palette.pillFill))
            layer?.backgroundColor = fill.cgColor
            shade.backgroundColor = NSColor.clear.cgColor
        }
        rim.borderWidth = m.selected ? 2 : 0
        rim.borderColor = (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.17)).cgColor
        var faviconColors = colors
        faviconColors.isDark = dark
        favicon.show(m.icon, flip: m.icon != nil && m.glyphDark == dark, colors: faviconColors)
        unreadDot.isHidden = !(m.unread && !m.selected)
        unreadDot.backgroundColor = (m.tileColor == nil ? colors.textPrimary : (dark ? NSColor.white : NSColor.black)).withAlphaComponent(0.6).cgColor
        if m.focus != (focusRing != nil) {
            if m.focus {
                let r = FocusRingLayer(radius: 13)
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
        favicon.frame = NSRect(x: (bounds.width - 20) / 2, y: (bounds.height - 20) / 2, width: 20, height: 20)
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

    override func mouseEntered(with event: NSEvent) { hovering = true; ArcTooltipController.shared.mouseMoved(in: self) }
    override func mouseMoved(with event: NSEvent) { ArcTooltipController.shared.mouseMoved(in: self) }
    override func mouseExited(with event: NSEvent) { hovering = false; ArcTooltipController.shared.mouseExited(self) }

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
            NSBezierPath(roundedRect: r, xRadius: 13, yRadius: 13).fill()
            rep?.draw(in: r)
            return true
        }
        item.setDraggingFrame(bounds, contents: image)
        beginDraggingSession(with: [item], event: p, source: self)
    }
    override func mouseUp(with event: NSEvent) {
        guard press != nil, let grid else { return }
        press = nil
        grid.ui.keyboardFocusID = nil
        grid.store.selectTab(itemID, window: grid.ui.windowID)
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
    var text: String { model?.title ?? "" }
    var keys: [String] { [] }
    var followsCursor: Bool { true }
    var subtitle: String? { nil }
    var optionText: String? { nil }
    var onShow: (() -> Void)? { nil }
    var screenFrame: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    var hostWindow: NSWindow? { window }
}
