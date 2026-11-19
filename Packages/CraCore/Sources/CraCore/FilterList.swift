import Foundation

/// A filter list in Adblock Plus / uBlock Origin syntax (EasyList's), as WebKit content rules
/// (GitHub #570). Cra's blocker matched domains only, and some ad networks serve the same loader
/// from new domains every few days: its path is what stays. Network rules become `block` rules
/// (paths, wildcards, separators, regexes in WebKit's subset, resource types, first or third
/// party, `domain=`), exceptions become `ignore-previous-rules` after everything they undo, and
/// element hiding becomes `css-display-none`. What WebKit's rules can't express (scriptlets,
/// procedural selectors, `redirect=`, `csp=`, lookarounds, …) is counted in `skippedRules`.
///
/// The iPhone compiles Cra's own list (resources/blocklist/filters.txt) into its Block Ads rule
/// list. Lists added under Block Lists go through it too, each compiled into rule lists of its own
/// (BlocklistRules, MobileBlocklist.customRuleLists).
public struct FilterList: Equatable {
    public static func == (a: FilterList, b: FilterList) -> Bool {
        a.blocking == b.blocking && a.hiding == b.hiding && a.exceptions == b.exceptions
            && a.skippedRules == b.skippedRules && a.appliedRules == b.appliedRules
    }

    public struct Trigger: Equatable {
        /// WebKit's regex subset: no alternation, counted repeats or \d, ASCII only.
        public var urlFilter: String
        public var caseSensitive = false
        public var resourceTypes: [String] = []
        public var loadTypes: [String] = []
        public var loadContexts: [String] = []
        /// "*example.com": the page's site or a subdomain of it.
        public var ifDomains: [String] = []
        public var unlessDomains: [String] = []
    }

    public enum Action: Equatable {
        case block, allow
        case hide(String)
    }

    public struct Rule: Equatable {
        public var trigger: Trigger
        public var action: Action
    }

    public private(set) var blocking: [Rule] = []
    public private(set) var hiding: [Rule] = []
    public private(set) var exceptions: [Rule] = []
    /// Rules Cra can't turn into WebKit's: counted, never guessed at.
    public private(set) var skippedRules = 0
    /// The list's lines that became rules (an exception or a hiding rule counts as one).
    public private(set) var appliedRules = 0
    private let matcher: Matcher

    /// Blocks and hides first, exceptions last: WebKit's `ignore-previous-rules` undoes only the
    /// rules before it in the same list.
    public var rules: [Rule] { blocking + hiding + exceptions }

    /// Generic hiding rules share a rule, this many selectors each: one selector WebKit can't parse
    /// loses only its group.
    static let selectorsPerRule = 100

    public init(text: String) {
        var blocking: [Rule] = []
        var exceptions: [Rule] = []
        var skipped = 0
        var applied = 0
        var generic: [String] = []
        var genericSeen = Set<String>()
        var notGeneric = Set<String>()
        var genericExceptions: [String: [String]] = [:]
        var specific: [(key: [String], unless: Bool, selectors: [String])] = []
        var specificIndex: [SpecificKey: Int] = [:]

        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("!") || line.hasPrefix("[") { continue }
            if let cosmetic = Self.cosmetic(line) {
                guard let selector = Self.usableSelector(cosmetic.selector), cosmetic.marker == "##" || cosmetic.marker == "#@#",
                      let domains = Self.domains(cosmetic.domains, separator: ","), domains.only.isEmpty || domains.unless.isEmpty
                else { skipped += 1; continue }
                if cosmetic.marker == "#@#" {
                    guard domains.unless.isEmpty else { skipped += 1; continue }
                    if domains.only.isEmpty { notGeneric.insert(selector) } else { genericExceptions[selector, default: []] += domains.only }
                } else if domains.only.isEmpty && domains.unless.isEmpty {
                    if genericSeen.insert(selector).inserted { generic.append(selector) }
                } else {
                    let unless = domains.only.isEmpty
                    let key = SpecificKey(domains: unless ? domains.unless : domains.only, unless: unless)
                    // Looked up, not searched: EasyList has tens of thousands of these.
                    if let index = specificIndex[key] {
                        specific[index].selectors.append(selector)
                    } else {
                        specificIndex[key] = specific.count
                        specific.append((key.domains, unless, [selector]))
                    }
                }
                applied += 1
                continue
            }
            if line.hasPrefix("#") { continue }  // a hosts-style comment
            guard let rules = Self.networkRules(line) else { skipped += 1; continue }
            applied += 1
            for rule in rules {
                if rule.action == .allow { exceptions.append(rule) } else { blocking.append(rule) }
            }
        }

        var hiding: [Rule] = []
        var grouped: [String] = []
        for selector in generic where !notGeneric.contains(selector) {
            if let off = genericExceptions[selector] {
                var trigger = Trigger(urlFilter: ".*")
                trigger.unlessDomains = Self.unique(off).map { "*" + $0 }
                hiding.append(Rule(trigger: trigger, action: .hide(selector)))
            } else {
                grouped.append(selector)
            }
        }
        for start in stride(from: 0, to: grouped.count, by: Self.selectorsPerRule) {
            let group = grouped[start..<min(start + Self.selectorsPerRule, grouped.count)]
            hiding.append(Rule(trigger: Trigger(urlFilter: ".*"), action: .hide(group.joined(separator: ", "))))
        }
        for entry in specific {
            var trigger = Trigger(urlFilter: ".*")
            let domains = Self.unique(entry.key).map { "*" + $0 }
            if entry.unless { trigger.unlessDomains = domains } else { trigger.ifDomains = domains }
            for start in stride(from: 0, to: entry.selectors.count, by: Self.selectorsPerRule) {
                let group = entry.selectors[start..<min(start + Self.selectorsPerRule, entry.selectors.count)]
                hiding.append(Rule(trigger: trigger, action: .hide(group.joined(separator: ", "))))
            }
        }

        self.blocking = blocking
        self.hiding = hiding
        self.exceptions = exceptions
        skippedRules = skipped
        appliedRules = applied
        matcher = Matcher(blocking: blocking, exceptions: exceptions)
    }

    private struct SpecificKey: Hashable {
        var domains: [String]
        var unless: Bool
    }

    private init(blocking: [Rule], hiding: [Rule], exceptions: [Rule], skipped: Int, applied: Int) {
        self.blocking = blocking
        self.hiding = hiding
        self.exceptions = exceptions
        skippedRules = skipped
        appliedRules = applied
        matcher = Matcher(blocking: blocking, exceptions: exceptions)
    }

    /// Both lists as one: blocks, hides, then both lists' exceptions.
    public func merging(_ other: FilterList) -> FilterList {
        FilterList(blocking: blocking + other.blocking, hiding: hiding + other.hiding, exceptions: exceptions + other.exceptions,
                   skipped: skippedRules + other.skippedRules, applied: appliedRules + other.appliedRules)
    }

    /// Rules as a WebKit rule list, brackets included.
    public static func json<Rules: Sequence>(_ rules: Rules) -> String where Rules.Element == Rule {
        let objects = rules.map(\.json)
        guard let data = try? JSONSerialization.data(withJSONObject: objects, options: [.withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8)
        else { return "[]" }
        return text
    }

    /// Whether WebKit, given these rules, stops a request for `url` on a page of `pageHost` (nil for
    /// a page with no host, such as a data: page, which WebKit treats as third party to all). Used
    /// to count what was blocked; the resource type isn't known there, so it isn't checked.
    public func blocks(url: String, onPage pageHost: String?) -> Bool {
        matcher.blocks(url: url, pageHost: pageHost?.lowercased())
    }

    /// The rules as WebKit's JSON objects, comma-separated without the surrounding brackets, so
    /// they can follow other rules in one list. Empty when there are none.
    public func contentRulesJSON() -> String {
        let all = rules
        guard !all.isEmpty else { return "" }
        let text = Self.json(all)
        return text == "[]" ? "" : String(text.dropFirst().dropLast())
    }

    // MARK: Network rules

    static let resourceTypes: [String: String] = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "css": "style-sheet", "font": "font",
        "media": "media", "object": "raw", "xmlhttprequest": "raw", "xhr": "raw", "websocket": "raw", "other": "raw",
        "ping": "ping", "beacon": "ping", "popup": "popup", "popunder": "popup",
    ]

    /// One line's rules: usually one, more for a regex with alternatives or a trailing separator.
    /// nil when WebKit can't do what the line asks.
    static func networkRules(_ line: String) -> [Rule]? {
        var body = Substring(line)
        let isException = body.hasPrefix("@@")
        if isException { body = body.dropFirst(2) }
        var pattern = body
        var optionsText: Substring = ""
        if let split = Self.regexOptionsSplit(body) {
            pattern = body[...split]
            optionsText = body[body.index(split, offsetBy: 2)...]
        } else if !(body.hasPrefix("/") && body.hasSuffix("/") && body.count > 2), let dollar = body.lastIndex(of: "$") {
            pattern = body[..<dollar]
            optionsText = body[body.index(after: dollar)...]
        }

        var types: [String] = []
        var frames = false
        var document = false
        var party: String?
        var caseSensitive = false
        var only: [String] = []
        var unless: [String] = []
        for option in optionsText.split(separator: ",") {
            let parts = option.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1)
            guard let name = parts.first?.lowercased() else { continue }
            switch name {
            case "third-party", "3p", "~first-party", "~1p": party = "third-party"
            case "~third-party", "~3p", "first-party", "1p": party = "first-party"
            case "domain", "from":
                guard parts.count == 2, let domains = Self.domains(parts[1], separator: "|") else { return nil }
                only += domains.only
                unless += domains.unless
            case "match-case": caseSensitive = true
            case "important", "all": break
            case "subdocument", "frame": frames = true
            case "document", "doc": document = true
            default:
                guard let type = resourceTypes[name] else { return nil }
                if !types.contains(type) { types.append(type) }
            }
        }
        // WebKit takes if-domain or unless-domain, not both.
        guard only.isEmpty || unless.isEmpty else { return nil }

        let host = Self.wholeHost(pattern)
        // An exception for whole pages ($document): nothing on that site is blocked or hidden.
        if document {
            guard isException, types.isEmpty, !frames, let host else { return nil }
            var trigger = Trigger(urlFilter: ".*")
            trigger.ifDomains = ["*" + host]
            return [Rule(trigger: trigger, action: .allow)]
        }

        let filters: [String]
        if pattern.hasPrefix("/") && pattern.hasSuffix("/") && pattern.count > 2 {
            guard let expanded = RegexExpander.expand(String(pattern.dropFirst().dropLast())) else { return nil }
            filters = expanded
        } else {
            guard let converted = Self.urlFilters(pattern) else { return nil }
            // A rule for every address ("*$popup,domain=…") needs sites to narrow it.
            if converted.isEmpty && only.isEmpty { return nil }
            filters = converted.isEmpty ? [".*"] : converted
        }
        guard !filters.isEmpty, filters.allSatisfy({ $0.allSatisfy(\.isASCII) }) else { return nil }

        // Frames are WebKit's document loads in a child frame; the context would narrow the other
        // types too, so they get rules of their own.
        var variants: [(types: [String], contexts: [String])] = []
        if !types.isEmpty || !frames { variants.append((types, [])) }
        if frames { variants.append((["document"], ["child-frame"])) }

        var rules: [Rule] = []
        for filter in filters {
            for variant in variants {
                var trigger = Trigger(urlFilter: filter)
                trigger.caseSensitive = caseSensitive
                trigger.resourceTypes = variant.types
                trigger.loadContexts = variant.contexts
                trigger.loadTypes = party.map { [$0] } ?? []
                trigger.ifDomains = Self.unique(only).map { "*" + $0 }
                trigger.unlessDomains = Self.unique(unless).map { "*" + $0 }
                rules.append(Rule(trigger: trigger, action: isException ? .allow : .block))
            }
        }
        return rules
    }

    /// Where "/regex/$options" ends its regex: the first "/$" followed by an option's name. An
    /// option's value may hold "/" or "$" itself (`header=link:/x/`), and a regex "\/$" or "$/".
    static func regexOptionsSplit(_ body: Substring) -> Substring.Index? {
        guard body.hasPrefix("/") else { return nil }
        var from = body.index(after: body.startIndex)
        while let range = body[from...].range(of: "/$") {
            if let next = body[range.upperBound...].first, next.isLetter || next == "~" { return range.lowerBound }
            from = range.upperBound
        }
        return nil
    }

    /// "||example.com^" (or "||example.com", "||example.com^|"): the host a whole-site rule names.
    static func wholeHost(_ pattern: Substring) -> String? {
        guard pattern.hasPrefix("||") else { return nil }
        var host = pattern.dropFirst(2)
        if host.hasSuffix("|") { host = host.dropLast() }
        if host.hasSuffix("^") { host = host.dropLast() }
        return ParsedBlocklist.domain(host)
    }

    /// An Adblock Plus address pattern as WebKit url-filters: "||" is the host or a subdomain of it,
    /// "|" an end, "*" anything, "^" a separator (a character other than a letter, digit or
    /// "_-.%", or the end of the address). Empty for a pattern that matches every address; nil for
    /// one WebKit can't take.
    static func urlFilters(_ pattern: Substring) -> [String]? {
        var rest = pattern
        var prefix = ""
        var inHost = false
        if rest.hasPrefix("||") {
            prefix = "^[^:]+://+([^/:]+\\.)?"
            rest = rest.dropFirst(2)
            inHost = true
        } else if rest.hasPrefix("|") {
            prefix = "^"
            rest = rest.dropFirst()
        }
        var endAnchor = false
        if rest.hasSuffix("|") {
            endAnchor = true
            rest = rest.dropLast()
        }
        guard rest.allSatisfy(\.isASCII) else { return nil }
        if prefix.isEmpty { while rest.hasPrefix("*") { rest = rest.dropFirst() } }
        if !endAnchor { while rest.hasSuffix("*") { rest = rest.dropLast() } }
        if rest.isEmpty { return prefix.isEmpty ? [] : nil }

        let separator = "[^a-zA-Z0-9_.%-]"
        var body = ""
        var trailing: [String] = [""]
        let characters = Array(rest)
        for (index, character) in characters.enumerated() {
            switch character {
            case "*":
                body += ".*"
                inHost = false
            case "^":
                if index == characters.count - 1 && !endAnchor {
                    // After a host WebKit's address always goes on with "/" or ":port".
                    trailing = inHost ? ["[/:]"] : [separator, "$"]
                } else {
                    body += inHost ? "[/:]" : separator
                }
                inHost = false
            case "/":
                body += "/"
                inHost = false
            case ".", "+", "?", "(", ")", "[", "]":
                body += "\\" + String(character)
            case "{", "}", "|", "\\", "$":
                return nil
            default:
                guard character.isASCII, !character.isWhitespace else { return nil }
                body += String(character)
            }
        }
        return trailing.map { prefix + body + $0 + (endAnchor ? "$" : "") }
    }

    // MARK: Element hiding

    /// "example.com##.ad" as its sites, marker and selector; nil for a line that isn't one. A
    /// hosts file's "## comment" and "#####" lines aren't: a selector never starts with a space,
    /// and "###" is an id only when a name follows.
    static func cosmetic(_ line: String) -> (domains: Substring, marker: String, selector: String)? {
        let markers = ["#@?#", "#@$#", "#@%#", "#?#", "#$#", "#%#", "#@#", "##"]
        var index = line.startIndex
        while let hash = line[index...].firstIndex(of: "#") {
            let rest = line[hash...]
            if let marker = markers.first(where: { rest.hasPrefix($0) }) {
                let selector = String(rest.dropFirst(marker.count))
                let domains = line[..<hash]
                if domains.contains(where: { $0 == " " || $0 == "/" }) { return nil }
                guard let first = selector.first, first != " ", first != "\t" else { return nil }
                if first == "#" {
                    guard let second = selector.dropFirst().first, second.isLetter || second == "_" || second == "-" else { return nil }
                }
                return (domains, marker, selector)
            }
            index = line.index(after: hash)
        }
        return nil
    }

    /// Selector syntax only uBlock or Adblock Plus run (procedural, scriptlets, HTML filters).
    static let extendedSyntax = [
        ":has-text(", ":-abp-", ":contains(", ":matches-css", ":xpath(", ":upward(", ":remove(", ":style(",
        ":watch-attr(", ":min-text-length(", ":matches-path(", ":matches-attr(", ":matches-prop(", ":matches-media(",
        ":others(", ":if(", ":if-not(", ":nth-ancestor(", ":remove-attr(", ":remove-class(", ":shadow(",
    ]

    static func usableSelector(_ selector: String) -> String? {
        let trimmed = selector.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("+js("), !trimmed.hasPrefix("^"),
              !trimmed.utf8.contains(UInt8(ascii: ":")) || !extendedSyntax.contains(where: { trimmed.contains($0) })
        else { return nil }
        return trimmed
    }

    /// "a.example,~b.example" or "a.example|~b.example": sites a rule is for and not for; nil when
    /// one of them isn't a plain host (uBlock's "example.*" sites, regexes).
    static func domains(_ text: Substring, separator: Character) -> (only: [String], unless: [String])? {
        var only: [String] = []
        var unless: [String] = []
        for entry in text.split(separator: separator) {
            let trimmed = entry.trimmingCharacters(in: .whitespaces)
            let negated = trimmed.hasPrefix("~")
            guard let domain = ParsedBlocklist.domain(Substring(negated ? String(trimmed.dropFirst()) : trimmed)) else { return nil }
            if negated { unless.append(domain) } else { only.append(domain) }
        }
        return (only, unless)
    }

    static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}

extension FilterList.Rule {
    var json: [String: Any] {
        var trigger: [String: Any] = ["url-filter": self.trigger.urlFilter]
        if self.trigger.caseSensitive { trigger["url-filter-is-case-sensitive"] = true }
        if !self.trigger.resourceTypes.isEmpty { trigger["resource-type"] = self.trigger.resourceTypes }
        if !self.trigger.loadTypes.isEmpty { trigger["load-type"] = self.trigger.loadTypes }
        if !self.trigger.loadContexts.isEmpty { trigger["load-context"] = self.trigger.loadContexts }
        if !self.trigger.ifDomains.isEmpty { trigger["if-domain"] = self.trigger.ifDomains }
        if !self.trigger.unlessDomains.isEmpty { trigger["unless-domain"] = self.trigger.unlessDomains }
        let action: [String: Any]
        switch self.action {
        case .block: action = ["type": "block"]
        case .allow: action = ["type": "ignore-previous-rules"]
        case .hide(let selector): action = ["type": "css-display-none", "selector": selector]
        }
        return ["trigger": trigger, "action": action]
    }
}

/// A JavaScript regex (as filter lists write them) in WebKit's subset: alternation becomes one
/// regex per alternative, {n,m} repeats the atom, \d becomes [0-9]. nil for what has no
/// equivalent (lookarounds, backreferences, \s, \b) or expands past `limit` alternatives.
struct RegexExpander {
    static let limit = 64
    static let maxRepeat = 40

    private let characters: [Character]
    private var index = 0

    static func expand(_ regex: String) -> [String]? {
        guard regex.allSatisfy(\.isASCII) else { return nil }
        var expander = RegexExpander(characters: Array(regex))
        guard let alternatives = expander.alternation(), expander.index == expander.characters.count else { return nil }
        let unique = FilterList.unique(alternatives)
        return unique.contains("") || !unique.allSatisfy(anchorsAtEnds) ? nil : unique
    }

    /// WebKit takes "^" only first and "$" only last; elsewhere they'd fail the whole list.
    static func anchorsAtEnds(_ regex: String) -> Bool {
        let characters = Array(regex)
        var inSet = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\" { index += 2; continue }
            if inSet {
                if character == "]" { inSet = false }
            } else if character == "[" {
                inSet = true
                if index + 1 < characters.count, characters[index + 1] == "^" { index += 1 }
            } else if character == "^" && index != 0 {
                return false
            } else if character == "$" && index != characters.count - 1 {
                return false
            }
            index += 1
        }
        return true
    }

    private init(characters: [Character]) { self.characters = characters }

    private var current: Character? { index < characters.count ? characters[index] : nil }

    private mutating func alternation() -> [String]? {
        guard var alternatives = sequence() else { return nil }
        while current == "|" {
            index += 1
            guard let next = sequence() else { return nil }
            alternatives += next
        }
        return alternatives.count <= Self.limit ? alternatives : nil
    }

    private mutating func sequence() -> [String]? {
        var results = [""]
        while let character = current, character != "|", character != ")" {
            guard let atom = atom(), let quantified = quantifier(atom) else { return nil }
            var next: [String] = []
            for result in results { for part in quantified { next.append(result + part) } }
            guard next.count <= Self.limit else { return nil }
            results = next
        }
        return results
    }

    /// One atom: its alternatives, and the text a quantifier can follow when it has just one.
    private mutating func atom() -> (alternatives: [String], unit: String?)? {
        guard let character = current else { return nil }
        index += 1
        switch character {
        case "(":
            if current == "?" {
                guard index + 1 < characters.count, characters[index + 1] == ":" else { return nil }
                index += 2
            }
            guard let inner = alternation(), current == ")" else { return nil }
            index += 1
            if inner.count == 1 { return ([inner[0]], "(" + inner[0] + ")") }
            return (inner, nil)
        case "[":
            guard let set = characterSet() else { return nil }
            return ([set], set)
        case "\\":
            guard let escaped = escape() else { return nil }
            return ([escaped], escaped)
        case ".", "^", "$":
            return ([String(character)], character == "." ? "." : nil)
        case "*", "+", "?", "{", "}", "]":
            return nil
        default:
            guard character.isASCII, !character.isWhitespace else { return nil }
            return ([String(character)], String(character))
        }
    }

    private mutating func escape() -> String? {
        guard let character = current else { return nil }
        index += 1
        switch character {
        case "d": return "[0-9]"
        case "w": return "[a-zA-Z0-9_]"
        case "/", "-", ":", "=", "&", "%", "_", ",", "#", "!", "@", "~", "'", "\"", "<", ">", ";": return String(character)
        case ".", "?", "+", "*", "(", ")", "[", "]", "^", "$": return "\\" + String(character)
        default: return nil
        }
    }

    /// "[...]" with \d and \w spelled out and other escapes reduced to their character.
    private mutating func characterSet() -> String? {
        var set = "["
        if current == "^" { set += "^"; index += 1 }
        var first = true
        while let character = current {
            index += 1
            if character == "]" && !first { return set + "]" }
            first = false
            if character == "\\" {
                guard let escaped = current else { return nil }
                index += 1
                switch escaped {
                case "d": set += "0-9"
                case "w": set += "a-zA-Z0-9_"
                case "-", "]", "\\", "^": set += "\\" + String(escaped)
                case "/", ".", "?", "+", "*", "(", ")", "[", "{", "}", "|", "$", ":", "=", "&", "%", "_", "#", ",": set += String(escaped)
                default: return nil
                }
            } else {
                guard character.isASCII, !character.isWhitespace else { return nil }
                set += String(character)
            }
        }
        return nil
    }

    private mutating func quantifier(_ atom: (alternatives: [String], unit: String?)) -> [String]? {
        guard let character = current else { return atom.alternatives }
        var low: Int
        var high: Int?  // nil: no upper bound
        switch character {
        case "?": low = 0; high = 1; index += 1
        case "*": low = 0; high = nil; index += 1
        case "+": low = 1; high = nil; index += 1
        case "{":
            guard let close = characters[index...].firstIndex(of: "}") else { return nil }
            let inside = String(characters[(index + 1)..<close])
            let numbers = inside.split(separator: ",", omittingEmptySubsequences: false)
            guard let first = numbers.first.flatMap({ Int($0) }), numbers.count <= 2 else { return nil }
            low = first
            if numbers.count == 1 { high = first } else if numbers[1].isEmpty { high = nil } else {
                guard let second = Int(numbers[1]), second >= first else { return nil }
                high = second
            }
            index = close + 1
        default:
            return atom.alternatives
        }
        if current == "?" { index += 1 }  // lazy: the same set of matches
        guard let unit = atom.unit else {
            // Alternatives can be made optional, not repeated: WebKit has no alternation.
            if low == 1 && high == 1 { return atom.alternatives }
            if low == 0 && high == 1 { return atom.alternatives + [""] }
            return nil
        }
        guard low + (high ?? 0) <= Self.maxRepeat else { return nil }
        if low == 0 && high == 1 { return [unit + "?"] }
        if low == 0 && high == nil { return [unit + "*"] }
        if low == 1 && high == nil { return [unit + "+"] }
        var text = String(repeating: unit, count: low)
        if let high {
            text += String(repeating: unit + "?", count: high - low)
        } else {
            text += unit + "*"
        }
        return [text]
    }
}

/// Matches addresses the way the compiled rules do, to count what they stopped.
/// An added list such as EasyList has tens of thousands of rules, so a request isn't run through
/// every regex: each rule is filed under a word its address must contain (`token(of:)`), and a
/// request is checked against the rules filed under its own words, plus the few that have none.
/// Regexes are compiled the first time a rule is checked.
private final class Matcher {
    /// A rule and its regex once compiled. Only used under the matcher's lock.
    final class Indexed {
        let trigger: FilterList.Trigger
        private var regex: NSRegularExpression??

        init(_ trigger: FilterList.Trigger) { self.trigger = trigger }

        func matches(_ url: String) -> Bool {
            if regex == nil {
                let options: NSRegularExpression.Options = trigger.caseSensitive ? [] : [.caseInsensitive]
                regex = .some(try? NSRegularExpression(pattern: trigger.urlFilter, options: options))
            }
            guard let compiled = regex ?? nil else { return false }
            return compiled.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }
    }

    struct Index {
        var rules: [Indexed] = []
        var byToken: [String: [Int]] = [:]
        var everywhere: [Int] = []

        init(_ rules: [FilterList.Rule]) {
            for rule in rules {
                let index = self.rules.count
                self.rules.append(Indexed(rule.trigger))
                if let token = Matcher.token(of: rule.trigger.urlFilter) {
                    byToken[token, default: []].append(index)
                } else {
                    everywhere.append(index)
                }
            }
        }

        func candidates(_ tokens: [String]) -> [Indexed] {
            var seen = Set<Int>()
            var out: [Indexed] = []
            for token in tokens {
                for index in byToken[token] ?? [] where seen.insert(index).inserted { out.append(rules[index]) }
            }
            return out + everywhere.map { rules[$0] }
        }
    }

    private let blocking: Index
    private let exceptions: Index
    private let lock = NSLock()

    init(blocking: [FilterList.Rule], exceptions: [FilterList.Rule]) {
        // A failed request is never a popup or the page itself.
        let counted = blocking.filter { rule in
            let types = rule.trigger.resourceTypes
            return !(types == ["popup"] || (types == ["document"] && rule.trigger.loadContexts != ["child-frame"]))
        }
        self.blocking = Index(counted)
        self.exceptions = Index(exceptions)
    }

    func blocks(url: String, pageHost: String?) -> Bool {
        guard !blocking.rules.isEmpty, let host = URL(string: url)?.host?.lowercased() else { return false }
        let thirdParty = pageHost.map { Self.site($0) != Self.site(host) } ?? true
        func matches(_ rule: Indexed) -> Bool {
            let trigger = rule.trigger
            if trigger.loadTypes == ["third-party"] && !thirdParty { return false }
            if trigger.loadTypes == ["first-party"] && thirdParty { return false }
            if !trigger.ifDomains.isEmpty {
                guard let pageHost, trigger.ifDomains.contains(where: { Self.host(pageHost, isIn: $0) }) else { return false }
            }
            if let pageHost, trigger.unlessDomains.contains(where: { Self.host(pageHost, isIn: $0) }) { return false }
            return rule.matches(url)
        }
        let tokens = Self.tokens(in: url)
        lock.lock()
        defer { lock.unlock() }
        return blocking.candidates(tokens).contains(where: matches) && !exceptions.candidates(tokens).contains(where: matches)
    }

    /// An address's words: its runs of ASCII letters and digits, lowercased.
    static func tokens(in url: String) -> [String] {
        var tokens: [String] = []
        var current: [UInt8] = []
        for byte in url.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"): current.append(byte)
            case UInt8(ascii: "A")...UInt8(ascii: "Z"): current.append(byte + 32)
            default:
                if !current.isEmpty { tokens.append(String(decoding: current, as: UTF8.self)); current.removeAll(keepingCapacity: true) }
            }
        }
        if !current.isEmpty { tokens.append(String(decoding: current, as: UTF8.self)) }
        return tokens
    }

    /// The prefix FilterList writes for "||": the host or a subdomain of it, so what follows starts
    /// after "/" or ".".
    static let hostPrefix = "^[^:]+://+([^/:]+\\.)?"

    /// The longest word every address the filter matches has as a whole word: letters and digits
    /// the filter spells out, with an edge on both sides ("/", ".", a separator class, an anchor).
    /// nil when there is none, as for ".*". By bytes: FilterList's filters are ASCII.
    static func token(of filter: String) -> String? {
        // A piece is a spelled-out byte, an edge (matches only what ends a word, or an end of the
        // address) or open (could match a letter or digit, or nothing).
        let edge: Int16 = -1, open: Int16 = -2
        var pieces: [Int16] = []
        var bytes = Array(filter.utf8)[...]
        if bytes.starts(with: hostPrefixBytes) {
            pieces.append(edge)
            bytes = bytes.dropFirst(hostPrefixBytes.count)
        } else if bytes.first == UInt8(ascii: "^") {
            pieces.append(edge)
            bytes = bytes.dropFirst()
        } else {
            pieces.append(open)
        }
        let characters = Array(bytes)
        var endAnchored = false
        var index = 0
        while index < characters.count {
            let byte = characters[index]
            switch byte {
            case UInt8(ascii: "\\"):
                guard index + 1 < characters.count else { return nil }
                let escaped = characters[index + 1]
                pieces.append(isWord(escaped) || escaped >= 0x80 ? open : Int16(escaped))
                index += 2
                continue
            case UInt8(ascii: "["):
                var close = index + 1
                if close < characters.count, characters[close] == UInt8(ascii: "^") { close += 1 }
                if close < characters.count, characters[close] == UInt8(ascii: "]") { close += 1 }
                while close < characters.count, characters[close] != UInt8(ascii: "]") {
                    close += characters[close] == UInt8(ascii: "\\") ? 2 : 1
                }
                guard close < characters.count else { return nil }
                pieces.append(separatorSets.contains(Array(characters[index...close])) ? edge : open)
                index = close + 1
                continue
            case UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: "?"):
                // The piece before may repeat or be missing.
                if !pieces.isEmpty { pieces[pieces.count - 1] = open }
            case UInt8(ascii: "$") where index == characters.count - 1:
                endAnchored = true
            case UInt8(ascii: "."), UInt8(ascii: "("), UInt8(ascii: ")"), UInt8(ascii: "|"), UInt8(ascii: "^"), UInt8(ascii: "$"),
                 UInt8(ascii: "{"), UInt8(ascii: "}"):
                pieces.append(open)
            default:
                pieces.append(byte >= 0x80 ? open : Int16(byte))
            }
            index += 1
        }
        pieces.append(endAnchored ? edge : open)

        func isWordPiece(_ piece: Int16) -> Bool { piece >= 0 && isWord(UInt8(piece)) }
        func isEdge(_ piece: Int16) -> Bool { piece == edge || (piece >= 0 && !isWord(UInt8(piece))) }
        var best: ArraySlice<Int16>?
        var start = 0
        while start < pieces.count {
            guard isWordPiece(pieces[start]) else { start += 1; continue }
            var end = start
            while end < pieces.count, isWordPiece(pieces[end]) { end += 1 }
            if start > 0, isEdge(pieces[start - 1]), end < pieces.count, isEdge(pieces[end]), end - start > (best?.count ?? 0) {
                best = pieces[start..<end]
            }
            start = end
        }
        return best.map { word in String(decoding: word.map { UInt8($0) }, as: UTF8.self).lowercased() }
    }

    private static let hostPrefixBytes = Array(hostPrefix.utf8)
    private static let separatorSets: Set<[UInt8]> = [Array("[/:]".utf8), Array("[^a-zA-Z0-9_.%-]".utf8)]

    private static func isWord(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
    }

    /// "*example.com" covers example.com and its subdomains.
    static func host(_ host: String, isIn entry: String) -> Bool {
        let domain = entry.hasPrefix("*") ? String(entry.dropFirst()) : entry
        return host == domain || host.hasSuffix("." + domain)
    }

    /// The site a host belongs to, near enough for first or third party: its last two labels, or
    /// three under a country's "co.", "com." and the like.
    static func site(_ host: String) -> String {
        let labels = host.split(separator: ".")
        guard labels.count > 2, let top = labels.last else { return host }
        let second = labels[labels.count - 2]
        let generic: Set<Substring> = ["co", "com", "net", "org", "gov", "edu", "ac", "ne", "or", "go"]
        return labels.suffix(top.count == 2 && generic.contains(second) ? 3 : 2).joined(separator: ".")
    }
}
