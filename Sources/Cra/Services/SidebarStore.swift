import Foundation
import Observation

/// The single source of truth for spaces, tabs, folders, favorites, the
/// archive and window preferences. Mutations here are what Arc's
/// SidebarDataStore mutations do; persistence mirrors its Storable*.json files.
@MainActor
@Observable
final class SidebarStore {
    // MARK: State

    private(set) var spaces: [UUID: Space] = [:]
    /// The stored theme of a space whose theme an editor is previewing (`previewTheme`): what
    /// goes to disk until the editor saves, and what Cancel or Escape puts back.
    @ObservationIgnored private var storedThemes: [UUID: SpaceTheme] = [:]
    private(set) var spaceOrder: [UUID] = []
    /// Profiles besides Default, in the order they were made.
    private(set) var profiles: [BrowserProfile] = []
    /// Arc's favorites per profile, with Share Favorites on (#154): the list each profile's
    /// spaces show. One stays while no space uses its profile.
    private(set) var profileFavorites: [ProfileFavorites] = []
    /// Observed item by item (ItemTable): a view re-renders when an item it read changes.
    let items = ItemTable()
    private(set) var archive: [ArchivedItem] = [] { didSet { archiveChanged = true } }
    /// archive.json is by far the largest file; it is written only when the archive changed.
    @ObservationIgnored private var archiveChanged = false
    var prefs = WindowPrefs() {
        didSet {
            prefsStore.save(prefs.withoutIncognito)
            notifyItemReaders(of: oldValue)
        }
    }
    var settings = AppSettings() { didSet { settingsStore.save(settings) } }
    private(set) var history: [String: HistoryEntry] = [:]
    private(set) var ranking = RankingData()
    /// Bumped on every structural change; cheap way for AppKit code to observe.
    private(set) var revision = 0
    /// The browser window that menu commands, new tabs and the command bar act on:
    /// the one the user is in (AppDelegate follows the key window).
    @ObservationIgnored var activeWindowID = UUID() {
        didSet { if !isStandalone(window: activeWindowID) { lastNormalWindowID = activeWindowID } }
    }
    /// The normal window in use last: where links from other apps and the Library go
    /// while an incognito or Blank Window is in front.
    @ObservationIgnored private(set) var lastNormalWindowID = UUID()
    /// Spaces of incognito windows. Not in `spaceOrder`, never saved.
    private(set) var incognitoSpaceIDs: Set<UUID> = []
    /// Spaces of Blank Windows (BlankWindow, #220): saved with the window, in no space list.
    private(set) var blankSpaceIDs: Set<UUID> = []
    /// Per window, the tab shown before the selected one: a close goes back to it (CloseSuccessor).
    /// Not saved: after a relaunch it has no page, so Arc wouldn't go back to it either.
    @ObservationIgnored private var previousTab: [UUID: UUID] = [:]
    /// Per window and space, the pinned row a collapsed pinned section keeps in sight (PinnedPeek).
    /// Not saved, like Arc's peekedPinnedSidebarItemID. Observed: the collapsed list draws it.
    private var pinnedPeeks: [UUID: [UUID: UUID]] = [:]
    /// Whether a tab's page is loaded; AppDelegate asks the windows' browser managers.
    @ObservationIgnored var hasPage: (UUID) -> Bool = { _ in true }
    /// A tab came into a space's pinned tabs from elsewhere (⌘D, a drag, a menu): Tidy Tab Titles
    /// may give it a shorter name (TidyTitlesService).
    @ObservationIgnored var tabPinned: (UUID) -> Void = { _ in }
    @ObservationIgnored var liveFolderChanged: (UUID) -> Void = { _ in }
    @ObservationIgnored private var liveFolderVersions: [UUID: UUID] = [:]

    // MARK: Persistence

    private let sidebarFile = JSONStore<SidebarDocument>("sidebar.json")
    private let archiveFile = JSONStore<[ArchivedItem]>("archive.json")
    private let prefsStore = JSONStore<WindowPrefs>("windows.json")
    private let settingsStore = JSONStore<AppSettings>("settings.json")
    private let historyFile = JSONStore<[HistoryEntry]>("history.json")
    private let rankingFile = JSONStore<RankingData>("commandbar.json")
    /// Every date the store stamps or compares (AppComposition passes the app's clock).
    @ObservationIgnored let clock: Scheduler

    init(clock: Scheduler? = nil) {
        self.clock = clock ?? LiveScheduler.shared
        let doc = sidebarFile.load(or: SidebarDocument.fresh)
        for s in doc.spaces {
            spaces[s.id] = s
            if s.standaloneWindowID != nil { blankSpaceIDs.insert(s.id) }
        }
        profiles = doc.profiles ?? []
        profileFavorites = doc.profileFavorites ?? []
        spaceOrder = BlankWindow.spaceOrder(saved: doc.spaceOrder, spaces: doc.spaces)
        for it in doc.items { items[it.id] = it }
        archive = archiveFile.load(or: { [] })
        archiveChanged = false
        prefs = prefsStore.load(or: { WindowPrefs() })
        var loaded = settingsStore.load(or: { AppSettings() })
        loaded.migrateToolbarDefault(arcShowsToolbar: ArcImporter.showsToolbar)
        settings = loaded
        for h in historyFile.load(or: { [] }) { history[h.url] = h }
        ranking = rankingFile.load(or: { RankingData() })
        // A Blank Window's space without its window goes; repair drops what was in it.
        for sid in BlankWindow.orphans(spaces: Array(spaces.values), windows: prefs.windows) {
            spaces[sid] = nil
            blankSpaceIDs.remove(sid)
        }
        repair()
        if prefs.windows.isEmpty { prefs.windows = [WindowSession()] }
        for i in prefs.windows.indices where prefs.windows[i].focusedSpaceID.flatMap({ spaces[$0] }) == nil {
            prefs.windows[i].focusedSpaceID = spaceOrder.first
        }
        activeWindowID = prefs.windows[0].id
        lastNormalWindowID = prefs.windows.first { !isStandalone(window: $0.id) }?.id ?? activeWindowID
        splitSharedFavorites(doc.favoritesContainerID)
        // Lists as the setting has them, also in a file an older Cra or a hand edit wrote.
        settings.sharedFavorites ? shareFavorites() : unshareFavorites()
    }

    /// Make sure every space has its containers and no item points at a
    /// parent that is gone.
    func repair() {
        for (id, var space) in spaces {
            if items[space.favoritesContainerID] == nil {
                let c = SidebarItem.container(.favorites(spaceID: id), id: space.favoritesContainerID)
                items[c.id] = c
            }
            if items[space.pinnedContainerID] == nil {
                let c = SidebarItem.container(.pinned(spaceID: id), id: space.pinnedContainerID)
                items[c.id] = c
            }
            if items[space.todayContainerID] == nil {
                let c = SidebarItem.container(.today(spaceID: id), id: space.todayContainerID)
                items[c.id] = c
            }
            // A profile that is gone: the space falls back to Default (Arc does the same).
            if let p = space.profileID, !profiles.contains(where: { $0.id == p }) { space.profileID = nil }
            spaces[id] = space
        }
        // No space a window can list (none, or only Blank Windows' own).
        if spaceOrder.isEmpty {
            let doc = SidebarDocument.fresh()
            for s in doc.spaces { spaces[s.id] = s }
            spaceOrder = doc.spaceOrder
            for it in doc.items { items[it.id] = it }
        }
        // Containers of a space that is gone, with everything in them: an incognito window's,
        // which updateTab used to write to disk. Its tabs never showed in a space again, but
        // the command bar offered them in normal windows. They go before the orphan pass below
        // would move them into a space.
        func drop(_ id: UUID) {
            for c in items[id]?.children ?? [] { drop(c) }
            items[id] = nil
        }
        for (id, it) in items.all {
            guard let sid = it.container?.spaceID, spaces[sid] == nil, sid != ContainerKind.sharedFavoritesSpaceID else { continue }
            drop(id)
        }
        // Drop children references that do not resolve and orphans.
        for (id, var it) in items.all {
            it.children = it.children.filter { items[$0] != nil && items[$0]?.parentID == id }
            items[id] = it
        }
        for (id, it) in items.all where it.container == nil {
            if let p = it.parentID, let parent = items[p], parent.children.contains(id) { continue }
            // Orphan: put it in the first space's today list rather than losing it.
            if let space = spaceOrder.first.flatMap({ spaces[$0] }) {
                var fixed = it
                fixed.parentID = space.todayContainerID
                items[id] = fixed
                items[space.todayContainerID]?.children.append(id)
            }
        }
    }

    /// Favorites used to be one set every space shared. Each space gets its own
    /// copy of that set so nothing disappears anywhere; the focused space keeps
    /// the original tabs, other spaces get copies.
    private func splitSharedFavorites(_ sharedID: UUID?) {
        guard let sharedID, let shared = items[sharedID] else { return }
        for sid in spaceOrder {
            guard let space = spaces[sid] else { continue }
            var copies: [UUID: UUID] = [:]
            for child in shared.children {
                if sid == focusedSpaceID {
                    items[child]?.parentID = space.favoritesContainerID
                    items[space.favoritesContainerID]?.children.append(child)
                } else {
                    copySubtree(child, into: space.favoritesContainerID, copies: &copies)
                }
            }
            // A favorite open in this space stays open: it is now this space's copy.
            for i in prefs.windows.indices {
                if let sel = prefs.windows[i].selectedTabPerSpace[sid], let copy = copies[sel] { prefs.windows[i].selectedTabPerSpace[sid] = copy }
            }
            for (old, new) in copies where prefs.expandedFolders.contains(old) { prefs.expandedFolders.insert(new) }
        }
        items[sharedID] = nil
        touch()
    }

    private func copySubtree(_ id: UUID, into parent: UUID, copies: inout [UUID: UUID]) {
        guard var it = items[id] else { return }
        let kids = it.children
        it.id = UUID()
        it.parentID = parent
        it.children = []
        copies[id] = it.id
        items[it.id] = it
        items[parent]?.children.append(it.id)
        for k in kids { copySubtree(k, into: it.id, copies: &copies) }
    }

    func save() {
        sidebarFile.save(document)
        if archiveChanged {
            archiveChanged = false
            archiveFile.save(archive)
        }
    }

    func saveAll() {
        sidebarFile.saveNow(document)
        archiveFile.saveNow(archive)
        prefsStore.saveNow(prefs.withoutIncognito)
        settingsStore.saveNow(settings)
        historyFile.saveNow(Array(history.values))
        rankingFile.saveNow(ranking)
    }

    private func touch() {
        pruneEmptyGroups()
        revision &+= 1
        save()
    }

    // MARK: Windows

    private func windowIndex(_ id: UUID?) -> Int {
        prefs.windows.firstIndex { $0.id == (id ?? activeWindowID) } ?? prefs.windows.firstIndex { $0.id == activeWindowID } ?? 0
    }

    /// A window's state; an unknown id (a window that is gone) reads as the active window.
    func window(_ id: UUID? = nil) -> WindowSession { prefs.windows[windowIndex(id)] }

    /// No-op for a window that is gone.
    func updateWindow(_ id: UUID?, _ change: (inout WindowSession) -> Void) {
        guard let i = prefs.windows.firstIndex(where: { $0.id == (id ?? activeWindowID) }) else { return }
        var w = prefs.windows[i]
        change(&w)
        guard w != prefs.windows[i] else { return }
        // Whatever changes what the window shows (a pick, a close, a space switch), the tab it
        // showed is the one a close goes back to (CloseSuccessor; Arc counts space switches too).
        let shown = { (s: WindowSession) in s.focusedSpaceID.flatMap { s.selectedTabPerSpace[$0] } }
        if shown(w) != shown(prefs.windows[i]) { previousTab[w.id] = shown(prefs.windows[i]) }
        // A pinned tab coming on screen is the one its collapsed section keeps in sight; a
        // favorite or a Today tab leaves the one before (Arc's peekedPinnedSidebarItemID).
        var peeks = pinnedPeeks[w.id] ?? [:]
        for (sid, tab) in w.selectedTabPerSpace where prefs.windows[i].selectedTabPerSpace[sid] != tab {
            peeks[sid] = PinnedPeek.showing(pinnedRow: pinnedRow(of: tab, in: sid), peek: peeks[sid])
        }
        if peeks != (pinnedPeeks[w.id] ?? [:]) { pinnedPeeks[w.id] = peeks }
        prefs.windows[i] = w
    }

    /// The row a tab draws in a space's pinned section (the tab, or the split holding it); nil
    /// when it isn't pinned there.
    private func pinnedRow(of tab: UUID, in sid: UUID) -> UUID? {
        guard let row = splitContaining(tab) ?? items[tab], rootContainer(of: row.id) == .pinned(spaceID: sid) else { return nil }
        return row.id
    }

    /// Every row a space's pinned section can draw, in sidebar order: tabs and splits, the ones
    /// in folders included.
    private func pinnedRows(in space: Space) -> [UUID] {
        var out: [UUID] = []
        func walk(_ id: UUID) {
            for c in children(of: id) {
                if c.isTab || c.isSplit { out.append(c.id) } else { walk(c.id) }
            }
        }
        walk(space.pinnedContainerID)
        return out
    }

    /// A new window on `spaceID` with nothing open yet (never on another window's own space).
    func addWindow(spaceID: UUID, frame: String?) -> WindowSession {
        let w = WindowSession(focusedSpaceID: isStandalone(space: spaceID) ? spaceOrder.first : spaceID, frame: frame)
        prefs.windows.append(w)
        return w
    }

    /// Arc's "When opening Arc, restore windows from previous session" turned off: launch keeps
    /// one window, the one in use last (a normal one when that was a Blank or incognito window).
    func keepOnlyActiveWindow() {
        let keep = prefs.windows.first { $0.id == activeWindowID && !isStandalone(window: $0.id) }
            ?? prefs.windows.first { !isStandalone(window: $0.id) } ?? prefs.windows.first
        guard let keep else { return }
        for w in prefs.windows where w.id != keep.id { removeWindow(w.id) }
        activeWindowID = keep.id
    }

    /// The last window is never removed: closing it only hides it. An incognito or Blank
    /// Window's tabs go with it (not to the Library): Arc drops a Blank Window's sidebar.
    func removeWindow(_ id: UUID) {
        guard prefs.windows.count > 1, let gone = prefs.windows.first(where: { $0.id == id }) else { return }
        let own = isStandalone(window: id) ? gone.focusedSpaceID : nil
        prefs.windows.removeAll { $0.id == id }
        pinnedPeeks[id] = nil
        if activeWindowID == id { activeWindowID = prefs.windows.first { !isStandalone(window: $0.id) }?.id ?? prefs.windows[0].id }
        if let sid = own, let space = spaces[sid] {
            var ids = Set<UUID>()
            collectSubtree(of: space, into: &ids)
            for i in ids { items[i] = nil }
            spaces[sid] = nil
            incognitoSpaceIDs.remove(sid)
            blankSpaceIDs.remove(sid)
            touch()
        }
    }

    /// Arc's Blank Window (⌃⌘N, #220): a window in the normal profile with a sidebar of its
    /// own, "This Window", that none of the spaces' tabs show in. Saved and restored with it.
    func addBlankWindow(frame: String?) -> WindowSession {
        var w = WindowSession(frame: frame)
        let (space, containers) = BlankWindow.space(window: w.id, at: clock.now)
        for c in containers { items[c.id] = c }
        spaces[space.id] = space
        blankSpaceIDs.insert(space.id)
        w.focusedSpaceID = space.id
        prefs.windows.append(w)
        touch()
        return w
    }

    /// A torn-off tab (#219) moves into a Blank Window's tabs and opens there; the window it left
    /// loses it, as in Arc (no other tab opens in its place). A new Blank Window takes the tab's
    /// profile, so its page stays signed in and isn't loaded again elsewhere (#288; Arc keeps the
    /// window on the space's profile).
    func moveToBlankWindow(_ id: UUID, window: UUID) {
        let sid = focusedSpaceID(window: window)
        guard isBlank(space: sid), let space = spaces[sid], items[id]?.isTab == true else { return }
        if children(of: space.todayContainerID).isEmpty {
            let profile = profileID(item: id)
            spaces[sid]?.profileID = profile
        }
        moveItem(id, to: space.todayContainerID, index: 0)
        guard items[id]?.parentID == space.todayContainerID else { return }
        tookTab(id, into: window, open: true)
    }

    /// A tab that came into a window's list from another window (a tear-off, or a drop on its
    /// sidebar): windows that had it open in another space let it go, and it opens here if it
    /// was open there (Arc showed a dropped tab in the window it was dropped on) or `open` says
    /// so. Windows on the same space keep it open (#4).
    func tookTab(_ id: UUID, into window: UUID, open: Bool = false) {
        guard let sid = spaceID(ofItem: id), sid == focusedSpaceID(window: window) else { return }
        var wasOpen = open
        for w in prefs.windows where w.id != window {
            for (s, tab) in w.selectedTabPerSpace where tab == id && s != sid {
                wasOpen = wasOpen || w.focusedSpaceID == s
                updateWindow(w.id) { $0.selectedTabPerSpace[s] = nil }
            }
        }
        if wasOpen { selectTab(id, window: window) }
    }

    /// A Blank Window's "Move to…" (Arc 1.172): its tabs go to the top of the space's Today in
    /// their order and the window lets them go. Returns the tab it had open, which AppDelegate
    /// opens in the main window before it closes the Blank Window.
    @discardableResult
    func moveBlankWindowTabs(_ window: UUID, toSpace sid: UUID) -> UUID? {
        let own = focusedSpaceID(window: window)
        guard isBlank(space: own), let blank = spaces[own], let target = spaces[sid], !isStandalone(space: sid) else { return nil }
        let open = selectedTabID(in: own, window: window)
        moveItems(children(of: blank.todayContainerID).map(\.id), to: target.todayContainerID, index: 0)
        updateWindow(window) { $0.selectedTabPerSpace[own] = nil }
        touch()
        return open
    }

    func isBlank(space id: UUID?) -> Bool { id.map(blankSpaceIDs.contains) ?? false }
    /// A space only its own window shows: an incognito or Blank Window's.
    func isStandalone(space id: UUID?) -> Bool { isIncognito(space: id) || isBlank(space: id) }
    func isBlank(window id: UUID?) -> Bool {
        guard let w = prefs.windows.first(where: { $0.id == (id ?? activeWindowID) }), let sid = w.focusedSpaceID else { return false }
        return spaces[sid]?.standaloneWindowID == w.id
    }
    /// A window showing only a space of its own (incognito or Blank): no space list, no paging.
    func isStandalone(window id: UUID?) -> Bool { window(id).isIncognito || isBlank(window: id) }

    /// Arc's New Incognito Window: a window with a space of its own whose tabs load
    /// in an off-the-record profile and are never written anywhere.
    func addIncognitoWindow(frame: String?) -> WindowSession {
        let id = UUID()
        let favorites = SidebarItem.container(.favorites(spaceID: id))
        let pinned = SidebarItem.container(.pinned(spaceID: id))
        let today = SidebarItem.container(.today(spaceID: id))
        for c in [favorites, pinned, today] { items[c.id] = c }
        spaces[id] = Space(id: id, title: "Incognito", emoji: "🕶️", theme: .incognito, favoritesContainerID: favorites.id,
                           pinnedContainerID: pinned.id, todayContainerID: today.id, createdAt: clock.now)
        incognitoSpaceIDs.insert(id)
        let w = WindowSession(focusedSpaceID: id, frame: frame, isIncognito: true)
        prefs.windows.append(w)
        return w
    }

    func isIncognito(space id: UUID?) -> Bool { id.map(incognitoSpaceIDs.contains) ?? false }
    func isIncognito(item id: UUID) -> Bool { isIncognito(space: spaceID(ofItem: id)) }

    /// The spaces a window pages between: an incognito or Blank Window has only its own.
    func pagedSpaces(window id: UUID?) -> [Space] {
        let w = window(id)
        if isStandalone(window: w.id), let s = w.focusedSpaceID.flatMap({ spaces[$0] }) { return [s] }
        return orderedSpaces
    }

    /// The tabs a window may show and the command bar may offer there: an incognito or Blank
    /// Window's own tabs, or every tab of the spaces.
    func profileTabs(window id: UUID?) -> [SidebarItem] {
        let sid = focusedSpaceID(window: id)
        if isStandalone(space: sid), let s = spaces[sid] {
            return tabs(under: s.favoritesContainerID) + tabs(under: s.pinnedContainerID) + tabs(under: s.todayContainerID)
        }
        // Not the favorites of a profile no space uses (#154): nothing shows them.
        return allTabs().filter { spaceID(ofItem: $0.id).map { !isStandalone(space: $0) } ?? false }
    }

    private func collectSubtree(of space: Space, into ids: inout Set<UUID>) {
        func walk(_ id: UUID) {
            ids.insert(id)
            for c in items[id]?.children ?? [] { walk(c) }
        }
        for c in [space.favoritesContainerID, space.pinnedContainerID, space.todayContainerID] { walk(c) }
    }

    // MARK: Lookup

    var orderedSpaces: [Space] { spaceOrder.compactMap { spaces[$0] } }
    /// Arc's single-space mode: one space and the header turned off. Incognito and Blank Windows keep theirs.
    /// Arc's "Allow websites to get your theme data": the `:root` rule a tab's pages get, from its
    /// space's theme in the scheme pages see (View ▸ Appearance, else the Mac's); nil when off or
    /// incognito.
    /// Arc's "Block Cookie Banners": the stylesheet a tab's pages get, nil while it's off.
    func cookieBannerCSS(item id: UUID) -> String? { settings.blockCookieBanners ? CookieBanners.css : nil }

    func themeDataCSS(item id: UUID, systemDark: Bool) -> String? {
        guard settings.shareThemeWithWebsites, !isIncognito(item: id),
              let theme = spaceID(ofItem: id).flatMap({ spaces[$0]?.theme }) else { return nil }
        let dark = settings.websiteAppearance == .dark || (settings.websiteAppearance == .automatic && systemDark)
        return ":root { " + ArcThemeData.declarations(palette: ArcThemeData.palette(theme: theme, dark: dark), gradient: theme.colors) + " }"
    }

    func hidesSpaceHeader(_ id: UUID) -> Bool {
        !settings.showSpaceHeaderOnSingleSpace && spaceOrder.count == 1 && !isStandalone(space: id)
    }
    func focusedSpaceID(window id: UUID?) -> UUID {
        window(id).focusedSpaceID.flatMap { spaces[$0] != nil ? $0 : nil } ?? spaceOrder.first!
    }
    func focusedSpace(window id: UUID?) -> Space { spaces[focusedSpaceID(window: id)] ?? orderedSpaces.first! }
    var focusedSpaceID: UUID { focusedSpaceID(window: nil) }
    var focusedSpace: Space { focusedSpace(window: nil) }

    func item(_ id: UUID) -> SidebarItem? { items[id] }
    func space(_ id: UUID) -> Space? { spaces[id] }

    func children(of id: UUID) -> [SidebarItem] {
        (items[id]?.children ?? []).compactMap { items[$0] }
    }

    /// Depth-first list of every tab under a container or folder.
    func tabs(under id: UUID) -> [SidebarItem] {
        var out: [SidebarItem] = []
        func walk(_ id: UUID) {
            for c in children(of: id) {
                if c.isTab { out.append(c) } else if c.isFolder || c.isSplit { walk(c.id) }
            }
        }
        walk(id)
        return out
    }

    func allTabs() -> [SidebarItem] { items.values.filter { $0.isTab } }

    /// Both MCP discovery and direct ID access use the same private-tab boundary.
    func mcpTab(_ id: UUID) -> SidebarItem? {
        guard let item = items[id], item.isTab, !isIncognito(item: id),
              spaceID(ofItem: id) != nil else { return nil }
        return item
    }

    /// Tab rows of a space's pinned and today lists in sidebar order, open
    /// folders included (what a ⇧-click range spans).
    func listedTabIDs(in spaceID: UUID) -> [UUID] {
        guard let space = spaces[spaceID] else { return [] }
        var out: [UUID] = []
        func walk(_ id: UUID) {
            for c in children(of: id) {
                if c.isTab { out.append(c.id) } else if c.isFolder, isExpanded(c.id) { walk(c.id) }
            }
        }
        walk(space.pinnedContainerID)
        walk(space.todayContainerID)
        return out
    }

    /// The top-level pinned rows a space's list draws. Collapsed, only the pinned row of the open
    /// tab stays, and the one last open after a favorite or a Today tab is picked (PinnedPeek).
    func listedPinnedItems(in space: Space, window: UUID? = nil) -> [SidebarItem] {
        guard isPinnedCollapsed(space.id) else { return children(of: space.pinnedContainerID) }
        let open = selectedTabID(in: space.id, window: window).flatMap { pinnedRow(of: $0, in: space.id) }
        let peek = pinnedPeeks[self.window(window).id]?[space.id]
        return PinnedPeek.listed(open: open, peek: peek, pinnedRows: pinnedRows(in: space)).compactMap { items[$0] }
    }

    /// Favorites + pinned + today for a space, in sidebar order. This is what
    /// ⌘1…⌘9 index into (Arc: "Go to Sidebar Item N").
    func visibleTabs(in spaceID: UUID) -> [SidebarItem] {
        guard let space = spaces[spaceID] else { return [] }
        return tabs(under: space.favoritesContainerID) + tabs(under: space.pinnedContainerID) + tabs(under: space.todayContainerID)
    }

    /// Which container an item ultimately lives in.
    func rootContainer(of id: UUID) -> ContainerKind? { rootContainerItem(of: id)?.container }

    private func rootContainerItem(of id: UUID) -> SidebarItem? {
        var cur = items[id]
        var hops = 0
        while let c = cur, hops < 64 {
            if c.container != nil { return c }
            guard let p = c.parentID else { return nil }
            cur = items[p]
            hops += 1
        }
        return nil
    }

    /// The space an item is in. Shared favorites (#154) are in every space of their profile:
    /// then it's the window's space when that is one of them, else the first.
    func spaceID(ofItem id: UUID, window: UUID? = nil) -> UUID? {
        guard let root = rootContainerItem(of: id), let kind = root.container else { return nil }
        guard case .favorites(let owner) = kind, owner == ContainerKind.sharedFavoritesSpaceID else { return kind.spaceID }
        if let focused = untrackedWindow(window).focusedSpaceID, spaces[focused]?.favoritesContainerID == root.id { return focused }
        return spaceOrder.first { spaces[$0]?.favoritesContainerID == root.id }
    }

    /// Whether a space lists the item: its own, or favorites it shares.
    func isInSpace(_ id: UUID, _ sid: UUID) -> Bool {
        guard let root = rootContainerItem(of: id)?.id, let s = spaces[sid] else { return false }
        return [s.favoritesContainerID, s.pinnedContainerID, s.todayContainerID].contains(root)
    }

    /// The spaces that show an item: one, every space on its profile for a shared favorite, or
    /// none for one on a profile no space uses.
    func spaceIDs(ofItem id: UUID) -> [UUID] {
        guard let root = rootContainerItem(of: id), let kind = root.container else { return [] }
        guard case .favorites(let owner) = kind, owner == ContainerKind.sharedFavoritesSpaceID else { return [kind.spaceID] }
        return spaceOrder.filter { spaces[$0]?.favoritesContainerID == root.id }
    }

    func isPinned(_ id: UUID) -> Bool {
        switch rootContainer(of: id) {
        case .pinned, .favorites: return true
        default: return false
        }
    }

    func isFavorite(_ id: UUID) -> Bool {
        if case .favorites? = rootContainer(of: id) { return true }
        return false
    }

    func selectedTabID(in spaceID: UUID, window: UUID? = nil) -> UUID? {
        guard let id = self.window(window).selectedTabPerSpace[spaceID], items[id]?.isTab == true else { return nil }
        return id
    }
    func selectedTabID(window: UUID?) -> UUID? { selectedTabID(in: focusedSpaceID(window: window), window: window) }
    func selectedTab(window: UUID?) -> SidebarItem? { selectedTabID(window: window).flatMap { items[$0] } }
    var selectedTabID: UUID? { selectedTabID(window: nil) }
    var selectedTab: SidebarItem? { selectedTab(window: nil) }

    // MARK: Tabs

    @discardableResult
    func createTab(url: String, title: String = "", in spaceID: UUID? = nil, pinned: Bool = false,
                   select: Bool = true, parent: UUID? = nil, index: Int? = nil, window: UUID? = nil,
                   referrer: UUID? = nil) -> SidebarItem {
        let sid = spaceID ?? focusedSpaceID(window: window)
        let space = spaces[sid] ?? focusedSpace(window: window)
        let requestedParent = parent ?? (pinned ? space.pinnedContainerID : space.todayContainerID)
        let parentID = liveFolder(containing: requestedParent) == nil ? requestedParent : space.todayContainerID
        var tab = SidebarItem.tab(url, title: title, parent: parentID)
        tab.data = .tab({
            var t = TabData(url: url, title: title)
            t.activeTabBeforeCreationID = selectedTabID(in: sid, window: window)
            t.referrerID = referrer
            // A background tab joins ⌃Tab's recent tabs when opened, as in Arc.
            if !select { t.timeLastActiveAt = clock.now }
            return t
        }())
        tab.isUnread = !select
        items[tab.id] = tab
        var p = items[parentID]!
        let at = index ?? (settings.newTabsAtTop && !pinned ? 0 : p.children.count)
        p.children.insert(tab.id, at: min(max(0, at), p.children.count))
        items[parentID] = p
        if select { selectTab(tab.id, window: window) } else { touch() }
        return tab
    }

    /// What Back does on tab `id`, whose page `canGoBack` or not: a tab a link opened, with no
    /// page behind, closes to the tab it came from while that one is still in the sidebar (#273).
    /// `swipe`: a two-finger swipe back over the page asks (#370).
    func backStep(_ id: UUID, canGoBack: Bool, swipe: Bool = false) -> BackToReferrer.Step {
        let referrer = items[id]?.tab?.referrerID.flatMap { items[$0]?.isTab == true ? $0 : nil }
        let inSplit = splitContaining(id) != nil, pinned = isPinned(id)
        return swipe
            ? BackToReferrer.swipeBack(pageCanGoBack: canGoBack, tab: id, referrer: referrer, inSplit: inSplit, pinned: pinned)
            : BackToReferrer.step(canGoBack: canGoBack, tab: id, referrer: referrer, inSplit: inSplit, pinned: pinned)
    }

    /// Back's `.close`: the tab goes to the archive like ⌘W and `referrer` is shown in `window`.
    func closeToReferrer(_ id: UUID, referrer: UUID, window: UUID?) {
        archiveTab(id, reason: .manual)
        selectTab(referrer, window: window)
    }

    func selectTab(_ id: UUID?, window: UUID? = nil) {
        var w = self.window(window).id
        // A space's tab picked while an incognito or Blank Window is in front (a link from
        // another app, the Library) opens in the last normal window.
        if window == nil, let id, isStandalone(window: w), spaceID(ofItem: id) != focusedSpaceID(window: w) { w = lastNormalWindowID }
        let focused = focusedSpaceID(window: w)
        guard let id, let it = items[id], it.isTab else {
            updateWindow(w) { $0.selectedTabPerSpace[focused] = nil }
            touch()
            return
        }
        let sid = spaceID(ofItem: id, window: w) ?? focused
        // Incognito and Blank Windows show only their own tabs, and only there.
        guard isStandalone(window: w) ? sid == focused : !isStandalone(space: sid) else { return }
        updateWindow(w) {
            $0.focusedSpaceID = sid
            $0.selectedTabPerSpace[sid] = id
        }
        noteShown(id)
        if !isIncognito(space: sid) {
            var dates = ranking.recentlySwitchedToTabs[id] ?? []
            dates.append(clock.now)
            if dates.count > 10 { dates.removeFirst(dates.count - 10) }
            ranking.recentlySwitchedToTabs[id] = dates
            rankingFile.save(ranking)
        }
        touch()
    }

    /// A tab coming on screen, picked or handed the selection by a close: it's read and last
    /// active now (Arc clears the unread mark either way).
    private func noteShown(_ id: UUID) {
        guard var it = items[id] else { return }
        it.isUnread = false
        if var t = it.tab { t.timeLastActiveAt = clock.now; it.data = .tab(t) }
        items[id] = it
        // Selecting a pane focuses it inside its split (Arc: focusItemID).
        if let p = it.parentID, var split = items[p], var s = split.split {
            s.focusTabID = id
            s.timeLastActiveAt = clock.now
            split.data = .split(s)
            items[p] = split
        }
        // In a closed folder the tab shows under the outermost closed one (Arc, GitHub #85).
        let peeks = FolderPeek.opening(id, folders: folderChain(of: id), isExpanded: { self._prefs.expandedFolders.contains($0) },
                                       peeks: _prefs.peekedFolders)
        if peeks != _prefs.peekedFolders { prefs.peekedFolders = peeks }
    }

    func updateTab(_ id: UUID, url: String? = nil, title: String? = nil) {
        guard var it = items[id], var t = it.tab else { return }
        if let url, !url.isEmpty, url != "about:blank" {
            t.url = url
            // A pinned tab that never had a page (a new pane of a pinned split) takes its first one as home.
            if !isPinned(id) || t.savedURL.isEmpty || t.savedURL == "about:blank" { t.savedURL = url }
            t.faviconKey = FaviconKey.key(after: t.faviconKey, goingTo: url)
        }
        if let liveURL = t.liveItemURL, t.url.hasPrefix(liveURL) {
            if let parentID = it.parentID,
               let item = items[parentID]?.liveFolder?.plugin?.snapshot?.items.first(where: { $0.url == liveURL }) {
                t.savedTitle = item.title
            }
        } else if let title {
            t.noteTitle(title, pinned: isPinned(id))
        }
        // Pages report titles and addresses over and over while they load, and every write to
        // `items` re-renders the sidebar's lists: only real changes are written.
        guard t != it.tab else { return }
        let wasEmpty = it.isEmptyTab
        it.data = .tab(t)
        items[id] = it
        // The window's layout (refresh) only depends on a tab becoming or ceasing to be an
        // empty pane; the rows and the toolbar observe the tab themselves.
        if it.isEmptyTab != wasEmpty { revision &+= 1 }
        // The document leaves incognito windows' tabs out.
        sidebarFile.save(document, delay: 2)
    }

    /// The tab's page loaded its own icon, cached under `key` (#211).
    func setFaviconKey(_ id: UUID, _ key: String) {
        guard var it = items[id], var t = it.tab, t.faviconKey != key else { return }
        t.faviconKey = key
        it.data = .tab(t)
        items[id] = it
        // Rows and the toolbar observe the tab; the window's layout doesn't change.
        sidebarFile.save(document, delay: 2)
    }

    /// Only saved: nothing on screen reads it back until the tab's page is made again. Incognito
    /// tabs are never restored, so they keep none.
    func setThemeColor(_ id: UUID, _ hex: String) {
        guard !isIncognito(item: id), var it = items[id], var t = it.tab, t.themeColor != hex else { return }
        t.themeColor = hex
        it.data = .tab(t)
        items[id] = it
        sidebarFile.save(document, delay: 2)
    }

    func markUnread(_ id: UUID, _ unread: Bool = true) {
        guard var it = items[id] else { return }
        it.isUnread = unread
        items[id] = it
        revision &+= 1
    }

    func setMuted(_ id: UUID, _ muted: Bool) {
        guard var it = items[id], var t = it.tab else { return }
        t.muted = muted
        it.data = .tab(t)
        items[id] = it
        touch()
    }

    func rename(_ id: UUID, to title: String?) {
        guard var it = items[id] else { return }
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        it.title = (trimmed?.isEmpty ?? true) ? nil : trimmed
        items[id] = it
        touch()
    }

    /// Pinned tabs have a home URL. Reset returns there (Arc: resetTab).
    func resetPinnedTab(_ id: UUID) -> String? {
        guard var it = items[id], var t = it.tab, isPinned(id) else { return nil }
        t.returnHome()
        it.data = .tab(t)
        items[id] = it
        // Closed, it no longer shows under a closed folder or a collapsed pinned section (Arc).
        let peeks = FolderPeek.removing(id, peeks: _prefs.peekedFolders)
        if peeks != _prefs.peekedFolders { prefs.peekedFolders = peeks }
        let row = splitContaining(id)?.id
        let pinned = pinnedPeeks.mapValues { $0.compactMapValues { PinnedPeek.closing(id, rowOfClosed: row, peek: $0) } }
        if pinned != pinnedPeeks { pinnedPeeks = pinned }
        touch()
        return t.savedURL
    }

    /// Make the current page the pinned home (Arc: replacePinnedTab).
    func setPinnedHomeToCurrent(_ id: UUID) {
        guard var it = items[id], var t = it.tab else { return }
        t.makeCurrentPageHome()
        it.data = .tab(t)
        items[id] = it
        touch()
    }

    /// Edit Pinned URL…: a new pinned URL for a pinned tab or favorite (#54). A tab
    /// on its pinned page goes with it; one navigated away keeps its page until Back to Pinned Page.
    @discardableResult
    func setPinnedURL(_ id: UUID, to url: String) -> Bool {
        guard var it = items[id], var t = it.tab, isPinned(id), t.liveItemURL == nil else { return false }
        if t.url == t.savedURL, t.url != url {
            t.url = url
            t.savedTitle = ""
            t.faviconKey = FaviconKey.key(for: url)
        }
        if t.savedURL != url { t.homeTitle = nil }
        t.savedURL = url
        it.data = .tab(t)
        items[id] = it
        touch()
        return true
    }

    func duplicateTab(_ id: UUID) -> SidebarItem? {
        guard let it = items[id], let t = it.tab, let parent = it.parentID else { return nil }
        let idx = (items[parent]?.children.firstIndex(of: id) ?? 0) + 1
        return createTab(url: t.url, title: t.savedTitle, in: spaceID(ofItem: id), pinned: false,
                         select: true, parent: parent, index: idx)
    }

    // MARK: Import helpers

    func insertItem(_ item: SidebarItem, into parent: UUID, at index: Int?) {
        var it = item
        it.parentID = parent
        items[it.id] = it
        guard var p = items[parent] else { return }
        p.children.insert(it.id, at: min(index ?? p.children.count, p.children.count))
        items[parent] = p
    }

    /// A Little Window closed: its page goes to the Library like a closed tab
    /// (Arc archives Little Arcs with source `littleArc`). It never had a
    /// sidebar slot, so `sourceSpaceID` is nil and restore uses the focused space.
    func archiveLittleWindowPage(url: String, title: String) {
        let it = SidebarItem.tab(url, title: title, parent: nil)
        archive.insert(ArchivedItem(archivedAt: clock.now, reason: .manual, sourceSpaceID: nil, wasPinned: false, item: it, fromLittleWindow: true), at: 0)
        if archive.count > 2000 { archive.removeLast(archive.count - 2000) }
        touch()
    }

    func appendArchived(_ entry: ArchivedItem) {
        archive.append(entry)
        archive.sort { $0.archivedAt > $1.archivedAt }
    }

    func touchAfterImport() { touch() }

    /// The sidebar another Mac wrote to the sync folder (SettingsSyncService), in place of this
    /// one's: spaces, items, profiles and profile favorites. Incognito and Blank Windows keep their
    /// spaces; they are this Mac's windows, never in a synced document (`SidebarDocument.forSync`).
    /// Repaired like a file at launch, so a profile the other Mac deleted leaves its spaces on
    /// Default, and a window whose space is gone shows the first.
    func replace(document synced: SidebarDocument) {
        let doc = synced.forSync()
        var kept = Set<UUID>()
        for sid in incognitoSpaceIDs.union(blankSpaceIDs) { if let s = spaces[sid] { collectSubtree(of: s, into: &kept) } }
        for id in items.all.keys where !kept.contains(id) { items[id] = nil }
        for (id, _) in spaces where !isStandalone(space: id) { spaces[id] = nil }
        storedThemes = [:]
        previousTab = [:]
        for s in doc.spaces { spaces[s.id] = s }
        profiles = doc.profiles ?? []
        profileFavorites = doc.profileFavorites ?? []
        spaceOrder = BlankWindow.spaceOrder(saved: doc.spaceOrder, spaces: doc.spaces)
        for it in doc.items where !kept.contains(it.id) { items[it.id] = it }
        repair()
        var windows = prefs.windows
        for i in windows.indices where !isStandalone(window: windows[i].id) {
            if windows[i].focusedSpaceID.flatMap({ spaces[$0] }) == nil { windows[i].focusedSpaceID = spaceOrder.first }
            windows[i].selectedTabPerSpace = windows[i].selectedTabPerSpace.filter { spaces[$0.key] != nil && items[$0.value] != nil }
        }
        prefs.windows = windows
        splitSharedFavorites(doc.favoritesContainerID)
        settings.sharedFavorites ? shareFavorites() : unshareFavorites()
        touch()
    }

    /// What goes to disk: everything but incognito windows' spaces and tabs. Blank Windows'
    /// spaces go too, outside `spaceOrder`.
    var document: SidebarDocument {
        var hidden = Set<UUID>()
        for sid in incognitoSpaceIDs { if let s = spaces[sid] { collectSubtree(of: s, into: &hidden) } }
        // A theme still being previewed goes to disk as it was stored.
        let saved = storedThemes.isEmpty ? orderedSpaces : orderedSpaces.map { s in
            var s = s
            if let t = storedThemes[s.id] { s.theme = t }
            return s
        }
        let blank = blankSpaceIDs.compactMap { spaces[$0] }.sorted { $0.createdAt < $1.createdAt }
        return SidebarDocument(version: 1, spaceOrder: spaceOrder, spaces: saved + blank,
                               items: hidden.isEmpty ? Array(items.values) : items.values.filter { !hidden.contains($0.id) },
                               profiles: profiles, profileFavorites: profileFavorites.isEmpty ? nil : profileFavorites)
    }

    /// The tab switcher's list (⌃Tab): a space's most recently used tabs, newest first
    /// (Arc shows five, the current tab first).
    func recentTabs(in sid: UUID, limit: Int, window: UUID? = nil) -> [UUID] {
        // A tab opened in the background since is newer than the current one, which still comes first.
        let current = selectedTabID(in: sid, window: window)
        return visibleTabs(in: sid)
            .filter { $0.tab?.timeLastActiveAt != nil }
            .sorted { a, b in
                if (a.id == current) != (b.id == current) { return a.id == current }
                return a.tab!.timeLastActiveAt! > b.tab!.timeLastActiveAt!
            }
            .prefix(limit).map(\.id)
    }

    // MARK: Tree moves

    /// Detach an item from its parent without deleting it.
    private func detach(_ id: UUID) {
        guard let it = items[id], let p = it.parentID, var parent = items[p] else { return }
        parent.children.removeAll { $0 == id }
        items[p] = parent
    }

    private func isDescendant(_ candidate: UUID, of ancestor: UUID) -> Bool {
        var cur = items[candidate]?.parentID
        var hops = 0
        while let c = cur, hops < 64 {
            if c == ancestor { return true }
            cur = items[c]?.parentID
            hops += 1
        }
        return false
    }

    /// Move an item (tab or folder) under `newParent` at `index`. Folders may
    /// only live in pinned sections or favorites; dropping a folder into the
    /// today list unpacks it.
    func moveItem(_ id: UUID, to newParent: UUID, index: Int?) {
        guard var it = items[id], items[newParent] != nil, id != newParent, !isDescendant(newParent, of: id) else { return }
        // A page can't change profile: nothing moves into or out of an incognito window.
        guard isIncognito(item: id) == isIncognito(item: newParent) else { return }
        // A Blank Window holds tabs only: nothing goes into its (hidden) favorites or pinned section.
        if isBlank(space: spaceID(ofItem: newParent)) {
            guard case .today? = rootContainerKind(newParent) else { return }
        }
        // Only tabs live inside a split; dropping onto a split adds a pane.
        if items[newParent]?.isSplit == true {
            if it.isTab { addToSplit(newParent, tabID: id, at: index) }
            return
        }
        let fromParent = it.parentID
        let movingLiveFolders = liveFolderRoots(under: id)
        let movingIDs = Set(movingLiveFolders.map(\.id))
        let destinationSpaces = Set(spaceIDs(ofItem: newParent))
        for folder in movingLiveFolders {
            guard let live = folder.liveFolder else { continue }
            if liveFolders.contains(where: { other in
                guard !movingIDs.contains(other.id), let otherLive = other.liveFolder,
                      !destinationSpaces.isDisjoint(with: spaceIDs(ofItem: other.id)) else { return false }
                if let plugin = live.plugin {
                    return otherLive.plugin?.id == plugin.id && otherLive.plugin?.settings == plugin.settings
                }
                guard otherLive.source == live.source else { return false }
                return live.source == .github || otherLive.serverURL.flatMap(GitLabLiveClient.serverURL) == live.serverURL.flatMap(GitLabLiveClient.serverURL)
            }) { return }
        }
        if !movingLiveFolders.isEmpty, case .today? = rootContainerKind(newParent) { return }
        let previousProfiles = Dictionary(uniqueKeysWithValues: movingLiveFolders.map { ($0.id, profileDirectoryName(item: $0.id)) })
        // A tab group lives at the top of Today and holds tabs and splits only (Arc's tabGroup items).
        if it.isTabGroup, items[newParent]?.container != .today(spaceID: spaceID(ofItem: id) ?? UUID()) { return }
        if items[newParent]?.isTabGroup == true, !(it.isTab || it.isSplit) { return }
        // A live folder fills itself: nothing is dropped into it, and it never unpacks into Today.
        if liveFolder(containing: newParent) != nil, fromParent != newParent { return }
        if it.isLiveFolder, case .today? = rootContainerKind(newParent) { return }
        if fromParent != newParent, let from = fromParent, let live = liveFolder(containing: from) { hideLiveItem(id, in: live.id) }
        let oldIndex = fromParent.flatMap { items[$0]?.children.firstIndex(of: id) }
        let wasPinned = fromParent.map { if case .pinned? = rootContainerKind($0) { return true } else { return false } } ?? false
        if it.isFolder, !it.isTabGroup, case .today? = rootContainerKind(newParent) {
            // Unpack: move the folder's tabs instead.
            let kids = it.children
            detach(id)
            items[id] = nil
            var at = index ?? 0
            for k in kids {
                moveItem(k, to: newParent, index: at)
                at += 1
            }
            touch()
            return
        }
        detach(id)
        it = items[id] ?? it
        var parent = items[newParent]!
        var at = index ?? parent.children.count
        if fromParent == newParent, let old = oldIndex, old < at { at -= 1 }
        at = min(max(0, at), parent.children.count)
        parent.children.insert(id, at: at)
        items[newParent] = parent
        it.parentID = newParent
        if var t = it.tab {
            // Moving into a pinned section makes the current page the home.
            let kind = rootContainerKind(newParent)
            switch kind {
            case .pinned, .favorites: t.makeCurrentPageHome()
            default: break
            }
            it.data = .tab(t)
        }
        items[id] = it
        for (folder, profile) in previousProfiles where profileDirectoryName(item: folder) != profile {
            invalidateLiveFolder(folder)
        }
        if it.isSplit, isPinned(newParent) {
            // A pinned split keeps each pane's page as that pane's home.
            for c in it.children {
                guard var pane = items[c], var t = pane.tab else { continue }
                t.makeCurrentPageHome()
                pane.data = .tab(t)
                items[c] = pane
            }
        }
        if let from = fromParent, from != newParent { collapseSplitIfNeeded(from) }
        touch()
        if !wasPinned, it.isTab, it.title == nil, !isIncognito(item: id), case .pinned? = rootContainerKind(newParent) { tabPinned(id) }
    }

    /// Moves several items so they end up next to each other, in the given
    /// order, starting at `index` (appended when nil).
    func moveItems(_ ids: [UUID], to newParent: UUID, index: Int?) {
        var at = index
        for id in ids {
            moveItem(id, to: newParent, index: at)
            if at != nil, let i = items[newParent]?.children.firstIndex(of: id) { at = i + 1 }
        }
    }

    /// Items let go on a folder's row go in at the top, in their order, and the folder stays as
    /// it was (Arc 1.172, a real drag in an offline copy, 9 Nov 2026, #266). A closed folder keeps
    /// an open tab it took in sight under it, as when a folder closes around one.
    func dropIntoFolder(_ ids: [UUID], folder: UUID) {
        moveItems(ids, to: folder, index: 0)
        let open = Set(_prefs.windows.flatMap { $0.selectedTabPerSpace.values })
        var peeks = _prefs.peekedFolders
        for tab in open where ids.contains(where: { $0 == tab || isDescendant(tab, of: $0) }) {
            peeks = FolderPeek.opening(tab, folders: folderChain(of: tab), isExpanded: { self._prefs.expandedFolders.contains($0) }, peeks: peeks)
        }
        if peeks != _prefs.peekedFolders { prefs.peekedFolders = peeks }
    }

    private func rootContainerKind(_ id: UUID) -> ContainerKind? { rootContainer(of: id) }

    // MARK: Split view (Arc: SidebarSplitViewData + WindowAction.SplitViewAction)

    /// The split item a tab is a pane of, if any.
    func splitContaining(_ tabID: UUID) -> SidebarItem? {
        guard let p = items[tabID]?.parentID, let parent = items[p], parent.isSplit else { return nil }
        return parent
    }

    /// The panes shown when `tabID` is selected: its split's children in pane
    /// order, or just the tab itself.
    func paneTabIDs(for tabID: UUID) -> [UUID] {
        if let split = splitContaining(tabID) { return split.children.filter { items[$0]?.isTab == true } }
        return [tabID]
    }

    /// Panes shown in a space right now (the selected tab's split).
    func visiblePaneTabIDs(in spaceID: UUID, window: UUID? = nil) -> [UUID] {
        guard let sel = selectedTabID(in: spaceID, window: window) else { return [] }
        return paneTabIDs(for: sel)
    }

    /// Put tabs into a new split, panes in the given order, at the place of
    /// `anchorID` (default: the first tab) in the sidebar. `inPlace` keeps a pinned anchor's split
    /// where the anchor is, with the tabs themselves as panes (a sidebar drop, `combineIntoSplit`).
    @discardableResult
    func createSplit(with tabIDs: [UUID], at anchorID: UUID? = nil, inPlace: Bool = false) -> SidebarItem? {
        let tabs = tabIDs.compactMap { items[$0] }.filter { $0.isTab }
        guard let first = anchorID.flatMap({ a in tabs.first { $0.id == a } }) ?? tabs.first else { return nil }
        if let existing = splitContaining(first.id) {
            for t in tabs where t.id != first.id { addToSplit(existing.id, tabID: t.id, at: nil) }
            return items[existing.id]
        }
        // Observed in Arc 1.170: splitting a favorite or pinned tab leaves it in
        // place and builds the split in Today from a copy of the page; a Today
        // tab moves into the split at its own slot.
        var parentID = first.parentID ?? focusedSpace.todayContainerID
        var at = items[parentID]?.children.firstIndex(of: first.id) ?? 0
        if isPinned(first.id), !inPlace {
            parentID = (spaceID(ofItem: first.id).flatMap { spaces[$0] } ?? focusedSpace).todayContainerID
            at = 0
        }
        var split = SidebarItem.split(parent: parentID)
        var s = SplitData()
        s.timeLastActiveAt = clock.now
        split.data = .split(s)
        items[split.id] = split
        var p = items[parentID]!
        p.children.insert(split.id, at: min(at, p.children.count))
        items[parentID] = p
        var paneIDs: [UUID] = []
        var anchorPane: UUID?
        for t in tabs {
            let paneID: UUID
            if isPinned(t.id), !inPlace, let data = t.tab {
                // Keep the pinned tab; the pane is a Today copy of its page.
                var copy = SidebarItem.tab(data.url, title: data.savedTitle, parent: split.id)
                copy.data = .tab({ var c = TabData(url: data.url, title: data.savedTitle); c.faviconKey = data.faviconKey; c.activeTabBeforeCreationID = t.id; return c }())
                items[copy.id] = copy
                paneID = copy.id
            } else {
                detach(t.id)
                var moved = items[t.id]!
                moved.parentID = split.id
                items[t.id] = moved
                paneID = t.id
            }
            items[split.id]!.children.append(paneID)
            paneIDs.append(paneID)
            if t.id == first.id { anchorPane = paneID }
        }
        if var sp = items[split.id], var sd = sp.split {
            sd.focusTabID = anchorPane ?? paneIDs.first
            sp.data = .split(sd)
            items[split.id] = sp
        }
        touch()
        return items[split.id]
    }

    /// A tab dropped on the middle of another tab's row (Arc: `draggedToCombineSplitCompatibleItems`,
    /// GitHub #191, #180): the two become one split in the target's place, so a drop on a pinned tab
    /// makes a pinned split, inside its folder if it has one. Both tabs move into it, the dropped
    /// one on the side it was dropped; nothing is copied. The dropped tab first moves next to the
    /// target the way any drop there would move it (pinning or unpinning it).
    @discardableResult
    func combineIntoSplit(_ draggedID: UUID, onto targetID: UUID, leading: Bool) -> SidebarItem? {
        guard draggedID != targetID, items[draggedID]?.isTab == true, let target = items[targetID], target.isTab,
              let parentID = target.parentID, items[parentID]?.isSplit == false, !isFavorite(targetID) else {
            return createSplit(with: leading ? [draggedID, targetID] : [targetID, draggedID], at: targetID)
        }
        if items[draggedID]?.parentID != parentID {
            moveItem(draggedID, to: parentID, index: items[parentID]?.children.firstIndex(of: targetID))
            guard items[draggedID]?.parentID == parentID else { return nil }
        }
        guard let split = createSplit(with: leading ? [draggedID, targetID] : [targetID, draggedID], at: targetID, inPlace: true),
              var sd = split.split else { return nil }
        // Arc focuses the dropped tab's pane (the ring and the full toolbar are on it).
        sd.focusTabID = draggedID
        items[split.id]?.data = .split(sd)
        touch()
        return items[split.id]
    }

    /// The pane that stands for `tabID` in its split (the tab itself, or the
    /// Today copy made for a pinned tab).
    func paneID(for tabID: UUID, in split: SidebarItem) -> UUID? {
        if split.children.contains(tabID) { return tabID }
        return split.children.first { items[$0]?.tab?.activeTabBeforeCreationID == tabID }
    }

    /// Arc's "Add Split View": an empty page becomes a new pane next to `tabID`
    /// (after it by default). Returns the new tab.
    @discardableResult
    func addEmptyPane(nextTo tabID: UUID, after: Bool = true, url: String = "", window: UUID? = nil) -> SidebarItem? {
        guard let anchor = items[tabID], anchor.isTab else { return nil }
        let split: SidebarItem
        if let s = splitContaining(tabID) { split = s } else if let s = createSplit(with: [tabID]) { split = s } else { return nil }
        guard let anchorPane = paneID(for: tabID, in: items[split.id] ?? split),
              let idx = items[split.id]?.children.firstIndex(of: anchorPane) else { return nil }
        var tab = SidebarItem.tab(url, title: "", parent: split.id)
        tab.data = .tab({ var t = TabData(url: url, title: ""); t.activeTabBeforeCreationID = tabID; return t }())
        items[tab.id] = tab
        var sp = items[split.id]!
        sp.children.insert(tab.id, at: after ? idx + 1 : idx)
        items[split.id] = sp
        selectTab(tab.id, window: window)
        return tab
    }

    /// A page's "Open Link in Split View" (#257): the link opens in a new pane right after the
    /// page it was clicked in (`tabID`), in that tab's split or a new one, and is the open pane.
    /// Nil when the split already has four panes, Arc's most (the window says "Cannot Add New Pane").
    @discardableResult
    func openLinkInSplit(_ url: String, from tabID: UUID, window: UUID? = nil) -> SidebarItem? {
        guard items[tabID]?.isTab == true, paneTabIDs(for: tabID).count < 4 else { return nil }
        return addEmptyPane(nextTo: tabID, url: url, window: window)
    }

    /// Add an existing tab as a pane of a split (Arc: onDropSidebarItem). A
    /// pinned or favorite tab stays where it is; a Today copy becomes the pane.
    func addToSplit(_ splitID: UUID, tabID: UUID, at index: Int?) {
        guard var split = items[splitID], split.isSplit, var tab = items[tabID], tab.isTab, tab.parentID != splitID else {
            if let i = index, let sp = items[splitID], sp.children.firstIndex(of: tabID) != nil { moveWithinSplit(splitID, tabID: tabID, to: i) }
            return
        }
        let from = tab.parentID
        var paneID = tabID
        if isPinned(tabID), let data = tab.tab {
            var copy = SidebarItem.tab(data.url, title: data.savedTitle, parent: splitID)
            copy.data = .tab({ var c = TabData(url: data.url, title: data.savedTitle); c.faviconKey = data.faviconKey; c.activeTabBeforeCreationID = tabID; return c }())
            items[copy.id] = copy
            paneID = copy.id
        } else {
            detach(tabID)
            tab.parentID = splitID
            items[tabID] = tab
        }
        split = items[splitID]!
        let at = min(max(0, index ?? split.children.count), split.children.count)
        split.children.insert(paneID, at: at)
        items[splitID] = split
        if paneID == tabID, let from, from != splitID { collapseSplitIfNeeded(from) }
        touch()
    }

    func moveWithinSplit(_ splitID: UUID, tabID: UUID, to index: Int) {
        guard var split = items[splitID], let old = split.children.firstIndex(of: tabID) else { return }
        split.children.remove(at: old)
        var at = index
        if old < at { at -= 1 }
        split.children.insert(tabID, at: min(max(0, at), split.children.count))
        items[splitID] = split
        touch()
    }

    /// Take a pane out of its split: it goes right after the split in the
    /// sidebar (Arc: "Separate Tab from Split"). A split with one pane left
    /// dissolves.
    func separateFromSplit(_ tabID: UUID) {
        guard let split = splitContaining(tabID), let gp = split.parentID, var grand = items[gp],
              let splitIndex = grand.children.firstIndex(of: split.id), var tab = items[tabID] else { return }
        detach(tabID)
        tab.parentID = gp
        items[tabID] = tab
        grand = items[gp]!
        grand.children.insert(tabID, at: min(splitIndex + 1, grand.children.count))
        items[gp] = grand
        collapseSplitIfNeeded(split.id)
        touch()
    }

    func separateAll(_ splitID: UUID) {
        guard let split = items[splitID], split.isSplit else { return }
        for id in split.children.reversed() { separateFromSplit(id) }
    }

    func setSplitWidthFactors(_ splitID: UUID, _ factors: [UUID: Double]) {
        guard var split = items[splitID], var s = split.split else { return }
        s.widthFactors = factors
        split.data = .split(s)
        items[splitID] = split
        touch()
    }

    func flipSplitOrientation(_ splitID: UUID) {
        guard var split = items[splitID], var s = split.split else { return }
        s.orientation = s.orientation == .horizontal ? .vertical : .horizontal
        split.data = .split(s)
        items[splitID] = split
        touch()
    }

    /// Zero or one pane left: the split goes away and the pane takes its slot.
    private func collapseSplitIfNeeded(_ splitID: UUID) {
        guard let split = items[splitID], split.isSplit, split.children.count <= 1 else { return }
        let sid = spaceID(ofItem: splitID)
        if let gp = split.parentID, var grand = items[gp] {
            let at = grand.children.firstIndex(of: splitID) ?? grand.children.count
            grand.children.removeAll { $0 == splitID }
            for c in split.children {
                if var child = items[c] {
                    child.parentID = gp
                    items[c] = child
                    grand.children.insert(c, at: min(at, grand.children.count))
                }
            }
            items[gp] = grand
        }
        items[splitID] = nil
        if let sid {
            for w in prefs.windows {
                if let sel = w.selectedTabPerSpace[sid], items[sel] == nil {
                    updateWindow(w.id) { $0.selectedTabPerSpace[sid] = split.children.first }
                }
            }
        }
    }

    func pinTab(_ id: UUID) {
        guard let sid = spaceID(ofItem: id), let space = spaces[sid] else { return }
        if isFavorite(id) {
            moveItem(id, to: space.pinnedContainerID, index: nil)
        } else {
            moveItem(id, to: space.pinnedContainerID, index: nil)
        }
    }

    func unpinTab(_ id: UUID) {
        guard let sid = spaceID(ofItem: id), let space = spaces[sid] else { return }
        moveItem(id, to: space.todayContainerID, index: 0)
    }

    /// A pane pins and unpins its whole split.
    func togglePinned(_ id: UUID) {
        let id = splitContaining(id)?.id ?? id
        if isPinned(id) { unpinTab(id) } else { pinTab(id) }
    }

    /// Favorites belong to one space: the tab's own unless another is given.
    /// `index` is a place among the favorites container's children (#176: a tab dropped between tiles); nil appends.
    func addToFavorites(_ id: UUID, in spaceID: UUID? = nil, at index: Int? = nil) {
        // A pane brings its whole split: Arc's top apps hold a split as one tile (AppItem.childItems).
        let id = splitContaining(id)?.id ?? id
        guard let it = items[id], it.isTab || it.isSplit else { return }
        guard let space = spaces[spaceID ?? self.spaceID(ofItem: id) ?? focusedSpaceID], !isBlank(space: space.id) else { return }
        // A new favorite takes the tile color when every existing one shares it.
        let colors = Set(favoriteTabs(in: space).map { $0.tab?.tileColor })
        moveItem(id, to: space.favoritesContainerID, index: index)
        if colors.count == 1, let color = colors.first!, items[id]?.tab?.tileColor == nil { setTileColor(color, for: [id]) }
    }

    /// The favorites' own tabs, not the panes of favorite splits.
    func favoriteTabs(in space: Space) -> [SidebarItem] { children(of: space.favoritesContainerID).filter(\.isTab) }

    func setTileColor(_ hex: String?, for ids: [UUID]) {
        for id in ids {
            guard var it = items[id], var t = it.tab else { continue }
            t.tileColor = hex
            it.data = .tab(t)
            items[id] = it
        }
        touch()
    }

    func setCustomIcon(_ key: String?, for id: UUID) {
        guard var it = items[id], var t = it.tab else { return }
        t.customIconKey = key
        it.data = .tab(t)
        items[id] = it
        touch()
    }

    func removeFromFavorites(_ id: UUID) {
        let id = splitContaining(id)?.id ?? id
        // Arc's Remove Favorite (1.171, shared favorites): the favorite is gone, not pinned or archived.
        if profileList(ofItem: id) != nil {
            let tabs = items[id]?.isSplit == true ? children(of: id).filter(\.isTab).map(\.id) : [id]
            for t in tabs { archiveTab(t, reason: .manual) }
            archive.removeAll { tabs.contains($0.id) }
            return
        }
        guard let space = spaceID(ofItem: id).flatMap({ spaces[$0] }) else { return }
        moveItem(id, to: space.pinnedContainerID, index: nil)
    }

    // MARK: Shared favorites (#154)

    /// Settings ▸ Tabs ▸ Share Favorites: Arc's favorites, one list per profile. On, each
    /// profile's spaces show its list, which takes in their own favorites (a page in two of them
    /// once); off, each space gets its own list again.
    func setFavoritesShared(_ on: Bool) {
        guard settings.sharedFavorites != on else { return }
        settings.sharedFavorites = on
        on ? shareFavorites() : unshareFavorites()
    }

    private func entries(_ container: UUID) -> [FavoritesSharing.Entry] {
        children(of: container).map { FavoritesSharing.Entry(id: $0.id, key: FavoritesSharing.key(of: $0, children: children(of: $0.id))) }
    }

    private func favoritesBySpace() -> [FavoritesSharing.SpaceFavorites] {
        orderedSpaces.map {
            FavoritesSharing.SpaceFavorites(spaceID: $0.id, profileID: $0.profileID, containerID: $0.favoritesContainerID,
                                            items: entries($0.favoritesContainerID))
        }
    }

    /// A profile's list, made empty when it has none (a space moving to a new profile).
    private func profileList(_ profileID: UUID?) -> UUID {
        if let l = profileFavorites.first(where: { $0.profileID == profileID }), items[l.containerID] != nil { return l.containerID }
        let c = SidebarItem.container(.favorites(spaceID: ContainerKind.sharedFavoritesSpaceID))
        items[c.id] = c
        profileFavorites.removeAll { $0.profileID == profileID }
        profileFavorites.append(ProfileFavorites(profileID: profileID, containerID: c.id))
        return c.id
    }

    private func isProfileList(_ container: UUID) -> Bool { profileFavorites.contains { $0.containerID == container } }

    /// Arc's Move to ▸ Profile on a favorite: it joins the end of that profile's list.
    func moveFavorite(_ id: UUID, toProfile profileID: UUID?) {
        let id = splitContaining(id)?.id ?? id
        guard let from = profileList(ofItem: id), from.profileID != profileID, profileID == nil || profile(profileID) != nil else { return }
        reparent(id, to: profileList(profileID))
        touch()
    }

    /// Makes the sidebar match FavoritesSharing.share; nothing changes when it already does.
    private func shareFavorites() {
        profileFavorites.removeAll { items[$0.containerID] == nil }
        let lists = profileFavorites.map { FavoritesSharing.ProfileList($0, items: entries($0.containerID)) }
        let plan = FavoritesSharing.share(favoritesBySpace(), lists: lists)
        for c in plan.created { items[c] = SidebarItem.container(.favorites(spaceID: ContainerKind.sharedFavoritesSpaceID), id: c) }
        // Raw moves: a favorite keeps its home (moveItem would make the current page it).
        for m in plan.moves { reparent(m.item, to: m.container) }
        // A window that had a dropped duplicate open shows the kept one (a split's panes in order).
        var replaced: [UUID: UUID] = [:]
        for (dup, kept) in plan.duplicates {
            replaced[dup] = kept
            let keptPanes = items[kept]?.children ?? []
            for (i, pane) in (items[dup]?.children ?? []).enumerated() { replaced[pane] = keptPanes.indices.contains(i) ? keptPanes[i] : kept }
            detach(dup)
            func drop(_ id: UUID) {
                for c in items[id]?.children ?? [] { drop(c) }
                items[id] = nil
            }
            drop(dup)
        }
        for c in plan.dropped { items[c] = nil }
        var changed = !plan.created.isEmpty || !plan.moves.isEmpty || !plan.duplicates.isEmpty || !plan.dropped.isEmpty
        profileFavorites = plan.lists
        for (sid, c) in plan.containers where spaces[sid]?.favoritesContainerID != c {
            spaces[sid]?.favoritesContainerID = c
            changed = true
        }
        if !replaced.isEmpty {
            var windows = prefs.windows
            for i in windows.indices {
                for (sid, tid) in windows[i].selectedTabPerSpace { if let r = replaced[tid] { windows[i].selectedTabPerSpace[sid] = r } }
            }
            prefs.windows = windows
            for (w, tid) in previousTab { if let r = replaced[tid] { previousTab[w] = r } }
        }
        if changed { touch() }
    }

    /// Each space showing a list gets one of its own: the first takes the favorites and their
    /// pages, the others copies. A list no space shows stays with its profile for next time.
    private func unshareFavorites() {
        let splits = FavoritesSharing.unshare(favoritesBySpace(), lists: profileFavorites)
        guard !splits.isEmpty else { return }
        var windows = prefs.windows
        var expanded = prefs.expandedFolders
        var own: [UUID: UUID] = [:]
        for s in splits {
            let c = SidebarItem.container(.favorites(spaceID: s.spaceID))
            items[c.id] = c
            own[s.spaceID] = c.id
        }
        // Copies first: the space that takes the favorites empties the list.
        for s in splits where !s.takes {
            var map: [UUID: UUID] = [:]
            for child in items[s.from]?.children ?? [] { copySubtree(child, into: own[s.spaceID]!, copies: &map) }
            // A favorite open in this space stays open: it is now this space's copy.
            for i in windows.indices {
                if let sel = windows[i].selectedTabPerSpace[s.spaceID], let copy = map[sel] { windows[i].selectedTabPerSpace[s.spaceID] = copy }
            }
            for (old, new) in map where expanded.contains(old) { expanded.insert(new) }
        }
        for s in splits where s.takes {
            for child in items[s.from]?.children ?? [] { reparent(child, to: own[s.spaceID]!) }
        }
        for s in splits { spaces[s.spaceID]?.favoritesContainerID = own[s.spaceID]! }
        let emptied = Set(splits.map(\.from))
        for c in emptied { items[c] = nil }
        profileFavorites.removeAll { emptied.contains($0.containerID) }
        // A favorite left open in a space that changed profile now belongs to one space.
        for i in windows.indices {
            for (sid, tid) in windows[i].selectedTabPerSpace where items[tid] != nil && !isInSpace(tid, sid) && profileList(ofItem: tid) == nil {
                windows[i].selectedTabPerSpace[sid] = nil
            }
        }
        var p = prefs
        p.windows = windows
        p.expandedFolders = expanded
        prefs = p
        touch()
    }

    private func reparent(_ id: UUID, to parent: UUID) {
        guard var it = items[id] else { return }
        detach(id)
        it.parentID = parent
        items[id] = it
        items[parent]?.children.append(id)
    }

    /// `following`: the window that goes along to `sid`.
    func moveTab(_ id: UUID, toSpace sid: UUID, following: UUID? = nil) {
        moveTabs([id], toSpace: sid, following: following)
    }

    /// Items of one space, in sidebar order, moved together (picked tabs dropped on a space):
    /// favorites and pinned tabs join the end of their section, Today tabs lead the new Today,
    /// each keeping its order.
    func moveTabs(_ ids: [UUID], toSpace sid: UUID, following: UUID? = nil) {
        let ids = ids.filter { items[$0] != nil }
        guard let space = spaces[sid], let first = ids.first else { return }
        let from = spaceID(ofItem: first)
        let moved = Set(ids + ids.flatMap { tabs(under: $0).map(\.id) })
        let today = from.flatMap { spaces[$0] }.map { shownTabs(under: $0.todayContainerID) } ?? []
        // Favorites the space already shows (#154) stay where they are.
        let favorites = ids.filter { isFavorite($0) && !isInSpace($0, sid) }
        let pinned = ids.filter { !isFavorite($0) && isPinned($0) }
        moveItems(favorites, to: space.favoritesContainerID, index: nil)
        moveItems(pinned, to: space.pinnedContainerID, index: nil)
        moveItems(ids.filter { !isFavorite($0) && !pinned.contains($0) }, to: space.todayContainerID, index: 0)
        // The window that goes along leaves nothing selected in the old space (Arc 1.171, Move to
        // Today in <space>); another window that had it open there picks the next tab, as on close.
        guard let from, from != sid, spaceID(ofItem: first) == sid else { return }
        for w in prefs.windows {
            guard let sel = w.selectedTabPerSpace[from], moved.contains(sel) else { continue }
            let list = today.contains(sel) ? today.filter { $0 == sel || !moved.contains($0) } : []
            let next = w.id == following ? nil : closeSuccessor(of: sel, in: from, window: w.id, list: list)
            updateWindow(w.id) { $0.selectedTabPerSpace[from] = next }
            if let next, w.focusedSpaceID == from { noteShown(next) }
        }
    }

    /// Arc's command bar "Move to Today in <space>": the tab goes to that space and the
    /// window follows it there with the tab still selected. A pane brings its split along.
    @discardableResult
    func moveTabAndFollow(_ id: UUID, toSpace sid: UUID, window: UUID? = nil) -> Bool {
        let moving = splitContaining(id)?.id ?? id
        guard items[id]?.isTab == true, spaces[sid] != nil, spaceID(ofItem: moving) != sid else { return false }
        moveTab(moving, toSpace: sid, following: self.window(window).id)
        guard spaceID(ofItem: moving) == sid else { return false }
        selectTab(id, window: window)
        return true
    }

    /// The sidebar's Move to: the tab the window has open (or its split) takes the window
    /// along, as in Arc (#86); any other tab moves on its own.
    func moveTab(_ id: UUID, toSpace sid: UUID, window: UUID?) {
        if let open = selectedTabID(window: window), open == id || splitContaining(open)?.id == id {
            moveTabAndFollow(open, toSpace: sid, window: window)
        } else {
            moveTab(id, toSpace: sid)
        }
    }

    // MARK: Folders

    @discardableResult
    func createFolder(named name: String, in parent: UUID, index: Int? = nil) -> SidebarItem {
        var folder = SidebarItem.folder(name, parent: parent)
        folder.parentID = parent
        items[folder.id] = folder
        var p = items[parent]!
        p.children.insert(folder.id, at: min(index ?? p.children.count, p.children.count))
        items[parent] = p
        prefs.expandedFolders.insert(folder.id)
        // A collapsed pinned list would hide the new folder (and its rename field).
        if case .pinned(let sid)? = rootContainer(of: parent) { prefs.collapsedPinnedSpaces.remove(sid) }
        touch()
        return folder
    }

    /// Drop a tab onto another: both go into a new folder at the target's
    /// place. Folders only live in pinned sections, so a Today target puts
    /// the folder at the end of its space's pinned list.
    @discardableResult
    func createFolder(combining targetID: UUID, with tabID: UUID, named name: String = "New Folder") -> SidebarItem? {
        createFolder(combining: targetID, with: [tabID], named: name)
    }

    @discardableResult
    func createFolder(combining targetID: UUID, with tabIDs: [UUID], named name: String = "New Folder") -> SidebarItem? {
        let tabIDs = tabIDs.filter { $0 != targetID && items[$0]?.isTab == true }
        guard !tabIDs.isEmpty, items[targetID]?.isTab == true,
              let parent = items[targetID]?.parentID, let sid = spaceID(ofItem: targetID), let space = spaces[sid] else { return nil }
        guard liveFolder(containing: parent) == nil else { return nil }
        let inPinned = rootContainer(of: targetID) == .pinned(spaceID: sid)
        let folder = createFolder(named: name, in: inPinned ? parent : space.pinnedContainerID,
                                  index: inPinned ? items[parent]?.children.firstIndex(of: targetID) : nil)
        moveItems([targetID] + tabIDs, to: folder.id, index: nil)
        return items[folder.id]
    }

    func setFolderIcon(_ style: FolderIconStyle?, for id: UUID) {
        guard var it = items[id], it.isFolder else { return }
        it.folderIcon = style
        items[id] = it
        touch()
    }

    func setFolderSymbol(_ symbol: FolderSymbol?, for id: UUID) {
        guard var item = items[id], item.isFolder, !item.isLiveFolder, !item.isTabGroup,
              item.folderSymbol != symbol else { return }
        item.folderSymbol = symbol
        items[id] = item
        touch()
    }

    /// A new folder at the top of the space's pinned list holding these tabs.
    @discardableResult
    func createFolder(with tabIDs: [UUID], named name: String = "New Folder") -> SidebarItem {
        let folder = createFolder(named: name, in: focusedSpace.pinnedContainerID, index: 0)
        moveItems(tabIDs, to: folder.id, index: nil)
        return items[folder.id] ?? folder
    }

    func deleteFolder(_ id: UUID) {
        guard let f = items[id], f.isFolder else { return }
        // A live folder's tabs are the service's items, not the user's: they go with it.
        if f.isLiveFolder {
            removeLiveTree(id)
            touch()
            return
        }
        for t in tabs(under: id) { archiveTab(t.id, reason: .manual) }
        // Nested folders left behind (now empty) go too.
        for c in children(of: id) where c.isFolder { deleteFolder(c.id) }
        for c in children(of: id) where c.isSplit { items[c.id] = nil }
        detach(id)
        items[id] = nil
        touch()
    }

    // Rows read their own expansion, collapse and selection through these. They depend on
    // the item's signal, not on `prefs`, which changes on every tab switch and window move;
    // `notifyItemReaders` signals the items whose state actually changed.

    /// A tab group is always open: it has a header, not a folder's disclosure (Arc's TabGroupHeaderCellView).
    func isExpanded(_ id: UUID) -> Bool {
        items[id]?.isTabGroup == true || _prefs.expandedFolders.contains(id)
    }

    /// The tabs a closed folder lists under itself (FolderPeek), in sidebar order.
    func peekedTabs(in folder: UUID) -> [SidebarItem] {
        items.observe(folder)
        guard _prefs.peekedFolders[folder] != nil else { return [] }
        let inside = tabs(under: folder)
        let listed = Set(FolderPeek.listed(in: folder, peeks: _prefs.peekedFolders, tabsInside: inside.map(\.id)))
        return inside.filter { listed.contains($0.id) }
    }

    /// The tabs a container shows as rows, top to bottom: an open folder's, a closed folder's
    /// peeked ones, one pane per split (its focused one). Arc hands a close over to the row
    /// above or below among these, never to a tab hidden in a closed folder (#105).
    func shownTabs(under id: UUID) -> [UUID] {
        children(of: id).flatMap { c -> [UUID] in
            if c.isTab { return [c.id] }
            if let s = c.split { return [s.focusTabID.flatMap { c.children.contains($0) ? $0 : nil } ?? c.children.first].compactMap { $0 } }
            guard c.isFolder else { return [] }
            return c.isTabGroup || _prefs.expandedFolders.contains(c.id) ? shownTabs(under: c.id) : peekedTabs(in: c.id).map(\.id)
        }
    }

    /// The folders an item sits in, outermost first.
    private func folderChain(of id: UUID) -> [UUID] {
        var out: [UUID] = []
        var p = items[id]?.parentID
        while let pid = p, let parent = items[pid] {
            if parent.isFolder { out.insert(pid, at: 0) }
            p = parent.parentID
        }
        return out
    }

    /// Whether `id` is the open tab of the window's focused space, or of `space`.
    func isSelected(_ id: UUID, inSpace space: UUID? = nil, window: UUID?) -> Bool {
        items.observe(id)
        let w = untrackedWindow(window)
        if let space { return w.selectedTabPerSpace[space] == id }
        return Self.openTab(in: w, firstSpace: spaceOrder.first) == id
    }

    private func untrackedWindow(_ id: UUID?) -> WindowSession {
        let windows = _prefs.windows
        return windows.first { $0.id == (id ?? activeWindowID) } ?? windows.first { $0.id == activeWindowID } ?? windows[0]
    }

    private static func openTab(in w: WindowSession, firstSpace: UUID?) -> UUID? {
        (w.focusedSpaceID ?? firstSpace).flatMap { w.selectedTabPerSpace[$0] }
    }

    private func notifyItemReaders(of old: WindowPrefs) {
        for id in old.expandedFolders.symmetricDifference(prefs.expandedFolders) { items.notify(id) }
        for id in old.collapsedPinnedSpaces.symmetricDifference(prefs.collapsedPinnedSpaces) { items.notify(id) }
        for id in old.favoritesEmptyStateDismissed.symmetricDifference(prefs.favoritesEmptyStateDismissed) { items.notify(id) }
        for id in Set(old.peekedFolders.keys).union(prefs.peekedFolders.keys) where old.peekedFolders[id] != prefs.peekedFolders[id] {
            items.notify(id)
        }
        let first = spaceOrder.first
        for w in prefs.windows {
            let was = old.windows.first { $0.id == w.id }
            var changed: Set<UUID?> = []
            let before = was.flatMap { Self.openTab(in: $0, firstSpace: first) }, now = Self.openTab(in: w, firstSpace: first)
            if before != now { changed.formUnion([before, now]) }
            let oldPicks = was?.selectedTabPerSpace ?? [:]
            for space in Set(oldPicks.keys).union(w.selectedTabPerSpace.keys) where oldPicks[space] != w.selectedTabPerSpace[space] {
                changed.formUnion([oldPicks[space], w.selectedTabPerSpace[space]])
            }
            for case let id? in changed { items.notify(id) }
        }
    }
    func setExpanded(_ id: UUID, _ expanded: Bool) {
        var p = prefs
        if expanded { p.expandedFolders.insert(id) } else { p.expandedFolders.remove(id) }
        // Open, it shows everything; closed again, only the open tab stays in sight (Arc).
        let open = selectedTabID.flatMap { folderChain(of: $0).contains(id) ? $0 : nil }
        p.peekedFolders = FolderPeek.expanding(id, expanded, openTabInside: open, peeks: p.peekedFolders)
        if p != prefs { prefs = p }
    }

    /// Arc's Collapse All Folders / Expand All Folders: every folder in the space, nested ones too.
    func setAllFoldersExpanded(_ expanded: Bool, inSpace sid: UUID) {
        guard let space = spaces[sid] else { return }
        var folders: [UUID] = []
        func walk(_ id: UUID) {
            for c in children(of: id) where c.isFolder && !c.isTabGroup { folders.append(c.id); walk(c.id) }
        }
        walk(space.pinnedContainerID)
        walk(space.todayContainerID)
        for f in folders { setExpanded(f, expanded) }
    }

    /// Arc's Reveal Tab in Sidebar (⌃Space): open the folders the tab sits in, and its space's
    /// pinned section when that is collapsed and the tab is in it.
    func revealInSidebar(_ id: UUID) {
        for f in folderChain(of: id) where !isExpanded(f) { setExpanded(f, true) }
        if isPinned(id), let sid = spaceID(ofItem: id), isPinnedCollapsed(sid) { togglePinnedCollapsed(sid) }
    }

    /// Arc's spacesWithCollapsedPinnedSections: clicking the space name hides its pinned tabs.
    func isPinnedCollapsed(_ spaceID: UUID) -> Bool {
        items.observe(spaceID)
        return _prefs.collapsedPinnedSpaces.contains(spaceID)
    }
    func togglePinnedCollapsed(_ spaceID: UUID) {
        guard prefs.collapsedPinnedSpaces.remove(spaceID) == nil else { return }
        prefs.collapsedPinnedSpaces.insert(spaceID)
        // Collapsed, each window keeps only its open tab's row in sight, as a closed folder does.
        for w in prefs.windows {
            let open = w.selectedTabPerSpace[spaceID].flatMap { pinnedRow(of: $0, in: spaceID) }
            pinnedPeeks[w.id, default: [:]][spaceID] = PinnedPeek.collapsing(openPinnedRow: open)
        }
    }

    /// Arc's topAppsEmptyStateDismissedForProfiles: the × on the empty Favorites card closes it
    /// for that set of favorites, for good.
    func isFavoritesEmptyStateDismissed(_ favoritesID: UUID) -> Bool {
        items.observe(favoritesID)
        return _prefs.favoritesEmptyStateDismissed.contains(favoritesID)
    }
    func dismissFavoritesEmptyState(_ favoritesID: UUID) {
        prefs.favoritesEmptyStateDismissed.insert(favoritesID)
    }

    // MARK: Live folders

    var liveFolders: [SidebarItem] { items.values.filter(\.isLiveFolder) }

    struct LiveRequestContext: Equatable {
        var plugin: LiveFolderPluginConfiguration?
        var source: LiveFolderSource
        var serverURL: String?
        var profile: String
        var attributes: GitHubLiveFilter.Attributes
        var version: UUID?
    }

    func liveRequestContext(_ id: UUID) -> LiveRequestContext? {
        guard let live = items[id]?.liveFolder else { return nil }
        return LiveRequestContext(plugin: live.plugin.map { config in
            LiveFolderPluginConfiguration(id: config.id, settings: config.settings, filters: config.filters,
                                          state: config.state, sessionOrigins: config.sessionOrigins)
        }, source: live.source, serverURL: live.serverURL,
                                  profile: profileDirectoryName(item: id), attributes: live.filter.attributes,
                                  version: liveFolderVersions[id])
    }

    private func liveFolderRoots(under id: UUID) -> [SidebarItem] {
        guard let item = items[id] else { return [] }
        if item.isLiveFolder { return [item] }
        return children(of: id).flatMap { liveFolderRoots(under: $0.id) }
    }

    private func invalidateLiveFolder(_ id: UUID) {
        liveFolderVersions[id] = UUID()
        for tab in tabs(under: id) where tab.tab.map({ $0.liveItemURL == nil || $0.url != $0.liveItemURL }) == true {
            if let sid = spaceID(ofItem: id), let today = spaces[sid]?.todayContainerID { moveItem(tab.id, to: today, index: nil) }
        }
        for child in items[id]?.children ?? [] { removeLiveTree(child) }
        updateLiveFolder(id) {
            $0.hiddenItems = []
            $0.lastFetch = nil
            $0.lastError = nil
            $0.ssoOrganizations = []
            $0.enterprise = nil
            $0.plugin?.snapshot = nil
            $0.plugin?.state = [:]
        }
        liveFolderChanged(id)
    }

    func liveFolder(containing id: UUID) -> SidebarItem? {
        var current: UUID? = id
        for _ in 0..<64 {
            guard let key = current, let item = items[key] else { return nil }
            if item.isLiveFolder { return item }
            current = item.parentID
        }
        return nil
    }

    /// The space's live folder for a source (Dia: one Pull Requests folder per space).
    /// Walks only the space's own lists, so a view that asks depends on those items alone.
    func liveFolder(_ source: LiveFolderSource, inSpace sid: UUID, serverURL: String? = nil) -> SidebarItem? {
        guard let space = spaces[sid] else { return nil }
        let server = serverURL.flatMap(GitLabLiveClient.serverURL)
        func find(under id: UUID) -> SidebarItem? {
            for c in children(of: id) where c.isFolder || c.isSplit {
                if let live = c.liveFolder, live.source == source,
                   serverURL == nil || (server != nil && live.serverURL.flatMap(GitLabLiveClient.serverURL) == server) { return c }
                if let found = find(under: c.id) { return found }
            }
            return nil
        }
        for root in [space.favoritesContainerID, space.pinnedContainerID, space.todayContainerID] {
            if let found = find(under: root) { return found }
        }
        return nil
    }

    func updateLiveFolder(_ id: UUID, _ change: (inout LiveFolderData) -> Void) {
        guard var live = items[id]?.liveFolder else { return }
        let previousFilters = live.plugin?.filters
        change(&live)
        if live.plugin?.snapshotFilters == nil, live.plugin?.filters != previousFilters {
            live.plugin?.snapshotFilters = previousFilters
        }
        items[id]?.liveFolder = live
        touch()
    }

    @discardableResult
    func createPluginFolder(_ configuration: LiveFolderPluginConfiguration, title: String, inSpace sid: UUID, legacySource: String? = nil) -> SidebarItem? {
        if let existing = liveFolders.first(where: { isInSpace($0.id, sid) && $0.liveFolder?.plugin?.id == configuration.id &&
            $0.liveFolder?.plugin?.settings == configuration.settings }) { return existing }
        guard let space = spaces[sid], !isStandalone(space: sid) else { return nil }
        let folder = createFolder(named: title, in: space.pinnedContainerID, index: 0)
        var live = LiveFolderData()
        live.plugin = configuration
        live.source = legacySource.flatMap(LiveFolderSource.init(rawValue:)) ?? .plugin
        items[folder.id]?.liveFolder = live
        touch()
        return items[folder.id]
    }

    func liveRepositories(_ id: UUID, fetched: [String]? = nil) -> [String] {
        guard let live = items[id]?.liveFolder else { return [] }
        let known = fetched ?? live.plugin?.snapshot?.items.compactMap(\.group)
            ?? children(of: id).compactMap { $0.tab?.liveItemURL.flatMap(live.repository) }
        var repositories: [String: String] = [:]
        for repository in known + live.filter.hiddenRepositories where repositories[repository.lowercased()] == nil {
            repositories[repository.lowercased()] = repository
        }
        return repositories.values.sorted { $0.lowercased() < $1.lowercased() }
    }

    private func removeLiveTree(_ id: UUID) {
        for child in items[id]?.children ?? [] { removeLiveTree(child) }
        detach(id)
        items[id] = nil
        prefs.expandedFolders.remove(id)
        prefs.peekedFolders.removeValue(forKey: id)
    }

    func applyPluginResults(_ snapshot: LiveFolderPluginSnapshot, to folderID: UUID, context: LiveRequestContext? = nil) {
        if let context, liveRequestContext(folderID) != context { return }
        guard var folder = items[folderID], var live = folder.liveFolder else { return }
        let hidden = Set(live.hiddenItems)
        let filtersChanged = live.plugin.map { config in
            config.snapshotFilters.map { Set($0) != Set(config.filters) } ?? false
        } ?? false
        let wanted = snapshot.items.filter { !hidden.contains($0.url) && !live.filter.isRepositoryHidden($0.group ?? "") }
        let groups = Dictionary(uniqueKeysWithValues: (live.plugin?.snapshot?.items ?? []).map { ($0.url, $0.group ?? "") })
        var existing: [String: UUID] = [:]
        for c in children(of: folderID) { if let u = c.tab?.liveItemURL { existing[u] = c.id } }
        let firstFill = live.lastFetch == nil || (live.lastError != nil && existing.isEmpty)
        var order: [UUID] = []
        for pr in wanted {
            let subtitle = pr.subtitle
            if let id = existing.removeValue(forKey: pr.url) ?? adoptablePluginTab(url: pr.url, folderID: folderID),
               var it = items[id], var t = it.tab {
                if it.parentID != folderID {
                    detach(id)
                    it.parentID = folderID
                    t.savedURL = pr.url
                }
                t.savedTitle = pr.title
                t.liveItemURL = pr.url
                t.liveSubtitle = subtitle
                t.liveGoneAt = nil
                it.data = .tab(t)
                items[id] = it
                order.append(id)
            } else {
                var tab = SidebarItem.tab(pr.url, title: pr.title, parent: folderID)
                var t = TabData(url: pr.url, title: pr.title)
                t.liveItemURL = pr.url
                t.liveSubtitle = subtitle
                tab.data = .tab(t)
                tab.isUnread = !firstFill
                tab.createdAt = pr.createdAt ?? clock.now
                items[tab.id] = tab
                order.append(tab.id)
            }
        }
        let preserved = Set(snapshot.preservedGroups.map { $0.lowercased() })
        for id in existing.values {
            guard var it = items[id], var t = it.tab else { continue }
            let preservesGroup = t.liveItemURL.flatMap { groups[$0] }.map { preserved.contains($0.lowercased()) } ?? false
            let hiddenGroup = t.liveItemURL.flatMap { groups[$0] }.map { live.filter.isRepositoryHidden($0) } ?? false
            if hiddenGroup || (filtersChanged && !preservesGroup) {
                let url = t.liveItemURL
                if t.url == url {
                    removeLiveTree(id)
                    for window in prefs.windows where window.selectedTabPerSpace.values.contains(id) {
                        updateWindow(window.id) { $0.selectedTabPerSpace = $0.selectedTabPerSpace.filter { $0.value != id } }
                    }
                } else if t.liveGoneAt != nil {
                    t.liveGoneAt = nil
                    it.data = .tab(t)
                    items[id] = it
                }
                continue
            }
            guard t.liveGoneAt == nil else { continue }
            if let url = t.liveItemURL, let group = groups[url], preserved.contains(group.lowercased()) { continue }
            t.liveGoneAt = clock.now
            it.data = .tab(t)
            items[id] = it
        }
        folder = items[folderID] ?? folder
        folder.children = order + folder.children.filter { !order.contains($0) && items[$0] != nil }
        live.lastFetch = clock.now
        live.lastError = nil
        var cached = snapshot
        let incoming = Set(snapshot.items.map(\.url))
        let retained = Set(folder.children.compactMap { items[$0]?.tab?.liveItemURL })
        cached.items += (live.plugin?.snapshot?.items ?? []).filter { !incoming.contains($0.url) && retained.contains($0.url) }
        live.plugin?.snapshot = cached
        let currentFilters = live.plugin?.filters
        live.plugin?.snapshotFilters = currentFilters
        folder.liveFolder = live
        items[folderID] = folder
        touch()
    }

    private func adoptablePluginTab(url: String, folderID: UUID) -> UUID? {
        guard let sid = spaceID(ofItem: folderID), let space = spaces[sid] else { return nil }
        return children(of: space.todayContainerID).first { $0.tab?.url == url }?.id
    }

    /// Live tabs whose pull request left the results longer than `age` ago go; one open in a
    /// window stays until it isn't.
    func expireLiveItems(olderThan age: TimeInterval) {
        let open = Set(prefs.windows.flatMap { $0.selectedTabPerSpace.values })
        var changed = false
        for folder in liveFolders {
            for c in tabs(under: folder.id) where !open.contains(c.id) {
                guard let tab = c.tab, tab.url == tab.liveItemURL,
                      let goneAt = tab.liveGoneAt, clock.now.timeIntervalSince(goneAt) >= age else { continue }
                detach(c.id)
                items[c.id] = nil
                changed = true
            }
        }
        if changed { touch() }
    }

    func applyLiveFailure(_ error: LiveFolderError, to folderID: UUID, context: LiveRequestContext? = nil) {
        if let context, liveRequestContext(folderID) != context { return }
        updateLiveFolder(folderID) {
            $0.lastFetch = clock.now
            $0.lastError = error
        }
    }

    /// Remembers a tab leaving its live folder so the next refresh doesn't bring it back;
    /// the tab itself becomes an ordinary one.
    private func hideLiveItem(_ id: UUID, in folderID: UUID) {
        guard var it = items[id], var t = it.tab, let url = t.liveItemURL, var live = items[folderID]?.liveFolder else { return }
        if !live.hiddenItems.contains(url) { live.hiddenItems.append(url) }
        // Arc keeps a short list; old pull requests are long closed.
        if live.hiddenItems.count > 200 { live.hiddenItems.removeFirst(live.hiddenItems.count - 200) }
        items[folderID]?.liveFolder = live
        t.liveItemURL = nil
        t.liveSubtitle = nil
        it.data = .tab(t)
        items[id] = it
    }

    // MARK: Archive

    func archiveTab(_ id: UUID, reason: ArchiveReason) {
        guard let it = items[id], it.isTab else { return }
        // ⌘Z now brings this tab back, not the tidy before it (Arc's undo stack).
        lastTidy = nil
        let sid = spaceID(ofItem: id)
        // Each window and space that has it open, every space sharing it for a favorite.
        let shownIn = spaceIDs(ofItem: id)
        let selectedIn = prefs.windows.flatMap { w in shownIn.filter { w.selectedTabPerSpace[$0] == id }.map { (w.id, $0) } }
        let pinned = isPinned(id)
        let split = splitContaining(id)
        let folder = it.parentID.flatMap { items[$0]?.isFolder == true ? $0 : nil }
        let index = folder.flatMap { items[$0]?.children.firstIndex(of: id) }
        let list = pinned ? [] : (sid.flatMap { spaces[$0] }.map { shownTabs(under: $0.todayContainerID) } ?? [])
        // Closed out of a live folder: the item stays out (Arc: hiddenItems). The archive keeps
        // the live copy so ⇧⌘T can put it back.
        if let folder, let live = liveFolder(containing: folder) {
            hideLiveItem(id, in: live.id)
        }
        detach(id)
        items[id] = nil
        // Empty panes never had a page and incognito pages leave no trace: nothing for the Library.
        if !it.isEmptyTab, !isIncognito(space: sid) {
            archive.insert(ArchivedItem(archivedAt: clock.now, reason: reason, sourceSpaceID: sid, wasPinned: pinned, item: it,
                                        sourceFolderID: folder, sourceIndex: index), at: 0)
            if archive.count > 2000 { archive.removeLast(archive.count - 2000) }
        }
        if !selectedIn.isEmpty {
            for (w, sid) in selectedIn {
                // Closing a pane keeps the split on screen: focus a neighbour pane. The split
                // still goes back to the tab shown before it (Arc).
                let kept = previousTab[w]
                let next = split.flatMap { s in items[s.id]?.children.first { items[$0]?.isTab == true } }
                    ?? closeSuccessor(of: id, in: sid, window: w, list: list)
                updateWindow(w) { $0.selectedTabPerSpace[sid] = next }
                guard focusedSpaceID(window: w) == sid else { continue }
                if split != nil { previousTab[w] = kept }
                if let next { noteShown(next) }
            }
        }
        if let split { collapseSplitIfNeeded(split.id) }
        touch()
    }

    /// The tab shown once the selected `id` closes in window `w`: `list` is the space's Today
    /// tabs while `id` is still among them, empty for a pinned tab.
    private func closeSuccessor(of id: UUID, in sid: UUID, window w: UUID, list: [UUID]) -> UUID? {
        let back = previousTab[w].flatMap { isInSpace($0, sid) ? $0 : nil }
        return CloseSuccessor.next(closing: id, previous: back, hasPage: hasPage, list: list)
    }

    /// A pinned tab, favorite or pinned split closed (unloaded) while selected: the tab to show
    /// instead, if any.
    func closeSuccessor(ofPinned id: UUID, window w: UUID) -> UUID? {
        guard let sid = spaceID(ofItem: id, window: w) else { return nil }
        let back = previousTab[w].flatMap { isInSpace($0, sid) ? $0 : nil }
        return CloseSuccessor.afterPinned(closing: id, isSplit: splitContaining(id) != nil, previous: back, hasPage: hasPage)
    }

    @discardableResult
    func restoreArchived(_ id: UUID, select: Bool = true) -> SidebarItem? {
        guard let idx = archive.firstIndex(where: { $0.id == id }) else { return nil }
        let entry = archive.remove(at: idx)
        var it = entry.item
        let sid = entry.sourceSpaceID.flatMap { spaces[$0] != nil ? $0 : nil } ?? focusedSpaceID
        let space = spaces[sid]!
        // Back into the folder it was closed from, if that's still in the space.
        let folder = entry.sourceFolderID.flatMap { items[$0]?.isFolder == true && spaceID(ofItem: $0) == sid ? $0 : nil }
        let parent = folder ?? (entry.wasPinned ? space.pinnedContainerID : space.todayContainerID)
        if let folder, let url = it.tab?.liveItemURL, items[folder]?.isLiveFolder == true {
            updateLiveFolder(folder) { $0.hiddenItems.removeAll { $0 == url } }
        } else if var t = it.tab, t.liveItemURL != nil {
            t.liveItemURL = nil
            t.liveSubtitle = nil
            t.liveGoneAt = nil
            it.data = .tab(t)
        }
        it.parentID = parent
        it.children = []
        it.isUnread = false
        items[it.id] = it
        var p = items[parent]!
        let index = folder != nil ? min(entry.sourceIndex ?? 0, p.children.count) : entry.wasPinned ? p.children.count : 0
        p.children.insert(it.id, at: index)
        items[parent] = p
        if select { selectTab(it.id) } else { touch() }
        return it
    }

    @discardableResult
    func reopenLastArchived() -> SidebarItem? {
        guard let last = archive.first else { return nil }
        return restoreArchived(last.id)
    }

    func removeFromArchive(_ id: UUID) {
        archive.removeAll { $0.id == id }
        touch()
    }

    func clearArchive() {
        archive.removeAll()
        touch()
    }

    // MARK: Tab groups (Tidy Tabs)

    /// Spaces whose Today tabs the model is sorting: the divider draws its squiggle meanwhile.
    private(set) var tidyingSpaces: Set<UUID> = []
    /// Per space, Today's tabs when Tidy last ran: Tidy waits for a new loose tab (TidyTabs.offers).
    /// Not saved, like Arc's.
    private(set) var tidiedTabs: [UUID: Set<UUID>] = [:]
    /// What ⌘Z puts back: the last tidy, until a tab closes or a group's header is used.
    @ObservationIgnored private var lastTidy: (spaceID: UUID, todayBefore: [UUID], moved: [UUID])?

    /// Today's top-level tabs, outside any group: what Tidy sorts.
    func looseTodayTabs(_ sid: UUID) -> [SidebarItem] {
        guard let space = spaces[sid] else { return [] }
        return children(of: space.todayContainerID).filter(\.isTab)
    }

    func tabGroups(in sid: UUID) -> [SidebarItem] {
        guard let space = spaces[sid] else { return [] }
        return children(of: space.todayContainerID).filter(\.isTabGroup)
    }

    /// Whether the divider offers Tidy now (the Apple Intelligence check is the caller's).
    func canTidy(_ sid: UUID) -> Bool {
        guard let space = spaces[sid], !isIncognito(space: sid) else { return false }
        return TidyTabs.offers(todayTabs: tabs(under: space.todayContainerID).count,
                               looseTabs: looseTodayTabs(sid).map(\.id), tidied: tidiedTabs[sid])
    }

    func setTidying(_ sid: UUID, _ on: Bool) {
        if on { tidyingSpaces.insert(sid) } else { tidyingSpaces.remove(sid) }
    }

    /// Sorts `tabIDs` (the loose tabs the model saw, in prompt order) as the plan says: new groups
    /// under the loose tabs left over, tabs joining groups Today already had. A plan that changes
    /// nothing still counts as a run, as Arc's did.
    func applyTidy(_ plan: TidyTabs.Plan, tabIDs: [UUID], in sid: UUID) {
        guard let space = spaces[sid] else { return }
        let today = space.todayContainerID
        let before = items[today]?.children ?? []
        let groups = tabGroups(in: sid)
        let loose = Set(looseTodayTabs(sid).map(\.id))
        func ids(_ indices: [Int]) -> [UUID] {
            indices.compactMap { tabIDs.indices.contains($0) ? tabIDs[$0] : nil }.filter(loose.contains)
        }
        var moved: [UUID] = []
        for (g, indices) in plan.joins.sorted(by: { $0.key < $1.key }) where groups.indices.contains(g) {
            let tabs = ids(indices)
            moveItems(tabs, to: groups[g].id, index: nil)
            moved += tabs
        }
        var newGroups: [UUID] = []
        for p in plan.newGroups {
            let tabs = ids(p.tabs)
            guard tabs.count >= 2 else { continue }
            var g = SidebarItem.tabGroup(p.name, parent: today)
            g.createdAt = clock.now
            items[g.id] = g
            var t = items[today]!
            t.children.append(g.id)
            items[today] = t
            moveItems(tabs, to: g.id, index: nil)
            newGroups.append(g.id)
            moved += tabs
        }
        if var t = items[today] {
            let rest = t.children.filter { !newGroups.contains($0) }
            t.children = TidyTabs.order(today: rest, isGroup: { self.items[$0]?.isTabGroup == true }, grouped: [], newGroups: newGroups)
            items[today] = t
        }
        lastTidy = moved.isEmpty ? nil : (sid, before, moved)
        tidiedTabs[sid] = Set(tabs(under: today).map(\.id))
        touch()
    }

    /// A run that ended without a plan (the model failed or had nothing to say) still hides Tidy.
    func markTidied(_ sid: UUID) {
        guard let space = spaces[sid] else { return }
        tidiedTabs[sid] = Set(tabs(under: space.todayContainerID).map(\.id))
    }

    /// ⌘Z after a tidy: the tabs it moved go back where they were, its new groups go with them.
    func undoTidy() -> Bool {
        guard let u = lastTidy, let space = spaces[u.spaceID] else { return false }
        lastTidy = nil
        let today = space.todayContainerID
        for id in u.moved where items[id] != nil && items[id]?.parentID != today {
            moveItem(id, to: today, index: nil)
        }
        if var t = items[today] {
            let old = u.todayBefore.filter(t.children.contains)
            t.children = t.children.filter { !old.contains($0) } + old
            items[today] = t
        }
        tidiedTabs[u.spaceID] = nil
        touch()
        return true
    }

    /// Arc's "Remove header": the tabs stay where they are, loose.
    func removeGroupHeader(_ id: UUID) {
        guard let g = items[id], g.isTabGroup, let p = g.parentID, let at = items[p]?.children.firstIndex(of: id) else { return }
        lastTidy = nil
        moveItems(g.children, to: p, index: at)
        touch()
    }

    /// Arc's "Create Folder" on a group header: an open folder of that name leads the space's
    /// pinned tabs, holding the group's tabs (pinned now); the group goes.
    @discardableResult
    func folderFromGroup(_ id: UUID) -> SidebarItem? {
        guard let g = items[id], g.isTabGroup, let sid = spaceID(ofItem: id), let space = spaces[sid] else { return nil }
        lastTidy = nil
        let f = createFolder(named: g.title ?? "Folder", in: space.pinnedContainerID, index: 0)
        moveItems(g.children, to: f.id, index: nil)
        touch()
        return items[f.id]
    }

    /// A group whose last tab closed or moved out goes too (Arc never shows an empty header).
    private func pruneEmptyGroups() {
        for space in spaces.values {
            guard var t = items[space.todayContainerID] else { continue }
            let empty = t.children.filter { items[$0].map { $0.isTabGroup && $0.children.isEmpty } ?? false }
            guard !empty.isEmpty else { continue }
            t.children.removeAll { empty.contains($0) }
            items[t.id] = t
            for g in empty { items[g] = nil }
        }
    }

    /// Arc's Today tab menu "Archive Tabs Below": every Today row under this one (splits and
    /// groups with all their tabs). Pinned and favorite tabs don't offer it.
    func archiveTabsBelow(_ id: UUID) {
        guard let item = items[id], let parent = item.parentID, let sid = spaceID(ofItem: id),
              spaces[sid]?.todayContainerID == parent,
              let rows = items[parent]?.children, let i = rows.firstIndex(of: id) else { return }
        for row in rows[(i + 1)...] {
            guard let r = items[row] else { continue }
            for t in r.isTab ? [r] : tabs(under: row) { archiveTab(t.id, reason: .manual) }
        }
    }

    func clearToday(_ sid: UUID? = nil) {
        guard let space = spaces[sid ?? focusedSpaceID] else { return }
        for t in tabs(under: space.todayContainerID) { archiveTab(t.id, reason: .clear) }
    }

    /// Today tabs idle longer than the threshold are archived (Arc:
    /// ArchiveState+AutoArchive, autoArchiveTimeThreshold).
    func runAutoArchive() {
        guard settings.autoArchiveEnabled else { return }
        let cutoff = clock.now.addingTimeInterval(-settings.autoArchive.seconds)
        for space in orderedSpaces {
            let selected = Set(prefs.windows.compactMap { $0.selectedTabPerSpace[space.id] })
            for t in tabs(under: space.todayContainerID) where !selected.contains(t.id) {
                let last = t.tab?.timeLastActiveAt ?? t.createdAt
                if last < cutoff { archiveTab(t.id, reason: .auto) }
            }
        }
    }

    // MARK: Spaces

    @discardableResult
    func createSpace(title: String, emoji: String, symbol: String? = nil, theme: SpaceTheme? = nil, focus: Bool = true) -> Space {
        let id = UUID()
        let favorites = SidebarItem.container(.favorites(spaceID: id))
        let pinned = SidebarItem.container(.pinned(spaceID: id))
        let today = SidebarItem.container(.today(spaceID: id))
        items[favorites.id] = favorites
        items[pinned.id] = pinned
        items[today.id] = today
        let t = theme ?? SpaceTheme.presets[spaceOrder.count % SpaceTheme.presets.count]
        let space = Space(id: id, title: title, emoji: emoji, theme: t, favoritesContainerID: favorites.id,
                          pinnedContainerID: pinned.id, todayContainerID: today.id, createdAt: clock.now, symbol: symbol)
        spaces[id] = space
        spaceOrder.append(id)
        if settings.sharedFavorites { shareFavorites() }
        if focus, !isStandalone(window: nil) { updateWindow(nil) { $0.focusedSpaceID = id } }
        touch()
        return spaces[id] ?? space
    }

    func updateSpace(_ space: Space) {
        guard spaces[space.id] != nil else { return }
        storedThemes[space.id] = nil
        spaces[space.id] = space
        touch()
    }

    /// A theme editor's change: drawn at once wherever the space shows, not written (Arc writes
    /// StorableSidebar.json when the editor commits). `endThemePreview` keeps or drops it.
    func previewTheme(_ theme: SpaceTheme, forSpace id: UUID) {
        guard var s = spaces[id] else { return }
        if storedThemes[id] == nil { storedThemes[id] = s.theme }
        s.theme = theme
        spaces[id] = s
    }

    /// The editor closed: `keep` writes the previewed theme, otherwise the stored one comes back.
    func endThemePreview(forSpace id: UUID, keep: Bool) {
        guard let stored = storedThemes.removeValue(forKey: id), var s = spaces[id] else { return }
        if keep {
            if s.theme != stored { touch() }
        } else if s.theme != stored {
            s.theme = stored
            spaces[id] = s
        }
    }

    func deleteSpace(_ id: UUID) {
        guard spaceOrder.count > 1, spaceOrder.contains(id), let space = spaces[id] else { return }
        // A profile's favorites stay with the profile (Arc).
        let shared = isProfileList(space.favoritesContainerID)
        let favorites = shared ? [] : [space.favoritesContainerID]
        for t in (favorites + [space.pinnedContainerID, space.todayContainerID]).flatMap({ tabs(under: $0) }) {
            archiveTab(t.id, reason: .spaceDeleted)
        }
        for c in (favorites + [space.pinnedContainerID]).flatMap({ children(of: $0) }) where c.isFolder { deleteFolder(c.id) }
        for c in favorites { items[c] = nil }
        items[space.pinnedContainerID] = nil
        items[space.todayContainerID] = nil
        spaces[id] = nil
        storedThemes[id] = nil
        spaceOrder.removeAll { $0 == id }
        var windows = prefs.windows
        for i in windows.indices {
            windows[i].selectedTabPerSpace[id] = nil
            if windows[i].focusedSpaceID == id { windows[i].focusedSpaceID = spaceOrder.first }
        }
        prefs.windows = windows
        touch()
    }

    /// Arc's "Export “<space>” into Folder": the space's favorites, pinned and Today items go into
    /// a folder named after it at the top of the target's pinned list, then the space is deleted
    /// (Arc logs it as "Space turned into folder"). Live folders fill themselves, so they go with it.
    @discardableResult
    func exportSpace(_ id: UUID, intoFolderIn target: UUID) -> SidebarItem? {
        guard id != target, let space = spaces[id], let dest = spaces[target], spaceOrder.count > 1 else { return nil }
        let folder = createFolder(named: space.title, in: dest.pinnedContainerID, index: 0)
        let moving = ((isProfileList(space.favoritesContainerID) ? [] : [space.favoritesContainerID]) + [space.pinnedContainerID, space.todayContainerID])
            .flatMap { children(of: $0) }
            .filter { !$0.isLiveFolder }
            .map(\.id)
        moveItems(moving, to: folder.id, index: nil)
        var windows = prefs.windows
        for i in windows.indices where windows[i].focusedSpaceID == id { windows[i].focusedSpaceID = target }
        prefs.windows = windows
        deleteSpace(id)
        return items[folder.id]
    }

    // MARK: Profiles

    func profile(_ id: UUID?) -> BrowserProfile? { id.flatMap { p in profiles.first { $0.id == p } } }
    func spaces(usingProfile id: UUID?) -> [Space] { orderedSpaces.filter { $0.profileID == id } }

    /// The Chromium folder a tab's pages load in: its space's profile, or nil for the
    /// Default profile (and for incognito, which has its own off-the-record one).
    func profilePath(item id: UUID) -> String? {
        if let l = profileList(ofItem: id) {
            return profile(l.profileID).map { AppPaths.chromiumCache.appendingPathComponent($0.directoryName, isDirectory: true).path }
        }
        return spaceID(ofItem: id).flatMap { profilePath(space: $0) }
    }

    /// A shared favorite loads in its list's profile (#154): a space that changed profile with
    /// one open keeps showing it, in the profile it was opened in (Arc).
    func profileList(ofItem id: UUID) -> ProfileFavorites? {
        guard let root = rootContainerItem(of: id)?.id else { return nil }
        return profileFavorites.first { $0.containerID == root }
    }

    func profilePath(space sid: UUID) -> String? {
        guard !isIncognito(space: sid) else { return nil }
        return profilePath(profile: spaces[sid]?.profileID)
    }

    /// A profile's Chromium folder, nil for Default (and for a profile that is gone).
    func profilePath(profile id: UUID?) -> String? {
        profile(id).map { AppPaths.chromiumCache.appendingPathComponent($0.directoryName, isDirectory: true).path }
    }

    /// The profile a page loads in, from its browser's folder (nil = Default).
    func profileID(path: String?) -> UUID? {
        guard let path else { return nil }
        return profiles.first { profilePath(profile: $0.id) == path }?.id
    }

    /// The profile a tab's pages load in: its shared-favorites list's, else its space's.
    func profileID(item id: UUID) -> UUID? {
        if let l = profileList(ofItem: id) { return profile(l.profileID)?.id }
        return spaceID(ofItem: id).flatMap(profileID(space:))
    }

    /// The profile a space's pages load in (nil = Default, and for an incognito space).
    func profileID(space id: UUID) -> UUID? {
        isIncognito(space: id) ? nil : profile(spaces[id]?.profileID)?.id
    }

    /// The Chromium profile folder ("Default" or "Profile <id>") a space's pages load in;
    /// incognito spaces count as Default, whose off-the-record profile they use.
    func profileDirectoryName(space id: UUID) -> String {
        guard !isIncognito(space: id), let p = profile(spaces[id]?.profileID) else { return "Default" }
        return p.directoryName
    }

    func profileDirectoryName(item id: UUID) -> String {
        if let l = profileList(ofItem: id) { return profile(l.profileID)?.directoryName ?? "Default" }
        return spaceID(ofItem: id).map { profileDirectoryName(space: $0) } ?? "Default"
    }

    @discardableResult
    func createProfile(name: String) -> BrowserProfile {
        let p = BrowserProfile(id: UUID(), name: name)
        profiles.append(p)
        touch()
        return p
    }

    func renameProfile(_ id: UUID, to name: String) {
        guard let i = profiles.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        profiles[i].name = name
        touch()
    }

    /// Pages already open in the space load again in the new profile (BrowserManager).
    func setProfile(_ profileID: UUID?, forSpace id: UUID) {
        guard var s = spaces[id], s.profileID != profileID, profileID == nil || profile(profileID) != nil else { return }
        let previousProfiles = Dictionary(uniqueKeysWithValues: liveFolders.map { ($0.id, profileDirectoryName(item: $0.id)) })
        // Arc: favorites belong to the profile. The space shows its new profile's list and takes
        // nothing along; the old list stays with the old profile, shown or not. A favorite open in
        // the space stays open, in its own profile, though its tile is gone (Arc 1.171).
        if isProfileList(s.favoritesContainerID) { s.favoritesContainerID = profileList(profileID) }
        s.profileID = profileID
        spaces[id] = s
        for (folder, profile) in previousProfiles where profileDirectoryName(item: folder) != profile {
            invalidateLiveFolder(folder)
        }
        touch()
    }

    /// The space's own search engine by Chromium keyword (GitHub #306); nil searches the default.
    func setSearchEngine(_ keyword: String?, forSpace id: UUID) {
        let keyword = keyword?.isEmpty == true ? nil : keyword
        guard var s = spaces[id], s.searchEngine != keyword else { return }
        s.searchEngine = keyword
        spaces[id] = s
        touch()
    }

    /// Arc: only profiles no space uses can be deleted. Chromium may still hold the
    /// folder open, so it goes at the next launch (ProfileCleanup).
    func deleteProfile(_ id: UUID) {
        guard let p = profile(id), spaces.values.allSatisfy({ $0.profileID != id }) else { return }
        profiles.removeAll { $0.id == id }
        // Its favorites go with it.
        for l in profileFavorites where l.profileID == id {
            func drop(_ id: UUID) {
                for c in items[id]?.children ?? [] { drop(c) }
                items[id] = nil
            }
            drop(l.containerID)
        }
        profileFavorites.removeAll { $0.profileID == id }
        settings.downloadLocations[DownloadLocation.key(profileID: id)] = nil
        settings.setNewDocumentApp(nil, profileID: id)
        ProfileCleanup.schedule(p.directoryName)
        touch()
    }

    func moveSpace(_ id: UUID, to index: Int) {
        guard let from = spaceOrder.firstIndex(of: id) else { return }
        spaceOrder.remove(at: from)
        spaceOrder.insert(id, at: min(max(0, index), spaceOrder.count))
        touch()
    }

    /// Two windows can have the same tab open; its page shows in the one in use
    /// (MainWindowController.refresh).
    func focusSpace(_ id: UUID, window: UUID? = nil) {
        let w = self.window(window).id
        guard spaces[id] != nil, id != focusedSpaceID(window: w), !isStandalone(window: w), !isStandalone(space: id) else { return }
        updateWindow(w) { $0.focusedSpaceID = id }
        revision &+= 1
    }

    func focusSpace(offset: Int, window: UUID? = nil) {
        guard let idx = spaceOrder.firstIndex(of: focusedSpaceID(window: window)), spaceOrder.count > 1 else { return }
        let n = spaceOrder.count
        focusSpace(spaceOrder[((idx + offset) % n + n) % n], window: window)
    }

    // MARK: History and ranking signals

    func recordVisit(url: String, title: String) {
        guard url.hasPrefix("http") else { return }
        var e = history[url] ?? HistoryEntry(url: url, title: title, lastVisit: clock.now, visitCount: 0)
        e.visitCount += 1
        e.lastVisit = clock.now
        if !title.isEmpty { e.title = title }
        history[url] = e
        if history.count > 5000 {
            let drop = history.values.sorted { $0.lastVisit < $1.lastVisit }.prefix(history.count - 5000)
            for d in drop { history[d.url] = nil }
        }
        historyFile.save(Array(history.values), delay: 5)
    }

    func recordQuerySelection(query: String, url: String) {
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, !window().isIncognito else { return }
        ranking.queriesToSelected[q] = url
        if ranking.queriesToSelected.count > 500 {
            if let k = ranking.queriesToSelected.keys.first { ranking.queriesToSelected[k] = nil }
        }
        rankingFile.save(ranking)
    }

    /// Chrome's Delete browsing data deleted history: the command bar forgets it too, and the
    /// archive (Cra's History) drops the tabs closed in that time.
    func clearHistory(_ range: BrowsingDataClear.Range) {
        (history, ranking) = BrowsingDataClear.clearing(range, history: history, ranking: ranking)
        archive = BrowsingDataClear.keptArchive(archive, clearing: range)
        historyFile.saveNow(Array(history.values))
        rankingFile.saveNow(ranking)
        archiveFile.saveNow(archive)
        touch()
        CraLog.note("history cleared (\(range == .allTime ? "all time" : "a time range"))")
    }

    func recordCommandUse(_ id: String) {
        ranking.commandUsage[id, default: 0] += 1
        rankingFile.save(ranking)
    }
}
