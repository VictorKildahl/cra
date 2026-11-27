import Foundation

/// Filter lists' scriptlets (#845): small, named page-script functions a list asks for on a site, written
/// `youtube.com##+js(json-prune, playerResponse.adPlacements)` (uBlock Origin), `youtube.com#%#//scriptlet('json-prune',
/// 'playerResponse.adPlacements')` (AdGuard) or `youtube.com#$#json-prune playerResponse.adPlacements` (Adblock Plus).
/// YouTube's in-stream ads and X's and Instagram's promoted posts arrive in the page's own data, so no network or
/// element rule reaches them; these functions take the ads out of that data before the page reads it. Cra runs its
/// own implementation of each name (Resources/blocklist/scriptlets.js); a name it doesn't implement is skipped.
public enum Scriptlets {
    /// Short and other lists' names, to the name scriptlets.js implements.
    public static let aliases: [String: String] = [
        "set": "set-constant", "set-constant.js": "set-constant",
        "aopr": "abort-on-property-read", "aopw": "abort-on-property-write",
        "acs": "abort-current-script", "acis": "abort-current-script", "abort-current-inline-script": "abort-current-script",
        "nostif": "no-setTimeout-if", "setTimeout-defuser": "no-setTimeout-if", "prevent-setTimeout": "no-setTimeout-if",
        "nosiif": "no-setInterval-if", "setInterval-defuser": "no-setInterval-if", "prevent-setInterval": "no-setInterval-if",
        "nano-stb": "adjust-setTimeout", "nano-setTimeout-booster": "adjust-setTimeout",
        "nano-sib": "adjust-setInterval", "nano-setInterval-booster": "adjust-setInterval",
        "aeld": "addEventListener-defuser", "prevent-addEventListener": "addEventListener-defuser",
        "nowoif": "no-window-open-if", "window.open-defuser": "no-window-open-if", "prevent-window-open": "no-window-open-if",
        "ra": "remove-attr", "rc": "remove-class",
        "noeval": "noeval-if", "prevent-eval-if": "noeval-if",
        "prevent-fetch": "no-fetch-if", "prevent-xhr": "no-xhr-if",
        "rpnt": "replace-node-text", "rmnt": "remove-node-text",
        "trusted-rpnt": "trusted-replace-node-text", "trusted-rpfr": "trusted-replace-fetch-response",
        "json-prune-fetch-response.js": "json-prune-fetch-response",
        "override-property-read": "set-constant", "abort-on-property-read.js": "abort-on-property-read",
        "trusted-set": "trusted-set-constant",
    ]

    /// The names scriptlets.js implements. `trusted-` ones run only from lists Cra trusts (`trustedSources`).
    public static let implemented: Set<String> = [
        "set-constant", "trusted-set-constant",
        "abort-on-property-read", "abort-on-property-write", "abort-current-script",
        "json-prune", "json-prune-fetch-response", "json-prune-xhr-response",
        "json-edit", "json-edit-fetch-response", "json-edit-xhr-response",
        "trusted-json-edit", "trusted-json-edit-fetch-response", "trusted-json-edit-xhr-response",
        "edit-inbound-object", "trusted-edit-inbound-object", "edit-outbound-object", "trusted-edit-outbound-object",
        "trusted-replace-fetch-response", "trusted-replace-xhr-response",
        "no-setTimeout-if", "no-setInterval-if", "adjust-setTimeout", "adjust-setInterval",
        "addEventListener-defuser", "no-window-open-if", "noeval-if", "no-fetch-if", "no-xhr-if",
        "remove-attr", "remove-class", "set-attr",
        "replace-node-text", "trusted-replace-node-text", "remove-node-text",
        "set-cookie", "set-local-storage-item", "set-session-storage-item", "nowebrtc",
    ]

    /// The arguments a scriptlet can't do without (what to set, prune or look for): a call with fewer does nothing,
    /// so it counts as one Cra can't use. Names not here need none.
    public static let requiredArguments: [String: Int] = [
        "set-constant": 2, "trusted-set-constant": 2, "abort-on-property-read": 1, "abort-on-property-write": 1,
        "abort-current-script": 1, "json-prune": 1, "json-prune-fetch-response": 1, "json-prune-xhr-response": 1,
        "json-edit": 1, "json-edit-fetch-response": 1, "json-edit-xhr-response": 1, "trusted-json-edit": 1,
        "trusted-json-edit-fetch-response": 1, "trusted-json-edit-xhr-response": 1, "edit-inbound-object": 3,
        "trusted-edit-inbound-object": 3, "edit-outbound-object": 2, "trusted-edit-outbound-object": 2,
        "trusted-replace-fetch-response": 1, "trusted-replace-xhr-response": 1, "remove-attr": 1, "remove-class": 1,
        "set-attr": 2, "replace-node-text": 2, "trusted-replace-node-text": 2, "remove-node-text": 2, "set-cookie": 2,
        "set-local-storage-item": 2, "set-session-storage-item": 2,
    ]

    /// Lists whose `trusted-` scriptlets run: uBlock Origin's own (as uBlock Origin trusts only its own), and the
    /// user's own filters. A `trusted-` scriptlet rewrites a page's script or data at will, so a list anyone can host
    /// never gets one.
    public static func isTrusted(source address: String) -> Bool {
        if address.isEmpty { return true }  // My filters
        guard let url = URL(string: address), url.scheme == "https", let host = url.host?.lowercased() else { return false }
        if host == "ublockorigin.github.io" { return url.path.hasPrefix("/uAssets/") || url.path.hasPrefix("/uAssetsCDN/") }
        if host == "ublockorigin.pages.dev" { return true }
        if host == "raw.githubusercontent.com" || host == "cdn.jsdelivr.net" {
            return url.path.lowercased().contains("/ublockorigin/uassets")
        }
        return false
    }

    public struct Rule: Equatable, Sendable {
        /// Hosts the rule is for ("" for every site); `example.*` is any top-level domain.
        public var hosts: [String]
        public var excluded: [String]
        /// The name, then its arguments. Empty in an exception that turns every scriptlet off.
        public var call: [String]
        public var exception: Bool
    }

    /// The canonical name for `name` (trimmed, `.js` and list aliases resolved).
    public static func canonical(_ name: String) -> String {
        var n = name.trimmingCharacters(in: .whitespaces)
        if let a = aliases[n] { return a }
        if n.hasSuffix(".js") { n.removeLast(3) }
        return aliases[n] ?? n
    }

    /// One filter line, nil when it isn't a scriptlet line.
    public static func parse(_ line: String) -> Rule? {
        guard line.utf8.count <= 16384 else { return nil }
        // uBlock Origin: `hosts##+js(name, args)` and `hosts#@#+js(...)`.
        for (marker, exception) in [("#@#+js(", true), ("##+js(", false)] {
            guard let at = line.range(of: marker) else { continue }
            guard line.hasSuffix(")") else { return nil }
            let domains = String(line[..<at.lowerBound])
            let inner = String(line[at.upperBound..<line.index(before: line.endIndex)])
            return rule(domains: domains, call: arguments(inner), exception: exception)
        }
        // AdGuard: `hosts#%#//scriptlet('name', 'arg')`, `hosts#@%#//scriptlet(...)`.
        for (marker, exception) in [("#@%#//scriptlet(", true), ("#%#//scriptlet(", false)] {
            guard let at = line.range(of: marker) else { continue }
            guard line.hasSuffix(")") else { return nil }
            let domains = String(line[..<at.lowerBound])
            let inner = String(line[at.upperBound..<line.index(before: line.endIndex)])
            return rule(domains: domains, call: arguments(inner).map(unquote), exception: exception)
        }
        // Adblock Plus: `hosts#$#name arg arg; name2 arg`; only the first call (lists rarely chain).
        if let at = line.range(of: "#$#") {
            let domains = String(line[..<at.lowerBound])
            let body = line[at.upperBound...].split(separator: ";").first.map(String.init) ?? ""
            let words = body.split(separator: " ").map(String.init).map(unquote)
            guard !words.isEmpty else { return nil }
            return rule(domains: domains, call: words, exception: false)
        }
        return nil
    }

    private static func rule(domains: String, call raw: [String], exception: Bool) -> Rule? {
        var call = raw
        if let name = call.first { call[0] = canonical(name) }
        if call == [""] { call = [] }
        guard exception || !call.isEmpty else { return nil }
        if domains.isEmpty {
            // A scriptlet on every site: uBlock Origin allows it, and lists use it sparingly.
            return Rule(hosts: [""], excluded: [], call: call, exception: exception)
        }
        guard let scopes = PageRuleDomains.parse(domains) else { return nil }
        return Rule(hosts: scopes.only.isEmpty ? [""] : scopes.only, excluded: scopes.unless, call: call, exception: exception)
    }

    /// uBlock Origin's argument list: split at commas outside quotes, `\,` an escaped comma, each trimmed, and an
    /// argument quoted in '…', "…" or `…` keeps its commas.
    public static func arguments(_ inner: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var atStart = true
        for c in inner {
            if escaped {
                if c != "," { current.append("\\") }
                current.append(c)
                escaped = false
                continue
            }
            if c == "\\" { escaped = true; continue }
            if let q = quote {
                if c == q { quote = nil } else { current.append(c) }
                continue
            }
            if atStart, c == "'" || c == "\"" || c == "`" {
                quote = c
                atStart = false
                continue
            }
            if c == "," {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                atStart = true
                continue
            }
            if atStart, c == " " { continue }
            atStart = false
            current.append(c)
        }
        if escaped { current.append("\\") }
        out.append(current.trimmingCharacters(in: .whitespaces))
        return out
    }

    private static func unquote(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        for q in ["'", "\""] where t.count >= 2 && t.hasPrefix(q) && t.hasSuffix(q) {
            return String(t.dropFirst().dropLast())
        }
        return t
    }

    /// Names that rewrite a page's own scripts at will, so run only from a trusted list, as in uBlock Origin.
    public static let needsTrust: Set<String> = ["replace-node-text"]

    /// Whether `call` can run: Cra implements its name, and a `trusted-` one (or one in `needsTrust`) comes from a
    /// trusted list.
    public static func runs(_ call: [String], trusted: Bool) -> Bool {
        guard let name = call.first, implemented.contains(name),
              call.count - 1 >= requiredArguments[name, default: 0],
              !call.dropFirst().prefix(requiredArguments[name, default: 0]).contains(where: \.isEmpty) else { return false }
        return trusted || !(name.hasPrefix("trusted-") || needsTrust.contains(name))
    }
}

/// The hosts before a page rule's marker (scriptlets, procedural hiding): `a.com,~b.a.com,site.*`. An entry Cra
/// can't read (a regular expression, a path) is left out rather than dropping the line, as uBlock Origin does; a
/// line left with no host it can read is dropped (it would otherwise apply everywhere).
public enum PageRuleDomains {
    public static func parse(_ text: String) -> (only: [String], unless: [String])? {
        var only: [String] = []
        var unless: [String] = []
        var unreadable = 0
        for entry in text.split(separator: ",") {
            var d = entry.trimmingCharacters(in: .whitespaces).lowercased()
            let negated = d.hasPrefix("~")
            if negated { d.removeFirst() }
            let entity = d.hasSuffix(".*")
            let name = entity ? String(d.dropLast(2)) : d
            guard !name.isEmpty, !name.hasPrefix("."), !name.hasSuffix("."), !name.contains(".."),
                  name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." || $0 == "_" }) else { unreadable += 1; continue }
            if negated { unless.append(d) } else { only.append(d) }
        }
        if only.isEmpty && unreadable > 0 { return nil }
        return (only, unless)
    }
}

/// Every scriptlet rule of the lists in use, by host, for the page script (#845).
public struct ScriptletTable: Equatable, Sendable {
    /// Host (or "" for all, `name.*` for any top-level domain) → calls, each [name, args…].
    public private(set) var calls: [String: [[String]]] = [:]
    /// Host → the calls an exception turns off there, as `call.joined("\u{1F}")`; "" turns off every one.
    public private(set) var exceptions: [String: [String]] = [:]
    /// Host → hosts under it the rule leaves out (`~sub.example.com`).
    private var excludedBy: [String: [[String]: [String]]] = [:]
    public private(set) var count = 0

    public init() {}

    /// Adds `lines` of one list; `trusted` lets its `trusted-` scriptlets run.
    public mutating func add(lines: [String], trusted: Bool) {
        for line in lines {
            guard let rule = Scriptlets.parse(line) else { continue }
            if rule.exception {
                let key = rule.call.joined(separator: "\u{1F}")
                for host in rule.hosts where !(exceptions[host]?.contains(key) ?? false) { exceptions[host, default: []].append(key) }
                continue
            }
            guard Scriptlets.runs(rule.call, trusted: trusted) else { continue }
            var added = false
            for host in rule.hosts where !(calls[host]?.contains(rule.call) ?? false) {
                calls[host, default: []].append(rule.call)
                if !rule.excluded.isEmpty { excludedBy[host, default: [:]][rule.call] = rule.excluded }
                added = true
            }
            if added { count += 1 }
        }
    }

    /// Whether a line is one of these rules Cra runs (for the list's counts).
    public static func counts(_ line: String, trusted: Bool) -> Bool {
        guard let rule = Scriptlets.parse(line) else { return false }
        return rule.exception || Scriptlets.runs(rule.call, trusted: trusted)
    }

    /// The keys a page on `host` reads: the host and each parent, each also as `label.*`, and "".
    public static func keys(for host: String) -> [String] {
        var keys: [String] = []
        var labels = host.lowercased().split(separator: ".").map(String.init)
        while !labels.isEmpty {
            keys.append(labels.joined(separator: "."))
            if labels.count >= 2 { keys.append(labels.dropLast().joined(separator: ".") + ".*") }
            labels.removeFirst()
        }
        return keys + [""]
    }

    /// The calls that run on `host` (what scriptlets.js computes from `json`, for tests and counts).
    public func calls(for host: String) -> [[String]] {
        let keys = Self.keys(for: host)
        let scopes = Set(keys)
        var off = Set<String>()
        for key in keys { off.formUnion(exceptions[key] ?? []) }
        if off.contains("") { return [] }
        var out: [[String]] = []
        for key in keys {
            for call in calls[key] ?? [] where !off.contains(call.joined(separator: "\u{1F}")) && !out.contains(call) {
                if let excluded = excludedBy[key]?[call], !scopes.isDisjoint(with: Self.excludedKeys(excluded)) { continue }
                out.append(call)
            }
        }
        return out
    }

    private static func excludedKeys(_ hosts: [String]) -> Set<String> { Set(hosts.map { $0.lowercased() }) }

    /// What the page script reads, "" when no scriptlet runs anywhere. Every frame of every page carries it, and AdGuard
    /// Base alone names thousands of sites, so it isn't one object to parse: each part is a string of lines the
    /// script looks up with `indexOf` for its own host and parses only the calls it runs.
    ///   h: "\n<host>\t<i>,<j>\n…" the calls (by number) for a host;  r: "\n<i>\t<[name, args…] as JSON>\n…";
    ///   x: "\n<host>\t<[exception keys] as JSON>\n…";  e: "\n<host>\t<i>\t<[excluded hosts] as JSON>\n…";
    ///   p: the paused hosts.
    public func json(paused: [String]) -> String {
        guard !calls.isEmpty else { return "" }
        var index: [[String]: Int] = [:]
        var r = "\n", h = "\n", x = "\n", e = "\n"
        func encode(_ value: Any) -> String {
            (try? JSONSerialization.data(withJSONObject: value)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        }
        for host in calls.keys.sorted() {
            var numbers: [Int] = []
            for call in calls[host] ?? [] {
                let i: Int
                if let known = index[call] { i = known } else {
                    i = index.count
                    index[call] = i
                    r += "\(i)\t" + encode(call) + "\n"
                }
                numbers.append(i)
                if let excluded = excludedBy[host]?[call] { e += "\(host)\t\(i)\t" + encode(excluded) + "\n" }
            }
            h += host + "\t" + numbers.map(String.init).joined(separator: ",") + "\n"
        }
        for host in exceptions.keys.sorted() { x += host + "\t" + encode(exceptions[host] ?? []) + "\n" }
        return encode(["h": h, "r": r, "x": x, "e": e, "p": paused] as [String: Any])
    }

    public var isEmpty: Bool { calls.isEmpty }
}
