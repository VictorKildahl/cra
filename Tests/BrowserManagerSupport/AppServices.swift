import AppKit
import CraCEF

/// Records each sheet the manager puts up; a test answers it with `answer(_:)` or closes it.
@MainActor final class AppDialog {
    static var presented: [AppDialog] = []
    let title: String
    private(set) var completion: ((NSApplication.ModalResponse) -> Void)?
    var isUp: Bool { completion != nil }
    init(title: String, actions: [DialogAction]) { self.title = title }
    func present(over window: NSWindow, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        self.completion = completion
        Self.presented.append(self)
    }
    /// The permission card (#371) records itself the same way, with the page it sits on.
    private(set) var anchor: NSView?
    func present(relativeTo rect: NSRect, of view: NSView, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        anchor = view
        present(over: view.window ?? NSWindow(), completion: completion)
    }
    /// The production sheet's close(): ends it as Escape would (.abort) when nothing was chosen.
    func close() { answer(.abort) }
    func answer(_ response: NSApplication.ModalResponse) {
        let done = completion
        completion = nil
        done?(response)
    }
}

/// The manager's permission popover (#371) is recorded with the sheets, so #286's test reads both.
typealias PermissionPopover = AppDialog

// Unrelated shell services required to typecheck the complete production manager.
// The tab store deliberately remains observable so stale callbacks can be asserted.
struct TestTab { var url: String; var savedTitle = ""; var muted = false; var faviconKey: String?; var themeColor: String?; var activeTabBeforeCreationID: UUID? }
struct TestItem {
    let id: UUID
    var tab: TestTab?
    var parentID: UUID?
    var children: [UUID] = []
    var isEmptyTab = false
    var isSplit = false
    var isTab: Bool { tab != nil }
}
enum TestRoot { case today }
@MainActor final class BlockLists {
    static let shared = BlockLists()
    func isPaused(url: String) -> Bool { false }
    func style(for host: String) -> String { "" }
    func procedural(for host: String) -> [String] { [] }
}
/// The filter lists' page scripts (#845): no procedural hiding in the harness.
@MainActor enum FilterPageScripts {
    static func proceduralExpression(_ selectors: [String]) -> String? { nil }
}

@MainActor final class SidebarStore {
    static let documentReplaced = Notification.Name("CraSidebarDocumentReplaced")
    struct Settings {
        var autoPictureInPicture = false
        /// Hosts whose Site Control Center switch turned automatic Picture in Picture off.
        var autoPictureInPictureOff: Set<String> = []
        func allowsAutoPictureInPicture(url: String) -> Bool {
            autoPictureInPicture && !autoPictureInPictureOff.contains(URL(string: url)?.host ?? "")
        }
        var shareThemeWithWebsites = true
        var removesAdblockWarnings = false
        var blockCookieBanners = false
        var blockAdsAndTrackers = true
        var littleWindowOnOptionCommandClick = false
        /// Settings ▸ Links ▸ a middle click in a split adds a pane (#498), off by default.
        var splitMiddleClickAddsPane = false
        /// Settings ▸ Links ▸ "Open background tabs below the current tab" (#532), off by default.
        var backgroundTabsBelowCurrent = false
        /// Settings ▸ Tabs ▸ "Always keep these sites active" (#458), by host; AppSettings matches subdomains.
        var keepActiveHosts: Set<String> = []
        /// Settings ▸ Tabs ▸ "Player with artwork" (Discussion #761): only the island reads what plays.
        var nowPlayingStyle: NowPlayingStyle = .arc
        func keepsActive(url: String) -> Bool { keepActiveHosts.contains(URL(string: url)?.host ?? "") }
        var defaultLinkDestination: LinkDestination = .littleWindowInUse
        var linkRoutes: [LinkRoute] = []
    }
    func cookieBannerCSS(item: UUID) -> String? { settings.blockCookieBanners ? "#onetrust-banner-sdk { display: none !important; }" : nil }
    func themeDataCSS(item: UUID, systemDark: Bool) -> String? {
        settings.shareThemeWithWebsites ? ":root { --arc-palette-title: #211A00FF; }" : nil
    }
    var settings = Settings()
    var items: [UUID: TestItem] = [:]
    func item(_ id: UUID) -> TestItem? { items[id] }
    var focusedSpace = UUID()
    func focusedSpaceID(window: UUID?) -> UUID { focusedSpace }
    var spaces: Set<UUID> = []
    func space(_ id: UUID) -> UUID? { (spaces.contains(id) || id == focusedSpace) ? id : nil }
    var standaloneSpaces: Set<UUID> = []
    var standaloneWindows: Set<UUID> = []
    func isStandalone(space id: UUID?) -> Bool { id.map { standaloneSpaces.contains($0) || incognitoItems.contains($0) } ?? false }
    func isStandalone(window id: UUID?) -> Bool { id.map(standaloneWindows.contains) ?? false || isStandalone(space: focusedSpace) }
    var pinnedItems: Set<UUID> = []
    var favoriteItems: Set<UUID> = []
    func isPinned(_ id: UUID) -> Bool { pinnedItems.contains(id) || favoriteItems.contains(id) }
    func isFavorite(_ id: UUID) -> Bool { favoriteItems.contains(id) }
    var incognitoItems: Set<UUID> = []
    func isIncognito(item: UUID) -> Bool { incognitoItems.contains(item) }
    var profilePaths: [UUID: String] = [:]
    var spaceProfiles: [UUID: String] = [:]
    func profilePath(space sid: UUID) -> String? { spaceProfiles[sid] }
    func profilePath(item: UUID) -> String? {
        if let path = profilePaths[item] { return path }
        return itemSpaces[item].flatMap { spaceProfiles[$0] }
    }
    func profileDirectoryName(item: UUID) -> String { "Default" }
    func profileID(item: UUID) -> UUID? { nil }
    var itemSpaces: [UUID: UUID] = [:]
    func spaceID(ofItem id: UUID) -> UUID? { itemSpaces[id] }
    var selectedTabPerSpace: [UUID: UUID] = [:]
    func splitContaining(_ id: UUID) -> TestItem? {
        guard let p = items[id]?.parentID, let parent = items[p], parent.isSplit else { return nil }
        return parent
    }
    func paneID(for tabID: UUID, in split: TestItem) -> UUID? {
        if split.children.contains(tabID) { return tabID }
        return split.children.first { items[$0]?.tab?.activeTabBeforeCreationID == tabID }
    }
    /// A split's panes, as SidebarStore reads them (#498): the tab alone when it isn't in one.
    func paneTabIDs(for tabID: UUID) -> [UUID] { splitContaining(tabID)?.children ?? [tabID] }
    var splitPaneLimit: Int { 4 }
    /// The panes a middle click in a split added (#498), in order.
    var linkPanes: [String] = []
    func openLinkInSplit(_ url: String, from tabID: UUID, window: UUID? = nil) -> TestItem? {
        guard paneTabIDs(for: tabID).count < splitPaneLimit else { return nil }
        linkPanes.append(url)
        return createTab(url: url)
    }
    func rootContainer(of: UUID) -> TestRoot? { nil }
    /// The slot below a link's source tab (#532); CraCore's LinkTabPlacementTests pin where it is.
    struct LinkSlot { let parent: UUID; let index: Int }
    func linkTabSlot(below source: UUID, afterEarlierLinks: Bool) -> LinkSlot? { nil }
    func updateTab(_ id: UUID, url: String? = nil, title: String? = nil) {
        if let url { items[id]?.tab?.url = url }
        if let title { items[id]?.tab?.savedTitle = title }
    }
    func setThemeColor(_ id: UUID, _ hex: String) { items[id]?.tab?.themeColor = hex }
    func setFaviconKey(_ id: UUID, _ key: String) { items[id]?.tab?.faviconKey = key }
    /// The URLs a finished load counted as visits, in order.
    var visits: [String] = []
    func recordVisit(url: String, title: String, profile: UUID?) { visits.append(url) }
    func clearHistory(_ range: BrowsingDataClear.Range) {}
    /// The tabs selected, in order (Picture in Picture's Back to Tab selects; Minimize doesn't),
    /// and the space each selection asked for (#843).
    private(set) var selections: [UUID] = []
    private(set) var selectedSpaces: [UUID?] = []
    func selectTab(_ id: UUID, in space: UUID? = nil, window: UUID?) {
        let sid = space ?? itemSpaces[id] ?? focusedSpace
        focusedSpace = sid
        selectedTabPerSpace[sid] = id
        selections.append(id)
        selectedSpaces.append(space)
    }
    var unreadItems: Set<UUID> = []
    func markUnread(_ id: UUID, _ unread: Bool) {
        if unread { unreadItems.insert(id) } else { unreadItems.remove(id) }
    }
    var movedTabs: [(id: UUID, toSpace: UUID, followed: Bool)] = []
    func moveTab(_ id: UUID, toSpace sid: UUID) {
        guard items[id]?.isTab == true, space(sid) != nil else { return }
        itemSpaces[id] = sid
        movedTabs.append((id, sid, false))
    }
    func selectedTabID(window: UUID?) -> UUID? { selectedTabPerSpace[focusedSpace] }
    /// As the app's: the window follows only the tab it has selected; any other tab moves on its own.
    func rerouteTab(_ id: UUID, toSpace sid: UUID, window: UUID?) {
        guard items[id]?.isTab == true, !isPinned(id), space(sid) != nil, !isStandalone(space: sid) else { return }
        guard selectedTabID(window: window) == id else { return moveTab(id, toSpace: sid) }
        let from = itemSpaces[id]
        let previous = items[id]?.tab?.activeTabBeforeCreationID
        itemSpaces[id] = sid
        if let from, from != sid, selectedTabPerSpace[from] == id {
            selectedTabPerSpace[from] = previous.flatMap { itemSpaces[$0] == from ? $0 : nil }
        }
        focusedSpace = sid
        selectedTabPerSpace[sid] = id
        movedTabs.append((id, sid, true))
    }
    @discardableResult
    func createTab(url: String, in space: UUID? = nil, select: Bool = false,
                   parent: UUID? = nil, index: Int? = nil, window: UUID? = nil, referrer: UUID? = nil) -> TestItem {
        let sid = space ?? focusedSpace
        spaces.insert(sid)
        let previous = selectedTabPerSpace[sid]
        let item = TestItem(id: UUID(), tab: TestTab(url: url, activeTabBeforeCreationID: previous))
        items[item.id] = item
        itemSpaces[item.id] = sid
        if select {
            focusedSpace = sid
            selectedTabPerSpace[sid] = item.id
        }
        return item
    }
}
typealias AppSettings = SidebarStore.Settings
/// The extensions turned on in the Default profile.
@MainActor final class ExtensionStore {
    struct Entry { let extensionID: String }
    static let shared = ExtensionStore()
    var entries: [Entry] = []
    func entries(inProfile name: String) -> [Entry] { entries }
    func proxyLine(inProfile name: String) -> String { "not set by an extension" }
    /// The profiles a loaded page asked for Web Store installs in (#203), in order.
    var webStoreProfiles: [String] = []
    func installFromWebStore(using browser: CraBrowser, profile: String) { webStoreProfiles.append(profile) }
    /// The profiles a loaded page brought its shared extensions up to date in (discussion #595), in order.
    var sharedProfiles: [String] = []
    func reconcileShared(profile: String, using browser: CraBrowser? = nil) { sharedProfiles.append(profile) }
}
enum BrowsingDataClear {
    enum Range { case allTime }
    static func historyRange(messageJSON: String, now: Date) -> Range? { nil }
}
enum TabSwitcherMetrics { static let thumbnail = NSSize(width: 320, height: 200) }
enum HitchMonitor { static func mark(_ event: String) {} }
/// A committed page lets its own redirect to another app ask once again (#560); no sheets here.
@MainActor enum AppLinkPrompt { static func pageLoaded(_ browser: CraBrowser) {} }
enum EmbeddedPages {
    static var viewsByHost: [ObjectIdentifier: [NSView]] = [:]
    static func isHost(_ window: NSWindow) -> Bool { viewsByHost[ObjectIdentifier(window)] != nil }
    static func pageViews(of window: NSWindow) -> [NSView]? { viewsByHost[ObjectIdentifier(window)] }
}
/// The engine's DevTools in a card (Sources/Cra/UI/Windows/EmbeddedDevTools.swift): the same rule for whose they
/// are, and no card here, so no frontend is ever in one.
@MainActor enum EmbeddedDevTools {
    final class Holder: NSView {}
    static func applies(to browser: CraBrowser?) -> Bool {
        guard let browser else { return false }
        return browser.hostWindow == nil && !(browser is WebKitBrowser)
    }
    static func holder(of w: NSWindow?) -> Holder? { nil }
}
final class LiveFolderManager {
    static let shared = LiveFolderManager()
    func pageChanged(tab: UUID, to url: String) {}
}
struct PictureInPictureActions {
    var backToTab: () -> Void
    var togglePlayback: () -> Void
    var skip: (Double) -> Void
    var seek: (Double) -> Void
    var close: () -> Void
    var minimize: () -> Void = {}
}
final class PictureInPictureChrome {
    static let shared = PictureInPictureChrome()
    var actions: PictureInPictureActions?
    var isPlaying = false
    var time: (position: Double, duration: Double) = (0, 0)
    var address = ""
    func videoEntered() {}
    func videoLeft() {}
}
/// The WebKit page (Sources/Cra/Services/WebKit/WebKitBrowser.swift): here only its type, which
/// is what PageEngines and BrowserManager decide on.
final class WebKitBrowser: CraBrowser {
    var isContentFullscreen = false
    var serviceName = ""
    var savedInteractionState: Data?
    /// Where a page that moved here for a protected video seeks to (the real page's user script).
    var resume: (url: String, seconds: Double)?
    convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool, profilePath: String?,
                     interactionState: Data?, resume: (url: String, seconds: Double)? = nil) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath)
        savedInteractionState = interactionState
        self.resume = resume
    }
}
/// WebKit's stores (Sources/Cra/Services/WebKit/WebKitStores.swift): here only what was copied in.
@MainActor
enum WebKitStores {
    static var added: [(cookies: [HTTPCookie], profilePath: String?, incognito: Bool)] = []
    static func add(_ cookies: [HTTPCookie], profilePath: String?, incognito isIncognito: Bool, done: @escaping @MainActor () -> Void) {
        added.append((cookies, profilePath, isIncognito))
        done()
    }
}

/// The engine Cra runs on (Sources/Cra/App/EngineFramework.swift): the Chromium engine here.
enum EngineFramework {
    static let isChromiumEngine = true
}
