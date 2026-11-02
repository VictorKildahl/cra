import Foundation

/// Settings ▸ Performance ▸ "Hide site names": every site Cra saw this session becomes `site-1`,
/// `site-2`… in every file of Help ▸ Export Diagnostics (GitHub #91). The same site gets the
/// same name in every file of one export, so a report can still say "site-3 crashed twice".
/// Not a hash: the list of domains is public, and a hash of one is found by looking it up.
public struct SiteNames {
    private var known: Set<String> = []
    private var aliases: [String: String] = [:]

    /// `hosts` are the sites to hide (from tabs, history and Cra's log). Hosts inside a web
    /// address in the text are hidden as well, known or not.
    public init(hosts: some Sequence<String>) {
        for h in hosts { if let k = Self.key(h) { known.insert(k) } }
    }

    /// A site's name in this export: the same for `www.example.com`, `example.com` and `EXAMPLE.COM`.
    public mutating func alias(_ host: String) -> String {
        guard let k = Self.key(host) else { return host }
        if let a = aliases[k] { return a }
        let a = "site-\(aliases.count + 1)"
        aliases[k] = a
        return a
    }

    /// The text with every known host, and the host of every web address, replaced. A host is a
    /// whole run of letters, digits, dots and dashes: `example.com` inside `api.example.com` is
    /// another site and stays unless it was seen too.
    public mutating func apply(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            guard Self.isHostByte(bytes[i]) else { out.append(bytes[i]); i += 1; continue }
            var end = i
            while end < bytes.count, Self.isHostByte(bytes[end]) { end += 1 }
            // Dots and dashes at either end belong to the sentence ("example.com." or "--flag").
            var lo = i, hi = end
            while lo < hi, bytes[lo] == UInt8(ascii: ".") || bytes[lo] == UInt8(ascii: "-") { lo += 1 }
            while hi > lo, bytes[hi - 1] == UInt8(ascii: ".") || bytes[hi - 1] == UInt8(ascii: "-") { hi -= 1 }
            out += bytes[i..<lo]
            if lo < hi {
                let token = String(decoding: bytes[lo..<hi], as: UTF8.self)
                if Self.followsWebScheme(bytes, at: lo) || known.contains(Self.key(token) ?? "") {
                    out += Array(alias(token).utf8)
                } else {
                    out += bytes[lo..<hi]
                }
            }
            out += bytes[hi..<end]
            i = end
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func isHostByte(_ b: UInt8) -> Bool {
        (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A) || b == 0x2E || b == 0x2D
    }

    /// `http://`, `https://`, `ws://`, `wss://` or `ftp://` right before `index`.
    private static func followsWebScheme(_ bytes: [UInt8], at index: Int) -> Bool {
        guard index >= 3, bytes[index - 3] == UInt8(ascii: ":"), bytes[index - 2] == UInt8(ascii: "/"),
              bytes[index - 1] == UInt8(ascii: "/") else { return false }
        var start = index - 3
        while start > 0, (bytes[start - 1] | 0x20) >= 0x61, (bytes[start - 1] | 0x20) <= 0x7A { start -= 1 }
        let scheme = String(decoding: bytes[start..<(index - 3)], as: UTF8.self).lowercased()
        return ["http", "https", "ws", "wss", "ftp"].contains(scheme)
    }

    /// The comparison key: lower case, without a leading `www.` or a trailing dot. Nil for what
    /// can't be a host Cra logged (empty, or Cra's own placeholders like "(no page)").
    public static func key(_ host: String) -> String? {
        var h = host.lowercased()
        while h.hasSuffix(".") { h.removeLast() }
        if h.hasPrefix("www.") { h.removeFirst(4) }
        guard !h.isEmpty, h.utf8.allSatisfy(isHostByte) else { return nil }
        return h
    }

    /// Hosts that name a site: http(s), ws(s) and ftp addresses. Cra's own pages, Chrome's,
    /// extensions and files are not sites.
    public static func siteHost(of url: String) -> String? {
        guard let u = URL(string: url), let scheme = u.scheme?.lowercased(),
              ["http", "https", "ws", "wss", "ftp"].contains(scheme), let host = u.host, !host.isEmpty else { return nil }
        return host
    }
}
