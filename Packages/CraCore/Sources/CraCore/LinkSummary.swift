import Foundation

/// Arc Max's 5-Second Previews (fiveSecondPreviews / link hover summaries), done by the Mac's
/// own Apple Intelligence model (FoundationModels, macOS 26).
///
/// On certain sites (Google, DuckDuckGo, Bing, X/Twitter, Threads, HackerNews), hovering over a
/// link automatically summarizes the destination webpage. On other sites, pressing or holding Shift
/// while hovering over a link triggers the summary. This decides which links may be summarized,
/// extracts and prepares the webpage text for the model prompt, and formats the generated bullet points.
public enum LinkSummaryPolicy {
    /// Sites where hovering over a link runs automatically without requiring Shift.
    public static func isAutoHoverSite(url: URL?) -> Bool {
        guard let host = url?.host()?.lowercased() else { return false }
        return isAutoHoverHost(host)
    }

    /// Checks if a host name belongs to one of the automatic hover preview sites:
    /// Google search, DuckDuckGo, Bing, X (Twitter), Threads, and HackerNews.
    public static func isAutoHoverHost(_ host: String) -> Bool {
        let clean = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if clean == "duckduckgo.com" || clean.hasSuffix(".duckduckgo.com") { return true }
        if clean == "bing.com" || clean.hasSuffix(".bing.com") { return true }
        if clean == "x.com" || clean.hasSuffix(".x.com") || clean == "twitter.com" || clean.hasSuffix(".twitter.com") { return true }
        if clean == "threads.net" || clean.hasSuffix(".threads.net") { return true }
        if clean == "news.ycombinator.com" || clean == "hacker-news.firebaseio.com" { return true }
        if isGoogleHost(clean) { return true }
        return false
    }

    private static func isGoogleHost(_ host: String) -> Bool {
        if host == "google.com" || host.hasSuffix(".google.com") { return true }
        // International Google domains: google.co.uk, google.fr, google.de, google.co.jp, etc.
        let parts = host.split(separator: ".")
        if let gIndex = parts.firstIndex(of: "google"), gIndex >= parts.count - 3 {
            return true
        }
        return false
    }

    /// Decides whether a link hover should trigger a summary given the current page URL and Shift modifier.
    public static func shouldTrigger(pageURL: URL?, isShiftPressed: Bool) -> Bool {
        if isAutoHoverSite(url: pageURL) { return true }
        return isShiftPressed
    }

    /// Whether the destination URL is eligible for preview: must be http(s), not local or internal,
    /// and not an in-page fragment of the source page.
    public static func canSummarize(targetURL: URL?, pageURL: URL? = nil) -> Bool {
        guard let targetURL, let scheme = targetURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        guard let targetHost = targetURL.host()?.lowercased(), !targetHost.isEmpty else { return false }
        if targetHost == "localhost" || targetHost == "127.0.0.1" { return false }
        if let pageURL, targetURL.scheme == pageURL.scheme,
           targetURL.host == pageURL.host,
           targetURL.port == pageURL.port,
           targetURL.path == pageURL.path,
           targetURL.query == pageURL.query {
            return false
        }
        return true
    }
}

/// Content extraction from HTML for summarizing destination webpages.
public enum LinkSummaryContent {
    public struct Extracted: Equatable {
        public var title: String?
        public var description: String?
        public var bodyText: String

        public init(title: String? = nil, description: String? = nil, bodyText: String = "") {
            self.title = title
            self.description = description
            self.bodyText = bodyText
        }
    }

    /// Maximum text length passed to the Apple Intelligence prompt to stay within token budgets.
    public static let maxContentLength = 800

    /// Extracts title, meta description, and cleaned body text from HTML.
    /// Optimized for high speed: scans the document header (<head> slice) for metadata
    /// and processes only the early body slice instead of running regexes across megabytes of HTML.
    public static func extractText(from html: String) -> Extracted {
        var title: String?
        var description: String?

        // Fast head isolation: metadata is always in <head> or the first 32 KB.
        let scanSlice = String(html.prefix(32_000))

        // Title tag: <title>(.*?)</title>
        if let titleRange = scanSlice.range(of: "(?i)<title[^>]*>(.*?)</title>", options: .regularExpression) {
            let tagContent = scanSlice[titleRange]
            if let start = tagContent.firstIndex(of: ">"), let end = tagContent.lastIndex(of: "<"), start < end {
                let inner = String(tagContent[tagContent.index(after: start)..<end])
                let clean = cleanHTMLText(inner)
                if !clean.isEmpty { title = clean }
            }
        }

        // Meta description: <meta name="description" content="..."> or property="og:description"
        let descPatterns = [
            "(?i)<meta[^>]+(?:name=[\"']description[\"']|property=[\"']og:description[\"'])[^>]+content=[\"']([^\"']*)[\"']",
            "(?i)<meta[^>]+content=[\"']([^\"']*)[\"'][^>]+(?:name=[\"']description[\"']|property=[\"']og:description[\"'])",
        ]
        for pattern in descPatterns {
            if description != nil { break }
            if let match = scanSlice.range(of: pattern, options: .regularExpression) {
                let tag = String(scanSlice[match])
                if let contentRange = tag.range(of: "(?i)content=[\"']([^\"']*)[\"']", options: .regularExpression) {
                    let sub = tag[contentRange]
                    if let firstQuote = sub.firstIndex(where: { $0 == "\"" || $0 == "'" }),
                       let lastQuote = sub.lastIndex(where: { $0 == "\"" || $0 == "'" }),
                       firstQuote < lastQuote {
                        let text = String(sub[sub.index(after: firstQuote)..<lastQuote])
                        let clean = cleanHTMLText(text)
                        if !clean.isEmpty { description = clean }
                    }
                }
            }
        }

        // Fast body isolation: only clean the first 20 KB of the body to keep regexes sub-millisecond.
        let bodySource: String
        if let headEnd = html.range(of: "(?i)</head>", options: .regularExpression) {
            let afterHead = html[headEnd.upperBound...]
            bodySource = String(afterHead.prefix(20_000))
        } else {
            bodySource = String(html.prefix(20_000))
        }

        // Strip non-content blocks: scripts, styles, svg, noscript
        var cleaned = bodySource
        let stripPatterns = [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<svg[^>]*>.*?</svg>",
            "(?is)<noscript[^>]*>.*?</noscript>",
            "(?is)<!--.*?-->",
        ]
        for pattern in stripPatterns {
            cleaned = cleaned.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }

        // Strip remaining HTML tags
        cleaned = cleaned.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        cleaned = cleanHTMLText(cleaned)

        if cleaned.count > maxContentLength {
            cleaned = String(cleaned.prefix(maxContentLength))
        }

        return Extracted(title: title, description: description, bodyText: cleaned)
    }

    /// Decodes HTML entities and normalizes whitespace.
    public static func cleanHTMLText(_ raw: String) -> String {
        var s = raw
        let entities = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&#39;", "'"),
            ("&apos;", "'"),
            ("&nbsp;", " "),
            ("&#x2F;", "/"),
            ("&#47;", "/"),
            ("&mdash;", "—"),
            ("&ndash;", "–"),
        ]
        for (entity, rep) in entities {
            s = s.replacingOccurrences(of: entity, with: rep)
        }
        // Normalize whitespace
        let words = s.split(whereSeparator: \.isWhitespace)
        return words.joined(separator: " ")
    }
}

/// The prompt and instructions given to Apple Intelligence (FoundationModels).
public enum LinkSummaryPrompt {
    public static let instructions = """
    You summarize destination webpages into an Arc Max preview card. \
    Format your response strictly as:
    Line 1: A one-sentence takeaway or verdict summarizing the page.
    Subsequent lines: 2 to 4 concise bullet points. Each bullet point MUST begin with a short keyword followed by a colon, like:
    - Keyword: One clear sentence explanation.
    Focus on concrete facts, features, and takeaways. Do not use filler like 'This article discusses'. \
    Respond in the language of the webpage content.
    """

    /// Formats the prompt sent to the Apple Intelligence model.
    public static func prompt(title: String, url: String, description: String? = nil, content: String) -> String {
        var lines: [String] = []
        if !title.isEmpty { lines.append("Title: \(title)") }
        lines.append("URL: \(url)")
        if let description, !description.isEmpty {
            lines.append("Description: \(description)")
        }
        if !content.isEmpty {
            lines.append("Content:\n\(content)")
        }
        lines.append("\nSummarize into a 1-sentence verdict, then 2 to 4 bullet points formatted as '- Keyword: description'.")
        return lines.joined(separator: "\n")
    }

    /// Parses the raw model text into a headline verdict and a list of bullet points.
    public static func parseResponse(_ text: String, fallbackHeadline: String? = nil) -> (headline: String?, bullets: [String]) {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var headline: String?
        var rawBullets: [String] = []

        for line in lines {
            if line.hasPrefix("- ") || line.hasPrefix("• ") || line.hasPrefix("* ") {
                rawBullets.append(line)
            } else if headline == nil && !line.hasPrefix("-") && !line.hasPrefix("•") && line.count > 15 && !line.lowercased().hasPrefix("title:") {
                let h = line.replacingOccurrences(of: "(?i)^headline:\\s*", with: "", options: .regularExpression)
                if !h.isEmpty { headline = h }
            } else if line.contains(":") {
                rawBullets.append(line)
            }
        }

        let bullets = cleanBullets(rawBullets)
        return (headline: headline ?? fallbackHeadline, bullets: bullets)
    }

    /// Cleans and formats bullets returned by the model.
    public static func cleanBullets(_ raw: [String], max: Int = 3) -> [String] {
        var cleaned: [String] = []
        for line in raw {
            var b = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Strip leading bullet markers like "• ", "- ", "* ", "1. "
            if b.hasPrefix("• ") || b.hasPrefix("- ") || b.hasPrefix("* ") {
                b = String(b.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            } else if let dot = b.firstIndex(of: "."), b[..<dot].allSatisfy(\.isNumber),
                      dot < b.index(b.startIndex, offsetBy: min(3, b.count)) {
                b = String(b[b.index(after: dot)...]).trimmingCharacters(in: .whitespaces)
            }
            if !b.isEmpty && b.count <= 300 {
                cleaned.append(b)
            }
            if cleaned.count >= max { break }
        }
        return cleaned
    }

    /// Formats a readable host name (dropping www).
    public static func host(_ url: URL) -> String {
        guard let h = url.host()?.lowercased() else { return "" }
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    /// Provides realistic bullets for test runs when Apple Intelligence is simulated.
    public static func fakeAnswer(title: String, url: URL, content: LinkSummaryContent.Extracted) -> LinkSummaryResult {
        let cleanTitle = content.title ?? (title.isEmpty ? host(url) : title)
        let headline = content.description ?? "Overview and key takeaways regarding \(cleanTitle)."
        var bullets: [String] = []
        if let desc = content.description, !desc.isEmpty {
            bullets.append(desc)
        }
        let sentences = content.bodyText.split(whereSeparator: { $0 == "." || $0 == "!" || $0 == "?" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count > 25 && $0.count < 180 }
        for sentence in sentences {
            if bullets.count >= 4 { break }
            if !bullets.contains(sentence) {
                bullets.append(sentence)
            }
        }
        if bullets.isEmpty {
            bullets = [
                "Overview and details regarding \(cleanTitle).",
                "Key takeaways and information from \(host(url)).",
            ]
        }
        return LinkSummaryResult(
            url: url.absoluteString,
            title: cleanTitle,
            host: host(url),
            headline: headline,
            bullets: bullets
        )
    }
}

/// The structured summary of a link's destination page matching Arc Max's preview card.
public struct LinkSummaryResult: Codable, Equatable, Sendable {
    public var url: String
    public var title: String
    public var host: String
    public var headline: String?
    public var bullets: [String]

    public init(url: String, title: String, host: String, headline: String? = nil, bullets: [String]) {
        self.url = url
        self.title = title
        self.host = host
        self.headline = headline
        self.bullets = bullets
    }
}
