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

    /// Arc Search's engines, in its menu's order; the two the Mac app lacks have their own addresses.
    @Test func searchEnginesAreArcSearchs() {
        #expect(MobileSearchEngine.allCases.map(\.label) == ["Google", "Bing", "DuckDuckGo", "Ecosia", "Perplexity", "Kagi"])
        #expect(MobileSearchEngine.ecosia.searchURL("a b&c") == "https://www.ecosia.org/search?q=a%20b%26c")
        #expect(MobileSearchEngine.perplexity.searchURL("a b") == "https://www.perplexity.ai/search?q=a%20b")
        #expect(MobileSearchEngine.perplexity.suggestURL("a") == nil)
        #expect(MobileSearchEngine.kagi.searchURL("a") == SearchEngine.kagi.searchURL("a"))
        #expect(MobileSearchEngine.ecosia.suggestURL("a b")?.absoluteString == "https://ac.ecosia.org/autocomplete?q=a%20b&type=list")
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
        #expect(document.archiveStale(after: .thirtyDays, now: Self.start) == 0)
        #expect(MobileArchiveAfter.allCases.map(\.label) == ["12 hours", "1 day", "3 days", "7 days", "30 days"])
        #expect(MobileArchiveAfter.oneDay.settingValue == "After 1 day")
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

    @Test func aClosedTabGoesToTheArchiveAndAnIncognitoOneDoesNot() {
        var document = MobileTabsDocument()
        let plain = Self.tab("plain", hoursAgo: 1), secret = Self.tab("secret", hoursAgo: 1, incognito: true)
        [plain, secret].forEach { document.open($0) }
        #expect(document.exportText == "plain\nhttps://plain.example")
        document.archive(secret.id)
        document.archive(plain.id)
        #expect(document.tabs.isEmpty && document.archived.map(\.title) == ["plain"])
        document.removeArchived([plain.id])
        #expect(document.archived.isEmpty)
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
        #expect(loaded.opensKeyboardOnLaunch && loaded.siteDefaults == MobileSiteOptions())
        #expect(loaded.siteDefaults.blockAds && loaded.siteDefaults.blockTrackers && loaded.siteDefaults.blockCookieBanners)
        #expect(loaded.siteDefaults.swipeToNavigate == .fromAnywhere && loaded.openAppLinksIn == .nativeApp)
        let saved = try JSONEncoder().encode(loaded)
        #expect(try JSONDecoder().decode(MobileSettings.self, from: saved) == loaded)
    }

    @Test func aSiteKeepsItsOwnChoicesUntilTheyMatchTheGlobalOnesAgain() {
        var settings = MobileSettings()
        var site = settings.options(for: "www.Example.com")
        site.blockAds = false
        site.swipeToNavigate = .fromEdges
        settings.setOptions(site, for: "www.Example.com")
        #expect(settings.options(for: "example.com").blockAds == false)
        #expect(settings.options(for: "example.com").swipeToNavigate == .fromEdges)
        #expect(settings.options(for: "example.com").blockTrackers == true)
        #expect(settings.options(for: "other.example").blockAds == true)
        // A global change reaches the site where it made no choice of its own.
        settings.siteDefaults.collapseBottomBar = false
        #expect(settings.options(for: "example.com").collapseBottomBar == false)
        settings.setOptions(settings.siteDefaults, for: "example.com")
        #expect(settings.siteOverrides.isEmpty)
    }
}

struct MobileArchiveTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Copenhagen")!
        return calendar
    }()
    /// Wednesday 11 November 2026, 21:00 in Copenhagen.
    static let now = Date(timeIntervalSince1970: 1_794_427_200)

    static func tab(_ title: String, hoursAgo: Double) -> MobileTab {
        MobileTab(url: "https://\(title.lowercased()).example/page", title: title, lastActive: now.addingTimeInterval(-hoursAgo * 3600))
    }

    /// Arc Search's Archive: "TODAY", "YESTERDAY", then each older day by its date.
    @Test func archiveIsGroupedByDayNewestFirst() {
        let tabs = [Self.tab("Morning", hoursAgo: 10), Self.tab("Evening", hoursAgo: 1), Self.tab("Tuesday", hoursAgo: 30),
                    Self.tab("LastWeek", hoursAgo: 24 * 6)]
        let sections = MobileArchive.sections(tabs, matching: "", now: Self.now, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(sections.map(\.title) == ["TODAY", "YESTERDAY", "THURSDAY, NOVEMBER 5"])
        #expect(sections[0].tabs.map(\.title) == ["Evening", "Morning"])
    }

    @Test func searchMatchesTitleAndAddress() {
        let tabs = [Self.tab("Pizza", hoursAgo: 1), Self.tab("Pasta", hoursAgo: 2)]
        let byTitle = MobileArchive.sections(tabs, matching: "piz", now: Self.now, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(byTitle.flatMap(\.tabs).map(\.title) == ["Pizza"])
        let byAddress = MobileArchive.sections(tabs, matching: "PASTA.example", now: Self.now, calendar: Self.calendar, locale: Locale(identifier: "en_US"))
        #expect(byAddress.flatMap(\.tabs).map(\.title) == ["Pasta"])
    }

    @Test func aRowShowsTheAddressWithoutItsScheme() {
        #expect(MobileArchive.subtitle(for: Self.tab("Pizza", hoursAgo: 1)) == "pizza.example/page")
    }
}

struct MobileTabCarouselTests {
    static let phone = CGSize(width: 393, height: 852)

    /// Arc Search's row at rest on an iPhone 15 Pro.
    @Test func cardsSitWhereArcSearchPutsThem() {
        let focus = MobileTabCarousel.placement(relative: 0, in: Self.phone)
        #expect(focus.frame == CGRect(x: 393 * 0.2112, y: 852 * 0.5147 - 277.5, width: 273, height: 555))
        #expect(abs(focus.frame.minX - 83) < 0.1 && abs(focus.frame.minY - 161) < 0.1)
        #expect(focus.scale == 1 && focus.dim == 0)
        let next = MobileTabCarousel.placement(relative: 1, in: Self.phone)
        #expect(abs(next.frame.minX - 304.1) < 0.1 && next.scale > 1 && next.dim == 0)
        let previous = MobileTabCarousel.placement(relative: -1, in: Self.phone)
        #expect(abs(previous.frame.minX - 10) < 0.1 && abs(previous.scale - 0.977) < 0.001)
        #expect(previous.dim == MobileTabCarousel.maximumDim)
        #expect(MobileTabCarousel.placement(relative: -0.5, in: Self.phone).dim == 0.08)
    }

    @Test func draggingFollowsTheFingerAndResistsPastTheEnds() {
        let pitch = MobileTabCarousel.pitch(in: Self.phone)
        #expect(MobileTabCarousel.position(start: 1, translation: -pitch, count: 3, in: Self.phone) == 2)
        #expect(MobileTabCarousel.position(start: 0, translation: pitch * 3, count: 3, in: Self.phone) == -1)
        #expect(MobileTabCarousel.position(start: 2, translation: -pitch * 3, count: 3, in: Self.phone) == 3)
    }

    @Test func aFlickGoesToTheNextCardAndStopsAtTheEnds() {
        #expect(MobileTabCarousel.restingIndex(position: 1.2, velocity: 0, count: 4, in: Self.phone) == 1)
        #expect(MobileTabCarousel.restingIndex(position: 1.2, velocity: -900, count: 4, in: Self.phone) == 2)
        #expect(MobileTabCarousel.restingIndex(position: 1.8, velocity: 900, count: 4, in: Self.phone) == 1)
        #expect(MobileTabCarousel.restingIndex(position: 3.3, velocity: -2000, count: 4, in: Self.phone) == 3)
        #expect(MobileTabCarousel.restingIndex(position: -0.2, velocity: 2000, count: 4, in: Self.phone) == 0)
    }

    @Test func aCardIsThrownAwayByDistanceOrByAFlick() {
        #expect(MobileTabCarousel.closes(translation: -130, velocity: 0))
        #expect(MobileTabCarousel.closes(translation: -40, velocity: -900))
        #expect(!MobileTabCarousel.closes(translation: -40, velocity: -100))
        #expect(!MobileTabCarousel.closes(translation: 200, velocity: 900))
    }
}

struct MobilePageMenuTests {
    /// Arc Search's menu with "Find on Page" and two more rows starts 413 pt down an iPhone 15
    /// Pro: three rows there (one group of one and one of two, 16 pt apart).
    @Test func heightMatchesArcSearch() {
        #expect(abs(MobilePageMenu.height(rows: 3, safeBottom: 34) + 16 - (852 - 413)) < 0.5)
        #expect(abs(MobilePageMenu.height(safeBottom: 34) - 519) < 0.001)
    }

    @Test func fourTilesSitAsMeasuredAndThreeStayCentred() {
        let four = MobilePageMenu.tileFrames(count: 4, width: 393)
        #expect(four.map { ($0.minX * 10).rounded() / 10 } == [21.3, 115.3, 209.4, 303.4])
        #expect(four[0].minY == 81)
        let three = MobilePageMenu.tileFrames(count: 3, width: 393)
        #expect(abs(three[1].midX - 196.5) < 0.01)
        #expect(abs((three[1].minX - three[0].minX) - (four[1].minX - four[0].minX)) < 0.01)
        #expect(MobilePageMenu.tiles(canSummarize: false) == [.reader, .copyLink, .share])
    }

    @Test func zoomStepsByTenthsWithinLimits() {
        #expect(MobilePageMenu.zoom(1, stepping: true) == 1.1)
        #expect(MobilePageMenu.zoom(1.1, stepping: false) == 1)
        #expect(MobilePageMenu.zoom(0.5, stepping: false) == 0.5)
        #expect(MobilePageMenu.zoom(3, stepping: true) == 3)
        #expect(MobilePageMenu.zoomLabel(1) == nil)
        #expect(MobilePageMenu.zoomLabel(1.3) == "130%")
    }

    @Test func blockedCountReadsAsArcSearchs() {
        #expect(MobilePageMenu.blockedLabel(0) == nil)
        #expect(MobilePageMenu.blockedLabel(6) == "Scrubbed 6 ads and trackers")
    }
}
