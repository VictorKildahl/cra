import Foundation

/// Subscription addresses are also their identities in the existing settings and disk cache.
public struct DesktopFilterList: Identifiable {
    public var id: String { address }
    public let name: String
    public let detail: String
    public let address: String
    public let regional: Bool

    private init(_ name: String, _ detail: String, _ address: String, regional: Bool = false) {
        self.name = name
        self.detail = detail
        self.address = address
        self.regional = regional
    }

    static let proAddress = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro-onlydomains.txt"
    static let proMiniAddress = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro.mini-onlydomains.txt"

    /// An older settings file can contain both addresses as custom subscriptions.
    /// Keep the most recently added variant when restoring or importing that file.
    static func resolveProVariants(_ addresses: [String]) -> [String] {
        guard let full = addresses.lastIndex(of: proAddress),
              let mini = addresses.lastIndex(of: proMiniAddress) else { return addresses }
        let superseded = full > mini ? proMiniAddress : proAddress
        return addresses.filter { $0 != superseded }
    }

    public static let catalog = [
        Self("EasyList", "Ads on international sites", "https://easylist.to/easylist/easylist.txt"),
        Self("EasyPrivacy", "Tracking and analytics", "https://easylist.to/easylist/easyprivacy.txt"),
        Self("EasyList Cookie List", "Cookie notices", "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt"),
        Self("Fanboy’s Annoyance List", "Overlays, social widgets and cookie notices", "https://easylist-downloads.adblockplus.org/fanboy-annoyance.txt"),
        Self("Fanboy’s Social Blocking List", "Social sharing buttons and widgets", "https://easylist-downloads.adblockplus.org/fanboy-social.txt"),
        Self("AdGuard Popups", "Promotional popups and overlays", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_19_Annoyances_Popups/filter.txt"),
        Self("AdGuard Widgets", "Third-party widgets, including support chats", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_22_Annoyances_Widgets/filter.txt"),
        Self("Adblock Warning Removal List", "Anti-adblock notices", "https://easylist-downloads.adblockplus.org/antiadblockfilters.txt"),
        Self("StevenBlack Unified Hosts", "Advertising and tracking domains, also offered by Pi-hole", "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"),
        Self("HaGeZi Multi NORMAL", "Start here for everyday browsing. Blocks ads and trackers while allowing crash reports, with a low risk of breaking sites.", "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/multi-onlydomains.txt"),
        Self("HaGeZi Multi PRO Mini", "A smaller download for everyday sites, including common crash trackers. Selecting Mini switches off full PRO.", proMiniAddress),
        Self("HaGeZi Multi PRO", "Covers less common trackers as well. Choose it for maximum coverage if you can make site exceptions. Switches off PRO Mini.", proAddress),
        Self("Liste AR", "Arabic-language sites", "https://easylist-downloads.adblockplus.org/Liste_AR.txt", regional: true),
        Self("Bulgarian List", "Bulgarian-language sites", "https://stanev.org/abp/adblock_bg.txt", regional: true),
        Self("EasyList China", "Chinese-language sites", "https://easylist-downloads.adblockplus.org/easylistchina.txt", regional: true),
        Self("AdGuard Chinese", "Chinese-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_224_Chinese/filter.txt", regional: true),
        Self("EasyList Czech and Slovak", "Czech and Slovak-language sites", "https://raw.githubusercontent.com/tomasko126/easylistczechandslovak/master/filters.txt", regional: true),
        Self("EasyList Dutch", "Dutch-language sites", "https://easylist-downloads.adblockplus.org/easylistdutch.txt", regional: true),
        Self("AdGuard Dutch", "Dutch-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_8_Dutch/filter.txt", regional: true),
        Self("Liste FR", "French-language sites", "https://easylist-downloads.adblockplus.org/liste_fr.txt", regional: true),
        Self("AdGuard French", "French-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_16_French/filter.txt", regional: true),
        Self("EasyList Germany", "German-language sites", "https://easylist.to/easylistgermany/easylistgermany.txt", regional: true),
        Self("AdGuard German", "German-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_6_German/filter.txt", regional: true),
        Self("void.gr", "Greek-language sites", "https://www.void.gr/kargig/void-gr-filters.txt", regional: true),
        Self("hufilter", "Hungarian-language sites", "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter.txt", regional: true),
        Self("IndianList", "Sites in Indian languages", "https://easylist-downloads.adblockplus.org/indianlist.txt", regional: true),
        Self("ABPindo", "Indonesian and Malay-language sites", "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt", regional: true),
        Self("EasyList Italy", "Italian-language sites", "https://easylist-downloads.adblockplus.org/easylistitaly.txt", regional: true),
        Self("AdGuard Italian", "Italian-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_26_Italian/filter.txt", regional: true),
        Self("Japanese Filters", "Japanese-language sites", "https://easylist-downloads.adblockplus.org/japanese-filters.txt", regional: true),
        Self("AdGuard Japanese", "Japanese-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_7_Japanese/filter.txt", regional: true),
        Self("YousList", "Korean-language sites", "https://raw.githubusercontent.com/yous/YousList/master/youslist.txt", regional: true),
        Self("EasyList Lithuania", "Lithuanian-language sites", "https://raw.githubusercontent.com/EasyList-Lithuania/easylist_lithuania/master/easylistlithuania.txt", regional: true),
        Self("Dandelion Sprout’s Nordic Filters", "Sites in Norway, Denmark, Iceland, Sweden and Finland", "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianExperimentalList%20alternate%20versions/NordicFiltersABP-Inclusion.txt", regional: true),
        Self("AdBlockFarsi", "Persian-language sites", "https://raw.githubusercontent.com/SlashArash/adblockfa/master/adblockfa.txt", regional: true),
        Self("EasyList Polish", "Polish-language sites", "https://easylist-downloads.adblockplus.org/easylistpolish.txt", regional: true),
        Self("AdGuard Polish", "Polish-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_27_Polish/filter.txt", regional: true),
        Self("EasyList Portuguese", "Portuguese-language sites", "https://easylist-downloads.adblockplus.org/easylistportuguese.txt", regional: true),
        Self("AdGuard Russian", "Russian-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_1_Russian/filter.txt", regional: true),
        Self("EasyList Spanish", "Spanish-language sites", "https://easylist-downloads.adblockplus.org/easylistspanish.txt", regional: true),
        Self("AdGuard Spanish/Portuguese", "Spanish and Portuguese-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_9_Spanish/filter.txt", regional: true),
        Self("Turkish Filters", "Turkish-language sites", "https://easylist-downloads.adblockplus.org/turkish-filters.txt", regional: true),
        Self("AdGuard Turkish", "Turkish-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_13_Turkish/filter.txt", regional: true),
        Self("AdGuard Ukrainian", "Ukrainian-language sites", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_23_Ukrainian/filter.txt", regional: true),
        Self("ABPVN", "Vietnamese-language sites", "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn.txt", regional: true),
    ]
}

public extension AppSettings {
    var customFilterAddresses: [String] {
        let presets = Set(DesktopFilterList.catalog.map(\.address))
        return Set(customBlocklists + disabledCustomBlocklists).subtracting(presets).sorted()
    }

    mutating func setFilterList(_ address: String, enabled: Bool) {
        disabledCustomBlocklists.removeAll { $0 == address }
        if enabled {
            if !customBlocklists.contains(address) {
                customBlocklists = DesktopFilterList.resolveProVariants(customBlocklists + [address])
            }
        } else {
            customBlocklists.removeAll { $0 == address }
            if !DesktopFilterList.catalog.contains(where: { $0.address == address }) {
                disabledCustomBlocklists.append(address)
            }
        }
    }

    mutating func forgetFilterList(_ address: String) {
        customBlocklists.removeAll { $0 == address }
        disabledCustomBlocklists.removeAll { $0 == address }
    }
}

/// The Mac can apply declarative element hiding to the top document alongside its domain blocker.
/// Only simple selectors are interpolated into stylesheets. Lists cannot supply CSS declarations.
public struct DesktopHidingRules {
    private struct Rule {
        var selector: String
        var excluded: Set<String>
        var exception: Bool
    }

    // A type, class or id selector and optional attributes, e.g. div.ad or [id^="ad_"].
    private static let selector = try! NSRegularExpression(pattern:
        #"^(?:[a-zA-Z][a-zA-Z0-9-]*)?(?:(?:[.#][a-zA-Z_][a-zA-Z0-9_-]*)|(?:\[[a-zA-Z][a-zA-Z0-9_-]*(?:[~|^$*]?=(?:"[a-zA-Z0-9_ .:/?=&%-]*"|'[a-zA-Z0-9_ .:/?=&%-]*'|[a-zA-Z0-9_-]+))?\]))+$"#)
    private var byHost: [String: [Rule]] = [:]

    private static func parse(_ line: String) -> (hosts: [String], rule: Rule)? {
        guard line.utf8.count <= 2048, let parts = FilterList.cosmetic(line),
              parts.marker == "##" || parts.marker == "#@#",
              parts.domains.isEmpty || !parts.domains.allSatisfy({ $0 == "," }),
              let scopes = FilterList.domains(parts.domains, separator: ","),
              selector.firstMatch(in: parts.selector, range: NSRange(parts.selector.startIndex..., in: parts.selector)) != nil
        else { return nil }
        return (scopes.only.isEmpty ? [""] : scopes.only,
                Rule(selector: parts.selector, excluded: Set(scopes.unless), exception: parts.marker == "#@#"))
    }

    public init(lines: [String]) {
        for line in lines {
            guard let entry = Self.parse(line) else { continue }
            for host in entry.hosts { byHost[host, default: []].append(entry.rule) }
        }
    }

    private static func suffixes(of host: String) -> [String] {
        var suffix = host[...]
        var keys: [String] = []
        while !suffix.isEmpty {
            keys.append(String(suffix))
            guard let dot = suffix.firstIndex(of: ".") else { break }
            suffix = suffix[suffix.index(after: dot)...]
        }
        return keys
    }

    public func css(host: String) -> String {
        guard !byHost.isEmpty, !host.isEmpty else { return "" }
        let keys = [""] + Self.suffixes(of: host.lowercased())
        let scopes = Set(keys)
        var hidden = Set<String>()
        var exceptions = Set<String>()
        for key in keys {
            for rule in byHost[key] ?? [] where scopes.isDisjoint(with: rule.excluded) {
                if rule.exception { exceptions.insert(rule.selector) } else { hidden.insert(rule.selector) }
            }
        }
        hidden.subtract(exceptions)
        return hidden.sorted().map { $0 + "{display:none!important}" }.joined(separator: "\n")
    }

    public static func read(_ text: String, address: String, fetched: Date) -> CachedBlocklist {
        var networkLines: [Substring] = []
        var requestRules: [String] = []
        var plainDomains = Set<String>()
        var lines: [String] = []
        var allowed = Set<String>()
        var ancestorsOfAllowed = Set<String>()
        var conditionalDepth = 0
        var skipped = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("!#if ") { conditionalDepth += 1; continue }
            if line == "!#endif" { conditionalDepth = max(0, conditionalDepth - 1); continue }
            if conditionalDepth > 0 {
                if !line.hasPrefix("!") { skipped += 1 }
                continue
            }
            if line.contains("#"), parse(line) != nil {
                lines.append(line)
                continue
            }
            switch ParsedBlocklist.classify(line) {
            case .ignored, .comment:
                networkLines.append(raw)
            case .domains(let names, adblock: false):
                plainDomains.formUnion(names)
                networkLines.append(raw)
            default:
                if DesktopNetworkRules.parse(line) != nil || DesktopNetworkRules.disabledRule(line) != nil {
                    requestRules.append(line)
                } else {
                    skipped += 1
                }
                // Keep a conservative domain-only fallback for older engines and cold starts.
                if line.hasPrefix("@@||") {
                    let host = line.dropFirst(4).prefix { !"^/$|?*".contains($0) }
                    if let domain = ParsedBlocklist.domain(host) {
                        allowed.insert(domain)
                        ancestorsOfAllowed.formUnion(Self.suffixes(of: domain))
                    }
                } else if case .domains(_, adblock: true) = ParsedBlocklist.classify(line) {
                    let options = line.split(separator: "$", maxSplits: 1).dropFirst().first
                    if options == nil || options == "third-party" || options == "3p" { networkLines.append(raw) }
                }
            }
        }
        var parsed = ParsedBlocklist(text: networkLines.joined(separator: "\n"))
        if !allowed.isEmpty {
            parsed.domains.removeAll { host in
                ancestorsOfAllowed.contains(host) || !allowed.isDisjoint(with: Self.suffixes(of: host))
            }
        }
        parsed.skippedRules = skipped
        var cache = CachedBlocklist(url: address, list: parsed, fetched: fetched)
        if plainDomains != Set(parsed.domains) { cache.sourceHosts = plainDomains.sorted() }
        cache.hasNetworkSource = true
        cache.networkRules = requestRules
        cache.hidingRules = lines
        return cache
    }
}
