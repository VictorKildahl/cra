import Foundation

/// The pop-ups Chromium's pop-up blocker held back on a page: a window.open or target=_blank the
/// page made without a click to back it, or past the one tab a click may open (a shared
/// folder's Open All). Chrome lists them from an icon in its address bar; Cra shows the button
/// in the toolbar and the sidebar's URL field, whose menu opens them one by one or all at once
/// and always allows the site (scripts/cef-patches/blocked-popups.patch).
///
/// Chromium sends its whole list whenever it changes ("Cra.popups"): a pop-up blocked, the list
/// cleared when the page navigates. Cra opens a pop-up as a new tab itself, so Chromium keeps
/// listing it; `open(_:)` hides it here until Chromium drops it.
public struct BlockedPopups: Equatable, Sendable {
    public struct Popup: Equatable, Sendable {
        /// Chromium's id for it, unique on the page.
        public let id: Int
        public let url: String

        public init(id: Int, url: String) {
            self.id = id
            self.url = url
        }
    }

    /// Chromium's list, oldest first.
    public private(set) var listed: [Popup] = []
    /// The ones Cra opened, still on Chromium's list.
    public private(set) var opened: Set<Int> = []

    public init() {}

    /// The pop-ups still to open, one per address (a page that asked twice lists it twice): the
    /// button shows while there are any.
    public var waiting: [Popup] {
        var seen = Set<String>()
        return listed.filter { !opened.contains($0.id) && seen.insert($0.url).inserted }
    }

    /// Chromium's list as it is now (ids and URLs pair up by index; extra entries are dropped).
    public mutating func update(ids: [Int], urls: [String]) {
        listed = zip(ids, urls).map(Popup.init)
        opened.formIntersection(listed.map(\.id))
    }

    /// The pop-ups to open for `id`, nil for all that are waiting, and marks them opened.
    public mutating func open(_ id: Int?) -> [Popup] {
        let picked = waiting.filter { id == nil || $0.id == id }
        picked.forEach { markOpened(url: $0.url) }
        return picked
    }

    /// The page opened `url` itself (a later click: a shared folder's "Open Tab 2 of 4"), so the
    /// button no longer offers it. True when that took one off the list.
    @discardableResult
    public mutating func markOpened(url: String) -> Bool {
        let ids = listed.filter { $0.url == url && !opened.contains($0.id) }.map(\.id)
        opened.formUnion(ids)
        return !ids.isEmpty
    }

    // MARK: Words

    /// Help for the toolbar button and the URL field's affordance.
    public static func buttonTitle(count: Int) -> String { count == 1 ? "Pop-up Blocked" : "Pop-ups Blocked" }

    /// The menu's heading.
    public static func heading(count: Int) -> String {
        count == 1 ? "1 Pop-up Blocked on This Page" : "\(count) Pop-ups Blocked on This Page"
    }

    public static func openAllTitle(count: Int) -> String { "Open All \(count) Pop-ups" }

    /// "Always Allow Pop-ups from example.com", nil for a page with no web address to allow.
    public static func allowTitle(pageURL: String) -> String? {
        site(of: pageURL).map { "Always Allow Pop-ups from \($0)" }
    }

    /// A pop-up's menu item: its address without the scheme, "www." or a lone trailing slash,
    /// cut to `limit` characters.
    public static func menuTitle(url: String, limit: Int = 60) -> String {
        var text = url
        if let colon = text.range(of: "://") { text = String(text[colon.upperBound...]) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        if text.hasSuffix("/"), text.dropLast().contains("/") == false { text.removeLast() }
        if text.isEmpty { return url }
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }

    /// The host Chrome's setting is for: http and https pages only (a file or a Cra page has none).
    public static func site(of pageURL: String) -> String? {
        guard let url = URL(string: pageURL), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host, !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
