import Foundation

/// Site icons: the ones an open page names, and for pages the phone has not opened (the Mac's
/// pinned tabs in the Spaces sheet) the ones the site's home page names, read from its HTML.
/// Asked of the site itself, never of an icon service, which would learn every site the user keeps.
public enum MobileFavicons {
    /// One `<link>` in a page's head: read from its HTML (`iconLinks(inHTML:page:)`), or from the
    /// open page itself, whose links the web view reports.
    public struct IconLink: Equatable, Sendable {
        public var rel: String
        public var href: String
        public var sizes: String?
        public var type: String?

        public init(rel: String, href: String, sizes: String? = nil, type: String? = nil) {
            self.rel = rel
            self.href = href
            self.sizes = sizes
            self.type = type
        }
    }

    /// The `<link rel="icon">` addresses in the page's head, best first (`bestFirst`).
    public static func iconLinks(inHTML html: String, page: URL) -> [String] {
        let head = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.lowerBound]) } ?? html
        let links = matches(#"<link\b[^>]*>"#, in: head).compactMap { tag -> IconLink? in
            guard let rel = attribute("rel", in: tag), let href = attribute("href", in: tag) else { return nil }
            return IconLink(rel: rel, href: href, sizes: attribute("sizes", in: tag), type: attribute("type", in: tag))
        }
        return bestFirst(links, page: page)
    }

    /// The icons among `links`, best first for a 21 pt row or a tab card's 18 pt header: sized
    /// icons largest first (an unsized one counts as 24 px, since an .ico often holds several),
    /// then `/favicon.ico` when the page doesn't name it, then touch icons. A touch icon is an app
    /// icon, an opaque square that would hide the site's own shape (a round or see-through
    /// favicon), so it is shown only when the site has nothing else. SVG is left out (UIImage
    /// can't draw it).
    public static func bestFirst(_ links: [IconLink], page: URL) -> [String] {
        var found: [(url: String, rank: Double)] = []
        for link in links {
            guard let url = URL(string: link.href, relativeTo: page)?.absoluteURL,
                  url.scheme == "https" || url.scheme == "http" else { continue }
            let words = Set(link.rel.lowercased().split(separator: " ").map(String.init))
            let touch = words.contains("apple-touch-icon") || words.contains("apple-touch-icon-precomposed")
            guard words.contains("icon") || touch else { continue }
            let type = link.type?.lowercased() ?? ""
            guard !url.path.lowercased().hasSuffix(".svg"), !type.contains("svg") else { continue }
            let size = link.sizes.flatMap { Double($0.lowercased().split(separator: "x").first ?? "") } ?? 24
            found.append((url.absoluteString, touch ? -1 : size))
        }
        if let fallback = URL(string: "/favicon.ico", relativeTo: page)?.absoluteURL.absoluteString,
           !found.contains(where: { $0.url == fallback }) {
            found.append((fallback, 0))
        }
        var seen = Set<String>()
        return found.enumerated().sorted { a, b in
            a.element.rank != b.element.rank ? a.element.rank > b.element.rank : a.offset < b.offset
        }.map(\.element.url).filter { seen.insert($0).inserted }
    }

    /// Whether an icon is a dark, colourless mark with see-through parts (GitHub's octocat), which
    /// a dark sheet would swallow: drawn in the text's colour there instead, as Arc Search does.
    /// `coverage` is the share of pixels that aren't see-through; over those, `luminance` is the
    /// mean, `chroma` the mean of max - min channel (absolute, so a near-black slate like
    /// GitHub's #1F2328 counts as colourless), and `lightShare` the share brighter than 0.6. An
    /// icon with light parts of its own (Vercel's white triangle on a black disc) shows as it is.
    public static func drawsAsMark(coverage: Double, luminance: Double, chroma: Double, lightShare: Double) -> Bool {
        coverage < 0.9 && luminance < 0.25 && chroma < 0.08 && lightShare < 0.03
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { Range($0.range, in: text).map { String(text[$0]) } }
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "\\b\(name)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s>]+))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for group in 1...3 {
            if let range = Range(match.range(at: group), in: tag) {
                return String(tag[range]).replacingOccurrences(of: "&amp;", with: "&")
            }
        }
        return nil
    }
}
