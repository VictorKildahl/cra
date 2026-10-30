import AppKit
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
        for e in entries {
            let item = NSMenuItem(title: e.name, action: #selector(runExtension(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = e.extensionID
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
            item.representedObject = e.extensionID
            item.image = Self.menuIcon(e.icon)
            item.state = store.isPinned(e.extensionID) ? .on : .off
            pinMenu.addItem(item)
        }
        pin.submenu = pinMenu
        pin.isEnabled = !entries.isEmpty
        menu.addItem(pin)

        let icons = NSMenuItem(title: "Toolbar Icons", action: nil, keyEquivalent: "")
        let iconsMenu = NSMenu(title: "Toolbar Icons")
        for e in entries {
            let item = NSMenuItem(title: e.name, action: nil, keyEquivalent: "")
            item.image = Self.menuIcon(store.toolbarIcon(for: e))
            item.submenu = Self.iconMenu(for: e)
            iconsMenu.addItem(item)
        }
        icons.submenu = iconsMenu
        icons.isEnabled = !entries.isEmpty
        menu.addItem(icons)
    }

    /// How one extension's toolbar button draws: its own icon, monochrome, a symbol or an
    /// image file (GitHub #9). Also the pinned button's context menu.
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
            do { try store.setCustomIcon(id, from: url) } catch { NSAlert(error: error).runModal() }
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
        guard let id = sender.representedObject as? String else { return }
        ExtensionStore.shared.setPinned(id, !ExtensionStore.shared.isPinned(id))
    }

    private func openTab(_ url: String) {
        app.store.createTab(url: url, select: true)
        app.main.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
