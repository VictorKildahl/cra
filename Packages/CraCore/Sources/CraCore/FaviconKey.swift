import Foundation

/// What favicons are cached under. A site's key is the page's host, lowercased: the icon a
/// suggestion or a not-yet-loaded tab borrows from the last page seen there. Above it, a section's
/// key adds the port and the first path segment ("docs.google.com/spreadsheets", "192.168.8.2:8006"),
/// as one host serves many apps (#909). A tab's own icon goes under a key combining its section and
/// tab ID, so tabs on one host keep their own icons even when they share an icon URL (GitHub #211;
/// Arc caches one favicon per sidebar item, SidebarItemsFaviconCache). A key falls back down its
/// `chain` to the host.
public enum FaviconKey {
    public static func key(for urlString: String) -> String? {
        guard let host = URL(string: urlString)?.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    public static func key(site: String, tabID: UUID) -> String {
        site + "#tab-" + tabID.uuidString.lowercased()
    }

    /// The key of the icon at `iconURL` on the page at `pageURL`: "<host>#<hash of the icon URL>".
    /// AWS consoles and localhost apps have one host and many icons.
    public static func key(for pageURL: String, iconURL: String) -> String? {
        key(for: pageURL).map { key(site: $0, iconURL: iconURL) }
    }

    /// The same for a site key already known (a tab's).
    public static func key(site: String, iconURL: String) -> String {
        guard !iconURL.isEmpty else { return site }
        // FNV-1a: stable across launches (the key names a file on disk), unlike Hasher.
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in iconURL.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return site + "#" + String(hash, radix: 16)
    }

    /// The site key an icon key falls back to.
    public static func siteKey(of key: String) -> String {
        key.firstIndex(of: "#").map { String(key[..<$0]) } ?? key
    }

    /// A tab's key after it goes to `url`. On the same host it keeps its own icon until the new
    /// page's arrives (Chromium sends none when the icon is the same); elsewhere it shows the
    /// last icon of the page's section meanwhile, not the host's, which any app on it overwrites (#909).
    public static func key(after current: String?, goingTo url: String) -> String? {
        guard let site = key(for: url) else { return current }
        if let current, hostKey(of: current) == site { return current }
        return sectionKey(for: url)
    }

    /// The key of the part of a site the page at `urlString` is in: its host, its port unless the
    /// scheme's own, and its first path segment. "https://docs.google.com/spreadsheets/d/1" is
    /// "docs.google.com/spreadsheets", "https://192.168.8.2:8006/" is "192.168.8.2:8006".
    public static func sectionKey(for urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = key(for: urlString) else { return nil }
        var section = host.contains(":") && !host.hasPrefix("[") ? "[" + host + "]" : host
        if let port = url.port, port != defaultPort[url.scheme?.lowercased() ?? ""] { section += ":\(port)" }
        // "#" and "/" separate a key's parts; a segment can carry them percent-encoded.
        let segment = String((url.pathComponents.dropFirst().first ?? "").prefix(64))
            .map { $0 == "#" || $0 == "/" ? "_" : String($0) }.joined()
        return segment.isEmpty ? section : section + "/" + segment
    }

    private static let defaultPort = ["http": 80, "https": 443]

    /// What `key` falls back to when nothing is stored under it, the key itself first, the host
    /// last: a tab's key, then its section ("host:port/segment"), then "host:port", then the host.
    public static func chain(of key: String) -> [String] {
        var keys = [key]
        while let next = fallback(of: keys[keys.count - 1]) { keys.append(next) }
        return keys
    }

    /// The keys that are a row's own icon: `key`'s chain short of the bare host, which every page
    /// on the host overwrites (#909). A host's key alone is its own.
    public static func ownKeys(of key: String) -> [String] {
        let keys = chain(of: key)
        return keys.count == 1 ? keys : Array(keys.dropLast())
    }

    /// The host at the end of `key`'s chain ("localhost" for "localhost:3000/settings#tab-…").
    public static func hostKey(of key: String) -> String { chain(of: key).last ?? key }

    private static func fallback(of key: String) -> String? {
        if let i = key.firstIndex(of: "#") { return String(key[..<i]) }
        if let i = key.firstIndex(of: "/") { return String(key[..<i]) }
        if key.hasPrefix("["), let close = key.lastIndex(of: "]") {
            // "[::1]:8080" → "[::1]" → "::1", the host as `key(for:)` gives it.
            let rest = key[key.index(after: close)...]
            return rest.isEmpty ? String(key[key.index(after: key.startIndex)..<close]) : String(key[...close])
        }
        guard let i = key.lastIndex(of: ":"), i != key.startIndex, !key[..<i].contains(":") else { return nil }
        let port = key[key.index(after: i)...]
        return !port.isEmpty && port.allSatisfy(\.isNumber) ? String(key[..<i]) : nil
    }
}
