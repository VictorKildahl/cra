import Foundation

/// Arc Max's Tidy Tab Titles (renamePinnedTabs), done by the Mac's own Apple Intelligence model:
/// a tab pinned without a name of its own gets a short one ("Climate - BBC News" became "Climate
/// News", "Foundation Models | Apple Developer Documentation" "Foundation Models", live in Arc 1.171,
/// 4 Nov 2026). Arc keeps it as the tab's custom title. This decides what the model is asked and
/// which answers become names; the model call and the animation are the app's.
public enum TidyTitles {
    static let maximumLength = 40

    public static let instructions = """
    You rename browser tabs in a sidebar so they are short and tidy, the way a person renames a \
    bookmark. Keep what the page is about and drop the website's name, slogans, unread counts and \
    separators. Use one to four words in the page title's own language, no quotes and no emoji. \
    For a site's home page, dashboard or inbox, use the site's name.
    """

    /// Pairs Arc's own renames made (Victor's Arc, 4 Nov 2026): the model copies their style.
    public static let examples: [(page: String, site: String, title: String)] = [
        ("IT Career Paths - IT General - Confluence", "atlassian.net", "IT Career Paths"),
        ("Personal apps | Heroku", "dashboard.heroku.com", "Heroku"),
        ("Climate - BBC News", "bbc.com", "Climate News"),
        ("Convert SVG to PNG - SVG Viewer", "svgviewer.dev", "SVG to PNG"),
        ("Deltagere ‹ Grønne tanker — WordPress", "groenne.dk", "Grønne tanker"),
        ("Free Backlink Checker by Ahrefs: Check Backlinks to Any Site", "ahrefs.com", "Ahrefs"),
    ]

    /// The request: the page's title and site.
    public static func prompt(title: String, url: String) -> String {
        var lines = ["Examples:"]
        for e in examples { lines.append("\"\(e.page)\" (\(e.site)) → \(e.title)") }
        lines.append("")
        lines.append("Rename this tab: \"\(clip(title, 200))\" (\(host(url)))")
        return lines.joined(separator: "\n")
    }

    /// The model's answer as a name, or nil when it isn't one worth using: empty, no shorter than
    /// the title shown now, or the same words.
    public static func clean(_ answer: String, shown: String) -> String? {
        var s = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        s = s.trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’«»`.")))
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !s.isEmpty, s.count <= maximumLength else { return nil }
        let a = s.lowercased(), b = shown.trimmingCharacters(in: .whitespaces).lowercased()
        guard a != b, s.count < shown.count else { return nil }
        return s
    }

    static func host(_ url: String) -> String {
        guard let h = URL(string: url)?.host?.lowercased() else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    static func clip(_ s: String, _ n: Int) -> String {
        s.count <= n ? s : String(s.prefix(n))
    }
}
