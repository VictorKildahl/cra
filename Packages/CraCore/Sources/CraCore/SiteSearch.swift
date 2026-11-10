import Foundation

/// One of Chromium's search engines, as chrome://settings/searchEngines lists and edits them: a
/// row of the profile's `keywords` table (Web Data), or its default engine, which the profile's
/// `default_search_provider_data.template_url_data` pref holds once one is picked. Arc's command
/// bar is Chromium's omnibox, so the default searches what is typed and an active keyword takes
/// Tab; Cra kept an engine list of its own and ignored both (reported on X, 2 Nov 2026: custom
/// engines did nothing, nor did editing the built-in ones).
public struct ChromiumSearchEngine: Equatable, Sendable {
    public var id: Int64
    public var name: String
    public var keyword: String
    /// Chromium's template: `{searchTerms}` and its other placeholders.
    public var url: String
    public var suggestURL: String
    public var faviconURL: String
    /// Chromium's built-in engines have one (Google 1, Bing 3, DuckDuckGo 92…).
    public var prepopulateID: Int
    /// Chromium may replace it: built-in and auto-added rows, until the user edits them.
    public var safeForAutoreplace: Bool
    /// TemplateURLData::ActiveStatus: 0 unspecified, 1 active, 2 deactivated.
    public var isActive: Int
    /// @bookmarks, @history, @tabs, @gemini…: Chrome's own pages, which Cra has no use for.
    public var starterPackID: Int
    public var syncGUID: String

    public init(id: Int64 = 0, name: String, keyword: String, url: String, suggestURL: String = "", faviconURL: String = "",
                prepopulateID: Int = 0, safeForAutoreplace: Bool = false, isActive: Int = 1, starterPackID: Int = 0, syncGUID: String = "") {
        self.id = id
        self.name = name
        self.keyword = keyword
        self.url = url
        self.suggestURL = suggestURL
        self.faviconURL = faviconURL
        self.prepopulateID = prepopulateID
        self.safeForAutoreplace = safeForAutoreplace
        self.isActive = isActive
        self.starterPackID = starterPackID
        self.syncGUID = syncGUID
    }

    public func searchURL(_ query: String) -> String { Self.expand(url, query: query) }

    /// The engine's suggest endpoint for `query`, nil when it has none.
    public func suggestURL(_ query: String) -> URL? {
        // Google's own template asks for an answer behind an XSSI guard (`xssi=t`) and a session
        // only the omnibox has; its plain endpoint is the one Cra always used.
        let template = suggestURL.hasPrefix("{google:baseSuggestURL}") ? Self.googleSuggest : suggestURL
        return template.isEmpty ? nil : URL(string: Self.expand(template, query: query))
    }

    private static let googleSuggest = "https://www.google.com/complete/search?client=chrome&ie=utf-8&oe=utf-8&q={searchTerms}"

    /// The settings page's "Search engines" list, the ones the picker offers: Chromium's own and
    /// whichever is the default.
    public var isBuiltIn: Bool { prepopulateID > 0 }

    /// Tab on its keyword scopes the bar to it, as Chromium's keyword mode does: an engine the
    /// user added, edited or activated, or a built-in one; not the sites Chromium adds by itself
    /// as you browse (inactive until activated, Arc 1.170) or the starter pack.
    public var takesTab: Bool {
        starterPackID == 0 && isActive != 2 && (isActive == 1 || !safeForAutoreplace || prepopulateID > 0)
    }

    // MARK: Templates

    /// Google's own placeholders resolve to its host; Chrome fills the rest in from the browser's
    /// state (RLZ, field trials, the page's URL), which a search from the bar has none of.
    private static let fixed: [String: String] = [
        "searchTerms": "", "inputEncoding": "UTF-8", "outputEncoding": "UTF-8",
        "google:baseURL": "https://www.google.com/", "google:baseSuggestURL": "https://www.google.com/complete/",
        "google:suggestPath": "search", "google:suggestClient": "chrome",
    ]

    /// Chromium's TemplateURLRef replacement for a typed query: `{searchTerms}` is the query
    /// percent-encoded, `{language}` the first preferred language, the known Google ones their
    /// values, and every other placeholder, optional (`{startPage?}`) or not, nothing. A query
    /// parameter left without a value goes too.
    public static func expand(_ template: String, query: String, language: String = "en") -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out += rest[..<open]
            guard let close = rest[open...].firstIndex(of: "}") else { out += rest[open...]; rest = ""; break }
            let name = String(rest[rest.index(after: open)..<close])
            switch name {
            case "searchTerms": out += encode(query)
            case "language": out += language
            default: out += fixed[name] ?? ""
            }
            rest = rest[rest.index(after: close)...]
        }
        out += rest
        return tidyQuery(out)
    }

    /// Unreserved characters stay, everything else is %-encoded (a space as %20).
    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Drops what emptied placeholders leave in the query: "search?q=a&&gs_ri=&ie=UTF-8&" →
    /// "search?q=a&ie=UTF-8".
    private static func tidyQuery(_ url: String) -> String {
        guard let q = url.firstIndex(of: "?") else { return url }
        let hashAt = url[q...].firstIndex(of: "#") ?? url.endIndex
        let parts = url[url.index(after: q)..<hashAt].split(separator: "&", omittingEmptySubsequences: true).filter { !$0.hasSuffix("=") }
        let query = parts.joined(separator: "&")
        return String(url[..<q]) + (query.isEmpty ? "" : "?" + query) + url[hashAt...]
    }

    // MARK: The default engine pref

    /// `default_search_provider_data.template_url_data` (or its mirror) as Chromium writes it;
    /// nil when it holds no engine.
    public init?(templateURLData d: [String: Any]) {
        guard let name = d["short_name"] as? String, let keyword = d["keyword"] as? String, let url = d["url"] as? String,
              !name.isEmpty, !keyword.isEmpty, !url.isEmpty else { return nil }
        func int(_ key: String) -> Int { (d[key] as? Int) ?? (d[key] as? String).flatMap { Int($0) } ?? 0 }
        self.init(id: Int64(int("id")), name: name, keyword: keyword, url: url, suggestURL: d["suggestions_url"] as? String ?? "",
                  faviconURL: d["favicon_url"] as? String ?? "", prepopulateID: int("prepopulate_id"),
                  safeForAutoreplace: d["safe_for_autoreplace"] as? Bool ?? false, isActive: int("is_active"),
                  starterPackID: int("starter_pack_id"), syncGUID: d["synced_guid"] as? String ?? "")
    }

    /// What Cra writes to that pref to make this the default, in Chromium's own keys
    /// (TemplateURLDataToDictionary). Chromium finds the engine by its GUID and makes it the default.
    public var templateURLData: [String: Any] {
        var d: [String: Any] = [
            "short_name": name, "keyword": keyword, "url": url, "suggestions_url": suggestURL, "favicon_url": faviconURL,
            "prepopulate_id": prepopulateID, "safe_for_autoreplace": safeForAutoreplace, "is_active": isActive,
            "starter_pack_id": starterPackID, "input_encodings": ["UTF-8"], "alternate_urls": [String](),
            "date_created": "0", "last_modified": "0", "usage_count": 0,
        ]
        if id != 0 { d["id"] = String(id) }
        if !syncGUID.isEmpty { d["synced_guid"] = syncGUID }
        return d
    }

    // MARK: Cra's own list (settings.json `searchEngine`)

    /// What Cra's engine setting meant, as Chromium would hold it: the default until Chromium has
    /// one of its own, and the engine an older setting moves to Chromium (Kagi isn't built in).
    public init(_ legacy: SearchEngine) {
        switch legacy {
        case .google:
            self.init(name: "Google", keyword: "google.com", url: "{google:baseURL}search?q={searchTerms}&ie={inputEncoding}",
                      suggestURL: Self.googleSuggest,
                      faviconURL: "https://www.google.com/favicon.ico", prepopulateID: 1, safeForAutoreplace: true, isActive: 0)
        case .duckduckgo:
            self.init(name: "DuckDuckGo", keyword: "duckduckgo.com", url: "https://duckduckgo.com/?q={searchTerms}",
                      suggestURL: "https://duckduckgo.com/ac/?q={searchTerms}&type=list",
                      faviconURL: "https://duckduckgo.com/favicon.ico", prepopulateID: 92, safeForAutoreplace: true, isActive: 0)
        case .bing:
            self.init(name: "Microsoft Bing", keyword: "bing.com", url: "https://www.bing.com/search?q={searchTerms}",
                      suggestURL: "https://www.bing.com/osjson.aspx?query={searchTerms}",
                      faviconURL: "https://www.bing.com/favicon.ico", prepopulateID: 3, safeForAutoreplace: true, isActive: 0)
        case .kagi:
            self.init(name: "Kagi", keyword: "kagi.com", url: "https://kagi.com/search?q={searchTerms}",
                      suggestURL: "https://kagi.com/api/autosuggest?q={searchTerms}", faviconURL: "https://kagi.com/favicon.ico")
        }
    }

    /// The built-in row an older Cra setting means (same prepopulate id or keyword), else that
    /// setting as an engine of its own.
    public static func migrating(_ legacy: SearchEngine, among engines: [ChromiumSearchEngine]) -> ChromiumSearchEngine {
        let wanted = ChromiumSearchEngine(legacy)
        return engines.first { $0.prepopulateID > 0 && $0.prepopulateID == wanted.prepopulateID }
            ?? engines.first { $0.keyword.lowercased() == wanted.keyword }
            ?? wanted
    }
}

// MARK: A space's own engine (GitHub #306)

extension ChromiumSearchEngine {
    /// What a space's Search Engine menu offers: the profile's built-in engines and those the user
    /// added on the settings page, not the sites Chromium picks up while browsing or the starter
    /// pack. Before the profile's Web Data can be read, Cra's own list stands in.
    public static func spaceChoices(among engines: [ChromiumSearchEngine]) -> [ChromiumSearchEngine] {
        let picked = engines.filter { $0.starterPackID == 0 && $0.isActive != 2 && ($0.isBuiltIn || !$0.safeForAutoreplace) }
        return picked.isEmpty ? SearchEngine.allCases.map { ChromiumSearchEngine($0) } : picked
    }

    /// The engine typed text searches in a space: the space's own (`keyword`) where its profile
    /// has that engine, else the one Cra's list knows by that keyword, else the profile's default,
    /// which a space without one, or with an engine since removed, falls back to.
    public static func forSpace(keyword: String?, default fallback: ChromiumSearchEngine,
                                among engines: [ChromiumSearchEngine]) -> ChromiumSearchEngine {
        guard let wanted = keyword?.lowercased(), !wanted.isEmpty else { return fallback }
        if fallback.keyword.lowercased() == wanted { return fallback }
        return engines.first { $0.keyword.lowercased() == wanted && $0.starterPackID == 0 }
            ?? SearchEngine.allCases.map({ ChromiumSearchEngine($0) }).first { $0.keyword == wanted }
            ?? fallback
    }
}

/// What Tab scopes the command bar to on a site (Arc's Site Search): one of Arc's sites, or one
/// of Chromium's keywords.
public struct SiteSearch: Equatable, Sendable {
    public let name: String
    /// What the typed text has to start (Chromium's keyword).
    public let host: String
    /// `%s` (Arc's list) or Chromium's template.
    public let url: String
    /// The pill's colour, "#RRGGBB"; nil takes the space's, as the tabs scope does.
    public let color: String?

    public init(name: String, host: String, url: String, color: String?) {
        self.name = name
        self.host = host
        self.url = url
        self.color = color
    }

    public init(_ engine: ChromiumSearchEngine) {
        let arc = Self.all.first { $0.host == engine.keyword.lowercased() }
        self.init(name: engine.name, host: engine.keyword, url: engine.url, color: arc?.color)
    }

    public func searchURL(_ query: String) -> String {
        if url.contains("{") { return ChromiumSearchEngine.expand(url, query: query) }
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "&", with: "%26") ?? query
        return url.replacingOccurrences(of: "%s", with: q)
    }

    /// "twit" offers X (twitter.com) though it completes to twitch.tv; the completed host
    /// wins when it is a site search itself. Chromium's keywords come in around Arc's sites: one
    /// typed out in full wins ("goo" for a Google edited to that), one started only after Arc's
    /// sites have had their turn, and from two letters on.
    public static func match(_ q: String, completion: String?, keywords: [ChromiumSearchEngine] = []) -> SiteSearch? {
        var t = q.lowercased()
        if t.hasPrefix("www.") { t.removeFirst(4) }
        guard !t.isEmpty, !t.contains(" "), !t.contains("/") else { return nil }
        let offered = keywords.filter(\.takesTab)
        if let exact = offered.first(where: { $0.keyword.lowercased() == t }) { return SiteSearch(exact) }
        if let completion, let site = all.first(where: { $0.host == completion && $0.host.hasPrefix(t) }) { return site }
        if let site = all.first(where: { $0.host.hasPrefix(t) }) { return site }
        guard t.count >= 2 else { return nil }
        return offered.first { $0.keyword.lowercased().hasPrefix(t) }.map(SiteSearch.init)
    }

    /// Arc 1.170's list, in its order; colours measured off its pills.
    public static let all: [SiteSearch] = [
        SiteSearch(name: "Google Drive", host: "drive.google.com", url: "https://drive.google.com/drive/search?q=%s", color: "#0F9D58"),
        SiteSearch(name: "Gmail", host: "mail.google.com", url: "https://mail.google.com/mail/u/0/#search/%s", color: "#D44638"),
        SiteSearch(name: "Google Maps", host: "maps.google.com", url: "https://www.google.com/maps/search/%s", color: "#FBBC05"),
        SiteSearch(name: "Google Calendar", host: "calendar.google.com", url: "https://calendar.google.com/calendar/u/0/r/search?q=%s", color: "#9C27B0"),
        SiteSearch(name: "Google Docs", host: "docs.google.com", url: "https://docs.google.com/document/u/0/?q=%s", color: "#4285F4"),
        SiteSearch(name: "Dropbox", host: "dropbox.com", url: "https://www.dropbox.com/search/personal?&query=%s", color: "#007EE5"),
        SiteSearch(name: "Amazon", host: "amazon.com", url: "https://www.amazon.com/s?k=%s", color: "#FF9900"),
        SiteSearch(name: "GitHub", host: "github.com", url: "https://github.com/search?q=%s", color: "#743FC7"),
        SiteSearch(name: "Figma", host: "figma.com", url: "https://www.figma.com/files/search?q=%s", color: "#F24E1E"),
        SiteSearch(name: "X", host: "x.com", url: "https://x.com/search?q=%s", color: "#000000"),
        SiteSearch(name: "X", host: "twitter.com", url: "https://x.com/search?q=%s", color: "#000000"),
        SiteSearch(name: "YouTube", host: "youtube.com", url: "https://www.youtube.com/results?search_query=%s", color: "#FF0000"),
        SiteSearch(name: "Wikipedia", host: "wikipedia.org", url: "https://wikipedia.org/w/index.php?search=%s", color: "#FFA500"),
        SiteSearch(name: "Reddit", host: "reddit.com", url: "https://www.reddit.com/search/?q=%s", color: "#FF4500"),
        SiteSearch(name: "SoundCloud", host: "soundcloud.com", url: "https://soundcloud.com/search?q=%s", color: "#F85216"),
        SiteSearch(name: "Asana", host: "asana.com", url: "https://app.asana.com/0/search?q=%s", color: "#F06A6A"),
        SiteSearch(name: "LinkedIn", host: "linkedin.com", url: "https://linkedin.com/search/results/all/?keywords=%s", color: "#0B66C2"),
        SiteSearch(name: "Apple Music", host: "music.apple.com", url: "https://music.apple.com/us/search?term=%s", color: "#FA2A44"),
        SiteSearch(name: "Spotify", host: "spotify.com", url: "https://open.spotify.com/search/%s", color: "#1DB954"),
    ]
}
