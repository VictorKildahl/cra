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
    /// How far SpacePagerView holds the favorites left of their place (see holdFavorites).
    private var favoritesShift: CGFloat = 0

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
        list.header = header
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

    /// Arc's favorites sit beside its space pager, not on a page (AX tree, 25 Oct), so a swipe
    /// between spaces that share them (#154) leaves the tiles still. SpacePagerView shifts each
    /// of the two pages' copies back by the page's offset and shows the nearer page's one.
    func holdFavorites(shift: CGFloat, shown: Bool) {
        let alpha: CGFloat = shown ? 1 : 0
        guard shift != favoritesShift || favorites.alphaValue != alpha else { return }
        favoritesShift = shift
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        favorites.setFrameOrigin(NSPoint(x: 8 + shift, y: favorites.frame.minY))
        favorites.alphaValue = alpha
        CATransaction.commit()
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
        set(favorites, NSRect(x: 8 + favoritesShift, y: 0, width: w - 16, height: fh))
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
/// opens into "Add to Favorites" while a tab is dragged over it. With none, Arc's empty-state
/// card stands in for the tiles until its × closes it. Arc shares them between spaces; in Cra
/// every space has its own. While the toolbar is hidden the profile's pinned extensions sit
/// over the tiles in a grid of their own (PinnedExtensionGrid), as in Arc.
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
    private let card = FavoritesEmptyCard()
    private var extensionButtons: [String: ToolbarGlyphButton] = [:]
    private var extensionOrder: [String] = []
    private var favoritesID: UUID?
    private(set) var palette: SpacePalette?
    private var syncQueued = false
    /// A sidebar item dragged over the tiles and the slot held open for it (#176).
    private var drop: Drop? { didSet { if drop != oldValue { dropChanged(from: oldValue) } } }
    private struct Drop: Equatable {
        let id: UUID
        let slot: Int
    }

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
        strip.accepts = { [weak self] id in self?.isFavorite(id) != true }
        card.accepts = strip.accepts
        card.onDrop = strip.onDrop
        card.onDismiss = { [weak self] in
            guard let self, let id = self.favoritesID else { return }
            self.store.dismissFavoritesEmptyState(id)
        }
        card.isHidden = true
        addSubview(strip)
        addSubview(card)
        registerForDraggedTypes([.craSidebarItem])
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func sync() {
        syncQueued = false
        var models: [(UUID, FavoriteTileModel)] = []
        var palette: SpacePalette?
        var dismissed = true
        var pins: [Pin] = []
        withObservationTracking {
            guard let space = store.space(spaceID) else { return }
            palette = space.theme.palette
            // Arc (4 Nov): with the URL field in the sidebar, the pins leave it for this grid.
            if !store.settings.showToolbar, !store.isIncognito(space: spaceID) {
                let ext = ExtensionStore.shared
                let profile = store.profileDirectoryName(space: spaceID)
                let entries = ext.entries(inProfile: profile)
                let tab = store.selectedTabID(in: spaceID, window: ui.windowID)
                pins = ext.pinnedIDs(inProfile: profile).compactMap { id in
                    entries.first { $0.extensionID == id }.map {
                        Pin(id: id, name: $0.name, icon: ext.toolbarIcon(for: $0, profile: profile, tab: tab),
                            badge: ext.badge(for: $0, profile: profile, tab: tab))
                    }
                }
            }
            favoritesID = space.favoritesContainerID
            dismissed = store.isIncognito(space: spaceID) || store.isFavoritesEmptyStateDismissed(space.favoritesContainerID)
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
        let showsCard = ids.isEmpty && !dismissed
        // Arc drops the card and moves the list up in one frame, like a first tile coming in.
        let countChanged = ids.count != order.count || showsCard == card.isHidden || pins.count != extensionOrder.count
        showExtensions(pins, palette: palette)
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
        if let palette { strip.palette = palette; card.palette = palette }
        strip.hasFavorites = !ids.isEmpty
        // The card takes the strip's drops while it shows.
        strip.isHidden = showsCard
        card.isHidden = !showsCard
        needsLayout = true
        if countChanged { onHeightChange(false) }
    }

    private struct Pin { let id: String; let name: String; let icon: NSImage?; let badge: ExtensionBadge? }

    /// The pinned extensions' buttons, in pin order; none while the toolbar shows them. Arc 1.171
    /// (4 Nov) draws each cell like a favorite tile, the tile's fill at rest and its hover fill,
    /// the 18 pt icon centred, and names it in a tooltip (its toolbar pins have none, #106).
    private func showExtensions(_ pins: [Pin], palette: SpacePalette?) {
        let colors = palette.map(SidebarColors.init) ?? SidebarColors()
        let dark = palette?.isDark ?? false
        let ids = pins.map(\.id)
        for (id, b) in extensionButtons where !ids.contains(id) {
            b.removeFromSuperview()
            extensionButtons[id] = nil
        }
        let ext = ExtensionStore.shared
        for p in pins {
            let b = extensionButtons[p.id] ?? {
                let b = ToolbarGlyphButton()
                extensionButtons[p.id] = b
                addSubview(b)
                return b
            }()
            b.configure(symbol: nil, image: ext.badged(p.icon, p.badge, tint: colors.textSecondary), help: p.name, enabled: true,
                        width: 28, iconSize: 18, tint: colors.textSecondary,
                        hover: dark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.09))
            b.restFill = palette.map { NSColor($0.pillFill) } ?? .clear
            b.cornerRadius = 10
            b.iconRowHeight = PinnedExtensionGrid.cellHeight
            let id = p.id
            b.action = { [weak self] in self?.actions.runExtension(id) }
            b.menuProvider = { ExtensionStore.shared.entries.first { $0.extensionID == id }.map(ExtensionsMenu.iconMenu) }
        }
        extensionOrder = ids
    }

    /// None while they all fit in the URL field (`w` is its width too).
    private func extensionGrid(forWidth w: CGFloat) -> PinnedExtensionGrid {
        let n = extensionOrder.count
        return PinnedExtensionGrid(count: PinnedExtensionGrid.fitsInURLField(count: n, fieldWidth: w) ? 0 : n, width: w)
    }

    /// Arc's columns and tile frames (FavoritesLayout, #29). A drag over the tiles counts the slot
    /// it holds open, so a tab brought in from the list can add a row.
    private func grid(forWidth w: CGFloat) -> FavoritesLayout { FavoritesLayout(count: slotCount(drop), width: w) }

    /// The tiles that keep a place of their own: all but the one being dragged over the grid.
    private func restingOrder(_ drop: Drop?) -> [UUID] { drop.map { d in order.filter { $0 != d.id } } ?? order }

    private func slotCount(_ drop: Drop?) -> Int { restingOrder(drop).count + (drop == nil ? 0 : 1) }

    func height(forWidth w: CGFloat) -> CGFloat {
        let top = extensionGrid(forWidth: w).favoritesOffset
        if !card.isHidden { return top + FavoritesEmptyCard.height }
        return top + grid(forWidth: w).gridHeight + (order.isEmpty ? 0 : 4) + strip.height
    }

    /// Where the header and list are placed from: the tiles' bottom (the empty-state card's
    /// while it stands in for them), the open "Add to Favorites" strip's while a tab is dragged
    /// over it, the pinned extensions' with no favorites, nil with neither.
    func tilesBottom(forWidth w: CGFloat) -> CGFloat? {
        let ext = extensionGrid(forWidth: w)
        let top = ext.favoritesOffset
        if !card.isHidden { return top + FavoritesEmptyCard.height }
        if strip.targeted { return height(forWidth: w) }
        if order.isEmpty { return ext.count == 0 ? nil : ext.height }
        return top + grid(forWidth: w).gridHeight
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
        let ext = extensionGrid(forWidth: w)
        for (i, id) in extensionOrder.enumerated() {
            extensionButtons[id]?.isHidden = ext.count == 0
            if ext.count > 0 { extensionButtons[id]?.frame = ext.frame(at: i) }
        }
        let top = ext.favoritesOffset
        let grid = grid(forWidth: w)
        placeTiles(grid, top: top, animated: false)
        strip.frame = NSRect(x: 0, y: top + grid.gridHeight + (order.isEmpty ? 0 : 4), width: w, height: strip.height)
        card.frame = NSRect(x: 0, y: top, width: w, height: FavoritesEmptyCard.height)
    }

    /// Every tile in its slot. While a drag holds a slot open the tiles after it sit one slot
    /// along, and a favorite being dragged waits, hidden, in the open slot.
    private func placeTiles(_ grid: FavoritesLayout, top: CGFloat, animated: Bool) {
        let open = drop?.slot
        for (i, id) in restingOrder(drop).enumerated() {
            guard let t = tiles[id] else { continue }
            let f = grid.frame(at: FavoritesLayout.slot(ofTile: i, opening: open)).offsetBy(dx: 0, dy: top)
            // A tile that just came in, or was hidden, has no place to move from.
            if animated && t.frame != .zero && t.alphaValue > 0 { t.animator().frame = f } else { t.frame = f }
        }
        for (id, t) in tiles {
            let dragged = drop?.id == id
            if dragged, let open { t.frame = grid.frame(at: open).offsetBy(dx: 0, dy: top) }
            t.alphaValue = dragged ? 0 : 1
        }
    }

    private func dropChanged(from old: Drop?) {
        let w = bounds.width
        guard window != nil, w > 0 else { needsLayout = true; return }
        let grid = grid(forWidth: w)
        // Arc 1.171 (60 fps capture, 4 Nov): the tiles slide over ~0.15 s, fast at first.
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            placeTiles(grid, top: extensionGrid(forWidth: w).favoritesOffset, animated: true)
        }
        // A tab from the list can open a row, and leaving gives it back.
        if grid.rows != FavoritesLayout(count: slotCount(old), width: w).rows { onHeightChange(true) }
    }

    // MARK: Drops (#176)

    /// Arc's top apps take a drop between their tiles: the tile or tab dragged over them opens a
    /// slot under the pointer, the others move aside, and letting go puts it there.
    private func dropSlot(_ info: NSDraggingInfo) -> Drop? {
        guard !order.isEmpty,
              let data = info.draggingPasteboard.data(forType: .craSidebarItem),
              let id = (try? JSONDecoder().decode(SidebarDragItem.self, from: data))?.id,
              let item = store.item(id), item.isTab || item.isSplit,
              store.isIncognito(item: id) == store.isIncognito(space: spaceID) else { return nil }
        let w = bounds.width
        let top = extensionGrid(forWidth: w).favoritesOffset
        let p = convert(info.draggingLocation, from: nil)
        // The pinned extensions over the tiles take nothing.
        guard p.y >= top - FavoritesLayout.gap / 2 else { return nil }
        let grid = FavoritesLayout(count: order.filter { $0 != id }.count + 1, width: w)
        return Drop(id: id, slot: grid.slot(at: CGPoint(x: p.x, y: p.y - top)))
    }

    private func dragOperation(_ info: NSDraggingInfo) -> NSDragOperation {
        drop = dropSlot(info)
        guard drop != nil else { return [] }
        return info.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dragOperation(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dragOperation(sender) }
    /// Arc keeps a dragged favorite's slot open after it leaves the tiles (down over the header,
    /// 4 Nov); the slot closes when the drag ends or lands elsewhere. A tab from the list gives
    /// its slot back as it leaves.
    override func draggingExited(_ sender: NSDraggingInfo?) {
        if let d = drop, !order.contains(d.id) { drop = nil }
    }
    override func draggingEnded(_ sender: NSDraggingInfo) { drop = nil }

    /// The strip and the card only add: a favorite of this grid dragged over them is not offered
    /// "Add to Favorites" (Arc shows none under its tiles).
    func isFavorite(_ id: UUID) -> Bool { order.contains(id) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let d = drop ?? dropSlot(sender), let space = store.space(spaceID) else { drop = nil; return false }
        let container = space.favoritesContainerID
        let children = store.item(container)?.children ?? []
        let resting = order.filter { $0 != d.id }
        let index = d.slot < resting.count ? (children.firstIndex(of: resting[d.slot]) ?? children.count) : children.count
        if order.contains(d.id) {
            store.moveItem(d.id, to: container, index: index)
        } else {
            store.addToFavorites(d.id, in: spaceID, at: index)
        }
        if store.settings.hapticFeedbackOnReorder {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
        }
        // The new order lands with the slot closing, so nothing jumps.
        sync()
        drop = nil
        return true
    }

    /// The dragged favorite's session ended: dropped elsewhere, or let go outside the sidebar.
    func favoriteDragEnded() { drop = nil }

    func spaceFavoriteIDs() -> [UUID] {
        guard let space = store.space(spaceID) else { return [] }
        return store.favoriteTabs(in: space).map(\.id)
    }
}

/// Takes a sidebar item dropped on it into the favorites: the strip under the grid, or the
/// empty-state card in its place.
class FavoritesDropTarget: NSView {
    var onDrop: (UUID) -> Bool = { _ in false }
    var accepts: (UUID) -> Bool = { _ in true }
    var onTargetChange: (Bool) -> Void = { _ in }
    var palette: SpacePalette? { didSet { refresh() } }
    private(set) var targeted = false { didSet { if targeted != oldValue { refresh(); onTargetChange(targeted) } } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        registerForDraggedTypes([.craSidebarItem])
    }

    required init?(coder: NSCoder) { fatalError() }

    func refresh() {}

    private func draggedID(_ info: NSDraggingInfo) -> UUID? {
        guard let data = info.draggingPasteboard.data(forType: .craSidebarItem),
              let d = try? JSONDecoder().decode(SidebarDragItem.self, from: data), accepts(d.id) else { return nil }
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

/// The drop strip under the grid: 6–8 pt of nothing, 36 pt "Add to Favorites" while targeted.
final class FavoritesDropStrip: FavoritesDropTarget {
    var hasFavorites = true
    private let border = CAShapeLayer()
    private let label = NSTextField.sidebarLabel(size: 11, weight: .medium)

    var height: CGFloat { targeted ? 36 : (hasFavorites ? 6 : 8) }

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.cornerRadius = 10
        border.fillColor = nil
        border.lineWidth = 1
        border.lineDashPattern = [4, 3]
        layer?.addSublayer(border)
        label.stringValue = "Add to Favorites"
        label.alignment = .center
        addSubview(label)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func refresh() {
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
}

/// Arc's empty Favorites (Arc 1.171, live, 3 Nov, #157): a card where the tiles go, a star badge,
/// "Drag to add Favorites" and a line on what they are, in the space's own ink. It takes a dragged
/// tab, and its × (sidebarFavoritesEmptyStateDismissButton) closes it for good. Measured at 2x:
/// the fill sits where the first tile would (8 pt in, 12 pt corners) and is 93.5 pt tall; a 1 pt
/// dashed line (5.5 on, 4.5 off) runs just outside it; the header goes 4 pt further down than
/// under a row of tiles. No hover state; a tab dragged over it makes the line solid, lightens the
/// fill and dims the rest to half.
final class FavoritesEmptyCard: FavoritesDropTarget {
    static let fillHeight: CGFloat = 93.5
    /// Where the header is placed from, like the tiles' bottom.
    static let height: CGFloat = fillHeight + 4
    var onDismiss: () -> Void = {}
    private let fill = CAShapeLayer()
    private let border = CAShapeLayer()
    private let content = FlippedView()
    private let badge = NSImageView()
    private let title = NSTextField.sidebarLabel(size: 13, weight: .semibold)
    private let subtitle = NSTextField(wrappingLabelWithString: "")
    private let close = FavoritesEmptyCardClose()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer?.masksToBounds = false
        fill.lineWidth = 0
        border.fillColor = nil
        border.lineWidth = 1
        for l in [fill, border] {
            l.actions = ["path": NSNull(), "fillColor": NSNull(), "strokeColor": NSNull(), "lineDashPattern": NSNull()]
            layer?.addSublayer(l)
        }
        content.wantsLayer = true
        badge.imageScaling = .scaleNone
        badge.wantsLayer = true
        badge.shadow = NSShadow()
        title.stringValue = "Drag to add Favorites"
        title.alignment = .center
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.maximumNumberOfLines = 2
        close.onPress = { [weak self] in self?.onDismiss() }
        for v in [badge, title, subtitle, close] { content.addSubview(v) }
        addSubview(content)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func refresh() {
        guard let p = palette else { return }
        let dark = p.isDark
        // Arc's badge is the darkest ink on a light theme (the toolbar's shade) and the brightest on
        // a dark one; the star inside takes the other end, with a glow of its colour on dark themes.
        let ink = NSColor(dark ? p.textPrimary : p.toolbarFill)
        let star = NSColor(dark ? p.toolbarFill : p.folderFill)
        let text = dark ? NSColor.white.withAlphaComponent(0.85) : NSColor(p.textPrimary)
        let lighter = targeted ? 0.32 : 0.14
        fill.fillColor = (dark ? NSColor.black.withAlphaComponent(targeted ? 0 : 0.135) : NSColor.white.withAlphaComponent(lighter)).cgColor
        border.strokeColor = ink.withAlphaComponent(0.3).cgColor
        border.lineDashPattern = targeted ? nil : [5.5, 4.5]
        content.alphaValue = targeted ? 0.5 : 1
        badge.image = NSImage(systemSymbolName: "star.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
                .applying(NSImage.SymbolConfiguration(paletteColors: [star, ink])))
        badge.shadow?.shadowColor = dark ? star : .clear
        badge.shadow?.shadowBlurRadius = 6
        title.textColor = text
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.minimumLineHeight = 15
        para.maximumLineHeight = 15
        subtitle.attributedStringValue = NSAttributedString(string: "Favorites keep your most used sites and apps close",
                                                            attributes: [.font: NSFont.systemFont(ofSize: 11), .paragraphStyle: para,
                                                                         .foregroundColor: text.withAlphaComponent(text.alphaComponent * 0.7)])
        close.color = text.withAlphaComponent(text.alphaComponent * 0.7)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        let card = NSRect(x: 0, y: 0, width: w, height: Self.fillHeight)
        fill.frame = bounds
        border.frame = bounds
        fill.path = CGPath(roundedRect: card, cornerWidth: 12, cornerHeight: 12, transform: nil)
        border.path = CGPath(roundedRect: card.insetBy(dx: -0.5, dy: -0.5), cornerWidth: 12.5, cornerHeight: 12.5, transform: nil)
        content.frame = card
        // Arc's centres and frames, from the fill's top-left: badge centre 19.75 pt down, title 33.5–49.5,
        // subtitle 53–83 (two 15 pt lines, 150 pt wide), × centred 15 pt in from the top-right corner.
        let b = badge.image?.size ?? NSSize(width: 16, height: 16)
        badge.frame = NSRect(x: ((w - b.width) / 2).rounded(.down), y: (19.75 - b.height / 2).rounded(), width: b.width, height: b.height)
        title.frame = NSRect(x: 10, y: 33.5, width: max(0, w - 20), height: 16)
        let sw = min(150, max(0, w - 20))
        subtitle.frame = NSRect(x: ((w - sw) / 2).rounded(), y: 53, width: sw, height: 30)
        close.frame = NSRect(x: w - 15 - 7, y: 15 - 7, width: 14, height: 14)
    }
}

/// The card's ×: a plain glyph in the subtitle's tone, no hover fill (Arc).
final class FavoritesEmptyCardClose: NSView {
    var onPress: () -> Void = {}
    var color: NSColor = .labelColor { didSet { glyph.contentTintColor = color } }
    private let glyph = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        glyph.image = SidebarSymbols.image("xmark", size: 10, weight: .semibold)
        glyph.imageScaling = .scaleNone
        glyph.autoresizingMask = [.width, .height]
        addSubview(glyph)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Dismiss")
        setAccessibilityIdentifier("sidebarFavoritesEmptyStateDismissButton")
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        glyph.frame = bounds
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress() }
    }
    override func accessibilityPerformPress() -> Bool { onPress(); return true }
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
            shade.backgroundColor = (m.selected || hovering ? (dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.07)) : .clear).cgColor
        } else {
            let fill: NSColor = m.selected ? (palette.isDark ? NSColor.white.withAlphaComponent(0.13) : NSColor.white.withAlphaComponent(0.38))
                : (hovering ? (palette.isDark ? NSColor.white.withAlphaComponent(0.15) : NSColor.black.withAlphaComponent(0.09)) : NSColor(palette.pillFill))
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
        item.setDraggingFrame(bounds.insetBy(dx: -Self.dragShadow, dy: -Self.dragShadow), contents: dragImage())
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

    /// Room around the drag image for its shadow.
    private static let dragShadow: CGFloat = 6

    /// Arc 1.171 (4 Nov): the tile follows the pointer as a light card, white at about two thirds
    /// over the sidebar, the tile's corners and a soft shadow under it, with the icons on it.
    private func dragImage() -> NSImage {
        let icons = favicons.map { f -> (NSRect, NSBitmapImageRep?) in
            let rep = f.bitmapImageRepForCachingDisplay(in: f.bounds)
            if let rep { f.cacheDisplay(in: f.bounds, to: rep) }
            return (f.frame, rep)
        }
        let size = bounds.size, pad = Self.dragShadow
        return NSImage(size: NSSize(width: size.width + 2 * pad, height: size.height + 2 * pad), flipped: true) { _ in
            let card = NSRect(x: pad, y: pad, width: size.width, height: size.height)
            let shape = NSBezierPath(roundedRect: card, xRadius: FavoriteTileMetrics.corner, yRadius: FavoriteTileMetrics.corner)
            // The shadow only outside the card, so it doesn't show through the see-through fill.
            NSGraphicsContext.saveGraphicsState()
            let outside = NSBezierPath(rect: NSRect(x: 0, y: 0, width: card.maxX + pad, height: card.maxY + pad))
            outside.append(shape)
            outside.windingRule = .evenOdd
            outside.addClip()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = 4
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.set()
            NSColor.black.setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSColor.white.withAlphaComponent(0.67).setFill()
            shape.fill()
            for (f, rep) in icons { rep?.draw(in: f.offsetBy(dx: pad, dy: pad), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil) }
            return true
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        grid?.ui.draggingID = nil
        if grid?.ui.listDrop != nil { grid?.ui.listDrop = nil }
        grid?.favoriteDragEnded()
    }

    // MARK: Menu

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let grid, let item = grid.store.item(itemID) else { return nil }
        let store = grid.store, ui = grid.ui, actions = grid.actions, favicons = grid.favicons
        let id = itemID
        if item.isSplit, let m = model {
            return SidebarMenus.split(id, panes: m.cells.map { ($0.id, $0.title) }, open: m.selected, store: store, ui: ui, actions: actions) {
                MenuItems.add($0, action: "favoriteTab", title: Self.removeTitle(id, store)) { store.removeFromFavorites(id) }
                Self.moveToProfile($0, id, store)
                $0.addItem(.separator())
            }
        }
        let tileColor = item.tab?.tileColor
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, action: "favoriteTab", title: Self.removeTitle(id, store)) { store.removeFromFavorites(id) }
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
        Self.moveToProfile(m, id, store)
        m.addItem(.separator())
        MenuItems.add(m, action: "closeTab", title: "Close") { actions.closeTab(id) }
        MenuItems.add(m, "Archive") { store.archiveTab(id, reason: .manual) }
        return m
    }

    /// Shared favorites (#154) take Arc's words: Remove Favorite deletes the favorite.
    private static func removeTitle(_ id: UUID, _ store: SidebarStore) -> String {
        store.profileList(ofItem: id) == nil ? "Remove from Favorites" : "Remove Favorite"
    }

    /// Arc 1.171's Move to ▸ Profile ▸ ✓Default / <profile>… on a shared favorite.
    private static func moveToProfile(_ menu: NSMenu, _ id: UUID, _ store: SidebarStore) {
        guard let list = store.profileList(ofItem: id) else { return }
        let profiles = MenuItems.submenu(MenuItems.submenu(menu, "Move to"), "Profile")
        MenuItems.add(profiles, "Default", on: list.profileID == nil) { store.moveFavorite(id, toProfile: nil) }
        for p in store.profiles {
            MenuItems.add(profiles, p.name, on: list.profileID == p.id) { store.moveFavorite(id, toProfile: p.id) }
        }
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
