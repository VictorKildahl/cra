import Foundation

/// The rows under the iPhone app's search field: what was typed, pages the phone knows that
/// match it, then the search engine's completions, four in all (Arc Search's count).
public enum MobileSuggestions {
    public struct Row: Equatable, Identifiable {
        public enum Kind: Equatable {
            /// Searches the default engine for `text`.
            case search
            /// Opens `text` as an address.
            case address
            /// A page the phone knows, shown by its title (`text`) and site icon.
            case site(url: String)
        }

        public var kind: Kind
        public var text: String
        /// How many leading characters of `text` the user typed. Arc Search draws them grey in a
        /// completion and leaves the row for the typed text itself all black.
        public var typedPrefixLength: Int

        public var id: String { "\(kind)|\(text)" }

        public init(kind: Kind, text: String, typedPrefixLength: Int = 0) {
            self.kind = kind
            self.text = text
            self.typedPrefixLength = typedPrefixLength
        }
    }

    /// A page the phone already knows (a favorite, an open or archived tab, a pinned tab from the
    /// Mac), offered as a row when what is typed matches it.
    public struct Site: Equatable {
        public var title: String
        public var url: String

        public init(title: String, url: String) {
            self.title = title
            self.url = url
        }
    }

    /// At most this many site rows, so the engine keeps at least two of the four.
    public static let maxSiteRows = 2

    /// The rows for `typed`: nothing for an empty field. Arc Search mixes site rows (icon and
    /// title, no "Browse for Me") above and below the typed text's row; here the site whose
    /// address starts with what was typed goes above it, as the likely destination, and a site
    /// matched by its title goes below. Then completions that differ from the typed text and from
    /// each other.
    public static func rows(typed: String, completions: [String], sites: [Site] = [],
                            limit: Int = MobileSearchSheet.visibleRows) -> [Row] {
        let query = typed.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let matches = siteMatches(typed: query, in: sites)
        let shown = Array((matches.byHost + matches.byTitle).prefix(min(maxSiteRows, max(0, limit - 1))))
        let siteRows = shown.map { Row(kind: .site(url: $0.url), text: title(of: $0)) }
        let typedRow = Row(kind: TypedURL.looksLikeURL(query) ? .address : .search, text: query)
        let leadsWithSite = !matches.byHost.isEmpty && !siteRows.isEmpty
        var rows = leadsWithSite ? [siteRows[0], typedRow] + siteRows.dropFirst() : [typedRow] + siteRows
        var seen: Set<String> = [query.lowercased()]
        for completion in completions {
            guard rows.count < limit else { break }
            let text = completion.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty, seen.insert(text.lowercased()).inserted else { continue }
            let typedLength = text.lowercased().hasPrefix(query.lowercased()) ? query.count : 0
            rows.append(Row(kind: .search, text: text, typedPrefixLength: typedLength))
        }
        return rows
    }

    /// The sites that match `typed`: those whose host starts with it (with or without "www."),
    /// and those with a title word starting with each typed word. Each group keeps `sites`'
    /// order, which is the caller's preference; a page listed twice counts once, and only web
    /// pages count.
    public static func siteMatches(typed: String, in sites: [Site]) -> (byHost: [Site], byTitle: [Site]) {
        let query = typed.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return ([], []) }
        let queryWords = words(query)
        var byHost: [Site] = []
        var byTitle: [Site] = []
        var seen: Set<String> = []
        for site in sites {
            guard let url = URL(string: site.url), let scheme = url.scheme?.lowercased(),
                  scheme == "https" || scheme == "http", let host = url.host?.lowercased(), !host.isEmpty,
                  seen.insert(pageKey(url, host: host)).inserted else { continue }
            if bare(host).hasPrefix(query) || host.hasPrefix(query) {
                byHost.append(site)
            } else if !queryWords.isEmpty {
                let titleWords = words(site.title.lowercased())
                if queryWords.allSatisfy({ word in titleWords.contains { $0.hasPrefix(word) } }) {
                    byTitle.append(site)
                }
            }
        }
        return (byHost, byTitle)
    }

    private static func title(of site: Site) -> String {
        let title = site.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? bare(URL(string: site.url)?.host ?? site.url) : title
    }

    private static func bare(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    private static func words(_ text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// One page whatever its scheme, "www.", trailing slash or fragment.
    private static func pageKey(_ url: URL, host: String) -> String {
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        return bare(host) + path + (url.query.map { "?" + $0 } ?? "")
    }

    /// Where a row goes: the address itself, or the engine's results for the text.
    public static func destination(for row: Row, engine: MobileSearchEngine) -> String {
        if case .site(let url) = row.kind { return url }
        return destination(forTyped: row.text, engine: engine, kind: row.kind)
    }

    /// Where the keyboard's Go key sends what was typed.
    public static func destination(forTyped typed: String, engine: MobileSearchEngine, kind: Row.Kind? = nil) -> String {
        let query = typed.trimmingCharacters(in: .whitespaces)
        let isAddress = kind.map { $0 == .address } ?? TypedURL.looksLikeURL(query)
        return isAddress ? TypedURL.fromInput(query) : engine.searchURL(query)
    }

    /// The completions in an OpenSearch suggest answer, `["query", ["one", "two", …], …]`, which
    /// Google, DuckDuckGo (`type=list`), Bing and Kagi all send. Google's `client=chrome` answer
    /// may open with `)]}'` and marks site suggestions NAVIGATION; those are left out, since the
    /// rows here are searches.
    public static func completions(fromOpenSearch data: Data) -> [String] {
        var body = data
        if let text = String(data: data, encoding: .utf8), text.hasPrefix(")]}'"),
           let stripped = text.dropFirst(4).data(using: .utf8) {
            body = stripped
        }
        guard let answer = try? JSONSerialization.jsonObject(with: body) as? [Any], answer.count > 1,
              let items = answer[1] as? [Any] else { return [] }
        let types = (answer.count > 4 ? answer[4] as? [String: Any] : nil)?["google:suggesttype"] as? [String] ?? []
        return items.enumerated().compactMap { index, item in
            guard let text = item as? String else { return nil }
            if index < types.count, types[index] == "NAVIGATION" { return nil }
            return text
        }
    }
}
