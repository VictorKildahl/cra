import Foundation

/// The command bar lists a page once. Rows name the same page when their addresses match without
/// `www.` and a trailing slash, or, for sites whose pages share titles, when host and title match
/// (Arc's dedupByTitleAndHostList). Of such rows the open tab's stays, so Return switches to the
/// tab instead of opening the page again, and it lists with the best score among them. Reported
/// on X, 1 Nov 2026: a pinned YouTube tab lost its row to a YouTube history entry that had more
/// visits, and Return opened a new tab. Arc 1.171, offline copy with injected history, 2 Nov 2026:
/// "semrush" listed the pinned tab at www.semrush.com/projects/ and hid the history entries for
/// semrush.com/projects/ and www.semrush.com/projects (more visits, other titles), while
/// www.semrush.com/analytics/ stayed.
public enum CommandBarDedupe {
    /// Arc's command_bar_behavior.json: dedupByTitleAndHostList.
    public static let titleAndHostHosts: Set<String> = [
        "figma.com", "www.figma.com", "notion.so", "www.notion.so", "github.com", "zoom.us", "maps.google.com",
        "console.cloud.google.com", "app.slack.com", "linear.app", "www.youtube.com", "docs.google.com", "mail.google.com",
    ]

    /// The address rows are compared by: no `www.`, no trailing slash, the host lowercased.
    public static func comparableURL(_ url: String) -> String {
        guard var c = URLComponents(string: url), let host = c.host?.lowercased() else { return url }
        c.host = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if c.path.hasSuffix("/") { c.path.removeLast() }
        return c.string ?? url
    }

    /// What an open tab completes the typed text to (Arc): its address without the scheme,
    /// `www.` and a trailing slash, "semrush.com/projects".
    public static func completionAddress(_ url: String) -> String {
        var s = comparableURL(url)
        if let r = s.range(of: "://") { s = String(s[r.upperBound...]) }
        return s
    }

    /// The keys a row matches others by. Commands and rows without an address keep their `id`.
    public static func keys(id: String, url: String?, title: String) -> [String] {
        guard let url, let host = URL(string: url)?.host?.lowercased() else { return [id] }
        let page = comparableURL(url)
        return titleAndHostHosts.contains(host) ? [page, "\(host)|\(title.lowercased())"] : [page]
    }

    public struct Row: Equatable {
        public let keys: [String]
        public let score: Double
        public let isOpenTab: Bool

        public init(keys: [String], score: Double, isOpenTab: Bool) {
            self.keys = keys
            self.score = score
            self.isOpenTab = isOpenTab
        }
    }

    /// The rows kept, as indices into `rows` with the score each lists with, best first (rows
    /// with equal scores in the order given). Rows sharing any key are one page.
    public static func kept(_ rows: [Row]) -> [(index: Int, score: Double)] {
        // Union rows that share a key; the group's root is its first row.
        var parent = Array(rows.indices)
        func root(_ i: Int) -> Int {
            var i = i
            while parent[i] != i { parent[i] = parent[parent[i]]; i = parent[i] }
            return i
        }
        var byKey: [String: Int] = [:]
        for (i, row) in rows.enumerated() {
            for k in row.keys {
                if let j = byKey[k] {
                    let (a, b) = (root(i), root(j))
                    if a != b { parent[max(a, b)] = min(a, b) }
                } else {
                    byKey[k] = i
                }
            }
        }
        var best: [Int: (index: Int, score: Double)] = [:]
        var order: [Int] = []
        for (i, row) in rows.enumerated() {
            let g = root(i)
            guard let held = best[g] else {
                best[g] = (i, row.score)
                order.append(g)
                continue
            }
            let current = rows[held.index]
            let wins = row.isOpenTab != current.isOpenTab ? row.isOpenTab : row.score > current.score
            best[g] = (wins ? i : held.index, max(held.score, row.score))
        }
        return order.enumerated().map { (offset: $0.offset, kept: best[$0.element]!) }
            .sorted { a, b in a.kept.score != b.kept.score ? a.kept.score > b.kept.score : a.offset < b.offset }
            .map(\.kept)
    }
}
