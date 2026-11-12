import Foundation

/// Arc's "Recent pages on Linear, Notion, and Figma" preview (Settings ▸ General ▸ Previews
/// Settings…; Arc 1.172.2's Previews/RecentPagesFetcher, GitHub #376): hovering a favorite or pinned
/// tab on one of these sites (Confluence too, in Arc's binary though not in the sheet's name) lists
/// the pages you visited there, newest first, from the browsing history. Nothing is fetched and no
/// sign-in is needed. Titles are tidied with Arc's rules; Arc's OAuth callbacks and Figma's own
/// Recently Viewed page are left out.
public enum RecentPagesPreview {
    public enum Site: String, CaseIterable, Sendable {
        case linear, notion, figma, confluence

        /// Arc's empty card (its "Empty state header for … preview" strings).
        public var emptyText: String {
            switch self {
            case .linear: "Recent Linear projects and issues appear here."
            case .notion: "Recent Notion docs appear here."
            case .figma: "Recent Figma files appear here."
            case .confluence: "Recent Confluence pages appear here."
            }
        }

        /// Arc's ＋ on the card: a new issue, page or file.
        public var newURL: String {
            switch self {
            case .linear: "https://linear.app/new"
            case .notion: "https://notion.so/new"
            case .figma: "https://figma.com/new"
            case .confluence: "https://confluence.new"
            }
        }

        /// The ＋'s name for VoiceOver and its tooltip.
        public var newLabel: String {
            switch self {
            case .linear: "New Issue"
            case .notion: "New Page"
            case .figma: "New File"
            case .confluence: "New Page"
            }
        }
    }

    public struct Page: Equatable, Sendable {
        public var title: String
        public var url: String
        public var lastVisit: Date
        public init(title: String, url: String, lastVisit: Date) { (self.title, self.url, self.lastVisit) = (title, url, lastVisit) }
    }

    /// Arc's limit on what it reads (the card scrolls through them).
    public static let limit = 20

    /// The pages Arc never lists: sign-in callbacks and Figma's Recently Viewed (Arc 1.172.2).
    static let excluded = ["notion.so/samlauthcallback", "notion.so/externalintegrationauthcallback", "notion.so/googlepopupcallback",
                           "notion.so/oauth2callback", "figma.com/files/recent"]

    /// Notion's hosts; Notion Calendar (calendar.notion.so) is another preview.
    static let notionHosts: Set<String> = ["notion.so", "notion.com", "app.notion.com"]

    /// The site a favorite or pinned tab is on, if Arc gives it recent pages.
    public static func site(for url: String) -> Site? {
        guard let u = URLComponents(string: url), u.scheme == "https" || u.scheme == "http", let raw = u.host?.lowercased() else { return nil }
        let host = raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
        switch host {
        case "linear.app": return .linear
        case "figma.com": return .figma
        case _ where notionHosts.contains(host) || host.hasSuffix(".notion.site"): return .notion
        case _ where host.hasSuffix(".atlassian.net") && (u.path == "/wiki" || u.path.hasPrefix("/wiki/")): return .confluence
        default: return nil
        }
    }

    /// The favorite's recent pages from the history, newest first, one row per page (a Figma
    /// file's frames are one file), without the favorite's own page. A Confluence favorite lists
    /// its own company's wiki only.
    public static func pages(for favorite: String, history: [HistoryEntry], rules: TidyTitleRules = .arc, limit: Int = limit) -> [Page] {
        guard let site = site(for: favorite) else { return [] }
        let home = key(favorite)
        let confluenceHost = site == .confluence ? URLComponents(string: favorite)?.host?.lowercased() : nil
        var seen = Set<String>()
        var out: [Page] = []
        for entry in history.sorted(by: { $0.lastVisit > $1.lastVisit }) {
            if out.count >= limit { break }
            guard Self.site(for: entry.url) == site else { continue }
            if let confluenceHost, URLComponents(string: entry.url)?.host?.lowercased() != confluenceHost { continue }
            let k = key(entry.url)
            guard k != home, !excluded.contains(where: k.hasPrefix), seen.insert(k).inserted else { continue }
            let title = tidy(entry.title, url: entry.url, site: site, rules: rules)
            // A page that never had a title (Chromium shows its address) says nothing in a list.
            guard !title.isEmpty, title != entry.url else { continue }
            out.append(Page(title: title, url: entry.url, lastVisit: entry.lastVisit))
        }
        return out
    }

    /// Arc's tidy title. Arc's Figma rule drops " – Figma" on /file/ and /files/ only; Figma's
    /// newer /design/, /board/ and /slides/ files end in it too, so the card drops it on any Figma page.
    static func tidy(_ title: String, url: String, site: Site, rules: TidyTitleRules) -> String {
        var t = rules.tidy(title, url: url)
        if site == .figma, t.hasSuffix(" – Figma"), t.count > 8 { t.removeLast(8) }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One page whatever its address carries: host without "www.", path without a trailing slash,
    /// and only the query items that name a page (Notion's peeked `p`, Confluence's `pageId`).
    static func key(_ url: String) -> String {
        guard let u = URLComponents(string: url), let raw = u.host?.lowercased() else { return url }
        let host = raw.hasPrefix("www.") ? String(raw.dropFirst(4)) : raw
        var path = u.path
        while path.hasSuffix("/") { path.removeLast() }
        let ids = (u.queryItems ?? []).filter { $0.name == "p" || $0.name == "pageId" }.map { "\($0.name)=\($0.value ?? "")" }
        return host + path + (ids.isEmpty ? "" : "?" + ids.sorted().joined(separator: "&"))
    }
}

/// Which hover card a favorite or pinned tab gets (Arc's Previews: "Hover your mouse over an Arc
/// Folder, Pinned, or Favorited tab"), by its address and the Previews Settings… checkboxes.
public enum SidebarTabPreview: Equatable, Sendable {
    case gmail
    case calendar
    case recentPages(RecentPagesPreview.Site)
    case outlookMail
    case outlookCalendar
    case notionCalendar

    public static func kind(for url: String, settings: AppSettings) -> SidebarTabPreview? {
        if GmailPreview.feedURL(for: url) != nil { return settings.favoritePreviews ? .gmail : nil }
        if CalendarPreview.isCalendar(url) { return settings.liveCalendar && settings.calendarHoverPreview ? .calendar : nil }
        if let site = RecentPagesPreview.site(for: url) { return settings.recentPagesPreviews ? .recentPages(site) : nil }
        switch OutlookPreview.kind(for: url) {
        case .mail: return settings.outlookMailPreviews ? .outlookMail : nil
        case .calendar: return settings.outlookCalendarPreviews ? .outlookCalendar : nil
        case nil: break
        }
        if NotionCalendarPreview.isNotionCalendar(url) { return settings.notionCalendarPreviews ? .notionCalendar : nil }
        return nil
    }

    /// The card an address gets whatever the checkboxes say (the card already open keeps its kind).
    public static func card(for url: String) -> SidebarTabPreview? { kind(for: url, settings: AppSettings()) }

    /// The calendar card's gear: the last item turns the preview off (Arc's Google Calendar says
    /// "Disable Live Calendar", which also stops the tile's countdown and Join link).
    public var turnOffTitle: String? {
        switch self {
        case .calendar: "Disable Live Calendar"
        case .outlookCalendar: "Turn Off Outlook Calendar Preview"
        case .notionCalendar: "Turn Off Notion Calendar Preview"
        default: nil
        }
    }

    /// That item's switch: Live Calendar for Google, the preview's own checkbox for the others.
    public func turnOff(_ settings: inout AppSettings) {
        switch self {
        case .gmail: settings.favoritePreviews = false
        case .calendar: settings.liveCalendar = false
        case .recentPages: settings.recentPagesPreviews = false
        case .outlookMail: settings.outlookMailPreviews = false
        case .outlookCalendar: settings.outlookCalendarPreviews = false
        case .notionCalendar: settings.notionCalendarPreviews = false
        }
    }
}
