import CraCore
import Foundation
import Testing

/// Block lists added on top of Cra's own (#507): what a list's text blocks, how a fetched copy
/// is kept, when it's fetched again, and what both apps hand their blocker.
struct CustomBlocklistTests {

    /// The list ABPindo is written in: Adblock Plus syntax. Its whole-domain rules apply; hiding
    /// rules, path rules, exceptions and rules narrowed to some sites can't, and are counted.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func adblockListGivesItsWholeDomainRules() {
        let list = ParsedBlocklist(text: """
        [Adblock Plus 2.0]
        ! Title: ABPindo
        ! Homepage: https://github.com/ABPindo/indonesianadblockrules
        ||judi-slot.example^
        ||ADS.Iklan.example^$third-party
        ||tracker.example^|
        ||popunder.example^$popup,third-party
        ||only-on-news.example^$domain=news.example
        ||cdn.example/banner/*
        @@||allowed.example^
        ##.iklan-banner
        news.example##.ad
        news.example#@#.sponsor
        /banner/ads-*
        """)
        #expect(list.title == "ABPindo")
        #expect(list.domains == ["judi-slot.example", "ads.iklan.example", "tracker.example", "popunder.example"])
        #expect(list.skippedRules == 7)
    }

    /// oisd and most others come as hosts files, plain domains or wildcards; all of it applies.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func hostsPlainWildcardAndDnsmasqListsApply() {
        let list = ParsedBlocklist(text: """
        # Title: oisd small
        #####################
        ## hosts section
        127.0.0.1 localhost
        ::1 localhost ip6-localhost
        0.0.0.0 0.0.0.0
        0.0.0.0 ads.example tracker.example # two on one line
        ads.example
        plain.example.
        *.wild.example
        address=/dns.example/0.0.0.0
        server=/dns2.example/
        not a domain
        """)
        #expect(list.title == "oisd small")
        #expect(list.domains == ["ads.example", "tracker.example", "plain.example", "wild.example", "dns.example", "dns2.example"])
        #expect(list.skippedRules == 1)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func onlyHostNamesAreDomains() {
        let list = ParsedBlocklist(text: "192.168.1.1\nexample\n-bad.example\nbad..example\nbad.example/path\nbücher.example\nok_under.example\n")
        #expect(list.domains == ["ok_under.example"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func typedAddressBecomesAListURL() {
        #expect(CustomBlocklist.listURL(from: "  big.oisd.nl ")?.absoluteString == "https://big.oisd.nl")
        #expect(CustomBlocklist.listURL(from: "https://raw.githubusercontent.com/ABPindo/indonesianadblockrules/master/subscriptions/abpindo.txt") != nil)
        #expect(CustomBlocklist.listURL(from: "http://lists.example/hosts")?.scheme == "http")
        #expect(CustomBlocklist.listURL(from: "file:///Users/me/blocklist.txt")?.isFileURL == true)
        #expect(CustomBlocklist.listURL(from: "localhost/list.txt") == nil)
        #expect(CustomBlocklist.listURL(from: "javascript:alert(1)") == nil)
        #expect(CustomBlocklist.listURL(from: "two words.example") == nil)
        #expect(CustomBlocklist.listURL(from: "") == nil)
    }

    /// The kept copy reads back as it was, keeps its name and survives a title with a line break.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func cachedListReadsBack() throws {
        let fetched = Date(timeIntervalSince1970: 1_800_000_000)
        let parsed = ParsedBlocklist(text: "! Title: ABPindo\n||a.example^\n||b.example^\n##.ad\n")
        let cached = CachedBlocklist(url: "https://lists.example/abpindo.txt", list: parsed, fetched: fetched)
        let read = try #require(CachedBlocklist(text: cached.text))
        #expect(read == cached)
        #expect(read.name == "ABPindo")
        #expect(read.domains == ["a.example", "b.example"])
        #expect(read.skippedRules == 1)

        var injected = cached
        injected.title = "Evil\nevil.example"
        let back = try #require(CachedBlocklist(text: injected.text))
        #expect(back.domains == ["a.example", "b.example"])

        let untitled = CachedBlocklist(url: "https://big.oisd.nl/", list: ParsedBlocklist(text: "x.example"), fetched: fetched)
        #expect(untitled.name == "big.oisd.nl")
        #expect(CachedBlocklist(text: "a.example\nb.example\n") == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func cacheFileNameIsStablePerAddress() {
        let a = CustomBlocklist.cacheFileName(for: "https://big.oisd.nl")
        #expect(a == CustomBlocklist.cacheFileName(for: "https://big.oisd.nl"))
        #expect(a != CustomBlocklist.cacheFileName(for: "https://small.oisd.nl"))
        #expect(a.hasSuffix(".txt") && a.count == 20)
        #expect(a == "26e90077f39e9473.txt")
    }

    /// The Mac scenario's kept copy (Tests/Fixtures/BlocklistProfile) and the iPhone UI test's are
    /// named for these addresses; a new name would leave both reading nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func keptCopiesInTestsMatchTheirAddresses() {
        #expect(CustomBlocklist.cacheFileName(for: "http://127.0.0.1:9/kept-list.txt") == "7eeafa63f8f68fab.txt")
        #expect(CustomBlocklist.cacheFileName(for: "https://lists.invalid/kept.txt") == "dac256c30d0d3b6d.txt")
    }

    /// Add List on each app: https:// assumed, a list added twice stays once, typed file:// refused,
    /// and http:// only on the Mac (the iPhone has no App Transport Security exception).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func addListOnEachApp() {
        let one = ["https://big.oisd.nl"]
        #expect(CustomBlocklist.adding("small.oisd.nl", to: one, httpsOnly: true) == .added(["https://big.oisd.nl", "https://small.oisd.nl"]))
        #expect(CustomBlocklist.adding("https://big.oisd.nl", to: one, httpsOnly: true) == .alreadyAdded)
        #expect(CustomBlocklist.adding(" big.oisd.nl ", to: one, httpsOnly: false) == .alreadyAdded)
        #expect(CustomBlocklist.adding("http://lists.example/hosts", to: [], httpsOnly: false) == .added(["http://lists.example/hosts"]))
        #expect(CustomBlocklist.adding("http://lists.example/hosts", to: [], httpsOnly: true) == .invalid)
        #expect(CustomBlocklist.adding("file:///etc/hosts", to: [], httpsOnly: false) == .invalid)
        #expect(CustomBlocklist.adding("not a list", to: [], httpsOnly: false) == .invalid)
        let file = URL(fileURLWithPath: "/Users/me/blocklist.txt")
        #expect(CustomBlocklist.adding(file, to: one) == .added(["https://big.oisd.nl", "file:///Users/me/blocklist.txt"]))
        #expect(CustomBlocklist.adding(file, to: ["file:///Users/me/blocklist.txt"]) == .alreadyAdded)
    }

    /// A change to the setting: removed lists lose their copy, new ones are fetched in the order
    /// added, and a reorder or an unchanged list fetches nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func settingChangesFetchAndForgetOnlyWhatChanged() {
        let a = "https://a.example/list", b = "https://b.example/list", c = "https://c.example/list"
        let change = CustomBlocklist.changes(from: [a, b], to: [b, c])
        #expect(change.removed == [a])
        #expect(change.added == [c])
        let reorder = CustomBlocklist.changes(from: [a, b], to: [b, a])
        #expect(reorder.removed.isEmpty && reorder.added.isEmpty)
        #expect(CustomBlocklist.changes(from: [], to: [a, b]).added == [a, b])
        #expect(CustomBlocklist.changes(from: [a], to: []).removed == [a])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func onlyListsWithoutAFreshCopyAreFetched() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = "https://fresh.example/list", old = "https://old.example/list", new = "https://new.example/list"
        let fetched = [fresh: now.addingTimeInterval(-3600), old: now.addingTimeInterval(-2 * 24 * 3600)]
        #expect(CustomBlocklist.due([fresh, old, new], fetched: fetched, now: now, atLaunch: true) == [old, new])
        #expect(CustomBlocklist.due([fresh, old, new], fetched: fetched, now: now, atLaunch: false) == [new])
    }

    /// The Mac engine keeps every set it's handed until Cra quits: only a new list, a removed one or a
    /// new fetch gives it another.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func blockerGetsANewSetOnlyWhenTheListsChanged() {
        let a = "https://a.example/list", b = "https://b.example/list"
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        let key = CustomBlocklist.engineKey([a, b], fetched: [a: day])
        #expect(CustomBlocklist.engineKey([a, b], fetched: [a: day]) == key)
        #expect(CustomBlocklist.engineKey([a, b], fetched: [a: day, b: day]) != key, "b's first copy arrived")
        #expect(CustomBlocklist.engineKey([a, b], fetched: [a: day.addingTimeInterval(86400)]) != key, "a was fetched again")
        #expect(CustomBlocklist.engineKey([a], fetched: [a: day, b: day]) != CustomBlocklist.engineKey([a, b], fetched: [a: day, b: day]),
                "b, which had a copy, was removed")
        #expect(CustomBlocklist.engineKey([a, b], fetched: [a: day, b: day]) != CustomBlocklist.engineKey([b, a], fetched: [a: day, b: day]),
                "the lists' order is the set's order")
        #expect(CustomBlocklist.engineKey([], fetched: [:]) == CustomBlocklist.engineKey([a], fetched: [:]), "a list without a copy adds nothing yet")
    }

    /// A day at launch; a week while Cra runs, since each list handed to the engine stays in memory.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func listsAreFetchedAgainWhenOld() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(!CustomBlocklist.isDue(fetched: now.addingTimeInterval(-23 * 3600), now: now, atLaunch: true))
        #expect(CustomBlocklist.isDue(fetched: now.addingTimeInterval(-25 * 3600), now: now, atLaunch: true))
        #expect(!CustomBlocklist.isDue(fetched: now.addingTimeInterval(-25 * 3600), now: now, atLaunch: false))
        #expect(CustomBlocklist.isDue(fetched: now.addingTimeInterval(-8 * 24 * 3600), now: now, atLaunch: false))
        #expect(CustomBlocklist.isDue(fetched: now.addingTimeInterval(3600), now: now, atLaunch: false))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func blockerGetsCrasListThenEachAddedOneOnce() {
        #expect(CustomBlocklist.merged([["a.example", "b.example"], ["b.example", "c.example"], ["a.example"]])
            == ["a.example", "b.example", "c.example"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func rowSaysWhatTheListBlocks() {
        #expect(CustomBlocklist.summary(domains: 48213, skippedRules: 0) == "48,213 domains")
        #expect(CustomBlocklist.summary(domains: 1, skippedRules: 1) == "1 domain · 1 rule Cra can’t use")
        #expect(CustomBlocklist.summary(domains: 12000, skippedRules: 3210) == "12,000 domains · 3,210 rules Cra can’t use")
    }

    /// Older settings files have no lists; the key is saved and read back, and it never goes in a usage report.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func settingsKeepTheAddedLists() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(old.customBlocklists.isEmpty)
        var settings = AppSettings()
        settings.customBlocklists = ["https://big.oisd.nl"]
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(back.customBlocklists == ["https://big.oisd.nl"])
        #expect(UsageStats.unreportedSettings.contains("customBlocklists"))
        #expect(UsageStats.changedSettings(settings)["customBlocklists"] == nil)

        var mobile = MobileSettings()
        mobile.customBlocklists = ["https://big.oisd.nl"]
        #expect(try JSONDecoder().decode(MobileSettings.self, from: JSONEncoder().encode(mobile)).customBlocklists == ["https://big.oisd.nl"])
        #expect(try JSONDecoder().decode(MobileSettings.self, from: Data("{}".utf8)).customBlocklists.isEmpty)
    }

    /// WebKit compiles at most 150,000 rules a list, so the iPhone splits added domains into lists
    /// of 50,000, which every page with Block Ads on gets.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func iPhoneSplitsAddedDomainsIntoRuleLists() {
        let domains = (0..<120_001).map { "d\($0).example" }
        let chunks = MobileBlocklist.customChunks(domains)
        #expect(chunks.map(\.count) == [50_000, 50_000, 20_001])
        #expect(MobileBlocklist.customChunks([]).isEmpty)

        var options = MobileSiteOptions()
        #expect(MobileBlocklist.ruleLists(for: options, customLists: 2) == ["ads", "custom-0", "custom-1", "trackers", "cookie-banners"])
        options.blockAds = false
        #expect(MobileBlocklist.ruleLists(for: options, customLists: 2) == ["trackers", "cookie-banners"])
        #expect(MobileBlocklist.ruleLists(for: MobileSiteOptions()) == ["ads", "trackers", "cookie-banners"])
    }
}

/// The iPhone's first page after launch waits for every rule list it should get (#507).
struct MobileBlockerReadinessTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func firstPageWaitsForAddedListsToo() {
        var r = MobileBlockerReadiness()
        r.launched(addresses: ["https://big.oisd.nl"], first: true)
        #expect(!r.isReady)
        r.ownListsCompiled()
        #expect(!r.isReady, "Cra's own lists alone would let the added list's domains through")
        r.addedListsCompiled()
        #expect(r.isReady)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func addedListsMayFinishFirst() {
        var r = MobileBlockerReadiness()
        r.launched(addresses: ["https://big.oisd.nl"], first: true)
        r.addedListsCompiled()
        #expect(!r.isReady)
        r.ownListsCompiled()
        #expect(r.isReady)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func withoutAddedListsOnlyCrasOwnAreWaitedFor() {
        var r = MobileBlockerReadiness()
        r.launched(addresses: [], first: true)
        #expect(!r.isReady)
        r.ownListsCompiled()
        #expect(r.isReady)
    }

    /// A list added while Cra runs applies from the next load; open pages never wait for it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/507")) func aListAddedLaterHoldsNothingBack() {
        var r = MobileBlockerReadiness()
        r.launched(addresses: [], first: true)
        r.ownListsCompiled()
        r.launched(addresses: ["https://big.oisd.nl"], first: false)
        #expect(r.isReady)
    }
}
