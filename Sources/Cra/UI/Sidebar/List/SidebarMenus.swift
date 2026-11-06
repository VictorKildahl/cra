import AppKit

/// The tab list's context menus (the SwiftUI rows' .contextMenu, item for item).
@MainActor
enum SidebarMenus {
    private static func menu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        return m
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, enabled: Bool = true, on: Bool? = nil, _ run: @escaping () -> Void) -> NSMenuItem {
        MenuItems.add(menu, title, enabled: enabled, on: on, run)
    }

    /// A row for a KeyBindings command, with its shortcut (MenuItems.add(_:action:)).
    @discardableResult
    private static func add(_ menu: NSMenu, action id: String, _ title: String? = nil, enabled: Bool = true, on: Bool? = nil,
                            _ run: @escaping () -> Void) -> NSMenuItem {
        MenuItems.add(menu, action: id, title: title, enabled: enabled, on: on, run)
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

    // MARK: Tab groups

    /// Arc's Tab Group Context Menu: one item, "Remove header" (the tabs stay, loose).
    static func tabGroup(_ id: UUID, list: SpaceListView) -> NSMenu {
        let menu = menu()
        add(menu, "Remove header") { list.store.removeGroupHeader(id) }
        return menu
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
            add(menu, action: "pinTab", "Unpin Tab") { store.unpinTab(id) }
        } else {
            add(menu, action: "pinTab", "Pin Tab") { store.pinTab(id) }
        }
        if store.isFavorite(id) {
            add(menu, action: "favoriteTab", "Remove from Favorites") { store.removeFromFavorites(id) }
        } else {
            add(menu, action: "favoriteTab", "Add to Favorites") { store.addToFavorites(id) }
        }
        menu.addItem(.separator())
        add(menu, action: "renameTab", "Rename…") { ui.renamingID = id }
        if item.title != nil { add(menu, "Use Page Title") { store.rename(id, to: nil) } }
        if m.pinned, tab.liveItemURL == nil { pinnedURLItems(menu, id, navigatedAway: m.navigatedAway, store: store, actions: actions) }
        add(menu, action: "duplicateTab", "Duplicate") { _ = store.duplicateTab(id) }
        add(menu, action: "copyURL", "Copy Link") { copy(tab.url) }
        add(menu, action: "muteTab", tab.muted ? "Unmute" : "Mute") {
            store.setMuted(id, !tab.muted)
            actions.performAction("muteTab:\(id)")
        }
        if m.pinned, m.navigatedAway {
            menu.addItem(.separator())
            add(menu, action: "resetTab", "Back to Pinned Page") { actions.resetPinnedTab(id) }
        }
        menu.addItem(.separator())
        let spaces = submenu(menu, "Move to Space")
        for s in store.orderedSpaces {
            add(spaces, "\(s.emoji) \(s.title)", enabled: !store.isInSpace(id, s.id)) { store.moveTab(id, toSpace: s.id, window: ui.windowID) }
        }
        folderItems(menu, [id], list: list)
        menu.addItem(.separator())
        if m.pinned {
            if store.isSelected(id, window: ui.windowID) || ui.loadedTabIDs.contains(id) {
                add(menu, action: "closeTab", "Close and Keep Pinned") { actions.closeTab(id) }
            }
            add(menu, "Archive Tab") { store.archiveTab(id, reason: .manual) }
        } else {
            add(menu, action: "closeTab", "Archive") { actions.closeTab(id) }
        }
        return menu
    }

    /// The pinned URL's items on pinned tabs and favorites (#54), beside Rename… since they edit
    /// the same item. Arc puts them in an Edit Pinned Page submenu; Cra lists them flat, as
    /// Anoninz suggested on PR #55. Replace is greyed out while the tab is on its pinned page.
    static func pinnedURLItems(_ menu: NSMenu, _ id: UUID, navigatedAway: Bool, store: SidebarStore, actions: SidebarActions) {
        add(menu, "Edit Pinned URL…") { actions.editPinnedURL(id) }
        add(menu, "Replace Pinned URL with Current", enabled: navigatedAway) { store.setPinnedHomeToCurrent(id) }
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
        if let category = item.liveFolderCategory, let root = store.liveFolder(containing: id) {
            note(menu, "Managed by \(root.displayTitle)")
            add(menu, "Refresh", enabled: !LiveFolderManager.shared.refreshing.contains(root.id)) {
                LiveFolderManager.shared.refresh(root.id, manual: true)
            }
            add(menu, "Hide This Category") {
                store.updateLiveFolder(root.id) { $0.filter.attributes.remove(category.attribute) }
                store.reapplyLiveResults(root.id)
                LiveFolderManager.shared.refresh(root.id, force: true)
            }
            return menu
        }
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
        if live.source == .gitlab {
            if let server = live.serverURL { note(menu, server) }
            if let status = manager.gitLabStatus[id] { note(menu, status) }
        }
        add(menu, "Refresh", enabled: !manager.refreshing.contains(id)) { manager.refresh(id, manual: true) }
        menu.addItem(.separator())
        let filters: [(String, GitHubLiveFilter.Attributes)] = live.source == .gitlab
            ? GitLabLiveCategory.allCases.map { ($0.title, $0.attribute) }
            : [("My Pull Requests", .authored), ("Review Requests", .reviewRequests), ("Team Review Requests", .teamReviewRequests)]
        let filterMenu = live.source == .gitlab ? submenu(menu, "Show Merge Requests") : menu
        for (title, attribute) in filters {
            let on = live.filter.attributes.contains(attribute)
            add(filterMenu, title, on: on) {
                store.updateLiveFolder(id) { l in
                    if on { l.filter.attributes.remove(attribute) } else { l.filter.attributes.insert(attribute) }
                }
                store.reapplyLiveResults(id)
                manager.refresh(id, force: true)
            }
        }
        if live.source == .gitlab {
            add(menu, "Separate by Category", on: live.separateByCategory == true) {
                store.updateLiveFolder(id) { $0.separateByCategory = $0.separateByCategory != true }
                store.reapplyLiveResults(id)
                if store.item(id)?.liveFolder?.cachedResults == nil { manager.refresh(id, force: true) }
            }
        }
        add(menu, "Restore Hidden", enabled: !live.hiddenItems.isEmpty) {
            store.resetHiddenLiveItems(id)
            manager.refresh(id, force: true, manual: true)
        }
        let repos = manager.repositories[id] ?? live.filter.hiddenRepositories
        if !repos.isEmpty {
            let sub = submenu(menu, live.source == .gitlab ? "Projects" : "Repositories")
            note(sub, live.source == .gitlab ? "Projects with active merge requests." : "This list is generated based on your currently active pull requests.")
            sub.addItem(.separator())
            for repo in repos {
                let shown = !live.filter.hiddenRepositories.contains(repo)
                add(sub, repo, on: shown) {
                    store.updateLiveFolder(id) { l in
                        l.filter.hiddenRepositories.removeAll { $0 == repo }
                        if shown { l.filter.hiddenRepositories.append(repo) }
                    }
                    store.reapplyLiveResults(id)
                    manager.refresh(id, force: true)
                }
            }
        }
        if live.lastError == .notSignedIn {
            menu.addItem(.separator())
            add(menu, "Sign In to \(live.source.title)…") { actions.openURL(live.signInURL) }
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
            let lines = store.tabs(under: id).compactMap { c in c.tab.map { "- [\(c.displayTitle)](\($0.liveItemURL ?? $0.url))" } }
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
        alert.informativeText = item.liveFolder?.source == .gitlab
            ? "You can add it again with New GitLab Live Folder in the sidebar’s menu."
            : "You can add it again with New GitHub Live Folder in the sidebar’s menu or the command bar."
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

    private static func newGitLabFolder(_ list: SpaceListView) {
        let alert = NSAlert()
        alert.messageText = "New GitLab Live Folder"
        alert.informativeText = "Enter your GitLab server URL, or leave it blank for GitLab.com. Sign in using this space’s browser profile, then refresh the folder."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        field.placeholderString = "https://gitlab.com"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        let space = list.spaceID
        let create: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            let address = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let server = GitLabLiveClient.serverURL(address.isEmpty ? "https://gitlab.com" : address) else {
                let error = NSAlert()
                error.messageText = "Invalid GitLab server URL"
                error.informativeText = "Enter an HTTP or HTTPS server URL without credentials, a query or a fragment."
                error.runModal()
                return
            }
            if let existing = list.store.liveFolder(.gitlab, inSpace: space, serverURL: server) {
                let duplicate = NSAlert()
                duplicate.messageText = "This GitLab server already has a live folder"
                duplicate.informativeText = "Use \(existing.displayTitle) to change its filters or category layout."
                duplicate.runModal()
                return
            }
            guard let folder = list.store.createLiveFolder(.gitlab, inSpace: space, serverURL: server) else { return }
            LiveFolderManager.shared.refresh(folder.id, force: true)
        }
        if let window = list.window { alert.beginSheetModal(for: window, completionHandler: create) }
        else { create(alert.runModal()) }
    }

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
        add(menu, action: "addSplitView", "Add Tab…", enabled: open && children.count < 4) {
            if let first = children.first {
                actions.focusPane(first)
                actions.performAction("addSplitView")
            }
        }
        add(menu, action: "flipSplitOrientation",
            store.item(id)?.split?.orientation == .vertical ? "Convert to Horizontal Split View" : "Convert to Vertical Split View") {
            store.flipSplitOrientation(id)
        }
        menu.addItem(.separator())
        note(menu, "Tab Options")
        for c in panes {
            paneItems(submenu(menu, c.title), c.id, store: store, actions: actions)
        }
        menu.addItem(.separator())
        // Arc's way back to the panes from a renamed split.
        if store.item(id)?.title != nil { add(menu, "Reset Name and Icon") { store.rename(id, to: nil) } }
        add(menu, "Rename…") { ui.renamingID = id }
        menu.addItem(.separator())
        let spaces = submenu(menu, "Move to")
        for s in store.orderedSpaces {
            let current = store.isInSpace(id, s.id)
            add(spaces, "\(s.emoji) \(s.title)", on: current) { if !current { store.moveTab(id, toSpace: s.id, window: ui.windowID) } }
        }
        menu.addItem(.separator())
        add(menu, "Archive Item") { for c in children { store.archiveTab(c, reason: .manual) } }
        return menu
    }

    /// One pane's submenu under "Tab Options" (Arc: childItem(id, …)).
    private static func paneItems(_ menu: NSMenu, _ id: UUID, store: SidebarStore, actions: SidebarActions) {
        guard let tab = store.item(id)?.tab else { return }
        // No shortcut glyphs: every pane has this submenu, and the keys act on the focused one.
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
        // Arc's sidebar menu starts with the space's look, as the header's does (#170).
        if let s = store.space(space) {
            if let header = list.header, !store.hidesSpaceHeader(space) {
                add(menu, "Change Space Icon…") { [weak header] in if let header { actions.changeSpaceIcon(s, header) } }
                add(menu, "Rename Space…") { [weak header] in header?.beginRename() }
            }
            add(menu, "Edit Theme Color…") { actions.editSpaceTheme(s) }
            menu.addItem(.separator())
        }
        add(menu, action: "newTab", "New Tab") { actions.openCommandBar(.newTab) }
        add(menu, action: "newFolder") { actions.performAction("newFolder") }
        add(menu, action: "newGitHubLiveFolder", enabled: store.liveFolder(.github, inSpace: space) == nil) {
            actions.performAction("newGitHubLiveFolder")
        }
        add(menu, "New GitLab Live Folder…", enabled: !store.isStandalone(space: space)) {
            newGitLabFolder(list)
        }
        menu.addItem(.separator())
        if let s = store.space(space), !store.children(of: s.todayContainerID).isEmpty {
            add(menu, action: "clearToday") { store.clearToday(space) }
        }
        if let s = store.space(space) {
            add(menu, action: "editSpace") { actions.editSpace(s) }
        }
        // With the header hidden (one space), its menu items live here.
        if store.hidesSpaceHeader(space) {
            add(menu, "Show Space Header") { store.settings.showSpaceHeaderOnSingleSpace = true }
        }
        return menu
    }
}
