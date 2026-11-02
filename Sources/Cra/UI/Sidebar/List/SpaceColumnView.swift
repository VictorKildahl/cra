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
        header = SpaceHeaderView(spaceID: spaceID, store: store, ui: ui, actions: actions)
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
    /// the first tile's top goes): the header's hover fill 8–44 pt below, 8 pt in from both
    /// sides like the tiles (measured 1 Nov), the divider line 54.5 pt below. With the header
    /// hidden the line is 18.5 pt under the tiles, 15.5 pt under the URL field.
    private func place(animated: Bool) {
        let w = bounds.width
        let fh = favorites.height(forWidth: w - 16)
        let set = { (v: NSView, f: NSRect) in if v.frame != f { animated ? (v.animator().frame = f) : (v.frame = f) } }
        set(favorites, NSRect(x: 8, y: 0, width: w - 16, height: fh))
        let tiles = favorites.tilesBottom(forWidth: w - 16)
        let base = tiles ?? -8
        set(header, NSRect(x: 8, y: base + 8, width: w - 16, height: header.isHidden ? 0 : 36))
        // The list's line sits 11.5 pt into it (3 pt inset, then halfway down the 18 pt divider).
        let top = base + (!header.isHidden ? 43 : tiles == nil ? 4 : 7)
        set(list, NSRect(x: 0, y: top, width: w, height: max(0, bounds.height - top)))
    }
}

// MARK: - Space header

/// The space's emoji and name. Arc 1.171 (live, 1 Nov): a click collapses or expands the pinned
/// tabs; on hover the fill comes in, the chevron takes the icon's place and the ••• button
/// (sidebarSpaceEditButton) shows at the trailing edge, all in one frame. The ••• and a
/// right-click open the same space menu at the pointer. Collapsed, the chevron stays and points right.
final class SpaceHeaderView: NSView, NSTextFieldDelegate {
    private let spaceID: UUID
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let emoji = NSTextField.sidebarLabel(size: 14)
    private let title = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    /// An Icon-tab glyph in the emoji's place.
    private let symbol = NSImageView()
    private let chevron = NSImageView()
    /// Holds the chevron at a fixed 20 pt frame, so it turns about its own centre while layout
    /// moves the box.
    private let chevronBox = NSView()
    private lazy var more = SidebarGlyphButton(symbol: "ellipsis", size: 24, height: 24, iconSize: 13, weight: .semibold, help: "", colors: colors) { [weak self] in
        self?.showMenu(NSApp.currentEvent)
    }
    /// Rename Space…: the name turns into a field and the ••• into Arc's "Done".
    private let done = NSTextField.sidebarLabel(size: 10, weight: .semibold)
    private var renameField: NSTextField?
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }
    /// Arc keeps the hover look while the space menu is open.
    private var menuOpen = false { didSet { if menuOpen != oldValue { refresh() } } }
    private var collapsed = false
    private var colors = SidebarColors()
    private var syncQueued = false
    /// The column lays out again when Arc's single-space mode hides or shows the header.
    var onHiddenChange: (() -> Void)?

    init(spaceID: UUID, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions) {
        self.spaceID = spaceID
        self.store = store
        self.ui = ui
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        // Pixel-fitted to Arc's 2x capture (chevron.down 12.5 bold, ellipsis 13 semibold; #57).
        chevron.image = SidebarSymbols.image("chevron.down", size: 12.5, weight: .bold)
        chevron.imageScaling = .scaleNone
        chevron.wantsLayer = true
        chevron.frame = NSRect(x: 0, y: 0, width: 20, height: 20)
        chevronBox.addSubview(chevron)
        done.stringValue = "Done"
        done.isHidden = true
        symbol.imageScaling = .scaleNone
        for v in [emoji, symbol, title, chevronBox, more, done] { addSubview(v) }
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func sync() {
        syncQueued = false
        var hide = false
        let wasCollapsed = collapsed
        withObservationTracking {
            guard let space = store.space(spaceID) else { return }
            emoji.stringValue = space.emoji
            symbol.image = space.symbol.flatMap { SidebarSymbols.image($0, size: 13, weight: .medium) }
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
        if collapsed != wasCollapsed { turnChevron() }
        refresh()
        if hide != isHidden {
            isHidden = hide
            onHiddenChange?()
        }
    }

    private func refresh() {
        let lit = hovering || menuOpen || renameField != nil
        // Arc's dark header title is dimmer than its other secondary text (white 0.45, 1 Nov).
        title.textColor = colors.isDark ? NSColor.white.withAlphaComponent(0.45) : colors.textSecondary
        done.textColor = colors.textTertiary
        chevron.contentTintColor = colors.textSecondary
        more.tint = colors.textSecondary
        let showsChevron = lit || collapsed
        chevron.alphaValue = showsChevron ? 1 : 0
        emoji.alphaValue = showsChevron ? 0 : 1
        symbol.alphaValue = showsChevron ? 0 : 1
        symbol.contentTintColor = colors.textSecondary
        more.colors = colors
        more.isHidden = !lit || renameField != nil
        done.isHidden = renameField == nil
        // Arc's dark header fill is white 0.10, a little lighter than its rows' (1 Nov).
        let fill = colors.isDark ? NSColor.white.withAlphaComponent(0.1) : colors.hoverFill
        layer?.backgroundColor = (lit ? fill : .clear).cgColor
        needsLayout = true
    }

    /// Arc points the chevron down while the pinned tabs show and right while they are collapsed,
    /// and turns it a quarter over about 0.12 s (a 60 fps capture, 1 Nov). The turn is AppKit's own
    /// rotation: one set on the layer was reset by AppKit's layer geometry, so a space that opened
    /// collapsed showed the chevron pointing down.
    private func turnChevron() {
        let degrees: CGFloat = collapsed ? 90 : 0
        guard window != nil else { chevron.frameCenterRotation = degrees; return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            chevron.animator().frameCenterRotation = degrees
        }
    }

    /// Arc 1.171, 2x captures (1 Nov): a 14.5 pt emoji centred in the icon's 26 pt box 5 pt in (its
    /// line box sits 0.75 pt low), the chevron (13 pt semibold) in the icon's place, the name (13 pt
    /// semibold) 36 pt in, the ••• (24 pt fill in a 26 pt frame) centred 18.5 pt from the trailing edge.
    /// The name stops 2 pt before that frame, or 8.5 pt from the edge while the button is hidden.
    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        let es = emoji.intrinsicContentSize
        let ew = emoji.attributedStringValue.size().width
        emoji.frame = NSRect(x: 18.25 - ew / 2 - SidebarText.inset, y: (h - es.height) / 2 - 1.25, width: ew + 2 * SidebarText.inset, height: es.height)
        symbol.frame = iconRect
        // Turned right, Arc's chevron sits a little higher than chevron.down turned about its centre.
        let (cx, cy): (CGFloat, CGFloat) = collapsed ? (18.5, h / 2 - 0.25) : (18.25, h / 2 + 0.5)
        chevronBox.frame = NSRect(x: cx - 10, y: cy - 10, width: 20, height: 20)
        more.frame = NSRect(x: w - 18.5 - 12, y: (h - 24) / 2 + 0.5, width: 24, height: 24)
        let dw = ceil(done.attributedStringValue.size().width) + 2 * SidebarText.inset
        let dh = done.intrinsicContentSize.height
        done.frame = NSRect(x: w - 5.5 - dw + SidebarText.inset, y: (h - dh) / 2, width: dw, height: dh)
        let x: CGFloat = 36
        let end = renameField != nil ? done.frame.minX - 6 : (more.isHidden ? w - 8.5 : w - 18.5 - 13 - 2)
        let th = title.intrinsicContentSize.height
        let tw = min(ceil(title.attributedStringValue.size().width), max(0, end - x))
        title.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: tw + 2 * SidebarText.inset, height: th)
        renameField?.frame = NSRect(x: x - SidebarText.inset, y: (h - th) / 2, width: max(0, end - x) + 2 * SidebarText.inset, height: th)
    }

    /// The icon's 26 pt box: Change Space Icon… points its popover at it.
    var iconRect: NSRect { NSRect(x: 5, y: (bounds.height - 26) / 2, width: 26, height: 26) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p) else { return }
        if renameField != nil {
            if done.frame.insetBy(dx: -6, dy: -6).contains(p) { commitRename() }
            return
        }
        store.togglePinnedCollapsed(spaceID)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        renameField == nil ? makeSpaceMenu() : nil
    }

    /// The ••• opens the menu where it was clicked, as a right-click does (Arc pops it up at the
    /// pointer, not under the button). The button acts on mouse-up, and a context menu needs a
    /// mouse-down to place itself, so it gets one at the same point.
    private func showMenu(_ event: NSEvent?) {
        guard let event, let m = makeSpaceMenu(),
              let down = NSEvent.mouseEvent(with: .rightMouseDown, location: event.locationInWindow, modifierFlags: [],
                                            timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                            eventNumber: 0, clickCount: 1, pressure: 1) else { return }
        menuOpen = true
        NSMenu.popUpContextMenu(m, with: down, for: self)
        menuOpen = false
        if let w = window { hovering = bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) { menuOpen = true }
    override func didCloseMenu(_ menu: NSMenu, with event: NSEvent?) {
        menuOpen = false
        if let w = window { hovering = bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) }
    }

    private func makeSpaceMenu() -> NSMenu? {
        SpaceMenu.make(spaceID: spaceID, store: store, ui: ui, actions: actions, anchor: self) { [weak self] in self?.beginRename() }
    }

    // MARK: Rename (Arc: isEditingSpaceHeader, "Sidebar space header done button")

    func beginRename() {
        guard renameField == nil, let space = store.space(spaceID) else { return }
        let f = NSTextField(string: space.title)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = title.font
        f.textColor = colors.textPrimary
        f.delegate = self
        f.cell?.isScrollable = true
        renameField = f
        addSubview(f)
        title.isHidden = true
        refresh()
        DispatchQueue.main.async { [weak self, weak f] in
            guard let f, let w = self?.window else { return }
            w.makeFirstResponder(f)
            f.currentEditor()?.selectAll(nil)
        }
    }

    private func endRename() {
        guard let f = renameField else { return }
        renameField = nil
        f.delegate = nil
        if let w = window, let editor = f.currentEditor(), w.firstResponder === editor { w.makeFirstResponder(nil) }
        f.removeFromSuperview()
        title.isHidden = false
        if let w = window { hovering = bounds.contains(convert(w.mouseLocationOutsideOfEventStream, from: nil)) }
        refresh()
    }

    private func commitRename() {
        guard let f = renameField, var space = store.space(spaceID) else { return }
        let name = f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        endRename()
        guard !name.isEmpty, name != space.title else { return }
        space.title = name
        store.updateSpace(space)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        if sel == #selector(NSResponder.cancelOperation(_:)) { endRename(); return true }
        if sel == #selector(NSResponder.insertNewline(_:)) { commitRename(); return true }
        return false
    }

    func controlTextDidEndEditing(_ obj: Notification) { commitRename() }
}

/// Arc 1.171's space menu (SpaceMenu.swift), item for item, for the space header's ••• and
/// right-click and the Library's Spaces page. "Share Space…" is left out: it publishes the space
/// through Arc's servers.
@MainActor
enum SpaceMenu {
    static func make(spaceID id: UUID, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, anchor: NSView,
                     rename: @escaping () -> Void) -> NSMenu? {
        guard let space = store.space(id) else { return nil }
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, "Change Space Icon…") { [weak anchor] in if let anchor { actions.changeSpaceIcon(space, anchor) } }
        MenuItems.add(m, "Rename Space…", rename)
        MenuItems.add(m, "Edit Theme Color…") { actions.editSpaceTheme(space) }
        let profiles = MenuItems.submenu(m, "Set Profile")
        MenuItems.add(profiles, "Default", on: space.profileID == nil) { store.setProfile(nil, forSpace: id) }
        for p in store.profiles {
            MenuItems.add(profiles, p.name, on: space.profileID == p.id) { store.setProfile(p.id, forSpace: id) }
        }
        profiles.addItem(.separator())
        MenuItems.add(profiles, "New Profile…") { actions.newProfile(id) }
        m.addItem(.separator())
        MenuItems.add(m, action: "newFolder") {
            ui.renamingID = store.createFolder(named: "New Folder", in: space.pinnedContainerID, index: 0).id
        }
        let live = MenuItems.submenu(m, "Live Folders")
        let github = store.liveFolder(.github, inSpace: id)
        MenuItems.add(live, "GitHub", on: github != nil) {
            if let github {
                SidebarMenus.confirmDeleteLiveFolder(github, store: store)
            } else if let f = store.createLiveFolder(.github, inSpace: id) {
                store.setExpanded(f.id, true)
                LiveFolderManager.shared.refresh(f.id)
            }
        }
        m.addItem(.separator())
        let export = MenuItems.submenu(m, "Export “\(space.title)” into Folder")
        for s in store.orderedSpaces {
            MenuItems.add(export, s.title, enabled: s.id != id) { store.exportSpace(id, intoFolderIn: s.id) }
        }
        m.addItem(.separator())
        MenuItems.add(m, action: "manageSpaces") { actions.manageSpaces() }
        // Arc offers this only while there is one space; Show Space Header brings it back.
        if store.orderedSpaces.count == 1 {
            MenuItems.add(m, "Hide Space Header") { store.settings.showSpaceHeaderOnSingleSpace = false }
        }
        m.addItem(.separator())
        MenuItems.add(m, action: "deleteSpace", title: "Delete Space") { actions.deleteSpace(space) }
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

    /// A row for a KeyBindings command: its name, unless the menu words it its own way (Arc's
    /// "Pin Tab" for pinTab), and its shortcut on the right, as in the menu bar (#89).
    @discardableResult
    static func add(_ menu: NSMenu, action id: String, title: String? = nil, enabled: Bool = true, on: Bool? = nil,
                    _ run: @escaping () -> Void) -> NSMenuItem {
        let item = add(menu, title ?? KeyBindingRegistry.shared.action(id)?.name ?? id, enabled: enabled, on: on, run)
        item.showShortcut(of: id)
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

    /// Arc's columns and tile frames (FavoritesLayout, #29).
    private func grid(forWidth w: CGFloat) -> FavoritesLayout { FavoritesLayout(count: order.count, width: w) }

    func height(forWidth w: CGFloat) -> CGFloat {
        grid(forWidth: w).gridHeight + (order.isEmpty ? 0 : 4) + strip.height
    }

    /// Where the header and list are placed from: the tiles' bottom, the open "Add to Favorites"
    /// strip's while a tab is dragged over it, nil with no favorites.
    func tilesBottom(forWidth w: CGFloat) -> CGFloat? {
        if strip.targeted { return height(forWidth: w) }
        return order.isEmpty ? nil : grid(forWidth: w).gridHeight
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
        let grid = grid(forWidth: w)
        for (i, id) in order.enumerated() { tiles[id]?.frame = grid.frame(at: i) }
        strip.frame = NSRect(x: 0, y: grid.gridHeight + (order.isEmpty ? 0 : 4), width: w, height: strip.height)
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
                MenuItems.add($0, action: "favoriteTab", title: "Remove from Favorites") { store.removeFromFavorites(id) }
                $0.addItem(.separator())
            }
        }
        let tileColor = item.tab?.tileColor
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, action: "favoriteTab", title: "Remove from Favorites") { store.removeFromFavorites(id) }
        MenuItems.add(m, action: "renameTab", title: "Rename…") { ui.renamingID = id }
        if let t = item.tab, t.liveItemURL == nil {
            SidebarMenus.pinnedURLItems(m, id, navigatedAway: t.url != t.savedURL, store: store, actions: actions)
        }
        MenuItems.add(m, action: "copyURL", title: "Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.tab?.url ?? "", forType: .string)
        }
        if let t = item.tab, t.url != t.savedURL {
            MenuItems.add(m, action: "resetTab", title: "Back to Pinned Page") { actions.resetPinnedTab(id) }
        }
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
        MenuItems.add(m, action: "closeTab", title: "Close") { actions.closeTab(id) }
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
