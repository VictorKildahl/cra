import AppKit

// Unrelated shell services required to typecheck the complete production manager.
// The tab store deliberately remains observable so stale callbacks can be asserted.
struct TestTab { var url: String; var savedTitle = ""; var muted = false; var faviconKey: String? }
struct TestItem {
    let id: UUID
    var tab: TestTab?
    var parentID: UUID?
    var children: [UUID] = []
    var isEmptyTab = false
    var isTab: Bool { tab != nil }
}
enum TestRoot { case today }
@MainActor final class SidebarStore {
    struct Settings { var autoPictureInPicture = false }
    var settings = Settings()
    var items: [UUID: TestItem] = [:]
    func item(_ id: UUID) -> TestItem? { items[id] }
    func isIncognito(item: UUID) -> Bool { false }
    func profilePath(item: UUID) -> String? { nil }
    func spaceID(ofItem: UUID) -> UUID? { nil }
    func rootContainer(of: UUID) -> TestRoot? { nil }
    func updateTab(_ id: UUID, url: String? = nil, title: String? = nil) {
        if let url { items[id]?.tab?.url = url }
        if let title { items[id]?.tab?.savedTitle = title }
    }
    func recordVisit(url: String, title: String) {}
    func selectTab(_ id: UUID, window: UUID?) {}
    func markUnread(_ id: UUID, _ unread: Bool) {}
    @discardableResult
    func createTab(url: String, in space: UUID? = nil, select: Bool = false,
                   parent: UUID? = nil, index: Int? = nil, window: UUID? = nil) -> TestItem {
        let item = TestItem(id: UUID(), tab: TestTab(url: url))
        items[item.id] = item
        return item
    }
}
final class FaviconCache {
    static func key(for url: String) -> String? { url }
    func store(_ image: NSImage, forKey: String, persist: Bool) {}
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
    func videoEntered() {}
    func videoLeft() {}
}
