import Foundation

/// A site's icon for places that show a site Cra may never have opened (a boost on Library ▸
/// Boosts): read from its home page's `<link rel=icon>` tags as a page's icon is (the largest it
/// declares, bitmaps before SVG), then /favicon.ico.
public enum SiteIcon {
    /// Where to look, best first, from the page at `base`.
    public static func candidates(html: String, base: URL) -> [URL] {
        var links: [(url: URL, size: Int, svg: Bool)] = []
        var rest = Substring(html)
        while let open = rest.range(of: "<link", options: .caseInsensitive) {
            guard let close = rest.range(of: ">", range: open.upperBound..<rest.endIndex) else { break }
            let tag = String(rest[open.upperBound..<close.lowerBound])
            rest = rest[close.upperBound...]
            guard let rel = attribute("rel", in: tag)?.lowercased(),
                  rel.split(separator: " ").contains(where: { $0 == "icon" || $0 == "apple-touch-icon" }),
                  let href = attribute("href", in: tag), let url = URL(string: decode(href), relativeTo: base)?.absoluteURL,
                  ["http", "https"].contains(url.scheme ?? "") else { continue }
            let size = (attribute("sizes", in: tag) ?? "").split(separator: " ")
                .compactMap { Int($0.lowercased().split(separator: "x").first ?? "") }.max() ?? 0
            let svg = url.path.lowercased().hasSuffix(".svg") || attribute("type", in: tag)?.contains("svg") == true
            links.append((url, size, svg))
        }
        var out = links.enumerated().sorted { a, b in
            if a.element.svg != b.element.svg { return !a.element.svg }
            if a.element.size != b.element.size { return a.element.size > b.element.size }
            return a.offset < b.offset
        }.map(\.element.url)
        if let ico = URL(string: "/favicon.ico", relativeTo: base)?.absoluteURL, !out.contains(ico) { out.append(ico) }
        return out
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let pattern = "(?i)(?:^|\\s)" + name + "\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+))"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)) else { return nil }
        for i in 1...3 { if let r = Range(m.range(at: i), in: tag) { return String(tag[r]) } }
        return nil
    }

    private static func decode(_ s: String) -> String { s.replacingOccurrences(of: "&amp;", with: "&") }
}
