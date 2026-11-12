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

    /// Pages the phone knows join the list: a site whose address starts with what was typed
    /// leads, the typed text follows, a title match comes after it, and completions fill the rest.
    @Test func knownSitesJoinTheList() {
        let sites = [
            MobileSuggestions.Site(title: "Weather Forecast Aarhus", url: "https://yr.no/aarhus"),
            MobileSuggestions.Site(title: "Weather.com", url: "https://www.weather.com/"),
            MobileSuggestions.Site(title: "Weather.com again", url: "http://weather.com#today"),
            MobileSuggestions.Site(title: "Local weather", url: "cra://weather"),
        ]
        let rows = MobileSuggestions.rows(typed: "weat", completions: ["weather", "weather today", "weather aarhus"], sites: sites)
        #expect(rows.map(\.text) == ["Weather.com", "weat", "Weather Forecast Aarhus", "weather"])
        #expect(rows[0].kind == .site(url: "https://www.weather.com/"))
        #expect(rows[2].kind == .site(url: "https://yr.no/aarhus"))
        #expect(MobileSuggestions.destination(for: rows[0], engine: .google) == "https://www.weather.com/")
        #expect(MobileSuggestions.destination(for: rows[3], engine: .google) == "https://www.google.com/search?q=weather")
    }

    /// Without an address match the typed text stays on top; every typed word has to begin a
    /// word of the title, and no more than two sites crowd out the engine.
    @Test func titleMatchesFollowTheTypedText() {
        let sites = [
            MobileSuggestions.Site(title: "Risotto vs paella", url: "https://a.example/1"),
            MobileSuggestions.Site(title: "Paella recipe", url: "https://b.example/2"),
            MobileSuggestions.Site(title: "Best paella in Valencia", url: "https://c.example/3"),
            MobileSuggestions.Site(title: "Spanish rice", url: "https://d.example/4"),
        ]
        let rows = MobileSuggestions.rows(typed: "pae", completions: ["paella"], sites: sites)
        #expect(rows.map(\.text) == ["pae", "Risotto vs paella", "Paella recipe", "paella"])
        #expect(MobileSuggestions.rows(typed: "paella rec", completions: [], sites: sites).map(\.text) == ["paella rec", "Paella recipe"])
        #expect(MobileSuggestions.rows(typed: "ella", completions: [], sites: sites).map(\.text) == ["ella"])
        // A site with no title shows its address.
        let untitled = MobileSuggestions.rows(typed: "news", completions: [], sites: [.init(title: " ", url: "https://www.news.example/")])
        #expect(untitled.map(\.text) == ["news.example", "news"])
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

    @Test func anIncognitoTabClosesOnceItIsLeftAndNeverShowsInTheRow() {
        var document = MobileTabsDocument()
        let plain = Self.tab("plain", hoursAgo: 1), secret = Self.tab("secret", hoursAgo: 0, incognito: true)
        [plain, secret].forEach { document.open($0) }
        #expect(document.rowTabs.map(\.title) == ["plain"])
        #expect(document.closeIncognitoTabsLeftBehind().isEmpty, "the tab on screen stays")
        document.select(plain.id, now: Self.start)
        #expect(document.closeIncognitoTabsLeftBehind() == [secret.id])
        #expect(document.tabs.map(\.title) == ["plain"] && document.archived.isEmpty)
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

    /// "Browse for Me" as the search engine: older files load without it, the engine stays for
    /// suggestions, and a search (not an address) becomes a Browse for Me tab.
    @Test func browseForMeCanBeTheSearchEngine() throws {
        var settings = try JSONDecoder().decode(MobileSettings.self, from: Data(#"{"searchEngine":"bing"}"#.utf8))
        #expect(settings.searchChoice == .engine(.bing) && !settings.searchesWithBrowseForMe)
        settings.searchChoice = .browseForMe
        #expect(settings.searchEngine == .bing && settings.searchesWithBrowseForMe)
        let saved = try JSONDecoder().decode(MobileSettings.self, from: JSONEncoder().encode(settings))
        #expect(saved.searchChoice == .browseForMe)
        settings.searchChoice = .engine(.kagi)
        #expect(settings.searchEngine == .kagi && !settings.searchesWithBrowseForMe)
        #expect(MobileSearchChoice.all(browseForMeAvailable: true).map(\.label) == ["Browse for Me", "Google", "Bing", "DuckDuckGo", "Ecosia", "Perplexity", "Kagi"])
        #expect(MobileSearchChoice.all(browseForMeAvailable: false).first == .engine(.google))
        #expect(MobileSuggestions.destination(forTyped: "pizza ovens", engine: .bing, browsesForMe: true) == MobileBrowseForMe.tabAddress(query: "pizza ovens"))
        #expect(MobileSuggestions.destination(forTyped: "crabrowser.app", engine: .bing, browsesForMe: true) == "https://crabrowser.app")
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

struct MobileBlocklistTests {
    static let list = MobileBlocklist(text: "# comment\n\nads.example.com\nDoubleClick.net\nanalytics.example.org\n")

    @Test func listedDomainsCoverTheirSubdomains() {
        #expect(Self.list.domains == ["ads.example.com", "doubleclick.net", "analytics.example.org"])
        #expect(Self.list.blocks(host: "ads.example.com"))
        #expect(Self.list.blocks(host: "static.G.doubleclick.net"))
        #expect(!Self.list.blocks(host: "example.com"))
        #expect(!Self.list.blocks(host: "notdoubleclick.net"))
        #expect(!Self.list.blocks(host: "net"))
    }

    @Test func aRequestIsStoppedOnlyWhileItsKindIsSwitchedOn() {
        var options = MobileSiteOptions()
        #expect(Self.list.stops(host: "x.doubleclick.net", with: options))
        #expect(Self.list.stops(host: "eu.analytics.example.org", with: options))
        options.blockAds = false
        #expect(!Self.list.stops(host: "x.doubleclick.net", with: options))
        #expect(Self.list.stops(host: "eu.analytics.example.org", with: options))
        #expect(!Self.list.stops(host: "example.com", with: MobileSiteOptions()))
    }

    @Test func aDomainIsATrackerWhenItsNameSaysSo() {
        #expect(Self.list.domains(of: .trackers) == ["analytics.example.org"])
        #expect(Self.list.domains(of: .ads) == ["ads.example.com", "doubleclick.net"])
    }

    /// The JSON WebKit compiles: one third-party block rule per domain, valid JSON whose filter
    /// matches the domain and its subdomains only.
    @Test func rulesAreValidContentBlockerJSON() throws {
        let json = MobileBlocklist.rulesJSON(blocking: ["doubleclick.net"])
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let trigger = try #require(rules.first?["trigger"] as? [String: Any])
        let filter = try #require(trigger["url-filter"] as? String)
        #expect(trigger["load-type"] as? [String] == ["third-party"])
        #expect((rules.first?["action"] as? [String: String])?["type"] == "block")
        let regex = try NSRegularExpression(pattern: filter)
        func matches(_ url: String) -> Bool { regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil }
        #expect(matches("https://doubleclick.net/ad.js") && matches("https://g.doubleclick.net:443/x"))
        #expect(!matches("https://notdoubleclick.net/") && !matches("https://doubleclickxnet/") && !matches("https://example.com/doubleclick.net/"))
    }

    @Test func cookieBannerRuleHidesTheKnownContainers() throws {
        let json = MobileBlocklist.cookieBannerRulesJSON()
        let rules = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        let action = try #require(rules.first?["action"] as? [String: String])
        #expect(action["type"] == "css-display-none")
        #expect(action["selector"]?.contains("#onetrust-banner-sdk") == true)
        #expect(action["selector"]?.contains("[id^=\"sp_message_container\"]") == true)
    }

    @Test func aSitesSwitchesPickItsRuleLists() {
        var options = MobileSiteOptions()
        #expect(MobileBlocklist.ruleLists(for: options) == ["ads", "trackers", "cookie-banners"])
        options.blockAds = false
        options.blockCookieBanners = false
        #expect(MobileBlocklist.ruleLists(for: options) == ["trackers"])
    }
}

struct MobileSwipeTests {
    @Test func aDragCommitsByDistanceOrByAFlickInItsOwnDirection() {
        #expect(MobileSwipe.direction(translation: 150, velocity: 0, width: 393) == 1)
        #expect(MobileSwipe.direction(translation: -150, velocity: 0, width: 393) == -1)
        #expect(MobileSwipe.direction(translation: 60, velocity: 0, width: 393) == 0)
        #expect(MobileSwipe.direction(translation: 60, velocity: 900, width: 393) == 1)
        #expect(MobileSwipe.direction(translation: 60, velocity: -900, width: 393) == 0)
        #expect(MobileSwipe.direction(translation: 10, velocity: 2000, width: 393) == 0)
    }

    @Test func theBarSwipeMovesAlongTheTabRow() {
        #expect(MobileSwipe.tabStep(translation: 200, velocity: 0, width: 393, hasOlder: true, hasNewer: true) == -1)
        #expect(MobileSwipe.tabStep(translation: -200, velocity: 0, width: 393, hasOlder: true, hasNewer: true) == 1)
        #expect(MobileSwipe.tabStep(translation: 200, velocity: 0, width: 393, hasOlder: false, hasNewer: true) == 0)
    }

    /// Arc Search: back on a tab's first page archives the tab; the opposite swipe reopens it.
    @Test func backOnTheFirstPageArchivesTheTabAndForwardBringsItBack() {
        func swipe(_ translation: CGFloat, back: Bool = false, forward: Bool = false, other: Bool = true, reopen: Bool = false) -> MobileSwipe.Navigation {
            MobileSwipe.navigation(translation: translation, velocity: 0, width: 393, canGoBack: back, canGoForward: forward,
                                   hasOtherTab: other, canReopenTab: reopen)
        }
        #expect(swipe(200, back: true) == .back)
        #expect(swipe(200) == .archiveTab)
        #expect(swipe(200, other: false) == .none)
        #expect(swipe(-200, forward: true, reopen: true) == .forward)
        #expect(swipe(-200, reopen: true) == .reopenTab)
        #expect(swipe(-200) == .none)
        #expect(swipe(40, back: true) == .none)
    }

    @Test func edgesOnlyKeepsTheSwipeToTheSides() {
        #expect(MobileSwipe.mayStart(at: 200, width: 393, mode: .fromAnywhere))
        #expect(!MobileSwipe.mayStart(at: 200, width: 393, mode: .fromEdges))
        #expect(MobileSwipe.mayStart(at: 10, width: 393, mode: .fromEdges))
        #expect(MobileSwipe.mayStart(at: 385, width: 393, mode: .fromEdges))
    }

    @Test func pullToRefreshActsOnRelease() {
        #expect(MobileSwipe.refreshes(pullAtRelease: 100))
        #expect(!MobileSwipe.refreshes(pullAtRelease: 60))
    }
}

struct MobileSummaryTests {
    @Test func thePageIsCutAtASentenceToFitTheModel() {
        let sentence = "This is a sentence about pizza. "
        let long = String(repeating: sentence, count: 400)
        let clipped = MobileSummary.clipped(long)
        #expect(clipped.count <= MobileSummary.maxTextLength)
        #expect(clipped.hasSuffix("pizza."))
        #expect(MobileSummary.clipped("a   b\n\n\n  c ") == "a b\nc")
        #expect(MobileSummary.prompt(title: "Pizza", text: "Dough.", language: "Danish")
            == "Answer in Danish.\n\nWEB PAGE:\n<webpage>\nTitle: Pizza\nDough.\n</webpage>")
    }

    @Test func aPageNeedsSomeTextToBeSummarized() {
        #expect(!MobileSummary.canSummarize(text: "Sign in"))
        #expect(MobileSummary.canSummarize(text: String(repeating: "Words about a thing. ", count: 20)))
    }

    @Test func anAnswerIsTidiedAndAnEmptyOneIsNoAnswer() {
        let answer = MobileSummary.Answer(overview: "  About pizza.\n", sections: [
            .init(title: " Dough ", body: "Flour and water."), .init(title: "", body: "No title"), .init(title: "Empty", body: "  "),
        ])
        #expect(answer.cleaned == MobileSummary.Answer(overview: "About pizza.", sections: [.init(title: "Dough", body: "Flour and water.")]))
        #expect(MobileSummary.Answer(overview: " ", sections: []).cleaned == nil)
        #expect(MobileSummary.fakeAnswer(title: "T", text: "One. Two. Three.").sections.map(\.body) == ["Two.", "Three."])
    }
}

struct MobileBrowseForMeTests {
    /// DuckDuckGo's HTML results, trimmed to two results and an ad (its markup, 11 Nov 2026).
    static let results = """
    <div class="result results_links results_links_deep result--ad">
      <a rel="nofollow" class="result__a" href="https://duckduckgo.com/y.js?ad_domain=shop.example&amp;u3=x">Buy Pizza Ovens</a>
      <a class="result__snippet" href="https://duckduckgo.com/y.js?ad_domain=shop.example">An ad.</a>
    </div>
    <div class="result results_links results_links_deep web-result">
      <h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.example.com%2Fpizza%3Fa%3D1%26b%3D2&amp;rut=abc">Neapolitan <b>pizza</b> &amp; its dough</a></h2>
      <a class="result__snippet" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.example.com%2Fpizza">A soft, thin <b>pizza</b> from Naples.</a>
    </div>
    <div class="result results_links results_links_deep web-result">
      <h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fwww.example.com%2Fother&amp;rut=def">Same site again</a></h2>
      <a class="result__snippet" href="#">More.</a>
    </div>
    <div class="result results_links results_links_deep web-result">
      <h2 class="result__title"><a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fen.wikipedia.org%2Fwiki%2FPizza&amp;rut=ghi">Pizza - Wikipedia</a></h2>
      <a class="result__snippet" href="#">Pizza is a dish.</a>
    </div>
    """

    @Test func readsTheResultsAndLeavesAdsOut() {
        let hits = MobileBrowseForMe.hits(fromResultsHTML: Self.results)
        #expect(hits.map(\.url) == ["https://www.example.com/pizza?a=1&b=2", "https://www.example.com/other", "https://en.wikipedia.org/wiki/Pizza"])
        #expect(hits[0].title == "Neapolitan pizza & its dough")
        #expect(hits[0].snippet == "A soft, thin pizza from Naples.")
        #expect(hits[0].host == "example.com")
        #expect(MobileBrowseForMe.pick(hits).map(\.host) == ["example.com", "en.wikipedia.org"])
        #expect(MobileBrowseForMe.hits(fromResultsHTML: "<html>nothing</html>").isEmpty)
    }

    @Test func theQueryGoesToDuckDuckGosPlainResults() {
        #expect(MobileBrowseForMe.searchURL("what to do & see")?.absoluteString == "https://html.duckduckgo.com/html/?q=what%20to%20do%20%26%20see")
    }

    @Test func thePromptGivesEachPageItsSiteAndAClippedText() {
        let source = MobileBrowseForMe.Source(hit: .init(title: "T", url: "https://www.example.com/a"), title: "Pizza", text: String(repeating: "Dough rests. ", count: 100))
        let prompt = MobileBrowseForMe.prompt(query: "pizza", sources: [source], language: "English")
        #expect(prompt.hasPrefix("Answer in English.\n\nQUESTION: pizza\n\nWEB PAGES:\n<page 1 site=\"example.com\">\nPizza\nDough rests."))
        #expect(prompt.count < 700)
    }

    @Test func aTabRemembersItsQuery() {
        let address = MobileBrowseForMe.tabAddress(query: "what to do at joshua tree?")
        #expect(MobileBrowseForMe.query(fromTabAddress: address) == "what to do at joshua tree?")
        #expect(URL(string: address)?.host == nil)
        #expect(MobileBrowseForMe.query(fromTabAddress: "https://example.com") == nil)
    }

    @Test func thePageEscapesWhatItWasGiven() {
        let source = MobileBrowseForMe.Source(hit: .init(title: "Hit", url: "https://example.com/a?x=1&y=2"), title: "<b>Title</b>", text: "", image: "/pic.jpg")
        let answer = MobileBrowseForMe.Answer(title: "A <script>", points: [.init(emoji: "🍕", term: "Dough", text: "Rests & rises.")],
                                              sections: [.init(heading: "Oven", text: "400 \"degrees\".")])
        let html = MobileBrowseForMe.pageHTML(query: "pizza <i>", answer: answer, sources: [source], searchURL: "https://duckduckgo.com/?q=pizza")
        #expect(html.contains("<title>A &lt;script&gt;</title>"))
        #expect(html.contains("<span>pizza &lt;i&gt;</span>"))
        #expect(html.contains("<b>Dough</b> — Rests &amp; rises."))
        #expect(html.contains("href=\"https://example.com/a?x=1&amp;y=2\""))
        #expect(html.contains("src=\"https://example.com/pic.jpg\""))
        #expect(html.contains("Read 1 web page<"))
        #expect(!html.contains("<script>"))
    }

    @Test func anAnswerWithNothingInItIsNoAnswer() {
        #expect(MobileBrowseForMe.Answer(title: "T", points: [.init(emoji: "", term: "", text: " ")], sections: []).cleaned == nil)
        #expect(MobileBrowseForMe.readingLabel(6) == "Reading 6 web pages")
    }
}

struct MobileSpacesTests {
    /// A Mac sidebar: one space with a pinned tab, a folder holding a tab, and a Today tab; and
    /// a second, empty space.
    static func sidebar() -> (SidebarDocument, folder: UUID) {
        var document = SidebarDocument.fresh()
        let space = document.spaces[0]
        var pinned = SidebarItem.tab("https://mail.example/inbox", title: "Mail", parent: space.pinnedContainerID)
        pinned.title = "Inbox"
        var folder = SidebarItem.folder("Work", parent: space.pinnedContainerID)
        let inside = SidebarItem.tab("https://docs.example/", title: "Docs", parent: folder.id)
        folder.children = [inside.id]
        let today = SidebarItem.tab("https://news.example/story", title: "", parent: space.todayContainerID)
        document.items += [pinned, folder, inside, today]
        for (container, children) in [(space.pinnedContainerID, [pinned.id, folder.id]), (space.todayContainerID, [today.id])] {
            let index = document.items.firstIndex { $0.id == container }!
            document.items[index].children = children
        }
        let secondID = UUID()
        let containers = [SidebarItem.container(.favorites(spaceID: secondID)), .container(.pinned(spaceID: secondID)), .container(.today(spaceID: secondID))]
        document.items += containers
        document.spaces.append(Space(id: secondID, title: "Play", emoji: "🎮", theme: SpaceTheme.presets[1], favoritesContainerID: containers[0].id,
                                     pinnedContainerID: containers[1].id, todayContainerID: containers[2].id, createdAt: Date()))
        document.spaceOrder.append(secondID)
        return (document, folder.id)
    }

    @Test func aSpaceListsItsPinsFoldersAndTodayTabs() {
        let (document, folder) = Self.sidebar()
        let spaces = MobileSpaces.spaces(in: document)
        #expect(spaces.map(\.title) == ["Personal", "Play"])
        #expect(spaces[0].rows.map(\.title) == ["Inbox", "Work", "Docs", "Today", "news.example"])
        #expect(spaces[0].rows.map(\.depth) == [0, 0, 1, 0, 0])
        #expect(spaces[0].rows[0].kind == .tab(url: "https://mail.example/inbox"))
        #expect(spaces[0].rows[3].kind == .todayHeader)
        #expect(spaces[1].rows.isEmpty)
        #expect(spaces[0].colors == SpaceTheme.presets[0].colors)
        let closed = MobileSpaces.spaces(in: document, closedFolders: [folder])
        #expect(closed[0].rows.map(\.title) == ["Inbox", "Work", "Today", "news.example"])
    }

    @Test func theSyncedFileReadsBack() throws {
        let (document, _) = Self.sidebar()
        let data = try JSONEncoder().encode(document)
        #expect(MobileSpaces.document(from: data)?.spaces.count == 2)
        #expect(MobileSpaces.document(from: Data("{}".utf8)) == nil)
    }
}

struct MobileFavoritesTests {
    @Test func aPageTogglesInAndOutWhateverItsTrackers() {
        var favorites = MobileFavorites()
        let added = favorites.toggle(url: "https://example.com/a?utm_source=x", title: "A")
        #expect(added)
        #expect(favorites.contains("https://example.com/a#part"))
        #expect(!favorites.contains("https://example.com/b"))
        let stillThere = favorites.toggle(url: "https://example.com/a", title: "A")
        #expect(!stillThere)
        #expect(favorites.sites.isEmpty)
        favorites.toggle(url: "https://example.org/", title: "")
        #expect(favorites.sites[0].title == "example.org")
    }

    @Test func fourShowUnderTheFieldInTheirOrder() throws {
        var favorites = MobileFavorites()
        for name in ["a", "b", "c", "d", "e"] { favorites.toggle(url: "https://\(name).example", title: name) }
        favorites.move(from: 4, to: 0)
        #expect(favorites.shown().map(\.title) == ["e", "a", "b", "c"])
        let saved = try JSONEncoder().encode(favorites)
        #expect(try JSONDecoder().decode(MobileFavorites.self, from: saved) == favorites)
        #expect(try JSONDecoder().decode(MobileFavorites.self, from: Data("{}".utf8)).sites.isEmpty)
    }
}

struct MobileMotionTests {
    /// Arc Search's tab row: each frame leaves about 0.54 of the distance of the frame before,
    /// once the motion is under way.
    @Test func theTabRowSettlesAtArcSearchsRate() {
        let spring = MobileMotion.tabRowSettle
        let frame = 1.0 / 30
        let ratio = spring.remaining(after: 6 * frame) / spring.remaining(after: 5 * frame)
        #expect(abs(ratio - 0.6) < 0.08)
        #expect(spring.remaining(after: 0.3) < 0.03)
        #expect(abs(spring.stiffness - 341.5) < 1 && abs(spring.damping - 36.96) < 0.1)
    }

    @Test func aCardIsItsPageWithinFiveFrames() {
        #expect(MobileMotion.tabOpen.remaining(after: 5.0 / 30) < 0.1)
    }

    @Test func draggingTheBarUpOpensTheRowByDistanceOrFlick() {
        #expect(MobileMotion.switcherProgress(dragUp: 150) == 0.5)
        #expect(MobileMotion.switcherProgress(dragUp: 900) == 1)
        #expect(MobileMotion.opensSwitcher(dragUp: 120, velocityUp: 0))
        #expect(MobileMotion.opensSwitcher(dragUp: 40, velocityUp: 800))
        #expect(!MobileMotion.opensSwitcher(dragUp: 40, velocityUp: 100))
    }
}

struct MobileOnboardingTests {
    @Test func theStepsFollowArcSearchsOrderAndSkipAIWhereThereIsNone() {
        #expect(MobileOnboarding.steps(canUseAI: true) == [.welcome, .meet, .browseForMe, .icon, .blocking, .defaultBrowser])
        #expect(MobileOnboarding.steps(canUseAI: false) == [.welcome, .meet, .icon, .blocking, .defaultBrowser])
        #expect(MobileOnboarding.buttonTitle(for: .welcome) == "Next")
        #expect(MobileOnboarding.buttonTitle(for: .blocking) == "Let’s go")
        #expect(MobileOnboarding.cards.map(\.title) == ["Protect your privacy", "Auto-archives old tabs", "Keep your logins", "Navigate faster"])
    }

    @Test func iconsMapToTheirAlternateNames() {
        #expect(MobileAppIcon.allCases.map(\.alternateName) == [nil, "AppIcon-Midnight", "AppIcon-Mono", "AppIcon-Violet"])
        #expect(MobileAppIcon(alternateName: "AppIcon-Violet") == .violet)
        #expect(MobileAppIcon(alternateName: nil) == .segments)
        #expect(MobileAppIcon(alternateName: "Gone") == .segments)
        #expect(MobileAppIcon.mono.previewName == "AppIcon-Mono-Preview")
    }
}

struct MobileDownloadsTests {
    /// Arc Search 1.16: downloads get sequential numbers so files aren't overwritten.
    @Test func aRepeatedDownloadIsNumberedNotOverwritten() {
        #expect(MobileDownloads.freeName(for: "report.pdf", taken: []) == "report.pdf")
        #expect(MobileDownloads.freeName(for: "report.pdf", taken: ["report.pdf"]) == "report 2.pdf")
        #expect(MobileDownloads.freeName(for: "report.pdf", taken: ["report.pdf", "report 2.pdf"]) == "report 3.pdf")
        #expect(MobileDownloads.freeName(for: "README", taken: ["README"]) == "README 2")
        #expect(MobileDownloads.freeName(for: "archive.tar.gz", taken: ["archive.tar.gz"]) == "archive.tar 2.gz")
    }

    @Test func aNameCannotLeaveTheFolderOrHide() {
        #expect(MobileDownloads.safeName("../../etc/passwd") == "_.._etc_passwd")
        #expect(MobileDownloads.safeName(".hidden") == "hidden")
        #expect(MobileDownloads.safeName("  ") == "Download")
    }

    @Test func theListKeepsNewestFirstAndSaysWhereAFileCameFrom() throws {
        var downloads = MobileDownloads()
        let old = MobileDownloads.Item(name: "a.pdf", source: "https://www.example.com/a.pdf", date: Date(timeIntervalSince1970: 1), bytes: 2_048)
        let new = MobileDownloads.Item(name: "b.pkpass", source: "https://tickets.example/b", date: Date(timeIntervalSince1970: 2), bytes: 10)
        downloads.add(old)
        downloads.add(new)
        #expect(downloads.items.map(\.name) == ["b.pkpass", "a.pdf"])
        #expect(MobileDownloads.detail(for: old).hasPrefix("example.com · "))
        #expect(MobileDownloads.opening(forName: "b.pkpass") == .walletPass)
        #expect(MobileDownloads.opening(forName: "a.PDF") == .preview)
        downloads.remove([new.id])
        let saved = try JSONEncoder().encode(downloads)
        #expect(try JSONDecoder().decode(MobileDownloads.self, from: saved) == downloads)
    }

    @Test func aCertificateExceptionIsForOneHost() {
        var exceptions = MobileCertificateExceptions()
        exceptions.allow("Self-Signed.Example")
        #expect(exceptions.allows("self-signed.example"))
        #expect(!exceptions.allows("other.example"))
    }
}

struct MobileFidgetTests {
    @Test func theSpinSlowsDownAndStops() {
        var angle = 0.0, speed = MobileFidget.launchSpeed(angularVelocity: 200)
        #expect(speed == 60)
        var seconds = 0.0
        while MobileFidget.isSpinning(speed: speed) {
            (angle, speed) = MobileFidget.step(angle: angle, speed: speed, elapsed: 1.0 / 60)
            seconds += 1.0 / 60
        }
        #expect(seconds > 4 && seconds < 7)
        #expect(angle > 60)
    }

    @Test func itSettlesUprightOnTheTurnItWasHeadingFor() {
        #expect(abs(MobileFidget.restAngle(from: 7, speed: 1) - 4 * Double.pi) < 1e-9)
        #expect(abs(MobileFidget.restAngle(from: 7, speed: -1) - 2 * Double.pi) < 1e-9)
        #expect(MobileFidget.restAngle(from: -1, speed: -1) == -2 * Double.pi)
        #expect(MobileFidget.quarterTurns(from: 0, to: 3.3) == 2)
    }

    /// Arc Search pushes the page back as a card under the status bar while the sheet is up:
    /// 10 pt in from each side on a 393 pt screen.
    @Test func thePageSitsBehindTheSearchSheetAsACard() {
        let placed = MobilePageBehindSearch.transform(in: CGSize(width: 393, height: 852), safeTop: 59)
        #expect(abs(placed.scale - 373.0 / 393) < 1e-9)
        // The scaled page's top edge: half the lost height, plus the shift.
        let top = 852 * (1 - placed.scale) / 2 + placed.shiftDown
        #expect(abs(top - 59) < 1e-9)
        // White under the dim comes out #cccccc, the screenshot's colour.
        #expect(Int(((1 - MobilePageBehindSearch.dim) * 255).rounded()) == 0xcc)
    }
}

/// The switch between Browse for Me and the search engine on their pages.
struct MobileBrowseToggleTests {
    /// TapSmart's screenshot of Arc Search (402 × 874 pt, bar top at 798.3 pt): the capsule spans
    /// 278–386 pt across and 738–781 pt down.
    @Test func theSwitchSitsWhereArcSearchPutsIt() {
        let frame = MobileBrowseToggle.frame(screenWidth: 402, barTop: 798)
        #expect(frame == CGRect(x: 278, y: 738, width: 108, height: 43))
        #expect(MobileBrowseToggle.segmentFrame(for: .browseForMe) == CGRect(x: 6, y: 6, width: 42, height: 31))
        #expect(MobileBrowseToggle.segmentFrame(for: .engine) == CGRect(x: 60, y: 6, width: 42, height: 31))
    }

    /// A Browse for Me tab shows its side; the engine's results show the other; other pages none.
    @Test func eachPageKnowsItsSideAndQuery() {
        let browse = MobileBrowseToggle.state(tabAddress: MobileBrowseForMe.tabAddress(query: "best places paris"), pageURL: "about:blank", engine: .google)
        #expect(browse?.side == .browseForMe && browse?.query == "best places paris")
        let results = MobileBrowseToggle.state(tabAddress: "https://www.google.com/search?q=best+places%20paris&hl=en",
                                               pageURL: "https://www.google.com/search?q=best+places%20paris&hl=en", engine: .google)
        #expect(results?.side == .engine && results?.query == "best places paris")
        #expect(MobileBrowseToggle.state(tabAddress: "https://example.com/search?q=x", pageURL: "https://example.com/search?q=x", engine: .google) == nil)
        // Another engine's results are not the chosen engine's.
        #expect(MobileBrowseToggle.state(tabAddress: "", pageURL: "https://www.bing.com/search?q=x", engine: .google) == nil)
    }

    /// Every engine's own results address reads back the query it was made from.
    @Test func everyEnginesResultsReadBack() {
        for engine in MobileSearchEngine.allCases {
            #expect(engine.query(fromResultsURL: engine.searchURL("risotto vs paella & more")) == "risotto vs paella & more", "\(engine)")
        }
        #expect(MobileSearchEngine.duckduckgo.query(fromResultsURL: "https://duckduckgo.com/?t=h_&q=cats&ia=web") == "cats")
        #expect(MobileSearchEngine.google.query(fromResultsURL: "https://www.google.com/search?q=") == nil)
    }
}

struct MobileSelectionQueryTests {
    /// Selected text becomes one line, cut at a word within 200 characters.
    @Test func selectedTextBecomesAQuestion() {
        #expect(MobileBrowseForMe.query(fromSelection: "  wood-fired\n\tpizza   ovens ") == "wood-fired pizza ovens")
        let long = Array(repeating: "word", count: 60).joined(separator: " ")
        let query = MobileBrowseForMe.query(fromSelection: long)
        #expect(query.count <= 200 && query.hasSuffix("word") && !query.hasSuffix(" "))
        #expect(MobileBrowseForMe.query(fromSelection: String(repeating: "x", count: 300)).count == 200)
        #expect(MobileBrowseForMe.query(fromSelection: " \n ").isEmpty)
    }
}

/// Links from other apps' share sheets, waiting in the App Group for the app.
struct MobileShareInboxTests {
    /// A saved link joins the row behind what is on screen.
    @Test func aSavedLinkJoinsTheRowWithoutTakingTheScreen() {
        let now = Date(timeIntervalSince1970: 0)
        let shown = MobileTab(url: "https://a.example", lastActive: now)
        var document = MobileTabsDocument(tabs: [shown], selected: shown.id)
        document.add(MobileTab(url: "https://b.example", title: "B", lastActive: now))
        #expect(document.selected == shown.id && document.tabs.map(\.url) == ["https://a.example", "https://b.example"])
    }

    @Test func savedLinksWaitOnceEachAndRememberThePlace() {
        var inbox = MobileShareInbox()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let kept1 = inbox.save(url: "https://tidbits.com/a", title: " TidBITS ", to: .favorites, at: now)
        #expect(kept1)
        let kept2 = inbox.save(url: "https://tidbits.com/a", title: "TidBITS again", to: .favorites, at: now)
        #expect(kept2)
        let kept3 = inbox.save(url: "https://tidbits.com/a", title: "", to: .tabs, at: now)
        #expect(kept3)
        let kept4 = inbox.save(url: "file:///etc/hosts", title: "x", to: .tabs, at: now)
        #expect(!kept4)
        let kept5 = inbox.save(url: "javascript:alert(1)", title: "x", to: .tabs, at: now)
        #expect(!kept5)
        #expect(inbox.items.map(\.title) == ["TidBITS again", "tidbits.com"])
        #expect(inbox.lastDestination == .tabs)
        let taken = inbox.take()
        #expect(taken.count == 2)
        #expect(inbox.items.isEmpty && inbox.lastDestination == .tabs)
        for index in 0..<(MobileShareInbox.limit + 5) { inbox.save(url: "https://e.example/\(index)", title: "", to: .tabs, at: now) }
        #expect(inbox.items.count == MobileShareInbox.limit && inbox.items.first?.url == "https://e.example/5")
    }

    /// The extension writes, the app takes: one file in the shared folder, read back whole.
    @Test func theFileCarriesLinksFromTheExtensionToTheApp() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("inbox-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let saved = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in
            inbox.save(url: "https://crabrowser.app", title: "Cra", to: .favorites, at: Date(timeIntervalSince1970: 0))
        }
        #expect(saved == true)
        let place = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in inbox.lastDestination }
        #expect(place == .favorites)
        let taken = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in inbox.take() } ?? []
        #expect(taken.map(\.url) == ["https://crabrowser.app"] && taken.first?.destination == .favorites)
        let left = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in inbox.items.count }
        #expect(left == 0)
        // A file from a newer or broken build is an empty inbox, not a crash.
        try Data("{\"items\":[{\"url\":1}],\"lastDestination\":\"space\"}".utf8).write(to: folder.appendingPathComponent(MobileShareInbox.fileName))
        let broken = MobileShareInbox.update(in: folder) { (inbox: inout MobileShareInbox) in inbox }
        #expect(broken == MobileShareInbox())
    }
}
