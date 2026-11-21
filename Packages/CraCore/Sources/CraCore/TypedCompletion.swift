import Foundation

/// What ⌘T completes a site's name to (GitHub #667): the address typed most on that site, as Arc's
/// omnibox (Chromium's history matching) does. Chromium weighs how often an address was typed
/// (History's typed_count), not only how often it was visited, and prefers a site's shortest address.
/// With many YouTube videos open, "youtube" completed to one of the videos in Cra and Return switched to
/// it; Arc completes to youtube.com, typed hundreds of times. Nothing typed on the site leaves the
/// completion to the other rows, an open tab first (Arc 1.171's semrush copy, CommandBarDedupe).
public enum TypedCompletion {
    /// A visited page with how often its address was entered in the command bar.
    public struct Page: Equatable, Sendable {
        public let url: String
        public let typedCount: Int
        /// Host and port, lowercased, without `www.`: what the typed text is matched against.
        let site: String
        /// The address as the bar completes to it: no scheme, `www.` or trailing slash.
        let address: String

        public init?(url: String, typedCount: Int) {
            guard let c = URLComponents(string: url), var host = c.host?.lowercased(), !host.isEmpty else { return nil }
            if host.hasPrefix("www.") { host.removeFirst(4) }
            self.url = url
            self.typedCount = typedCount
            site = c.port.map { "\(host):\($0)" } ?? host
            address = CommandBarDedupe.completionAddress(url)
        }
    }

    /// The page an inline completion of `query` leads with, and the text it completes to: of the sites
    /// whose name starts with the query, the one typed most across its pages, and on it the shortest
    /// address typed (the more typed of two as short). nil when nothing on such a site was typed.
    public static func lead(for query: String, pages: [Page]) -> (url: String, completion: String)? {
        let q = query.lowercased()
        let www = q.hasPrefix("www.")
        let name = www ? String(q.dropFirst(4)) : q
        guard name.count >= 2, !name.contains(" "), !name.contains("/") else { return nil }
        var typed: [String: Int] = [:]
        for p in pages where p.typedCount > 0 && p.site.hasPrefix(name) { typed[p.site, default: 0] += p.typedCount }
        guard let site = typed.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key })?.key else { return nil }
        let best = pages.filter { $0.site == site && $0.typedCount > 0 }.min { a, b in
            if a.address.count != b.address.count { return a.address.count < b.address.count }
            if a.typedCount != b.typedCount { return a.typedCount > b.typedCount }
            return a.address < b.address
        }
        guard let best else { return nil }
        let completion = (www ? "www." : "") + best.address
        guard completion.count > q.count, completion.hasPrefix(q) else { return nil }
        return (best.url, completion)
    }

    /// The history address an entry in the bar is counted under: a bare host gets the "/" its page
    /// loads at, as Chromium records it, so "youtube.com" counts for https://youtube.com/.
    public static func key(_ url: String) -> String {
        guard var c = URLComponents(string: url), c.host != nil, c.path.isEmpty else { return url }
        c.path = "/"
        return c.string ?? url
    }
}
