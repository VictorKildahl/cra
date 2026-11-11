import CoreGraphics
import CraCore
import Foundation
import Testing

/// The iPhone app's decisions: the chrome's measurements from Arc Search, the rows under the
/// search field, and the tabs with their archive.
struct MobileChromeTests {
    /// Arc Search on an iPhone 15 Pro: the sheet's top edge is 258.6 pt down with the 291 pt
    /// keyboard up, and the field starts 16 pt below it.
    @Test func searchSheetSitsWhereArcSearchPutsIt() {
        #expect(MobileSearchSheet.height == 302)
        #expect(MobileSearchSheet.top(screenHeight: 852, keyboardHeight: 291) == 259)
    }

    /// The same phone's bar: 76 pt tall, pill 76 × 39 centred 44.5 pt above the bottom edge,
    /// round buttons 35 pt wide centred 41 pt from each side.
    @Test func bottomBarOnAnIPhone15Pro() {
        let frames = MobileBottomBar.frames(in: CGSize(width: 393, height: 852), safeBottom: 34)
        #expect(frames.bar == CGRect(x: 0, y: 776, width: 393, height: 76))
        #expect(frames.pill == CGRect(x: 158.5, y: 788, width: 76, height: 39))
        #expect(frames.pill.midY == 807.5)
        #expect(frames.tabs == CGRect(x: 23.5, y: 790, width: 35, height: 35))
        #expect(frames.menu == CGRect(x: 334.5, y: 790, width: 35, height: 35))
    }

    @Test func bottomBarWithoutAHomeIndicator() {
        let frames = MobileBottomBar.frames(in: CGSize(width: 375, height: 667), safeBottom: 0)
        #expect(frames.bar.height == 42)
        #expect(frames.pill.midX == 187.5)
    }
}

struct MobileSuggestionsTests {
    @Test func emptyFieldHasNoRows() {
        #expect(MobileSuggestions.rows(typed: "  ", completions: ["a"]).isEmpty)
    }

    /// Arc Search's list for "what to do": the typed text, then three completions with the typed
    /// part marked.
    @Test func typedTextComesFirstThenCompletions() {
        let rows = MobileSuggestions.rows(typed: "what to do", completions: [
            "what to do", "what to do nyc", "what to do new jersey", "what to do in nyc today", "what to do in paris",
        ])
        #expect(rows.map(\.text) == ["what to do", "what to do nyc", "what to do new jersey", "what to do in nyc today"])
        #expect(rows.map(\.typedPrefixLength) == [0, 10, 10, 10])
        #expect(rows.allSatisfy { $0.kind == .search })
    }

    @Test func completionThatDoesNotStartWithTheTypedTextIsAllNew() {
        let rows = MobileSuggestions.rows(typed: "nyc", completions: ["weather nyc", "NYC subway"])
        #expect(rows.map(\.typedPrefixLength) == [0, 0, 3])
    }

    @Test func anAddressOpensAndASearchSearches() {
        let rows = MobileSuggestions.rows(typed: "crabrowser.app", completions: ["crabrowser.app download"])
        #expect(rows[0].kind == .address)
        #expect(MobileSuggestions.destination(for: rows[0], engine: .google) == "https://crabrowser.app")
        #expect(MobileSuggestions.destination(for: rows[1], engine: .duckduckgo) == "https://duckduckgo.com/?q=crabrowser.app%20download")
        #expect(MobileSuggestions.destination(forTyped: " a b ", engine: .google) == "https://www.google.com/search?q=a%20b")
    }

    @Test func readsOpenSearchAnswers() {
        let google = Data(#")]}'["wh",["whatsapp","weather","whatsapp.com"],["","",""],[],{"google:suggesttype":["QUERY","QUERY","NAVIGATION"]}]"#.utf8)
        #expect(MobileSuggestions.completions(fromOpenSearch: google) == ["whatsapp", "weather"])
        let duck = Data(#"["wh",["what","who"]]"#.utf8)
        #expect(MobileSuggestions.completions(fromOpenSearch: duck) == ["what", "who"])
        #expect(MobileSuggestions.completions(fromOpenSearch: Data("<html>".utf8)).isEmpty)
    }
}

struct MobileTabsTests {
    static let start = Date(timeIntervalSince1970: 1_800_000_000)

    static func tab(_ name: String, hoursAgo: Double, incognito: Bool = false) -> MobileTab {
        MobileTab(url: "https://\(name).example", title: name, lastActive: start.addingTimeInterval(-hoursAgo * 3600),
                  isIncognito: incognito)
    }

    @Test func closingTheTabOnScreenShowsItsNeighbour() {
        var document = MobileTabsDocument()
        let tabs = ["a", "b", "c"].map { Self.tab($0, hoursAgo: 1) }
        tabs.forEach { document.open($0) }
        document.select(tabs[1].id, now: Self.start)
        document.close(tabs[1].id)
        #expect(document.selected == tabs[2].id)
        document.close(tabs[2].id)
        #expect(document.selected == tabs[0].id)
        document.close(tabs[0].id)
        #expect(document.selected == nil)
    }

    @Test func staleTabsGoToTheArchiveNewestFirst() {
        var document = MobileTabsDocument()
        let old = Self.tab("old", hoursAgo: 50), older = Self.tab("older", hoursAgo: 80), fresh = Self.tab("fresh", hoursAgo: 2)
        let secret = Self.tab("secret", hoursAgo: 60, incognito: true), onScreen = Self.tab("on-screen", hoursAgo: 90)
        [older, old, fresh, secret, onScreen].forEach { document.open($0) }
        #expect(document.archiveStale(after: .oneDay, now: Self.start) == 3)
        #expect(document.tabs.map(\.title) == ["fresh", "on-screen"])
        #expect(document.archived.map(\.title) == ["old", "older"])
        #expect(document.archiveStale(after: .never, now: Self.start.addingTimeInterval(1e7)) == 0)
    }

    @Test func restoringAnArchivedTabShowsIt() {
        var document = MobileTabsDocument()
        let old = Self.tab("old", hoursAgo: 50), current = Self.tab("current", hoursAgo: 0)
        [old, current].forEach { document.open($0) }
        document.archiveStale(after: .twelveHours, now: Self.start)
        document.restore(old.id, now: Self.start)
        #expect(document.archived.isEmpty)
        #expect(document.selectedTab?.title == "old")
        #expect(document.selectedTab?.lastActive == Self.start)
    }

    @Test func aSavedDocumentLoadsBack() throws {
        var document = MobileTabsDocument()
        document.open(Self.tab("a", hoursAgo: 1))
        let data = try JSONEncoder().encode(document)
        #expect(try JSONDecoder().decode(MobileTabsDocument.self, from: data) == document)
        // A file from before a field existed, and one whose selected tab is gone.
        let bare = Data(#"{"tabs":[{"id":"7B0D4A1E-3C5F-4E7A-9B1D-2F6A8C0E4D21","url":"https://a.example","lastActive":0}],"selected":"00000000-0000-0000-0000-000000000000"}"#.utf8)
        let loaded = try JSONDecoder().decode(MobileTabsDocument.self, from: bare)
        #expect(loaded.tabs.first?.displayTitle == "a.example")
        #expect(loaded.selected == nil)
    }
}

struct MobileSettingsTests {
    @Test func aMissingOrOlderFileIsTheDefaults() throws {
        let loaded = try JSONDecoder().decode(MobileSettings.self, from: Data(#"{"searchEngine":"duckduckgo","archiveAfter":"someday"}"#.utf8))
        #expect(loaded.searchEngine == .duckduckgo)
        #expect(loaded.archiveAfter == .oneDay)
        #expect(loaded.opensKeyboardOnLaunch && loaded.blockAds && loaded.blockTrackers && loaded.blockCookieBanners)
        let saved = try JSONEncoder().encode(loaded)
        #expect(try JSONDecoder().decode(MobileSettings.self, from: saved) == loaded)
    }

    @Test func aSiteKeepsItsOwnBlockingUntilItMatchesTheDefaultsAgain() {
        var settings = MobileSettings()
        settings.setBlocking({ $0.blockAds = false }, for: "www.Example.com")
        #expect(settings.blocking(for: "example.com").ads == false)
        #expect(settings.blocking(for: "example.com").trackers == true)
        #expect(settings.blocking(for: "other.example").ads == true)
        settings.setBlocking({ $0.blockAds = true }, for: "example.com")
        #expect(settings.siteExceptions.isEmpty)
    }
}
