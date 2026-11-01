import Foundation

// Legacy preference migration is unrelated to editing saved URLs; don't read an installed Arc profile.
enum ArcImporter { static var showsToolbar: Bool? { nil } }

@main
struct PinnedURLTests {
    @MainActor
    static func main() {
        precondition(ProcessInfo.processInfo.environment["CRA_DATA_DIR"] != nil)
        let store = SidebarStore()
        let folder = store.createFolder(named: "Links", in: store.focusedSpace.pinnedContainerID)
        let pinned = store.createTab(url: "https://example.com/old", title: "Old page", pinned: true,
                                     select: false, parent: folder.id)
        store.rename(pinned.id, to: "My link")
        store.setCustomIcon("custom-test", for: pinned.id)
        store.setTileColor("#123456", for: [pinned.id])
        let before = store.item(pinned.id)!
        let order = store.children(of: folder.id).map(\.id)
        precondition(store.setPinnedURL(pinned.id, to: "https://example.org/new?q=1#section"))
        let after = store.item(pinned.id)!
        precondition(after.tab?.url == "https://example.org/new?q=1#section")
        precondition(after.tab?.savedURL == after.tab?.url)
        precondition(after.tab?.savedTitle == "")
        precondition(after.tab?.faviconKey == "example.org")
        precondition(after.id == before.id && after.title == before.title && after.parentID == before.parentID)
        precondition(after.tab?.customIconKey == before.tab?.customIconKey && after.tab?.tileColor == before.tab?.tileColor)
        precondition(store.children(of: folder.id).map(\.id) == order)

        store.updateTab(pinned.id, url: "https://example.org/redirected", title: "New page")
        precondition(store.item(pinned.id)?.tab?.savedURL == "https://example.org/new?q=1#section")
        precondition(store.resetPinnedTab(pinned.id) == "https://example.org/new?q=1#section")
        store.updateTab(pinned.id, url: "https://example.org/current")
        store.setPinnedHomeToCurrent(pinned.id)
        precondition(store.item(pinned.id)?.tab?.savedURL == "https://example.org/current")

        let favorite = store.createTab(url: "https://example.com/favorite", select: false)
        store.addToFavorites(favorite.id)
        precondition(store.setPinnedURL(favorite.id, to: "https://example.org/favorite"))
        precondition(store.isFavorite(favorite.id))
        let unchanged = store.item(favorite.id)!
        precondition(store.setPinnedURL(favorite.id, to: "https://example.org/favorite"))
        precondition(store.item(favorite.id) == unchanged)

        let today = store.createTab(url: "https://example.com/today", select: false)
        precondition(!store.setPinnedURL(today.id, to: "https://example.org/"))
        precondition(store.item(today.id)?.tab?.url == "https://example.com/today")
        precondition(!store.setPinnedURL(folder.id, to: "https://example.org/"))
        precondition(!store.setPinnedURL(UUID(), to: "https://example.org/"))
        let live = store.createTab(url: "https://github.com/example/repo/pull/1", pinned: true, select: false)
        store.items[live.id]?.data = .tab({
            var tab = store.item(live.id)!.tab!
            tab.liveItemURL = tab.url
            return tab
        }())
        precondition(!store.setPinnedURL(live.id, to: "https://example.org/"))

        store.saveAll()
        let restored = SidebarStore()
        for id in [pinned.id, favorite.id] {
            precondition(restored.item(id)?.tab == store.item(id)?.tab)
            precondition(restored.item(id)?.title == store.item(id)?.title)
            precondition(restored.item(id)?.parentID == store.item(id)?.parentID)
        }
        precondition(restored.children(of: folder.id).map(\.id) == order)
        print("PASS: pinned/favorite edits, metadata, navigation, Replace, guards, and persistence")
    }
}
