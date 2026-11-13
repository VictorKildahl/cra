import CraCore
import Foundation
import Testing

/// Arc's "Recent pages on Linear, Notion, and Figma" preview (GitHub #376): which tabs get it and
/// what it lists from the history.
struct RecentPagesPreviewTests {
    static let now = Date(timeIntervalSince1970: 1_794_500_000)

    static func entry(_ url: String, _ title: String, minutesAgo: Double) -> HistoryEntry {
        HistoryEntry(url: url, title: title, lastVisit: now.addingTimeInterval(-minutesAgo * 60), visitCount: 1)
    }

    /// Arc 1.172.2's hosts: Linear, Notion (its app and its public sites), Figma, and Confluence on
    /// atlassian.net's wiki. Notion Calendar and Jira are other things.
    static let sites: [(String, RecentPagesPreview.Site?)] = [
        ("https://linear.app/cra/inbox", .linear),
        ("https://www.notion.so/cra/Roadmap-0123", .notion),
        ("https://notion.so/", .notion),
        ("https://app.notion.com/p/abc", .notion),
        ("https://cra.notion.site/Changelog-1", .notion),
        ("https://www.figma.com/files/team/1/recents-and-sharing", .figma),
        ("https://figma.com/design/KEY/Sidebar", .figma),
        ("https://acme.atlassian.net/wiki/spaces/ENG/overview", .confluence),
        ("https://acme.atlassian.net/wiki", .confluence),
        ("https://acme.atlassian.net/jira/software/projects/ENG/boards/1", nil),
        ("https://acme.atlassian.net/wikipedia", nil),
        ("https://calendar.notion.so/", nil),
        ("https://notion.example.com/", nil),
        ("https://mail.google.com/mail/u/0/", nil),
        ("file:///Users/x/linear.app", nil),
    ]

    @Test(arguments: sites)
    func knowsTheSites(url: String, site: RecentPagesPreview.Site?) {
        #expect(RecentPagesPreview.site(for: url) == site)
    }

    @Test func listsTheSitesPagesNewestFirstWithoutTheFavoriteItself() {
        let history = [
            Self.entry("https://linear.app/cra/issue/CRA-12/sidebar-jumps", "CRA-12 Sidebar jumps", minutesAgo: 30),
            Self.entry("https://linear.app/cra/inbox", "Inbox", minutesAgo: 1),
            Self.entry("https://linear.app/cra/project/previews-1a2b", "Previews", minutesAgo: 5),
            Self.entry("https://www.figma.com/design/KEY/Sidebar", "Sidebar", minutesAgo: 2),
            Self.entry("https://example.com/", "Example", minutesAgo: 0),
        ]
        let pages = RecentPagesPreview.pages(for: "https://linear.app/cra/inbox/", history: history)
        #expect(pages.map(\.title) == ["Previews", "CRA-12 Sidebar jumps"])
        #expect(pages.first?.url == "https://linear.app/cra/project/previews-1a2b")
        #expect(pages.first?.lastVisit == Self.now.addingTimeInterval(-300))
    }

    /// A Figma file visited at several frames is one row, opening the latest; its title loses
    /// " – Figma" (Arc's tidy rules), and Recently Viewed is left out as in Arc.
    @Test func oneRowPerFigmaFileWithTidyTitles() {
        let history = [
            Self.entry("https://www.figma.com/design/KEY/Sidebar?node-id=1-2", "Sidebar – Figma", minutesAgo: 10),
            Self.entry("https://www.figma.com/design/KEY/Sidebar?node-id=4-7&t=x", "Sidebar – Figma", minutesAgo: 3),
            Self.entry("https://www.figma.com/files/recent", "Recently Viewed", minutesAgo: 1),
            Self.entry("https://www.figma.com/file/OLD/Icons", "Icons – Figma", minutesAgo: 60),
        ]
        let pages = RecentPagesPreview.pages(for: "https://www.figma.com/", history: history)
        #expect(pages.map(\.title) == ["Sidebar", "Icons"])
        #expect(pages.first?.url == "https://www.figma.com/design/KEY/Sidebar?node-id=4-7&t=x")
    }

    /// Notion's sign-in callbacks never show; a database item opened as a peek (`?p=`) is its own page.
    @Test func notionLeavesOutCallbacksAndKeepsPeekedPages() {
        let history = [
            Self.entry("https://www.notion.so/oauth2callback?code=1", "Notion", minutesAgo: 1),
            Self.entry("https://www.notion.so/samlauthcallback", "Notion", minutesAgo: 1),
            Self.entry("https://www.notion.so/cra/Tasks-abc?v=1&p=111&pm=s", "Fix sidebar", minutesAgo: 2),
            Self.entry("https://www.notion.so/cra/Tasks-abc?v=1", "Tasks", minutesAgo: 3),
            Self.entry("https://cra.notion.site/Changelog-1", "Changelog", minutesAgo: 4),
            Self.entry("https://calendar.notion.so/", "Notion Calendar", minutesAgo: 0),
        ]
        let pages = RecentPagesPreview.pages(for: "https://www.notion.so/cra", history: history)
        #expect(pages.map(\.title) == ["Fix sidebar", "Tasks", "Changelog"])
    }

    /// A Confluence favorite lists its own company's wiki, not another site's or Jira.
    @Test func confluenceStaysOnItsOwnWiki() {
        let history = [
            Self.entry("https://acme.atlassian.net/wiki/spaces/ENG/pages/1/Runbook", "Runbook", minutesAgo: 1),
            Self.entry("https://other.atlassian.net/wiki/spaces/X/pages/2/Secret", "Secret", minutesAgo: 1),
            Self.entry("https://acme.atlassian.net/browse/ENG-1", "ENG-1", minutesAgo: 1),
            Self.entry("https://acme.atlassian.net/wiki/pages/viewpage.action?pageId=7", "Old page", minutesAgo: 2),
            Self.entry("https://acme.atlassian.net/wiki/pages/viewpage.action?pageId=8", "Older page", minutesAgo: 3),
        ]
        let pages = RecentPagesPreview.pages(for: "https://acme.atlassian.net/wiki/home", history: history)
        #expect(pages.map(\.title) == ["Runbook", "Old page", "Older page"])
    }

    @Test func skipsUntitledPagesAndStopsAtTheLimit() {
        var history = [Self.entry("https://linear.app/cra/issue/CRA-1", "", minutesAgo: 0),
                       Self.entry("https://linear.app/cra/issue/CRA-2", "https://linear.app/cra/issue/CRA-2", minutesAgo: 0)]
        history += (1...30).map { Self.entry("https://linear.app/cra/issue/CRA-\($0 + 10)", "Issue \($0)", minutesAgo: Double($0)) }
        let pages = RecentPagesPreview.pages(for: "https://linear.app/cra", history: history)
        #expect(pages.count == RecentPagesPreview.limit)
        #expect(pages.first?.title == "Issue 1")
        #expect(RecentPagesPreview.pages(for: "https://example.com/", history: history).isEmpty)
    }

    /// Arc's empty lines and ＋ addresses, from its binary.
    @Test func arcsEmptyLinesAndNewPages() {
        #expect(RecentPagesPreview.Site.linear.emptyText == "Recent Linear projects and issues appear here.")
        #expect(RecentPagesPreview.Site.notion.emptyText == "Recent Notion docs appear here.")
        #expect(RecentPagesPreview.Site.figma.emptyText == "Recent Figma files appear here.")
        #expect(RecentPagesPreview.Site.confluence.emptyText == "Recent Confluence pages appear here.")
        #expect(RecentPagesPreview.Site.allCases.map(\.newURL) == ["https://linear.app/new", "https://notion.so/new", "https://figma.com/new", "https://confluence.new"])
    }

    /// The card a favorite or pinned tab gets, each behind its checkbox in Previews Settings….
    @Test func eachPreviewFollowsItsCheckbox() {
        var s = AppSettings()
        #expect(SidebarTabPreview.kind(for: "https://mail.google.com/mail/u/0/", settings: s) == .gmail)
        #expect(SidebarTabPreview.kind(for: "https://calendar.google.com/calendar/u/0/r", settings: s) == .calendar)
        #expect(SidebarTabPreview.kind(for: "https://www.figma.com/", settings: s) == .recentPages(.figma))
        #expect(SidebarTabPreview.kind(for: "https://example.com/", settings: s) == nil)
        s.recentPagesPreviews = false
        #expect(SidebarTabPreview.kind(for: "https://www.figma.com/", settings: s) == nil)
        #expect(SidebarTabPreview.kind(for: "https://mail.google.com/mail/u/0/", settings: s) == .gmail)
        s.favoritePreviews = false
        s.liveCalendar = false
        #expect(SidebarTabPreview.kind(for: "https://mail.google.com/mail/u/0/", settings: s) == nil)
        #expect(SidebarTabPreview.kind(for: "https://calendar.google.com/calendar/u/0/r", settings: s) == nil)
    }

    /// On by default, as in Arc; settings.json from before #376 loads with it on, and Off is kept.
    @Test func theSettingIsOnByDefaultAndSaved() throws {
        #expect(AppSettings().recentPagesPreviews)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).recentPagesPreviews)
        var off = AppSettings()
        off.recentPagesPreviews = false
        #expect(try !JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(off)).recentPagesPreviews)
    }
}
