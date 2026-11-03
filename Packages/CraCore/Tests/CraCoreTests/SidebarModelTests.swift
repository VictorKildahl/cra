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

    /// The line under a tab's title (GitHub #88, #139): Arc's TabCellState.subtitle is a
    /// developer-mode site's host (and port), else a pull request's author. Leaving a pinned
    /// page shows none.
    @Test func sidebarSubtitle() {
        var tab = TabData(url: "https://www.youtube.com/watch?v=1", title: "Video")
        #expect(tab.sidebarSubtitle(developerMode: false) == nil)
        #expect(tab.sidebarSubtitle(developerMode: true) == "youtube.com", "developer mode: the host, without www.")
        tab.savedURL = "https://example.com/"
        #expect(tab.sidebarSubtitle(developerMode: false) == nil, "a pinned tab that left its site shows no host")
        #expect(TabData(url: "http://127.0.0.1:8080/a").sidebarSubtitle(developerMode: true) == "127.0.0.1:8080", "with its port")
        var pull = TabData(url: "https://github.com/o/r/pull/1")
        pull.liveSubtitle = "octocat"
        #expect(pull.sidebarSubtitle(developerMode: false) == "octocat")
        #expect(pull.sidebarSubtitle(developerMode: true) == "github.com", "developer mode comes first in Arc")
        #expect(TabData(url: "notes").sidebarSubtitle(developerMode: true) == nil, "no host, no line")
    }

    /// GitHub #139: a pinned tab that goes back to its page shows that page's name and favicon,
    /// not the last page's, before it loads again.
    @Test func returningHomeShowsTheHomesNameAndIcon() throws {
        var tab = TabData(url: "https://github.com/", title: "")
        tab.noteTitle("GitHub", pinned: true)
        #expect(tab.homeTitle == "GitHub")
        tab.url = "https://gist.github.com/o/1"
        tab.faviconKey = "gist.github.com"
        tab.noteTitle("Developer bar: Console", pinned: true)
        #expect(tab.homeTitle == "GitHub", "a page away from home is not the home")
        tab.returnHome()
        #expect(tab.url == "https://github.com/" && tab.savedTitle == "GitHub" && tab.faviconKey == "github.com")

        var today = TabData(url: "https://example.com/", title: "")
        today.noteTitle("Example", pinned: false)
        #expect(today.homeTitle == nil, "only pinned tabs keep a home name")

        var unseen = TabData(url: "https://a.com/", title: "A")
        unseen.url = "https://a.com/b"
        unseen.savedTitle = "B"
        unseen.returnHome()
        #expect(unseen.savedTitle == "B", "a home never seen keeps the last name until its page reports")

        var pinning = TabData(url: "https://b.com/", title: "Bee")
        pinning.url = "https://c.com/"
        pinning.savedTitle = "Sea"
        pinning.makeCurrentPageHome()
        #expect(pinning.savedURL == "https://c.com/" && pinning.homeTitle == "Sea")

        let data = try JSONEncoder().encode(tab)
        #expect(try JSONDecoder().decode(TabData.self, from: data).homeTitle == "GitHub")
        #expect(try !String(decoding: JSONEncoder().encode(today), as: UTF8.self).contains("homeTitle"), "not written when unknown")
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

    @Test func toolbarShowsTheHostOnlyUnlessAsked() throws {
        #expect(!AppSettings().toolbarShowsFullURL, "Arc's default: the host only")
        let decode = { (json: String) in try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)) }
        #expect(try !decode("{}").toolbarShowsFullURL, "settings from before the option keep Arc's default")
        #expect(try decode(#"{"toolbarShowsFullURL": true}"#).toolbarShowsFullURL)
        var settings = AppSettings()
        settings.toolbarShowsFullURL = true
        #expect(try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)).toolbarShowsFullURL)
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
