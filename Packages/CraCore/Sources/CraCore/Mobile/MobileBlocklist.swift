import Foundation

/// The iPhone app's request blocking, from the same list the Mac app uses
/// (`resources/blocklist/domains.txt`: one domain per line, a listed domain covers its
/// subdomains). WebKit blocks by compiled content rules, so the list becomes rule JSON here.
public struct MobileBlocklist {
    /// What a listed domain is blocked as. Arc Search switches ads and trackers separately; the
    /// list does not say which is which, so a domain counts as a tracker when its name says so.
    public enum Kind: String, CaseIterable {
        case ads, trackers
    }

    public let domains: [String]
    private let lookup: Set<String>

    /// Reads the list's text: comments and blank lines dropped.
    public init(text: String) {
        domains = text.split(whereSeparator: \.isNewline).compactMap { line in
            let entry = line.trimmingCharacters(in: .whitespaces).lowercased()
            return entry.isEmpty || entry.hasPrefix("#") ? nil : entry
        }
        lookup = Set(domains)
    }

    private static let trackerWords = [
        "analytic", "track", "metric", "telemetry", "pixel", "beacon", "stats", "statistic", "insight", "measure",
        "collect", "segment", "tagmanager", "counter", "audience", "fingerprint", "log.", "logs.", "rum.", "events.",
    ]

    public static func kind(of domain: String) -> Kind {
        trackerWords.contains { domain.contains($0) } ? .trackers : .ads
    }

    public func domains(of kind: Kind) -> [String] {
        domains.filter { Self.kind(of: $0) == kind }
    }

    /// Whether `host` or a parent of it is listed.
    public func blocks(host: String) -> Bool {
        listedDomain(for: host) != nil
    }

    /// The listed domain that covers `host`: itself or its nearest listed parent.
    public func listedDomain(for host: String) -> String? {
        var name = Substring(host.lowercased())
        while true {
            if lookup.contains(String(name)) { return String(name) }
            guard let dot = name.firstIndex(of: ".") else { return nil }
            name = name[name.index(after: dot)...]
            if !name.contains(".") { return nil }
        }
    }

    /// Whether a request to `host` is stopped on a site with `options`: listed, and the switch
    /// for its kind is on.
    public func stops(host: String, with options: MobileSiteOptions) -> Bool {
        guard let listed = listedDomain(for: host) else { return false }
        return Self.kind(of: listed) == .trackers ? options.blockTrackers : options.blockAds
    }

    /// WebKit content rules that block third-party requests to `domains` and their subdomains.
    public static func rulesJSON(blocking domains: [String]) -> String {
        let rules = domains.map { domain -> String in
            let escaped = domain.replacingOccurrences(of: ".", with: "\\\\.").replacingOccurrences(of: "\"", with: "")
            return "{\"trigger\":{\"url-filter\":\"^[^:]+://+([^:/]+\\\\.)?\(escaped)[:/]\",\"load-type\":[\"third-party\"]},\"action\":{\"type\":\"block\"}}"
        }
        return "[" + rules.joined(separator: ",") + "]"
    }

    /// A content rule that hides the cookie banners' containers on every page.
    public static func cookieBannerRulesJSON(selectors: [String] = CookieBanners.selectors) -> String {
        let selector = selectors.joined(separator: ", ").replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "[{\"trigger\":{\"url-filter\":\".*\"},\"action\":{\"type\":\"css-display-none\",\"selector\":\"\(selector)\"}}]"
    }

    /// The rule lists a page on a site with `options` gets, by name.
    public static func ruleLists(for options: MobileSiteOptions) -> [String] {
        var names: [String] = []
        if options.blockAds { names.append(Kind.ads.rawValue) }
        if options.blockTrackers { names.append(Kind.trackers.rawValue) }
        if options.blockCookieBanners { names.append("cookie-banners") }
        return names
    }
}
