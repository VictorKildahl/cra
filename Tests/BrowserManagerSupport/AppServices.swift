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
        var blockCookieBanners = false
        var littleWindowOnOptionCommandClick = false
        /// Settings ▸ Links ▸ a middle click in a split adds a pane (#498), off by default.
        var splitMiddleClickAddsPane = false
        /// Settings ▸ Links ▸ "Open background tabs below the current tab" (#532), off by default.
        var backgroundTabsBelowCurrent = false
        /// Settings ▸ Tabs ▸ "Always keep these sites active" (#458), by host; AppSettings matches subdomains.
        var keepActiveHosts: Set<String> = []
        func keepsActive(url: String) -> Bool { keepActiveHosts.contains(URL(string: url)?.host ?? "") }
    }
    func cookieBannerCSS(item: UUID) -> String? { settings.blockCookieBanners ? "#onetrust-banner-sdk { display: none !important; }" : nil }
    func themeDataCSS(item: UUID, systemDark: Bool) -> String? {
        settings.shareThemeWithWebsites ? ":root { --arc-palette-title: #211A00FF; }" : nil
    }
    var settings = Settings()
    var items: [UUID: TestItem] = [:]
    func item(_ id: UUID) -> TestItem? { items[id] }
    private let focusedAskSpace = UUID()
    func focusedSpaceID(window: UUID?) -> UUID { focusedAskSpace }
    var incognitoItems: Set<UUID> = []
    func isIncognito(item: UUID) -> Bool { incognitoItems.contains(item) }
    var profilePaths: [UUID: String] = [:]
    func profilePath(item: UUID) -> String? { profilePaths[item] }
    func profileDirectoryName(item: UUID) -> String { "Default" }
    func spaceID(ofItem: UUID) -> UUID? { nil }
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
    func recordVisit(url: String, title: String) { visits.append(url) }
    func clearHistory(_ range: BrowsingDataClear.Range) {}
    /// The tabs selected, in order (Picture in Picture's Back to Tab selects; Minimize doesn't).
    private(set) var selections: [UUID] = []
    func selectTab(_ id: UUID, window: UUID?) { selections.append(id) }
    func markUnread(_ id: UUID, _ unread: Bool) {}
    @discardableResult
    func createTab(url: String, in space: UUID? = nil, select: Bool = false,
                   parent: UUID? = nil, index: Int? = nil, window: UUID? = nil, referrer: UUID? = nil) -> TestItem {
        let item = TestItem(id: UUID(), tab: TestTab(url: url))
        items[item.id] = item
        return item
    }
}
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
}
enum BrowsingDataClear {
    enum Range { case allTime }
    static func historyRange(messageJSON: String, now: Date) -> Range? { nil }
}
enum TabSwitcherMetrics { static let thumbnail = NSSize(width: 320, height: 200) }
enum HitchMonitor { static func mark(_ event: String) {} }
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
    convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool, profilePath: String?,
                     interactionState: Data?) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath)
        savedInteractionState = interactionState
    }
}
