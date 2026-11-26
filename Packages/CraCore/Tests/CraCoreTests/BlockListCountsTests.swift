import CraCore
import Foundation
import Testing

/// Settings ▸ Privacy ▸ Block lists shows how many rules each list has and how many are in use
/// (WhatsApp report, 26 Nov 2026: "add block lists with more details, like how many rules").
struct BlockListCountsTests {
    private let abp = """
    [Adblock Plus 2.0]
    ! Title: Fixture
    ||ads.example^
    ||tracker.example^$third-party
    ||cdn.example/banner/*$script
    @@||ads.example/consent.js$script,domain=news.example
    ##.ad-banner
    news.example##.sponsored
    news.example#?#div:has(> .ad)
    /ads-*$redirect=noop.js
    """

    @Test func anAdblockListCountsEachRuleOnceWithChromiumNetworkRules() {
        let list = DesktopHidingRules.read(abp, address: "https://lists.example/abp.txt", fetched: .distantPast)
        let count = BlockListCount(list, networkRules: true)
        // Four network rules (two domains among them, not counted twice) and two hiding rules.
        #expect(count.applied == 6)
        #expect(count.skipped == 2)
        #expect(count.summary == "6 rules · 2 Cra can’t use")
    }

    @Test func withoutNetworkRulesOnlyDomainsAndHidingApply() {
        let list = DesktopHidingRules.read(abp, address: "https://lists.example/abp.txt", fetched: .distantPast)
        // tracker.example and two hiding rules: ads.example has an exception, so the domain blocker leaves it.
        #expect(BlockListCount(list, networkRules: false).applied == 3)
    }

    @Test func aHostsListCountsItsDomains() {
        let list = DesktopHidingRules.read("""
        # Title: Hosts
        0.0.0.0 a.example
        0.0.0.0 b.example
        127.0.0.1 localhost
        c.example
        """, address: "https://lists.example/hosts", fetched: .distantPast)
        #expect(BlockListCount(list, networkRules: true) == BlockListCount(applied: 3))
        #expect(BlockListCount(list, networkRules: true).summary == "3 rules")
    }

    @Test func aKeptCopyCountsAsTheFetchedOne() throws {
        let fetched = DesktopHidingRules.read(abp, address: "https://lists.example/abp.txt", fetched: Date(timeIntervalSince1970: 1_700_000_000))
        let kept = try #require(CachedBlocklist(text: fetched.text))
        #expect(BlockListCount(kept, networkRules: true) == BlockListCount(fetched, networkRules: true))
    }

    @Test func summariesReadAsNumbers() {
        #expect(BlockListCount(applied: 0).summary == "")
        #expect(BlockListCount(applied: 1).summary == "1 rule")
        #expect(BlockListCount(applied: 48_210, skipped: 3_102).summary == "48,210 rules · 3,102 Cra can’t use")
        #expect(BlockListCount.inUse(rules: 26_332, lists: 2) == "In use: 26,332 rules from 2 lists.")
        #expect(BlockListCount.inUse(rules: 5, lists: 1) == "In use: 5 rules from 1 list.")
        #expect(BlockListCount.inUse(rules: 0, lists: 0) == "No block list is in use.")
    }

    @Test func theTotalCountsADomainOnceAcrossLists() {
        let hosts = DesktopHidingRules.read("a.example\nb.example\n", address: "https://lists.example/one", fetched: .distantPast)
        let more = DesktopHidingRules.read("b.example\nc.example\n##.ad\n", address: "https://lists.example/two", fetched: .distantPast)
        let total = BlockListCount.total(builtIn: [["a.example", "z.example"]], lists: [hosts, more], networkRules: true)
        // a, b, c, z and one hiding rule.
        #expect(total == 5)
    }

    @Test func sharedBuiltInHidingRulesCountOnceAcrossSources() {
        let list = DesktopHidingRules.read("##.ad-container", address: "", fetched: .distantPast)
        let builtIn = ["##.ad-container", "##.dfp-slot"]
        for networkRules in [true, false] {
            #expect(BlockListCount.total(builtIn: [], builtInHiding: builtIn, lists: [list], networkRules: networkRules) == 2)
            #expect(BlockListCount.total(builtIn: [], builtInHiding: [], lists: [list], networkRules: networkRules) == 1)
        }
    }
}
