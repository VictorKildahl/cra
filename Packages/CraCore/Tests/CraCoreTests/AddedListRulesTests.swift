import CraCore
import Foundation
import Testing
#if canImport(WebKit)
import WebKit
#endif

/// Lists added under Block Lists apply their full rules on the iPhone (#570): #507 kept only their
/// domains, so EasyList or AdGuard Base gave a fraction of what they block. Path, regex, exception
/// and element-hiding rules now go through FilterList. The #507 file stays as it was, so an older
/// Cra still reads it; the list's text is kept in a file of its own beside it.
struct AddedListRulesTests {
    static let issue = "https://github.com/VictorKildahl/cra/issues/570"

    static let mixed = """
    [Adblock Plus 2.0]
    ! Title: Regional list
    ||ads.example^
    ||cdn.example/ads/loader.js$script,third-party
    /banner/ad-loader.js$script
    @@||ads.example/ok.js
    ##.sponsored-box
    news.example##.promo
    example.com##+js(nowoif)
    0.0.0.0 hosts.example
    """

    /// Path rules, exceptions and hiding rules apply, not only the domains; a scriptlet is counted.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func anAddedListAppliesItsPathAndHidingRules() throws {
        let rules = BlocklistRules(text: Self.mixed)
        #expect(rules.hasFilterRules)
        #expect(rules.title == "Regional list")
        // The path rule stops the loader on a domain no list has.
        #expect(rules.filters.blocks(url: "https://unlisted-570.example/banner/ad-loader.js", onPage: "site.example"))
        #expect(rules.filters.blocks(url: "https://cdn.example/ads/loader.js", onPage: "site.example"))
        #expect(!rules.filters.blocks(url: "https://cdn.example/app.js", onPage: "site.example"))
        // The whole-domain rule goes with the list's exceptions, which undo it.
        #expect(rules.filters.blocks(url: "https://ads.example/x.js", onPage: "site.example"))
        #expect(!rules.filters.blocks(url: "https://ads.example/ok.js", onPage: "site.example"))
        // A hosts line in the same list still blocks its domain as #507 did, third party only, in
        // the list's own rules rather than the merged domains.
        #expect(rules.domains.isEmpty)
        #expect(rules.filters.blocks(url: "https://cdn.hosts.example/x.js", onPage: "site.example"))
        #expect(!rules.filters.blocks(url: "https://hosts.example/x.js", onPage: "hosts.example"))
        #expect(rules.appliedRules == 7)
        #expect(rules.skippedRules == 1)
        #expect(CustomBlocklist.summary(rules) == "7 rules · 1 rule Cra can’t use")

        // What WebKit gets: the list's rules, with its exceptions last.
        let lists = MobileBlocklist.customRuleLists(domains: rules.domains, filters: [rules.filters])
        try #require(lists.count == 1)
        let objects = try #require(try JSONSerialization.jsonObject(with: Data(lists[0].json().utf8)) as? [[String: Any]])
        let filters = objects.compactMap { ($0["trigger"] as? [String: Any])?["url-filter"] as? String }
        #expect(filters.contains { $0.contains("ad-loader\\.js") })
        let hidden = objects.compactMap { ($0["action"] as? [String: String])?["selector"] }
        #expect(hidden.contains(".sponsored-box"))
        #expect(hidden.contains(".promo"))
        #expect((objects.last?["action"] as? [String: String])?["type"] == "ignore-previous-rules")
    }

    /// A list with nothing but domain rules (hosts files, oisd's "||domain^" form) blocks exactly as
    /// #507 had it: by domain, third party, merged with the other lists. Its row is unchanged.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func aListOfOnlyDomainsStaysADomainList() {
        let text = """
        # Title: oisd small
        127.0.0.1 localhost
        0.0.0.0 ads.example tracker.example
        ||abp.example^
        ||popup.example^$popup,third-party
        not a domain
        """
        let rules = BlocklistRules(text: text)
        let parsed = ParsedBlocklist(text: text)
        #expect(!rules.hasFilterRules)
        #expect(rules.domains == parsed.domains)
        #expect(rules.skippedRules == parsed.skippedRules)
        #expect(CustomBlocklist.summary(rules) == "4 domains · 1 rule Cra can’t use")
        #expect(BlocklistRules.keepsRulesFile(rules) == false)
        #expect(MobileBlocklist.customRuleLists(domains: rules.domains, filters: []).count == 1)
    }

    /// The new file holds the list as fetched under three lines of its own, and reads back. The #507
    /// file beside it is written exactly as before, so an older Cra still reads its domains.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func theListsTextIsKeptInAFileOfItsOwn() throws {
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        let url = "https://lists.example/regional.txt"
        let kept = CachedBlocklistRules(url: url, fetched: fetched, listText: Self.mixed)
        let read = try #require(CachedBlocklistRules(text: kept.text))
        #expect(read == kept)
        #expect(read.listText == Self.mixed)
        #expect(kept.text.hasPrefix("! Cra block list rules"))
        #expect(kept.text.contains("\n! url: https://lists.example/regional.txt\n! fetched: 2027-01-15T08:00:00Z\n"))
        #expect(CachedBlocklistRules.fileName(for: url) == String(CustomBlocklist.cacheFileName(for: url).dropLast(4)) + ".rules.txt")
        #expect(CachedBlocklistRules.fileName(for: "https://big.oisd.nl") == "26e90077f39e9473.rules.txt")

        // An address with a line break can't add lines of its own.
        let evil = CachedBlocklistRules(url: "https://x.example/\n! fetched: 2000-01-01T00:00:00Z", fetched: fetched, listText: "||a.example^")
        let back = try #require(CachedBlocklistRules(text: evil.text))
        #expect(back.fetched == fetched)
        #expect(back.listText == "||a.example^")
        #expect(CachedBlocklistRules(text: "||a.example^\n##.ad\n") == nil)
        #expect(CachedBlocklistRules(text: CachedBlocklist(url: url, list: ParsedBlocklist(text: Self.mixed), fetched: fetched).text) == nil)

        // The #507 file, byte for byte as Cra wrote it before this change.
        let old = CachedBlocklist(url: url, list: ParsedBlocklist(text: Self.mixed), fetched: fetched)
        #expect(old.text == """
        # Cra block list (added in Settings). One domain per line; a domain also blocks its subdomains.
        # url: https://lists.example/regional.txt
        # title: Regional list
        # fetched: 2027-01-15T08:00:00Z
        # skipped: 6
        ads.example
        hosts.example

        """)
    }

    /// Without the new file (a list an older Cra fetched, or one fetched before this change) the
    /// list blocks its domains, as #507 did, until its next fetch writes the file. A file from
    /// another fetch (an older Cra fetched the list again and left it) is not used either.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func withoutItsRulesFileAListFallsBackToItsDomains() {
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        let url = "https://lists.example/regional.txt"
        let kept = CachedBlocklist(url: url, list: ParsedBlocklist(text: Self.mixed), fetched: fetched)

        let fallback = BlocklistRules.loading(kept: kept, rulesFile: nil)
        #expect(!fallback.hasFilterRules)
        #expect(fallback.domains == ["ads.example", "hosts.example"])
        #expect(fallback.skippedRules == 6)
        #expect(CustomBlocklist.summary(fallback) == "2 domains · 6 rules Cra can’t use")

        let stale = CachedBlocklistRules(url: url, fetched: fetched.addingTimeInterval(-86400), listText: Self.mixed)
        #expect(!BlocklistRules.loading(kept: kept, rulesFile: stale).hasFilterRules)
        let otherList = CachedBlocklistRules(url: "https://lists.example/other.txt", fetched: fetched, listText: Self.mixed)
        #expect(!BlocklistRules.loading(kept: kept, rulesFile: otherList).hasFilterRules)

        // Both files as read back from disk, where dates keep whole seconds.
        let later = Date(timeIntervalSince1970: 1_800_000_000.75)
        let keptBack = CachedBlocklist(text: CachedBlocklist(url: url, list: ParsedBlocklist(text: Self.mixed), fetched: later).text)!
        let fileBack = CachedBlocklistRules(text: CachedBlocklistRules(url: url, fetched: later, listText: Self.mixed).text)
        let full = BlocklistRules.loading(kept: keptBack, rulesFile: fileBack)
        #expect(full.hasFilterRules)
        #expect(full == BlocklistRules(text: Self.mixed))
        #expect(BlocklistRules.keepsRulesFile(full))
    }

    /// A big list in EasyList's shape (its sections, rule forms and proportions; made up, no list's
    /// text copied) is split into rule lists under WebKit's 150,000 rules a list, each with the
    /// list's exceptions after its rules, and every one compiles in WebKit's own compiler.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func aBigListStaysUnderWebKitsLimits() async throws {
        let text = SyntheticEasyList.text()
        let parsed = ParsedBlocklist(text: text)
        var clock = ContinuousClock.now
        let rules = BlocklistRules(text: text)
        let parseTime = ContinuousClock.now - clock
        #expect(rules.hasFilterRules)
        #expect(rules.appliedRules > 3 * parsed.domains.count, "far more of the list applies than its domains")
        #expect(rules.filters.hiding.count > 1000)

        let lists = MobileBlocklist.customRuleLists(domains: rules.domains, filters: [rules.filters])
        #expect(lists.count >= 1)
        let exceptions = rules.filters.exceptions.count
        for list in lists {
            #expect(list.ruleCount <= MobileBlocklist.maxRulesPerList)
            let objects = try #require(try JSONSerialization.jsonObject(with: Data(list.json().utf8)) as? [[String: Any]])
            #expect(objects.count == list.ruleCount)
            let types = objects.compactMap { ($0["action"] as? [String: String])?["type"] }
            #expect(Array(types.suffix(exceptions)) == Array(repeating: "ignore-previous-rules", count: exceptions))
        }

        // What it blocks, and that counting a blocked request stays quick with this many rules.
        #expect(rules.filters.blocks(url: "https://adsrv-tozamuqe7.com/serve.js", onPage: "news.example"))
        clock = ContinuousClock.now
        var counted = 0
        for n in 0..<2000 where rules.filters.blocks(url: "https://cdn\(n).example/assets/app-\(n).js?v=\(n)", onPage: "news.example") {
            counted += 1
        }
        let matchTime = ContinuousClock.now - clock
        #expect(counted == 0)
        let lineCount = text.split(whereSeparator: \.isNewline).count
        print("""
        #570 EasyList-shaped list, \(lineCount) lines:
          before (#507 domains): \(parsed.domains.count) domains, \(parsed.skippedRules) rules skipped
          after: \(rules.appliedRules) rules applied (\(rules.domains.count) as domains), \(rules.skippedRules) skipped; \
        \(rules.filters.rules.count) WebKit rules in \(lists.count) lists \(lists.map(\.ruleCount)); parsed in \(parseTime); \
        2000 unblocked URLs checked in \(matchTime)
        """)

        #if canImport(WebKit)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-570-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made: WKContentRuleListStore? = WKContentRuleListStore(url: folder)
        let store = try #require(made)
        for (index, list) in lists.enumerated() {
            let json = list.json()
            let start = ContinuousClock.now
            let compiled: Bool = await withCheckedContinuation { done in
                DispatchQueue.main.async {
                    store.compileContentRuleList(forIdentifier: "cra-test-custom-\(index)", encodedContentRuleList: json) { list, error in
                        if let error { print("compile \(index): \(error)") }
                        done.resume(returning: list != nil)
                    }
                }
            }
            print("  rule list \(index): \(list.ruleCount) rules compiled in \(ContinuousClock.now - start)")
            #expect(compiled, "rule list \(index) compiles")
        }
        #endif
    }

    /// A list past one rule list is split into several, each with all the list's exceptions after
    /// its share of the rules (an exception only undoes rules before it in the same rule list). The
    /// domain lists' merged domains come first, as #507 named them.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func aListPastOneRuleListIsSplitWithItsExceptionsInEach() throws {
        let blocks = (0..<25).map { "/ad-path-\($0)/loader.js" }
        let text = (blocks + ["##.banner", "@@||good.example^", "@@||fine.example/ad-path-3/"]).joined(separator: "\n")
        let rules = BlocklistRules(text: text)
        let lists = MobileBlocklist.customRuleLists(domains: ["a.example", "b.example"], filters: [rules.filters], chunkSize: 10)
        #expect(lists.map(\.ruleCount) == [2, 12, 12, 8])
        #expect(lists.first == .domains(["a.example", "b.example"]))
        var seen: [FilterList.Rule] = []
        for list in lists.dropFirst() {
            guard case .filters(let part, let exceptions) = list else { Issue.record("not a rules list"); continue }
            #expect(Array(exceptions) == rules.filters.exceptions)
            seen += part
        }
        #expect(seen == rules.filters.blocking + rules.filters.hiding)
        #expect(BlocklistRules.maxExceptions + MobileBlocklist.customChunkSize == MobileBlocklist.maxRulesPerList)
    }

    /// At launch a list's compiled rule lists are found by name, without reading the list: the names
    /// carry the fetch and how many there are, so a set cut short (Cra quit while compiling) is
    /// compiled again, and a new fetch or a new conversion gets new names.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func compiledRuleListsAreFoundByName() {
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        let file = CachedBlocklistRules(url: "https://lists.example/regional.txt", fetched: fetched, listText: Self.mixed)
        let key = file.ruleListKey
        #expect(key.count == 16)
        #expect(CachedBlocklistRules(url: file.url, fetched: fetched.addingTimeInterval(0.4), listText: "").ruleListKey == key,
                "the files keep whole seconds")
        #expect(CachedBlocklistRules(url: file.url, fetched: fetched.addingTimeInterval(86400), listText: Self.mixed).ruleListKey != key)
        #expect(CachedBlocklistRules(url: "https://lists.example/other.txt", fetched: fetched, listText: Self.mixed).ruleListKey != key)

        let names = (0..<3).map { MobileBlocklist.ruleListIdentifier(key: key, index: $0, count: 3) }
        #expect(names[0] == "cra-custom-rules-\(key)-0of3")
        #expect(names.allSatisfy { $0.hasPrefix("cra-custom-") }, "removed with the other added lists' when unused")
        let others = ["cra-ads-v2-1-x", "cra-custom-0-12-abc", MobileBlocklist.ruleListIdentifier(key: "0123456789abcdef", index: 0, count: 1)]
        #expect(MobileBlocklist.compiledRuleLists(key: key, in: others + names.reversed()) == names)
        #expect(MobileBlocklist.compiledRuleLists(key: key, in: others + [names[0], names[2]]) == nil)
        #expect(MobileBlocklist.compiledRuleLists(key: key, in: others) == nil)
        #expect(MobileBlocklist.compiledRuleLists(key: key, in: names + [MobileBlocklist.ruleListIdentifier(key: key, index: 0, count: 2)]) == nil)
    }

    /// The kept files as Cra writes them (Fixtures/Model): an older Cra's #507 file loads and saves
    /// back unchanged, and so does the new one.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func keptFilesLoadAsRecorded() throws {
        func text(_ folder: String, _ name: String) throws -> String {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Model/\(folder)"))
            return try String(contentsOf: url, encoding: .utf8)
        }
        let kept = try #require(CachedBlocklist(text: try text("input", "blocklist-kept.txt")))
        #expect(kept.text == (try text("recorded", "blocklist-kept.txt")))
        let file = try #require(CachedBlocklistRules(text: try text("input", "blocklist-rules.txt")))
        #expect(file.text == (try text("recorded", "blocklist-rules.txt")))
        let rules = BlocklistRules.loading(kept: kept, rulesFile: file)
        #expect(rules.hasFilterRules)
        #expect(rules.filters.blocks(url: "https://unlisted-570.example/banner/ad-loader.js", onPage: "site.example"))
    }
}

/// A list in EasyList's shape: its sections in about their proportions (Nov 2026), with each
/// section's usual rule forms. Names are made up from syllables; no list's text is copied.
enum SyntheticEasyList {
    struct Generator {
        var state: UInt64
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        static let syllables = ["ad", "ba", "ce", "do", "fu", "ga", "hi", "jo", "ka", "le", "mo", "nu", "pa", "qe", "ri",
                                "so", "tu", "ve", "wa", "xo", "za", "mi", "ro", "te", "zam", "uq", "e7", "lin", "ster", "vio"]
        mutating func word() -> String {
            (0..<(3 + next(3))).map { _ in Self.syllables[next(Self.syllables.count)] }.joined()
        }
        mutating func pick<T>(_ items: [T]) -> T { items[next(items.count)] }
    }

    static func text() -> String {
        var g = Generator(state: 570)
        let sites = (0..<12_000).map { _ in "\(g.word()).\(g.pick(["com", "net", "org", "co.uk", "de", "fr", "io"]))" }
        var lines = ["[Adblock Plus 2.0]", "! Version: 202611190000", "! Title: EasyList (synthetic shape)", "! Expires: 4 days"]
        func section(_ name: String, _ count: Int, _ make: (inout Generator) -> String) {
            lines.append("! *** easylist:easylist/\(name).txt ***")
            for _ in 0..<count { lines.append(make(&g)) }
        }
        section("easylist_general_block", 4200) { g in
            let w = g.word()
            return g.pick(["-\(w)-ad.", "/\(w)/ads/*", "/\(w)ad.js$script", "_\(w)_banner.", "&\(w)_ad=", "?\(w)adid=",
                           ".com/\(w)/ad-$image", "/ads/\(w).$~third-party", "/\(w)/advert/*$xmlhttprequest", "-\(w)-sponsor-$script,third-party"])
        }
        section("easylist_general_block_dimensions", 600) { g in "-\(100 + g.next(900))x\(50 + g.next(600))-\(g.word())." }
        section("easylist_general_block_popup", 120) { g in "&\(g.word())=$popup" }
        section("easylist_general_hide", 10_500) { g in
            let w = g.word()
            return g.pick(["##.\(w)-ad", "###\(w)Ad\(g.next(99))", "##div[id^=\"\(w)-ad-\"]", "##a[href^=\"https://\(w).com/ads/\"]",
                           "##.\(w)_sponsored", "##[class^=\"\(w)Ad-module\"]", "##aside[data-\(w)=\"ad\"]"])
        }
        section("easylist_allowlist_general_hide", 900) { g in "\(g.pick(sites))#@#.\(g.word())-ad" }
        section("easylist_adservers", 20_500) { g in
            let host = "\(g.word())\(g.next(9)).\(g.pick(["com", "net", "xyz", "online", "site"]))"
            return g.pick(["||\(host)^", "||\(host)^$third-party", "||\(host)^$third-party", "||\(host)^$script,third-party"])
        }
        lines.append("||adsrv-tozamuqe7.com^$third-party")
        section("easylist_adservers_popup", 1600) { g in "||\(g.word()).\(g.pick(["com", "net", "top"]))^$popup" }
        section("easylist_thirdparty", 3100) { g in
            let w = g.word()
            return g.pick(["||\(w).net/ads/\(g.word())/*$script,third-party", "||cdn.\(w).com/banner^", "||\(w).com/js/\(g.word())ad.js",
                           "||static.\(w).io/adserver/$third-party", "||\(w).com^*/pixel.gif$image,third-party"])
        }
        section("easylist_thirdparty_popup", 400) { g in "||\(g.word()).com/\(g.word())/$popup,third-party" }
        section("easylist_specific_block", 2600) { g in
            let site = g.pick(sites), other = g.pick(sites), w = g.word()
            return g.pick(["||\(site)/ad/\(w).js", "/\(w)-banner.js$domain=\(site)|\(other)", "||\(w).com/\(g.word())$script,domain=\(site)",
                           "||\(site)/\(w)/ads/*$image", "||\(site)^*/\(w)-ad-$subdocument"])
        }
        section("easylist_specific_hide", 26_000) { g in
            let site = g.pick(sites), w = g.word()
            return g.pick(["\(site)##.\(w)-promo", "\(site),\(g.pick(sites))##div[class*=\"\(w)\"]", "\(site)###\(w)Banner",
                           "\(site)##.\(w) > .ad", "\(site)##aside.\(w)"])
        }
        section("easylist_specific_hide_abp", 1500) { g in
            "\(g.pick(sites))#?#div:-abp-has(> .\(g.word()))"
        }
        section("easylist_snippets", 300) { g in "\(g.pick(sites))#$#abort-on-property-read \(g.word())" }
        section("easylist_allowlist", 2100) { g in
            let site = g.pick(sites), w = g.word()
            return g.pick(["@@||\(w).com/ads.js$script,domain=\(site)", "@@||\(site)/ads/\(w)$xmlhttprequest", "@@||\(w).net^$script,domain=\(site)"])
        }
        section("easylist_allowlist_generichide", 220) { g in "@@||\(g.pick(sites))^$generichide" }
        section("easylist_rewrite", 30) { g in "||\(g.word()).com/ad.js$rewrite=abp-resource:blank-js" }
        section("easylist_general_block_regex", 40) { g in
            "/^https?:\\/\\/[a-z]{\(6 + g.next(4)),\(12 + g.next(4))}\\.(com|net)\\/[a-z0-9]{10}\\.js$/$script,third-party"
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
