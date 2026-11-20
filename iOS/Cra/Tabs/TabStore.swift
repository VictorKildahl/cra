import CraCore
import UIKit
import WebKit

/// The iPhone app's tabs: `tabs.json` in the data folder (`MobileTabsDocument` decides what
/// changes), the live web views, and each tab's last picture.
final class TabStore {
    private(set) var document: MobileTabsDocument
    private let fileURL: URL
    private let snapshotsURL: URL
    /// Each tab's place in its page: WKWebView's interactionState (back and forward list, scroll
    /// position) in a PageHistory, as the Mac keeps its WebKit pages' (#273). A tab whose page is made
    /// again, after a relaunch or from the archive, opens where it was, as Arc Search does (#656).
    private let historiesURL: URL
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
        historiesURL = directory.appendingPathComponent("PageHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: historiesURL, withIntermediateDirectories: true)
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

    /// "Open in Background Tab": a tab at the end of the row, not shown. An incognito one waits
    /// unseen while the private session goes on (`MobileTabsDocument.addInBackground`).
    func addInBackground(url: String, incognito: Bool) -> MobileTab {
        let tab = MobileTab(url: url, lastActive: now(), isIncognito: incognito)
        document.addInBackground(tab)
        changed()
        return tab
    }

    func select(_ id: UUID) {
        document.select(id, now: now())
        changed()
    }

    /// A tab picked from the row: shown, and moved to the row's newest end (#647).
    func bringToFront(_ id: UUID) {
        document.bringToFront(id, now: now())
        changed()
    }

    /// The tab row's tabs: incognito tabs are never in it.
    var rowTabs: [MobileTab] { document.rowTabs }

    /// The tab switcher's cards: the row, and on a private page the private tabs waiting unseen.
    var switcherTabs: [MobileTab] { document.switcherTabs }

    /// Where a flick up on the tab button goes: the tab looked at before this one.
    var previousTab: MobileTab? { document.previousTab }

    /// The open tab that opened `id`, through openers that have closed since.
    private func liveOpener(of id: UUID) -> WebPage? {
        var opener = pages[id]?.opener
        while let page = opener, !document.tabs.contains(where: { $0.id == page.tabID }) { opener = page.opener }
        return opener
    }

    func close(_ id: UUID) {
        let wasSelected = document.selected == id
        let opener = liveOpener(of: id)
        document.close(id)
        if wasSelected, let opener { document.select(opener.tabID, now: now()) }
        pages[id] = nil
        snapshots[id] = nil
        try? FileManager.default.removeItem(at: snapshotFile(id))
        try? FileManager.default.removeItem(at: historyFile(id))
        changed()
    }

    var archived: [MobileTab] { document.archived }

    /// Closes a tab into the archive, as throwing its card away does.
    func archive(_ id: UUID) {
        let wasSelected = document.selected == id
        let opener = liveOpener(of: id)
        document.archive(id, returningTo: opener?.tabID)
        // Back on its opener, whose archive clock restarts as when it is picked.
        if wasSelected, let opener, document.selected == opener.tabID { document.select(opener.tabID, now: now()) }
        if let page = pages[id] { saveHistory(of: page) }
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
        ids.forEach {
            try? FileManager.default.removeItem(at: snapshotFile($0))
            try? FileManager.default.removeItem(at: historyFile($0))
        }
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
            if let page = pages[id] { saveHistory(of: page) }
            pages[id] = nil
            snapshots[id] = nil
        }
        changed()
    }

    private func changed() {
        // A private popup's source is still live: window.close() must be able to return to it.
        // Leaving that live chain for an unrelated tab still closes every private tab in it.
        var retained = Set<UUID>()
        var opener = document.selected.flatMap { pages[$0]?.opener }
        while let page = opener {
            retained.insert(page.tabID)
            opener = page.opener
        }
        for id in document.closeIncognitoTabsLeftBehind(keeping: retained) {
            pages[id] = nil
            snapshots[id] = nil
        }
        scheduleSave()
    }

    // MARK: Pages

    /// Returns a retained related page without loading its URL: WebKit continues the original
    /// request in the returned view. Privacy belongs to the source, even if selection changed.
    func openPopup(configuration: WKWebViewConfiguration, request: URLRequest, from source: WebPage) -> WebPage? {
        guard pages[source.tabID] === source,
              let origin = document.tabs.first(where: { $0.id == source.tabID }) else { return nil }
        let tab = MobileTab(url: request.url?.absoluteString ?? "about:blank", lastActive: now(), isIncognito: origin.isIncognito)
        let page = WebPage(tab: tab, configuration: configuration, opener: source)
        pages[tab.id] = page
        document.open(tab)
        changed()
        return page
    }

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

    // MARK: Places in pages

    private func historyFile(_ id: UUID) -> URL {
        historiesURL.appendingPathComponent("\(id.uuidString).json")
    }

    /// Keeps where `page` is, its scroll position and back and forward list, for when its tab's page is
    /// made again (#656). Never an incognito tab's.
    func saveHistory(of page: WebPage) {
        guard let tab = (document.tabs + document.archived).first(where: { $0.id == page.tabID }), !tab.isIncognito,
              page.webView.backForwardList.currentItem != nil, let url = page.webView.url?.absoluteString,
              let state = page.webView.interactionState as? Data,
              let data = try? JSONEncoder().encode(PageHistory(engine: .webKit, url: url, state: state, savedAt: now())) else { return }
        try? data.write(to: historyFile(page.tabID), options: .atomic)
    }

    /// Every page's place: the app is going to the background, where iOS may end it.
    func saveHistories() {
        for page in pages.values { saveHistory(of: page) }
    }

    /// The place to open `tab`'s new page at, when it was saved on the page the tab is on.
    func history(for tab: MobileTab) -> PageHistory? {
        guard !tab.isIncognito, let data = try? Data(contentsOf: historyFile(tab.id)),
              let history = try? JSONDecoder().decode(PageHistory.self, from: data),
              history.restores(into: .webKit, at: tab.url) else { return nil }
        return history
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
