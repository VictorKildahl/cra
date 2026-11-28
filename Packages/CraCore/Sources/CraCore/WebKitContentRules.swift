import Foundation

/// Cra's network rules for WebKit pages (the protected-media tabs and the sites switched to Safari's engine): the
/// same rules the Chromium engine gets (DesktopNetworkRules.compile, from every list that is on and My filters),
/// written as WebKit content-blocker lists (WKContentRuleList's JSON). WebKit has no per-request callback, so it
/// compiles these itself and checks each load against them.
///
/// WebKit reads a list's rules in order: `ignore-previous-rules` undoes what came before it, so the rules go out by
/// Chromium's priority (blocks, exceptions, `$important` blocks, `$important` exceptions). Each list is checked on its
/// own, so a big selection is split into lists that each repeat every rule above the plain blocks. Every list ends
/// by letting a tab's own page load, as Chromium's rules leave `main_frame` alone. A paused site isn't here: a WebKit
/// page takes the lists off before it loads one (WebKitContentBlocking).
public enum WebKitContentRules {
    /// WebKit refuses a list over 150,000 rules; Crest splits at 70,000, and so does Cra.
    public static let maxRulesPerList = 70_000

    /// The JSON of each list, none when `rules` holds nothing WebKit can use.
    public static func lists(from rules: [DesktopNetworkRules.Rule], maxRules: Int = maxRulesPerList) -> [String] {
        build(from: rules, maxRules: maxRules).lists
    }

    /// The lists' JSON and how many rules they hold in all (cra.log's count).
    public static func build(from rules: [DesktopNetworkRules.Rule], maxRules: Int = maxRulesPerList) -> (lists: [String], rules: Int) {
        var plain: [[String: Any]] = []
        var after: [[String: Any]] = []
        let ordered = rules.enumerated().sorted { a, b in
            let pa = rank(a.element), pb = rank(b.element)
            return pa != pb ? pa < pb : a.offset < b.offset
        }
        for (_, rule) in ordered {
            let converted = convert(rule)
            if rule.priority <= 1 && rule.action.type == "block" { plain += converted } else { after += converted }
        }
        guard !plain.isEmpty || after.contains(where: isBlock) else { return ([], 0) }
        after += pageLoads
        let room = max(1, maxRules - after.count)
        var lists: [String] = []
        var count = 0
        var start = 0
        repeat {
            let slice = plain[start..<min(start + room, plain.count)]
            lists.append(json(Array(slice) + after))
            count += slice.count + after.count
            start += room
        } while start < plain.count
        return (lists, count)
    }

    /// Order within the same priority: blocks before the exceptions that undo them.
    private static func rank(_ rule: DesktopNetworkRules.Rule) -> Int {
        rule.priority * 2 + (rule.action.type == "block" ? 0 : 1)
    }

    private static func isBlock(_ rule: [String: Any]) -> Bool {
        (rule["action"] as? [String: String])?["type"] == "block"
    }

    /// A tab's own page and a popup's page always load (Chromium's rules exclude `main_frame`); their subresources are
    /// still checked.
    static let pageLoads: [[String: Any]] = [
        ["trigger": ["url-filter": ".*", "resource-type": ["document"], "load-context": ["top-frame"]], "action": ["type": "ignore-previous-rules"]],
        ["trigger": ["url-filter": ".*", "resource-type": ["popup"]], "action": ["type": "ignore-previous-rules"]],
    ]

    private static func json(_ rules: [[String: Any]]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("[]".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    /// One Chromium rule as WebKit rules: one for each host it names (WebKit's url-filter has no alternation), none
    /// for what WebKit can't say.
    static func convert(_ rule: DesktopNetworkRules.Rule) -> [[String: Any]] {
        let c = rule.condition
        let action: [String: String] = ["type": rule.action.type == "block" ? "block" : "ignore-previous-rules"]
        // `$document` exceptions: every load of a page on the site.
        if rule.action.type == "allowAllRequests" {
            var trigger: [String: Any] = ["url-filter": ".*"]
            if let filter = c.urlFilter {
                guard let top = regex(filter) else { return [] }
                trigger["if-top-url"] = [top]
            } else if let hosts = c.requestDomains, !hosts.isEmpty {
                trigger["if-domain"] = hosts.map { "*" + $0 }
            } else {
                return []
            }
            return [["trigger": trigger, "action": action]]
        }
        var trigger: [String: Any] = [:]
        if let only = c.initiatorDomains {
            // WebKit can't combine the two; an exception keeps the sites it names, a block whose sites have holes is
            // left out rather than blocking where the list said not to.
            if c.excludedInitiatorDomains != nil && rule.action.type == "block" { return [] }
            trigger["if-domain"] = only.map { "*" + $0 }
        } else if let unless = c.excludedInitiatorDomains {
            trigger["unless-domain"] = unless.map { "*" + $0 }
        }
        switch c.domainType {
        case "thirdParty": trigger["load-type"] = ["third-party"]
        case "firstParty": trigger["load-type"] = ["first-party"]
        default: break
        }
        if c.isUrlFilterCaseSensitive == true { trigger["url-filter-is-case-sensitive"] = true }
        if let types = resourceTypes(c) {
            guard !types.isEmpty else { return [] }
            trigger["resource-type"] = types
        }
        if let hosts = c.requestDomains {
            return hosts.map { host in
                var t = trigger
                t["url-filter"] = hostPattern(host)
                return ["trigger": t, "action": action]
            }
        }
        if let pattern = c.urlFilter {
            guard let filter = regex(pattern) else { return [] }
            trigger["url-filter"] = filter
        } else {
            trigger["url-filter"] = ".*"
        }
        return [["trigger": trigger, "action": action]]
    }

    /// WebKit's resource types for Chromium's; nil for every type. `main_frame` needs nothing: `pageLoads` keeps it.
    static func resourceTypes(_ c: DesktopNetworkRules.Condition) -> [String]? {
        if let included = c.resourceTypes {
            return Array(Set(included.compactMap { webKitTypes[$0] })).sorted()
        }
        let excluded = Set((c.excludedResourceTypes ?? []).compactMap { webKitTypes[$0] })
        guard !excluded.isEmpty else { return nil }
        return allTypes.filter { !excluded.contains($0) }
    }

    private static let webKitTypes = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "sub_frame": "document",
        "xmlhttprequest": "fetch", "font": "font", "media": "media", "object": "other", "ping": "ping",
        "websocket": "websocket", "other": "other",
    ]
    private static let allTypes = ["document", "fetch", "font", "image", "media", "other", "ping", "script", "style-sheet", "svg-document", "websocket"]

    /// A whole host and its subdomains (`||host^`), on any scheme and port.
    static func hostPattern(_ host: String) -> String {
        "^[^:]+://+([^:/]+\\.)?" + escape(host) + "[:/]"
    }

    /// The separator `^` stands for: anything but a letter, a digit or `_ - . %` (the end of the address too).
    private static let separator = "[^a-zA-Z0-9_.%-]"

    /// An Adblock Plus address pattern (`||`, `|`, `*`, `^`) as the regular expression WebKit's url-filter takes, which
    /// has no alternation and anchors only at its ends. Nil for one it can't take.
    static func regex(_ pattern: String) -> String? {
        var body = Substring(pattern)
        var out = ""
        if body.hasPrefix("||") {
            out = "^[^:]+://+([^:/]+\\.)?"
            body = body.dropFirst(2)
        } else if body.hasPrefix("|") {
            out = "^"
            body = body.dropFirst()
        }
        var anchoredEnd = false
        if body.hasSuffix("|") {
            anchoredEnd = true
            body = body.dropLast()
        }
        // A leading or trailing wildcard says nothing (WebKit's filter isn't anchored), and slows WebKit's matcher.
        if out.isEmpty { while body.first == "*" { body = body.dropFirst() } }
        if !anchoredEnd { while body.last == "*" { body = body.dropLast() } }
        for (i, ch) in zip(body.indices, body) {
            switch ch {
            case "*": out += ".*"
            case "^":
                let last = body.index(after: i) == body.endIndex
                out += last ? (anchoredEnd ? separator + "?" : "(" + separator + ".*)?$") : separator
                if last && !anchoredEnd { return out }
            default: out += escape(String(ch))
            }
        }
        if anchoredEnd { out += "$" }
        guard !out.isEmpty, out.allSatisfy(\.isASCII) else { return out.isEmpty ? ".*" : nil }
        return out
    }

    private static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            if "\\.+?()[]{}$|^*".contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}
