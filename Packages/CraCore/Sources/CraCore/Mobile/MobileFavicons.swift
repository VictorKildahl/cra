import Foundation

/// Site icons for pages the phone has not opened (the Mac's pinned tabs in the Spaces sheet):
/// the icons the site's home page names, read from its HTML. Asked of the site itself, never of
/// an icon service, which would learn every site the user keeps.
public enum MobileFavicons {
    /// The `<link rel="icon">` addresses in the page's head, best first for a 21 pt row: sized
    /// icons largest first (an unsized one counts as 24 px, since an .ico often holds several),
    /// then touch icons, which are drawn as app icons; SVG left out (UIImage can't draw it);
    /// `/favicon.ico` last when the page doesn't name it.
    public static func iconLinks(inHTML html: String, page: URL) -> [String] {
        let head = html.range(of: "</head>", options: .caseInsensitive).map { String(html[..<$0.lowerBound]) } ?? html
        var found: [(url: String, rank: Double)] = []
        for tag in matches(#"<link\b[^>]*>"#, in: head) {
            guard let rel = attribute("rel", in: tag)?.lowercased(), let href = attribute("href", in: tag),
                  let url = URL(string: href, relativeTo: page)?.absoluteURL,
                  url.scheme == "https" || url.scheme == "http" else { continue }
            let words = Set(rel.split(separator: " ").map(String.init))
            let touch = words.contains("apple-touch-icon") || words.contains("apple-touch-icon-precomposed")
            guard words.contains("icon") || touch else { continue }
            let type = attribute("type", in: tag)?.lowercased() ?? ""
            guard !url.path.lowercased().hasSuffix(".svg"), !type.contains("svg") else { continue }
            let size = attribute("sizes", in: tag).flatMap { Double($0.lowercased().split(separator: "x").first ?? "") } ?? 24
            found.append((url.absoluteString, touch ? -1 : size))
        }
        var seen = Set<String>()
        var links = found.enumerated().sorted { a, b in
            a.element.rank != b.element.rank ? a.element.rank > b.element.rank : a.offset < b.offset
        }.map(\.element.url).filter { seen.insert($0).inserted }
        if let fallback = URL(string: "/favicon.ico", relativeTo: page)?.absoluteURL.absoluteString, !seen.contains(fallback) {
            links.append(fallback)
        }
        return links
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
