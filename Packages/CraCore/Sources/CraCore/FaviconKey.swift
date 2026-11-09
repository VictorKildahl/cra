import Foundation

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
    /// site's last icon meanwhile.
    public static func key(after current: String?, goingTo url: String) -> String? {
        guard let site = key(for: url) else { return current }
        if let current, siteKey(of: current) == site { return current }
        return site
    }
}
