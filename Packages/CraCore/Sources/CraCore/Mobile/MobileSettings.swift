import Foundation

/// `settings.json` in the iPhone app's data folder. Every field has a default, so a file from an
/// older build loads and a missing file is the defaults.
public struct MobileSettings: Codable, Equatable {
    public var searchEngine: SearchEngine = .google
    public var archiveAfter: MobileArchiveAfter = .oneDay
    /// Arc Search comes up ready to type.
    public var opensKeyboardOnLaunch = true
    public var blockAds = true
    public var blockTrackers = true
    public var blockCookieBanners = true
    /// Hosts where a block is switched off, per kind.
    public var siteExceptions: [String: SiteBlocking] = [:]

    public struct SiteBlocking: Codable, Equatable {
        public var blockAds: Bool?
        public var blockTrackers: Bool?
        public var blockCookieBanners: Bool?

        public init(blockAds: Bool? = nil, blockTrackers: Bool? = nil, blockCookieBanners: Bool? = nil) {
            self.blockAds = blockAds
            self.blockTrackers = blockTrackers
            self.blockCookieBanners = blockCookieBanners
        }

        var isEmpty: Bool { blockAds == nil && blockTrackers == nil && blockCookieBanners == nil }
    }

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case searchEngine, archiveAfter, opensKeyboardOnLaunch, blockAds, blockTrackers, blockCookieBanners, siteExceptions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        searchEngine = (try? c.decodeIfPresent(SearchEngine.self, forKey: .searchEngine)) ?? .google
        archiveAfter = (try? c.decodeIfPresent(MobileArchiveAfter.self, forKey: .archiveAfter)) ?? .oneDay
        opensKeyboardOnLaunch = try c.decodeIfPresent(Bool.self, forKey: .opensKeyboardOnLaunch) ?? true
        blockAds = try c.decodeIfPresent(Bool.self, forKey: .blockAds) ?? true
        blockTrackers = try c.decodeIfPresent(Bool.self, forKey: .blockTrackers) ?? true
        blockCookieBanners = try c.decodeIfPresent(Bool.self, forKey: .blockCookieBanners) ?? true
        siteExceptions = try c.decodeIfPresent([String: SiteBlocking].self, forKey: .siteExceptions) ?? [:]
    }

    /// What is blocked on `host`: the site's own choice where it made one, the default otherwise.
    public func blocking(for host: String?) -> (ads: Bool, trackers: Bool, cookieBanners: Bool) {
        let site = host.flatMap { siteExceptions[Self.siteKey($0)] }
        return (site?.blockAds ?? blockAds, site?.blockTrackers ?? blockTrackers, site?.blockCookieBanners ?? blockCookieBanners)
    }

    /// Records a site's choice, and forgets the site once it matches the defaults again.
    public mutating func setBlocking(_ change: (inout SiteBlocking) -> Void, for host: String) {
        let key = Self.siteKey(host)
        var site = siteExceptions[key] ?? SiteBlocking()
        change(&site)
        if site.blockAds == blockAds { site.blockAds = nil }
        if site.blockTrackers == blockTrackers { site.blockTrackers = nil }
        if site.blockCookieBanners == blockCookieBanners { site.blockCookieBanners = nil }
        siteExceptions[key] = site.isEmpty ? nil : site
    }

    /// A site is its host without `www.`, lowercased.
    public static func siteKey(_ host: String) -> String {
        let lower = host.lowercased()
        return lower.hasPrefix("www.") ? String(lower.dropFirst(4)) : lower
    }
}
