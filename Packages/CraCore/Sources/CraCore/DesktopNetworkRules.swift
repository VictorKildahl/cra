import Foundation

/// The intersection of ABP network filters and Chromium's declarative request API.
/// Keep all conditions of a rule or skip the entire rule.
public enum DesktopNetworkRules {
    public struct Condition: Codable, Hashable {
        public var urlFilter: String?
        public var requestDomains: [String]?
        public var initiatorDomains: [String]?
        public var excludedInitiatorDomains: [String]?
        public var resourceTypes: [String]?
        public var excludedResourceTypes: [String]?
        public var domainType: String?
        public var isUrlFilterCaseSensitive: Bool?
    }

    public struct Rule: Codable {
        public struct Action: Codable { public let type: String }
        public let id: Int
        public let priority: Int
        public let action: Action
        public let condition: Condition
    }

    struct Filter: Hashable {
        var condition: Condition
        var priority: Int
        var allow: Bool
    }

    private static let types = [
        "script": "script", "image": "image", "stylesheet": "stylesheet", "css": "stylesheet",
        "subdocument": "sub_frame", "frame": "sub_frame", "xmlhttprequest": "xmlhttprequest",
        "xhr": "xmlhttprequest", "font": "font", "media": "media", "object": "object",
        "ping": "ping", "beacon": "ping", "websocket": "websocket", "other": "other",
    ]

    static func parse(_ line: String) -> Filter? {
        let allow = line.hasPrefix("@@")
        let body = allow ? line.dropFirst(2) : line[...]
        let parts = body.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        // Chromium rejects the entire dynamic update if a domain anchor starts with a wildcard.
        guard let pattern = parts.first, !pattern.isEmpty, pattern.utf8.count <= 2000,
              !pattern.hasPrefix("||*"), !pattern.contains("#"), !pattern.contains(where: { !$0.isASCII || $0.isWhitespace }),
              !(pattern.count > 1 && pattern.first == "/" && pattern.last == "/") else { return nil }
        var c = Condition()
        var included = Set<String>()
        var excluded = Set<String>()
        var important = false
        var documentException = false
        if parts.count == 2 {
            for raw in parts[1].split(separator: ",", omittingEmptySubsequences: false) {
                let option = raw.lowercased()
                if option.hasPrefix("domain=") || option.hasPrefix("from=") {
                    let names = option.drop(while: { $0 != "=" }).dropFirst().split(separator: "|", omittingEmptySubsequences: false)
                    guard !names.isEmpty, c.initiatorDomains == nil, c.excludedInitiatorDomains == nil else { return nil }
                    var only: [String] = [], unless: [String] = []
                    for name in names {
                        let negated = name.first == "~"
                        guard let domain = ParsedBlocklist.domain(negated ? name.dropFirst() : name[...]),
                              !name.hasSuffix(".") else { return nil }
                        if negated { unless.append(domain) } else { only.append(domain) }
                    }
                    if !only.isEmpty { c.initiatorDomains = only.sorted() }
                    if !unless.isEmpty { c.excludedInitiatorDomains = unless.sorted() }
                    continue
                }
                switch option {
                case "third-party", "3p", "~first-party", "~1p": c.domainType = "thirdParty"
                case "first-party", "1p", "~third-party", "~3p": c.domainType = "firstParty"
                case "match-case": c.isUrlFilterCaseSensitive = true
                case "important": important = true
                case "document", "doc":
                    guard allow else { return nil }
                    documentException = true
                default:
                    let negated = option.hasPrefix("~")
                    guard let type = types[negated ? String(option.dropFirst()) : option] else { return nil }
                    if negated { excluded.insert(type) } else { included.insert(type) }
                }
            }
        }
        if documentException {
            guard included.isEmpty, excluded.isEmpty else { return nil }
            c.resourceTypes = ["main_frame", "sub_frame"]
        } else if !included.isEmpty {
            included.subtract(excluded)
            guard !included.isEmpty else { return nil }
            c.resourceTypes = included.sorted()
        } else {
            // Top-level browsing has always been allowed by Cra's advertising filter.
            c.excludedResourceTypes = excluded.union(["main_frame"]).sorted()
        }
        if pattern.hasPrefix("||"), pattern.last == "^",
           let host = ParsedBlocklist.domain(pattern.dropFirst(2).dropLast()) {
            c.requestDomains = [host]
        } else if pattern != "*" {
            c.urlFilter = String(pattern)
        } else if parts.count == 1 {
            return nil
        }
        return Filter(condition: c, priority: important ? (allow ? 4 : 3) : (allow ? 2 : 1), allow: allow)
    }

    static func disabledRule(_ line: String) -> String? {
        guard let dollar = line.lastIndex(of: "$") else { return nil }
        let options = line[line.index(after: dollar)...].split(separator: ",")
        guard options.contains("badfilter") else { return nil }
        let remaining = options.filter { $0 != "badfilter" }.joined(separator: ",")
        return String(line[..<dollar]) + (remaining.isEmpty ? "" : "$" + remaining)
    }

    public static let dynamicRuleLimit = 30_000

    /// A main-frame exception covers the whole document, including embedded frames.
    /// Anchoring the scheme and the end of the host keeps sibling hosts and subdomains independent.
    public static func siteExceptions(for hosts: [String], after count: Int) -> [Rule] {
        var rules: [Rule] = []
        for host in hosts.sorted() {
            for scheme in ["http", "https"] {
                let condition = Condition(urlFilter: "|\(scheme)://\(host)^", requestDomains: [host], resourceTypes: ["main_frame"])
                rules.append(Rule(id: count + rules.count + 1, priority: 5, action: .init(type: "allowAllRequests"), condition: condition))
            }
        }
        return rules
    }

    /// One group for hosts with identical conditions. Large DNS subscriptions therefore use
    /// hundreds of declarative rules instead of hundreds of thousands.
    public static func compile(domains: [String], lines: [String]) -> [Rule] {
        var filters = [Filter]()
        var seen = Set<Filter>()
        var groups = [Filter: Set<String>]()
        var order = [Filter]()
        if !domains.isEmpty {
            let c = Condition(excludedResourceTypes: ["main_frame"], domainType: "thirdParty")
            let base = Filter(condition: c, priority: 1, allow: false)
            order.append(base)
            groups[base] = Set(domains)
        }
        let disabled = Set(lines.compactMap(disabledRule).compactMap(parse))
        for line in lines {
            guard var filter = parse(line), !disabled.contains(filter) else { continue }
            if let host = filter.condition.requestDomains?.first {
                filter.condition.requestDomains = nil
                if groups[filter] == nil { order.append(filter) }
                groups[filter, default: []].insert(host)
            } else if seen.insert(filter).inserted {
                filters.append(filter)
            }
        }
        for base in order {
            let hosts = (groups[base] ?? []).sorted()
            for start in stride(from: 0, to: hosts.count, by: 1000) {
                var filter = base
                filter.condition.requestDomains = Array(hosts[start..<min(start + 1000, hosts.count)])
                filters.append(filter)
            }
        }
        return filters.enumerated().map { i, f in
            Rule(id: i + 1, priority: f.priority, action: .init(type: f.allow && f.condition.resourceTypes?.contains("main_frame") == true ? "allowAllRequests" : (f.allow ? "allow" : "block")), condition: f.condition)
        }
    }
}
