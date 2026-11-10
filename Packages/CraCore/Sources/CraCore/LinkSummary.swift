import Foundation

/// Arc Max's 5-Second Previews, which Arc calls hover cards (`hoverCardsEnabled`, the HoverCards
/// module): a card that summarizes the page behind a link, done here by the Mac's own Apple
/// Intelligence model instead of Arc's server.
///
/// Arc shows a card on its own for some links on three sites (`HoverCardsSupportedDomain`: Google,
/// X and Hacker News), and for any link while Shift is held. Its settings text: "Instant summaries
/// appear when you hover over links on certain websites. Or hold Shift while hovering to preview
/// any link." Nothing is fetched before one of those triggers.
public enum LinkSummaryPolicy {
    /// The sites where a hover alone shows a card.
    public enum Site: Equatable, Sendable {
        case google, x, hackerNews
    }

    /// Arc's supported domains. On Google only the results page counts: Arc's selector there
    /// (`g-section-with-header a [role=heading]`) is a search result's heading.
    public static func autoSite(page: URL?) -> Site? {
        guard let page, let host = page.host()?.lowercased() else { return nil }
        let h = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if h == "news.ycombinator.com" { return .hackerNews }
        if ["x.com", "twitter.com", "mobile.x.com", "mobile.twitter.com"].contains(h) { return .x }
        if isGoogleSearchHost(h), page.path().hasPrefix("/search") { return .google }
        return nil
    }

    /// google.com, google.fr, google.co.uk: Google's own site, not mail.google.com or a Google
    /// subdomain of something else.
    static func isGoogleSearchHost(_ host: String) -> Bool {
        guard host.hasPrefix("google."), let site = SiteKey.site(of: "https://\(host)") else { return false }
        return site == host
    }

    /// Hosts whose links on a results page are ads, not results.
    static let adHosts: Set<String> = ["googleadservices.com", "doubleclick.net", "googlesyndication.com"]

    /// Whether resting on this link shows a card without Shift. Arc picks the links by selector:
    /// Hacker News's story titles (`.title .titleline > a`), links in a post on X
    /// (`[data-testid=tweetText] a`, link cards), Google's result headings. Cra only learns the
    /// hovered URL, so it takes the links that leave the site: a story's page, a t.co link, a
    /// result. The site's own links (comments, profiles, "hide", "login") and ads stay out.
    public static func autoHovers(link: URL, page: URL?) -> Bool {
        guard let site = autoSite(page: page), let page,
              let linkSite = SiteKey.site(of: link.absoluteString),
              let pageSite = SiteKey.site(of: page.absoluteString), linkSite != pageSite else { return false }
        if adHosts.contains(linkSite) { return false }
        if site == .google, isGoogleSearchHost(linkSite) { return false }
        if site == .x, linkSite == "x.com" || linkSite == "twitter.com" { return false }
        return true
    }

    /// Whether a hover shows a card: Shift anywhere, or one of the links above.
    public static func shouldTrigger(link: URL, page: URL?, shiftHeld: Bool) -> Bool {
        shiftHeld || autoHovers(link: link, page: page)
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
        guard autoSite(page: page) == .google, let page,
              let raw = URLComponents(url: page, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems?.first(where: { $0.name == "q" })?.value,
              // A form's + is a space; URLComponents leaves it.
              let q = raw.replacingOccurrences(of: "+", with: " ").removingPercentEncoding,
              !q.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return q
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

    /// Body text handed to the model. The on-device model has a 4,096-token context, shared with
    /// the instructions and the answer; 2,400 characters is about 600 tokens of English.
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
        var page: [String] = ["URL: \(url)"]
        if let title = content.title { page.append("Title: \(title)") }
        if let description = content.description { page.append("Description: \(description)") }
        if !content.bodyText.isEmpty { page.append(content.bodyText) }
        var lines = ["WEBPAGE INFO:", "<webpage>", page.joined(separator: "\n"), "</webpage>"]
        if let searchQuery {
            lines.append("Focus the answer card on the user's search query: '\(searchQuery)'.")
        }
        lines.append("Write responses in \(language).")
        return lines.joined(separator: "\n")
    }

    /// Arc's row limits: 2 to 4 details.
    public static let maxDetails = 4

    /// The model's answer, cleaned into a card. Nil when it said the page is blocked (asks for
    /// JavaScript or a security check) or said nothing usable: the card then reads
    /// "No preview available", as Arc's does.
    public static func result(url: URL, title: String?, answer: Answer) -> LinkSummaryResult? {
        guard !answer.blocked else { return nil }
        let details = answer.details.compactMap { d -> LinkSummaryResult.Detail? in
            let label = clean(d.label).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            let info = clean(d.info)
            guard !info.isEmpty else { return nil }
            return LinkSummaryResult.Detail(label: label, icon: d.icon.trimmingCharacters(in: .whitespaces), info: info)
        }.prefix(maxDetails)
        let quick = clean(answer.quickSummary)
        guard !details.isEmpty || !quick.isEmpty else { return nil }
        let host = displayHost(url)
        return LinkSummaryResult(url: url.absoluteString, title: title.map(clean).flatMap { $0.isEmpty ? nil : $0 } ?? host,
                                 host: host, quickSummary: quick.isEmpty ? nil : quick, details: Array(details))
    }

    /// The model's fields before cleaning.
    public struct Answer: Equatable, Sendable {
        public var blocked: Bool
        public var quickSummary: String
        public var details: [LinkSummaryResult.Detail]

        public init(blocked: Bool, quickSummary: String, details: [LinkSummaryResult.Detail]) {
            self.blocked = blocked
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

/// A card's content.
public struct LinkSummaryResult: Equatable, Sendable {
    public struct Detail: Equatable, Sendable {
        /// Arc's examples: "Price", "Story", "Solution 1", "Highlights", "Criticism".
        public var label: String
        /// An SF Symbol name the model chose; the card falls back when the system has no such symbol.
        public var icon: String
        public var info: String

        public init(label: String, icon: String, info: String) {
            self.label = label
            self.icon = icon
            self.info = info
        }
    }

    public var url: String
    public var title: String
    public var host: String
    public var quickSummary: String?
    public var details: [Detail]

    public init(url: String, title: String, host: String, quickSummary: String?, details: [Detail]) {
        self.url = url
        self.title = title
        self.host = host
        self.quickSummary = quickSummary
        self.details = details
    }
}

/// Summaries already made, newest last, so hovering a link again shows its card at once without
/// growing for as long as Cra runs.
public struct LinkSummaryCache: Sendable {
    public let limit: Int
    private var order: [String] = []
    private var entries: [String: LinkSummaryResult?] = [:]

    public init(limit: Int = 40) { self.limit = limit }

    /// `.some(nil)` is a page known to have no preview.
    public func lookup(_ key: String) -> LinkSummaryResult?? { entries[key] }

    public mutating func store(_ value: LinkSummaryResult?, for key: String) {
        if entries.updateValue(value, forKey: key) != nil { order.removeAll { $0 == key } }
        order.append(key)
        while order.count > limit { entries.removeValue(forKey: order.removeFirst()) }
    }

    public var count: Int { entries.count }
}

/// The card's size and place, measured on Arc 1.171 (10 Nov 2026, a Hacker News story on a 2x
/// display): 300 pt wide, a 100 pt banner, 15 pt margins, rows indented to 39 pt, 6 pt between
/// rows, 12 pt corners. It hangs 6 pt under the link, 7 pt left of the link's start.
public enum LinkSummaryCardLayout {
    public static let width: CGFloat = 300
    public static let bannerHeight: CGFloat = 100
    public static let cornerRadius: CGFloat = 12
    public static let margin: CGFloat = 15
    public static let rowIndent: CGFloat = 39
    public static let rowGap: CGFloat = 6
    public static let lineHeight: CGFloat = 18.5
    /// Room under the last row for the share button (32 pt, its centre 24 pt from the right and
    /// 25 pt from the bottom).
    public static let bottomInset: CGFloat = 40
    public static let shareButton: CGFloat = 32
    static let gapBelowLink: CGFloat = 6
    static let leadBeforeLink: CGFloat = 7

    /// Where the card goes, in screen coordinates (y up). Under the link when it fits on the
    /// screen, else above it; without the link's frame, under the pointer. Kept 8 pt inside the screen.
    public static func origin(size: CGSize, link: CGRect?, pointer: CGPoint, screen: CGRect) -> CGPoint {
        let anchor = link ?? CGRect(x: pointer.x - 20, y: pointer.y - 10, width: 40, height: 20)
        var x = anchor.minX - leadBeforeLink
        var y = anchor.minY - gapBelowLink - size.height
        if y < screen.minY + 8 { y = anchor.maxY + gapBelowLink }
        x = min(max(x, screen.minX + 8), screen.maxX - 8 - size.width)
        y = min(max(y, screen.minY + 8), screen.maxY - 8 - size.height)
        return CGPoint(x: x.rounded(), y: y.rounded())
    }
}
