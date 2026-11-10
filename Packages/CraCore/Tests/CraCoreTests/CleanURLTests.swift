import Foundation
import CraCore
import Testing

/// Arc's Copy URL (⇧⌘C) copies "the current tab's URL without trackers" (Help ▸ Essential
/// Keyboard Shortcuts, Arc 1.172); Copy URL as Quote (⌃⇧⌘C) copies the selection with a link to it.
struct CleanURLTests {
    @Test func dropsTrackingParameters() {
        #expect(CleanURL.withoutTrackers("https://example.com/a?utm_source=x&utm_medium=y&id=4&fbclid=abc")
            == "https://example.com/a?id=4")
        #expect(CleanURL.withoutTrackers("https://shop.example/p?gclid=1&msclkid=2&mc_eid=3&_hsenc=4&igshid=5")
            == "https://shop.example/p")
    }

    @Test func keepsTheFragmentAndOrder() {
        #expect(CleanURL.withoutTrackers("https://example.com/?b=2&utm_campaign=z&a=1#top")
            == "https://example.com/?b=2&a=1#top")
    }

    @Test(arguments: ["https://example.com/", "https://example.com/?q=utm_source", "https://www.google.com/search?q=cra+browser",
                      "file:///Users/me/a.html", "chrome://settings", "not a url", "https://example.com/?utm=1"])
    func leavesEverythingElseAlone(url: String) {
        #expect(CleanURL.withoutTrackers(url) == url)
    }

    @Test func quotesTheSelectionWithALinkToIt() {
        #expect(CleanURL.quote("Hello, world", url: "https://example.com/post?utm_source=x")
            == "“Hello, world”\nhttps://example.com/post#:~:text=Hello%2C%20world")
    }

    @Test func longQuotesLinkByTheirEnds() {
        let text = "one two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen"
        #expect(CleanURL.quote(text, url: "https://example.com/#old")
            == "“\(text)”\nhttps://example.com/#:~:text=one%20two%20three%20four%20five,eleven%20twelve%20thirteen%20fourteen%20fifteen")
    }

    @Test func squeezesWhitespaceAndEscapesFragmentSyntax() {
        #expect(CleanURL.quote("  a-b &\n c  ", url: "https://example.com/")
            == "“a-b & c”\nhttps://example.com/#:~:text=a%2Db%20%26%20c")
    }

    @Test func nothingSelectedIsNoQuote() {
        #expect(CleanURL.quote(" \n ", url: "https://example.com/") == nil)
    }
}

/// Arc's ⇧⌘C with several tabs picked in the sidebar copies every picked tab's link, one per line
/// ("Copied item links": "the links for the multi-selection have been copied", Arc 1.172).
struct CopiedLinksTests {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/322"))
    func severalPicksCopyEveryPickInSidebarOrder() {
        #expect(CleanURL.tabsToCopy(picked: [c, a], listed: [a, b, c, d], open: b) == [a, c])
        #expect(CleanURL.links(["https://a.example/?utm_source=x", "https://c.example/"])
            == "https://a.example/\nhttps://c.example/")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/322"))
    func noPicksCopyTheOpenTab() {
        #expect(CleanURL.tabsToCopy(picked: [], listed: [a, b], open: b) == [b])
        #expect(CleanURL.tabsToCopy(picked: [], listed: [a, b], open: nil) == [])
        #expect(CleanURL.links(["https://b.example/?fbclid=1"]) == "https://b.example/")
    }

    /// A pick hidden since (its folder closed) still counts, as ⌘W still closes it; it goes after
    /// the listed picks.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/322"))
    func picksNoLongerListedFollowTheListedOnes() {
        #expect(CleanURL.tabsToCopy(picked: [d, b], listed: [a, b, c], open: a) == [b, d])
    }
}
