import Foundation

/// Block lists the person adds on top of the one Cra ships (GitHub #507): a regional list such as
/// ABPindo, or a bigger one such as oisd. Not in Arc, which had no blocker of its own; Cra's comes
/// from Dia's onboarding switch, and an added list goes under that switch on the Mac and under
/// Block Ads on the iPhone. The Mac's blocker matches domains, so only a list's domain rules apply
/// there; the iPhone applies its other rules too (#570, BlocklistRules).
public enum CustomBlocklist {
    /// The address a person typed, as the list's URL: https:// is assumed without a scheme. Only
    /// http(s) addresses with a dotted host, and (on the Mac, from Choose File) file URLs.
    public static func listURL(from input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let text = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else { return nil }
        switch scheme {
        case "https", "http":
            guard let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
            return url
        case "file":
            return url.path.isEmpty ? nil : url
        default:
            return nil
        }
    }

    /// The list's cache file name: a stable hash of its address (FNV-1a, 64 bits), so the same
    /// address finds its file on every launch and on both apps.
    public static func cacheFileName(for url: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in url.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx.txt", hash)
    }

    /// How old a fetched list may get before Cra fetches it again. At launch a day (the lists
    /// people add update daily); while Cra runs a week, because the engine keeps every list it
    /// was handed until Cra quits (CraContentBlocker.h never frees a replaced set).
    public static func refreshAge(atLaunch: Bool) -> TimeInterval {
        atLaunch ? 24 * 3600 : 7 * 24 * 3600
    }

    /// Whether a list fetched at `fetched` is due again at `now`. A date ahead of `now` (the clock
    /// went back) counts as due.
    public static func isDue(fetched: Date, now: Date, atLaunch: Bool) -> Bool {
        let age = now.timeIntervalSince(fetched)
        return age < 0 || age >= refreshAge(atLaunch: atLaunch)
    }

    /// What an Add List with `input` does to `addresses`. The iPhone takes only https:// (it has no
    /// App Transport Security exception, so an http:// list would never load); the Mac takes http
    /// too. A typed file:// address is refused on both: files come from Choose File.
    public enum Addition: Equatable {
        case added([String])
        case alreadyAdded
        case invalid
    }

    public static func adding(_ input: String, to addresses: [String], httpsOnly: Bool) -> Addition {
        guard let url = listURL(from: input), !url.isFileURL,
              !httpsOnly || url.scheme?.lowercased() == "https" else { return .invalid }
        return adding(url, to: addresses)
    }

    /// A chosen file, or a checked address.
    public static func adding(_ url: URL, to addresses: [String]) -> Addition {
        let address = url.absoluteString
        return addresses.contains(address) ? .alreadyAdded : .added(addresses + [address])
    }

    /// What a change to the setting means: copies to forget, and lists to fetch, in order.
    public static func changes(from old: [String], to new: [String]) -> (removed: Set<String>, added: [String]) {
        (Set(old).subtracting(new), new.filter { !old.contains($0) })
    }

    /// The lists to fetch now: those with no copy, and those whose copy is due.
    public static func due(_ addresses: [String], fetched: [String: Date], now: Date, atLaunch: Bool) -> [String] {
        addresses.filter { address in
            fetched[address].map { isDue(fetched: $0, now: now, atLaunch: atLaunch) } ?? true
        }
    }

    /// What the blocker was given, as a value: it gets a new set only when this changes. Each set
    /// handed to the Mac engine stays in memory until Cra quits, so a write to settings or a
    /// failed fetch must not hand it the same lists again, and nor must a list that has no copy yet.
    public static func engineKey(_ addresses: [String], fetched: [String: Date]) -> [String] {
        addresses.compactMap { address in fetched[address].map { "\(address) \($0.timeIntervalSince1970)" } }
    }

    /// Every domain the blocker gets: Cra's own list, then each added one, each once.
    public static func merged(_ lists: [[String]]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for list in lists {
            for domain in list where seen.insert(domain).inserted { out.append(domain) }
        }
        return out
    }

    /// The row's second line: how many domains it blocks, and how many of its rules (hiding, path,
    /// exception and per-site ones) Cra can't use.
    public static func summary(domains: Int, skippedRules: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        let n = { (value: Int) in f.string(from: NSNumber(value: value)) ?? String(value) }
        var text = domains == 1 ? "1 domain" : "\(n(domains)) domains"
        if skippedRules > 0 {
            text += " · \(n(skippedRules)) " + (skippedRules == 1 ? "rule" : "rules") + " Cra can’t use"
        }
        return text
    }

    /// The iPhone's row (#570): a list applied with its full rules says how many of its rules apply
    /// (its domain lines among them) and how many can't; a list of domains says it as before.
    public static func summary(_ rules: BlocklistRules) -> String {
        guard rules.hasFilterRules else { return summary(domains: rules.domains.count, skippedRules: rules.skippedRules) }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        let n = { (value: Int) in f.string(from: NSNumber(value: value)) ?? String(value) }
        var text = rules.appliedRules == 1 ? "1 rule" : "\(n(rules.appliedRules)) rules"
        if rules.skippedRules > 0 {
            text += " · \(n(rules.skippedRules)) " + (rules.skippedRules == 1 ? "rule" : "rules") + " Cra can’t use"
        }
        return text
    }
}

/// A list's text as Cra's domain blocker reads it. Takes hosts files ("0.0.0.0 ads.example"), plain
/// domain lists, wildcard lists ("*.ads.example"), dnsmasq lines ("address=/ads.example/") and
/// Adblock Plus syntax, of which only whole-domain rules apply ("||ads.example^", with options that
/// don't narrow it to some sites). Hiding rules ("##.ad"), path rules and exceptions ("@@") are
/// counted in `skippedRules`.
public struct ParsedBlocklist: Equatable {
    /// The list's own name, from its "Title:" comment.
    public var title: String?
    /// Lowercased, each once, in list order.
    public var domains: [String]
    public var skippedRules: Int

    /// Adblock Plus options that leave a whole-domain rule a whole-domain block. Anything else
    /// (`domain=`, `~third-party`, `badfilter`, `redirect`, …) makes it a rule Cra can't apply.
    static let wholeDomainOptions: Set<String> = [
        "third-party", "3p", "all", "important", "script", "image", "stylesheet", "css", "subdocument", "frame",
        "xmlhttprequest", "xhr", "media", "font", "object", "ping", "websocket", "other", "document", "doc", "popup",
    ]

    public init(text: String) {
        var seen = Set<String>()
        var domains: [String] = []
        var skipped = 0
        var title: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            switch Self.classify(raw.trimmingCharacters(in: .whitespaces)) {
            case .ignored: continue
            case .comment(let named):
                if title == nil, let named { title = named }
            case .domains(let names, _):
                for domain in names where seen.insert(domain).inserted { domains.append(domain) }
            case .unusable:
                skipped += 1
            }
        }
        self.title = title
        self.domains = domains
        skippedRules = skipped
    }

    /// What one line of a list is to the domain blocker. BlocklistRules reads lines the same way.
    enum Line: Equatable {
        /// Blank, a "[Adblock Plus 2.0]" header, or a hosts entry for localhost and the like.
        case ignored
        case comment(title: String?)
        /// Blocked by domain. `adblock` for an Adblock Plus "||domain^" rule, false for a hosts,
        /// plain, wildcard or dnsmasq line. A hosts line's names can all be dropped (localhost).
        case domains([String], adblock: Bool)
        /// Not a domain rule. `adblock` when it may be one of Adblock Plus's other rules (hiding,
        /// exception, path), false for a dnsmasq line without a domain.
        case unusable(adblock: Bool)
    }

    /// `line` is trimmed.
    static func classify(_ line: String) -> Line {
        if line.isEmpty || line.hasPrefix("[") { return .ignored }
        let isHiding = isHidingRule(line)
        if line.hasPrefix("!") || (line.hasPrefix("#") && !isHiding) { return .comment(title: title(inComment: line)) }
        if isHiding || line.hasPrefix("@@") { return .unusable(adblock: true) }
        if line.hasPrefix("||") {
            return adblockDomain(line.dropFirst(2)).map { .domains([$0], adblock: true) } ?? .unusable(adblock: true)
        }
        if line.hasPrefix("address=/") || line.hasPrefix("server=/") || line.hasPrefix("local=/") {
            let parts = line.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count >= 2, let name = domain(parts[1]) else { return .unusable(adblock: false) }
            return .domains([name], adblock: false)
        }
        // Hosts files and plain lists: a comment can follow the entries.
        let entry = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let words = entry.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let first = words.first else { return .ignored }
        if words.count > 1, isAddress(first) {
            return .domains(words.dropFirst().compactMap(domain), adblock: false)  // localhost and the like are dropped
        }
        if words.count == 1 {
            let name = first.hasPrefix("*.") ? first.dropFirst(2) : first
            if let name = domain(name) { return .domains([name], adblock: false) }
            if isAddress(first) || ["localhost", "local", "broadcasthost"].contains(first.lowercased()) { return .ignored }
        }
        return .unusable(adblock: true)
    }

    /// An element-hiding rule ("##.ad", "site.example##.ad", "#@#", "#?#", …), told apart from
    /// a hosts file's "## comment" and "#####" lines: a selector never starts with a space or "#".
    static func isHidingRule(_ line: String) -> Bool {
        guard line.utf8.contains(UInt8(ascii: "#")) else { return false }
        let markers = ["##", "#@#", "#?#", "#$#", "#%#"]
        guard line.hasPrefix("#") else { return markers.contains { line.contains($0) } }
        if let marker = markers.dropFirst().first(where: { line.hasPrefix($0) }) { return line.count > marker.count }
        guard line.hasPrefix("##"), let next = line.dropFirst(2).first else { return false }
        return next != " " && next != "#" && next != "\t"
    }

    /// "||ads.example^" or "||ads.example^$third-party": the domain and its subdomains.
    private static func adblockDomain(_ rule: Substring) -> String? {
        let parts = rule.split(separator: "$", maxSplits: 1, omittingEmptySubsequences: false)
        var pattern = parts[0]
        if pattern.hasSuffix("^|") { pattern = pattern.dropLast() }
        guard pattern.hasSuffix("^") else { return nil }
        pattern = pattern.dropLast()
        if parts.count > 1 {
            let options = parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            guard options.allSatisfy(wholeDomainOptions.contains) else { return nil }
        }
        return domain(pattern)
    }

    private static func title(inComment line: String) -> String? {
        let body = line.drop(while: { $0 == "!" || $0 == "#" || $0 == " " })
        guard body.lowercased().hasPrefix("title:") else { return nil }
        let name = body.dropFirst("title:".count).trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : String(name.prefix(80))
    }

    /// An IPv4 or IPv6 address, as hosts files start their lines.
    static func isAddress(_ word: Substring) -> Bool {
        if word.contains(":") { return word.allSatisfy { $0.isHexDigit || $0 == ":" || $0 == "." || $0 == "%" } }
        return !word.isEmpty && word.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
    }

    /// A blockable domain name, lowercased without a trailing dot; nil for an address, a bare name
    /// (localhost) or anything with a path, wildcard or other character a host can't have.
    static func domain(_ word: Substring) -> String? {
        // By bytes: big lists such as EasyList ask this hundreds of thousands of times.
        var bytes: [UInt8] = []
        bytes.reserveCapacity(word.utf8.count)
        for byte in word.utf8 {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"):
                bytes.append(byte)
            case UInt8(ascii: "A")...UInt8(ascii: "Z"):
                bytes.append(byte + 32)
            default:
                return nil
            }
        }
        while bytes.last == UInt8(ascii: ".") { bytes.removeLast() }
        guard bytes.count <= 253, bytes.contains(UInt8(ascii: ".")), bytes.first != UInt8(ascii: "."), bytes.first != UInt8(ascii: "-")
        else { return nil }
        for index in bytes.indices.dropFirst() where bytes[index] == UInt8(ascii: ".") && bytes[index - 1] == UInt8(ascii: ".") { return nil }
        let name = String(decoding: bytes, as: UTF8.self)
        guard !isAddress(Substring(name)), name != "localhost.localdomain" else { return nil }
        return name
    }
}

/// A fetched list as Cra keeps it in the data folder: its domains one per line under a few
/// "#" lines saying where it came from, so it's readable as is and the engine's own list parser
/// would read it too. Saved after each fetch; read at launch, before the next fetch.
public struct CachedBlocklist: Equatable {
    public var url: String
    public var title: String?
    public var fetched: Date
    public var domains: [String]
    public var skippedRules: Int

    public init(url: String, list: ParsedBlocklist, fetched: Date) {
        self.url = url
        title = list.title
        self.fetched = fetched
        domains = list.domains
        skippedRules = list.skippedRules
    }

    private static func dateFormatter() -> ISO8601DateFormatter { ISO8601DateFormatter() }

    /// The name the row shows: the list's own title, else its file name or host.
    public var name: String {
        if let title { return title }
        guard let u = URL(string: url) else { return url }
        if u.isFileURL { return u.lastPathComponent }
        return u.host ?? url
    }

    public var text: String {
        let oneLine = { (s: String) in s.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ") }
        var lines = [
            "# Cra block list (added in Settings). One domain per line; a domain also blocks its subdomains.",
            "# url: " + oneLine(url),
        ]
        if let title { lines.append("# title: " + oneLine(title)) }
        lines.append("# fetched: " + Self.dateFormatter().string(from: fetched))
        lines.append("# skipped: \(skippedRules)")
        return (lines + domains).joined(separator: "\n") + "\n"
    }

    /// Reads a file `text` wrote; nil without its url and fetched lines.
    public init?(text: String) {
        var url: String?
        var title: String?
        var fetched: Date?
        var skipped = 0
        var domains: [String] = []
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard line.hasPrefix("#") else {
                if let d = ParsedBlocklist.domain(Substring(line)) { domains.append(d) }
                continue
            }
            let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
            func value(_ key: String) -> String? {
                body.hasPrefix(key + ":") ? body.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces) : nil
            }
            if let v = value("url") { url = v }
            else if let v = value("title") { title = v }
            else if let v = value("fetched") { fetched = Self.dateFormatter().date(from: v) }
            else if let v = value("skipped") { skipped = Int(v) ?? 0 }
        }
        guard let url, let fetched else { return nil }
        self.url = url
        self.title = title
        self.fetched = fetched
        self.domains = domains
        skippedRules = skipped
    }
}
