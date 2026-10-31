import AppKit

/// The tab list's context menus (the SwiftUI rows' .contextMenu, item for item).
@MainActor
enum SidebarMenus {
    private final class Action: NSObject {
        let run: () -> Void
        init(_ run: @escaping () -> Void) { self.run = run }
        @objc func fire() { run() }
    }

    private static func menu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        return m
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, enabled: Bool = true, on: Bool? = nil, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = Action(run)
        let item = NSMenuItem(title: title, action: #selector(Action.fire), keyEquivalent: "")
        item.target = a
        item.representedObject = a
        item.isEnabled = enabled
        if let on { item.state = on ? .on : .off }
        menu.addItem(item)
        return item
    }

    private static func note(_ menu: NSMenu, _ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    private static func submenu(_ menu: NSMenu, _ title: String) -> NSMenu {
        let sub = Self.menu()
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = sub
        menu.addItem(item)
        return sub
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    // MARK: Tabs

    static func tab(_ m: TabRowModel, list: SpaceListView) -> NSMenu {
        let store = list.store, ui = list.ui, actions = list.actions
        let id = m.id
        let menu = menu()
        let group = list.closeGroup(for: id)
        if group.count > 1 {
            folderItems(menu, ui.group(for: id, in: store), list: list)
            menu.addItem(.separator())
            add(menu, "Close \(group.count) Tabs") { list.closeTabs(group) }
            add(menu, "Deselect All") { ui.clearPicks() }
            return menu
        }
        guard let item = store.item(id), let tab = item.tab else { return menu }
        if m.pinned {
            add(menu, "Unpin Tab") { store.unpinTab(id) }
        } else {
            add(menu, "Pin Tab") { store.pinTab(id) }
        }
        if store.isFavorite(id) {
            add(menu, "Remove from Favorites") { store.removeFromFavorites(id) }
        } else {
            add(menu, "Add to Favorites") { store.addToFavorites(id) }
        }
        menu.addItem(.separator())
        add(menu, "Rename…") { ui.renamingID = id }
        if item.title != nil { add(menu, "Use Page Title") { store.rename(id, to: nil) } }
        add(menu, "Duplicate") { _ = store.duplicateTab(id) }
        add(menu, "Copy Link") { copy(tab.url) }
        add(menu, tab.muted ? "Unmute" : "Mute") {
            store.setMuted(id, !tab.muted)
            actions.performAction("muteTab:\(id)")
        }
        if m.pinned {
            menu.addItem(.separator())
            if m.navigatedAway { add(menu, "Back to Pinned Page") { actions.resetPinnedTab(id) } }
            add(menu, "Make This the Pinned Page") { store.setPinnedHomeToCurrent(id) }
        }
        menu.addItem(.separator())
        let spaces = submenu(menu, "Move to Space")
        let current = store.spaceID(ofItem: id)
        for s in store.orderedSpaces {
            add(spaces, "\(s.emoji) \(s.title)", enabled: s.id != current) { store.moveTab(id, toSpace: s.id) }
        }
        folderItems(menu, [id], list: list)
        menu.addItem(.separator())
        if m.pinned {
            if store.isSelected(id, window: ui.windowID) || ui.loadedTabIDs.contains(id) {
                add(menu, "Close and Keep Pinned") { actions.closeTab(id) }
            }
            add(menu, "Archive Tab") { store.archiveTab(id, reason: .manual) }
        } else {
            add(menu, "Archive") { actions.closeTab(id) }
        }
        return menu
    }

    /// Move to Folder / New Folder for this tab, or for every picked tab.
    private static func folderItems(_ menu: NSMenu, _ ids: [UUID], list: SpaceListView) {
        let store = list.store, ui = list.ui
        let folders = store.children(of: store.focusedSpace(window: ui.windowID).pinnedContainerID).filter { $0.isFolder && !$0.isLiveFolder }
        if !folders.isEmpty {
            let sub = submenu(menu, ids.count > 1 ? "Move \(ids.count) Tabs to Folder" : "Move to Folder")
            for f in folders {
                add(sub, f.title ?? "Folder", enabled: !ids.allSatisfy { store.item($0)?.parentID == f.id }) {
                    store.moveItems(ids, to: f.id, index: nil)
                }
            }
        }
        add(menu, ids.count > 1 ? "New Folder with \(ids.count) Tabs" : "New Folder with Tab") {
            ui.renamingID = store.createFolder(with: ids).id
        }
    }

    // MARK: Folders

    private static func iconColor(_ menu: NSMenu, _ item: SidebarItem, list: SpaceListView) {
        let sub = submenu(menu, "Icon Color")
        let id = item.id
        for (title, style) in [("Auto", FolderIconStyle?.none), ("White", .white), ("Black", .black)] {
            add(sub, title, on: item.folderIcon == style) { list.store.setFolderIcon(style, for: id) }
        }
    }

    static func folder(_ item: SidebarItem, list: SpaceListView) -> NSMenu {
        let store = list.store, ui = list.ui
        let id = item.id
        let menu = menu()
        add(menu, "Rename…") { ui.renamingID = id }
        add(menu, "New Folder Inside") {
            let f = store.createFolder(named: "New Folder", in: id, index: 0)
            store.setExpanded(id, true)
            ui.renamingID = f.id
        }
        iconColor(menu, item, list: list)
        menu.addItem(.separator())
        add(menu, "Delete Folder (archives tabs)") { store.deleteFolder(id) }
        return menu
    }

    /// The live folder's menu (Arc: SidebarMenu+ListContextMenu liveFolderContextMenu).
    static func liveFolder(_ item: SidebarItem, list: SpaceListView) -> NSMenu {
        let store = list.store, ui = list.ui, actions = list.actions
        let manager = LiveFolderManager.shared
        let id = item.id
        let live = item.liveFolder ?? LiveFolderData()
        let menu = menu()
        note(menu, manager.refreshing.contains(id) ? "Updating…" : LiveFolderText.lastUpdate(live))
        add(menu, "Refresh") { manager.refresh(id) }
        menu.addItem(.separator())
        for (title, attribute) in [("My Pull Requests", GitHubLiveFilter.Attributes.authored),
                                   ("Review Requests", .reviewRequests),
                                   ("Team Review Requests", .teamReviewRequests)] {
            let on = live.filter.attributes.contains(attribute)
            add(menu, title, on: on) {
                store.updateLiveFolder(id) { l in
                    if on { l.filter.attributes.remove(attribute) } else { l.filter.attributes.insert(attribute) }
                }
                manager.refresh(id, force: true)
            }
        }
        let repos = manager.repositories[id] ?? live.filter.hiddenRepositories
        if !repos.isEmpty {
            let sub = submenu(menu, "Repositories")
            note(sub, "This list is generated based on your currently active pull requests.")
            sub.addItem(.separator())
            for repo in repos {
                let shown = !live.filter.hiddenRepositories.contains(repo)
                add(sub, repo, on: shown) {
                    store.updateLiveFolder(id) { l in
                        l.filter.hiddenRepositories.removeAll { $0 == repo }
                        if shown { l.filter.hiddenRepositories.append(repo) }
                    }
                    manager.refresh(id, force: true)
                }
            }
        }
        if live.lastError == .notSignedIn {
            menu.addItem(.separator())
            add(menu, "Sign In to GitHub…") { actions.openURL(live.signInURL) }
        } else if !live.ssoOrganizations.isEmpty {
            menu.addItem(.separator())
            note(menu, "SSO ensures all of your organizations’ PRs appear")
            for org in live.ssoOrganizations {
                add(menu, "Sign In to \(org) with SSO…") { actions.openURL("https://github.com/orgs/\(org)/sso") }
            }
        }
        menu.addItem(.separator())
        add(menu, "Rename…") { ui.renamingID = id }
        iconColor(menu, item, list: list)
        add(menu, "Copy All Links as Markdown", enabled: !item.children.isEmpty) {
            let lines = store.children(of: id).compactMap { c in c.tab.map { "- [\(c.displayTitle)](\($0.liveItemURL ?? $0.url))" } }
            copy(lines.joined(separator: "\n"))
        }
        menu.addItem(.separator())
        add(menu, "Delete Live Folder") { confirmDeleteLiveFolder(item, store: store) }
        return menu
    }

    /// Arc asks first ("Delete your %@ Live Folder?") and says how to get it back.
    static func confirmDeleteLiveFolder(_ item: SidebarItem, store: SidebarStore) {
        let alert = NSAlert()
        alert.messageText = "Delete your \(item.title ?? "Pull Requests") Live Folder?"
        alert.informativeText = "You can add it again with New GitHub Live Folder in the sidebar’s menu or the command bar."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        let id = item.id
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window) { if $0 == .alertFirstButtonReturn { store.deleteFolder(id) } }
        } else if alert.runModal() == .alertFirstButtonReturn {
            store.deleteFolder(id)
        }
    }

    // MARK: Splits

    /// Arc 1.171's split menu, item for item where Cra has the feature (no Share or Change Icon).
    /// It is pinned by dragging it into Pinned or with Pin Tab (⌘D), not from here.
    static func split(_ m: SplitRowModel, list: SpaceListView) -> NSMenu {
        split(m.id, panes: m.cells.map { ($0.id, $0.title) }, open: m.selected, store: list.store, ui: list.ui, actions: list.actions)
    }

    /// A split's menu, from its sidebar row or its favorite tile.
    static func split(_ id: UUID, panes: [(id: UUID, title: String)], open: Bool, store: SidebarStore, ui: SidebarUIState,
                      actions: SidebarActions, leading: (NSMenu) -> Void = { _ in }) -> NSMenu {
        let menu = menu()
        leading(menu)
        let children = panes.map(\.id)
        add(menu, "Separate All Tabs") { store.separateAll(id) }
        // Arc greys it out while the split is closed (no pane to add next to).
        add(menu, "Add Tab…", enabled: open && children.count < 4) {
            if let first = children.first {
                actions.focusPane(first)
                actions.performAction("addSplitView")
            }
        }
        add(menu, store.item(id)?.split?.orientation == .vertical ? "Convert to Horizontal Split View" : "Convert to Vertical Split View") {
            store.flipSplitOrientation(id)
        }
        menu.addItem(.separator())
        note(menu, "Tab Options")
        for c in panes {
            paneItems(submenu(menu, c.title), c.id, store: store, actions: actions)
        }
        menu.addItem(.separator())
        add(menu, "Rename…") { ui.renamingID = id }
        menu.addItem(.separator())
        let spaces = submenu(menu, "Move to")
        let current = store.spaceID(ofItem: id)
        for s in store.orderedSpaces {
            add(spaces, "\(s.emoji) \(s.title)", on: s.id == current) { if s.id != current { store.moveTab(id, toSpace: s.id) } }
        }
        menu.addItem(.separator())
        add(menu, "Archive Item") { for c in children { store.archiveTab(c, reason: .manual) } }
        return menu
    }

    /// One pane's submenu under "Tab Options" (Arc: childItem(id, …)).
    private static func paneItems(_ menu: NSMenu, _ id: UUID, store: SidebarStore, actions: SidebarActions) {
        guard let tab = store.item(id)?.tab else { return }
        add(menu, "Separate from Split View") { store.separateFromSplit(id) }
        menu.addItem(.separator())
        add(menu, tab.muted ? "Unmute" : "Mute") {
            store.setMuted(id, !tab.muted)
            actions.performAction("muteTab:\(id)")
        }
        add(menu, "Copy Link") { copy(tab.url) }
        add(menu, "Copy Link as Markdown") { copy("[\(store.item(id)?.displayTitle ?? tab.savedTitle)](\(tab.url))") }
        menu.addItem(.separator())
        add(menu, "Archive Item") { store.archiveTab(id, reason: .manual) }
    }

    // MARK: The list

    static func spaceList(_ list: SpaceListView) -> NSMenu {
        let store = list.store, actions = list.actions
        let space = list.spaceID
        let menu = menu()
        add(menu, "New Tab") { actions.openCommandBar(.newTab) }
        add(menu, "New Folder") { actions.performAction("newFolder") }
        add(menu, "New GitHub Live Folder", enabled: store.liveFolder(.github, inSpace: space) == nil) {
            actions.performAction("newGitHubLiveFolder")
        }
        menu.addItem(.separator())
        if let s = store.space(space), !store.children(of: s.todayContainerID).isEmpty {
            add(menu, "Clear Today") { store.clearToday(space) }
        }
        if let s = store.space(space) {
            add(menu, "Edit Space…") { actions.editSpace(s) }
        }
        // With the header hidden (one space), its menu items live here.
        if store.hidesSpaceHeader(space) {
            add(menu, "Show Space Header") { store.settings.showSpaceHeaderOnSingleSpace = true }
        }
        return menu
    }
}
