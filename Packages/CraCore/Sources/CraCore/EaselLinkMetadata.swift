import Foundation

/// What a link card shows, read from the page's HTML the way Arc's MetaTagParser does (its
/// selectors, in order: og:title, then <title>; og:description, then meta description; og:image).
public struct EaselLinkMetadata: Equatable, Sendable {
    public var title: String?
    public var summary: String?
    /// Absolute.
    public var image: String?
    /// The site's icon for the card's bar, absolute: apple-touch-icon, else icon, else /favicon.ico.
    public var icon: String?

    public init(title: String? = nil, summary: String? = nil, image: String? = nil, icon: String? = nil) {
        (self.title, self.summary, self.image, self.icon) = (title, summary, image, icon)
    }

    /// Only the page's <head> is read, at most this much.
    public static let maxBytes = 512 * 1024

    public static func parse(html: String, url: String) -> EaselLinkMetadata {
        let head = String(html.prefix(maxBytes))
        var metas: [(key: String, content: String)] = []
        for tag in matches(#"<meta\b[^>]*>"#, in: head) {
            let attrs = attributes(tag)
            guard let content = attrs["content"] else { continue }
            if let key = attrs["property"] ?? attrs["name"] { metas.append((key.lowercased(), decode(content))) }
        }
        func meta(_ key: String) -> String? {
            metas.first { $0.key == key }.map(\.content).map(clean).flatMap { $0.isEmpty ? nil : $0 }
        }
        let titleTag = matches(#"<title\b[^>]*>[\s\S]*?</title>"#, in: head).first.map {
            clean(decode($0.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)))
        }
        let image = (meta("og:image") ?? meta("og:image:url") ?? meta("twitter:image")).flatMap { absolute($0, base: url) }
        var icons: [(rel: String, href: String)] = []
        for tag in matches(#"<link\b[^>]*>"#, in: head) {
            let attrs = attributes(tag)
            if let rel = attrs["rel"]?.lowercased(), let href = attrs["href"] { icons.append((rel, decode(href))) }
        }
        let icon = ["apple-touch-icon", "icon", "shortcut icon"].lazy.compactMap { want in icons.first { $0.rel == want }?.href }.first
        return EaselLinkMetadata(title: meta("og:title") ?? titleTag.flatMap { $0.isEmpty ? nil : $0 },
                                 summary: meta("og:description") ?? meta("description"),
                                 image: image,
                                 icon: absolute(icon ?? "/favicon.ico", base: url))
    }

    static func absolute(_ s: String, base: String) -> String? {
        guard let u = URL(string: s, relativeTo: URL(string: base))?.absoluteURL,
              let scheme = u.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return u.absoluteString
    }

    private static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    private static func matches(_ pattern: String, in s: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return re.matches(in: s, range: NSRange(s.startIndex..., in: s)).compactMap { Range($0.range, in: s).map { String(s[$0]) } }
    }

    private static func attributes(_ tag: String) -> [String: String] {
        guard let re = try? NSRegularExpression(pattern: #"([a-zA-Z:_-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))"#) else { return [:] }
        var out: [String: String] = [:]
        for m in re.matches(in: tag, range: NSRange(tag.startIndex..., in: tag)) {
            guard let k = Range(m.range(at: 1), in: tag) else { continue }
            let v = [3, 4, 5].lazy.compactMap { Range(m.range(at: $0), in: tag) }.first.map { String(tag[$0]) } ?? ""
            out[tag[k].lowercased()] = v
        }
        return out
    }

    private static func decode(_ s: String) -> String {
        var out = s
        for (k, v) in [("&amp;", "&"), ("&quot;", "\""), ("&#39;", "'"), ("&#x27;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
            out = out.replacingOccurrences(of: k, with: v)
        }
        return out
    }
}
