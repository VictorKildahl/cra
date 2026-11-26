import Foundation

/// What the clearing commands clear for the page in front, as DevTools protocol calls, and how the page
/// reloads after. Arc's "Clear Cookies and Refresh" clears this site's cookies and "Clear Cache and Refresh"
/// the HTTP cache; Cra's "Clear Site Data and Refresh" (#853) clears everything the page's origin keeps in
/// the browser (cookies, local and session storage, IndexedDB, service workers, Cache Storage, file systems)
/// and reloads past the HTTP cache, so a broken site starts clean without touching any other site.
public enum SiteDataClearing {
    public enum Kind: String, Sendable, CaseIterable {
        case cookies, cache, siteData
    }

    public enum Reload: Sendable, Equatable {
        case normal
        /// Every resource fetched again, as ⇧⌘R does.
        case ignoringCache
    }

    public struct Call: Sendable, Equatable {
        public let method: String
        public let params: [String: String]

        public init(method: String, params: [String: String]) {
            self.method = method
            self.params = params
        }
    }

    public struct Plan: Sendable, Equatable {
        public let call: Call
        public let reload: Reload

        public init(call: Call, reload: Reload) {
            self.call = call
            self.reload = reload
        }
    }

    /// Chromium's `Storage.clearDataForOrigin` storage types for everything an origin keeps.
    public static let everything = "all"

    /// The page's origin ("https://example.com", with a port when it has one), nil when the address has
    /// none: an empty tab or about:blank has no site to clear.
    public static func origin(of address: String) -> String? {
        guard let u = URL(string: address), let scheme = u.scheme?.lowercased(), let host = u.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        return "\(scheme)://\(host)\(u.port.map { ":\($0)" } ?? "")"
    }

    /// What `kind` does for the page at `address`; nil when there's nothing to clear.
    public static func plan(_ kind: Kind, address: String) -> Plan? {
        guard let origin = origin(of: address) else { return nil }
        switch kind {
        case .cookies:
            return Plan(call: Call(method: "Storage.clearDataForOrigin", params: ["origin": origin, "storageTypes": "cookies"]), reload: .normal)
        case .cache:
            return Plan(call: Call(method: "Network.clearBrowserCache", params: [:]), reload: .normal)
        case .siteData:
            // The origin's own data only; the HTTP cache has no per-site clear in the protocol, so the reload
            // fetches the page and everything it loads again instead.
            return Plan(call: Call(method: "Storage.clearDataForOrigin", params: ["origin": origin, "storageTypes": everything]),
                        reload: .ignoringCache)
        }
    }
}
