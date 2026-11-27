import Foundation

/// How many of a block list's rules Cra applies, and how many it reads but can't use: what Settings ▸
/// Privacy ▸ Block lists ▸ Advanced… shows under each list (asked for on WhatsApp, 26 Nov 2026: "how
/// much has rules"). A rule is one line Cra acts on: a blocked domain, a network rule (a path, an
/// exception, a rule for some sites) or an element-hiding rule.
public struct BlockListCount: Equatable, Sendable {
    public var applied: Int
    public var skipped: Int

    public init(applied: Int, skipped: Int = 0) {
        self.applied = applied
        self.skipped = skipped
    }

    /// A fetched list (or the person's own filters). With Chromium's network rules (`networkRules`), its
    /// domain lines, network rules and hiding rules apply; an Adblock Plus "||ads.example^" line is one
    /// network rule, not also a domain. Without them (the CEF engine), its domains and hiding rules do.
    public init(_ list: CachedBlocklist, networkRules: Bool) {
        let page = Self.pageRules(list)
        if networkRules && list.hasNetworkSource {
            applied = list.plainDomains.count + list.networkRules.count + page.used.count
        } else {
            applied = list.domains.count + page.used.count
        }
        skipped = list.skippedRules + page.unused
    }

    /// A list's page rules (element hiding, scriptlets, procedural hiding; #845): the ones Cra runs, and how many it
    /// keeps but doesn't (a scriptlet it doesn't implement, a `trusted-` one or `:style()` from a list it doesn't trust).
    public static func pageRules(_ list: CachedBlocklist) -> (used: [String], unused: Int) {
        let trusted = Scriptlets.isTrusted(source: list.url)
        var used: [String] = []
        var unused = 0
        for line in list.hidingRules {
            let runs: Bool
            if Scriptlets.parse(line) != nil {
                runs = ScriptletTable.counts(line, trusted: trusted)
            } else if line.contains(":style(") {
                runs = ProceduralTable.counts(line, trusted: trusted)
            } else {
                runs = true
            }
            if runs { used.append(line) } else { unused += 1 }
        }
        return (used, unused)
    }

    /// "48,210 rules · 3,102 Cra can’t use"; nothing when the list has no rule at all.
    public var summary: String {
        guard applied > 0 || skipped > 0 else { return "" }
        var text = Self.rules(applied)
        if skipped > 0 { text += " · \(Self.number(skipped)) Cra can’t use" }
        return text
    }

    /// The rules in use across every list that is on, each counted once: Cra's built-in domains and hiding rules,
    /// the fetched lists and the person's own filters. Two lists naming one domain block it once.
    public static func total(builtIn: [[String]], builtInHiding: [String] = [], lists: [CachedBlocklist], networkRules: Bool) -> Int {
        var domains = Set<String>()
        var network = Set<String>()
        var hiding = Set(builtInHiding)
        for list in builtIn { domains.formUnion(list) }
        for list in lists {
            if networkRules && list.hasNetworkSource {
                domains.formUnion(list.plainDomains)
                network.formUnion(list.networkRules)
            } else {
                domains.formUnion(list.domains)
            }
            hiding.formUnion(pageRules(list).used)
        }
        return domains.count + network.count + hiding.count
    }

    /// The Block lists row on the Privacy pane: what is in use now.
    public static func inUse(rules: Int, lists: Int) -> String {
        guard rules > 0, lists > 0 else { return "No block list is in use." }
        return "In use: \(Self.rules(rules)) from \(lists == 1 ? "1 list" : "\(number(lists)) lists")."
    }

    static func rules(_ n: Int) -> String { n == 1 ? "1 rule" : "\(number(n)) rules" }

    static func number(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
}
