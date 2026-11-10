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
    /// The production sheet's close(): ends it as Escape would (.abort) when nothing was chosen.
    func close() { answer(.abort) }
    func answer(_ response: NSApplication.ModalResponse) {
        let done = completion
        completion = nil
        done?(response)
    }
}

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
    struct Settings {
        var autoPictureInPicture = false
        /// Hosts whose Site Control Center switch turned automatic Picture in Picture off.
        var autoPictureInPictureOff: Set<String> = []
        func allowsAutoPictureInPicture(url: String) -> Bool {
            autoPictureInPicture && !autoPictureInPictureOff.contains(URL(string: url)?.host ?? "")
        }
        var shareThemeWithWebsites = true
        var blockCookieBanners = false
    }
    func cookieBannerCSS(item: UUID) -> String? { settings.blockCookieBanners ? "#onetrust-banner-sdk { display: none !important; }" : nil }
    func themeDataCSS(item: UUID, systemDark: Bool) -> String? {
        settings.shareThemeWithWebsites ? ":root { --arc-palette-title: #211A00FF; }" : nil
    }
    var settings = Settings()
    var items: [UUID: TestItem] = [:]
    func item(_ id: UUID) -> TestItem? { items[id] }
    var incognitoItems: Set<UUID> = []
    func isIncognito(item: UUID) -> Bool { incognitoItems.contains(item) }
    func profilePath(item: UUID) -> String? { nil }
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
    func rootContainer(of: UUID) -> TestRoot? { nil }
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
    func selectTab(_ id: UUID, window: UUID?) {}
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
final class LiveFolderManager {
    static let shared = LiveFolderManager()
    func pageChanged(tab: UUID, to url: String) {}
}
struct PictureInPictureActions {
    var backToTab: () -> Void
    var togglePlayback: () -> Void
    var skip: (Double) -> Void
    var close: () -> Void
}
final class PictureInPictureChrome {
    static let shared = PictureInPictureChrome()
    var actions: PictureInPictureActions?
    var isPlaying = false
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
