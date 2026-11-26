import Foundation

/// Subscription addresses are also their identities in the existing settings and disk cache.
public struct DesktopFilterList: Identifiable {
    public var id: String { address }
    public let name: String
    public let detail: String
    public let address: String
    public enum Category: String {
        case ads, tracking, annoyances, mixed, regional
    }

    public let category: Category
    public var regional: Bool { category == .regional }

    private init(_ name: String, _ detail: String, _ address: String, category: Category) {
        self.name = name
        self.detail = detail
        self.address = address
        self.category = category
    }

    static let proAddress = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro-onlydomains.txt"
    static let proMiniAddress = "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro.mini-onlydomains.txt"

    public static let warningListAddress = "https://easylist-downloads.adblockplus.org/antiadblockfilters.txt"

    public static let catalog = [
        Self("EasyList", "Ads on international sites", "https://easylist.to/easylist/easylist.txt", category: .ads),
        Self("EasyPrivacy", "Tracking and analytics", "https://easylist.to/easylist/easyprivacy.txt", category: .tracking),
        Self("EasyList Cookie List", "Cookie notices", "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt", category: .annoyances),
        Self("Fanboy’s Annoyance List", "Overlays, social widgets and cookie notices", "https://easylist-downloads.adblockplus.org/fanboy-annoyance.txt", category: .annoyances),
        Self("Fanboy’s Social Blocking List", "Social sharing buttons and widgets", "https://easylist-downloads.adblockplus.org/fanboy-social.txt", category: .annoyances),
        Self("AdGuard Popups", "Promotional popups and overlays", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_19_Annoyances_Popups/filter.txt", category: .annoyances),
        Self("AdGuard Widgets", "Third-party widgets, including support chats", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_22_Annoyances_Widgets/filter.txt", category: .annoyances),
        Self("Adblock Warning Removal List", "Anti-adblock notices", warningListAddress, category: .ads),
        Self("StevenBlack Unified Hosts", "Advertising and tracking domains", "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts", category: .ads),
        Self("HaGeZi Multi NORMAL", "For everyday browsing. Blocks ad, tracker, phishing and malware domains while allowing crash reports.", "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/multi-onlydomains.txt", category: .mixed),
        Self("HaGeZi Multi PRO Mini", "A smaller download for everyday sites, including common crash trackers. Its domains are included in full PRO.", proMiniAddress, category: .mixed),
        Self("HaGeZi Multi PRO", "Covers less common trackers as well. Choose it for maximum coverage if you can make site exceptions.", proAddress, category: .mixed),
        Self("Arabic", "Liste AR", "https://easylist-downloads.adblockplus.org/Liste_AR.txt", category: .regional),
        Self("Bulgarian", "Bulgarian List", "https://stanev.org/abp/adblock_bg.txt", category: .regional),
        Self("Chinese", "EasyList China", "https://easylist-downloads.adblockplus.org/easylistchina.txt", category: .regional),
        Self("Chinese", "AdGuard Chinese", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_224_Chinese/filter.txt", category: .regional),
        Self("Czech and Slovak", "EasyList Czech and Slovak", "https://raw.githubusercontent.com/tomasko126/easylistczechandslovak/master/filters.txt", category: .regional),
        Self("Dutch", "EasyList Dutch", "https://easylist-downloads.adblockplus.org/easylistdutch.txt", category: .regional),
        Self("Dutch", "AdGuard Dutch", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_8_Dutch/filter.txt", category: .regional),
        Self("French", "Liste FR", "https://easylist-downloads.adblockplus.org/liste_fr.txt", category: .regional),
        Self("French", "AdGuard French", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_16_French/filter.txt", category: .regional),
        Self("German", "EasyList Germany", "https://easylist.to/easylistgermany/easylistgermany.txt", category: .regional),
        Self("German", "AdGuard German", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_6_German/filter.txt", category: .regional),
        Self("Greek", "void.gr", "https://www.void.gr/kargig/void-gr-filters.txt", category: .regional),
        Self("Hungarian", "hufilter", "https://cdn.jsdelivr.net/gh/hufilter/hufilter@gh-pages/hufilter.txt", category: .regional),
        Self("Indian languages", "IndianList", "https://easylist-downloads.adblockplus.org/indianlist.txt", category: .regional),
        Self("Indonesian and Malay", "ABPindo", "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt", category: .regional),
        Self("Italian", "EasyList Italy", "https://easylist-downloads.adblockplus.org/easylistitaly.txt", category: .regional),
        Self("Italian", "AdGuard Italian", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_26_Italian/filter.txt", category: .regional),
        Self("Japanese", "Japanese Filters", "https://easylist-downloads.adblockplus.org/japanese-filters.txt", category: .regional),
        Self("Japanese", "AdGuard Japanese", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_7_Japanese/filter.txt", category: .regional),
        Self("Korean", "YousList", "https://raw.githubusercontent.com/yous/YousList/master/youslist.txt", category: .regional),
        Self("Lithuanian", "EasyList Lithuania", "https://raw.githubusercontent.com/EasyList-Lithuania/easylist_lithuania/master/easylistlithuania.txt", category: .regional),
        Self("Nordic countries", "Dandelion Sprout’s Nordic Filters", "https://raw.githubusercontent.com/DandelionSprout/adfilt/master/NorwegianExperimentalList%20alternate%20versions/NordicFiltersABP-Inclusion.txt", category: .regional),
        Self("Persian", "AdBlockFarsi", "https://raw.githubusercontent.com/SlashArash/adblockfa/master/adblockfa.txt", category: .regional),
        Self("Polish", "EasyList Polish", "https://easylist-downloads.adblockplus.org/easylistpolish.txt", category: .regional),
        Self("Polish", "AdGuard Polish", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_27_Polish/filter.txt", category: .regional),
        Self("Portuguese", "EasyList Portuguese", "https://easylist-downloads.adblockplus.org/easylistportuguese.txt", category: .regional),
        Self("Russian", "AdGuard Russian", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_1_Russian/filter.txt", category: .regional),
        Self("Spanish", "EasyList Spanish", "https://easylist-downloads.adblockplus.org/easylistspanish.txt", category: .regional),
        Self("Spanish and Portuguese", "AdGuard Spanish/Portuguese", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_9_Spanish/filter.txt", category: .regional),
        Self("Turkish", "Turkish Filters", "https://easylist-downloads.adblockplus.org/turkish-filters.txt", category: .regional),
        Self("Turkish", "AdGuard Turkish", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_13_Turkish/filter.txt", category: .regional),
        Self("Ukrainian", "AdGuard Ukrainian", "https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_23_Ukrainian/filter.txt", category: .regional),
        Self("Vietnamese", "ABPVN", "https://raw.githubusercontent.com/abpvn/abpvn/master/filter/abpvn.txt", category: .regional),
    ]
}

/// Settings ▸ Privacy's one choice under "Block ads and trackers" (Victor, 26 Nov: nobody should need to
/// know filter lists for blocking to work). Standard is Cra's built-in lists; Strict adds EasyList and
/// EasyPrivacy. Not a stored key: Strict is those two lists being on, so Settings ▸ Privacy ▸ Advanced
/// shows the same lists switched on, and older Cra reads the file unchanged.
public enum AdBlockingLevel: Hashable, Sendable {
    case standard, strict
}

public extension DesktopFilterList {
    static let strictAddresses = ["https://easylist.to/easylist/easylist.txt", "https://easylist.to/easylist/easyprivacy.txt"]
}

public extension AppSettings {
    var adBlockingLevel: AdBlockingLevel {
        get { DesktopFilterList.strictAddresses.allSatisfy(customBlocklists.contains) ? .strict : .standard }
        set { for address in DesktopFilterList.strictAddresses { setFilterList(address, enabled: newValue == .strict) } }
    }

    /// The pane's main switch. On while any of Cra's lists or Strict's are on; off turns all of them off,
    /// back on gives Standard. Lists added by hand and the user's own filters keep their own switches.
    var blocksAdsAndTrackers: Bool {
        get { blockAdsAndTrackers || adBlockingLevel == .strict }
        set {
            blockAdsAndTrackers = newValue
            if !newValue { adBlockingLevel = .standard }
        }
    }
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
                customBlocklists.append(address)
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
/// Only supported selector tokens are interpolated into stylesheets. Lists cannot supply CSS declarations.
public struct DesktopHidingRules {
    private struct Rule {
        var selector: String
        var excluded: Set<String>
        var exception: Bool
    }

    // A type, class or id selector and optional attributes, e.g. div.ad or [id^="ad_"].
    private static let selector = try! NSRegularExpression(pattern:
        #"^(?:[a-zA-Z][a-zA-Z0-9-]*)?(?:(?:[.#][a-zA-Z_][a-zA-Z0-9_-]*)|(?:\[[a-zA-Z][a-zA-Z0-9_-]*(?:[~|^$*]?=(?:"[a-zA-Z0-9_ .:/?=&%-]*"|'[a-zA-Z0-9_ .:/?=&%-]*'|[a-zA-Z0-9_-]+))?\]))+$"#)
    // Site-specific CSS may select a container by its descendants. Keep strings inside
    // complete attribute selectors and admit only native selector functions.
    private static let scopedToken = try! NSRegularExpression(pattern:
        #"(?::(?:has|not|is|where)\(|\)|[ >+~,]|[.#]?[a-zA-Z_][a-zA-Z0-9_-]*|\*|\[[a-zA-Z][a-zA-Z0-9_-]*(?:[~|^$*]?=(?:"[a-zA-Z0-9_ .:/?=&%-]*"|'[a-zA-Z0-9_ .:/?=&%-]*'|[a-zA-Z0-9_-]+))?\])"#)

    // Native class and attribute exclusions on a simple selector can also be global.
    // Semicolons are valid inside a quoted style attribute value.
    private static let simpleExclusion = try! NSRegularExpression(pattern:
        #":not\((?:\.[a-zA-Z_][a-zA-Z0-9_-]*|\[[a-zA-Z][a-zA-Z0-9_-]*(?:[~|^$*]?=(?:"[a-zA-Z0-9_ .:/?=&%;-]*"|'[a-zA-Z0-9_ .:/?=&%;-]*'|[a-zA-Z0-9_-]+))?\])\)"#)

    private static func supports(_ value: String, scoped: Bool) -> Bool {
        var range = NSRange(value.startIndex..., in: value)
        if selector.firstMatch(in: value, range: range) != nil { return true }
        if value.hasSuffix(":empty") {
            let base = String(value.dropLast(6))
            return selector.firstMatch(in: base, range: NSRange(base.startIndex..., in: base)) != nil
        }
        if let exclusion = value.range(of: ":not("),
           selector.firstMatch(in: value, range: NSRange(value.startIndex..<exclusion.lowerBound, in: value)) != nil {
            var rest = NSRange(exclusion.lowerBound..<value.endIndex, in: value)
            while let token = simpleExclusion.firstMatch(in: value, options: .anchored, range: rest) {
                rest.location += token.range.length
                rest.length -= token.range.length
                if rest.length == 0 { return true }
            }
        }
        guard scoped, value.contains(":has(") else { return false }
        let source = value as NSString
        var depth = 0
        while range.length > 0 {
            guard let token = scopedToken.firstMatch(in: value, options: .anchored, range: range) else { return false }
            switch source.character(at: token.range.location) {
            case 58: depth += 1 // opening selector function
            case 41: depth -= 1
            default: break
            }
            guard depth >= 0, depth <= 16 else { return false }
            range.location += token.range.length
            range.length -= token.range.length
        }
        return depth == 0
    }

    private var byHost: [String: [Rule]] = [:]

    private static func parse(_ line: String) -> (hosts: [String], rule: Rule)? {
        guard line.utf8.count <= 2048, let parts = FilterList.cosmetic(line),
              parts.marker == "##" || parts.marker == "#@#",
              parts.domains.isEmpty || !parts.domains.allSatisfy({ $0 == "," }),
              let scopes = FilterList.domains(parts.domains, separator: ","),
              supports(parts.selector, scoped: !scopes.only.isEmpty)
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
        var css = hidden.sorted().map { $0 + "{display:none!important}" }.joined(separator: "\n")
        // Some utility styles force an ad slot back to display:block and reserve a fixed height.
        // Collapse only slots whose hide rule survived the user's cosmetic exceptions.
        let slots = [".ad-container", ".dfp-slot", #"[id^="div-gpt-ad"]"#].filter(hidden.contains)
        if !slots.isEmpty {
            css += "\n" + slots.joined(separator: ",") + "{min-block-size:0!important;max-block-size:0!important;overflow:clip!important}"
        }
        return css
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
