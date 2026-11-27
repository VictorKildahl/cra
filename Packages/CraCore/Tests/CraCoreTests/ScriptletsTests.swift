import Foundation
import Testing
@testable import CraCore

/// Filter lists' scriptlets and procedural hiding (#845): the YouTube, X and Instagram rules uBlock filters,
/// AdGuard Base and EasyList ship, read the way Cra's page scripts run them.
@Suite struct ScriptletsTests {
    private let issue = "https://github.com/VictorKildahl/cra/issues/845"

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/845"))
    func youTubeRulesParseIntoTheCallsScriptletsJSRuns() throws {
        let prune = try #require(Scriptlets.parse("youtube.com##+js(json-prune, playerResponse.adPlacements playerResponse.playerAds adPlacements playerAds adSlots)"))
        #expect(prune.hosts == ["youtube.com"])
        #expect(prune.call == ["json-prune", "playerResponse.adPlacements playerResponse.playerAds adPlacements playerAds adSlots"])
        // uBlock filters' own rule: `\,` is a comma inside an argument, and an empty argument stays empty.
        let replace = try #require(Scriptlets.parse(#"www.youtube.com##+js(trusted-replace-xhr-response, /"adPlacements.*?([A-Z]"\}|"\}{2\,4})\}\]\,/, , /playlist\?list=|\/player(?:\?.+)?$|watch\?[tv]=/)"#))
        #expect(replace.call == ["trusted-replace-xhr-response", #"/"adPlacements.*?([A-Z]"\}|"\}{2,4})\}\],/"#, "",
                                 #"/playlist\?list=|\/player(?:\?.+)?$|watch\?[tv]=/"#])
        let rpfr = try #require(Scriptlets.parse(#"www.youtube.com##+js(trusted-rpfr, '"adPlacements"', '"no_ads"', player?)"#))
        #expect(rpfr.call == ["trusted-replace-fetch-response", #""adPlacements""#, #""no_ads""#, "player?"])
        let stb = try #require(Scriptlets.parse("www.youtube.com##+js(nano-stb, [native code], 17000, 0.001)"))
        #expect(stb.call == ["adjust-setTimeout", "[native code]", "17000", "0.001"])
        let multi = try #require(Scriptlets.parse("m.youtube.com,youtubekids.com,~music.youtube.com##+js(set, ytInitialPlayerResponse.adPlacements, undefined)"))
        #expect(multi.hosts == ["m.youtube.com", "youtubekids.com"])
        #expect(multi.excluded == ["music.youtube.com"])
        #expect(multi.call == ["set-constant", "ytInitialPlayerResponse.adPlacements", "undefined"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/845"))
    func otherListsSyntaxReadsTheSame() throws {
        // AdGuard and Adblock Plus write the same call their way.
        let adguard = try #require(Scriptlets.parse("youtube.com#%#//scriptlet('set-constant', 'playerResponse.adPlacements', 'undefined')"))
        #expect(adguard.call == ["set-constant", "playerResponse.adPlacements", "undefined"])
        let abp = try #require(Scriptlets.parse("example.com#$#abort-on-property-read adLoader"))
        #expect(abp.call == ["abort-on-property-read", "adLoader"])
        let off = try #require(Scriptlets.parse("example.com#@#+js()"))
        #expect(off.exception && off.call.isEmpty)
        let entity = try #require(Scriptlets.parse("yts.*,eztv.*##+js(nowoif)"))
        #expect(entity.hosts == ["yts.*", "eztv.*"])
        #expect(entity.call == ["no-window-open-if"])
        #expect(Scriptlets.parse("example.com##.ad") == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/845"))
    func trustedScriptletsRunOnlyFromTrustedLists() {
        #expect(Scriptlets.isTrusted(source: DesktopFilterList.ublockFiltersAddress))
        #expect(Scriptlets.isTrusted(source: DesktopFilterList.ublockQuickFixesAddress))
        #expect(Scriptlets.isTrusted(source: "https://ublockorigin.github.io/uAssets/filters/filters.txt"))
        // Strict's page lists are entries of the catalog, so Advanced… shows each with its switch.
        for address in DesktopFilterList.strictPageAddresses {
            #expect(DesktopFilterList.catalog.contains { $0.address == address })
        }
        #expect(Scriptlets.isTrusted(source: ""))  // My filters
        #expect(!Scriptlets.isTrusted(source: DesktopFilterList.adguardBaseAddress))
        #expect(!Scriptlets.isTrusted(source: "https://evil.example/uAssets/filters.txt"))
        #expect(!Scriptlets.isTrusted(source: "http://ublockorigin.github.io/uAssets/filters/filters.txt"))
        let line = #"www.youtube.com##+js(trusted-rpfr, '"adPlacements"', '"no_ads"', player?)"#
        var untrusted = ScriptletTable()
        untrusted.add(lines: [line, "youtube.com##+js(json-prune, adSlots)", "youtube.com##+js(not-a-scriptlet, x)",
                              "youtube.com##+js(rpnt, script, /ads/, x)"], trusted: false)
        #expect(untrusted.calls(for: "www.youtube.com") == [["json-prune", "adSlots"]])
        // A call missing what it needs does nothing, so it isn't run (or counted as in use).
        #expect(!Scriptlets.runs(["set-constant"], trusted: true))
        #expect(!Scriptlets.runs(["set-constant", "", "undefined"], trusted: true))
        #expect(Scriptlets.runs(["set-constant", "ads", "undefined"], trusted: false))
        #expect(Scriptlets.runs(["nowebrtc"], trusted: false))
        var trusted = ScriptletTable()
        trusted.add(lines: [line], trusted: true)
        #expect(trusted.calls(for: "www.youtube.com").count == 1)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/845"))
    func tableKeysExceptionsAndExcludedHosts() throws {
        var table = ScriptletTable()
        table.add(lines: [
            "youtube.com,~music.youtube.com##+js(json-prune, adSlots)",
            "youtube.*##+js(set, ytAds, false)",
            "##+js(nowebrtc)",
            "kids.youtube.com#@#+js(json-prune, adSlots)",
            "tv.youtube.com#@#+js()",
        ], trusted: false)
        #expect(ScriptletTable.keys(for: "www.youtube.com") == ["www.youtube.com", "www.youtube.*", "youtube.com", "youtube.*", "com", ""])
        #expect(table.calls(for: "www.youtube.com") == [["json-prune", "adSlots"], ["set-constant", "ytAds", "false"], ["nowebrtc"]])
        #expect(table.calls(for: "music.youtube.com") == [["set-constant", "ytAds", "false"], ["nowebrtc"]])
        #expect(table.calls(for: "kids.youtube.com") == [["set-constant", "ytAds", "false"], ["nowebrtc"]])
        #expect(table.calls(for: "tv.youtube.com").isEmpty)
        #expect(table.calls(for: "example.org") == [["nowebrtc"]])
        let json = table.json(paused: ["www.youtube.com"])
        let parsed = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(parsed["p"] as? [String] == ["www.youtube.com"])
        // Each call written once, by number; each host names its numbers.
        let r = try #require(parsed["r"] as? String)
        #expect(r.components(separatedBy: "\n").filter { !$0.isEmpty }.count == 3)
        #expect((parsed["h"] as? String)?.contains("\nyoutube.*\t") == true)
        #expect((parsed["x"] as? String)?.contains("\ntv.youtube.com\t[\"\"]\n") == true)
        #expect(ScriptletTable().json(paused: []).isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/845"))
    func ifBlocksForChromiumAreRead() {
        #expect(FilterConditions.holds("env_chromium"))
        #expect(!FilterConditions.holds("ext_ublock"))
        #expect(FilterConditions.holds("!cap_html_filtering"))
        #expect(FilterConditions.holds("(env_mobile || env_chromium) && !adguard"))
        #expect(!FilterConditions.holds("env_safari"))
        let lines = """
        a##+js(set, one, true)
        !#if env_chromium
        b##+js(set, two, true)
        !#else
        c##+js(set, three, true)
        !#endif
        !#if ext_ublock
        d##+js(set, four, true)
        !#if env_chromium
        e##+js(set, five, true)
        !#endif
        !#endif
        """.split(separator: "\n")
        let active = FilterConditions.active(lines)
        #expect(active.lines.map { $0.first.map(String.init) } == ["a", "b"])
        #expect(active.skipped == 3)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/845"))
    func promotedPostRulesGoToTheProceduralRunner() throws {
        // EasyList's X rule and AdGuard Base's Instagram rule: text inside a post, so only the runner can find them.
        let x = try #require(ProceduralHiding.parse(#"twitter.com,x.com#?#h2[role="heading"]:has-text(/Promoted|Gesponsert/)"#, trusted: false))
        #expect(x.hosts == ["twitter.com", "x.com"])
        #expect(x.selector == #"h2[role="heading"]:has-text(/Promoted|Gesponsert/)"#)
        let upward = try #require(ProceduralHiding.parse(#"x.com##div[style^="transform"] h2 > div[style^="-webkit-line-clamp"] > span:has-text(/^(?:Promoted Post)$/):upward(3)"#, trusted: false))
        #expect(upward.selector.hasSuffix(":upward(3)"))
        let instagram = try #require(ProceduralHiding.parse(#"instagram.com##main > div div[style*="flex-direction: column;"] > article > div:has(span:contains(/(Sponsored|Gesponsert)/))"#, trusted: false))
        #expect(instagram.hosts == ["instagram.com"])
        // :style() writes a list's CSS: only from a trusted list.
        let styled = #"instagram.com##article:has(a[href^="https://www.facebook.com/ads/"]):style(height: 0 !important;)"#
        #expect(ProceduralHiding.parse(styled, trusted: false) == nil)
        #expect(ProceduralHiding.parse(styled, trusted: true) != nil)
        // A plain selector the stylesheet takes, a rule for every site, and what the runner can't do stay out.
        #expect(ProceduralHiding.parse("x.com##.promoted-account", trusted: false) == nil)
        #expect(ProceduralHiding.parse("##div:has-text(Ad)", trusted: false) == nil)
        #expect(ProceduralHiding.parse("x.com##div:matches-prop(ad)", trusted: false) == nil)
        #expect(ProceduralHiding.parse("x.com##div:has-text(Ad", trusted: false) == nil)
        #expect(ProceduralHiding.parse("x.com##div{color:red}", trusted: false) == nil)
        // A site-specific selector too complex for the stylesheet goes to the runner instead of being dropped.
        let complex = ##"x.com##[id^="urt"] > ul > li[data-index]:has(.x-link+button [href="#icon-more-dots-hor"])"##
        #expect(ProceduralHiding.parse(complex, trusted: false) != nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/845"))
    func proceduralTableSelectsByHostWithExceptions() {
        var table = ProceduralTable()
        table.add(lines: [
            #"x.com,twitter.com#?#div[data-testid="cellInnerDiv"]:has(span:has-text(/^Ad$/))"#,
            #"instagram.com,~business.instagram.com##article:has(span:has-text(Sponsored))"#,
            #"mobile.x.com#@?#div[data-testid="cellInnerDiv"]:has(span:has-text(/^Ad$/))"#,
        ], trusted: false)
        #expect(table.selectors(for: "x.com") == [#"div[data-testid="cellInnerDiv"]:has(span:has-text(/^Ad$/))"#])
        #expect(table.selectors(for: "mobile.x.com").isEmpty)
        #expect(table.selectors(for: "www.instagram.com") == ["article:has(span:has-text(Sponsored))"])
        #expect(table.selectors(for: "business.instagram.com").isEmpty)
        #expect(table.selectors(for: "example.org").isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/845"))
    func listCopiesKeepScriptletAndProceduralLines() {
        let text = """
        ! Title: fixture
        ||ads.example^
        youtube.com##+js(json-prune, adSlots)
        x.com#?#article:has-text(Promoted)
        !#if env_chromium
        www.youtube.com##+js(nano-stb, [native code], 17000, 0.001)
        !#endif
        !#if cap_html_filtering
        example.com##^script:has-text(ads)
        !#endif
        """
        let list = DesktopHidingRules.read(text, address: "fixture", fetched: Date(timeIntervalSince1970: 10))
        #expect(list.hidingRules.contains("youtube.com##+js(json-prune, adSlots)"))
        #expect(list.hidingRules.contains("x.com#?#article:has-text(Promoted)"))
        #expect(list.hidingRules.contains("www.youtube.com##+js(nano-stb, [native code], 17000, 0.001)"))
        #expect(!list.hidingRules.contains { $0.contains("##^") })
        #expect(CachedBlocklist(text: list.text) == list)
        // The stylesheet path ignores them.
        #expect(DesktopHidingRules(lines: list.hidingRules).css(host: "www.youtube.com").isEmpty)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/845"))
    func strictTurnsOnThePageListsAndOlderStrictSettingsGetThemOnce() throws {
        var settings = AppSettings()
        settings.adBlockingLevel = .strict
        #expect(DesktopFilterList.strictPageAddresses.allSatisfy(settings.customBlocklists.contains))
        settings.adBlockingLevel = .standard
        #expect(settings.customBlocklists.isEmpty)
        // Settings saved by 0.1.58 with Strict on: the page lists come in once, and a list switched off later stays off.
        let old = #"{"customBlocklists": ["https://easylist.to/easylist/easylist.txt", "https://easylist.to/easylist/easyprivacy.txt"]}"#
        var loaded = try JSONDecoder().decode(AppSettings.self, from: Data(old.utf8))
        #expect(loaded.adBlockingLevel == .strict)
        #expect(DesktopFilterList.strictPageAddresses.allSatisfy(loaded.customBlocklists.contains))
        loaded.setFilterList(DesktopFilterList.adguardBaseAddress, enabled: false)
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(loaded))
        #expect(!again.customBlocklists.contains(DesktopFilterList.adguardBaseAddress))
        #expect(again.adBlockingLevel == .strict)
        // Standard settings from before stay Standard.
        let standard = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(standard.customBlocklists.isEmpty)
    }
}
