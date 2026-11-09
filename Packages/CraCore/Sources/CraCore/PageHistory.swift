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
    public func restores(into engine: PageEngine, at tabURL: String) -> Bool {
        engine == self.engine && !state.isEmpty && url == tabURL
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
