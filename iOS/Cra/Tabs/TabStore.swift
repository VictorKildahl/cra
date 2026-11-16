import CraCore
import UIKit
import WebKit

/// The iPhone app's tabs: `tabs.json` in the data folder (`MobileTabsDocument` decides what
/// changes), the live web views, and each tab's last picture.
final class TabStore {
    private(set) var document: MobileTabsDocument
    private let fileURL: URL
    private let snapshotsURL: URL
    private var pages: [UUID: WebPage] = [:]
    private var snapshots: [UUID: UIImage] = [:]
    private var saveScheduled = false
    private let now: () -> Date


    init(directory: URL, now: @escaping () -> Date = Date.init) {
        self.now = now
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("tabs.json")
        snapshotsURL = directory.appendingPathComponent("Snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: snapshotsURL, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(MobileTabsDocument.self, from: data) {
            document = loaded
        } else {
            document = MobileTabsDocument()
        }
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Cra", isDirectory: true)
    }

    var tabs: [MobileTab] { document.tabs }
    var selected: MobileTab? { document.selectedTab }

    // MARK: Changes

    @discardableResult
    func open(url: String, incognito: Bool = false) -> MobileTab {
        let tab = MobileTab(url: url, lastActive: now(), isIncognito: incognito)
        document.open(tab)
        changed()
        return tab
    }

    /// A tab at the end of the row that is not shown (a link saved from another app).
    func add(url: String, title: String) {
        document.add(MobileTab(url: url, title: title, lastActive: now()))
        changed()
    }

    func select(_ id: UUID) {
        document.select(id, now: now())
        changed()
    }

    /// The tab row's tabs: incognito tabs are never in it.
    var rowTabs: [MobileTab] { document.rowTabs }

    func close(_ id: UUID) {
        document.close(id)
        pages[id] = nil
        snapshots[id] = nil
        try? FileManager.default.removeItem(at: snapshotFile(id))
        changed()
    }

    var archived: [MobileTab] { document.archived }

    /// Closes a tab into the archive, as throwing its card away does.
    func archive(_ id: UUID) {
        document.archive(id)
        pages[id] = nil
        snapshots[id] = nil
        changed()
    }

    func restore(_ id: UUID) {
        document.restore(id, now: now())
        changed()
    }

    func removeArchived(_ ids: Set<UUID>) {
        document.removeArchived(ids)
        ids.forEach { try? FileManager.default.removeItem(at: snapshotFile($0)) }
        changed()
    }

    func clearArchive() {
        removeArchived(Set(document.archived.map(\.id)))
    }

    func update(_ id: UUID, url: String?, title: String?) {
        guard let index = document.tabs.firstIndex(where: { $0.id == id }) else { return }
        var tab = document.tabs[index]
        if let url, !url.isEmpty { tab.url = url }
        if let title { tab.title = title }
        guard tab != document.tabs[index] else { return }
        document.tabs[index] = tab
        scheduleSave()
    }

    /// Moves tabs nobody opened for `after` to the archive; their pages are let go.
    func archiveStale(after: MobileArchiveAfter) {
        let before = Set(document.tabs.map(\.id))
        guard document.archiveStale(after: after, now: now()) > 0 else { return }
        for id in before.subtracting(document.tabs.map(\.id)) {
            pages[id] = nil
            snapshots[id] = nil
        }
        changed()
    }

    private func changed() {
        // An incognito tab that is no longer on screen has no way back, so it closes.
        for id in document.closeIncognitoTabsLeftBehind() {
            pages[id] = nil
            snapshots[id] = nil
        }
        scheduleSave()
    }

    // MARK: Pages

    /// The tab's web view, made on first use.
    func page(for tab: MobileTab) -> WebPage {
        if let page = pages[tab.id] { return page }
        let page = WebPage(tab: tab)
        pages[tab.id] = page
        return page
    }

    func existingPage(_ id: UUID) -> WebPage? { pages[id] }

    // MARK: Pictures

    func snapshot(_ id: UUID) -> UIImage? {
        if let image = snapshots[id] { return image }
        guard let image = UIImage(contentsOfFile: snapshotFile(id).path) else { return nil }
        snapshots[id] = image
        return image
    }

    func setSnapshot(_ image: UIImage, for id: UUID) {
        guard document.tabs.contains(where: { $0.id == id }) else { return }
        snapshots[id] = image
        let file = snapshotFile(id)
        // Incognito tabs keep their picture in memory only.
        guard document.tabs.first(where: { $0.id == id })?.isIncognito == false else { return }
        DispatchQueue.global(qos: .utility).async {
            try? image.jpegData(compressionQuality: 0.7)?.write(to: file, options: .atomic)
        }
    }

    private func snapshotFile(_ id: UUID) -> URL {
        snapshotsURL.appendingPathComponent("\(id.uuidString).jpg")
    }

    // MARK: Saving

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.saveNow() }
    }

    func saveNow() {
        saveScheduled = false
        // Incognito tabs are never written down.
        var saved = document
        saved.tabs.removeAll(where: \.isIncognito)
        if let selected = saved.selected, !saved.tabs.contains(where: { $0.id == selected }) { saved.selected = saved.tabs.last?.id }
        guard let data = try? JSONEncoder().encode(saved) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
