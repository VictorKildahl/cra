import Foundation

/// Element hiding a stylesheet can't express (#845): a promoted post on X or Instagram is an ordinary post whose only
/// mark is the text "Promoted" or "Sponsored" in it, so lists find it with uBlock Origin's procedural operators,
/// `x.com##div[data-testid="cellInnerDiv"]:has(span:has-text(/^Ad$/))`, `:upward(3)` to the post around the label,
/// `:xpath(…)`, `:matches-css(…)`. Cra's runner (Resources/blocklist/procedural.js) evaluates these on the page in
/// Cra's own world and hides what they select, again as the page changes. It also takes site-specific selectors the
/// stylesheet path leaves out (DesktopHidingRules accepts only plain selector tokens), because the runner only
/// selects elements and never puts a list's text into a stylesheet. A rule for every site stays out: a procedural
/// selector on every page of every site costs too much.
public enum ProceduralHiding {
    /// The operators procedural.js runs (uBlock Origin's, AdGuard's and Adblock Plus's names).
    public static let operators = [
        "has-text", "contains", "-abp-contains", "has", "-abp-has", "if", "if-not", "not", "upward", "nth-ancestor",
        "xpath", "matches-css", "matches-css-before", "matches-css-after", "min-text-length", "matches-attr",
        "matches-path", "remove", "remove-attr", "remove-class", "watch-attr", "style",
    ]

    /// Operators a selector may contain that the runner can't, so the rule is left out.
    static let unsupported = [":matches-prop(", ":matches-media(", ":others(", ":shadow(", ":-abp-properties(", ":spath("]

    public struct Rule: Equatable, Sendable {
        public var hosts: [String]
        public var excluded: [String]
        public var selector: String
        public var exception: Bool
    }

    /// One line, nil when the stylesheet path takes it (or nobody can).
    public static func parse(_ line: String, trusted: Bool) -> Rule? {
        guard line.utf8.count <= 4096, let parts = FilterList.cosmetic(line),
              ["##", "#?#", "#@#", "#@?#"].contains(parts.marker) else { return nil }
        let selector = parts.selector.trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty, !selector.hasPrefix("+js("), !selector.hasPrefix("^"),
              !selector.contains("{"), !selector.contains("}"),
              !unsupported.contains(where: selector.contains) else { return nil }
        // :style() writes the list's CSS into the page: only from a list Cra trusts.
        if selector.contains(":style("), !trusted { return nil }
        let exception = parts.marker.hasPrefix("#@")
        let procedural = FilterList.extendedSyntax.contains(where: selector.contains)
        // `#?#` without a procedural operator (one line in EasyList) stays unused, as before #845 (#849's counts).
        if parts.marker.contains("?"), !procedural { return nil }
        guard !parts.domains.isEmpty, let scopes = PageRuleDomains.parse(String(parts.domains)), !scopes.only.isEmpty else { return nil }
        // A plain selector the stylesheet path reads stays there.
        if !procedural, DesktopHidingRules(lines: [line]).hasRules { return nil }
        guard balanced(selector) else { return nil }
        return Rule(hosts: scopes.only, excluded: scopes.unless, selector: selector, exception: exception)
    }

    private static func balanced(_ s: String) -> Bool {
        var depth = 0
        var quote: Character?
        var escaped = false
        for c in s {
            if escaped { escaped = false; continue }
            if c == "\\" { escaped = true; continue }
            if let q = quote { if c == q { quote = nil }; continue }
            if c == "\"" || c == "'" { quote = c; continue }
            if c == "(" { depth += 1 } else if c == ")" { depth -= 1; if depth < 0 { return false } }
        }
        return depth == 0 && quote == nil
    }
}

/// The procedural rules of the lists in use, by host.
public struct ProceduralTable: Equatable, Sendable {
    private var selectors: [String: [String]] = [:]
    private var exceptions: [String: Set<String>] = [:]
    private var excludedBy: [String: [String: [String]]] = [:]
    public private(set) var count = 0

    public init() {}

    public mutating func add(lines: [String], trusted: Bool) {
        for line in lines {
            guard let rule = ProceduralHiding.parse(line, trusted: trusted) else { continue }
            if rule.exception {
                for host in rule.hosts { exceptions[host, default: []].insert(rule.selector) }
                continue
            }
            var added = false
            for host in rule.hosts where !(selectors[host]?.contains(rule.selector) ?? false) {
                selectors[host, default: []].append(rule.selector)
                if !rule.excluded.isEmpty { excludedBy[host, default: [:]][rule.selector] = rule.excluded }
                added = true
            }
            if added { count += 1 }
        }
    }

    /// Whether `line` is a rule this table runs (for the list's counts).
    public static func counts(_ line: String, trusted: Bool) -> Bool { ProceduralHiding.parse(line, trusted: trusted) != nil }

    /// The selectors the runner applies on `host`.
    public func selectors(for host: String) -> [String] {
        let keys = ScriptletTable.keys(for: host).filter { !$0.isEmpty }
        let scopes = Set(keys)
        var off = Set<String>()
        for key in keys { off.formUnion(exceptions[key] ?? []) }
        var out: [String] = []
        for key in keys {
            for selector in selectors[key] ?? [] where !off.contains(selector) && !out.contains(selector) {
                if let excluded = excludedBy[key]?[selector], !scopes.isDisjoint(with: excluded) { continue }
                out.append(selector)
            }
        }
        return out
    }

    public var isEmpty: Bool { selectors.isEmpty }
}
