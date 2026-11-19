import Foundation

/// A list added under Block Lists as the iPhone applies it (#570). #507 kept only a list's domain
/// rules, so EasyList or AdGuard Base gave a fraction of what they block; their path, regex,
/// exception and hiding rules now go through FilterList, each list into rule lists of its own
/// (`MobileBlocklist.customRuleLists`), so its exceptions undo its own blocks.
///
/// A list that has nothing but domains (hosts files, plain or wildcard domain lists, dnsmasq,
/// oisd's "||domain^" form) blocks exactly as #507 had it: by domain, third party, merged with the
/// other lists. A list with more is self-contained: its domain rules go with the rest, so its
/// exceptions undo them. The Mac blocks by domain through Chromium and doesn't use this.
public struct BlocklistRules: Equatable {
    /// The list's own name, from its "Title:" comment.
    public var title: String?
    /// A list of nothing but domains: they're blocked as #507 blocked them, merged with the other
    /// such lists. Empty for a list with full rules.
    public var domains: [String]
    /// A list with more than domains: all its rules, its domains among them. Empty otherwise.
    public var filters: FilterList
    /// The list's rules that apply: its rules that became WebKit rules, or its domains.
    public var appliedRules: Int
    /// Rules WebKit can't run (scriptlets, procedural selectors, `redirect=`, …), counted.
    public var skippedRules: Int

    public var hasFilterRules: Bool { !filters.rules.isEmpty }

    /// Each of a list's rule lists carries all its exceptions after its share of the rules, since an
    /// exception only undoes rules before it in the same list. Past this many, the rest are skipped:
    /// WebKit's 150,000 rules a list less the 50,000 rules a chunk (`MobileBlocklist`, which the Mac's
    /// harnesses don't compile).
    public static let maxExceptions = 100_000

    public init(text: String) {
        var title: String?
        var allDomains: [String] = []
        var allSeen = Set<String>()
        var listSkipped = 0
        var hostDomains: [String] = []
        var hostSeen = Set<String>()
        var domainRules: [String] = []
        var others: [String] = []
        var unusable = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let kind = ParsedBlocklist.classify(line)
            // As #507 reads the list.
            switch kind {
            case .ignored: break
            case .comment(let named): if title == nil, let named { title = named }
            case .domains(let names, _): for name in names where allSeen.insert(name).inserted { allDomains.append(name) }
            case .unusable: listSkipped += 1
            }
            // As FilterList reads it: hiding rules first, which include "###id" (a comment to #507).
            if !line.hasPrefix("!"), FilterList.cosmetic(line) != nil {
                others.append(line)
                continue
            }
            switch kind {
            case .ignored, .comment: break
            case .domains(_, adblock: true): domainRules.append(line)
            case .domains(let names, adblock: false): for name in names where hostSeen.insert(name).inserted { hostDomains.append(name) }
            case .unusable(adblock: true): others.append(line)
            case .unusable(adblock: false): unusable += 1
            }
        }
        self.title = title
        let rest = FilterList(text: others.joined(separator: "\n"))
        guard !rest.rules.isEmpty else {
            domains = allDomains
            filters = FilterList(text: "")
            appliedRules = allDomains.count
            skippedRules = listSkipped
            return
        }
        // Hosts-style lines block as #507's domain rules do (third party, the domain and its
        // subdomains), in the list's own rule lists, so its exceptions undo them too.
        let hostRules = hostDomains.map { "||\($0)^$third-party" }
        filters = FilterList(text: (domainRules + hostRules).joined(separator: "\n")).merging(rest)
        domains = []
        appliedRules = filters.appliedRules
        skippedRules = filters.skippedRules + unusable + max(0, filters.exceptions.count - Self.maxExceptions)
    }

    /// A list blocked by its domains alone.
    public init(domains: [String], skippedRules: Int, title: String?) {
        self.title = title
        self.domains = domains
        filters = FilterList(text: "")
        appliedRules = domains.count
        self.skippedRules = skippedRules
    }

    /// A kept list at launch: its full rules from the rules file written by the same fetch, else
    /// (an older Cra fetched it, or no file) its domains from the #507 file, until the next fetch.
    public static func loading(kept: CachedBlocklist, rulesFile: CachedBlocklistRules?) -> BlocklistRules {
        if let rulesFile, rulesFile.belongs(to: kept) {
            return BlocklistRules(text: rulesFile.listText)
        }
        return BlocklistRules(domains: kept.domains, skippedRules: kept.skippedRules, title: kept.title)
    }

    /// Whether a fetch keeps the list's text in a rules file: only when it has more than domains.
    public static func keepsRulesFile(_ rules: BlocklistRules) -> Bool { rules.hasFilterRules }
}

/// An added list's text as fetched, kept beside #507's file of its domains (`<hash>.txt`) as
/// `<hash>.rules.txt`, for the iPhone's full rules (#570). Three lines say where it came from and
/// which fetch wrote it; the list follows as it was. #507's file is still written as before, so an
/// older Cra reads its domains and never looks at this one. When an older Cra fetches the list
/// again, the two files' dates differ and this one is not used until the next fetch writes both.
public struct CachedBlocklistRules: Equatable {
    public var url: String
    public var fetched: Date
    public var listText: String

    public init(url: String, fetched: Date, listText: String) {
        self.url = url
        self.fetched = fetched
        self.listText = listText
    }

    public static func fileName(for url: String) -> String {
        String(CustomBlocklist.cacheFileName(for: url).dropLast(".txt".count)) + ".rules.txt"
    }

    static let header = "! Cra block list rules (added in Settings): the list as fetched, below these three lines."

    /// Bumped when FilterList turns lists into different rules, so lists compiled before are
    /// compiled again.
    public static let conversion = 1

    /// Names this fetch's compiled rule lists (`MobileBlocklist.ruleListIdentifier`): a new fetch, or
    /// a new conversion, compiles afresh; a launch with the same file looks them up.
    public var ruleListKey: String {
        String(CustomBlocklist.cacheFileName(for: "\(url)\n\(Self.stamp(fetched))\n\(Self.conversion)").dropLast(".txt".count))
    }

    /// Whether this file was written by the fetch that wrote `kept`.
    public func belongs(to kept: CachedBlocklist) -> Bool {
        url == kept.url && Self.stamp(fetched) == Self.stamp(kept.fetched)
    }

    /// Dates as both files write them: whole seconds.
    static func stamp(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }

    public var text: String {
        let oneLine = url.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        return Self.header + "\n! url: " + oneLine + "\n! fetched: " + Self.stamp(fetched) + "\n" + listText
    }

    /// Reads a file `text` wrote; nil for anything else.
    public init?(text: String) {
        let parts = text.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == Self.header, parts[1].hasPrefix("! url: "), parts[2].hasPrefix("! fetched: "),
              let fetched = ISO8601DateFormatter().date(from: String(parts[2].dropFirst("! fetched: ".count)))
        else { return nil }
        url = String(parts[1].dropFirst("! url: ".count))
        self.fetched = fetched
        listText = parts.count > 3 ? String(parts[3]) : ""
    }
}
