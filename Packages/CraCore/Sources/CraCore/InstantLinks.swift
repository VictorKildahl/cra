import Foundation

/// Arc Max's Instant Links (`instantLinksEnabled`), on the Mac's own Apple Intelligence model instead
/// of Arc's server.
///
/// In ⌘T, Shift-Return on a search asks the model to turn what was typed into a plan: a title, a format
/// (tab, folder or split) and up to four Google searches, each with the number of results wanted. Cra
/// searches Google in a hidden page and opens the top results as tabs, a split or a folder; the sidebar
/// shows "Searching the web for you…" meanwhile. Arc's strings and its Google selectors are from
/// Arc 1.172.2's binary (docs/arc-reverse-engineering.md, "Instant Links").
///
/// The model is small and makes the same few mistakes, so `plan` checks its answer against what was
/// typed. Each rule is one it was measured to need.
public enum InstantLinks {
    public enum Format: String, Sendable, Codable, CaseIterable {
        case tab, folder, split
    }

    public struct Search: Equatable, Sendable {
        public var query: String
        /// How many results to open.
        public var count: Int

        public init(query: String, count: Int) {
            self.query = query
            self.count = count
        }
    }

    public struct Plan: Equatable, Sendable {
        public var title: String
        public var format: Format
        public var searches: [Search]

        public init(title: String, format: Format, searches: [Search]) {
            self.title = title
            self.format = format
            self.searches = searches
        }
    }

    // MARK: Arc's text

    /// Settings ▸ Max, as Arc words it.
    public static let settingsTitle = "Instant Links"
    public static let settingsDetail = "Press Shift + Enter for any web search to instantly open the top result. You can also search multiple queries!"
    /// The sidebar row while it works, and when it fails.
    public static let searchingTitle = "Searching the web for you…"
    public static let errorTitle = "Oops, something went wrong."

    /// The model's instructions. The examples are what keep a 3B model to one search per thing and its
    /// counts honest; the app pairs them with a guided-generation schema (title, format, up to four
    /// searches of query and a count of 1...10).
    public static let instructions = """
    You turn what someone typed into a browser's command bar into Google searches. The browser opens the top results of each search as tabs.

    Most inputs need exactly one search. Make more than one only when the input names different things, like "greek and italian restaurants" or "the trailer and the showtimes". Never write two searches for the same thing: if the user wants several results for one thing, write one search and set its count.

    For each search:
    - query: the user's own words and language, short, without filler such as "give me", "find me", "show me", "open", "on the left". When the input names a website (YouTube, Reddit, Wikipedia, Amazon, Spotify, Resy…), leave the name out and add site: with its domain, like site:youtube.com.
    - count: how many results the user asks for: "top 5" is 5, "the first two" is 2, "a few" is 3. Otherwise 1. A number that belongs to the thing itself, as in "iphone 15" or "2 player games", is not a count.

    format: "split" only if the input asks for a split or says left and right; "folder" only if it asks for a folder; otherwise "tab".
    title: a short name for the results, in Title Case.

    Examples:
    "the barbie trailer" → tab "Barbie Trailer": [barbie trailer, 1]
    "top 3 pizza places in naples" → tab "Pizza in Naples": [best pizza naples, 3]
    "a few lasagna recipes" → tab "Lasagna Recipes": [lasagna recipes, 3]
    "iphone 15 cases" → tab "iPhone 15 Cases": [iphone 15 cases, 1]
    "greek and italian restaurants in greenpoint in a split" → split "Greek and Italian Restaurants": [greek restaurants greenpoint, 1] [italian restaurants greenpoint, 1]
    "the barbie trailer on the left and showtimes on the right" → split "Barbie": [barbie trailer, 1] [barbie showtimes, 1]
    "folder of iphone chargers on amazon" → folder "iPhone Chargers": [iphone chargers site:amazon.com, 1]
    "mkbhd and linus tech tips on youtube" → tab "MKBHD and Linus": [mkbhd site:youtube.com, 1] [linus tech tips site:youtube.com, 1]
    "ricette del tiramisù, apri le prime due" → tab "Ricette del Tiramisù": [ricetta tiramisù, 2]
    """

    // MARK: The rules on the model's answer

    /// `phrase` is what the user typed; the rest is the model's raw answer.
    public static func plan(title: String, format: Format, searches: [Search], phrase: String) -> Plan {
        let words = tokens(phrase)
        var kept: [Search] = []
        for search in searches {
            // "cartella con guide per sciare" came back with "cartella con" in the search: the format's words
            // say where the results go, not what to look for.
            let written = search.query.trimmingCharacters(in: .whitespacesAndNewlines)
            let bare = withoutFormatWords(written)
            var query = bare.isEmpty ? written : bare
            let own = query.split(separator: " ").map { String($0).lowercased() }
            let plain = own.filter { !$0.hasPrefix("site:") }
            // 1. A name copied from the examples, not typed ("youtube mkbhd" came back with mr beast too).
            guard plain.contains(where: { w in words.contains { $0 == w || stem($0) == stem(w) } }) else { continue }
            // 2. "oatmeal cookie recipes reddit" means site:reddit.com; "amazon rainforest facts" doesn't.
            if !own.contains(where: { $0.hasPrefix("site:") }), own.count > 1,
               let named = plain.first(where: { name in
                   namesSite(at: plain.firstIndex(of: name)!, in: plain)
                       || words.indices.contains { words[$0] == name && namesSite(at: $0, in: words) }
               }), let domain = siteNames[named] {
                // The name goes, and the word pointing at it: "playlists on spotify" → "playlists site:spotify.com".
                let at = plain.firstIndex(of: named)!
                let gone = at > 0 && sitePointers.contains(plain[at - 1]) ? (at - 1)...at : at...at
                query = plain.indices.filter { !gone.contains($0) }.map { plain[$0] }.joined(separator: " ") + " site:" + domain
            }
            kept.append(Search(query: query, count: search.count))
        }
        // 3. The phrase names one website and the model left it out ("search reddit for oatmeal cookie
        // recipes" came back as "oatmeal cookie recipes"): search on it.
        let named = Set(words.indices.compactMap { namesSite(at: $0, in: words) ? siteNames[words[$0]] : nil })
        if named.count == 1, let domain = named.first,
           !kept.contains(where: { $0.query.lowercased().split(separator: " ").contains { $0.hasPrefix("site:") } }) {
            // A search that is the site's own name ("youtube") is the site, not a search on it.
            kept = kept.map { search in
                let own = search.query.lowercased().split(separator: " ").map(String.init)
                return own.contains { siteNames[$0] == domain } ? search : Search(query: search.query + " site:" + domain, count: search.count)
            }
        }
        // 4. The same thing twice is one search.
        var merged: [Search] = []
        for search in kept {
            let mine = signature(search.query)
            if !mine.words.isEmpty, let i = merged.firstIndex(where: {
                let other = signature($0.query)
                return !other.words.isEmpty && other.sites == mine.sites
                    && (mine.words.isSubset(of: other.words) || other.words.isSubset(of: mine.words))
            }) {
                merged[i].count = max(merged[i].count, search.count)
            } else {
                merged.append(search)
            }
        }
        // 5. A count above 1 needs a word in the phrase that asks for it.
        let countable = phrase.contains(where: \.isNumber) || words.contains { countWords.contains($0) }
        var searches = merged.map { Search(query: $0.query, count: min(10, max(1, countable ? $0.count : 1))) }
        // 6. Nothing left: search what was typed.
        let typed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        if searches.isEmpty { searches = [Search(query: typed, count: 1)] }
        if searches.count == 1, let stated = statedCount(in: phrase) { searches[0].count = stated }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return Plan(title: name.isEmpty ? titleCase(typed) : name, format: checkedFormat(model: format, phrase: phrase), searches: searches)
    }

    /// A count the phrase states plainly (2...10), nil when it names none. A number that belongs to the
    /// thing ("1984", "iphone 15", "windows 11", "best 2 player board games") isn't one.
    public static func statedCount(in phrase: String) -> Int? {
        let t = tokens(phrase)
        func number(_ i: Int) -> Int? { t.indices.contains(i) ? numbers[t[i]] : nil }

        if let first = t.firstIndex(where: { !leadWords.contains($0) }), let n = number(first),
           !(t.indices.contains(first + 1) && things.contains(t[first + 1])), countsThings(after: first, in: t) { return n }
        for i in t.indices {
            if ["top", "first", "primi", "prime"].contains(t[i]), let n = number(i + 1) { return n }
            if let n = number(i), t.indices.contains(i + 1), ["migliori", "best", "results", "risultati"].contains(t[i + 1]),
               !(i > 0 && t[i - 1] == "best") { return n }
            if t[i] == "a", t.indices.contains(i + 1) {
                if t[i + 1] == "couple" { return 2 }
                if t[i + 1] == "few" { return 3 }
            }
            if t[i] == "qualche" { return 3 }
        }
        return nil
    }

    /// A number at the start counts things when plural things follow it: "3 easy bread recipes", "dammi
    /// 3 ristoranti a trieste", but not "7 wonders board game" or "3 body problem". The words up to the
    /// first preposition name the things; the last of them has to be plural (English -s, Italian -i).
    private static func countsThings(after i: Int, in t: [String]) -> Bool {
        let named = t[(i + 1)...].prefix { !thingsEnd.contains($0) }
        guard let last = named.last else { return false }
        return (last.count > 2 && last.hasSuffix("s") && !last.hasSuffix("ss")) || (last.count > 3 && last.hasSuffix("i"))
    }

    /// Words after a number that make it part of the thing ("2 player games", "5 star hotels", "5 minute abs").
    private static let things: Set<String> = [
        "player", "players", "giocatore", "giocatori", "star", "stars", "stelle", "minute", "minutes", "min", "minuti",
        "hour", "hours", "ore", "day", "days", "giorni", "week", "weeks", "month", "months", "year", "years", "anni",
        "second", "seconds", "ingredient", "ingredients", "ingredienti", "step", "steps", "piece", "pieces", "door", "doors", "pack",
    ]
    private static let thingsEnd: Set<String> = [
        "for", "in", "on", "of", "from", "by", "with", "near", "at", "to", "about", "and", "a", "di", "da", "per", "su", "con", "nel", "e",
    ]

    /// What to open: each search with its number of results. A folder of one search that asks for one
    /// result opens 5 (Arc's rule); a split opens `PickedTabsMenu.maxPanes` panes in all; ten tabs at most.
    public static func openings(for plan: Plan) -> [Search] {
        var searches = plan.searches.map { Search(query: $0.query, count: min(10, max(1, $0.count))) }
        if plan.format == .folder, searches.count == 1, searches[0].count == 1 { searches[0].count = 5 }
        var left = plan.format == .split ? PickedTabsMenu.maxPanes : 10
        var out: [Search] = []
        for (i, search) in searches.enumerated() where left > 0 {
            // Every search gets a result before any gets a second.
            let n = min(search.count, max(1, left - (searches.count - i - 1)))
            out.append(Search(query: search.query, count: n))
            left -= n
        }
        return out
    }

    /// A plan without the model: the phrase as one search, its stated count and any cue for a split or a
    /// folder. The fallback when the model fails (a guardrail, the context window, a language it doesn't
    /// support) and the test model's plan (CRA_TIDY_FAKE_MODEL=1).
    public static func plainPlan(for phrase: String) -> Plan {
        let typed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        // No model to say it: any cue for a split or a folder counts.
        let asSplit = checkedFormat(model: .split, phrase: phrase)
        let cued = asSplit != .tab ? asSplit : checkedFormat(model: .folder, phrase: phrase)
        let bare = withoutFormatWords(typed)
        let what = bare.isEmpty ? typed : bare
        return Plan(title: titleCase(what), format: cued, searches: [Search(query: what, count: statedCount(in: phrase) ?? 1)])
    }

    // MARK: Google

    /// Arc reads results from Google's page only.
    public static func readsResults(of engine: ChromiumSearchEngine?) -> Bool {
        guard let engine else { return false }
        if engine.prepopulateID == 1 || engine.url.contains("{google:") { return true }
        let rest = engine.url.lowercased().components(separatedBy: "://").last ?? ""
        let host = rest.prefix { $0 != "/" && $0 != "?" }
        return host.hasPrefix("www.google.") || host.hasPrefix("google.")
    }

    /// Google's results page, the query percent-encoded as Arc's is ("site:" stays readable).
    public static func googleURL(for query: String) -> URL {
        let q = query.addingPercentEncoding(withAllowedCharacters: queryCharacters) ?? ""
        return URL(string: "https://www.google.com/search?q=" + q) ?? URL(string: "https://www.google.com/")!
    }

    private static let queryCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~:"))

    /// Runs in a hidden page on Google's results page and resolves to `{"links": [href…], "blocked": Bool}`
    /// as a JSON string. Arc's selectors: the anchors of `#main` that hold a real heading, none from the
    /// bottom ads or "more results" blocks. It polls for them for up to 5 seconds, so it can run as the
    /// page loads. It returns more links than `limit`: `results(fromJSON:limit:)` drops Google's own.
    public static func resultsScript(limit: Int) -> String {
        """
        (async () => {
          const want = \(max(1, limit) * 3 + 10);
          const blocked = () => !!document.querySelector("form#captcha-form, iframe[title='reCAPTCHA'], div#recaptcha, iframe[title='recaptcha']");
          const links = () => {
            const main = document.querySelector('#main');
            if (!main) return [];
            const found = document.evaluate(".//a[.//h3[not(@role='header') and not(@aria-hidden='true')]]", main, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            const out = [];
            for (let i = 0; i < found.snapshotLength && out.length < want; i++) {
              const a = found.snapshotItem(i);
              if (a.closest('div#botstuff, div#bottomads')) continue;
              try { out.push(new URL(a.getAttribute('href'), location.href).href); } catch (e) {}
            }
            return out;
          };
          const deadline = Date.now() + 5000;
          let hrefs = links();
          while (hrefs.length === 0 && !blocked() && Date.now() < deadline) {
            await new Promise((resolve) => setTimeout(resolve, 100));
            hrefs = links();
          }
          return JSON.stringify({ links: hrefs, blocked: hrefs.length === 0 && blocked() });
        })()
        """
    }

    public struct Results: Equatable, Sendable {
        public var links: [URL]
        /// Google asked for a captcha instead of answering.
        public var blocked: Bool

        public init(links: [URL], blocked: Bool) {
            self.links = links
            self.blocked = blocked
        }
    }

    /// The script's answer as pages to open: web addresses only, Google's `/url?q=` (Arc does) and
    /// `/goto?url=` unwrapped to the page (opened as they are, `/goto` shows Google's "verifying your
    /// request" page for seconds first), Google's own search, maps and sign-in links, a wrapper without a
    /// web address and repeats left out, `limit` at most.
    public static func results(fromJSON json: String, limit: Int) -> Results {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else {
            return Results(links: [], blocked: false)
        }
        var links: [URL] = []
        var seen: Set<String> = []
        for case let raw as String in (object["links"] as? [Any]) ?? [] {
            guard links.count < limit, var url = URL(string: raw), isWeb(url) else { continue }
            if isGoogle(url), let name = ["/url": "q", "/goto": "url"][url.path],
               let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == name })?.value,
               let target = URL(string: q), isWeb(target) {
                url = target
            }
            if isGoogle(url) { continue }
            if seen.insert(url.absoluteString).inserted { links.append(url) }
        }
        return Results(links: links, blocked: object["blocked"] as? Bool ?? false)
    }

    // MARK: Parts

    private static func isWeb(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return (scheme == "http" || scheme == "https") && url.host != nil
    }

    /// Google's own pages: its search, and the hosts its results page links to for maps, sign-in and help.
    /// Documents on docs.google.com and the like are results.
    private static func isGoogle(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if ["accounts.google.com", "maps.google.com", "support.google.com", "policies.google.com"].contains(host) { return true }
        return host.hasPrefix("www.google.") || host.hasPrefix("google.")
    }

    private static func tokens(_ s: String) -> [String] {
        s.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
    }

    private static func stem(_ w: String) -> String { w.count > 3 && w.hasSuffix("s") ? String(w.dropLast()) : w }

    /// A search's words without filler, and its site: tokens.
    private static func signature(_ query: String) -> (words: Set<String>, sites: Set<String>) {
        let all = tokens(query)
        let words = all.filter { !$0.hasPrefix("site:") && !stopWords.contains($0) }.map(stem)
        return (Set(words), Set(all.filter { $0.hasPrefix("site:") }))
    }

    private static func checkedFormat(model: Format, phrase: String) -> Format {
        let p = phrase.lowercased()
        // Whole words only: "splitting the bill", "leftover", "manila folders" ask for nothing.
        func has(_ cues: [String]) -> Bool {
            cues.contains { p.range(of: "(?<![\\p{L}\\p{N}])" + $0 + "(?![\\p{L}\\p{N}])", options: .regularExpression) != nil }
        }
        let split = has(["split", "side by side", "affianc\\p{L}*"]) || (has(["left"]) && has(["right"]))
            || (has(["sinistra"]) && has(["destra"]))
        let folder = has(["folder", "cartella"])
        var format: Format = model == .split && split ? .split : model == .folder && folder ? .folder : .tab
        if format == .tab {
            if has(["folder of", "in a folder", "cartella con", "cartella di", "in una cartella"]) {
                format = .folder
            } else if has(["split view", "in a split", "split of", "in split"]) {
                format = .split
            }
        }
        return format
    }

    /// The words that ask for a folder or a split, taken out of a search ("folder of pizza" → "pizza").
    static func withoutFormatWords(_ s: String) -> String {
        let pattern = "\\b(?:give me a folder of|a folder of|folder of|in a folder|in a split view|split view of|split view with|"
            + "in a split|split of|in split|in una cartella|una cartella di|cartella con|cartella di)\\b"
        let stripped = s.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        return stripped.split(separator: " ").joined(separator: " ")
    }

    private static func titleCase(_ s: String) -> String {
        s.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    private static let leadWords: Set<String> = ["give", "me", "show", "open", "find", "get", "dammi", "mostrami", "apri", "trova", "cerca"]
    private static let stopWords: Set<String> = ["the", "of", "in", "a", "on", "for", "to", "from", "di", "del", "della", "e", "le", "best", "top"]
    private static let numbers: [String: Int] = [
        "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9, "10": 10,
        "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "due": 2, "tre": 3, "quattro": 4, "cinque": 5, "sei": 6, "sette": 7, "otto": 8, "nove": 9, "dieci": 10,
    ]
    private static let countWords: Set<String> = Set(numbers.keys).union(["few", "couple", "primi", "prime", "top"])

    /// The sites a person names in a search, and the domain `site:` takes for each.
    private static let siteNames: [String: String] = [
        "wiki": "wikipedia.org", "wikipedia": "wikipedia.org", "youtube": "youtube.com", "reddit": "reddit.com",
        "amazon": "amazon.com", "spotify": "spotify.com", "github": "github.com", "stackoverflow": "stackoverflow.com",
        "pinterest": "pinterest.com", "tiktok": "tiktok.com", "linkedin": "linkedin.com", "netflix": "netflix.com",
        "goodreads": "goodreads.com", "threads": "threads.net", "twitter": "x.com", "resy": "resy.com",
        "yelp": "yelp.com", "imdb": "imdb.com", "infatuation": "theinfatuation.com",
    ]

    /// Whether `t[i]` names a website rather than being a word of the search. Pointing at it always
    /// does ("on amazon", "from amazon", "search reddit for"). Otherwise a brand at either end of the
    /// search does ("youtube mkbhd", "oatmeal cookie recipes reddit"), but a name that is also an
    /// everyday word only where it reads as the site: "1812 wiki" yes, "a wiki for my team", "amazon
    /// rainforest facts" and "m3 screw threads" no.
    static func namesSite(at i: Int, in t: [String]) -> Bool {
        guard t.indices.contains(i), siteNames[t[i]] != nil else { return false }
        if i > 0, sitePointers.contains(t[i - 1]) { return true }
        let places = everydaySiteNames[t[i]] ?? [.first, .last]
        let first = t.firstIndex { !leadWords.contains($0) && !beforeTheThing.contains($0) && numbers[$0] == nil }
        return (places.contains(.first) && first == i) || (places.contains(.last) && i == t.count - 1)
    }

    private enum SitePlace { case first, last }
    private static let sitePointers: Set<String> = ["on", "from", "via", "search", "su", "da"]
    private static let beforeTheThing: Set<String> = ["search", "top", "best", "the", "a", "first"]
    private static let everydaySiteNames: [String: Set<SitePlace>] = [
        "amazon": [], "threads": [], "wiki": [.last], "infatuation": [.first],
        // "netflix stock price" is about the company; "stranger things netflix" is on the site.
        "netflix": [.last],
    ]
}
