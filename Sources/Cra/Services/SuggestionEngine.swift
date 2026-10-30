import Foundation

enum CommandBarMode: Equatable {
    /// ⌘T: commit creates a new tab in the current space.
    case newTab
    /// ⌘L: commit navigates the current tab.
    case editURL
}

enum SuggestionKind: Equatable {
    case switchToTab(UUID)
    case archived(UUID)
    case history
    case navigate
    case search
    case topDomain
    case command(String)
    case switchSpace(UUID)
    case moveToSpace(UUID)
    case moveToFolder(UUID)
}

struct Suggestion: Identifiable, Equatable {
    let id: String
    let kind: SuggestionKind
    let title: String
    let subtitle: String
    let url: String?
    let faviconKey: String?
    let symbol: String?
    let trailing: String?
    var score: Double
    var spaceID: UUID? = nil
    /// Matched only as scattered letters ("pota" in "grænselandsPOrTAl"): listed after the
    /// search engine's suggestions, which Arc shows instead of such matches.
    var loose = false
    var tabID: UUID? {
        if case .switchToTab(let id) = kind { return id }
        return nil
    }
}

struct SuggestionResult {
    var items: [Suggestion] = []
    /// Host (or more) to complete the typed text to, e.g. "github.com".
    var inlineCompletion: String?
    /// The site Tab scopes the bar to ("Search YouTube  Tab").
    var siteSearch: SiteSearch?
    var query: String = ""
}

/// What makes ⌘T feel like Arc: open tabs, archived tabs, history, the
/// typed URL or search, popular domains and commands, ranked with
/// recency/frequency/learned signals (Arc: CommandBarRanking*).
@MainActor
final class SuggestionEngine {
    unowned let store: SidebarStore
    unowned let bindings: KeyBindingRegistry
    private let remote = SearchSuggestions()
    /// Arc's command bar always lists five rows; search suggestions make up what the
    /// tabs, history and commands don't fill, so the bar keeps its height while you type.
    static let maxRows = 5

    init(store: SidebarStore, bindings: KeyBindingRegistry) {
        self.store = store
        self.bindings = bindings
    }

    // MARK: Entry

    func suggestions(for rawQuery: String, mode: CommandBarMode, currentTabID: UUID?) -> SuggestionResult {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        let q = query.lowercased()
        var result = SuggestionResult(query: query)
        if q.isEmpty {
            result.items = Array(recentSuggestions(excluding: currentTabID).prefix(Self.maxRows))
            return result
        }

        var items: [Suggestion] = []
        let typed = typedRow(query: query)
        items.append(contentsOf: tabSuggestions(q, excluding: currentTabID))
        // Incognito: the window's own tabs, search and commands; nothing from the normal profile.
        if !incognito {
            items.append(contentsOf: archiveSuggestions(q))
            items.append(contentsOf: historySuggestions(q, openURLs: searchIndex.openURLs))
            items.append(contentsOf: topDomainSuggestions(q))
        }
        items.append(contentsOf: commandSuggestions(q, currentTabID: currentTabID))

        // Learned: the user picked this URL for this query before.
        if let learned = store.ranking.queriesToSelected[q] {
            for i in items.indices where items[i].url == learned { items[i].score += 150 }
        }

        items = dedupe(items)
        // Stable: equal scores keep their order (tabs, archive, history, domains, then commands
        // in menu order), so "clear" lists Clear Cache before Clear Cookies, as Arc does.
        items = items.enumerated().sorted { a, b in
            a.element.score != b.element.score ? a.element.score > b.element.score : a.offset < b.offset
        }.map(\.element)

        // Arc's order: the row that supplies the inline completion comes first,
        // then what you typed, then everything else.
        let completion = inlineCompletion(q, candidates: items)
        if let completion, let idx = items.firstIndex(where: { $0.id == completion.candidateID }) {
            let c = items.remove(at: idx)
            items.insert(c, at: 0)
            items.insert(typed, at: 1)
        } else if let top = items.first, case .command = top.kind, top.score >= 68 {
            // Arc 1.171 lists a command the text names above it too: "sett" → Settings,
            // "clear" → Clear Cache and Refresh, "clear cook" → Clear Cookies and Refresh.
            items.insert(typed, at: 1)
        } else {
            items.insert(typed, at: 0)
        }
        if store.settings.searchSuggestions {
            let at = items.firstIndex(where: \.loose) ?? items.count
            if at < Self.maxRows {
                items.insert(contentsOf: searchSuggestions(query, after: items).prefix(Self.maxRows - at), at: at)
            }
        }
        result.items = Array(items.prefix(Self.maxRows))
        result.inlineCompletion = completion?.text
        result.siteSearch = SiteSearch.match(q, completion: completion?.text)
        return result
    }

    /// The bar scoped to a site (after Tab): one row, the typed text searched there.
    func suggestions(for rawQuery: String, in site: SiteSearch) -> SuggestionResult {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        var result = SuggestionResult(query: query)
        guard !query.isEmpty else { return result }
        result.items = [Suggestion(id: "typed", kind: .search, title: query, subtitle: "Search \(site.name)", url: site.searchURL(query),
                                   faviconKey: nil, symbol: "magnifyingglass", trailing: nil, score: 1000)]
        return result
    }

    // MARK: Search index

    /// What scoring needs from a title and a URL. Worked out per keystroke for every tab,
    /// archived tab and history entry (a URL parse each) it held up typing in the command bar.
    struct Searchable {
        let title: String
        let words: [Substring]
        let url: String
        let host: String
        let bareHost: String

        init(title: String, url: String) {
            self.title = title.lowercased()
            words = self.title.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            self.url = SuggestionEngine.humanURL(url).lowercased()
            host = (URL(string: url)?.host ?? "").lowercased()
            bareHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    private struct SearchIndex {
        var tabs: [(SidebarItem, Searchable)] = []
        var archive: [(ArchivedItem, Searchable)] = []
        var history: [(HistoryEntry, Searchable)] = []
        var openURLs: Set<String> = []
    }

    private var index: SearchIndex?

    /// Built on the first keystroke after the command bar opens, kept until it closes.
    private var searchIndex: SearchIndex {
        if let index { return index }
        var i = SearchIndex()
        let tabs = store.profileTabs(window: nil)
        i.tabs = tabs.compactMap { tab in tab.tab.map { (tab, Searchable(title: tab.displayTitle, url: $0.url)) } }
        i.openURLs = Set(tabs.compactMap { $0.tab?.url })
        i.archive = store.archive.prefix(400).compactMap { e in e.item.tab.map { (e, Searchable(title: e.item.displayTitle, url: $0.url)) } }
        i.history = store.history.values.map { ($0, Searchable(title: $0.title, url: $0.url)) }
        index = i
        return i
    }

    /// The command bar opened or closed: what it searches may have changed since.
    func resetIndex() {
        index = nil
        remote.reset()
    }

    /// Asks the search engine about `rawQuery`; `done` runs when its answer is in, to list again.
    func fetchSearchSuggestions(for rawQuery: String, done: @escaping @MainActor () -> Void) {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        guard store.settings.searchSuggestions, !query.isEmpty, !query.contains("://") else { return }
        remote.fetch(query, engine: store.settings.searchEngine, done: done)
    }

    /// The engine's suggestions not already listed, as search rows (or site rows).
    private func searchSuggestions(_ query: String, after items: [Suggestion]) -> [Suggestion] {
        let engine = store.settings.searchEngine
        let titles = Set(items.map { $0.title.lowercased() })
        let urls = Set(items.compactMap(\.url))
        return remote.items(for: query, engine: engine).compactMap { r in
            let t = r.text.lowercased()
            guard t != query.lowercased(), !titles.contains(t) else { return nil }
            guard let url = r.url else {
                return Suggestion(id: "sugg:\(t)", kind: .search, title: r.text, subtitle: "", url: engine.searchURL(r.text),
                                  faviconKey: nil, symbol: "magnifyingglass", trailing: nil, score: 0)
            }
            guard !urls.contains(url) else { return nil }
            return Suggestion(id: "sugg:\(url)", kind: .history, title: r.text, subtitle: "", url: url,
                              faviconKey: FaviconCache.key(for: url), symbol: "globe", trailing: nil, score: 0)
        }
    }

    // MARK: Typed text

    static func looksLikeURL(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.contains(" ") { return false }
        if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*://"#, options: .regularExpression) != nil { return true }
        if t.hasPrefix("localhost") || t.hasPrefix("about:") || t.hasPrefix("view-source:") || t.hasPrefix("data:") || t.hasPrefix("file:") { return true }
        if t.range(of: #"^(\d{1,3}\.){3}\d{1,3}(:\d+)?(/.*)?$"#, options: .regularExpression) != nil { return true }
        // host.tld[:port][/path]
        return t.range(of: #"^[\w\-]+(\.[\w\-]+)+(:\d+)?(/\S*)?$"#, options: .regularExpression) != nil
    }

    static func urlFromInput(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.range(of: #"^[a-zA-Z][a-zA-Z0-9+.\-]*:"#, options: .regularExpression) != nil { return t }
        if t.hasPrefix("localhost") || t.range(of: #"^(\d{1,3}\.){3}\d{1,3}"#, options: .regularExpression) != nil {
            return "http://" + t
        }
        return "https://" + t
    }

    private func typedRow(query: String) -> Suggestion {
        if Self.looksLikeURL(query) {
            let url = Self.urlFromInput(query)
            return Suggestion(id: "typed", kind: .navigate, title: query, subtitle: "Open URL", url: url,
                              faviconKey: FaviconCache.key(for: url), symbol: "globe", trailing: nil, score: 1000)
        }
        let engine = store.settings.searchEngine
        return Suggestion(id: "typed", kind: .search, title: query, subtitle: "Search \(engine.label)",
                          url: engine.searchURL(query), faviconKey: nil, symbol: "magnifyingglass", trailing: nil, score: 1000)
    }

    // MARK: Sources

    /// The command bar is open in an incognito window (it acts on the window in use).
    private var incognito: Bool { store.window().isIncognito }

    private func tabSuggestions(_ q: String, excluding current: UUID?) -> [Suggestion] {
        var out: [Suggestion] = []
        for (tab, key) in searchIndex.tabs where tab.id != current {
            guard let t = tab.tab else { continue }
            var score = Self.score(q, key)
            let loose = score < Self.looseBelow && !(tab.title?.lowercased().hasPrefix(q) ?? false)
            if let custom = tab.title?.lowercased(), custom.hasPrefix(q) { score += 40 }
            if score < 30 { continue }
            score += recencyBoost(t.timeLastActiveAt)
            let switches = store.ranking.recentlySwitchedToTabs[tab.id]?.filter { $0 > Date().addingTimeInterval(-7 * 86400) }.count ?? 0
            score += Double(min(switches, 10)) * 3
            let sid = store.spaceID(ofItem: tab.id)
            let spaceName = sid.flatMap { store.space($0)?.title } ?? ""
            let pinned = store.isPinned(tab.id)
            out.append(Suggestion(id: "tab:\(tab.id)", kind: .switchToTab(tab.id), title: tab.displayTitle,
                                  subtitle: [spaceName, pinned ? "Pinned" : "", Self.humanURL(t.url)].filter { !$0.isEmpty }.joined(separator: " · "),
                                  url: t.url, faviconKey: t.faviconKey, symbol: nil, trailing: "Switch to Tab", score: score, spaceID: sid, loose: loose))
        }
        return out
    }

    /// Below this a text score means only scattered letters matched (`fuzzy`).
    private static let looseBelow = 50.0

    private func archiveSuggestions(_ q: String) -> [Suggestion] {
        var out: [Suggestion] = []
        for (entry, key) in searchIndex.archive {
            guard let t = entry.item.tab else { continue }
            let text = Self.score(q, key)
            var score = text * 0.85
            if score < 30 { continue }
            score += recencyBoost(entry.archivedAt) * 0.5
            let spaceName = entry.sourceSpaceID.flatMap { store.space($0)?.title } ?? ""
            out.append(Suggestion(id: "arch:\(entry.id)", kind: .archived(entry.id), title: entry.item.displayTitle,
                                  subtitle: ["Archived \(Self.relative(entry.archivedAt))", spaceName, Self.humanURL(t.url)].filter { !$0.isEmpty }.joined(separator: " · "),
                                  url: t.url, faviconKey: t.faviconKey, symbol: nil, trailing: "Restore", score: score,
                                  loose: text < Self.looseBelow))
        }
        return out
    }

    private func historySuggestions(_ q: String, openURLs: Set<String>) -> [Suggestion] {
        var out: [Suggestion] = []
        for (h, key) in searchIndex.history where !openURLs.contains(h.url) {
            let text = Self.score(q, key)
            var score = text * 0.8
            if score < 30 { continue }
            score += min(Double(h.visitCount), 20) * 1.5 + recencyBoost(h.lastVisit) * 0.6
            out.append(Suggestion(id: "hist:\(h.url)", kind: .history, title: h.title.isEmpty ? Self.humanURL(h.url) : h.title,
                                  subtitle: Self.humanURL(h.url), url: h.url, faviconKey: FaviconCache.key(for: h.url),
                                  symbol: "clock", trailing: nil, score: score, loose: text < Self.looseBelow))
        }
        return out
    }

    private func topDomainSuggestions(_ q: String) -> [Suggestion] {
        guard !q.contains(" ") else { return [] }
        var out: [Suggestion] = []
        for (i, d) in PopularDomains.list.enumerated() {
            let bare = d.hasPrefix("www.") ? String(d.dropFirst(4)) : d
            guard bare.hasPrefix(q) || d.hasPrefix(q) else { continue }
            let url = "https://\(d)/"
            out.append(Suggestion(id: "top:\(d)", kind: .topDomain, title: bare, subtitle: "Open URL", url: url,
                                  faviconKey: FaviconCache.key(for: url), symbol: "globe", trailing: nil,
                                  score: 72 - Double(i) * 0.1))
        }
        return out
    }

    private func commandSuggestions(_ q: String, currentTabID: UUID?) -> [Suggestion] {
        guard q.count >= 2 else { return [] }
        var out: [Suggestion] = []
        func nameScore(_ name: String, triggers: [String]) -> Double {
            let n = name.lowercased()
            if n.hasPrefix(q) { return 80 }
            if n.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 68 }
            if triggers.contains(where: { $0.hasPrefix(q) }) { return 70 }
            if n.contains(q) { return 50 }
            return 0
        }
        for a in bindings.actions where a.inCommandBar {
            var s = nameScore(a.name, triggers: a.triggers)
            guard s > 0 else { continue }
            s += Double(min(store.ranking.commandUsage[a.id] ?? 0, 10)) * 2
            out.append(Suggestion(id: "cmd:\(a.id)", kind: .command(a.id), title: a.name, subtitle: "Command",
                                  url: nil, faviconKey: nil, symbol: a.symbol ?? "command", trailing: a.primary?.display, score: s))
        }
        for space in incognito ? [] : store.orderedSpaces {
            let s = nameScore("Switch to \(space.title)", triggers: [space.title.lowercased()])
            if s > 0 && space.id != store.focusedSpaceID {
                out.append(Suggestion(id: "space:\(space.id)", kind: .switchSpace(space.id), title: "Switch to \(space.title)",
                                      subtitle: "Space", url: nil, faviconKey: nil, symbol: nil, trailing: space.emoji, score: s))
            }
            if currentTabID != nil, space.id != store.focusedSpaceID {
                let m = nameScore("Move Tab to \(space.title)", triggers: ["move"])
                if m > 0 {
                    out.append(Suggestion(id: "move:\(space.id)", kind: .moveToSpace(space.id), title: "Move Tab to \(space.title)",
                                          subtitle: "Space", url: nil, faviconKey: nil, symbol: "arrow.right.square", trailing: space.emoji, score: m - 5))
                }
            }
        }
        if currentTabID != nil {
            for f in store.children(of: store.focusedSpace.pinnedContainerID) where f.isFolder && !f.isLiveFolder {
                let name = f.title ?? "Folder"
                let m = nameScore("Move Tab to Folder \(name)", triggers: [name.lowercased()])
                if m > 0 {
                    out.append(Suggestion(id: "folder:\(f.id)", kind: .moveToFolder(f.id), title: "Move Tab to \(name)",
                                          subtitle: "Folder", url: nil, faviconKey: nil, symbol: "folder", trailing: nil, score: m - 5))
                }
            }
        }
        return out
    }

    private func recentSuggestions(excluding current: UUID?) -> [Suggestion] {
        let tabs = store.profileTabs(window: nil).filter { $0.id != current }
            .sorted { ($0.tab?.timeLastActiveAt ?? .distantPast) > ($1.tab?.timeLastActiveAt ?? .distantPast) }
            .prefix(7)
        var out: [Suggestion] = tabs.map { tab in
            let sid = store.spaceID(ofItem: tab.id)
            return Suggestion(id: "tab:\(tab.id)", kind: .switchToTab(tab.id), title: tab.displayTitle,
                              subtitle: [sid.flatMap { store.space($0)?.title } ?? "", Self.humanURL(tab.tab?.url ?? "")].filter { !$0.isEmpty }.joined(separator: " · "),
                              url: tab.tab?.url, faviconKey: tab.tab?.faviconKey, symbol: nil, trailing: "Switch to Tab", score: 0, spaceID: sid)
        }
        for entry in store.archive.prefix(incognito ? 0 : 2) {
            guard let t = entry.item.tab else { continue }
            out.append(Suggestion(id: "arch:\(entry.id)", kind: .archived(entry.id), title: entry.item.displayTitle,
                                  subtitle: "Archived \(Self.relative(entry.archivedAt))", url: t.url, faviconKey: t.faviconKey,
                                  symbol: nil, trailing: "Restore", score: 0))
        }
        return out
    }

    // MARK: Scoring

    /// 0...100 from how well the query matches a title and a URL.
    func textScore(_ q: String, title: String, url: String) -> Double {
        Self.score(q, Searchable(title: title, url: url))
    }

    private static func score(_ q: String, _ key: Searchable) -> Double {
        let t = key.title, u = key.url, host = key.host, bareHost = key.bareHost
        var score = 0.0
        let tokens = q.split(separator: " ").map(String.init)
        if tokens.count > 1 {
            let hay = t + " " + u
            let hits = tokens.filter { hay.contains($0) }.count
            if hits == tokens.count { score = 75 } else if hits > 0 { score = 30 * Double(hits) / Double(tokens.count) }
            if t.hasPrefix(q) { score = 95 }
            return score
        }
        if t.hasPrefix(q) { score = 100 }
        else if key.words.contains(where: { $0.hasPrefix(q) }) { score = 85 }
        else if t.contains(q) { score = 65 }
        else if let f = fuzzy(q, in: t) { score = 25 + 25 * f }
        if bareHost.hasPrefix(q) || host.hasPrefix(q) { score = max(score, 95) }
        else if bareHost.contains(q) { score = max(score, 70) }
        else if u.contains(q) { score = max(score, 55) }
        return score
    }

    /// Subsequence match quality (0...1) or nil when not a subsequence.
    private static func fuzzy(_ q: String, in text: String) -> Double? {
        guard q.count >= 3 else { return nil }
        var it = text.makeIterator()
        var matched = 0
        var gaps = 0
        var inGap = false
        for c in q {
            var found = false
            while let x = it.next() {
                if x == c { found = true; break }
                inGap = true
            }
            if !found { return nil }
            if inGap { gaps += 1; inGap = false }
            matched += 1
        }
        return max(0, 1 - Double(gaps) / Double(q.count))
    }

    private func recencyBoost(_ date: Date?) -> Double {
        guard let date else { return 0 }
        let age = Date().timeIntervalSince(date)
        if age < 600 { return 30 }
        if age < 3600 { return 22 }
        if age < 86400 { return 14 }
        if age < 7 * 86400 { return 7 }
        return 0
    }

    /// Arc dedups by title+host for sites whose tabs share titles
    /// (command_bar_behavior.json: dedupByTitleAndHostList).
    private static let dedupHosts: Set<String> = ["figma.com", "www.figma.com", "notion.so", "www.notion.so", "github.com",
                                                   "zoom.us", "maps.google.com", "console.cloud.google.com", "app.slack.com",
                                                   "linear.app", "www.youtube.com", "docs.google.com", "mail.google.com"]

    private func dedupe(_ items: [Suggestion]) -> [Suggestion] {
        var seen: Set<String> = []
        var out: [Suggestion] = []
        for s in items.sorted(by: { $0.score > $1.score }) {
            var key = s.id
            if let url = s.url, let host = URL(string: url)?.host?.lowercased() {
                key = Self.dedupHosts.contains(host) ? "\(host)|\(s.title.lowercased())" : url
                if case .command = s.kind { key = s.id }
            }
            if seen.insert(key).inserted { out.append(s) }
        }
        return out
    }

    private func inlineCompletion(_ q: String, candidates: [Suggestion]) -> (text: String, candidateID: String)? {
        guard !q.contains(" "), q.count >= 2, !Self.looksLikeURL(q) || !q.contains("/") else { return nil }
        for c in candidates {
            guard let url = c.url, c.score >= 90 || c.kind == .topDomain, let host = URL(string: url)?.host?.lowercased() else { continue }
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if bare.hasPrefix(q) && bare != q { return (bare, c.id) }
            if host.hasPrefix(q) && host != q { return (host, c.id) }
        }
        return nil
    }

    // MARK: Formatting

    nonisolated static func humanURL(_ url: String) -> String {
        var s = url
        for p in ["https://www.", "http://www.", "https://", "http://"] where s.hasPrefix(p) { s = String(s.dropFirst(p.count)); break }
        if s.hasSuffix("/") { s.removeLast() }
        if s.count > 70 { s = String(s.prefix(67)) + "…" }
        return s
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

/// Arc's Site Search: the sites it seeds into Chromium's keyword table (active, not
/// auto-added), with the pill colour each one gets in the bar.
struct SiteSearch: Equatable {
    let name: String
    /// Chromium's keyword: what the typed text has to start.
    let host: String
    let url: String
    let color: String

    func searchURL(_ query: String) -> String {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)?
            .replacingOccurrences(of: "&", with: "%26") ?? query
        return url.replacingOccurrences(of: "%s", with: q)
    }

    /// "twit" offers X (twitter.com) though it completes to twitch.tv; the completed host
    /// wins when it is a site search itself.
    static func match(_ q: String, completion: String?) -> SiteSearch? {
        var t = q
        if t.hasPrefix("www.") { t.removeFirst(4) }
        guard !t.isEmpty, !t.contains(" "), !t.contains("/") else { return nil }
        if let completion, let site = all.first(where: { $0.host == completion && $0.host.hasPrefix(t) }) { return site }
        return all.first { $0.host.hasPrefix(t) }
    }

    /// Arc 1.170's list, in its order; colours measured off its pills.
    static let all: [SiteSearch] = [
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

enum PopularDomains {
    static let list: [String] = [
        "google.com", "youtube.com", "github.com", "gmail.com", "mail.google.com", "docs.google.com", "drive.google.com",
        "calendar.google.com", "maps.google.com", "chatgpt.com", "claude.ai", "x.com", "twitter.com", "reddit.com",
        "wikipedia.org", "en.wikipedia.org", "amazon.com", "apple.com", "developer.apple.com", "netflix.com", "linkedin.com",
        "facebook.com", "instagram.com", "notion.so", "figma.com", "slack.com", "app.slack.com", "discord.com", "zoom.us",
        "vercel.com", "stackoverflow.com", "npmjs.com", "medium.com", "nytimes.com", "bbc.com", "spotify.com",
        "open.spotify.com", "dr.dk", "tv2.dk", "jysk.com", "jysk.dk", "stripe.com", "dashboard.stripe.com", "cloudflare.com",
        "aws.amazon.com", "console.cloud.google.com", "linear.app", "trello.com", "asana.com", "dropbox.com",
        "icloud.com", "twitch.tv", "pinterest.com", "ebay.com", "booking.com", "airbnb.com", "paypal.com",
        "convex.dev", "supabase.com", "openai.com", "platform.openai.com", "anthropic.com", "huggingface.co",
        "producthunt.com", "news.ycombinator.com", "arc.net", "tryspook.com", "kildahl.dk", "localhost:3000",
    ]
}
