import AppKit
import CraCEF
import UniformTypeIdentifiers

/// The menu bar's Extensions menu, after Dia 1.54 (Extensions, between History and
/// Window): one row per extension with its 16 pt icon, in plain ordinal name order
/// (Dia lists "dataslayer" after "Vercel"), then Add Extension…, Manage Extensions…
/// and Pin Extensions…. Rebuilt each time it opens, so new folders show up at once.
@MainActor
final class ExtensionsMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private unowned let app: AppDelegate

    init(app: AppDelegate) { self.app = app }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Extensions")
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let store = ExtensionStore.shared
        store.reload()
        let entries = app.main.extensionEntries.sorted { $0.name < $1.name }
        let profile = app.main.profileDirectoryName, tab = app.main.selectedTabID
        for e in entries {
            let item = NSMenuItem(title: e.name, action: #selector(runExtension(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = e.extensionID
            // Arc lists the manifest's action icon here, not the one the extension set (#106).
            item.image = Self.menuIcon(e.icon)
            menu.addItem(item)
        }
        if !entries.isEmpty { menu.addItem(.separator()) }

        let add = NSMenuItem(title: "Add Extension…", action: #selector(addExtension), keyEquivalent: "")
        add.target = self
        add.image = NSImage(systemSymbolName: "plus", accessibilityDescription: nil)
        menu.addItem(add)
        let manage = NSMenuItem(title: "Manage Extensions…", action: #selector(manageExtensions), keyEquivalent: "")
        manage.target = self
        menu.addItem(manage)

        // Dia's checklist; the Site Control Center's tiles pin the same list (Arc).
        let pin = NSMenuItem(title: "Pin Extensions…", action: nil, keyEquivalent: "")
        let pinMenu = NSMenu(title: "Pin Extensions")
        for e in entries {
            let item = NSMenuItem(title: e.name, action: #selector(togglePin(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [e.extensionID, profile]
            item.image = Self.menuIcon(e.icon)
            item.state = store.isPinned(e.extensionID, inProfile: profile) ? .on : .off
            pinMenu.addItem(item)
        }
        pin.submenu = pinMenu
        pin.isEnabled = !entries.isEmpty
        menu.addItem(pin)

        let icons = NSMenuItem(title: "Toolbar Icons", action: nil, keyEquivalent: "")
        let iconsMenu = NSMenu(title: "Toolbar Icons")
        for e in entries {
            let item = NSMenuItem(title: e.name, action: nil, keyEquivalent: "")
            item.image = Self.menuIcon(store.toolbarIcon(for: e, profile: profile, tab: tab))
            item.submenu = Self.iconMenu(for: e)
            iconsMenu.addItem(item)
        }
        icons.submenu = iconsMenu
        icons.isEnabled = !entries.isEmpty
        menu.addItem(icons)
    }

    /// How one extension's toolbar button draws: its own icon, monochrome, a symbol or an
    /// image file (GitHub #9). Also the pinned button's context menu.
    /// A pinned extension's right-click menu in the toolbar: Arc's rows (CraCore ExtensionActionMenu,
    /// #695), Cra's icon choices under Icon. `profile`: the Chromium profile folder the bar lists its pins
    /// for; `open` opens a page in a new tab of the window.
    static func actionMenu(for e: ExtensionStore.Entry, profile: String, open: @escaping (String) -> Void) -> NSMenu {
        let id = e.extensionID
        let menu = NSMenu(title: e.name)
        let rows = ExtensionActionMenu.rows(name: e.name, hasOptions: e.optionsPath != nil, fromWebStore: e.managedByChrome)
        for row in rows {
            switch row {
            case .separator: menu.addItem(.separator())
            case .name(_, let opensWebStore):
                let item = BlockMenuItem(title: row.title) { open(ExtensionActionMenu.webStorePage(id: id)) }
                item.image = menuIcon(e.icon)
                if !opensWebStore { item.action = nil }
                menu.addItem(item)
            case .ownItems:
                // The extension's own rows (chrome.contextMenus for its action), from the engine (#695).
                guard let page = Self.page(), page.responds(to: #selector(CraBrowser.extensionActionMenuItems(_:))) else { break }
                let own = Self.ownMenuItems(page.extensionActionMenuItems(id), extension: id, page: page)
                guard !own.isEmpty else { break }
                own.forEach(menu.addItem)
                menu.addItem(.separator())
            case .siteAccess:
                // The site access line for the page, from the engine (#695).
                guard let page = Self.page(), page.responds(to: #selector(CraBrowser.extensionSiteAccess(_:))),
                      let access = ExtensionSiteAccess(engine: page.extensionSiteAccess(id)) else { break }
                menu.addItem(Self.siteAccessItem(access, extension: id, page: page, open: open))
                menu.addItem(.separator())
            case .remove:
                menu.addItem(BlockMenuItem(title: row.title) { Self.confirmRemove(e, profile: profile) })
            case .options:
                if let path = e.optionsPath { menu.addItem(BlockMenuItem(title: row.title) { open(ExtensionActionMenu.optionsPage(id: id, path: path)) }) }
            case .unpin:
                menu.addItem(BlockMenuItem(title: row.title) { ExtensionStore.shared.setPinned(id, false, inProfile: profile) })
            case .manage:
                menu.addItem(BlockMenuItem(title: row.title) { open(ExtensionActionMenu.managePage(id: id)) })
            case .webPermissions:
                menu.addItem(BlockMenuItem(title: row.title) { open(ExtensionActionMenu.webPermissionsPage(id: id)) })
            case .icon:
                let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                item.submenu = iconMenu(for: e)
                menu.addItem(item)
            }
        }
        return menu
    }

    /// The page the menu acts on: the browser window's current page.
    @MainActor static func page() -> CraBrowser? { (NSApp.delegate as? AppDelegate)?.main?.currentBrowser }

    /// The engine's rows (`extensionActionMenuItems`) as menu items: a click runs the row for the page (#695).
    static func ownMenuItems(_ rows: [[String: Any]], extension id: String, page: CraBrowser) -> [NSMenuItem] {
        rows.map { row in
            let kind = row["kind"] as? String ?? "normal"
            guard kind != "separator" else { return .separator() }
            let title = row["title"] as? String ?? ""
            let itemID = row["id"] as? String ?? ""
            let children = row["children"] as? [[String: Any]] ?? []
            if !children.isEmpty {
                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                let sub = NSMenu(title: title)
                ownMenuItems(children, extension: id, page: page).forEach(sub.addItem)
                item.submenu = sub
                return item
            }
            let item = BlockMenuItem(title: title) { [weak page] in _ = page?.runExtensionMenuItem(itemID, extension: id) }
            if (row["enabled"] as? Bool) == false { item.action = nil }
            if (row["checked"] as? Bool) == true { item.state = .on }
            return item
        }
    }

    /// "Can't Read or Change Site's Data", greyed out, or the submenu with the three choices and Learn More (#695).
    static func siteAccessItem(_ access: ExtensionSiteAccess, extension id: String, page: CraBrowser, open: @escaping (String) -> Void) -> NSMenuItem {
        let item = NSMenuItem(title: access.title, action: nil, keyEquivalent: "")
        guard !access.rows.isEmpty else { return item }
        let sub = NSMenu(title: access.title)
        for row in access.rows {
            if row.isSeparator { sub.addItem(.separator()); continue }
            let choice = row.choice
            let entry = BlockMenuItem(title: row.title) { [weak page] in
                guard let choice else { open(ExtensionSiteAccess.learnMorePage); return }
                let done = page?.setExtensionSiteAccess(choice.rawValue, extension: id) == true
                CraLog.note("extension site access \(id.prefix(8)): \(choice.rawValue) \(done ? "set" : "refused")")
            }
            if !row.enabled { entry.action = nil }
            if row.checked { entry.state = .on }
            sub.addItem(entry)
        }
        item.submenu = sub
        return item
    }

    /// Remove from Cra: asked first, as Chrome's "Remove from Chrome…" does (#695). `profile`: the profile folder the
    /// menu is for.
    static func confirmRemove(_ e: ExtensionStore.Entry, profile: String) {
        let dialog = AppDialog(title: "Remove “\(e.name)”?",
                               message: ExtensionRemoval.message(isShared: ExtensionStore.shared.shares.isShared(e.extensionID),
                                                                 isCraCopy: !e.managedByChrome, profileCount: e.profiles?.count),
                               actions: [DialogAction("Remove", role: .destructive), .cancel])
        let remove = { (r: NSApplication.ModalResponse) in if r == .alertFirstButtonReturn { Self.remove(e, profile: profile) } }
        if let window = AppDialog.parentWindow { dialog.present(over: window, completion: remove) } else { remove(dialog.runModal()) }
    }

    /// Chromium uninstalls it from the profile the menu is for (`profile`, a profile folder), not the window's current
    /// page, which can be another profile's: one without it crashed Cra (crash-extension-remove-other-profile). A copy
    /// Cra loads itself from its folder goes too, or it would load again at the next launch.
    @MainActor static func remove(_ e: ExtensionStore.Entry, profile: String) {
        // Shared (discussion #595): from every profile, as Settings removes it. Chrome keeps it otherwise.
        if ExtensionStore.shared.shares.isShared(e.extensionID) {
            ExtensionStore.shared.removeShared(e)
            CraLog.note("extension removed \(e.extensionID.prefix(8)): shared, from every profile")
            return
        }
        var uninstalled = false
        if let folder = ExtensionRemoval.engineProfile(menuProfile: profile, installedIn: e.profiles) {
            if CraCEFRuntime.responds(to: #selector(CraCEFRuntime.uninstallExtension(_:profilePath:))) {
                uninstalled = CraCEFRuntime.uninstallExtension(e.extensionID, profilePath: ExtensionStore.profilePath(folder))
            } else if let page = page(), page.responds(to: #selector(CraBrowser.uninstallExtension(_:))) {
                uninstalled = page.uninstallExtension(e.extensionID)   // CEF: one profile
            }
        }
        if !e.managedByChrome { ExtensionStore.shared.remove(e) }
        CraLog.note("extension removed \(e.extensionID.prefix(8)): engine=\(uninstalled ? 1 : 0) folder=\(e.managedByChrome ? 0 : 1) profile=\(profile)")
    }

    static func iconMenu(for e: ExtensionStore.Entry) -> NSMenu {
        let store = ExtensionStore.shared
        let id = e.extensionID
        let style = store.iconStyle(id)
        let menu = NSMenu(title: e.name)

        let original = BlockMenuItem(title: "Original Icon") { store.setIconStyle(id, .init()) }
        original.state = style == .init() ? .on : .off
        menu.addItem(original)
        let mono = BlockMenuItem(title: "Monochrome") {
            var s = store.iconStyle(id)
            s.monochrome.toggle()
            s.symbol = nil
            store.setIconStyle(id, s)
        }
        mono.state = style.monochrome && style.symbol == nil ? .on : .off
        menu.addItem(mono)
        menu.addItem(.separator())

        let symbols = NSMenuItem(title: "Symbol", action: nil, keyEquivalent: "")
        let symbolMenu = NSMenu(title: "Symbol")
        for name in ExtensionStore.iconSymbols {
            let item = BlockMenuItem(title: name) {
                var s = store.iconStyle(id)
                s.symbol = name
                s.imageFile = nil
                store.setIconStyle(id, s)
            }
            item.image = NSImage(systemSymbolName: name, accessibilityDescription: name)
            item.state = style.symbol == name ? .on : .off
            symbolMenu.addItem(item)
        }
        symbols.submenu = symbolMenu
        symbols.state = style.symbol != nil ? .on : .off
        menu.addItem(symbols)
        let choose = BlockMenuItem(title: "Choose Image…") {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.message = "Choose an icon for \(e.name)'s toolbar button"
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do { try store.setCustomIcon(id, from: url) } catch { AppDialog(error: error).runModal() }
        }
        choose.state = style.imageFile != nil ? .on : .off
        menu.addItem(choose)
        return menu
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        // Extensions only run in Chrome-style pages.
        switch item.action {
        case #selector(runExtension(_:)), #selector(manageExtensions): return app.store.settings.chromeEngine
        default: return true
        }
    }

    private static func menuIcon(_ image: NSImage?) -> NSImage? {
        guard let image else { return NSImage(systemSymbolName: "puzzlepiece.extension", accessibilityDescription: nil) }
        let sized = image.copy() as! NSImage
        sized.size = NSSize(width: 16, height: 16)
        return sized
    }

    // MARK: Actions

    @objc private func runExtension(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        runAction(id: id)
    }

    /// Dia runs the extension's toolbar action on the current tab (Chrome's popup, hung
    /// under the toolbar's right end); see MainWindowController.runExtensionAction.
    func runAction(id: String) {
        app.main.runExtensionAction(id)
    }

    @objc private func addExtension() { openTab("https://chromewebstore.google.com/category/extensions") }

    @objc private func manageExtensions() { openTab("chrome://extensions") }

    @objc private func togglePin(_ sender: NSMenuItem) {
        // The profile of the space the menu was opened in: the pins are that profile's (GitHub #107).
        guard let pair = sender.representedObject as? [String], pair.count == 2 else { return }
        ExtensionStore.shared.setPinned(pair[0], !ExtensionStore.shared.isPinned(pair[0], inProfile: pair[1]), inProfile: pair[1])
    }

    private func openTab(_ url: String) {
        app.store.createTab(url: url, select: true)
        app.main.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
