import CraCore
import Foundation
import Testing

struct SidebarModelTests {
    static let space = UUID()

    /// The sidebar row's title: the user's name, then the page title, then the host.
    @Test func displayTitle() {
        var tab = SidebarItem.tab("https://example.com/a", title: "Page", parent: nil)
        #expect(tab.displayTitle == "Page")
        tab.title = "Renamed"
        #expect(tab.displayTitle == "Renamed")
        tab.title = ""
        #expect(tab.displayTitle == "Page", "an empty name is no name")
        #expect(SidebarItem.tab("https://example.com/a", parent: nil).displayTitle == "example.com")
        #expect(SidebarItem.tab("notes", parent: nil).displayTitle == "notes", "no host: the URL as typed")
        #expect(SidebarItem.tab("about:blank", parent: nil).displayTitle == "New Tab")
        #expect(SidebarItem.tab("", parent: nil).displayTitle == "New Tab")
        #expect(SidebarItem.split(parent: nil).displayTitle == "Split View")
        #expect(SidebarItem.folder("Reading", parent: nil).displayTitle == "Reading")
        #expect(SidebarItem.container(.today(spaceID: Self.space)).displayTitle == "Untitled")
    }

    @Test func kinds() {
        let parent = UUID()
        let tab = SidebarItem.tab("https://example.com", parent: parent)
        #expect(tab.isTab && !tab.isFolder && !tab.isSplit && tab.split == nil && tab.container == nil && tab.parentID == parent)
        #expect(tab.tab?.faviconKey == "example.com" && tab.tab?.savedURL == "https://example.com")
        var folder = SidebarItem.folder("F", parent: nil)
        #expect(folder.isFolder && !folder.isLiveFolder && folder.tab == nil && !folder.isEmptyTab)
        folder.liveFolder = LiveFolderData()
        #expect(folder.isLiveFolder)
        let split = SidebarItem.split(parent: nil)
        #expect(split.isSplit && split.split == SplitData())
        let id = UUID()
        let container = SidebarItem.container(.pinned(spaceID: Self.space), id: id)
        #expect(container.id == id && container.container?.spaceID == Self.space)
    }

    @Test func iconKeyPrefersTheUsersPick() {
        var tab = TabData(url: "https://example.com", title: "E")
        #expect(tab.iconKey == "example.com")
        tab.customIconKey = "picked"
        #expect(tab.iconKey == "picked")
    }

    @Test func containerKindsRoundTripAndNeedAKind() throws {
        for kind in [ContainerKind.favorites(spaceID: Self.space), .pinned(spaceID: Self.space), .today(spaceID: Self.space)] {
            #expect(try JSONDecoder().decode(ContainerKind.self, from: JSONEncoder().encode(kind)) == kind)
            #expect(kind.spaceID == Self.space)
        }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ContainerKind.self, from: Data("{}".utf8)) }
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(ContainerKind.self, from: Data(#"{"pinned": {}}"#.utf8)) }
    }

    @Test func freshSidebarHasOneSpaceWithItsContainers() throws {
        let doc = SidebarDocument.fresh()
        let space = try #require(doc.spaces.first)
        #expect(doc.spaces.count == 1 && doc.spaceOrder == [space.id] && space.title == "Personal" && space.emoji == "🌱")
        #expect(Set(doc.items.map(\.id)) == [space.favoritesContainerID, space.pinnedContainerID, space.todayContainerID])
        #expect(doc.items.allSatisfy { $0.container?.spaceID == space.id })
        #expect(doc.version == 1 && doc.favoritesContainerID == nil && doc.profiles == nil)
    }

    @Test func profileFolderName() {
        let id = UUID()
        #expect(BrowserProfile(id: id, name: "Work").directoryName == "Profile \(id.uuidString)")
    }

    @Test func thresholds() {
        #expect(AutoArchiveThreshold.allCases.map(\.seconds) == [43_200, 86_400, 604_800, 2_592_000])
        #expect(AutoArchiveThreshold.allCases.map(\.label) == ["12 hours", "24 hours", "7 days", "30 days"])
        #expect(AutoArchiveThreshold.allCases.map(\.id) == AutoArchiveThreshold.allCases.map(\.rawValue))
        #expect(TabSleepThreshold.allCases.map(\.seconds) == [900, 3600, 14_400, 43_200])
        #expect(TabSleepThreshold.allCases.map(\.label) == ["15 minutes", "1 hour", "4 hours", "12 hours"])
        #expect(TabSleepThreshold.allCases.map(\.id) == TabSleepThreshold.allCases.map(\.rawValue))
    }

    @Test(arguments: [
        (SearchEngine.google, "Google", "https://www.google.com/search?q=a%20b%26c", "https://www.google.com/complete/search?client=chrome&ie=utf-8&oe=utf-8&q=a%20b%26c"),
        (.duckduckgo, "DuckDuckGo", "https://duckduckgo.com/?q=a%20b%26c", "https://duckduckgo.com/ac/?type=list&q=a%20b%26c"),
        (.bing, "Bing", "https://www.bing.com/search?q=a%20b%26c", "https://api.bing.com/osjson.aspx?query=a%20b%26c"),
        (.kagi, "Kagi", "https://kagi.com/search?q=a%20b%26c", "https://kagi.com/api/autosuggest?q=a%20b%26c"),
    ])
    func searchEngines(engine: SearchEngine, label: String, search: String, suggest: String) {
        #expect(engine.label == label && engine.id == engine.rawValue)
        #expect(engine.searchURL("a b&c") == search, "& is escaped so it stays in the query")
        #expect(engine.suggestURL("a b&c")?.absoluteString == suggest)
    }

    @Test func developerModeIsPerSite() {
        var settings = AppSettings()
        #expect(AppSettings.siteKey(for: "https://www.Example.com/a") == "example.com")
        #expect(AppSettings.siteKey(for: "notes") == nil)
        settings.toggleDeveloperMode(url: "http://localhost:3000/")
        #expect(settings.isDeveloperMode(url: "http://localhost:8080/other"))
        #expect(!settings.isDeveloperMode(url: "https://example.com"))
        #expect(!settings.isDeveloperMode(url: "notes"))
        settings.toggleDeveloperMode(url: "http://localhost/")
        #expect(settings.developerHosts.isEmpty)
        settings.toggleDeveloperMode(url: "notes")
        #expect(settings.developerHosts.isEmpty, "no host, nothing to toggle")
    }

    @Test func littleWindowSwitchIsTheDefaultDestination() {
        var settings = AppSettings()
        #expect(settings.openExternalLinksInLittleWindow)
        settings.openExternalLinksInLittleWindow = false
        #expect(settings.defaultLinkDestination == .mostRecentSpace)
        settings.openExternalLinksInLittleWindow = true
        #expect(settings.defaultLinkDestination == .littleWindow)
    }

    @Test func incognitoWindowsAreNeverSaved() {
        let normal = WindowSession(focusedSpaceID: Self.space)
        let prefs = WindowPrefs(sidebarWidth: 300, windows: [normal, WindowSession(isIncognito: true)])
        #expect(prefs.withoutIncognito.windows == [normal] && prefs.withoutIncognito.sidebarWidth == 300)
    }

    @Test func archivedItemIsKnownByItsItem() {
        let item = SidebarItem.tab("https://example.com", parent: nil)
        let archived = ArchivedItem(archivedAt: Date(), reason: .manual, sourceSpaceID: nil, wasPinned: false, item: item)
        #expect(archived.id == item.id && archived.fromLittleWindow == nil && archived.sourceFolderID == nil && archived.sourceIndex == nil)
    }

    @Test func memberwiseValues() {
        let date = Date(timeIntervalSince1970: 0)
        let entry = HistoryEntry(url: "https://example.com", title: "E", lastVisit: date, visitCount: 2)
        #expect(entry.visitCount == 2 && entry.lastVisit == date)
        let ranking = RankingData(commandUsage: ["newTab": 1])
        #expect(ranking.commandUsage["newTab"] == 1 && ranking.recentlySwitchedToTabs.isEmpty && ranking.queriesToSelected.isEmpty)
        let doc = SidebarDocument(spaceOrder: [], spaces: [], items: [])
        #expect(doc.version == 1)
        let theme = SpaceTheme.presets[0]
        let space = Space(id: Self.space, title: "S", emoji: "", theme: theme, favoritesContainerID: UUID(), pinnedContainerID: UUID(),
                          todayContainerID: UUID(), createdAt: date, symbol: "star")
        #expect(space.symbol == "star" && space.profileID == nil)
    }
}
