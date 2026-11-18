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
