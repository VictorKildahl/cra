import AppKit
import CraCore

/// The menu bar's Spaces menu. Its Space list is rebuilt when the menu opens so adding,
/// deleting or reordering a Space is reflected without rebuilding the whole menu bar.
@MainActor
final class SpacesMenu: NSObject, NSMenuDelegate, NSMenuItemValidation {
    private unowned let app: AppDelegate

    init(app: AppDelegate) { self.app = app }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "Spaces")
        menu.delegate = self
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(boundItem("newSpace"))
        for id in ["editSpace", "changeProfile", "deleteSpace"] { menu.addItem(boundItem(id)) }
        menu.addItem(.separator())
        menu.addItem(boundItem("nextSpace"))
        menu.addItem(boundItem("previousSpace"))
        menu.addItem(.separator())

        let spaces = app.store.orderedSpaces
        let composition = SpacesMenuComposition(spaceIDs: spaces.map(\.id))
        for (row, space) in zip(composition.navigation, spaces) {
            menu.addItem(spaceItem(row, space: space))
        }
        menu.addItem(.separator())
        menu.addItem(boundItem("manageSpaces"))
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(navigateToSpace(_:)),
              let spaceID = item.representedObject as? UUID,
              let space = app.store.space(spaceID) else { return false }
        // Validation can follow an icon edit while the menu is open; fetch the current icon again.
        item.image = SpaceMenuIcon.image(for: space)
        return true
    }

    private func boundItem(_ id: String) -> NSMenuItem {
        guard let action = app.bindings.action(id) else { return NSMenuItem() }
        let item = NSMenuItem(title: action.name, action: #selector(AppDelegate.menuAction(_:)), keyEquivalent: "")
        item.representedObject = action.id
        item.target = app
        item.showShortcut(of: id)
        return item
    }

    private func spaceItem(_ row: SpacesMenuComposition.Row, space: Space) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: #selector(navigateToSpace(_:)), keyEquivalent: "")
        item.representedObject = row.spaceID
        item.target = self
        if let shortcutID = row.shortcutID { item.showShortcut(of: shortcutID) }
        let title = SpaceMenuTitle.plain(space.title)
        item.image = SpaceMenuIcon.image(for: space)
        SpaceMenuTitle.apply(title, to: item)
        // The menu bar follows the browser window in use. A Little Window leaves that window in
        // use; a standalone window has its own Space and therefore checks no normal Space row.
        if row.spaceID == app.store.focusedSpaceID(window: app.main.windowID) {
            item.state = .on
        }
        return item
    }

    @objc private func navigateToSpace(_ sender: NSMenuItem) {
        guard let spaceID = sender.representedObject as? UUID, app.store.space(spaceID) != nil else { return }
        app.store.focusSpace(spaceID)
    }
}
