import Foundation

/// Which sites to ask for their icon (SiteIcon) in the background, for sidebar tabs, favorites and
/// command-bar rows that show a globe: rows on screen first, `cap` at a time, each site once a launch,
/// never from an incognito space. SiteIconLoader drives it: `want` per row, `next` until nil, `finished`.
public struct SiteIconQueue {
    /// A row that shows no icon, as its view knows it.
    public struct Row {
        public var url: String
        /// The key the row reads its icon under (a tab's `iconKey`, a suggestion's `faviconKey`).
        public var iconKey: String?
        /// A popular domain, typed address or search engine's suggestion in the command bar: a site the
        /// user may never have been to, which is never asked.
        public var preset: Bool
        /// On screen: in its list's clip view, in the space the window shows.
        public var visible: Bool
        public var incognito: Bool

        public init(url: String, iconKey: String?, preset: Bool = false, visible: Bool = true, incognito: Bool) {
            self.url = url
            self.iconKey = iconKey
            self.preset = preset
            self.visible = visible
            self.incognito = incognito
        }
    }

    /// A site to fetch: the favicon key it is stored under (the host, or a section of it such as
    /// "docs.google.com/spreadsheets", #909) and the page its icons are declared on.
    public struct Fetch: Equatable {
        public let host: String
        public let origin: URL
    }

    public let cap: Int
    private var asked: Set<String> = []
    private var visible: [Fetch] = []
    private var margin: [Fetch] = []
    private var inFlight: Set<String> = []

    public init(cap: Int = 3) { self.cap = cap }

    /// Queues the row's site when it may ask: not a preset, not from incognito, and read under a key of
    /// that site, so a custom icon or another site's never asks. A visible row goes before the rest. True while that site's fetch is still to come or running.
    @discardableResult
    public mutating func want(_ row: Row) -> Bool {
        // Rows ask on every redraw: a site asked before costs one address parse.
        guard !row.preset, !row.incognito, let host = Self.key(for: row) else { return false }
        let isVisible = row.visible
        guard !asked.contains(host) else {
            if isVisible, let i = margin.firstIndex(where: { $0.host == host }) { visible.append(margin.remove(at: i)) }
            return inFlight.contains(host) || visible.contains { $0.host == host } || margin.contains { $0.host == host }
        }
        guard let fetch = Self.fetch(for: row.url, host: host) else { return false }
        asked.insert(host)
        if isVisible { visible.append(fetch) } else { margin.append(fetch) }
        return true
    }

    /// The next site to fetch while fewer than `cap` run; it runs until `finished`.
    public mutating func next() -> Fetch? {
        guard inFlight.count < cap else { return nil }
        let fetch: Fetch
        if !visible.isEmpty { fetch = visible.removeFirst() } else if !margin.isEmpty { fetch = margin.removeFirst() } else { return nil }
        inFlight.insert(fetch.host)
        return fetch
    }

    /// A fetch ended, stored or not: its site is not asked again this launch.
    public mutating func finished(_ host: String) { inFlight.remove(host) }

    /// The key the row's icon is fetched for: what its key falls back to short of a tab's own (the host,
    /// or the section the row reads, #909), when that is a key of the row's host; nil otherwise.
    public static func key(for row: Row) -> String? {
        guard let host = FaviconKey.key(for: row.url), let iconKey = row.iconKey else { return nil }
        let site = FaviconKey.siteKey(of: iconKey)
        return FaviconKey.hostKey(of: site) == host ? site : nil
    }

    private static func fetch(for url: String, host key: String) -> Fetch? {
        guard var parts = URLComponents(string: url), let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = FaviconKey.key(for: url) else { return nil }
        parts.scheme = scheme
        parts.host = host
        parts.user = nil
        parts.password = nil
        // A section's page: "https://docs.google.com/spreadsheets" for "docs.google.com/spreadsheets", from the
        // address's own first segment, which the key may have shortened or had "#" and "/" replaced in.
        let segment = URLComponents(string: url)?.percentEncodedPath.split(separator: "/").first.map(String.init) ?? ""
        parts.percentEncodedPath = key.contains("/") && !segment.isEmpty ? "/" + segment : "/"
        parts.query = nil
        parts.fragment = nil
        return parts.url.map { Fetch(host: key, origin: $0) }
    }
}
