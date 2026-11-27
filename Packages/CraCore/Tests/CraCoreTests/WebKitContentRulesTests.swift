import Foundation
import Testing
@testable import CraCore

/// Ad blocking in WebKit pages: the network rules Chromium pages get, as WebKit content-blocker lists. The patterns
/// are checked with NSRegularExpression, whose syntax WebKit's url-filter is a subset of.
@Suite struct WebKitContentRulesTests {
    private func rules(_ lines: [String], domains: [String] = []) -> [DesktopNetworkRules.Rule] {
        DesktopNetworkRules.compile(domains: domains, lines: lines)
    }

    private func decode(_ json: String) throws -> [[String: Any]] {
        try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
    }

    private func matches(_ pattern: String, _ url: String) -> Bool {
        let regex = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        return regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
    }

    private func trigger(_ rule: [String: Any]) -> [String: Any] { rule["trigger"] as? [String: Any] ?? [:] }
    private func action(_ rule: [String: Any]) -> String { (rule["action"] as? [String: Any])?["type"] as? String ?? "" }

    @Test func aBlockedHostBlocksItAndItsSubdomainsOnly() {
        let pattern = WebKitContentRules.hostPattern("ads.example.com")
        #expect(matches(pattern, "https://ads.example.com/x.js"))
        #expect(matches(pattern, "https://cdn.ads.example.com/x.js"))
        #expect(matches(pattern, "http://ads.example.com:8080/x.js"))
        #expect(!matches(pattern, "https://ads.example.company/x.js"))
        #expect(!matches(pattern, "https://badads.example.com/x.js"))
        #expect(!matches(pattern, "https://site.example/?u=https://ads.example.com/"))
    }

    @Test func addressPatternsReadAsAdblockPlusMeansThem() throws {
        let anchored = try #require(WebKitContentRules.regex("||cdn.example.org/promotions/*"))
        #expect(matches(anchored, "https://cdn.example.org/promotions/a.js"))
        #expect(matches(anchored, "https://eu.cdn.example.org/promotions/a.js"))
        #expect(!matches(anchored, "https://cdn.example.org/news/promotions/a.js"))
        // `^` is a separator or the end of the address, never part of a name.
        let separated = try #require(WebKitContentRules.regex("/banner/ad^"))
        #expect(matches(separated, "https://site.example/banner/ad"))
        #expect(matches(separated, "https://site.example/banner/ad?x=1"))
        #expect(!matches(separated, "https://site.example/banner/ads.js"))
        let middle = try #require(WebKitContentRules.regex("||track.example^*/pixel"))
        #expect(matches(middle, "https://track.example/v1/pixel"))
        #expect(!matches(middle, "https://track.examples/v1/pixel"))
        let start = try #require(WebKitContentRules.regex("|https://ads."))
        #expect(matches(start, "https://ads.example/"))
        #expect(!matches(start, "https://site.example/?r=https://ads.example/"))
        let end = try #require(WebKitContentRules.regex(".gif|"))
        #expect(matches(end, "https://site.example/a.gif"))
        #expect(!matches(end, "https://site.example/a.gif?x"))
        // Regex characters in a pattern are themselves.
        let literal = try #require(WebKitContentRules.regex("/ad(1)+[x]?.js"))
        #expect(matches(literal, "https://site.example/ad(1)+[x]?.js"))
        #expect(!matches(literal, "https://site.example/ad1.js"))
        // Wildcards at the ends say nothing; WebKit's filter isn't anchored.
        #expect(WebKitContentRules.regex("*/ads/*") == "/ads/")
        #expect(WebKitContentRules.regex("*") == ".*")
    }

    @Test func requestTypesPartiesAndSitesCarryOver() throws {
        let lines = ["||assets.example/promo.png$xmlhttprequest,domain=news.example|~sports.news.example",
                     "/beacon.js$script,third-party,domain=~shop.example",
                     "@@||assets.example/promo.png$xmlhttprequest,domain=reader.example",
                     "||ads.example^$image,stylesheet,subdocument,first-party,match-case"]
        let all = rules(lines).flatMap(WebKitContentRules.convert)
        // A block naming sites with a hole in them can't be said in WebKit, so it's left out.
        #expect(!all.contains { (trigger($0)["url-filter"] as? String)?.contains("promo") == true && action($0) == "block" })
        let beacon = try #require(all.first { (trigger($0)["url-filter"] as? String)?.contains("beacon") == true })
        #expect(trigger(beacon)["resource-type"] as? [String] == ["script"])
        #expect(trigger(beacon)["load-type"] as? [String] == ["third-party"])
        #expect(trigger(beacon)["unless-domain"] as? [String] == ["*shop.example"])
        let allow = try #require(all.first { action($0) == "ignore-previous-rules" })
        #expect(trigger(allow)["resource-type"] as? [String] == ["fetch"])
        #expect(trigger(allow)["if-domain"] as? [String] == ["*reader.example"])
        let typed = try #require(all.first { (trigger($0)["url-filter"] as? String) == WebKitContentRules.hostPattern("ads.example") })
        #expect(trigger(typed)["resource-type"] as? [String] == ["document", "image", "style-sheet"])
        #expect(trigger(typed)["load-type"] as? [String] == ["first-party"])
        #expect(trigger(typed)["url-filter-is-case-sensitive"] as? Bool == true)
    }

    @Test func blockedDomainsAreThirdPartyLoadsAndTheTabsOwnPageAlwaysLoads() throws {
        let lists = WebKitContentRules.lists(from: rules([], domains: ["ads.example", "tracker.example"]))
        #expect(lists.count == 1)
        let list = try decode(lists[0])
        let blocks = list.filter { action($0) == "block" }
        #expect(blocks.map { trigger($0)["url-filter"] as? String } == ["ads.example", "tracker.example"].map(WebKitContentRules.hostPattern))
        #expect(blocks.allSatisfy { trigger($0)["load-type"] as? [String] == ["third-party"] })
        // Chromium never blocks `main_frame`: the last rules let a tab's page and a popup's page load.
        let tail = list.suffix(2).map(trigger)
        #expect(tail[0]["resource-type"] as? [String] == ["document"] && tail[0]["load-context"] as? [String] == ["top-frame"])
        #expect(tail[1]["resource-type"] as? [String] == ["popup"])
        #expect(list.suffix(2).allSatisfy { action($0) == "ignore-previous-rules" })
    }

    @Test func exceptionsComeAfterTheBlocksTheyUndoAndImportantBlocksAfterThem() throws {
        let lines = ["@@||cdn.example/ok.js$important", "||cdn.example^$important", "@@||cdn.example/ads.js", "||cdn.example/ads.js",
                     "@@||trusted.example^$document"]
        let list = try decode(try #require(WebKitContentRules.lists(from: rules(lines)).first))
        let order = list.dropLast(2).map { (action($0), trigger($0)["url-filter"] as? String ?? "") }
        #expect(order.map(\.0) == ["block", "ignore-previous-rules", "ignore-previous-rules", "block", "ignore-previous-rules"])
        #expect(order[0].1.contains("ads"))
        #expect(order[3].1 == WebKitContentRules.hostPattern("cdn.example"))
        #expect(order[4].1.contains("ok"))
        // `$document`: every load on a page of the site.
        let document = try #require(list.first { trigger($0)["if-domain"] as? [String] == ["*trusted.example"] })
        #expect(action(document) == "ignore-previous-rules" && trigger(document)["url-filter"] as? String == ".*")
    }

    @Test func aBigSelectionSplitsAndEachListKeepsEveryException() throws {
        let domains = (0..<25).map { "ads\($0).example" }
        let lists = WebKitContentRules.lists(from: rules(["@@||ads3.example/ok.js", "||ads.example/x$important"], domains: domains), maxRules: 10)
        // Each list: 6 blocks, then the exception, the important block and the two page rules.
        #expect(lists.count == 5)
        var blocked = Set<String>()
        for json in lists {
            let list = try decode(json)
            #expect(list.count <= 10)
            #expect(list.suffix(4).map(action) == ["ignore-previous-rules", "block", "ignore-previous-rules", "ignore-previous-rules"])
            blocked.formUnion(list.dropLast(4).compactMap { trigger($0)["url-filter"] as? String })
        }
        #expect(blocked == Set(domains.map(WebKitContentRules.hostPattern)))
    }

    @Test func nothingToBlockIsNoList() {
        #expect(WebKitContentRules.lists(from: []).isEmpty)
        #expect(WebKitContentRules.lists(from: rules(["@@||cdn.example/ok.js"])).isEmpty)
    }
}
