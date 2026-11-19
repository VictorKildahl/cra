import CraCore
import Foundation
import Testing
#if canImport(WebKit)
import WebKit
#endif

/// Filter lists in Adblock Plus / uBlock Origin syntax as WebKit content rules (#570): the iPhone
/// blocked by domain only, and the pop-up ads on manga sites come from a loader whose path stays
/// while its domain changes every few days.
struct FilterListTests {
    static let issue = "https://github.com/VictorKildahl/cra/issues/570"

    static func repoFile(_ path: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
    }

    static func bundled() throws -> FilterList { FilterList(text: try repoFile("resources/blocklist/filters.txt")) }

    /// The overlays on ww7.readopm.com and ww13.readonepiece.com ("Anna has sent (7) photos", "The
    /// file is ready to download") as the report traced them: aqle3.com/btag.min.js, pubadx.one,
    /// and zone scripts from rotating hosts. Cra's own filters stop those, and the same loader and
    /// zone scripts from a domain no list has yet; the sites' own files and ordinary paths load.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func crasFiltersStopTheMangaSitesAdsOnAnyDomain() throws {
        let filters = try Self.bundled()
        let opm = "ww7.readopm.com", onePiece = "ww13.readonepiece.com"
        #expect(filters.blocks(url: "https://aqle3.com/btag.min.js", onPage: opm))
        #expect(filters.blocks(url: "https://pubadx.one/js/load.js", onPage: opm))
        #expect(filters.blocks(url: "https://chagnougroalry.net/5/9357427/", onPage: onePiece))
        #expect(filters.blocks(url: "https://sootoarathus.net/web/files/300x250/19.png", onPage: onePiece))
        // The same network from domains no list has.
        #expect(filters.blocks(url: "https://qwertyuiopas.com/btag.min.js", onPage: opm))
        #expect(filters.blocks(url: "https://zxcvbnmlkj.net/5/9357427", onPage: onePiece))
        #expect(filters.blocks(url: "https://zxcvbnmlkj.com/400/1234567?v=2", onPage: opm))
        #expect(filters.blocks(url: "https://glookockish.com/401/12345678", onPage: opm))
        #expect(filters.blocks(url: "https://sheegiwoqx.com/tag.min.js", onPage: opm))
        #expect(filters.blocks(url: "https://alwingulla.com/88/tag.min.js", onPage: opm))
        #expect(filters.blocks(url: "https://cdn.adnet.example/pfe/current/tag.min.js?z=123", onPage: opm))
        // Not the site's own files, nor paths that only look alike.
        #expect(!filters.blocks(url: "https://ww7.readopm.com/btag.min.js", onPage: opm))
        #expect(!filters.blocks(url: "https://ww7.readopm.com/manga/5/1234567", onPage: opm))
        #expect(!filters.blocks(url: "https://images.example.com/5/1234567.jpg", onPage: opm))
        #expect(!filters.blocks(url: "https://cdn.jsdelivr.net/npm/widget/tag.min.js", onPage: opm))
        #expect(!filters.blocks(url: "https://example.com/5/12/photo.jpg", onPage: opm))
        #expect(!filters.blocks(url: "https://www.monetag.com/", onPage: "monetag.com"))
        #expect(filters.skippedRules == 0)
    }

    /// The iPhone's Block Ads list is Cra's ad domains followed by these filters, so the sites'
    /// switch (and "Reload without ad blockers") covers both, and the count in the page menu
    /// counts what the filters stopped.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func blockAdsCarriesTheFiltersAndCountsWhatTheyStop() throws {
        let filters = FilterList(text: "/btag.min.js$script,third-party")
        let json = MobileBlocklist.adsRulesJSON(domains: ["doubleclick.net"], filters: filters)
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        #expect(rules.count == 2)
        let trigger = try #require(rules.last?["trigger"] as? [String: Any])
        #expect(trigger["resource-type"] as? [String] == ["script"])
        #expect(trigger["load-type"] as? [String] == ["third-party"])
        #expect((rules.last?["action"] as? [String: String])?["type"] == "block")

        let list = MobileBlocklist(text: "doubleclick.net\nanalytics.example.org\n")
        var options = MobileSiteOptions()
        #expect(list.stops(url: "https://zzqqrrtt.com/btag.min.js", onPage: "ww7.readopm.com", with: options, filters: filters))
        #expect(list.stops(url: "https://g.doubleclick.net/x", onPage: "site.example", with: options, filters: filters))
        #expect(!list.stops(url: "https://site.example/app.js", onPage: "site.example", with: options, filters: filters))
        options.blockAds = false
        #expect(!list.stops(url: "https://zzqqrrtt.com/btag.min.js", onPage: "ww7.readopm.com", with: options, filters: filters))
        #expect(list.stops(url: "https://eu.analytics.example.org/c", onPage: "site.example", with: options, filters: filters))
    }

    /// Network rules: anchors, wildcards, separators, options and exceptions mean what they mean in
    /// Adblock Plus, and what WebKit can't do is counted, not guessed at.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func networkRulesMatchAsInAdblockPlus() {
        let list = FilterList(text: """
        [Adblock Plus 2.0]
        ! Title: Test
        ||ads.example^
        /banner/*/ad.$image,third-party
        |https://track.example/pixel
        ||cdn.example/ads^
        @@||ads.example/allowed^
        ||only.example/x.js$script,domain=a.example|b.example
        ||pop.example^$popup
        ||frames.example^$subdocument,1p
        /^https:\\/\\/[a-z]{3}\\.(com|net)\\/\\d{2,3}\\/x\\.js/$script
        ||mixed.example/x.js$domain=news.example|~sport.news.example
        ||thing.example^$redirect=noop.js
        /(?=lookahead)/
        ||caf\u{e9}.example^
        /^https:\\/\\/bare\\.example\\/y\\.js$/
        /^https:\\/\\/hdr\\.example\\/y\\.js$/$script,header=link:/x\\.re\\/>;rel=preconnect/
        /a$b/
        """)
        // A regex's options may hold "/" and "$" themselves; "$" inside a regex WebKit can't take.
        #expect(list.skippedRules == 6)
        #expect(list.blocks(url: "https://bare.example/y.js", onPage: "site.example"))
        #expect(!list.blocks(url: "https://hdr.example/y.js", onPage: "site.example"))
        #expect(list.blocks(url: "https://sub.ads.example/a.js", onPage: "site.example"))
        #expect(list.blocks(url: "https://ads.example:8443/a.js", onPage: "site.example"))
        #expect(!list.blocks(url: "https://ads.example.org/", onPage: "site.example"))
        #expect(!list.blocks(url: "https://notads.example/", onPage: "site.example"))
        #expect(!list.blocks(url: "https://ads.example/allowed/1.js", onPage: "site.example"))
        #expect(list.blocks(url: "https://ads.example/allowedx", onPage: "site.example"))
        #expect(list.blocks(url: "https://img.example/banner/12/ad.png", onPage: "site.example"))
        #expect(!list.blocks(url: "https://img.example/banner/12/ad.png", onPage: "img.example"))
        #expect(list.blocks(url: "https://track.example/pixel?x=1", onPage: "site.example"))
        #expect(!list.blocks(url: "https://other.example/?u=https://track.example/pixel", onPage: "site.example"))
        #expect(list.blocks(url: "https://cdn.example/ads", onPage: "site.example"))
        #expect(list.blocks(url: "https://cdn.example/ads/1.js", onPage: "site.example"))
        #expect(!list.blocks(url: "https://cdn.example/adserver.js", onPage: "site.example"))
        #expect(list.blocks(url: "https://only.example/x.js", onPage: "a.example"))
        #expect(list.blocks(url: "https://only.example/x.js", onPage: "www.b.example"))
        #expect(!list.blocks(url: "https://only.example/x.js", onPage: "c.example"))
        #expect(list.blocks(url: "https://abc.com/12/x.js", onPage: "site.example"))
        #expect(list.blocks(url: "https://abc.net/123/x.js", onPage: "site.example"))
        #expect(!list.blocks(url: "https://abcd.com/12/x.js", onPage: "site.example"))
        #expect(!list.blocks(url: "https://abc.org/12/x.js", onPage: "site.example"))
        #expect(!list.blocks(url: "https://mixed.example/x.js", onPage: "news.example"))
    }

    /// What WebKit gets: its own trigger fields, its regex subset only (no alternation, counted
    /// repeats or \d), and exceptions after everything they undo.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func rulesAreWebKitsSubset() throws {
        let list = FilterList(text: """
        @@||ads.example/allowed^
        ||ads.example^
        ||pop.example^$popup
        ||frames.example^$subdocument,1p
        /^https:\\/\\/[a-z]{3}\\.(com|net)\\/\\d{2,3}\\/x\\.js/$script,match-case
        ##.ad-banner
        """)
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(("[" + list.contentRulesJSON() + "]").utf8)) as? [[String: Any]])
        let triggers = rules.compactMap { $0["trigger"] as? [String: Any] }
        let actions = rules.compactMap { ($0["action"] as? [String: String])?["type"] }
        // "/allowed^" ends in a separator or the address's end: two rules, both after the rest.
        #expect(Array(actions.suffix(2)) == ["ignore-previous-rules", "ignore-previous-rules"])
        #expect(actions.filter { $0 == "ignore-previous-rules" }.count == 2)
        #expect(actions.contains("css-display-none"))
        let filters = triggers.compactMap { $0["url-filter"] as? String }
        #expect(filters.count == rules.count)
        for filter in filters {
            let ascii = filter.allSatisfy { $0.isASCII }
            #expect(ascii, "\(filter)")
            #expect(!filter.contains("{") && !filter.contains("|") && !filter.contains("\\d") && !filter.contains("(?"), "\(filter)")
        }
        // The regex rule, one per alternative, case-sensitive as asked.
        let regex = triggers.filter { ($0["url-filter"] as? String)?.contains("x\\.js") == true }
        #expect(regex.count == 2)
        #expect(regex.allSatisfy { $0["url-filter-is-case-sensitive"] as? Bool == true })
        let popup = try #require(triggers.first { ($0["url-filter"] as? String)?.contains("pop\\.example") == true })
        #expect(popup["resource-type"] as? [String] == ["popup"])
        let frames = try #require(triggers.first { ($0["url-filter"] as? String)?.contains("frames\\.example") == true })
        #expect(frames["resource-type"] as? [String] == ["document"])
        #expect(frames["load-context"] as? [String] == ["child-frame"])
        #expect(frames["load-type"] as? [String] == ["first-party"])
    }

    /// Element hiding (Cra already hides cookie banners this way): generic rules, rules for some
    /// sites, exceptions that take a generic rule off some sites or everywhere. uBlock's procedural
    /// and scriptlet rules need a script WebKit's rules can't run, and are counted.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func hidingRulesBecomeDisplayNone() throws {
        let list = FilterList(text: """
        ##.ad-banner
        ##.sponsored
        ##.overlay-ad
        example.com,news.example##.promo
        ~safe.example##.popup-ad
        example.com#@#.sponsored
        #@#.ad-banner
        example.com,~x.example.com##.mixed
        ##.x:has-text(Buy)
        example.com##+js(nowoif)
        example.com#?#.y:-abp-has(.z)
        """)
        #expect(list.skippedRules == 4)
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(("[" + list.contentRulesJSON() + "]").utf8)) as? [[String: Any]])
        func rule(hiding selector: String) -> [String: Any]? {
            rules.first { (($0["action"] as? [String: String])?["selector"])?.contains(selector) == true }
        }
        #expect(rule(hiding: ".ad-banner") == nil)
        let promo = try #require(rule(hiding: ".promo")?["trigger"] as? [String: Any])
        #expect(promo["if-domain"] as? [String] == ["*example.com", "*news.example"])
        let sponsored = try #require(rule(hiding: ".sponsored")?["trigger"] as? [String: Any])
        #expect(sponsored["unless-domain"] as? [String] == ["*example.com"])
        let popup = try #require(rule(hiding: ".popup-ad")?["trigger"] as? [String: Any])
        #expect(popup["unless-domain"] as? [String] == ["*safe.example"])
        let overlay = try #require(rule(hiding: ".overlay-ad")?["trigger"] as? [String: Any])
        #expect(overlay["url-filter"] as? String == ".*")
        #expect(overlay["if-domain"] == nil && overlay["unless-domain"] == nil)
        #expect(rule(hiding: ".mixed") == nil && rule(hiding: "has-text") == nil)
    }

    #if canImport(WebKit)
    /// The rule list the iPhone builds for Block Ads, Cra's ad domains with the filters, compiles in
    /// WebKit's own compiler and stays under its 150,000 rules a list; so do the converter's forms.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/570")) func blockAdsListCompilesInWebKit() async throws {
        let domains = MobileBlocklist(text: try Self.repoFile("resources/blocklist/domains.txt")).domains(of: .ads)
        let ads = MobileBlocklist.adsRulesJSON(domains: domains, filters: try Self.bundled())
        let count = try #require(try JSONSerialization.jsonObject(with: Data(ads.utf8)) as? [Any]).count
        #expect(count > domains.count && count < MobileBlocklist.maxRulesPerList)

        let forms = FilterList(text: """
        ||ads.example^
        /banner/*/ad.$image,third-party
        |https://track.example/pixel
        ||cdn.example/ads^
        @@||ads.example/allowed^
        ||only.example/x.js$script,domain=a.example|b.example
        ||pop.example^$popup
        ||frames.example^$subdocument,1p
        ||xhr.example^$xmlhttprequest,websocket,ping,other,font,media,stylesheet
        /^https:\\/\\/[a-z]{3}\\.(com|net)\\/\\d{2,3}\\/x\\.js/$script,match-case
        @@||allowed-site.example^$document
        ##.ad-banner
        example.com##.promo
        ~safe.example##.popup-ad
        """)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-570-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let made: WKContentRuleListStore? = WKContentRuleListStore(url: folder)
        let store = try #require(made)
        for (name, json) in [("ads", ads), ("forms", "[" + forms.contentRulesJSON() + "]")] {
            let compiled: Bool = await withCheckedContinuation { done in
                DispatchQueue.main.async {
                    store.compileContentRuleList(forIdentifier: "cra-test-\(name)", encodedContentRuleList: json) { list, error in
                        if let error { print("compile \(name): \(error)") }
                        done.resume(returning: list != nil)
                    }
                }
            }
            #expect(compiled, "\(name) compiles")
        }
    }
    #endif
}
