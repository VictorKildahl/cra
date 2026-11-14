import Foundation

/// Arc Max's 5-Second Previews, which Arc calls hover cards (`hoverCardsEnabled`, the HoverCards
/// module): a card that summarizes the page behind a link, done here by the Mac's own Apple
/// Intelligence model instead of Arc's server.
///
/// Arc's settings text: "Instant summaries appear when you hover over links on certain websites.
/// Or hold Shift while hovering to preview any link." Measured on Arc 1.171 (10 Nov 2026): a card
/// opens after the pointer rests 1 s on one of Arc's links on Google, X or Hacker News, or on any
/// link the pointer reaches with Shift already held (pressing Shift on a link does nothing). With
/// Shift, a link to the page's own site gets the small card (title and address); any other link
/// the summary. Nothing is fetched before a card opens.
public enum LinkSummaryPolicy {
    /// The sites where a hover alone shows a card (`HoverCardsSupportedDomain`).
    public enum Site: Equatable, Sendable {
        case google, x, hackerNews
    }

    /// The two cards: Arc's answer card, and its small card for a link within the site.
    public enum Kind: Equatable, Sendable {
        case summary, link
    }

    /// How long the pointer rests on a link before its card opens: 0.97 and 1.2 s in two
    /// recordings of Arc on Hacker News (60 fps).
    public static let rest: Duration = .seconds(1)

    public static func autoSite(page: URL?) -> Site? {
        guard let page, let host = page.host()?.lowercased() else { return nil }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if h == "news.ycombinator.com" { return .hackerNews }
        if ["x.com", "twitter.com", "mobile.x.com", "mobile.twitter.com"].contains(h) { return .x }
        if isGoogleSearchHost(h) { return .google }
        return nil
    }

    /// google.com, google.fr, google.co.uk: Google's own site, not mail.google.com or a Google
    /// subdomain of something else.
    static func isGoogleSearchHost(_ host: String) -> Bool {
        guard host.hasPrefix("google."), let site = SiteKey.site(of: "https://\(host)") else { return false }
        return site == host
    }

    /// Arc's links per site, as its binary lists them: Hacker News's story titles, the links in a
    /// post and its link card on X, and the links in Google's results (#search, #tvcap above them,
    /// #topstuff and #botstuff), not its side panel (an organic result opened a card in Arc, a
    /// side-panel link didn't).
    public static func selectors(for site: Site) -> [String] {
        switch site {
        case .hackerNews: [".title .titleline > a"]
        case .x: ["[data-testid=tweetText] a[role=link][target=_blank]", "[data-testid='card.wrapper'] a[role=link]",
                  "a[role=link][rel='nofollow noreferrer'][target=_blank]"]
        case .google: ["#search a", "#tvcap a", "#topstuff a", "#botstuff a", "g-section-with-header a [role=heading]"]
        }
    }

    /// The page script run when the pointer has rested on a link: the link under `pointer`
    /// (fractions of the view, y down), its rect in fractions of the viewport, and whether it is one
    /// of Arc's links for `site`. Answers null when no link is there. Runs in Cra's isolated world.
    public static func hoverScript(pointer: CGPoint, site: Site?) -> String {
        let selectors = site.map(selectors(for:)) ?? []
        let list = (try? JSONSerialization.data(withJSONObject: selectors)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        return """
        (() => {
          const vv = visualViewport;
          const el = document.elementFromPoint(\(Double(pointer.x)) * vv.width + vv.offsetLeft, \(Double(pointer.y)) * vv.height + vv.offsetTop);
          const a = el && el.closest && el.closest('a[href], area[href]');
          if (!a) return null;
          const arc = \(list).some(s => [...document.querySelectorAll(s)].some(m => (m.closest('a') || m) === a));
          const r = a.getBoundingClientRect();
          return {x: (r.left - vv.offsetLeft) / vv.width, y: (r.top - vv.offsetTop) / vv.height,
                  width: r.width / vv.width, height: r.height / vv.height, arc, href: a.href};
        })()
        """
    }

    /// Which card a rested hover opens, if any. `shiftHeld` is Shift as the pointer reached the
    /// link; `arcLink` is the page script's answer.
    public static func kind(link: URL, page: URL?, shiftHeld: Bool, arcLink: Bool) -> Kind? {
        if shiftHeld {
            guard let page, let a = SiteKey.site(of: link.absoluteString), let b = SiteKey.site(of: page.absoluteString) else { return .summary }
            return a == b ? .link : .summary
        }
        return autoSite(page: page) != nil && arcLink ? .summary : nil
    }

    /// Whether resting on a link may open a card at all, before asking the page.
    public static func mayOpen(page: URL?, shiftHeld: Bool) -> Bool { shiftHeld || autoSite(page: page) != nil }

    /// The address as the small card shows it: host and path without the scheme or "www.".
    public static func displayAddress(_ url: URL) -> String {
        var s = url.absoluteString
        for prefix in ["https://", "http://"] where s.hasPrefix(prefix) { s.removeFirst(prefix.count) }
        if s.hasPrefix("www.") { s.removeFirst(4) }
        if s.hasSuffix("/"), s.filter({ $0 == "/" }).count == 1 { s.removeLast() }
        return s
    }

    /// Whether the link can be previewed at all: a web page on the public internet that isn't the
    /// page itself (an in-page #fragment). Hosts on this Mac or the local network are never
    /// fetched: a hover mustn't reach a router or a dev server.
    public static func canPreview(link: URL?, page: URL? = nil) -> Bool {
        guard let link, let scheme = link.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = link.host()?.lowercased(), isPublicHost(host) else { return false }
        if let page, sameDocument(link, page) { return false }
        return true
    }

    static func sameDocument(_ a: URL, _ b: URL) -> Bool {
        a.host()?.lowercased() == b.host()?.lowercased() && a.port == b.port && a.path() == b.path() && a.query() == b.query()
    }

    /// False for loopback, private, link-local and shared address ranges, IPv6 literals, single-label
    /// names and the local-only suffixes.
    public static func isPublicHost(_ rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        if host.isEmpty || host.contains(":") || host.hasPrefix("[") { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        if labels.count < 2 || labels.contains(where: \.isEmpty) { return false }
        for suffix in ["localhost", "local", "internal", "lan", "home", "intranet", "corp", "home.arpa"] {
            if host == suffix || host.hasSuffix("." + suffix) { return false }
        }
        if host.allSatisfy({ $0.isNumber || $0 == "." }) {
            // Short or odd forms (127.1, 0x7f.1 never gets here) resolve to whatever the resolver makes of them.
            let octets = labels.compactMap { Int($0) }
            guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else { return false }
            let (a, b) = (octets[0], octets[1])
            if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
            if a == 169 && b == 254 { return false }
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
            if a == 100 && (64...127).contains(b) { return false }
        }
        return true
    }

    /// What gets fetched for a link: the link itself, or https:// when the user turned on
    /// Always use secure connections, so a hover never makes a plain-text request a click wouldn't.
    public static func fetchURL(for link: URL, httpsOnly: Bool) -> URL {
        guard httpsOnly, link.scheme?.lowercased() == "http",
              var c = URLComponents(url: link, resolvingAgainstBaseURL: false) else { return link }
        c.scheme = "https"
        if c.port == 80 { c.port = nil }
        return c.url ?? link
    }

    /// The search on a Google results page, which Arc hands the model as the question to focus on.
    public static func searchQuery(page: URL?) -> String? {
        guard autoSite(page: page) == .google, let page, page.path().hasPrefix("/search"),
              let raw = URLComponents(url: page, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems?.first(where: { $0.name == "q" })?.value,
              // A form's + is a space; URLComponents leaves it.
              let q = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
              !q.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return q
    }
}

/// Preview-only network policy. Every hop is validated before it is requested; these limits
/// bound the whole page load and are Cra choices, not recovered Arc timeout values.
public enum LinkSummaryFetchPolicy {
    public static let maximumBytes = 1_048_576
    public static let maximumRedirects = 5
    public static let timeout: TimeInterval = 20

    public static func target(_ raw: String, relativeTo base: URL? = nil, httpsOnly: Bool) -> URL? {
        guard let parsed = URL(string: raw, relativeTo: base)?.absoluteURL,
              var parts = URLComponents(url: parsed, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil,
              LinkSummaryPolicy.canPreview(link: parsed), let host = parsed.host()?.lowercased() else { return nil }
        // Chromium accepts legacy hexadecimal and octal IPv4 forms. Reject ambiguous literals
        // before CEF canonicalizes them to a private address after the initial host check.
        let labels = host.trimmingCharacters(in: CharacterSet(charactersIn: ".")).split(separator: ".")
        let numeric = labels.allSatisfy { part in
            part.allSatisfy(\.isNumber) || (part.lowercased().hasPrefix("0x") && part.dropFirst(2).allSatisfy(\.isHexDigit))
        }
        if numeric && labels.contains(where: { $0.count > 1 && $0.first == "0" }) { return nil }
        parts.fragment = nil
        parts.host = host
        parts.scheme = parts.scheme?.lowercased()
        if parts.path.isEmpty { parts.path = "/" }
        guard let url = parts.url else { return nil }
        let secure = LinkSummaryPolicy.fetchURL(for: url, httpsOnly: httpsOnly)
        guard var canonical = URLComponents(url: secure, resolvingAgainstBaseURL: false) else { return nil }
        if (canonical.scheme == "http" && canonical.port == 80) || (canonical.scheme == "https" && canonical.port == 443) { canonical.port = nil }
        return canonical.url
    }
}

/// The text of a fetched page for the model.
public enum LinkSummaryContent {
    public struct Extracted: Equatable, Sendable {
        public var title: String?
        public var description: String?
        public var bodyText: String
        /// The page's share picture (og:image), as written: maybe relative to the page.
        public var image: String?

        public init(title: String? = nil, description: String? = nil, bodyText: String = "", image: String? = nil) {
            self.title = title
            self.description = description
            self.bodyText = bodyText
            self.image = image
        }

        /// The banner picture's address, resolved against the page, when it is a public web address.
        public func imageURL(page: URL) -> URL? {
            guard let image, let url = URL(string: image, relativeTo: page)?.absoluteURL,
                  LinkSummaryPolicy.canPreview(link: url) else { return nil }
            return url
        }
    }

    /// Extracted body cap before the complete request is fitted by LinkSummaryPrompt.
    /// Character counts alone do not establish a local model token fit.
    public static let maxContentLength = 2_400
    /// How much of the HTML is read. Pages put megabytes of script before their text; past this the
    /// card would wait on regexes for text the model has no room for.
    public static let maxHTMLLength = 400_000

    /// Title, meta description and visible text, from a page's HTML.
    public static func extractText(from html: String) -> Extracted {
        let source = String(html.prefix(maxHTMLLength))
        let headEnd = source.range(of: "</head>", options: [.caseInsensitive])
        let head = headEnd.map { String(source[..<$0.lowerBound]) } ?? String(source.prefix(64_000))

        var title: String?
        if let r = head.range(of: "(?is)<title[^>]*>(.*?)</title>", options: .regularExpression) {
            let tag = head[r]
            if let open = tag.firstIndex(of: ">"), let close = tag.range(of: "</", options: .backwards) {
                let clean = cleanHTMLText(String(tag[tag.index(after: open)..<close.lowerBound]))
                if !clean.isEmpty { title = clean }
            }
        }
        if title == nil { title = metaContent(in: head, names: ["og:title", "twitter:title"]) }
        let description = metaContent(in: head, names: ["description", "og:description", "twitter:description"])
        let image = metaContent(in: head, names: ["og:image", "og:image:url", "og:image:secure_url", "twitter:image"])

        var body = headEnd.map { String(source[$0.upperBound...]) } ?? source
        // Prefer the article when the page marks one: navigation and footers say little.
        for tag in ["article", "main"] {
            if let r = body.range(of: "(?is)<\(tag)[\\s>].*</\(tag)>", options: .regularExpression) {
                body = String(body[r])
                break
            }
        }
        for pattern in ["(?is)<script[^>]*>.*?</script>", "(?is)<style[^>]*>.*?</style>", "(?is)<svg[^>]*>.*?</svg>",
                        "(?is)<noscript[^>]*>.*?</noscript>", "(?is)<template[^>]*>.*?</template>", "(?s)<!--.*?-->"] {
            body = body.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        body = body.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        var text = cleanHTMLText(body)
        if text.count > maxContentLength { text = String(text.prefix(maxContentLength)) }
        return Extracted(title: title, description: description, bodyText: text, image: image)
    }

    /// The content of the first `<meta>` whose name or property is one of `names`, in that order.
    static func metaContent(in head: String, names: [String]) -> String? {
        var found: [String: String] = [:]
        var rest = head[...]
        while let r = rest.range(of: "(?is)<meta\\b[^>]*>", options: .regularExpression) {
            let tag = String(rest[r])
            rest = rest[r.upperBound...]
            guard let key = attribute("name", in: tag) ?? attribute("property", in: tag),
                  let content = attribute("content", in: tag) else { continue }
            let k = key.lowercased()
            if found[k] == nil { found[k] = cleanHTMLText(content) }
        }
        return names.lazy.compactMap { found[$0] }.first { !$0.isEmpty }
    }

    /// An attribute's value, quoted with " or ' (the other quote may appear inside it).
    static func attribute(_ name: String, in tag: String) -> String? {
        for q in ["\"", "'"] {
            let pattern = "(?i)\\s\(name)\\s*=\\s*\(q)([^\(q)]*)\(q)"
            if let r = tag.range(of: pattern, options: .regularExpression) {
                let m = tag[r]
                guard let open = m.firstIndex(of: Character(q)) else { continue }
                return String(m[m.index(after: open)..<m.index(before: m.endIndex)])
            }
        }
        return nil
    }

    /// Decodes the common entities (named and numeric) and folds whitespace.
    public static func cleanHTMLText(_ raw: String) -> String {
        var s = raw
        if s.contains("&") {
            for (entity, rep) in [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "),
                                  ("&mdash;", "—"), ("&ndash;", "–"), ("&hellip;", "…"), ("&rsquo;", "’"), ("&lsquo;", "‘"),
                                  ("&rdquo;", "”"), ("&ldquo;", "“"), ("&copy;", "©")] {
                s = s.replacingOccurrences(of: entity, with: rep)
            }
            s = decodeNumericEntities(s)
            s = s.replacingOccurrences(of: "&amp;", with: "&")
        }
        return s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func decodeNumericEntities(_ s: String) -> String {
        guard s.contains("&#") else { return s }
        var out = ""
        var rest = s[...]
        while let r = rest.range(of: "&#[xX]?[0-9a-fA-F]{1,6};", options: .regularExpression) {
            out += rest[..<r.lowerBound]
            let body = rest[r].dropFirst(2).dropLast()
            let value = body.first == "x" || body.first == "X" ? UInt32(body.dropFirst(), radix: 16) : UInt32(body)
            if let value, let scalar = Unicode.Scalar(value) { out.unicodeScalars.append(scalar) } else { out += rest[r] }
            rest = rest[r.upperBound...]
        }
        return out + rest
    }
}

/// What the model is asked, and how its answer becomes a card. The prompt is Arc's own (Arc 1.171,
/// HoverCardViewModel.loadSummary), with its JSON schema moved into the guided-generation type.
public enum LinkSummaryPrompt {
    public static let instructions = """
    As a concise and helpful summarizer, create a glanceable "answer card" containing the most important information from the webpage. \
    Capture the tone, perspective and POV of the writer.
    """

    /// The page as Arc hands it over, between `<webpage>` tags, with the search the user made when
    /// the link was a Google result.
    public static func prompt(url: String, content: LinkSummaryContent.Extracted, searchQuery: String?, language: String) -> String {
        fitted(url: url, content: content, searchQuery: searchQuery, language: language).prompt
    }

    private static func render(url: String, content: LinkSummaryContent.Extracted, searchQuery: String?, language: String) -> String {
        var page: [String] = ["URL: \(url)"]
        if let title = content.title { page.append("Title: \(title)") }
        if let description = content.description { page.append("Description: \(description)") }
        if !content.bodyText.isEmpty { page.append(content.bodyText) }
        var lines = ["WEBPAGE INFO:", "<webpage>", page.joined(separator: "\n"), "</webpage>"]
        if let searchQuery {
            lines.append("User search query: '\(searchQuery)'")
        }
        lines.append("Write responses (but not JSON keys) in \(language) using markdown formatting.")
        return lines.joined(separator: "\n")
    }

    /// A bounded model payload only. Original navigation/cache identity remains in LinkSummaryRequest.
    public struct Input: Equatable, Sendable {
        public let url: String
        public let content: LinkSummaryContent.Extracted
        public let searchQuery: String?
        public let language: String
        public var prompt: String { LinkSummaryPrompt.render(url: url, content: content, searchQuery: searchQuery, language: language) }
    }

    /// Cra's conservative earlier-OS allowance; exact SDK counts replace the estimate on 26.4+.
    public static let maximumPromptBytes = 1_536
    public static let responseTokenLimit = 1_024
    public static let contextSafetyMargin = 256
    public static let fallbackFixedTokens = 1_280

    public static func fitted(url: String, content: LinkSummaryContent.Extracted, searchQuery: String?, language: String,
                              compact: Bool = false) -> Input {
        let scale = compact ? 2 : 1
        func field(_ value: String, _ limit: Int) -> String { clip(value, characters: limit / scale, bytes: limit / scale) }
        let url = field(url, 256)
        let title = content.title.map { field($0, 160) }
        let description = content.description.map { field($0, 160) }
        let query = searchQuery.map { field($0, 128) }.flatMap { $0.isEmpty ? nil : $0 }
        let chosenLanguage = field(language, 48)
        let language = chosenLanguage.isEmpty ? "English" : chosenLanguage
        let metadata = LinkSummaryContent.Extracted(title: title, description: description)
        let overhead = render(url: url, content: metadata, searchQuery: query, language: language).utf8.count
        // Adding the body inserts one newline in the page's field list.
        let room = max(0, maximumPromptBytes / scale - overhead - 1)
        let body = clip(content.bodyText, characters: room, bytes: room)
        return Input(url: url, content: .init(title: title, description: description, bodyText: body), searchQuery: query, language: language)
    }

    /// Never splits a Character, including a combining sequence or joined emoji.
    private static func clip(_ value: String, characters: Int, bytes: Int) -> String {
        var output = "", used = 0
        for character in value.prefix(max(0, characters)) {
            let size = String(character).utf8.count
            guard size <= bytes - used else { break }
            output.append(character)
            used += size
        }
        return output
    }

    public static func fitsContext(inputTokens: Int, contextSize: Int) -> Bool {
        let reserve = responseTokenLimit + contextSafetyMargin
        return inputTokens >= 0 && contextSize >= reserve && inputTokens <= contextSize - reserve
    }

    /// Treat UTF-8 bytes as a conservative variable-token estimate, not an exact tokenizer.
    public static func fitsFallback(_ input: Input, contextSize: Int) -> Bool {
        fitsContext(inputTokens: input.prompt.utf8.count + fallbackFixedTokens, contextSize: contextSize)
    }

    /// Capture once in the request; only generated values are localized, never schema keys.
    public static func responseLanguage(preferredLanguages: [String]) -> String {
        let code = preferredLanguages.first.flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        return Locale(identifier: "en_US").localizedString(forLanguageCode: code) ?? "English"
    }

    /// Arc's row limits: 2 to 4 details.
    public static let maxDetails = 4

    /// The model's answer, cleaned into a card. Nil when it said the page is blocked (asks for
    /// JavaScript or a security check) or said nothing usable: the card then reads
    /// "No preview available", as Arc's does.
    public static func result(url: URL, title: String?, answer: Answer, final: Bool = false) -> LinkSummaryResult? {
        guard !answer.blocked else { return nil }
        let details = answer.details.compactMap { d -> LinkSummaryResult.Detail? in
            let label = clean(d.label).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            let info = clean(d.info)
            let icon = d.icon.trimmingCharacters(in: .whitespaces)
            guard !info.isEmpty, !final || (!label.isEmpty && !icon.isEmpty) else { return nil }
            return LinkSummaryResult.Detail(label: label, icon: icon, info: info)
        }.prefix(maxDetails)
        let quick = answer.quickSummary.map(clean) ?? ""
        guard !final || details.count >= 2 else { return nil }
        guard !details.isEmpty || !quick.isEmpty else { return nil }
        let host = displayHost(url)
        return LinkSummaryResult(url: url.absoluteString, title: title.map(clean).flatMap { $0.isEmpty ? nil : $0 } ?? host,
                                 host: host, quickSummary: quick.isEmpty ? nil : quick, details: Array(details))
    }

    /// The model's fields before cleaning.
    public struct Answer: Equatable, Sendable {
        public var blocked: Bool
        /// A generated search focus, not displayed or substituted for the quick summary.
        public var userQuestion: String?
        public var quickSummary: String?
        public var details: [LinkSummaryResult.Detail]

        public init(blocked: Bool, userQuestion: String? = nil, quickSummary: String?, details: [LinkSummaryResult.Detail]) {
            self.blocked = blocked
            self.userQuestion = userQuestion
            self.quickSummary = quickSummary
            self.details = details
        }
    }

    /// Arc asks for markdown; the card shows plain text, so emphasis marks and stray quotes go.
    static func clean(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
        t = t.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 2, t.first == "\"", t.last == "\"" { t = String(t.dropFirst().dropLast()) }
        return t.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The host as the card shows it, without www.
    public static func displayHost(_ url: URL) -> String {
        guard let h = url.host()?.lowercased() else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// The test model's answer (CRA_TIDY_FAKE_MODEL=1): the page's description and first sentences.
    public static func fakeAnswer(content: LinkSummaryContent.Extracted) -> Answer {
        let sentences = content.bodyText.split(whereSeparator: { ".!?".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.count > 12 }
        let details = sentences.prefix(3).enumerated().map {
            LinkSummaryResult.Detail(label: "Point \($0.offset + 1)", icon: "text.alignleft", info: $0.element)
        }
        return Answer(blocked: details.isEmpty && content.description == nil,
                      quickSummary: content.description ?? content.title ?? "", details: details)
    }
}

/// A preview's fetch and model context. Arc keys cards by URL and browser context; the local
/// answer also depends on search, language and secure-connection policy.
public struct LinkSummaryRequest: Hashable, Sendable {
    public enum Profile: Hashable, Sendable {
        case `default`
        case path(String)
    }

    public let link: URL
    public let profile: Profile
    public let httpsOnly: Bool
    public let searchQuery: String?
    public let language: String

    public init(link: URL, profilePath: String?, httpsOnly: Bool, searchQuery: String?, language: String) {
        self.link = link
        // CEF treats both nil and an empty profile path as its global Default context.
        self.profile = profilePath.flatMap { $0.isEmpty ? nil : .path($0) } ?? .default
        self.httpsOnly = httpsOnly
        self.searchQuery = searchQuery
        self.language = language
    }

    public var profilePath: String? {
        if case .path(let path) = profile { return path }
        return nil
    }

    public var fetchURL: URL { LinkSummaryPolicy.fetchURL(for: link, httpsOnly: httpsOnly) }
}

/// The document that originated a hover. A matching URL alone cannot identify a browser,
/// navigation back to the same page, another tab or another window.
public struct LinkSummaryContext: Equatable, Sendable {
    public let request: LinkSummaryRequest
    public let page: URL?
    public let windowID: UUID
    public let tabID: UUID
    public let runtimeID: ObjectIdentifier
    public let navigationRevision: UInt

    public init(request: LinkSummaryRequest, page: URL?, windowID: UUID, tabID: UUID,
                runtimeID: ObjectIdentifier, navigationRevision: UInt) {
        self.request = request
        self.page = page
        self.windowID = windowID
        self.tabID = tabID
        self.runtimeID = runtimeID
        self.navigationRevision = navigationRevision
    }
}

/// Completed usable summaries, newest last. Failed or blocked pages are retried on the next
/// hover, rather than retaining a temporary model failure or login challenge for the app's life.
public struct LinkSummaryCache: Sendable {
    public let limit: Int
    private var order: [LinkSummaryRequest] = []
    private var entries: [LinkSummaryRequest: LinkSummaryResult] = [:]

    public init(limit: Int = 40) { self.limit = limit }

    public func lookup(_ key: LinkSummaryRequest) -> LinkSummaryResult? { entries[key] }

    public mutating func store(_ value: LinkSummaryResult?, for key: LinkSummaryRequest) {
        guard let value else { return }
        if entries.updateValue(value, forKey: key) != nil { order.removeAll { $0 == key } }
        order.append(key)
        while order.count > limit { entries.removeValue(forKey: order.removeFirst()) }
    }

    public var count: Int { entries.count }
}
