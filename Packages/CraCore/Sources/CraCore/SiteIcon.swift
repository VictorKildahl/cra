import Foundation

/// A site's icon for places that show a site Cra may never have opened (a boost on Library ▸
/// Boosts, a tab that never loaded, SiteIconQueue): read from its home page's `<link rel=icon>`
/// tags as a page's icon is (the largest it declares, bitmaps before SVG), then /favicon.ico.
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

    /// Whether the icon loader may request `url`, a candidate or a redirect, for the site at `origin`: an
    /// http(s) address, and one on the Mac or its local network only for a site that is local itself
    /// (a dev server's page may use its own), so a public page can't make Cra send requests into the LAN.
    public static func mayFetch(_ url: URL, for origin: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), let host = url.host, !host.isEmpty else { return false }
        return !isLocal(host: host) || isLocal(host: origin.host ?? "")
    }

    /// The formats favicons come in, by ImageIO type identifier. Only these reach ImageIO's parsers from a
    /// site, not camera RAW, PSD or the dozens of others it reads.
    public static let imageTypes: Set<String> = [
        "public.png", "public.jpeg", "com.compuserve.gif", "com.microsoft.ico", "org.webmproject.webp", "com.microsoft.bmp",
    ]

    /// Whether a site's bytes may be read as an icon: in one of `imageTypes`, as ImageIO typed them, or
    /// SVG text, which ImageIO doesn't type.
    public static func isIcon(imageType: String?, data: Data) -> Bool {
        imageType.map(imageTypes.contains) ?? isSVG(data)
    }

    /// Whether a site's bytes are an SVG: after a BOM and whitespace, an `<svg` element, or an XML prolog with
    /// one in the first 4 KB. The loader reads only these and bitmaps, not a PDF that AppKit would also draw.
    public static func isSVG(_ data: Data) -> Bool {
        var head = Substring(String(decoding: data.prefix(4096), as: UTF8.self))
        if head.first == "\u{FEFF}" { head = head.dropFirst() }
        head = head.drop { $0.isWhitespace }
        func element(at i: Substring.Index) -> Bool {
            let rest = head[i...].dropFirst(4)
            return head[i...].hasPrefix("<svg") && (rest.first.map { $0.isWhitespace || $0 == ">" || $0 == "/" } ?? false)
        }
        if let first = head.indices.first, element(at: first) { return true }
        guard head.hasPrefix("<?xml") else { return false }
        var from = head.startIndex
        while let r = head.range(of: "<svg", range: from..<head.endIndex) {
            if element(at: r.lowerBound) { return true }
            from = r.upperBound
        }
        return false
    }

    /// Whether a request for the site at `origin` may go to a server at `addresses`, the numeric
    /// addresses its name resolved to: by name a host may look public (mayFetch) and still point into the
    /// Mac or its network, an intranet name or one a page aims at a router. Only a local site's may.
    public static func mayConnect(to addresses: [String], for origin: URL) -> Bool {
        isLocal(host: origin.host ?? "") || !addresses.contains { isLocal(host: $0) }
    }

    /// Whether `host` names the Mac itself or a machine on its network: localhost, an unqualified or
    /// `.local` name, and loopback, private, shared (100.64/10), link-local and unique-local addresses.
    public static func isLocal(host: String) -> Bool {
        var name = host.lowercased()
        if name.hasPrefix("["), name.hasSuffix("]") { name = String(name.dropFirst().dropLast()) }
        while name.hasSuffix(".") { name.removeLast() }
        if name.contains(":") {
            // A resolved link-local address names its interface: fe80::1%en0.
            if let zone = name.firstIndex(of: "%") { name = String(name[..<zone]) }
            var v6 = in6_addr()
            guard inet_pton(AF_INET6, name, &v6) == 1 else { return false }
            let b = withUnsafeBytes(of: v6) { Array($0) }
            if b[0..<10].allSatisfy({ $0 == 0 }), b[10] == 0xff, b[11] == 0xff { return isLocal(v4: b[12...].reduce(0) { $0 << 8 | UInt32($1) }) }
            return b[0..<15].allSatisfy { $0 == 0 } && b[15] <= 1  // :: and ::1
                || b[0] & 0xfe == 0xfc  // fc00::/7
                || (b[0] == 0xfe && b[1] & 0xc0 == 0x80)  // fe80::/10
        }
        var v4 = in_addr()
        // inet_aton also reads the short and numeric forms URLSession connects to (127.1, 2130706433).
        if inet_aton(name, &v4) != 0 { return isLocal(v4: UInt32(bigEndian: v4.s_addr)) }
        return name == "localhost" || name.hasSuffix(".localhost") || name.hasSuffix(".local") || !name.contains(".")
    }

    private static func isLocal(v4 a: UInt32) -> Bool {
        let ranges: [(UInt32, UInt32)] = [
            (0x0000_0000, 8), (0x0A00_0000, 8), (0x7F00_0000, 8), (0xA9FE_0000, 16),
            (0xAC10_0000, 12), (0xC0A8_0000, 16), (0x6440_0000, 10),
        ]
        return ranges.contains { net, bits in a >> (32 - bits) == net >> (32 - bits) }
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
