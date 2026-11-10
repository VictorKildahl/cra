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
    /// What Tab scopes the bar to ("Search YouTube  Tab", "Search Tabs  Tab").
    var scope: CommandBarScope?
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

    /// `spaceShown` is the space the bar's window shows, which "Switch to" leaves out: a Little
    /// Window's own target (#316); nil, the focused space.
    func suggestions(for rawQuery: String, mode: CommandBarMode, currentTabID: UUID?, spaceShown: UUID? = nil) -> SuggestionResult {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        let q = query.lowercased()
        var result = SuggestionResult(query: query)
        if q.isEmpty {
            result.items = Array(recentSuggestions(excluding: currentTabID).prefix(Self.maxRows))
            // Tab on the empty field lists the actions (Arc's typeTravel), with no hint at the end of it.
            result.scope = .actions
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
        items.append(contentsOf: commandSuggestions(q, currentTabID: currentTabID, spaceShown: spaceShown))

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
        result.scope = TabSearchScope.isOffered(by: query) ? .tabs
            : SiteSearch.match(q, completion: completion?.text, keywords: engines.keywords).map(CommandBarScope.site)
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

    /// The bar scoped to a space's open tabs ("%" Tab): its favorites, pinned and today tabs but
    /// the one in front, and nothing from history, the archive or the network.
    func suggestions(for rawQuery: String, inTabsOf spaceID: UUID, currentTabID: UUID?) -> SuggestionResult {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        let q = query.lowercased()
        var result = SuggestionResult(query: query)
        let tabs = store.visibleTabs(in: spaceID).filter { $0.id != currentTabID && $0.tab != nil }
        let byID = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let ranked = TabSearchScope.rank(tabs.map { tab in
            TabSearchScope.Candidate(id: tab.id, score: q.isEmpty ? 0 : textScore(q, title: tab.displayTitle, url: tab.tab?.url ?? ""),
                                     lastActive: tab.tab?.timeLastActiveAt)
        }, typed: !q.isEmpty)
        result.items = ranked.prefix(Self.maxRows).compactMap { byID[$0] }.map { tab in
            Suggestion(id: "tab:\(tab.id)", kind: .switchToTab(tab.id), title: tab.displayTitle, subtitle: Self.humanURL(tab.tab?.url ?? ""),
                       url: tab.tab?.url, faviconKey: tab.tab?.faviconKey, symbol: nil, trailing: "Switch to Tab", score: 0, spaceID: spaceID)
        }
        return result
    }

    /// The bar scoped to actions (Tab on the empty field, Arc's typeTravel): commands, space
    /// switches and moves, the most used first, narrowed by what is typed.
    func suggestions(forActionsMatching rawQuery: String, currentTabID: UUID?, spaceShown: UUID? = nil) -> SuggestionResult {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        let q = query.lowercased()
        var result = SuggestionResult(query: query)
        let rows = actionRows(q, currentTabID: currentTabID, spaceShown: spaceShown).filter { row in
            if case .command(let id) = row.suggestion.kind { return ActionSearchScope.lists(actionID: id) }
            return true
        }
        let ranked = ActionSearchScope.rank(rows.indices.map {
            ActionSearchScope.Candidate(id: $0, score: rows[$0].suggestion.score, uses: rows[$0].uses)
        }, typed: !q.isEmpty)
        result.items = ranked.prefix(Self.maxRows).map { rows[$0].suggestion }
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
        let tabs = commandBarTabs()
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
        enginesRead = nil
        remote.reset()
    }

    // MARK: Search engines

    private var enginesRead: (default: ChromiumSearchEngine, keywords: [ChromiumSearchEngine])?

    /// Chromium's, in the window's space's profile (an incognito window's are its Default's),
    /// read when the bar opens. The default is the space's own engine where it has one (#306).
    private var engines: (default: ChromiumSearchEngine, keywords: [ChromiumSearchEngine]) {
        if let enginesRead { return enginesRead }
        let space = store.focusedSpaceID
        let profile = store.profilePath(space: space)
        let keywords = SearchEngines.shared.keywords(profilePath: profile)
        let fallback = SearchEngines.shared.defaultEngine(profilePath: profile, legacy: store.settings.searchEngine)
        let read = (ChromiumSearchEngine.forSpace(keyword: store.space(space)?.searchEngine, default: fallback, among: keywords), keywords)
        enginesRead = read
        return read
    }

    /// Where typed text that isn't an address is searched.
    var searchEngine: ChromiumSearchEngine { engines.default }

    func searchURL(_ text: String) -> String { engines.default.searchURL(text) }

    /// Asks the search engine about `rawQuery`; `done` runs when its answer is in, to list again.
    func fetchSearchSuggestions(for rawQuery: String, done: @escaping @MainActor () -> Void) {
        let query = rawQuery.trimmingCharacters(in: .whitespaces)
        guard store.settings.searchSuggestions, !query.isEmpty, !query.contains("://") else { return }
        remote.fetch(query, engine: searchEngine, done: done)
    }

    /// The engine's suggestions not already listed, as search rows (or site rows).
    private func searchSuggestions(_ query: String, after items: [Suggestion]) -> [Suggestion] {
        let engine = searchEngine
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
                              faviconKey: FaviconKey.key(for: url), symbol: "globe", trailing: nil, score: 0)
        }
    }

    // MARK: Typed text

    static func looksLikeURL(_ s: String) -> Bool { TypedURL.looksLikeURL(s) }

    static func urlFromInput(_ s: String) -> String { TypedURL.fromInput(s) }

    private func typedRow(query: String) -> Suggestion {
        if Self.looksLikeURL(query) {
            let url = Self.urlFromInput(query)
            return Suggestion(id: "typed", kind: .navigate, title: query, subtitle: "Open URL", url: url,
                              faviconKey: FaviconKey.key(for: url), symbol: "globe", trailing: nil, score: 1000)
        }
        let engine = searchEngine
        return Suggestion(id: "typed", kind: .search, title: query, subtitle: "Search \(engine.name)",
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
                                  subtitle: Self.humanURL(h.url), url: h.url, faviconKey: FaviconKey.key(for: h.url),
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
                                  faviconKey: FaviconKey.key(for: url), symbol: "globe", trailing: nil,
                                  score: 72 - Double(i) * 0.1))
        }
        return out
    }

    private func commandSuggestions(_ q: String, currentTabID: UUID?, spaceShown: UUID?) -> [Suggestion] {
        guard q.count >= 2 else { return [] }
        return actionRows(q, currentTabID: currentTabID, spaceShown: spaceShown).map { row in
            var s = row.suggestion
            s.score += Double(min(row.uses, 10)) * 2
            return s
        }
    }

    /// Commands, space switches and moves the text names (all of them with nothing typed), each
    /// scored by its name alone, with how often it was run from the bar.
    private func actionRows(_ q: String, currentTabID: UUID?, spaceShown: UUID?) -> [(suggestion: Suggestion, uses: Int)] {
        var out: [(suggestion: Suggestion, uses: Int)] = []
        func nameScore(_ name: String, triggers: [String]) -> Double {
            let n = name.lowercased()
            if n.hasPrefix(q) { return 80 }
            if n.split(separator: " ").contains(where: { $0.hasPrefix(q) }) { return 68 }
            if triggers.contains(where: { $0.hasPrefix(q) }) { return 70 }
            if n.contains(q) { return 50 }
            return 0
        }
        for a in bindings.actions where a.inCommandBar {
            let s = nameScore(a.name, triggers: a.triggers)
            guard s > 0 else { continue }
            out.append((Suggestion(id: "cmd:\(a.id)", kind: .command(a.id), title: a.name, subtitle: "Command",
                                   url: nil, faviconKey: nil, symbol: a.symbol ?? "command", trailing: a.primary?.display, score: s),
                        store.ranking.commandUsage[a.id] ?? 0))
        }
        for space in incognito ? [] : store.orderedSpaces {
            let s = nameScore("Switch to \(space.title)", triggers: [space.title.lowercased()])
            if s > 0 && space.id != (spaceShown ?? store.focusedSpaceID) {
                out.append((Suggestion(id: "space:\(space.id)", kind: .switchSpace(space.id), title: "Switch to \(space.title)",
                                       subtitle: "Space", url: nil, faviconKey: nil, symbol: nil, trailing: space.emoji, score: s), 0))
            }
            if currentTabID != nil, space.id != store.focusedSpaceID {
                let m = nameScore("Move Tab to \(space.title)", triggers: ["move"])
                if m > 0 {
                    out.append((Suggestion(id: "move:\(space.id)", kind: .moveToSpace(space.id), title: "Move Tab to \(space.title)",
                                           subtitle: "Space", url: nil, faviconKey: nil, symbol: "arrow.right.square", trailing: space.emoji, score: m - 5), 0))
                }
            }
        }
        if currentTabID != nil {
            for f in store.children(of: store.focusedSpace.pinnedContainerID) where f.isFolder && !f.isLiveFolder {
                let name = f.title ?? "Folder"
                let m = nameScore("Move Tab to Folder \(name)", triggers: [name.lowercased()])
                if m > 0 {
                    out.append((Suggestion(id: "folder:\(f.id)", kind: .moveToFolder(f.id), title: "Move Tab to \(name)",
                                           subtitle: "Folder", url: nil, faviconKey: nil, symbol: "folder", trailing: nil, score: m - 5), 0))
                }
            }
        }
        return out
    }

    /// The open tabs ⌘T searches: the profile's, or the window's space's with Settings ▸ Advanced
    /// "Search only the current space’s tabs" (#307). A tab open in another space
    /// then doesn't hide its history row either.
    private func commandBarTabs() -> [SidebarItem] {
        TabSearchScope.commandBarTabs(store.profileTabs(window: nil), space: { self.store.spaceID(ofItem: $0.id) },
                                      windowSpace: store.focusedSpaceID, currentSpaceOnly: store.settings.commandBarCurrentSpaceOnly)
    }

    private func recentSuggestions(excluding current: UUID?) -> [Suggestion] {
        let tabs = commandBarTabs().filter { $0.id != current }
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

    private func dedupe(_ items: [Suggestion]) -> [Suggestion] {
        let rows = items.map { s -> CommandBarDedupe.Row in
            let isCommand: Bool
            if case .command = s.kind { isCommand = true } else { isCommand = false }
            return CommandBarDedupe.Row(keys: CommandBarDedupe.keys(id: s.id, url: isCommand ? nil : s.url, title: s.title),
                                        score: s.score, isOpenTab: s.tabID != nil)
        }
        return CommandBarDedupe.kept(rows).map { kept in
            var s = items[kept.index]
            s.score = kept.score
            return s
        }
    }

    private func inlineCompletion(_ q: String, candidates: [Suggestion]) -> (text: String, candidateID: String)? {
        guard !q.contains(" "), q.count >= 2, !Self.looksLikeURL(q) || !q.contains("/") else { return nil }
        func completion(_ c: Suggestion) -> String? {
            guard let url = c.url, c.score >= 90 || c.kind == .topDomain, let host = URL(string: url)?.host?.lowercased() else { return nil }
            let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
            if bare.hasPrefix(q) && bare != q { return bare }
            if host.hasPrefix(q) && host != q { return host }
            return nil
        }
        guard let best = candidates.lazy.compactMap({ c in completion(c).map { (text: $0, candidateID: c.id) } }).first else { return nil }
        // An open tab on the completed host leads, so Return switches to it rather than opening the
        // site again from history, and completes to its whole address (Arc 1.171: "semrush" →
        // semrush.com/projects for a tab on www.semrush.com/projects/).
        if let tab = candidates.first(where: { $0.tabID != nil && completion($0) == best.text }), let url = tab.url {
            let address = CommandBarDedupe.completionAddress(url)
            return (address.lowercased().hasPrefix(q) && address.count > q.count ? address : best.text, tab.id)
        }
        return best
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

/// What Tab scopes the bar to, a pill before the field until Backspace on the empty field or
/// Escape (Arc's ScopedSearchType).
enum CommandBarScope: Equatable {
    /// Arc's Site Search: "youtube" Tab searches YouTube.
    case site(SiteSearch)
    /// The open tabs of the window's space (#49).
    case tabs
    /// Arc's typeTravel: Tab on the empty field lists the browser's actions (#195).
    case actions

    var name: String {
        switch self {
        case .site(let site): return site.name
        case .tabs: return TabSearchScope.name
        case .actions: return ActionSearchScope.name
        }
    }
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
