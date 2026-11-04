import CraCore
import Foundation
import Testing

/// Arc's tidy titles (per-site rules, always on) and Tidy Tab Titles (the model's names on pin).
struct TidyTitleRulesTests {
    let rules = TidyTitleRules.arc

    @Test func arcsRulesLoad() {
        #expect(rules.sites.count == 52)
        #expect(rules.site(forHost: "en.wikipedia.org")?.siteName == "Wikipedia")
    }

    @Test func titlesSeenInArc() {
        // Arc 1.171's sidebar, 4 Nov 2026.
        #expect(rules.tidy("Jupiter - Wikipedia", url: "https://en.wikipedia.org/wiki/Jupiter") == "Jupiter")
        #expect(rules.tidy("Y Combinator | Hacker News", url: "https://news.ycombinator.com/item?id=1") == "Y Combinator")
        // No rules for the BBC: the page's own title.
        #expect(rules.tidy("Climate - BBC News", url: "https://www.bbc.com/news/topics/x") == "Climate - BBC News")
    }

    @Test func pathAndFragmentRules() {
        #expect(rules.tidy("Wikipedia, the free encyclopedia", url: "https://en.wikipedia.org/wiki/Main_Page") == "Wikipedia")
        #expect(rules.tidy("Inbox (3) - me@example.com - Gmail", url: "https://mail.google.com/mail/u/0/#inbox") == "Gmail")
        #expect(rules.tidy("Starred - me@example.com - Gmail", url: "https://mail.google.com/mail/u/0/#starred") == "Starred")
        #expect(rules.tidy("Receipts - me@example.com - Gmail", url: "https://mail.google.com/mail/u/0/#label/Receipts") == "Receipts")
        #expect(rules.tidy("Amazon.com", url: "https://www.amazon.com/") == "Amazon")
    }

    @Test func removingPatternsAndHosts() {
        // removingPatterns: LinkedIn's counter and suffix both go.
        #expect(rules.tidy("(3) Jane Doe | LinkedIn", url: "https://www.linkedin.com/in/jane") == "Jane Doe")
        // www. is ignored, other subdomains aren't the site.
        #expect(rules.site(forHost: "WWW.Amazon.com") != nil)
        #expect(rules.site(forHost: "music.youtube.com") == nil)
        #expect(rules.tidy("x", url: "not a url") == "x")
        #expect(rules.tidy("", url: "https://en.wikipedia.org/wiki/X") == "")
    }

    @Test func aRuleLeavingNothingKeepsTheTitle() throws {
        let json = #"{"a.com": {"siteName": "A", "rules": [{"title": {"removingPattern": ".*"}}]}}"#
        let r = TidyTitleRules(sites: try JSONDecoder().decode([String: TidyTitleRules.Site].self, from: Data(json.utf8)))
        #expect(r.tidy("Anything", url: "https://a.com/") == "Anything")
    }
}

struct TidyTitlesTests {
    @Test func promptGivesExamplesTitleAndSite() {
        let p = TidyTitles.prompt(title: "Foundation Models | Apple Developer Documentation", url: "https://developer.apple.com/documentation/foundationmodels")
        #expect(p.hasPrefix("Examples:\n\"IT Career Paths - IT General - Confluence\" (atlassian.net) → IT Career Paths"))
        #expect(p.hasSuffix("Rename this tab: \"Foundation Models | Apple Developer Documentation\" (developer.apple.com)"))
        #expect(TidyTitles.prompt(title: "x", url: "https://www.bbc.com/").hasSuffix("(bbc.com)"))
    }

    @Test func cleanKeepsShorterNames() {
        #expect(TidyTitles.clean("\"Climate News\"", shown: "Climate - BBC News") == "Climate News")
        #expect(TidyTitles.clean("  Foundation   Models.\nextra", shown: "Foundation Models | Apple Developer Documentation") == "Foundation Models")
        // Nothing to gain: empty, the same, or no shorter.
        #expect(TidyTitles.clean("", shown: "Jupiter") == nil)
        #expect(TidyTitles.clean("jupiter", shown: "Jupiter") == nil)
        #expect(TidyTitles.clean("Jupiter the planet", shown: "Jupiter") == nil)
        #expect(TidyTitles.clean(String(repeating: "a", count: 41), shown: String(repeating: "b", count: 90)) == nil)
    }
}
