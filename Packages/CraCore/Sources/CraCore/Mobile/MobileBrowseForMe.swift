import Foundation

/// Arc Search's "Browse for Me": reads a handful of pages about a query and makes one page of
/// the answer. In Cra everything happens on the phone: it fetches the search results and the
/// pages itself, and the device's own model writes the answer. These are the parts that need no
/// network and no model: reading the results, building the prompt, and the page's HTML.
public enum MobileBrowseForMe {
    public struct Hit: Equatable, Sendable {
        public var title: String
        public var url: String
        public var snippet: String

        public init(title: String, url: String, snippet: String = "") {
            self.title = title
            self.url = url
            self.snippet = snippet
        }

        public var host: String {
            URL(string: url)?.host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        }
    }

    /// A page that was read for the answer.
    public struct Source: Equatable, Sendable {
        public var hit: Hit
        public var title: String
        public var text: String
        /// The page's share picture, when it names one.
        public var image: String?

        public init(hit: Hit, title: String, text: String, image: String? = nil) {
            self.hit = hit
            self.title = title
            self.text = text
            self.image = image
        }
    }

    public struct Point: Equatable, Sendable {
        public var emoji: String
        public var term: String
        public var text: String

        public init(emoji: String, term: String, text: String) {
            self.emoji = emoji
            self.term = term
            self.text = text
        }
    }

    public struct Section: Equatable, Sendable {
        public var heading: String
        public var text: String

        public init(heading: String, text: String) {
            self.heading = heading
            self.text = text
        }
    }

    public struct Answer: Equatable, Sendable {
        public var title: String
        public var points: [Point]
        public var sections: [Section]
        /// Questions to ask next, shown as chips at the end (Arc Search 1.24's follow-ups).
        public var followUps: [String]

        public init(title: String, points: [Point], sections: [Section], followUps: [String] = []) {
            self.title = title
            self.points = points
            self.sections = sections
            self.followUps = followUps
        }

        /// At most this many follow-ups.
        public static let maxFollowUps = 3

        /// Trimmed, with empty entries dropped; nil when nothing is left to show.
        public var cleaned: Answer? {
            func tidy(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
            let points = points.map { Point(emoji: tidy($0.emoji), term: tidy($0.term), text: tidy($0.text)) }.filter { !$0.text.isEmpty }
            let sections = sections.map { Section(heading: tidy($0.heading), text: tidy($0.text)) }.filter { !$0.heading.isEmpty && !$0.text.isEmpty }
            guard !points.isEmpty || !sections.isEmpty else { return nil }
            var seen: Set<String> = []
            let followUps = followUps.map(tidy).filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
            return Answer(title: tidy(title), points: points, sections: sections, followUps: Array(followUps.prefix(Self.maxFollowUps)))
        }
    }

    /// Arc Search read "at least six" pages.
    public static let sourceCount = 6
    /// The on-device model reads 4,096 tokens in all; six sources at this length leave room for
    /// the instructions and the answer.
    public static let sourceTextLength = 450

    // MARK: Search results

    /// Where the search results come from: DuckDuckGo's plain HTML results, which need no script
    /// to read.
    public static func searchURL(_ query: String) -> URL? {
        var components = URLComponents(string: "https://html.duckduckgo.com/html/")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    /// The results on DuckDuckGo's HTML page: each `result__a` link (its real address is in the
    /// redirect's `uddg` parameter) with the `result__snippet` that follows it. Ads are left out.
    public static func hits(fromResultsHTML html: String) -> [Hit] {
        guard let link = try? NSRegularExpression(pattern: #"<a[^>]*class="result__a"[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, options: [.dotMatchesLineSeparators]),
              let snippet = try? NSRegularExpression(pattern: #"class="result__snippet"[^>]*>(.*?)</a>"#, options: [.dotMatchesLineSeparators]) else { return [] }
        let text = html as NSString
        let whole = NSRange(location: 0, length: text.length)
        let snippets = snippet.matches(in: html, range: whole)
        var hits: [Hit] = []
        for match in link.matches(in: html, range: whole) {
            let href = decodeEntities(text.substring(with: match.range(at: 1)))
            guard let url = destination(ofResultLink: href) else { continue }
            let title = plain(text.substring(with: match.range(at: 2)))
            let after = snippets.first { $0.range.location > match.range.location }
            let blurb = after.map { plain(text.substring(with: $0.range(at: 1))) } ?? ""
            hits.append(Hit(title: title, url: url, snippet: blurb))
        }
        return hits
    }

    /// Markup to text: tags out, entities decoded.
    private static func plain(_ markup: String) -> String {
        LinkSummaryContent.cleanHTMLText(markup.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression))
    }

    private static func decodeEntities(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// The address behind a result link, or nil for an ad or anything that is not a web page.
    static func destination(ofResultLink href: String) -> String? {
        var address = href.hasPrefix("//") ? "https:" + href : href
        if let components = URLComponents(string: address), components.host?.hasSuffix("duckduckgo.com") == true {
            if components.path.hasPrefix("/y.js") { return nil }
            guard let real = components.queryItems?.first(where: { $0.name == "uddg" })?.value else { return nil }
            address = real
        }
        guard let url = URL(string: address), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host?.isEmpty == false else { return nil }
        return address
    }

    /// The pages to read: the first `limit` results, one per site.
    public static func pick(_ hits: [Hit], limit: Int = sourceCount) -> [Hit] {
        var seen = Set<String>()
        return Array(hits.filter { !$0.host.isEmpty && seen.insert($0.host).inserted }.prefix(limit))
    }

    // MARK: The model

    public static let instructions = """
    You answer a question by combining what several web pages say. Write a short title, then three or four key points \
    (an emoji, a term of one to three words, and one sentence), then two or three sections with a heading and two or \
    three sentences each. Use only what the pages say. Do not mention the pages or that you are summarizing.
    """

    public static func prompt(query: String, sources: [Source], language: String) -> String {
        let pages = sources.enumerated().map { index, source -> String in
            let body = MobileSummary.clipped(source.text.isEmpty ? source.hit.snippet : source.text, limit: sourceTextLength)
            return "<page \(index + 1) site=\"\(source.hit.host)\">\n\(source.title)\n\(body)\n</page>"
        }
        return "Answer in \(language).\n\nQUESTION: \(query)\n\nWEB PAGES:\n" + pages.joined(separator: "\n")
    }

    /// A stand-in answer for tests, built from the sources themselves.
    public static func fakeAnswer(query: String, sources: [Source]) -> Answer {
        Answer(title: "About \(query)",
               points: sources.prefix(3).map { Point(emoji: "⭐️", term: $0.hit.host, text: $0.title) },
               sections: sources.prefix(2).map { Section(heading: $0.title, text: MobileSummary.clipped($0.text, limit: 160)) },
               followUps: ["best \(query)", "\(query) for beginners"])
    }

    // MARK: The loading screen

    public static func readingLabel(_ count: Int) -> String {
        count == 1 ? "Reading 1 web page" : "Reading \(count) web pages"
    }

    public static let makingLabel = "Making a website for you"

    // MARK: The page

    /// The tab's address for a Browse for Me page: not a web address, so nothing loads it by accident.
    public static func tabAddress(query: String) -> String {
        "cra-browse:" + (query.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? query)
    }

    /// The longest question taken from selected text.
    public static let selectionQueryLimit = 200

    /// Selected text as a question: whitespace and line breaks run together, cut at a word
    /// boundary within `selectionQueryLimit` characters.
    public static func query(fromSelection text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var query = ""
        for word in words {
            let next = query.isEmpty ? String(word) : query + " " + word
            if next.count > selectionQueryLimit { return query.isEmpty ? String(next.prefix(selectionQueryLimit)) : query }
            query = next
        }
        return query
    }

    /// The query capsule's link: the search sheet with the question in it, to change it (Arc
    /// Search 1.12's query editing). Only Cra's own pages carry it; it does nothing else.
    public static func editAddress(query: String) -> String {
        "cra-edit:" + (query.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? query)
    }

    public static func query(fromEditAddress address: String) -> String? {
        guard address.hasPrefix("cra-edit:") else { return nil }
        return String(address.dropFirst("cra-edit:".count)).removingPercentEncoding
    }

    /// The query of a Browse for Me tab, or nil for any other address.
    public static func query(fromTabAddress address: String) -> String? {
        guard address.hasPrefix("cra-browse:") else { return nil }
        return String(address.dropFirst("cra-browse:".count)).removingPercentEncoding
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The answer as a page, in Arc Search's order: the query in a capsule, the sources' pictures,
    /// "Read N web pages" with the source cards, the title, the key points, then the sections.
    /// The capsule edits the question (`editAddress`); `searchURL` is kept for the engine's results
    /// (the floating switch goes there).
    public static func pageHTML(query: String, answer: Answer, sources: [Source], searchURL: String) -> String {
        let pictures = sources.compactMap { source -> String? in
            guard let image = source.image, let url = URL(string: image, relativeTo: URL(string: source.hit.url))?.absoluteURL,
                  url.scheme == "https" else { return nil }
            return "<a class=\"shot\" href=\"\(escape(source.hit.url))\"><img src=\"\(escape(url.absoluteString))\" alt=\"\" loading=\"lazy\" onerror=\"this.parentNode.remove()\"></a>"
        }
        let cards = sources.map { source in
            "<a class=\"card\" href=\"\(escape(source.hit.url))\"><span class=\"card-title\">\(escape(source.title.isEmpty ? source.hit.title : source.title))</span>"
                + "<span class=\"card-site\">\(escape(source.hit.host))</span></a>"
        }
        let points = answer.points.map { point in
            "<li><span class=\"emoji\">\(escape(point.emoji.isEmpty ? "•" : point.emoji))</span><span>"
                + (point.term.isEmpty ? "" : "<b>\(escape(point.term))</b> — ") + "\(escape(point.text))</span></li>"
        }
        let sections = answer.sections.map { "<h2>\(escape($0.heading))</h2><p>\(escape($0.text))</p>" }
        // Follow-ups (1.24): each a new Browse for Me; and the pages read, as links (1.24's "Sources").
        let followUps = answer.followUps.filter { $0.lowercased() != query.lowercased() }.map { question in
            "<a class=\"chip\" href=\"\(escape(tabAddress(query: question)))\">\(escape(question))</a>"
        }
        let sourceLinks = sources.map { source in
            "<li><a href=\"\(escape(source.hit.url))\"><span class=\"src-title\">\(escape(source.title.isEmpty ? source.hit.title : source.title))</span>"
                + "<span class=\"card-site\">\(escape(source.hit.host))</span></a></li>"
        }
        return """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escape(answer.title.isEmpty ? query : answer.title))</title>
        <style>
        :root { color-scheme: light dark; --ink: #1c1c1e; --soft: #6e6e73; --blue: #2b2bd6; --card: rgba(0,0,0,0.05); --page: #fff; }
        @media (prefers-color-scheme: dark) { :root { --ink: #ececee; --soft: #9a999f; --blue: #8f93ff; --card: rgba(255,255,255,0.09); --page: #1c1c1e; } }
        body { margin: 0; padding: 12px 20px 140px; font: 16px/1.45 -apple-system, system-ui, sans-serif; color: var(--ink); background: var(--page); -webkit-text-size-adjust: 100%; }
        main { max-width: 680px; margin: 0 auto; }
        a { color: inherit; text-decoration: none; }
        .query { display: flex; align-items: center; gap: 9px; height: 40px; padding: 0 16px; border-radius: 20px; background: var(--card); font-weight: 500; white-space: nowrap; overflow: hidden; }
        .query svg { flex: none; } .query span { overflow: hidden; text-overflow: ellipsis; }
        .shots { display: flex; gap: 8px; overflow-x: auto; margin: 16px -20px 0; padding: 0 20px; scrollbar-width: none; }
        .shots::-webkit-scrollbar, .cards::-webkit-scrollbar { display: none; }
        .shot { flex: none; width: 62%; aspect-ratio: 4 / 3; border-radius: 12px; overflow: hidden; background: var(--card); }
        .shot img { width: 100%; height: 100%; object-fit: cover; display: block; }
        .read { margin: 18px 0 8px; font-size: 14px; color: var(--soft); }
        .cards { display: flex; gap: 8px; overflow-x: auto; margin: 0 -20px; padding: 0 20px; scrollbar-width: none; }
        .card { flex: none; width: 150px; padding: 10px 12px; border-radius: 12px; background: var(--card); display: flex; flex-direction: column; gap: 6px; }
        .card-title { font-size: 13px; font-weight: 500; line-height: 1.3; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; min-height: 34px; }
        .card-site { font-size: 12px; color: var(--soft); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
        h1 { margin: 24px 0 14px; font-size: 26px; line-height: 1.2; font-weight: 600; color: var(--blue); }
        ul { list-style: none; margin: 0; padding: 0; }
        li { display: flex; gap: 10px; margin: 0 0 12px; }
        .emoji { flex: none; width: 24px; text-align: center; }
        h2 { margin: 24px 0 6px; font-size: 19px; font-weight: 600; color: var(--blue); }
        p { margin: 0 0 10px; }
        .chips { display: flex; flex-wrap: wrap; gap: 8px; margin: 22px 0 6px; }
        .chip { padding: 8px 14px; border-radius: 18px; background: var(--card); font-size: 15px; font-weight: 500; }
        .sources { margin-top: 8px; } .sources li { display: block; margin: 0 0 10px; }
        .sources a { display: flex; flex-direction: column; } .src-title { font-weight: 500; }
        </style></head><body><main>
        <a class="query" href="\(escape(editAddress(query: query)))"><svg width="15" height="15" viewBox="0 0 15 15" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"><circle cx="6.3" cy="6.3" r="4.8"/><path d="M10 10l3.6 3.6"/></svg><span>\(escape(query))</span></a>
        \(pictures.isEmpty ? "" : "<div class=\"shots\">\(pictures.joined())</div>")
        <div class="read">Read \(sources.count) web page\(sources.count == 1 ? "" : "s")</div>
        <div class="cards">\(cards.joined())</div>
        <h1>\(escape(answer.title.isEmpty ? query : answer.title))</h1>
        <ul>\(points.joined())</ul>
        \(sections.joined())
        \(followUps.isEmpty ? "" : "<div class=\"chips\">\(followUps.joined())</div>")
        \(sourceLinks.isEmpty ? "" : "<h2>Sources</h2><ul class=\"sources\">\(sourceLinks.joined())</ul>")
        </main></body></html>
        """
    }
}
