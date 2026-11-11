import Foundation

/// A tab's back and forward list, kept across a relaunch as Arc keeps it (GitHub #273). Arc maps
/// each sidebar tab to a Chromium session tab (StorableSessionRestorationData.json) and Chromium's
/// session service saves that tab's navigations, page state included (scroll position, form
/// contents): after a relaunch Back still goes where it went. Cra asks the page for the same
/// serialized navigations (`Cra.getHistory`, Chromium's ContentSerializedNavigationBuilder, the
/// current entry and up to six on each side like Chrome's session service) and puts them back
/// into a new page before it loads (`Cra.restoreHistory`). WebKit pages save WKWebView's
/// interactionState instead. Saved in the data folder's PageHistory/<tab id>.json, one file a tab.
public struct PageHistory: Codable, Equatable, Sendable {
    /// Which engine wrote `state`; the other can't read it.
    public var engine: PageEngine
    /// The address the page was on: the entry the restored page opens at.
    public var url: String
    /// The engine's own serialization.
    public var state: Data
    /// Chromium: the current entry's place in `state`'s list. WebKit's state holds its own.
    public var index: Int
    public var savedAt: Date

    public init(engine: PageEngine, url: String, state: Data, index: Int = 0, savedAt: Date) {
        self.engine = engine
        self.url = url
        self.state = state
        self.index = index
        self.savedAt = savedAt
    }

    /// Whether a new page for a tab now at `tabURL`, made in `engine`, opens with this history.
    /// Only while it ends where the tab is: a pinned tab put back on its page, a tab whose page
    /// moved on after the last save or a page reopened in the other engine starts fresh there.
    /// Not on one of Chromium's own pages either (chrome://settings and the like): Chromium builds
    /// such a page's WebUI as the restored entry starts to load, inside the page's creation, and
    /// crashed there at every launch (0.1.38, a tab left on chrome://settings/privacy).
    public func restores(into engine: PageEngine, at tabURL: String) -> Bool {
        engine == self.engine && !state.isEmpty && url == tabURL && !Self.isChromiumOwnPage(tabURL)
    }

    /// Whether `url` is a page Chromium serves itself, with a WebUI behind it.
    static func isChromiumOwnPage(_ url: String) -> Bool {
        let scheme = url.prefix { $0 != ":" }.lowercased()
        return ["chrome", "chrome-untrusted", "devtools"].contains(scheme)
    }

    /// The tabs whose saved history stays on disk: every tab in the sidebar, and the tabs most
    /// recently closed, which ⇧⌘T and the Library bring back with their history (Chrome's
    /// TabRestoreService keeps 25). `archive` is newest first.
    public static let reopenable = 25

    public static func kept(sidebarTabs: Set<UUID>, archive: [UUID]) -> Set<UUID> {
        sidebarTabs.union(archive.prefix(reopenable))
    }
}

/// Saved as its raw value ("chromium", "webKit").
extension PageEngine: Codable {}
