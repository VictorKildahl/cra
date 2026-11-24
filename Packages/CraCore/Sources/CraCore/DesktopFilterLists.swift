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

    public static let catalog = [
        Self("EasyList", "Ads on international sites", "https://easylist.to/easylist/easylist.txt"),
        Self("EasyPrivacy", "Tracking and analytics", "https://easylist.to/easylist/easyprivacy.txt"),
        Self("EasyList Cookie List", "Cookie notices", "https://secure.fanboy.co.nz/fanboy-cookiemonster.txt"),
        Self("Fanboy’s Annoyance List", "Overlays, social widgets and cookie notices", "https://easylist-downloads.adblockplus.org/fanboy-annoyance.txt"),
        Self("Fanboy’s Social Blocking List", "Social sharing buttons and widgets", "https://easylist-downloads.adblockplus.org/fanboy-social.txt"),
        Self("Adblock Warning Removal List", "Anti-adblock notices", "https://easylist-downloads.adblockplus.org/antiadblockfilters.txt"),
        Self("StevenBlack Unified Hosts", "Advertising and tracking domains, also offered by Pi-hole", "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"),
        Self("HaGeZi Multi NORMAL", "A broader general-purpose domain list", "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/multi-onlydomains.txt"),
        Self("HaGeZi Multi PRO", "Stronger alternative to NORMAL. May affect more sites.", "https://cdn.jsdelivr.net/gh/hagezi/dns-blocklists@latest/wildcard/pro-onlydomains.txt"),
        Self("EasyList Germany", "German-language sites", "https://easylist.to/easylistgermany/easylistgermany.txt", regional: true),
        Self("Liste FR", "French-language sites", "https://easylist-downloads.adblockplus.org/liste_fr.txt", regional: true),
        Self("EasyList Italy", "Italian-language sites", "https://easylist-downloads.adblockplus.org/easylistitaly.txt", regional: true),
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
            if !customBlocklists.contains(address) { customBlocklists.append(address) }
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
            // The engine blocks hosts for every third-party resource. Never turn a path,
            // document type or site restriction into a blanket block.
            if line.hasPrefix("||"), let dollar = line.firstIndex(of: "$") {
                let options = line[line.index(after: dollar)...].lowercased().split(separator: ",")
                if !options.allSatisfy({ $0 == "third-party" || $0 == "3p" }) {
                    skipped += 1
                    continue
                }
            }
            if line.hasPrefix("@@||") {
                let host = line.dropFirst(4).prefix { !"^/$|?*".contains($0) }
                if let domain = ParsedBlocklist.domain(host) {
                    allowed.insert(domain)
                    ancestorsOfAllowed.formUnion(Self.suffixes(of: domain))
                }
            }
            networkLines.append(raw)
        }
        var parsed = ParsedBlocklist(text: networkLines.joined(separator: "\n"))
        let before = parsed.domains.count
        if !allowed.isEmpty {
            // A path-specific exception also keeps this host out of our domain-only blocker.
            parsed.domains.removeAll { host in
                ancestorsOfAllowed.contains(host) || !allowed.isDisjoint(with: Self.suffixes(of: host))
            }
        }
        parsed.skippedRules += skipped + before - parsed.domains.count
        var cache = CachedBlocklist(url: address, list: parsed, fetched: fetched)
        cache.hidingRules = lines
        return cache
    }
}
