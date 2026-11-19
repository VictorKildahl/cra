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

    /// Domains of the lists added in Default Site Settings ▸ Block Lists (#507), in rule lists
    /// WebKit compiles: it stops at 150,000 rules a list, and big lists such as oisd go past that.
    /// Lists with more than domains add rule lists of their own (#570, `customRuleLists`).
    public static let customChunkSize = 50_000

    public static func customChunks(_ domains: [String]) -> [[String]] {
        stride(from: 0, to: domains.count, by: customChunkSize).map { Array(domains[$0..<min($0 + customChunkSize, domains.count)]) }
    }

    public static func customRuleListName(_ index: Int) -> String { "custom-\(index)" }

    /// One of the rule lists made from the added lists: some of their merged domains, or some of one
    /// list's full rules (#570) followed by all of that list's exceptions.
    public enum CustomRuleList: Equatable {
        case domains([String])
        case filters(rules: ArraySlice<FilterList.Rule>, exceptions: ArraySlice<FilterList.Rule>)

        public var ruleCount: Int {
            switch self {
            case .domains(let domains): return domains.count
            case .filters(let rules, let exceptions): return rules.count + exceptions.count
            }
        }

        public func json() -> String {
            switch self {
            case .domains(let domains): return MobileBlocklist.rulesJSON(blocking: domains)
            case .filters(let rules, let exceptions): return FilterList.json(rules + exceptions)
            }
        }
    }

    /// Every rule list the added lists make, in the order they're named custom-0, custom-1, …: the
    /// merged domains in lists of 50,000, then each list with full rules in lists of 50,000 rules
    /// plus its exceptions (at most `BlocklistRules.maxExceptions`), so none passes WebKit's 150,000.
    public static func customRuleLists(domains: [String], filters: [FilterList], chunkSize: Int = customChunkSize) -> [CustomRuleList] {
        var lists = customChunks(domains).map(CustomRuleList.domains)
        for list in filters {
            let rules = list.blocking + list.hiding
            let exceptions = list.exceptions.prefix(BlocklistRules.maxExceptions)
            for start in stride(from: 0, to: rules.count, by: chunkSize) {
                lists.append(.filters(rules: rules[start..<min(start + chunkSize, rules.count)], exceptions: exceptions))
            }
        }
        return lists
    }

    /// The name WebKit keeps the `index`-th of a list's `count` rule lists under (#570). The count is
    /// in the name, so a launch can tell from the names alone that all of them were compiled, and
    /// look them up without reading the list.
    public static func ruleListIdentifier(key: String, index: Int, count: Int) -> String {
        "cra-custom-rules-\(key)-\(index)of\(count)"
    }

    /// A list's compiled rule lists among `available`, in order; nil unless every one is there.
    public static func compiledRuleLists(key: String, in available: [String]) -> [String]? {
        let prefix = "cra-custom-rules-\(key)-"
        var found: [Int: String] = [:]
        var count: Int?
        for name in available where name.hasPrefix(prefix) {
            let parts = name.dropFirst(prefix.count).split(separator: "o")
            guard parts.count == 2, parts[1].hasPrefix("f"), let index = Int(parts[0]), let total = Int(parts[1].dropFirst()),
                  total > 0, index < total, count == nil || count == total
            else { return nil }
            count = total
            found[index] = name
        }
        guard let count, found.count == count else { return nil }
        return (0..<count).compactMap { found[$0] }
    }

    /// The rule lists a page on a site with `options` gets, by name. The added lists count as ads.
    public static func ruleLists(for options: MobileSiteOptions, customLists: Int = 0) -> [String] {
        var names: [String] = []
        if options.blockAds { names.append(Kind.ads.rawValue) }
        if options.blockAds { names += (0..<customLists).map(customRuleListName) }
        if options.blockTrackers { names.append(Kind.trackers.rawValue) }
        if options.blockCookieBanners { names.append("cookie-banners") }
        return names
    }
}

extension MobileBlocklist {
    /// WebKit stops compiling a rule list at 150,000 rules.
    public static let maxRulesPerList = 150_000

    /// The Block Ads rule list: Cra's ad domains, then its filters (#570), whose exceptions come last
    /// and so apply to the domains too.
    public static func adsRulesJSON(domains: [String], filters: FilterList) -> String {
        let domainRules = rulesJSON(blocking: domains)
        let filterRules = filters.contentRulesJSON()
        if filterRules.isEmpty { return domainRules }
        if domains.isEmpty { return "[" + filterRules + "]" }
        return String(domainRules.dropLast()) + "," + filterRules + "]"
    }

    /// Whether a request for `url` on a page of `pageHost` is stopped: its host is listed and the
    /// switch for its kind is on, or Block Ads is on and a filter stops it.
    public func stops(url: String, onPage pageHost: String?, with options: MobileSiteOptions, filters: FilterList) -> Bool {
        guard let host = URL(string: url)?.host else { return false }
        return stops(host: host, with: options) || (options.blockAds && filters.blocks(url: url, onPage: pageHost))
    }
}
