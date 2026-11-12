import CraCore
import Foundation

/// The Mac's sidebar, as it arrives through sync. The Mac app writes `sidebar.json` into a `Cra`
/// folder in its iCloud Documents container (Settings ▸ General ▸ Sync there); the phone reads
/// it from the same container. `-CraSyncDir <folder>` points a test at a folder instead.
enum SyncedSidebar {
    enum State {
        case spaces(SidebarDocument)
        /// iCloud is there but the Mac has not synced anything into it yet.
        case nothingSynced
        /// No iCloud on this phone, or this build may not use it.
        case unavailable
    }

    private static var folder: URL? {
        if let path = LaunchOptions.value("CraSyncDir") {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(SettingsSync.folderName, isDirectory: true)
    }

    /// Reads the synced sidebar off the main thread (finding the iCloud container can take a moment).
    static func load(_ done: @escaping (State) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let state = read()
            DispatchQueue.main.async { done(state) }
        }
    }

    /// A made-up Mac sidebar for tests and screenshots: "Personal" with a pinned tab, a folder
    /// holding one, and a Today tab; and an empty "Play".
    private static func demo() -> SidebarDocument {
        var document = SidebarDocument.fresh()
        let space = document.spaces[0]
        var inbox = SidebarItem.tab("data:text/html,<title>Inbox</title><h1>Inbox</h1>", title: "Inbox", parent: space.pinnedContainerID)
        inbox.title = "Inbox"
        var work = SidebarItem.folder("Work", parent: space.pinnedContainerID)
        let docs = SidebarItem.tab("https://example.com/docs", title: "Docs", parent: work.id)
        work.children = [docs.id]
        let story = SidebarItem.tab("https://example.com/story", title: "A Story", parent: space.todayContainerID)
        document.items += [inbox, work, docs, story]
        for (container, children) in [(space.pinnedContainerID, [inbox.id, work.id]), (space.todayContainerID, [story.id])] {
            if let index = document.items.firstIndex(where: { $0.id == container }) { document.items[index].children = children }
        }
        let playID = UUID()
        let containers = [SidebarItem.container(.favorites(spaceID: playID)), .container(.pinned(spaceID: playID)), .container(.today(spaceID: playID))]
        document.items += containers
        document.spaces.append(Space(id: playID, title: "Play", emoji: "🎮", theme: SpaceTheme.presets[min(2, SpaceTheme.presets.count - 1)],
                                     favoritesContainerID: containers[0].id, pinnedContainerID: containers[1].id,
                                     todayContainerID: containers[2].id, createdAt: Date()))
        document.spaceOrder.append(playID)
        return document
    }

    private static func read() -> State {
        if LaunchOptions.value("CraSyncDir") == "demo" { return .spaces(demo()) }
        guard let folder else { return .unavailable }
        let file = folder.appendingPathComponent(SettingsSync.sidebarName)
        let manager = FileManager.default
        // Not downloaded yet: ask for it; the next look finds it.
        let placeholder = folder.appendingPathComponent(SettingsSync.placeholderName(for: SettingsSync.sidebarName))
        if !manager.fileExists(atPath: file.path), manager.fileExists(atPath: placeholder.path) {
            try? manager.startDownloadingUbiquitousItem(at: file)
        }
        var data: Data?
        var error: NSError?
        NSFileCoordinator().coordinate(readingItemAt: file, options: [], error: &error) { url in data = try? Data(contentsOf: url) }
        guard let data, let document = MobileSpaces.document(from: data) else { return .nothingSynced }
        return .spaces(document)
    }
}
