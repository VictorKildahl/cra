import AppKit
import Compression
import CryptoKit
import Foundation
import Observation
import SQLite3

/// The production store and the Arc importer, booted through AppComposition with a manual
/// clock and a throwaway data folder: timed work (auto-archive, tab sleep cadence) and the
/// import run in milliseconds, against a made-up Arc profile (Tests/Fixtures/Arc).
@main
enum StoreTests {
    private static var checks = 0

    @MainActor
    static func main() throws {
        let data = FileManager.default.temporaryDirectory.appendingPathComponent("cra-store-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: data) }
        // Before AppPaths and ArcImporter read them: they are fixed for the process.
        setenv("CRA_DATA_DIR", data.path, 1)
        setenv("CRA_ARC_DIR", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc").path, 1)
        setenv("CRA_DIA_DIR", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Dia").path, 1)
        setenv("CRA_ARDIA_DIR", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Ardia").path, 1)
        setenv("CRA_YAB_DIR", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Yab").path, 1)
        setenv("CRA_PHI_DIR", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Phi").path, 1)
        setenv("CRA_CREST_DIR", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Crest").path, 1)

        try arcImport()
        try arcKeepsAnyAddress()
        try importedTabsKeepTheirOwnIcons()
        try arcIconsBeyondTheSidebarCache()
        try diaImport()
        try diaIconsFromItsDatabase()
        try ardiaImport()
        try phiImport()
        try crestImport()
        try arcImportReport()
        try arcSpacesOnOneProfileCountTheirFavoritesOnce()
        try arcArchiveBeyondItsLimitIsListed()
        try arcTabThatIsNoLiveItemIsListed()
        try diaImportReport()
        try ardiaImportReport()
        try yabImportReport()
        try yabFavoritesCountAsYabHoldsThem()
        try arcCraAddressesAreListed()
        diaSidebarCraAddressesAreListed()
        try diaLegacyLeftOutAreListed()
        chromiumImportReport()
        firefoxImportReport()
        zenImportReport()
        try safariImportReport()
        try yabImport()
        try yabOwnIcons()
        pinPickerReadsTheImportsIconStores()
        iconFilesAreDecodedSmall()
        faviconDatabaseLookup()
        try chromiumAndFirefoxPlansBringIcons()
        plansReadOffTheMainThread()
        planLoaderReadsOffMainAndKeepsTheLastPick()
        try yabKeepsAnyAddress()
        chromiumProfile()
        try firefoxImport()
        try zenImport()
        try safariImport()
        deletedBrowserStillImports()
        protectedBrowserAsksForFullDiskAccess()
        importListReadsNothingInsideABrowsersFolder()
        signedInChromeProfileImports()
        chromiumManifestV2Import()
        zenFaviconSize()
        autoArchive()
        autoArchiveCounts()
        longAutoArchive()
        profileAutoArchive()
        tabSleepCadence()
        tabRestTimes()
        integrity()
        liveFolderExpiry()
        pluginFolderResults()
        liveRepositoryFiltering()
        liveRepositoryMenus()
        liveFolderExpiryKeepsNavigatedPages()
        mergedPullRequestsLeaveAnUpdatedFolder()
        closedPullRequestsLeaveFromTheirOwnPages()
        closedPullRequestsStayOutAcrossRefreshes()
        gitLabHiddenItems()
        gitLabFolderExpiryAndDeletion()
        gitLabMultipleServers()
        liveFoldersRejectStandaloneSpaces()
        gitLabProfileChangeClearsResults()
        gitLabFolderMovesRejectDuplicateServers()
        gitLabProfileChangeKeepsNavigatedPages()
        stampsUseTheClock()
        visitsRememberTheirProfile()
        historyFromBeforeProfilesTakesThemFromChromium()
        persistenceFaults()
        incognitoStaysOffDisk()
        chromePagesLeaveIncognito()
        incognitoKeepsItsSpacesProfile()
        mcpExcludesPrivateTabs()
        pinnedURL()
        tabFavicons()
        folderSymbols()
        moveTabToSpace()
        moveFolderToSpace()
        folderPeek()
        folderPeekAfterClosing()
        collapsedPinnedPeek()
        closeSuccessor()
        favoritesEmptyState()
        sharedFavorites()
        selectSharedFavoriteInSpace()
        removedFavoriteComesBackOnUndo()
        profileTabsSpaceBySpace()
        newDocumentApps()
        themePreview()
        try arcSpacesWithoutAThemeShareOneDefault()
        try arcItemListedTwice()
        try arcLiveFolderImportsLive()
        try arcSpaceWithoutAnIconImportsAsADot()
        try arcSpaceIconTabGlyphImports()
        try arcStubContainerBeforeTheSpaces()
        littleWindowProfile()
        tidyTabs()
        tidyExistingGroupIdentity()
        tidyConsideredSnapshots()
        tidySingletonGroups()
        pinHook()
        dropOnPinnedTabSplits()
        reopenClosedTabs()
        reopenClosedPinnedTabs()
        reopenClosedTabInThisSpaceOnly()
        duplicateFavoritesAndSplits()
        windowsShareTheSidebar()
        clearTodayArchivesInOnePass()
        settingsSync()
        syncKeepsASplitMadeWhileTheOtherMacLooked()
        thinSplitsGoOnLoad()
        syncLeavesBlankWindowsOnTheirMac()
        blankWindows()
        blankWindowWithoutItsWindow()
        tornOffTabMovesToABlankWindow()
        tornOffTabKeepsItsProfile()
        archiveTabsBelow()
        archiveTabsAboveAndOthers()
        splitIconAndReset()
        numberedSidebarItems()
        clearTodayKeepsSelectedAndPlaying()
        tabsMenuCountsStopEarly()
        allFoldersExpanded()
        dropIntoFolderGoesOnTop()
        revealInSidebar()
        oneWindowAtLaunch()
        openLinkInSplit()
        fullSplitTakesNoMorePanes()
        backToReferrer()
        recentTabsTakeBackgroundTabs()
        recentTabsInAllSpacesGoBack()
        recentCardsKeepSplitsWhole()
        incognitoSpaceKeepsItsContext()
        newWindowsTakeTheLastSidebarChoice()
        rerouteTabKeepsOriginSelection()
        print("Store: \(checks) checks passed")
    }

    @MainActor
    private static func arcImport() throws {
        let plan = try ArcImporter.plan()
        expect(plan.spaces.map(\.title) == ["Home", "Work"], "both spaces come over in Arc's order")
        expect(plan.spaces.map(\.emoji) == ["🏠", "💼"], "emoji_v2 and the older numeric emoji both read")
        let home = plan.spaces[0], work = plan.spaces[1]
        expect(home.favorites.compactMap(\.url) == ["https://example.com/mail", "https://example.com/calendar"],
               "the profile's top apps become the space's favorites")
        expect(home.pinned.count == 1 && home.pinned[0].isFolder && home.pinned[0].customTitle == "Reading"
               && home.pinned[0].children.count == 2, "a pinned folder keeps its title and tabs")
        expect(home.pinned[0].children[1].customTitle == "My blog", "a renamed tab keeps its custom title")
        expect(home.today.count == 3, "Today tabs come over")
        expect(work.pinned.isEmpty && work.today.count == 1 && work.today[0].isFolder && work.today[0].children.count == 2,
               "a split view is flattened into a folder of its tabs")
        expect(plan.archive.map(\.pageTitle) == ["Old two", "Old one"], "archived tabs are newest first, about:blank and blob: ones left out")
        expect(plan.archive.map(\.reason) == [.manual, .auto] && plan.archive.map(\.spaceTitle) == ["Work", "Home"],
               "archive entries keep their reason and space")
        expect(plan.settings.sidebarWidth == 280, "the sidebar width comes from StorableWindows.json")

        let composition = AppComposition(clock: ManualScheduler())
        let result = composition.store.apply(plan, includeArchive: true, includeSettings: true)
        expect(result.spaces == 2 && result.archived == 2, "applying the plan adds both spaces and the archive")
        let titles = composition.store.orderedSpaces.map(\.title)
        expect(titles.contains("Home") && titles.contains("Work"), "the imported spaces are in the sidebar")
        expect(composition.store.integrityProblems().isEmpty, "the imported sidebar is sound")
        arcLinkRoutes(store: composition.store)
        arcProfiles(plan: plan, store: composition.store)
        arcSiteProfiles(plan: plan, store: composition.store)
    }

    // promise: #742
    /// Arc import keeps a tab whatever its address, as it always has, and leaves out what every
    /// importer leaves out: a blank or new tab page and a blob:.
    private static func arcKeepsAnyAddress() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        var sidebar = root["sidebar"] as! [String: Any]
        var containers = sidebar["containers"] as! [[String: Any]]
        let main = containers.firstIndex { $0["spaces"] != nil }!
        var items = containers[main]["items"] as! [Any]
        let tabs = ["file:///Users/me/notes.html", "javascript:void(document.title)", "chrome://extensions/",
                    "about:blank", "chrome://newtab/", "blob:https://example.com/5f1c"]
        let ids = tabs.indices.map { "work-t\($0)" }
        for (id, url) in zip(ids, tabs) {
            items += [id, ["id": id, "parentID": "work-today", "childrenIds": [String](), "isUnread": false, "originatingDevice": "FIXTURE",
                           "createdAt": 800000000.0, "data": ["tab": ["savedURL": url, "savedTitle": id]]] as [String: Any]]
        }
        let today = items.firstIndex { ($0 as? String) == "work-today" }! + 1
        var container = items[today] as! [String: Any]
        container["childrenIds"] = (container["childrenIds"] as! [String]) + ids
        items[today] = container
        containers[main]["items"] = items
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let plan = try ArcImporter.plan(sidebar: JSONSerialization.data(withJSONObject: root))
        expect(plan.spaces[1].today.compactMap(\.url) == Array(tabs.prefix(3)),
               "Arc's Today tabs come over whatever their address; about:blank, a new tab page and blob: left out")
    }

    // promise: #673
    /// Arc keeps one favicon per sidebar item, and the importer has each one's file. They were all
    /// copied under the host alone, so every imported Google Doc, Sheet and Slide showed one icon,
    /// and the icon of whichever page on the host loaded last (#673). Each imported tab keeps its own.
    @MainActor
    private static func importedTabsKeepTheirOwnIcons() throws {
        func saved(_ key: String?) -> Data? {
            key.flatMap { try? Data(contentsOf: AppPaths.favicons.appendingPathComponent(FaviconCache.fileName($0))) }
        }
        // From Arc's own files: the fixture's pinned folder has two tabs on example.com, with an icon
        // each in SidebarItemsFaviconCache.
        let arc = AppComposition(clock: ManualScheduler()).store
        let home = arc.apply(try ArcImporter.plan(), includeArchive: false, includeSettings: false).spaceIDs[0]
        let fromArc = (arc.space(home)?.pinnedContainerID).map(arc.tabs(under:)) ?? []
        let news = fromArc.first { $0.tab?.url == "https://example.com/news" }, blog = fromArc.first { $0.tab?.url == "https://example.com/blog" }
        let cached = { (item: String) in ArcImporter.faviconFile(forItemID: item).flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } }
        expect(cached("home-p1") != nil && cached("home-p1") != cached("home-p2"), "the fixture has a different icon for each of the two tabs")
        expect(news?.tab?.faviconKey == news.map { FaviconKey.key(site: "example.com", tabID: $0.id) }
               && saved(news?.tab?.faviconKey) == cached("home-p1") && saved(blog?.tab?.faviconKey) == cached("home-p2"),
               "each tab imported from Arc keeps the icon Arc cached for it")

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-import-icons-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        func icon(_ name: String, _ color: NSColor) -> (path: String, data: Data) {
            let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in color.setFill(); r.fill(); return true }
            let data = ZenImporter.faviconPNG(image) ?? Data()
            let file = dir.appendingPathComponent(name)
            try? data.write(to: file)
            return (file.path, data)
        }
        let doc = icon("doc", .blue), sheet = icon("sheet", .green), other = icon("other", .red)
        let docURL = "https://docs.example.com/document/d/1/edit", sheetURL = "https://docs.example.com/spreadsheets/d/2/edit"
        var plan = ImportPlan(source: "Arc")
        plan.spaces = [ImportedSpace(title: "Icons", emoji: "📄", pinned: [
            ImportedItem(customTitle: "Files", pageTitle: "Files", isFolder: true, children: [
                ImportedItem(pageTitle: "Doc", url: docURL, faviconPath: doc.path),
                ImportedItem(pageTitle: "Sheet", url: sheetURL, faviconPath: sheet.path),
            ]),
            ImportedItem(pageTitle: "No icon", url: "https://docs.example.com/presentation/d/3/edit"),
            ImportedItem(pageTitle: "Elsewhere", url: "https://other.example.com/", faviconPath: other.path),
        ])]
        let store = AppComposition(clock: ManualScheduler()).store
        let space = store.apply(plan, includeArchive: false, includeSettings: false).spaceIDs[0]
        guard let pinned = store.space(space)?.pinnedContainerID else { return expect(false, "the imported space is there") }
        let tabs = store.tabs(under: pinned)
        func tab(_ url: String) -> SidebarItem? { tabs.first { $0.tab?.url == url } }
        guard let d = tab(docURL), let s = tab(sheetURL) else { return expect(false, "both tabs on the host are imported") }
        expect(d.tab?.faviconKey == FaviconKey.key(site: "docs.example.com", tabID: d.id)
               && s.tab?.faviconKey == FaviconKey.key(site: "docs.example.com", tabID: s.id),
               "an imported tab's icon goes under the tab's own key, not its host's")
        expect(saved(d.tab?.faviconKey) == doc.data && saved(s.tab?.faviconKey) == sheet.data,
               "two imported tabs on one host each keep the icon Arc had for them")
        // Another page on the host loads: its icon becomes the host's (BrowserManager's didLoadFavicon).
        let cache = FaviconCache()
        cache.store(NSImage(contentsOfFile: other.path) ?? NSImage(), forKey: "docs.example.com", persist: false)
        func pixels(_ image: NSImage?) -> Data? { image.flatMap { ZenImporter.faviconPNG($0) } }
        expect(pixels(cache.image(forKey: d.tab?.faviconKey)) == pixels(NSImage(contentsOfFile: doc.path))
               && pixels(cache.image(forKey: s.tab?.faviconKey)) == pixels(NSImage(contentsOfFile: sheet.path)),
               "and neither changes when another page on the host loads its icon")
        expect(saved("docs.example.com") == doc.data, "the host still has an icon, for suggestions and tabs with none")
        expect(tab("https://docs.example.com/presentation/d/3/edit")?.tab?.faviconKey == "docs.example.com",
               "a tab imported with no icon shows its host's until its page loads")
        expect(saved(tab("https://other.example.com/")?.tab?.faviconKey) == other.data, "a tab alone on its host keeps its icon too")
        expect(store.integrityProblems().isEmpty, "the imported sidebar is sound")
    }

    /// Arc keeps icons beyond SidebarItemsFaviconCache: an archived tab's in ArchiveItemsFaviconCache
    /// (md5 of its id, Tests/Fixtures/Arc), and every page it loaded in its profiles' Favicons databases.
    @MainActor
    private static func arcIconsBeyondTheSidebarCache() throws {
        let cached = try Data(contentsOf: ArcImporter.supportDir.appendingPathComponent("ArchiveItemsFaviconCache/8a8bb7cd343aa2ad99b7d762030857a2"))
        let plan = try ArcImporter.plan()
        let old1 = plan.archive.first { $0.url == "https://example.com/old/1" }, old2 = plan.archive.first { $0.url == "https://example.com/old/2" }
        expect(old1?.faviconPath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } == cached, "an archived tab comes with the icon Arc cached for it")
        expect(old2 != nil && old2?.faviconPath == nil, "an archived tab Arc cached no icon for comes without one")

        let store = AppComposition(clock: ManualScheduler()).store
        store.apply(plan, includeArchive: true, includeSettings: false)
        let archived = store.archive.first { $0.item.tab?.url == "https://example.com/old/1" }?.item
        expect(archived?.tab?.faviconKey == archived.map { FaviconKey.key(site: "example.com", tabID: $0.id) },
               "an archived tab's icon goes under its own key, the one the Library's row reads")
        expect(savedFavicon(archived?.tab?.faviconKey) == cached, "and it is the icon Arc had for it")

        // Arc's Favicons database, for the tabs Arc's sidebar cache has no file for.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-arc-icons-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let userData = root.appendingPathComponent("User Data", isDirectory: true)
        makeChromiumUserData(userData, bookmarks: [], icons: [("http://example.com/", 20)])
        let withDatabase = try ArcImporter.plan(favicons: userData)
        func all(_ items: [ImportedItem]) -> [ImportedItem] { items.flatMap { $0.isFolder ? all($0.children) : [$0] } }
        let home = withDatabase.spaces.first { $0.title == "Home" }.map { all($0.pinned) + all($0.today) } ?? []
        let uncached = home.first { $0.url == "https://example.com/today/1" }, news = home.first { $0.url == "https://example.com/news" }
        expect(pixelsWide(uncached?.faviconPath) == 20, "a tab Arc cached no icon for takes its host's from Arc's Favicons database")
        expect(news?.faviconPath != nil && news?.faviconPath == ArcImporter.faviconFile(forItemID: "home-p1"), "a tab Arc cached an icon for keeps that one")
    }

    // promise: #258
    /// Air Traffic Control comes over pointed at the spaces of the same name; a Little Arc that
    /// names a space becomes a Little Window in it (#258).
    @MainActor
    private static func arcLinkRoutes(store: SidebarStore) {
        let work = store.orderedSpaces.first { $0.title == "Work" }!.id, home = store.orderedSpaces.first { $0.title == "Home" }!.id
        let routes = store.settings.linkRoutes.map { "\($0.match.rawValue) \($0.text)" }
        expect(routes == ["contains meet.google.com", "contains work.example.com", "equals example.com/standup"],
               "the routes come over in Arc's order, Meet once")
        let to = { (text: String) in store.settings.linkRoutes.first { $0.text == text }?.destination }
        expect(to("work.example.com") == .littleWindow(space: work), "a Little Arc in Work opens a Little Window in Work")
        expect(to("example.com/standup") == .space(home) && to("meet.google.com") == .mostRecentSpace, "space routes keep their space")
        expect(store.settings.defaultLinkDestination == .littleWindowInUse, "Little Arc as the default stays in the space in use")
    }

    // promise: #768
    /// Arc's domainToProfilePreferences: the profile picked for each site in a Little Arc comes over on the
    /// Cra profile its folder became.
    @MainActor
    private static func arcSiteProfiles(plan: ImportPlan, store: SidebarStore) {
        let work = store.orderedSpaces.first { $0.title == "Work" }!, home = store.orderedSpaces.first { $0.title == "Home" }!
        let client = store.profiles.first { $0.name == "Client" }
        let sites = store.prefs.siteProfiles
        expect(plan.settings.siteProfiles.map { "\($0.site) \($0.folder)" } == ["example.com Default", "other.example.com Profile 9", "work.example.com Profile 2"],
               "the profile picked for each site in a Little Arc comes from the fixture's preferences, not this Mac's Arc")
        expect(sites.profile(for: "https://work.example.com/a") == RememberedProfile(id: client?.id)
               && sites.profile(for: "https://www.example.com/") == RememberedProfile(id: nil),
               "each site keeps its Little Arc profile, on the Cra profile its folder became")
        expect(sites.profile(for: "https://other.example.com/") == nil, "a site on a profile no imported space is on follows the window used last")
        expect(sites.space(for: "https://work.example.com/", lastUsed: home.id, in: store.orderedSpaces) == work.id,
               "so a Little Window on it opens in Work")
    }

    // promise: #131
    /// Arc's spaces keep their profiles (GitHub #131): Work is on "Profile 2", named Client.
    @MainActor
    private static func arcProfiles(plan: ImportPlan, store: SidebarStore) {
        expect(plan.spaces[0].profile == nil && plan.spaces[1].profile == ImportedProfile(folder: "Profile 2", name: "Client"),
               "a space on Arc's Default has no profile, one on Profile 2 carries it with Local State's name")
        let work = store.orderedSpaces.first { $0.title == "Work" }!, home = store.orderedSpaces.first { $0.title == "Home" }!
        let client = store.profiles.first { $0.name == "Client" }
        expect(store.profiles.count == 1 && client != nil && work.profileID == client?.id && home.profileID == nil,
               "the import makes one Cra profile per Arc profile besides Default and puts its spaces on it")
        expect(store.profileDirectoryName(space: work.id) == client?.directoryName && store.profileDirectoryName(space: home.id) == "Default",
               "pages of Work load in the new profile's folder")

        let again = store.apply(plan, includeArchive: false, includeSettings: false)
        expect(store.profiles.count == 1 && again.profiles.folders == ["Default": "Default", "Profile 2": client!.directoryName],
               "importing again reuses the profile of the same name")
        let map = again.profiles
        let all: Set<String> = ["Default", client!.directoryName]

        let exts = ExtensionImporter.extensions(inUserData: ArcImporter.userData)
        func ext(_ name: String) -> ImportableExtension { exts.first { $0.name == name }! }
        expect(exts.map(\.name) == ["Fixture Client", "Fixture Everywhere", "Fixture Personal Off"], "one entry per extension across profiles")
        expect(ext("Fixture Everywhere").profiles == ["Default": true, "Profile 2": true] && ext("Fixture Personal Off").profiles == ["Default": false],
               "each extension knows the profiles that have it and whether it is on there")
        expect(map.extensionProfiles(sources: ext("Fixture Everywhere").sourceProfiles, allFolders: all) == nil,
               "an extension in every profile loads everywhere, as before")
        expect(map.extensionProfiles(sources: ext("Fixture Client").sourceProfiles, allFolders: all) == [client!.directoryName],
               "an extension only Client had loads only in its Cra profile")
        expect(map.extensionProfiles(sources: ext("Fixture Personal Off").sourceProfiles, allFolders: all) == ["Default"],
               "a turned-off extension picked anyway goes where it was installed")
        expect(ExtensionImporter.pinnedIDs(inProfile: ArcImporter.userData.appendingPathComponent("Profile 2")) == [String(repeating: "c", count: 32), String(repeating: "a", count: 32)],
               "Arc's pins of a profile come from its Preferences")
        newProfileDatabases()
        rebuildFromArc(plan: plan)
    }

    // promise: #131
    /// Rebuild from Arc (#131): a sidebar imported before profiles came over gets them afterwards.
    @MainActor
    private static func rebuildFromArc(plan: ImportPlan) {
        let store = AppComposition(clock: ManualScheduler()).store
        var flat = plan
        for i in flat.spaces.indices { flat.spaces[i].profile = nil }
        store.apply(flat, includeArchive: false, includeSettings: false)
        expect(store.profiles.isEmpty, "an import that drops the profiles, as before #131")
        let moves = store.arcProfileMoves(plan)
        expect(moves.map(\.spaceTitle) == ["Work"] && moves.first?.folder == "Profile 2", "only Work is on an Arc profile")
        let map = store.applyArcProfileMoves(moves)
        let work = store.orderedSpaces.first { $0.title == "Work" }!
        let client = store.profiles.first { $0.name == "Client" }
        expect(store.profiles.count == 1 && work.profileID == client?.id && map.folders == ["Default": "Default", "Profile 2": client!.directoryName],
               "Work goes on a Client profile, Home stays on Default")
        expect(store.arcProfileMoves(plan).isEmpty, "a second rebuild finds nothing to move")
    }

    // promise: #131
    /// A profile Chromium hasn't opened gets its sign-in databases with Default's schema (#131).
    private static func newProfileDatabases() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-db-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let template = root.appendingPathComponent("Default/Cookies"), target = root.appendingPathComponent("Profile X/Cookies")
        try? FileManager.default.createDirectory(at: template.deletingLastPathComponent(), withIntermediateDirectories: true)
        var db: OpaquePointer?
        sqlite3_open(template.path, &db)
        sqlite3_exec(db, """
            CREATE TABLE meta(key LONGVARCHAR NOT NULL UNIQUE PRIMARY KEY, value LONGVARCHAR);
            INSERT INTO meta VALUES ('version', '24'), ('last_compatible_version', '24');
            CREATE TABLE cookies(creation_utc INTEGER NOT NULL, host_key TEXT NOT NULL, name TEXT NOT NULL);
            CREATE UNIQUE INDEX cookies_unique_index ON cookies(host_key, name);
            INSERT INTO cookies VALUES (1, 'example.com', 'secret');
            """, nil, nil, nil)
        sqlite3_close(db)
        CredentialImport.createDatabase(target, like: template)
        sqlite3_open(target.path, &db)
        defer { sqlite3_close(db) }
        let meta = SQLite.rows(db, "SELECT key, value FROM meta ORDER BY key").compactMap { $0["value"] as? String }
        let objects = SQLite.rows(db, "SELECT name FROM sqlite_master WHERE name NOT LIKE 'sqlite_%' ORDER BY name").compactMap { $0["name"] as? String }
        expect(meta == ["24", "24"] && objects == ["cookies", "cookies_unique_index", "meta"]
               && SQLite.rows(db, "SELECT 1 FROM cookies").isEmpty, "same tables, index and schema version, none of Default's rows")
        let mode = { (u: URL) in (try? FileManager.default.attributesOfItem(atPath: u.path)[.posixPermissions] as? Int) ?? 0 }
        expect(mode(target) == 0o600 && mode(target.deletingLastPathComponent()) == 0o700, "owner only, like Chromium's own")
    }

    /// Dia's plan brings each tab's icon from its profiles' Favicons databases, here a copy of the
    /// fixture's sidebar beside a Favicons made for the test.
    @MainActor
    private static func diaIconsFromItsDatabase() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-dia-icons-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let userData = root.appendingPathComponent("User Data", isDirectory: true)
        makeChromiumUserData(userData, bookmarks: [], icons: [("https://example.com/", 21)])
        let fixture = DiaImporter.userData.appendingPathComponent("Profile 1", isDirectory: true)
        let profile = userData.appendingPathComponent("Profile 1", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        for name in ["tabs.db", "tabs.db-wal"] {
            try FileManager.default.copyItem(at: fixture.appendingPathComponent(name), to: profile.appendingPathComponent(name))
        }
        let plan = try DiaImporter.plan(secret: "cra-test-secret", userData: userData)
        let home = plan.spaces.first { $0.title == "Home" }
        expect(home?.favorites.first?.url == "https://example.com/mail" && pixelsWide(home?.favorites.first?.faviconPath) == 21,
               "a Dia tab comes with its host's icon from Dia's Favicons database")
    }

    /// Dia 1.55's encrypted sidebar (Tests/Fixtures/Dia, rebuilt by its make-fixture.py with the
    /// Safe Storage secret "cra-test-secret").
    @MainActor
    private static func diaImport() throws {
        expect(DiaImporter.isAvailable && DiaImporter.hasEncryptedSidebar, "a profile with tabs.db counts as Dia data")
        let plan = try DiaImporter.plan(secret: "cra-test-secret")
        expect(plan.spaces.map(\.title) == ["Home", "Work"], "Dia's spaces come over oldest first")
        let home = plan.spaces[0], work = plan.spaces[1]
        expect(home.theme?.colors.first == "#F8D558" && work.theme == nil, "a named Dia colour becomes a theme, neutral the default")
        expect(home.favorites.compactMap(\.url) == ["https://example.com/mail", "https://example.com/calendar"]
               && work.favorites.compactMap(\.url) == ["https://example.com/jira"], "each space keeps its own favorites")
        expect(home.pinned.map { $0.customTitle ?? $0.pageTitle } == ["Docs", "Reading"], "pinned tabs and folders in order, deleted ones left out")
        expect(home.pinned[0].pageTitle == "Docs page", "a renamed pinned tab keeps both titles")
        let reading = home.pinned[1]
        expect(reading.isFolder && reading.children.count == 2 && reading.children[1].isFolder
               && reading.children[1].children.compactMap(\.url) == ["https://example.com/read/deep"], "folders nest")
        expect(home.today.compactMap(\.url) == ["https://example.com/open", "https://example.com/left", "https://example.com/right",
                                                "file:///Users/me/notes.html", "javascript:void(document.title)", "chrome://settings/"],
               "open tabs come over whatever their address, a split as its tabs; a new tab page, about:blank and blob: left out")
        expect(work.pinned.count == 1 && work.pinned[0].customTitle == "Tools" && work.pinned[0].children.compactMap(\.url) == ["https://example.com/ci"],
               "edits still in the -wal come over")

        expect((try? DiaImporter.plan(secret: "wrong")) == nil,
               "a secret that opens no sidebar database fails instead of importing Dia's stale older files")
        expect((try? DiaImporter.plan())?.spaces.contains { $0.title == "Home" } == false, "without the secret nothing comes from the database")
        let legacy = try DiaImporter.plan()
        expect(legacy.favorites.compactMap(\.url) == ["https://example.com/mail", "chrome://settings/"],
               "Dia's older files: favorites whatever their address, about:blank and a new tab page left out")
        expect(legacy.spaces.first { $0.title == "Dia" }?.today.compactMap(\.url)
               == ["https://example.com/open", "file:///Users/me/notes.html", "javascript:void(document.title)", "chrome://settings/"],
               "Dia's older open tabs whatever their address; about:blank, a new tab page and blob: left out")
        expect(legacy.spaces.first { $0.title == "Reading" }?.pinned.compactMap(\.url)
               == ["https://example.com/read", "file:///Users/me/notes.html", "javascript:void(document.title)"],
               "a bookmarks bar folder keeps its file: and javascript: bookmarks, about:blank and blob: left out")
        expect(!legacy.spaces.contains { $0.title == "Blank" }, "a folder of only blank bookmarks is left out")

        let clock = ManualScheduler()
        let composition = AppComposition(clock: clock)
        let result = composition.store.apply(plan, includeArchive: false, includeSettings: false)
        expect(result.spaces == 2 && result.folders == 3, "applying adds both spaces and their folders")
        let homeSpace = composition.store.orderedSpaces.first { $0.title == "Home" }
        let open = homeSpace.map { composition.store.tabs(under: $0.todayContainerID) } ?? []
        expect(open.count == 6 && open.allSatisfy { $0.tab?.timeLastActiveAt == clock.now },
               "open tabs count as active at the import, so auto-archive doesn't take weeks-old Dia tabs at once")
        expect(composition.store.integrityProblems().isEmpty, "the imported sidebar is sound")
    }

    // MARK: Import reports

    /// After an import the tabs, favorites and archive tiles each read "N of M" of their own kind,
    /// on the base each showed before the import, so the numbers match. Arc's profile leaves
    /// nothing out, and a second import of it counts what Cra already has as copied, not as skipped.
    @MainActor
    private static func arcImportReport() throws {
        let plan = try ArcImporter.plan()
        let store = AppComposition(clock: ManualScheduler()).store
        let first = store.apply(plan, includeArchive: true, includeSettings: false)
        let pinnedAndToday = plan.spaces.reduce(0) { $0 + $1.itemCount }
        expect(first.report[.tabs] == ImportReport(.tabs, copied: pinnedAndToday) && first.report[.tabs].summary == "\(pinnedAndToday) of \(pinnedAndToday) tabs",
               "the tabs tile counts the pinned and Today tabs, as before the import")
        let download = ImportSkip(title: "Download", url: "blob:https://example.com/5f1c", reason: .onlyInItsBrowser, kind: .archive)
        expect(first.report[.archive] == ImportReport(.archive, copied: 2, skipped: [download]) && first.report[.archive].summary == "2 of 3 tabs",
               "the archive tile counts the archive, its blob: tab listed")
        // Work's profile has no favorites of its own, so it shows Default's: Arc holds two favorites.
        expect(plan.spaces.allSatisfy { $0.favorites.count == 2 } && first.report[.favorites] == ImportReport(.favorites, copied: 2),
               "a space borrowing another profile's favorites counts them in that list, once, as Arc holds them")
        let again = store.apply(plan, includeArchive: true, includeSettings: false)
        expect(again.archived == 0, "the second import finds the archive already in Cra")
        expect(again.report == first.report, "and counts it as copied: the same N of N, nothing listed")
        for id in first.spaceIDs + again.spaceIDs { store.deleteSpace(id) }

        // Favorites that belong to no space go to the focused one, where the second import finds them.
        var favorites = ImportPlan(source: "Arc")
        favorites.favorites = plan.spaces[0].favorites
        _ = store.apply(favorites, includeArchive: false, includeSettings: false)
        let twice = store.apply(favorites, includeArchive: false, includeSettings: false)
        expect(twice.tabs == 0 && twice.report[.favorites] == ImportReport(.favorites, copied: favorites.favorites.count),
               "favorites Cra already has count as copied, not as skipped")
    }

    /// Two Arc spaces on one profile share its favorites: the favorites tile counts the profile's
    /// two, not two per space.
    @MainActor
    private static func arcSpacesOnOneProfileCountTheirFavoritesOnce() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        var sidebar = root["sidebar"] as! [String: Any]
        var containers = sidebar["containers"] as! [[String: Any]]
        let main = containers.firstIndex { $0["spaces"] != nil }!
        var spaces = containers[main]["spaces"] as! [Any]
        let work = spaces.firstIndex { ($0 as? String) == "work" }! + 1
        var space = spaces[work] as! [String: Any]
        space["profile"] = ["default": true]
        spaces[work] = space
        containers[main]["spaces"] = spaces
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let plan = try ArcImporter.plan(sidebar: JSONSerialization.data(withJSONObject: root))
        expect(plan.spaces.map(\.profile) == [nil, nil] && plan.spaces.allSatisfy { $0.favorites.compactMap(\.url) == ["https://example.com/mail", "https://example.com/calendar"] },
               "both spaces are on Default and carry its favorites")
        expect(plan.report(includeArchive: false)[.favorites].summary == "2 of 2 favorites", "the tile reads the profile's two")
        let store = AppComposition(clock: ManualScheduler()).store
        let result = store.apply(plan, includeArchive: false, includeSettings: false)
        expect(result.report[.favorites] == ImportReport(.favorites, copied: 2), "and so does the import")
        for id in result.spaceIDs { store.deleteSpace(id) }
    }

    /// Cra takes Arc's newest 1500 archived tabs; the older ones are listed, and only when the
    /// archive comes over.
    @MainActor
    private static func arcArchiveBeyondItsLimitIsListed() throws {
        let sidebar = try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json"))
        let entries: [[String: Any]] = (0...1500).map { i in
            ["sidebarItem": ["id": "old-\(i)", "data": ["tab": ["savedURL": "https://example.com/old/\(i)", "savedTitle": "Old \(i)"]]],
             "reason": "auto", "archivedAt": 700000000.0 + Double(i)]
        }
        let plan = try ArcImporter.plan(sidebar: sidebar, archive: JSONSerialization.data(withJSONObject: ["items": entries]))
        expect(plan.archive.count == 1500 && plan.archiveSkipped == [ImportSkip(title: "Old 0", url: "https://example.com/old/0", reason: .olderArchive(limit: 1500), kind: .archive)],
               "the oldest archived tab past 1500 is listed as left out")
        var archiveOnly = ImportPlan(source: "Arc")
        archiveOnly.archiveSkipped = plan.archiveSkipped
        let store = AppComposition(clock: ManualScheduler()).store
        expect(!store.apply(archiveOnly, includeArchive: false, includeSettings: false).report[.archive].isShown,
               "without the archive its skipped tabs aren't listed")
        let archiveKept = store.apply(archiveOnly, includeArchive: true, includeSettings: false).report
        expect(archiveKept[.archive].isShown && archiveKept[.archive].skipped == plan.archiveSkipped && archiveKept[.archive].skipped.first?.kind == .archive,
               "with the archive and no space picked, they are on the archive tile")
    }

    /// A tab someone put in Arc's GitHub live folder by hand stands for no pull request: the live
    /// folder refills itself and leaves it out, and the list says so.
    @MainActor
    private static func arcTabThatIsNoLiveItemIsListed() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        var sidebar = root["sidebar"] as! [String: Any]
        var containers = sidebar["containers"] as! [[String: Any]]
        let main = containers.firstIndex { $0["spaces"] != nil }!
        var items = containers[main]["items"] as! [Any]
        func item(_ id: String, children: [String] = [], data: [String: Any]) -> [Any] {
            [id, ["id": id, "childrenIds": children, "createdAt": 800000000.0, "data": data] as [String: Any]]
        }
        let pr = "https://github.com/example/app/pull/1"
        items += item("work-prs", children: ["work-pr1", "work-notes", "work-group"],
                      data: ["list": ["automaticLiveFolderData": ["dataSource": ["github": [String: Any]()]]]])
        items += item("work-pr1", data: ["tab": ["savedURL": pr, "savedTitle": "Pull 1", "liveItemID": ["url": ["_0": pr]]]])
        items += item("work-notes", data: ["tab": ["savedURL": "https://example.com/notes", "savedTitle": "Notes"]])
        items += item("work-group", children: ["work-deep"], data: ["list": [String: Any]()])
        items += item("work-deep", data: ["tab": ["savedURL": "https://example.com/deep", "savedTitle": "Deep"]])
        let pinned = items.firstIndex { ($0 as? String) == "work-pinned" }! + 1
        var container = items[pinned] as! [String: Any]
        container["childrenIds"] = ["work-prs"]
        items[pinned] = container
        containers[main]["items"] = items
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let plan = try ArcImporter.plan(sidebar: JSONSerialization.data(withJSONObject: root))

        let store = AppComposition(clock: ManualScheduler()).store
        let result = store.apply(plan, includeArchive: false, includeSettings: false)
        let tabs = plan.spaces.reduce(0) { $0 + $1.itemCount }
        expect(result.report[.tabs].skipped == [ImportSkip(title: "Notes", url: "https://example.com/notes", reason: .notALiveItem),
                                                ImportSkip(title: "Deep", url: "https://example.com/deep", reason: .notALiveItem)],
               "the hand-added tab, and the tab in a hand-added folder, are listed as no item of the live folder")
        expect(result.report[.tabs].total == tabs && result.report[.tabs].copied == tabs - 2, "and count in the total only")
        for id in result.spaceIDs { store.deleteSpace(id) }
    }

    /// Dia's archive takes web pages only (Tests/Fixtures/Dia/StorableAutoArchive.json has a
    /// chrome:// one): the page is listed when the archive comes over.
    @MainActor
    private static func diaImportReport() throws {
        let plan = try DiaImporter.plan(secret: "cra-test-secret")
        expect(plan.archive.map(\.url) == ["https://example.com/archived"]
               && plan.archiveSkipped == [ImportSkip(title: "Settings", url: "chrome://settings/", reason: .notAWebPage, kind: .archive)],
               "a chrome:// page in Dia's archive is left out and listed; its blank and new tab pages were never tabs")
        let store = AppComposition(clock: ManualScheduler()).store
        let without = store.apply(plan, includeArchive: false, includeSettings: false)
        expect(!without.report[.archive].isShown
               && without.report[.tabs].skipped == [ImportSkip(title: "Odd 4", url: "blob:https://example.com/5f1c", reason: .onlyInItsBrowser)],
               "without the archive, only the sidebar's blob: tab is listed")
        let with = store.apply(plan, includeArchive: true, includeSettings: false)
        expect(with.report[.archive] == ImportReport(.archive, copied: 1, skipped: plan.archiveSkipped)
               && with.report[.archive].summary == "1 of 2 tabs", "with it, the archive tile lists its chrome:// page")
        expect(with.report[.tabs] == without.report[.tabs], "and the tabs tile stays as it was")
        var noSpaces = plan
        noSpaces.spaces = []
        expect(plan.report(includeArchive: true)[.archive].isShown && noSpaces.report(includeArchive: true)[.archive].skipped == plan.archiveSkipped,
               "with every space left out, the archive tile still shows its skipped page")
        for id in without.spaceIDs + with.spaceIDs { store.deleteSpace(id) }
    }

    /// A skip for a tab or bookmark at Cra's own cra: address, which an import leaves behind (#742).
    private static func cra(_ title: String, _ url: String, _ kind: ImportKind = .tabs) -> ImportSkip {
        ImportSkip(title: title, url: url, reason: .craAddress, kind: kind)
    }

    /// Ardia's cra: tab and blob: tab (Tests/Fixtures/Ardia) are listed; its empty new tab and blank
    /// page were never tabs, and its other addresses come over (#742).
    @MainActor
    private static func ardiaImportReport() throws {
        let plan = try ArdiaImporter.plan()
        let download = ImportSkip(title: "Download", url: "blob:https://design.example.com/5f1c", reason: .onlyInItsBrowser)
        expect(plan.spaces.map(\.skipped) == [[cra("Cra Settings", "cra://settings")], [download], []],
               "Ardia's cra: tab and blob: tab are listed in their spaces, nothing else")
        let store = AppComposition(clock: ManualScheduler()).store
        let result = store.apply(plan, includeArchive: false, includeSettings: false)
        let tabs = plan.spaces.reduce(0) { $0 + $1.itemCount }
        expect(result.report[.tabs].copied == tabs && result.report[.tabs].summary == "\(tabs) of \(tabs + 2) tabs", "two short of the total")
        var picked = plan
        picked.spaces.removeFirst()
        let others = store.apply(picked, includeArchive: false, includeSettings: false)
        expect(others.report[.tabs].skipped == [download], "a space not picked lists nothing of its own")
        for id in result.spaceIDs + others.spaceIDs { store.deleteSpace(id) }
    }

    /// Yab's about:blank tab (Tests/Fixtures/Yab/session.json) is a blank page, never a tab: nothing
    /// is listed.
    private static func yabImportReport() throws {
        let plan = try YabImporter.plan(supportDir: YabImporter.supportDir, pinsInEverySpace: false)
        expect(plan.spaces.allSatisfy(\.skipped.isEmpty), "Yab's blank page is not listed")
    }

    /// The favorites tile counts favorites as the source holds them: two Yab
    /// spaces that each own a github.com tile bring two, the shared tiles every space shows bring
    /// theirs once. Both spaces here sign in on one Chromium profile.
    private static func yabFavoritesCountAsYabHoldsThem() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("cra-yab-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let work = "4D3C2B1A-0000-4000-8000-0000000000AA"
        func write(_ name: String, _ json: Any) throws { try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent(name)) }
        let tiles: [[String: Any]] = [["id": "g", "url": "https://github.com/", "title": "GitHub", "pin": "G"],
                                      ["id": "c", "url": "cra://settings", "title": "Cra Settings", "pin": "C"]]
        try write("spaces.json", [["id": YabImporter.firstID, "name": "Personal"], ["id": work, "name": "Work"]])
        try write("session.json", ["tabs": tiles + [["id": "n", "url": "https://news.example.com/", "title": "News"]]])
        try write("session-\(work).json", ["tabs": tiles + [["id": "d", "url": "https://design.example.com/", "title": "Design"]]])
        try write("session-\(YabImporter.sharedPinsID).json", ["tabs": tiles])
        let settings = cra("Cra Settings", "cra://settings", .favorites)

        let own = try YabImporter.plan(supportDir: dir, pinsInEverySpace: false).report(includeArchive: false)[.favorites]
        expect(own.copied == 2 && own.skipped == [settings, settings], "each space's own tiles count for that space: 2 GitHub tiles, 2 rows")
        let shared = try YabImporter.plan(supportDir: dir, pinsInEverySpace: true).report(includeArchive: false)[.favorites]
        expect(shared.copied == 1 && shared.skipped == [settings], "the shared tiles count once, though every space shows them")
    }

    /// Arc's cra: tab, favorite and archived tab are listed, each on its own tile.
    private static func arcCraAddressesAreListed() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        var sidebar = root["sidebar"] as! [String: Any]
        var containers = sidebar["containers"] as! [[String: Any]]
        let main = containers.firstIndex { $0["spaces"] != nil }!
        var items = containers[main]["items"] as! [Any]
        func add(_ id: String, _ url: String, _ title: String, to container: String) {
            items += [id, ["id": id, "childrenIds": [String](), "createdAt": 800000000.0, "data": ["tab": ["savedURL": url, "savedTitle": title]]] as [String: Any]]
            let at = items.firstIndex { ($0 as? String) == container }! + 1
            var c = items[at] as! [String: Any]
            c["childrenIds"] = (c["childrenIds"] as? [String] ?? []) + [id]
            items[at] = c
        }
        add("home-cra", "cra://settings", "Cra Settings", to: "home-today")
        add("fav-cra", "cra://downloads", "Downloads", to: "fav")
        containers[main]["items"] = items
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let archive = ["items": [["sidebarItem": ["id": "old-cra", "data": ["tab": ["savedURL": "cra://history", "savedTitle": "History"]]],
                                  "reason": "auto", "archivedAt": 700000000.0]]]
        let plan = try ArcImporter.plan(sidebar: JSONSerialization.data(withJSONObject: root), archive: JSONSerialization.data(withJSONObject: archive))
        let report = plan.report(includeArchive: true)
        expect(report[.tabs].skipped == [cra("Cra Settings", "cra://settings")], "a cra: tab is listed on the tabs tile")
        expect(plan.skipped.isEmpty && report[.favorites].skipped.map(\.url) == ["cra://downloads"] && report[.favorites].total == 3,
               "a cra: favorite on the favorites tile, once, though Home and Work both show Default's Top Apps")
        expect(report[.archive].skipped == [cra("History", "cra://history", .archive)], "a cra: archived tab on the archive tile")
        expect(plan.selecting(spaces: [1], favorites: true).report(includeArchive: false)[.favorites].skipped.map(\.url) == ["cra://downloads"]
               && !plan.selecting(spaces: [], favorites: true).report(includeArchive: false)[.favorites].isShown,
               "it shows with a space that shows its list, and not with none picked")

        // Work's profile with Top Apps of its own, holding the same cra: favorite: Arc holds two.
        let work: [String: Any] = ["custom": ["_0": ["directoryBasename": "Profile 2", "machineID": "fixture-machine"]]]
        items += ["fav2", ["id": "fav2", "childrenIds": ["fav2-cra"], "createdAt": 800000000.0,
                           "data": ["itemContainer": ["containerType": ["topApps": ["_0": work]]]]] as [String: Any]]
        items += ["fav2-cra", ["id": "fav2-cra", "childrenIds": [String](), "createdAt": 800000000.0,
                               "data": ["tab": ["savedURL": "cra://downloads", "savedTitle": "Downloads"]]] as [String: Any]]
        containers[main]["items"] = items
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let two = try ArcImporter.plan(sidebar: JSONSerialization.data(withJSONObject: root), archive: nil).report(includeArchive: false)[.favorites]
        expect(two.skipped.map(\.url) == ["cra://downloads", "cra://downloads"], "a left-out favorite counts once per Top Apps container")
    }

    /// Dia's sidebar database (a plain one made here, in tabs.db's schema): a cra: tab is listed, a
    /// cra: favorite on the favorites tile.
    private static func diaSidebarCraAddressesAreListed() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("cra-dia-\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: file) }
        var db: OpaquePointer?
        sqlite3_open(file.path, &db)
        sqlite3_exec(db, """
            CREATE TABLE spaces (id TEXT PRIMARY KEY, title TEXT, creation_date DATE, theme TEXT);
            CREATE TABLE nodes (id INTEGER PRIMARY KEY, kind TEXT, entity_id TEXT, parent_id INTEGER, "order" INTEGER, deleted_at DATETIME, space_id TEXT);
            CREATE TABLE tabs (id TEXT PRIMARY KEY, node_id INTEGER, creation_date DATE);
            CREATE TABLE tab_groups (id TEXT PRIMARY KEY, node_id INTEGER, title TEXT);
            CREATE TABLE content_panes (id TEXT PRIMARY KEY, node_id INTEGER, custom_title TEXT);
            CREATE TABLE web_contents (id INTEGER PRIMARY KEY, content_pane_id TEXT, url TEXT, title TEXT);
            INSERT INTO spaces VALUES ('home', 'Home', '2026-10-01 08:00:00.000', 'neutral');
            INSERT INTO nodes VALUES (1, 'window', 'w', NULL, 0, NULL, 'home'), (2, 'tab', 't-2', 1, 0, NULL, 'home'), (3, 'content_pane', 'p-3', 2, 0, NULL, 'home'),
                (4, 'tab', 't-4', 1, 1, NULL, 'home'), (5, 'content_pane', 'p-5', 4, 0, NULL, 'home'),
                (6, 'favorites', 'f', NULL, 1, NULL, 'home'), (7, 'tab', 't-7', 6, 0, NULL, 'home'), (8, 'content_pane', 'p-8', 7, 0, NULL, 'home');
            INSERT INTO content_panes VALUES ('p-3', 3, NULL), ('p-5', 5, NULL), ('p-8', 8, NULL);
            INSERT INTO web_contents (content_pane_id, url, title) VALUES ('p-3', 'https://example.com/open', 'Open'),
                ('p-5', 'cra://settings', 'Cra Settings'), ('p-8', 'cra://downloads', 'Downloads');
            """, nil, nil, nil)
        sqlite3_close(db)
        let spaces = SQLiteSnapshot(copying: file).map(DiaSidebar.spaces(in:)) ?? []
        expect(spaces.first?.today.compactMap(\.url) == ["https://example.com/open"], "Dia's web page comes over")
        expect(spaces.first?.skipped == [cra("Downloads", "cra://downloads", .favorites), cra("Cra Settings", "cra://settings")],
               "its cra: favorite and cra: tab are listed, each on its own tile")
    }

    /// Dia's files from before 1.55 (a copy of Tests/Fixtures/Dia with cra: entries added): its open
    /// tabs and favorites, and its bookmarks bar, list what they leave out, each on its tile.
    private static func diaLegacyLeftOutAreListed() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("cra-dia-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        try fm.copyItem(at: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Dia"), to: dir)
        func tab(_ url: String, _ title: String) -> [String: Any] {
            ["contents": [["variant": ["webContent": ["_0": ["url": url, "title": title]]]]], "creationDate": 800000000.0]
        }
        let containers = dir.appendingPathComponent("StorableProfileContainers.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: containers)) as! [String: Any]
        var list = root["containers"] as! [[String: Any]]
        list[0]["tabs"] = (list[0]["tabs"] as! [Any]) + [tab("cra://downloads", "Downloads")]
        list[1]["tabs"] = (list[1]["tabs"] as! [Any]) + [tab("cra://settings", "Cra Settings")]
        root["containers"] = list
        try JSONSerialization.data(withJSONObject: root).write(to: containers)
        let bookmarksFile = dir.appendingPathComponent("User Data/Profile 1/Bookmarks")
        var bookmarks = try JSONSerialization.jsonObject(with: Data(contentsOf: bookmarksFile)) as! [String: Any]
        var roots = bookmarks["roots"] as! [String: Any], bar = roots["bookmark_bar"] as! [String: Any]
        var kids = bar["children"] as! [[String: Any]]
        kids[0]["children"] = (kids[0]["children"] as! [Any]) + [["type": "url", "name": "History", "url": "cra://history"]]
        kids.append(["type": "url", "name": "Extensions", "url": "cra://extensions"])
        bar["children"] = kids
        roots["bookmark_bar"] = bar
        bookmarks["roots"] = roots
        try JSONSerialization.data(withJSONObject: bookmarks).write(to: bookmarksFile)

        let plan = try DiaImporter.plan(supportDir: dir, userData: dir.appendingPathComponent("User Data"))
        let download = ImportSkip(title: "Download", url: "blob:https://example.com/5f1c", reason: .onlyInItsBrowser)
        let all = plan.report(includeArchive: false)
        expect(all[.favorites].skipped == [cra("Downloads", "cra://downloads", .favorites), cra("Extensions", "cra://extensions", .favorites)]
               && Set(all[.tabs].skipped.map(\.url)) == ["blob:https://example.com/5f1c", "cra://settings", "cra://history"] && all[.tabs].skipped.count == 4,
               "a favorite and the bar's own bookmark go on the favorites tile, open tabs and folders' bookmarks on the tabs tile")
        let dia = plan.spaces.firstIndex { $0.title == "Dia" }, reading = plan.spaces.firstIndex { $0.title == "Reading" }
        expect(dia.map { plan.spaces[$0].skipped } == [download, cra("Cra Settings", "cra://settings")]
               && reading.map { plan.spaces[$0].skipped } == [download, cra("History", "cra://history")],
               "the open tabs' rows go with the Dia space, a folder's with the space it becomes")
        let nothing = plan.selecting(spaces: [], favorites: false).report(includeArchive: false)
        expect(!nothing[.tabs].isShown && !nothing[.favorites].isShown, "with no space and no favorites picked, nothing is listed")
    }

    /// Chrome's file: bookmark and its other addresses come over (#742); its new tab page and closed
    /// tab were never tabs. A cra: bookmark or tab is listed. A session or Bookmarks file that can't
    /// be read is one row.
    @MainActor
    private static func chromiumImportReport() {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Chromium")
        let plan = (try? ChromiumImporter.plan(browser: "Chrome", userData: fixtures)) ?? ImportPlan(source: "Chrome")
        let download = ImportSkip(title: "Download", url: "blob:https://example.com/5f1c", reason: .onlyInItsBrowser)
        expect(plan.spaces.count == 1 && plan.spaces.first?.skipped == [download, download],
               "Chrome's blob: bookmark and blob: tab are listed; its new tab page, blank page and closed tab are not")

        // SNSS version 1: one tab at a cra: address. Pickles: uint32 payload size, then 4-byte aligned fields.
        func pickle(_ fields: [Data]) -> Data { let body = fields.reduce(Data(), +); return le32(UInt32(body.count)) + body }
        func le32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.littleEndian) { Data($0) } }
        func string(_ s: String) -> Data { let d = Data(s.utf8); return le32(UInt32(d.count)) + d + Data(count: (4 - d.count % 4) % 4) }
        func string16(_ s: String) -> Data {
            let units = Array(s.utf16), d = units.reduce(Data()) { $0 + withUnsafeBytes(of: $1.littleEndian) { Data($0) } }
            return le32(UInt32(units.count)) + d + Data(count: (4 - d.count % 4) % 4)
        }
        func command(_ id: UInt8, _ body: Data) -> Data { withUnsafeBytes(of: UInt16(body.count + 1).littleEndian) { Data($0) } + Data([id]) + body }
        let session = Data("SNSS".utf8) + le32(1)
            + command(6, pickle([le32(7), le32(0), string("cra://settings"), string16("Cra Settings")]))
            + command(7, le32(7) + le32(0))
        var rows: [ImportSkip] = []
        _ = ChromiumImporter.parseSession(session, file: "Session_8") { rows.append($0) }
        expect(rows == [cra("Cra Settings", "cra://settings")], "a cra: tab in the session is listed")
        rows = []
        _ = ChromiumImporter.parseSession(Data("SNSS".utf8) + Data([4, 0, 0, 0]) + Data(repeating: 1, count: 16), file: "Session_9") { rows.append($0) }
        expect(rows == [.unreadable("Open tabs", file: "Session_9")], "an encrypted session is one row")

        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cra-unreadable-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        try? fm.createDirectory(at: root.appendingPathComponent("Default"), withIntermediateDirectories: true)
        try? fm.createDirectory(at: root.appendingPathComponent("Profile 1"), withIntermediateDirectories: true)
        try? Data(#"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"Docs","url":"https://docs.example.com/"},{"type":"url","name":"Cra Settings","url":"cra://settings"}]}}}"#.utf8)
            .write(to: root.appendingPathComponent("Profile 1/Bookmarks"))
        let bookmarks = root.appendingPathComponent("Default/Bookmarks")
        try? Data("{not json".utf8).write(to: bookmarks)
        let broken = (try? ChromiumImporter.plan(browser: "Chrome", userData: root)) ?? ImportPlan(source: "Chrome")
        expect(broken.spaces.map(\.skipped) == [[cra("Cra Settings", "cra://settings")]], "a cra: bookmark is listed in its profile's space")
        expect(broken.skipped == [.unreadable("Bookmarks", file: bookmarks.path)],
               "a damaged Bookmarks file is one row, kept though the profile brings no space")
        var noSpaces = broken
        noSpaces.spaces = []
        expect(noSpaces.report(includeArchive: false)[.tabs].isShown, "with no space to import, the tabs tile still shows, for the row")
        let result = AppComposition(clock: ManualScheduler()).store.apply(noSpaces, includeArchive: false, includeSettings: false)
        expect(result.report[.tabs].skipped == broken.skipped && result.report[.tabs].summary == "No tabs", "the row shows without a count")
    }

    /// A Firefox or Zen profile in a temporary folder: profiles.ini and the given files.
    private static func firefoxProfile(_ files: [String: Data]) -> (root: URL, profile: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cra-firefox-\(UUID().uuidString)", isDirectory: true)
        let profile = root.appendingPathComponent("abc.default-release", isDirectory: true)
        try? fm.createDirectory(at: profile.appendingPathComponent("sessionstore-backups"), withIntermediateDirectories: true)
        try? Data("[Profile0]\nName=default-release\nIsRelative=1\nPath=abc.default-release\nDefault=1\n".utf8)
            .write(to: root.appendingPathComponent("profiles.ini"))
        fm.createFile(atPath: profile.appendingPathComponent("places.sqlite").path, contents: Data())
        for (name, data) in files { try? data.write(to: profile.appendingPathComponent(name)) }
        return (root, profile)
    }

    /// Firefox's cra: and place: bookmarks and cra: and blob: tabs are listed; a session store that
    /// can't be read is one row.
    private static func firefoxImportReport() {
        let session = (try? mozLz4(["windows": [["tabs": [
            ["entries": [["url": "https://example.com/open", "title": "Open"]], "index": 1],
            ["entries": [["url": "cra://history", "title": "History"]], "index": 1],
            ["entries": [["url": "blob:https://example.com/5f1c", "title": "Download"]], "index": 1],
        ]]]])) ?? Data()
        let (root, profile) = firefoxProfile(["sessionstore.jsonlz4": session])
        defer { try? FileManager.default.removeItem(at: root) }
        var db: OpaquePointer?
        sqlite3_open(profile.appendingPathComponent("places.sqlite").path, &db)
        sqlite3_exec(db, """
            CREATE TABLE moz_places(id INTEGER PRIMARY KEY, url TEXT, title TEXT);
            CREATE TABLE moz_bookmarks(id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, position INTEGER, title TEXT, dateAdded INTEGER, guid TEXT);
            INSERT INTO moz_places VALUES (1, 'https://example.com/docs', 'Docs'), (2, 'cra://settings', NULL), (3, 'place:sort=8&maxResults=10', NULL);
            INSERT INTO moz_bookmarks VALUES (1, 2, NULL, 0, 0, '', 0, 'root________'), (2, 2, NULL, 1, 0, 'toolbar', 0, 'toolbar_____'),
                (3, 1, 1, 2, 0, 'Docs', 0, 'b1'), (4, 1, 2, 2, 1, 'Cra Settings', 0, 'b2'), (5, 1, 3, 2, 2, 'Most Visited', 0, 'b3');
            """, nil, nil, nil)
        sqlite3_close(db)
        let plan = (try? FirefoxImporter.plan(browser: "Firefox", root: root)) ?? ImportPlan(source: "Firefox")
        expect(plan.spaces.first?.pinned.map(\.url) == ["https://example.com/docs"] && plan.spaces.first?.today.map(\.url) == ["https://example.com/open"],
               "Firefox's web pages come over")
        expect(plan.spaces.first?.skipped == [cra("Cra Settings", "cra://settings"),
                                              ImportSkip(title: "Most Visited", url: "place:sort=8&maxResults=10", reason: .onlyInItsBrowser),
                                              cra("History", "cra://history"),
                                              ImportSkip(title: "Download", url: "blob:https://example.com/5f1c", reason: .onlyInItsBrowser)],
               "its cra: bookmark, place: query, cra: tab and blob: tab are listed")

        let (brokenRoot, brokenProfile) = firefoxProfile(["sessionstore.jsonlz4": Data("mozLz40\0garbage".utf8)])
        defer { try? FileManager.default.removeItem(at: brokenRoot) }
        var rows: [ImportSkip] = []
        _ = FirefoxImporter.openTabs(profile: brokenProfile) { rows.append($0) }
        expect(rows == [.unreadable("Open tabs", file: brokenProfile.appendingPathComponent("sessionstore.jsonlz4").path)],
               "a session store that can't be read is one row")
    }

    /// Zen's cra: tab is listed, its cra: Essential on the favorites tile; its empty and glance tabs
    /// were never tabs.
    private static func zenImportReport() {
        let sidebar = (try? mozLz4(["spaces": [["uuid": "s1", "name": "Home", "position": 0], ["uuid": "s2", "name": "Work", "position": 1]], "folders": [], "tabs": [
            ["zenWorkspace": "s2", "entries": [["url": "https://example.com/b", "title": "B"]], "index": 1],
            ["zenWorkspace": "s1", "entries": [["url": "https://example.com/a", "title": "A"]], "index": 1],
            ["zenWorkspace": "s1", "entries": [["url": "cra://downloads", "title": "Downloads"]], "index": 1],
            ["zenWorkspace": "s1", "zenEssential": true, "entries": [["url": "cra://settings", "title": "Cra Settings"]], "index": 1],
            ["zenWorkspace": "s1", "zenIsEmpty": true, "entries": [["url": "about:blank", "title": ""]], "index": 1],
            ["zenWorkspace": "s1", "zenIsGlance": true, "entries": [["url": "cra://history", "title": "History"]], "index": 1],
        ]])) ?? Data()
        let (root, _) = firefoxProfile(["zen-sessions.jsonlz4": sidebar])
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = (try? ZenImporter.plan(root: root)) ?? ImportPlan(source: "Zen")
        expect(plan.spaces.first?.today.map(\.url) == ["https://example.com/a"], "Zen's web page comes over")
        let settings = cra("Cra Settings", "cra://settings", .favorites)
        expect(plan.spaces.first?.skipped == [cra("Downloads", "cra://downloads"), settings],
               "its cra: tab is listed on the tabs tile, its cra: Essential on the favorites tile, the empty and glance tabs nowhere")
        var work = plan
        work.spaces.removeFirst()
        expect(work.spaces.map(\.title) == ["Work"] && work.report(includeArchive: false)[.favorites].skipped == [settings],
               "the Essentials come with every space, and so does the row of the one left out")
        expect(plan.report(includeArchive: false)[.favorites].skipped == [settings], "listed once with both spaces picked")
    }

    /// Safari's exported cra: bookmark is listed. The Reading List isn't bookmarks: nothing in it is.
    private static func safariImportReport() throws {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("cra-safari-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: folder) }
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("""
            <DL><p>
            <DT><H3>Favorites</H3>
            <DL><p>
            <DT><A HREF="https://example.com/docs">Docs</A>
            <DT><A HREF="cra://settings">Cra Settings</A>
            </DL><p>
            <DT><H3>Reading List</H3>
            <DL><p>
            <DT><A HREF="https://example.com/later">Later</A>
            <DT><A HREF="cra://history">History</A>
            </DL><p>
            </DL><p>
            """.utf8).write(to: folder.appendingPathComponent("Bookmarks.html"))
        let plan = try SafariImporter.read(folder).plan
        expect(plan.spaces.first?.pinned.map(\.url) == ["https://example.com/docs"]
               && plan.spaces.first?.skipped == [cra("Cra Settings", "cra://settings")],
               "Safari's cra: bookmark is listed; the Reading List stays out whole, so nothing in it is")
    }

    /// Ardia (X request, 18 Nov): its profiles are its spaces (Tests/Fixtures/Ardia/session.json).
    /// Top Apps become favorites, pinned rows and pinned groups the pinned section with nested
    /// folders, the rest Today; pins mirrored into a second window come over once, and a profile
    /// with no window brings the pins Ardia parked for it. Spaces on their own Chromium profile
    /// land on a Cra profile, so their sign-ins follow.
    @MainActor
    private static func ardiaImport() throws {
        expect(ArdiaImporter.isAvailable, "a session.json counts as Ardia data")
        let plan = try ArdiaImporter.plan()
        expect(plan.source == "Ardia" && plan.spaces.map(\.title) == ["Personal", "Work", "Side"], "Ardia's profiles come over as spaces, in its order")
        let personal = plan.spaces[0], work = plan.spaces[1], side = plan.spaces[2]
        expect(personal.favorites.compactMap(\.url) == ["https://mail.example.com/"],
               "a Top App comes over once, at the page it was pinned with, though every window holds a copy")
        expect(personal.pinned.count == 1 && personal.pinned[0].isFolder && personal.pinned[0].pageTitle == "Dev", "a pinned group is a pinned folder")
        let dev = personal.pinned[0].children
        expect(dev.count == 2 && dev[0].url == "https://code.example.com/" && dev[0].customTitle == "Code"
               && dev[1].isFolder && dev[1].pageTitle == "Reading" && dev[1].children.compactMap(\.url) == ["https://docs.example.com/"],
               "folders nest, each tab in its deepest group, renamed tabs keep their name")
        expect(personal.today.compactMap(\.url) == ["https://news.example.com/", "https://other.example.com/"],
               "unpinned tabs of every window come over, an empty new tab left out, an unpinned group flattened")
        expect(personal.profile == nil && personal.emoji == "" && personal.theme?.accent == "#C07A98",
               "the first profile stays on Default; no icon is a dot; its swatch becomes the theme")
        expect(work.favorites.compactMap(\.url) == ["https://tasks.example.com/"], "a Top Apps folder's tiles come over as favorites")
        expect(work.today.compactMap(\.url) == ["https://design.example.com/", "file:///Users/me/notes.html",
                                                "javascript:void(document.title)", "chrome://settings/"],
               "open tabs come over whatever their address; about:blank and blob: left out")
        expect(work.pinned.compactMap(\.url) == ["https://status.example.com/now"] && work.pinned.first?.pageTitle == "Status now",
               "a tab pinned with a new tab page comes over pinned, at the page it shows and that page's title")
        expect(work.profile == ImportedProfile(folder: "Profile p-work", name: "Work") && work.emoji == "💼",
               "a profile signs in on Chromium's \"Profile <id>\" folder")
        expect(side.pinned.count == 1 && side.pinned[0].pageTitle == "Talk" && side.pinned[0].children.compactMap(\.url) == ["https://chat.example.com/"],
               "a profile with no window open brings its parked pins")
        expect(side.profile == work.profile, "a profile sharing another's sign-ins goes on that profile")
        expect(side.symbol == "star" && side.theme?.colors == ["#FF8000", "#0000FF"] && side.theme?.appearance == "dark",
               "an SF Symbol icon and a custom gradient come over")

        let composition = AppComposition(clock: ManualScheduler())
        let store = composition.store
        let result = store.apply(plan, includeArchive: false, includeSettings: false)
        expect(result.spaces == 3 && result.folders == 3, "applying adds the spaces and their folders")
        let ids = result.spaceIDs.compactMap { store.space($0) }
        expect(ids[0].profileID == nil && ids[1].profileID != nil && ids[1].profileID == ids[2].profileID
               && store.profile(ids[1].profileID)?.name == "Work", "Work and Side share one Cra profile, Personal stays on Default")
        expect(result.profiles.craFolder(forSource: "Profile p-work") != "Default", "Work's cookies go to that profile")
        expect(store.integrityProblems().isEmpty, "the imported sidebar is sound")
        for id in result.spaceIDs { store.deleteSpace(id) }
    }

    // promise: #802
    /// Phi (#802): its SwiftData store (Tests/Fixtures/Phi/Phi/users/<account>/localDB, made with
    /// Phi's own models, see make-store.swift.txt). Spaces come in Phi's order without its agent
    /// spaces; a space's bookmark tree is its pinned section, folders nested and split bookmarks
    /// a page each; pinned tabs are favorites, read in the store's Pinned Tab Scope (a space's own,
    /// a profile's shared by its spaces, or one set for every space). A space on another Chromium
    /// profile lands on a Cra profile, so its sign-ins follow.
    @MainActor
    private static func phiImport() throws {
        expect(PhiImporter.isAvailable, "a LocalStore.sqlite under Phi/users counts as Phi data")
        let plan = try PhiImporter.plan()
        expect(plan.source == "Phi" && plan.spaces.map(\.title) == ["Home", "Work", "Reading"],
               "Phi's spaces come over in its order; its agent spaces stay behind")
        let home = plan.spaces[0], work = plan.spaces[1], reading = plan.spaces[2]
        expect(home.favorites.compactMap(\.url) == ["https://mail.google.com/mail/u/0/", "https://www.youtube.com/"],
               "a space's pinned tabs are its favorites, in Phi's order; other scopes' copies and open tabs stay out")
        expect(home.pinned.map { $0.url ?? "folder " + $0.pageTitle } == ["folder Docs", "https://mail.google.com/", "https://calendar.google.com/",
                                                                         "https://news.ycombinator.com/", "https://github.com/", "chrome://settings/"],
               "the bookmark tree is the pinned section, in Phi's order; a split bookmark brings each page")
        let docs = home.pinned[0].children
        expect(docs.count == 2 && docs[0].url == "https://www.swift.org/" && docs[1].isFolder && docs[1].pageTitle == "Deep"
               && docs[1].children.compactMap(\.url) == ["https://developer.apple.com/"], "folders nest")
        expect(home.pinned[4].customTitle == "Code" && home.pinned[4].pageTitle == "GitHub · Where software is built"
               && home.pinned[2].pageTitle == "Calendar", "a renamed bookmark keeps its name; a split's second page its own title")
        expect(home.skipped == [cra("Cra Settings", "cra://settings")], "a cra: bookmark is listed")
        expect(home.emoji == "🏠" && home.profile == nil && home.theme?.accent == "#3A6FF8",
               "an emoji icon, the Default profile, the space's colour as its theme")
        expect(work.favorites.compactMap(\.url) == ["https://app.slack.com/"] && work.skipped == [cra("Downloads", "cra://downloads", .favorites)]
               && work.pinned.compactMap(\.url) == ["https://linear.app/"], "each space has its own favorites and pinned section")
        expect(work.profile == ImportedProfile(folder: "Profile 1", name: "Work") && work.emoji == "" && work.symbol == nil,
               "a space on \"Profile 1\" signs in there; a Phi artwork icon is a dot")
        expect(reading.emoji == "9️⃣" && reading.pinned.isEmpty && reading.favorites.isEmpty && reading.profile == nil,
               "an empty space still comes over; a many-code-point emoji is read whole")
        expect(plan.favorites.isEmpty && home.today.isEmpty, "nothing is left without a space; Phi keeps open tabs in Chromium's session, not here")

        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Phi/scopes")
        let byProfile = try PhiImporter.plan(store: fixtures.appendingPathComponent("profile.sqlite"))
        expect(byProfile.spaces.map { $0.favorites.compactMap(\.url) } == [["https://profile.example/"], ["https://work-profile.example/"], ["https://profile.example/"]]
               && byProfile.spaces.map(\.favoritesList) == ["profile Default", "profile Profile 1", "profile Default"],
               "Pinned Tab Scope Profile: a profile's pinned tabs show in each of its spaces, counted once; a dormant one stays out")
        let byApp = try PhiImporter.plan(store: fixtures.appendingPathComponent("app.sqlite"))
        expect(byApp.spaces.allSatisfy { $0.favorites.compactMap(\.url) == ["https://app.example/"] && $0.favoritesList == "app" },
               "Pinned Tab Scope App: the same pinned tabs in every space")

        let phi = ImportSource.allCases.first { $0.id == "phi" }
        expect(phi?.isAvailable == true && phi?.keychainService == "Phi Safe Storage" && phi?.keychainAccount == "Phi",
               "Phi is listed from its folder, its passwords and cookies open with Phi's Keychain item")
        expect(phi?.credentialProfiles.map(\.id) == ["Default", "Profile 1"], "Phi's Chromium profiles sit right in its folder")

        let composition = AppComposition(clock: ManualScheduler())
        let store = composition.store
        let result = store.apply(plan, includeArchive: false, includeSettings: false)
        expect(result.spaces == 3 && result.folders == 2, "applying adds the three spaces and the two folders")
        let spaces = result.spaceIDs.compactMap { store.space($0) }
        expect(spaces[0].profileID == nil && spaces[1].profileID != nil && spaces[2].profileID == nil,
               "Work goes on a Cra profile of its own, Home and Reading stay on Default")
        expect(store.integrityProblems().isEmpty, "the imported sidebar is sound")
        for id in result.spaceIDs { store.deleteSpace(id) }
    }

    // promise: #688
    /// Crest (Discussion #688): its session file (Tests/Fixtures/Crest/ControlPlane/session.sqlite, in
    /// Crest's own format, see make-session.txt). Spaces come in Crest's order; tile-row tabs are
    /// favorites and saved tabs the pinned section, both at the page they were saved with, saved
    /// folders nested; current tabs are Today, a current folder's tabs on their own. Crest's own
    /// pages and blank tabs stay behind, cra: addresses are listed, and archived tabs come over
    /// newest first. The first Space stays on Default; the others land on a Cra profile for their
    /// "Crest-<id>" Chromium folder, Spaces sharing one on the same Cra profile.
    @MainActor
    private static func crestImport() throws {
        expect(CrestImporter.isAvailable, "ControlPlane/session.sqlite counts as Crest data")
        let plan = try CrestImporter.plan()
        expect(plan.source == "Crest" && plan.spaces.map(\.title) == ["Work", "Personal", "Side"], "Crest's Spaces come over in its order")
        let work = plan.spaces[0], personal = plan.spaces[1], side = plan.spaces[2]
        expect(work.favorites.compactMap(\.url) == ["https://mail.example.com/"] && work.favorites[0].pageTitle == "Inbox",
               "a tile-row tab is a favorite, at the page it was saved with")
        expect(work.skipped == [cra("Cra Settings", "cra://settings", .favorites)], "a cra: favorite is listed")
        expect(work.pinned.map { $0.url ?? "folder " + $0.pageTitle } == ["folder Projects", "https://status.example.com/now"],
               "saved tabs are the pinned section, a folder where its first tab is; Crest's own Settings page stays behind")
        let projects = work.pinned[0].children
        expect(projects.count == 2 && projects[0].url == "https://github.com/" && projects[0].customTitle == "Code"
               && projects[1].isFolder && projects[1].pageTitle == "Reading" && projects[1].children.compactMap(\.url) == ["https://docs.example.com/"],
               "saved folders nest through parentID, renamed tabs keep their name")
        expect(work.today.compactMap(\.url) == ["https://news.example.com/", "https://left.example.com/"],
               "current tabs are Today, a current folder's tabs on their own; a blank tab and the Start Page stay behind")
        expect(work.profile == nil && work.emoji == "" && work.symbol == "hammer.fill" && work.theme?.colors == ["#3C0E1A", "#722030"],
               "the first Space stays on Default, with its SF Symbol and its branding colours")
        expect(personal.favorites.compactMap(\.url) == ["https://calendar.example.com/"] && personal.pinned.compactMap(\.url) == ["file:///Users/me/notes.html"],
               "each Space reads its own tabs; a file: page comes over")
        expect(personal.emoji == "🏡" && personal.theme?.accent == "#1F7D85", "a crest.emoji: icon, and the accent's swatch without branding colours")
        expect(personal.profile == ImportedProfile(folder: "Crest-B0000000-0000-4000-8000-00000000000B", name: "Personal"),
               "a later Space signs in on its own \"Crest-<id>\" folder")
        expect(side.profile == personal.profile && side.pinned.isEmpty && side.symbol == "leaf",
               "a Space sharing another's Chromium profile goes on the same one; an empty Space still comes over")
        expect(plan.archive.map(\.url) == ["https://spec.example.com/", "https://plan.example.com/"]
               && plan.archive.map(\.reason) == [.manual, .auto] && plan.archive[0].customTitle == "Spec" && plan.archive[0].spaceTitle == "Work",
               "archived tabs come over newest first, a cleanup as auto-archived")
        expect(plan.archiveSkipped.map(\.url) == ["blob:https://files.example.com/5c1e"], "an archived blob: tab is listed")

        let crest = ImportSource.allCases.first { $0.id == "crest" }
        expect(crest?.isAvailable == true && crest?.keychainService == "Crest Safe Storage" && crest?.keychainAccount == "com.pauldavis.crest",
               "Crest is listed from its folder, its passwords and cookies open with Crest's Keychain item")
        expect(crest?.credentialProfiles.map(\.id) == ["Crest-A0000000-0000-4000-8000-00000000000A", "Crest-B0000000-0000-4000-8000-00000000000B"]
               && crest?.credentialProfiles.map(\.name) == ["Work", "Personal"],
               "Crest's \"Crest-<id>\" folders are found, shown by Space; its Default and a folder no Space uses are left out")

        let composition = AppComposition(clock: ManualScheduler())
        let store = composition.store
        let result = store.apply(plan, includeArchive: true, includeSettings: false)
        expect(result.spaces == 3 && result.folders == 2 && result.archived == 2, "applying adds the Spaces, their folders and the archive")
        let spaces = result.spaceIDs.compactMap { store.space($0) }
        expect(spaces[0].profileID == nil && spaces[1].profileID != nil && spaces[1].profileID == spaces[2].profileID,
               "Personal and Side share one Cra profile, Work stays on Default")
        expect(result.profiles.craFolder(forSource: "Crest-B0000000-0000-4000-8000-00000000000B") != "Default"
               && result.profiles.craFolder(forSource: "Crest-A0000000-0000-4000-8000-00000000000A") == "Default",
               "Personal's cookies go to its Cra profile, Work's to Default")
        expect(store.integrityProblems().isEmpty, "the imported sidebar is sound")
        for id in result.spaceIDs { store.deleteSpace(id) }
    }

    // promise: #734
    /// Yab (X request, 18 Nov): spaces.json plus one session file per space
    /// (Tests/Fixtures/Yab). Tiles are favorites, kept tabs the pinned section in their folders,
    /// the rest Today. With "pins in every space" on, a space that signs in where the first one does
    /// shows the shared tiles and a space with sign-ins of its own keeps its own (PR #734, Yab's
    /// SharedPins.showsShared). A space with sign-ins of its own is on the Chromium folder its
    /// receipt names.
    @MainActor
    private static func yabImport() throws {
        expect(YabImporter.isAvailable, "spaces.json counts as Yab data")
        let plan = try YabImporter.plan(supportDir: YabImporter.supportDir, pinsInEverySpace: nil)
        expect(plan.source == "Yab" && plan.spaces.map(\.title) == ["Personal", "Work"], "Yab's spaces come over in its order")
        let personal = plan.spaces[0], work = plan.spaces[1]
        expect(personal.favorites.compactMap(\.url) == ["https://mail.example.com/"] && personal.favorites[0].pageTitle == "Inbox",
               "a tile is a favorite, at the page it was pinned with")
        expect(personal.pinned.map(\.pageTitle) == ["Clients", "Code"] && personal.pinned[0].isFolder,
               "kept tabs are pinned, a folder where its first tab is")
        let clients = personal.pinned[0].children
        expect(clients.count == 1 && clients[0].pageTitle == "Work" && clients[0].children.first?.url == "https://tasks.example.com/"
               && clients[0].children.first?.customTitle == "Tasks", "folders nest through folderPath, renamed tabs keep their name")
        expect(personal.today.compactMap(\.url) == ["https://news.example.com/"], "today's tabs come over, about:blank left out")
        expect(personal.emoji == "🏠" && personal.profile == nil && personal.theme?.accent == "#8DB6E6",
               "an emoji icon, the shared sign-ins on Default, a swatch as the theme")
        expect(work.favorites.compactMap(\.url) == ["https://docs.example.com/"],
               "pins in every space unset is Yab's In Each Space for a Mac in use: each space keeps its own tiles")
        expect(work.pinned.compactMap(\.url) == ["https://wiki.example.com/"] && work.today.compactMap(\.url) == ["https://design.example.com/"],
               "each space reads its own session file")
        expect(work.profile == ImportedProfile(folder: "space-9C6B1E52-3D1F-4C2B-8E37-5A0F1D2C3B4A", name: "Work"),
               "own sign-ins: the Chromium folder the receipt names, not the space id")
        expect(work.symbol == "briefcase" && work.theme?.accent == "#7FB8A3" && work.theme?.noise == 0.4,
               "an Icon-tab symbol and a colour of its own with grain")
        let shared = try YabImporter.plan(supportDir: YabImporter.supportDir, pinsInEverySpace: true)
        expect(shared.spaces[0].favorites.compactMap(\.url) == ["https://calendar.example.com/"],
               "with pins in every space on, a space that signs in where the first one does shows the shared tiles")
        expect(shared.spaces[1].favorites.compactMap(\.url) == ["https://docs.example.com/"],
               "with pins in every space on, a space with sign-ins of its own keeps its own tiles, not the shared ones")
        let apart = try YabImporter.plan(supportDir: YabImporter.supportDir, pinsInEverySpace: false)
        expect(apart.spaces[0].favorites.compactMap(\.url) == ["https://mail.example.com/"]
               && apart.spaces[1].favorites.compactMap(\.url) == ["https://docs.example.com/"],
               "with pins in every space off, each space keeps its own tiles and none gets the shared ones")

        let yab = ImportSource.allCases.first { $0.id == "yab" }, ardia = ImportSource.allCases.first { $0.id == "ardia" }
        expect(yab?.isAvailable == true && ardia?.isAvailable == true, "both are listed in the picker from their data alone")
        expect(yab?.keychainService == "Yab Safe Storage" && ardia?.keychainService == "Ardia Safe Storage",
               "cookies and passwords open with each browser's own Keychain item")
        let profiles = yab?.credentialProfiles ?? []
        expect(Set(profiles.map(\.name)) == ["Shared", "Work"] && !profiles.contains { $0.id == "Default" },
               "Yab's space-<id> profiles are found and shown by space; its unused Default is left out")
        expect(ardia?.credentialProfiles.map(\.id) == ["Default", "Profile p-work"]
               && ardia?.credentialProfiles.map(\.name) == ["Personal", "Work"], "Ardia's \"Profile <id>\" folders are found, shown by space")

        let composition = AppComposition(clock: ManualScheduler())
        let result = composition.store.apply(plan, includeArchive: false, includeSettings: false)
        expect(result.spaces == 2 && result.folders == 2, "applying adds the spaces and their folders")
        expect(result.profiles.craFolder(forSource: "space-9C6B1E52-3D1F-4C2B-8E37-5A0F1D2C3B4A") != "Default"
               && result.profiles.craFolder(forSource: "space-00000000-0000-0000-0000-000000000001") == "Default",
               "the Work space's cookies go to its Cra profile, the shared ones to Default")
        expect(composition.store.integrityProblems().isEmpty, "the imported sidebar is sound")
    }

    /// Yab keeps icons of its own (Tests/Fixtures/Yab/icons): per page, listed in pages.json as
    /// "<host><path>" and stored as pages/<hash>.png, else per host as <host>.png.
    @MainActor
    private static func yabOwnIcons() throws {
        // A copy of the fixture with a second tab on news.example.com, at the page with an icon of its own.
        let fixture = YabImporter.supportDir
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("cra-yab-icons-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.copyItem(at: fixture, to: copy)
        setenv("CRA_YAB_DIR", copy.path, 1)
        defer { setenv("CRA_YAB_DIR", fixture.path, 1); try? FileManager.default.removeItem(at: copy) }
        let session = copy.appendingPathComponent("session.json")
        guard var root = try JSONSerialization.jsonObject(with: Data(contentsOf: session)) as? [String: Any], var tabs = root["tabs"] as? [[String: Any]] else {
            return expect(false, "the Yab fixture's session.json reads")
        }
        tabs.append(["id": "i", "url": "https://news.example.com/sport", "title": "Sport"])
        root["tabs"] = tabs
        try JSONSerialization.data(withJSONObject: root).write(to: session)

        let icons = YabImporter.supportDir.appendingPathComponent("icons", isDirectory: true)
        func shrunk(_ file: String) -> Data? { (try? Data(contentsOf: icons.appendingPathComponent(file))).flatMap { FaviconCache.png($0) } }
        func icon(_ item: ImportedItem?) -> Data? { item?.faviconPath.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } }
        let plan = try YabImporter.plan(pinsInEverySpace: nil)
        let personal = plan.spaces[0], work = plan.spaces[1]
        let news = personal.today.first { $0.url == "https://news.example.com/" }, sport = personal.today.first { $0.url == "https://news.example.com/sport" }
        expect(icon(sport) != nil && icon(sport) == shrunk("pages/5f0a1c2e3d4b5a6978695a4b.png"), "a tab on a page Yab has an icon for gets that page's icon")
        expect(icon(news) != nil && icon(news) == shrunk("news.example.com.png"), "a tab on another page of the host gets the host's icon")
        expect(icon(personal.favorites.first) != nil && icon(personal.favorites.first) == shrunk("mail.example.com.png"), "a tile gets its host's icon")
        expect(work.today.first?.url == "https://design.example.com/" && work.today.first?.faviconPath == nil,
               "a host with no icon file and no Favicons row gets none")

        let store = AppComposition(clock: ManualScheduler()).store
        let space = store.apply(plan, includeArchive: false, includeSettings: false).spaceIDs[0]
        let today = (store.space(space)?.todayContainerID).map(store.tabs(under:)) ?? []
        let newsTab = today.first { $0.tab?.url == "https://news.example.com/" }, sportTab = today.first { $0.tab?.url == "https://news.example.com/sport" }
        expect(icon(news) != icon(sport) && savedFavicon(newsTab?.tab?.faviconKey) == icon(news) && savedFavicon(sportTab?.tab?.faviconKey) == icon(sport),
               "two tabs on one host keep their different icons after the import")
    }

    /// The onboarding pin picker shows each site's icon from the stores the import reads: Yab's own
    /// icons/ folder before its Favicons databases.
    private static func pinPickerReadsTheImportsIconStores() {
        let found = ImportSource.allCases.first { $0.id == "yab" }?.favicons(hosts: ["mail.example.com", "design.example.com"]) ?? [:]
        expect(found["mail.example.com"] != nil, "a site Yab has an icon file for shows it in the pin picker")
        expect(found["design.example.com"] == nil, "a site with no icon anywhere shows none")
    }

    /// Icon files come from other browsers' stores and, for unit 2, from sites: a bitmap is shrunk
    /// without being decoded at the size it claims, so a 20000 px PNG of a few KB costs nothing.
    private static func iconFilesAreDecodedSmall() {
        let start = Date()
        let bomb = FaviconCache.png(hugePNG(side: 20000))
        expect(Date().timeIntervalSince(start) < 1, "a PNG claiming 20000 px is handled at once, not decoded at that size")
        expect(bomb.flatMap(NSBitmapImageRep.init(data:)).map { $0.pixelsWide <= 64 } ?? true, "and gives at most a 64 px icon")

        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 256, pixelsHigh: 128, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                   isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        let wide = rep?.representation(using: .png, properties: [:]).flatMap { FaviconCache.png($0) }.flatMap(NSBitmapImageRep.init(data:))
        expect(wide?.pixelsWide == 64 && wide?.pixelsHigh == 32, "a 256 px bitmap icon is shrunk to 64 px, keeping its shape")
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="3000" height="2000"><rect width="3000" height="2000" fill="orange"/></svg>"#
        let drawn = FaviconCache.png(Data(svg.utf8)).flatMap(NSBitmapImageRep.init(data:))
        expect(drawn != nil && (drawn?.pixelsWide ?? .max) <= 64, "an SVG, which ImageIO can't read, is drawn at 64 px")
    }

    /// A black 1-bit PNG `side` px square, a few KB of zlib: a decoder that trusts its size allocates GBs.
    private static func hugePNG(side: Int) -> Data {
        func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
        func crc32(_ d: Data) -> UInt32 {
            var c: UInt32 = 0xFFFF_FFFF
            for byte in d {
                c ^= UInt32(byte)
                for _ in 0..<8 { c = c & 1 == 1 ? (c >> 1) ^ 0xEDB8_8320 : c >> 1 }
            }
            return ~c
        }
        func chunk(_ type: String, _ body: Data) -> Data { let t = Data(type.utf8) + body; return be32(UInt32(body.count)) + t + be32(crc32(t)) }
        let raw = side * (1 + (side + 7) / 8)  // every row: filter byte 0, then zero bits
        let deflated = ((try? (Data(count: raw) as NSData).compressed(using: .zlib)) as Data?) ?? Data()
        // zlib wraps the deflate stream: a header, and an Adler-32 that for zeros is (n mod 65521) << 16 | 1.
        let zlib = Data([0x78, 0x01]) + deflated + be32(UInt32(raw % 65521) << 16 | 1)
        let header = be32(UInt32(side)) + be32(UInt32(side)) + Data([1, 0, 0, 0, 0])
        return Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + chunk("IHDR", header) + chunk("IDAT", zlib) + chunk("IEND", Data())
    }

    /// Chromium's Favicons and Firefox's favicons.sqlite hold icons by page address. A tab finds its
    /// host's under http or https, on any port, with www. added or dropped, but never a sibling's.
    private static func faviconDatabaseLookup() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-favicon-db-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let rows: [(page: String, side: Int)] = [
            ("http://plain.example.com/page", 11), ("https://ported.example.com:8443/", 12), ("https://bare.example.com/", 13),
            ("https://www.prefixed.example.com/", 14), ("https://mail.example.com/", 15), ("https://look.example.com.evil.test/", 17),
            ("https://wide.example.com/a", 16), ("https://wide.example.com/b", 32),
        ]
        let hosts = ["plain.example.com", "ported.example.com", "www.bare.example.com", "prefixed.example.com", "drive.example.com",
                     "look.example.com", "wide.example.com"]
        let chromium = root.appendingPathComponent("Chromium", isDirectory: true), firefox = root.appendingPathComponent("Firefox", isDirectory: true)
        makeChromiumUserData(chromium, bookmarks: [], icons: rows)
        makeFirefoxData(firefox, bookmarks: [], icons: rows)
        for (name, found) in [("Chromium", ChromiumImporter.favicons(userData: chromium, hosts: hosts)), ("Firefox", FirefoxImporter.favicons(root: firefox, hosts: hosts))] {
            let side = found.mapValues { NSBitmapImageRep(data: $0)?.pixelsWide ?? 0 }
            expect(side["plain.example.com"] == 11, "\(name): a page loaded over http gives its host an icon")
            expect(side["ported.example.com"] == 12, "\(name): so does a page on a port")
            expect(side["www.bare.example.com"] == 13, "\(name): a www. host finds the bare host's icon")
            expect(side["prefixed.example.com"] == 14, "\(name): a bare host finds the www. host's icon")
            expect(side["drive.example.com"] == nil, "\(name): a host never takes a sibling subdomain's icon")
            expect(side["look.example.com"] == nil, "\(name): nor that of a longer host that starts with it")
            expect(side["wide.example.com"] == 32, "\(name): the widest icon of the host wins")
        }
    }

    /// Chrome-family and Firefox imports bring each tab's icon from the profile's favicon database.
    private static func chromiumAndFirefoxPlansBringIcons() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-favicon-plans-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let pages = ["https://plain.example.com/", "https://drive.example.com/"], icons: [(page: String, side: Int)] = [("http://plain.example.com/page", 11)]
        let chromium = root.appendingPathComponent("Chromium", isDirectory: true), firefox = root.appendingPathComponent("Firefox", isDirectory: true)
        makeChromiumUserData(chromium, bookmarks: pages, icons: icons)
        makeFirefoxData(firefox, bookmarks: pages, icons: icons)
        let plans = [("Chrome", try ChromiumImporter.plan(browser: "Chrome", userData: chromium)), ("Firefox", try FirefoxImporter.plan(browser: "Firefox", root: firefox))]
        for (name, plan) in plans {
            let items = plan.spaces.first?.pinned ?? []
            expect(pixelsWide(items.first { $0.url == pages[0] }?.faviconPath) == 11, "\(name): a bookmark comes with its host's icon from the profile's database")
            expect(items.count == 2 && items[1].faviconPath == nil, "\(name): a bookmark on a host the database has no icon for comes without one")
        }
        // The import preview caches icons by path: another browser's plan must not overwrite them.
        let other = root.appendingPathComponent("Other", isDirectory: true)
        makeChromiumUserData(other, bookmarks: pages, icons: [("https://plain.example.com/", 12)])
        let second = try ChromiumImporter.plan(browser: "Brave", userData: other)
        expect(pixelsWide(second.spaces.first?.pinned.first?.faviconPath) == 12 && pixelsWide(plans[0].1.spaces.first?.pinned.first?.faviconPath) == 11,
               "a second browser's plan leaves the first one's icon files alone")
    }

    /// The import window reads the picked browser's plan on a background thread (#748 made it slow
    /// with icons): each fixture browser's plan reads there without the main thread, as it does on main.
    private static func plansReadOffTheMainThread() {
        func lines(_ plan: ImportPlan?) -> [String] {
            func icon(_ path: String?) -> String { path.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }?.base64EncodedString() ?? "-" }
            func items(_ list: [ImportedItem]) -> [String] {
                list.flatMap { ["\($0.customTitle ?? $0.pageTitle) \($0.url ?? "folder") \(icon($0.faviconPath))"] + items($0.children) }
            }
            guard let plan else { return [] }
            return items(plan.favorites) + plan.spaces.flatMap { ["space \($0.title)"] + items($0.favorites + $0.pinned + $0.today) }
                + plan.archive.map { "archive \($0.url) \(icon($0.faviconPath))" }
        }
        for source in ImportSource.allCases where [.arc, .dia, .yab, .ardia, .phi].contains(source.kind) {
            let onMain = lines(try? source.plan())
            var offMain: [String] = []
            let done = DispatchSemaphore(value: 0)
            DispatchQueue.global(qos: .userInitiated).async { offMain = lines(try? source.plan()); done.signal() }
            expect(done.wait(timeout: .now() + 60) == .success, "\(source.name): its plan reads on a background thread without waiting for the main thread")
            expect(!onMain.isEmpty && offMain == onMain, "\(source.name): read on a background thread, the plan is the one read on main")
            expect(source.kind != .arc || offMain.contains { !$0.hasSuffix(" -") && !$0.hasPrefix("space ") }, "Arc's plan read there brings its icons")
        }
    }

    /// Picking a browser reads its plan through ImportPlanLoader: off the main thread, and a read for
    /// an earlier pick never lands after a later one, slow archive or not.
    @MainActor
    private static func planLoaderReadsOffMainAndKeepsTheLastPick() {
        let loader = ImportPlanLoader()
        var delivered: [String] = []
        func record(_ result: Result<ImportPlan, Error>) { delivered.append((try? result.get().source) ?? "error") }
        func spin(until done: () -> Bool) {
            let deadline = Date().addingTimeInterval(10)
            while !done() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        }
        /// A read that waits for `gate`.
        func slowRead(_ gate: DispatchSemaphore) -> @Sendable () throws -> ImportPlan {
            { gate.wait(); return ImportPlan(source: "slow") }
        }
        /// Spins until `load`'s task has delivered or dropped its result.
        func finish(_ load: Task<Void, Never>) {
            var finished = false
            Task { @MainActor in await load.value; finished = true }
            spin { finished }
            expect(finished, "the earlier pick's read finishes")
        }

        loader.load({ ImportPlan(source: Thread.isMainThread ? "main thread" : "background") }, done: record)
        spin { !delivered.isEmpty }
        expect(delivered == ["background"], "the plan is read off the main thread")

        delivered = []
        loader.load({ throw CocoaError(.fileReadNoPermission) }, done: record)
        spin { !delivered.isEmpty }
        expect(delivered == ["error"], "a read that fails hands over its error")

        delivered = []
        var gate = DispatchSemaphore(value: 0)
        var slow = loader.load(slowRead(gate), done: record)
        loader.load({ ImportPlan(source: "fast") }, done: record)
        spin { !delivered.isEmpty }
        gate.signal()
        finish(slow)
        expect(delivered == ["fast"], "a slow read for an earlier pick is dropped once a later pick's plan is in")

        delivered = []
        gate = DispatchSemaphore(value: 0)
        slow = loader.load(slowRead(gate), done: record)
        loader.cancel()
        gate.signal()
        finish(slow)
        expect(delivered.isEmpty, "a later pick that reads nothing (Full Disk Access, Safari's export) drops the read in flight")
    }

    /// A Chrome-family "User Data" folder whose Default profile has `bookmarks` on its bar and an icon
    /// `side` px wide in its Favicons for each page of `icons`.
    private static func makeChromiumUserData(_ userData: URL, bookmarks: [String], icons: [(page: String, side: Int)]) {
        let profile = userData.appendingPathComponent("Default", isDirectory: true)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: profile.appendingPathComponent("Preferences"))
        let bar = bookmarks.enumerated().map { ["type": "url", "name": "Mark \($0.offset)", "url": $0.element] }
        try? JSONSerialization.data(withJSONObject: ["roots": ["bookmark_bar": ["type": "folder", "children": bar]]])
            .write(to: profile.appendingPathComponent("Bookmarks"))
        var sql = """
            CREATE TABLE icon_mapping(id INTEGER PRIMARY KEY, page_url LONGVARCHAR NOT NULL, icon_id INTEGER, page_url_type INTEGER DEFAULT 0);
            CREATE INDEX icon_mapping_page_url_idx ON icon_mapping(page_url);
            CREATE TABLE favicons(id INTEGER PRIMARY KEY, url LONGVARCHAR NOT NULL, icon_type INTEGER DEFAULT 1);
            CREATE TABLE favicon_bitmaps(id INTEGER PRIMARY KEY, icon_id INTEGER NOT NULL, last_updated INTEGER DEFAULT 0, image_data BLOB,
              width INTEGER DEFAULT 0, height INTEGER DEFAULT 0, last_requested INTEGER DEFAULT 0);
            """
        for (i, icon) in icons.enumerated() {
            sql += """
                INSERT INTO favicons VALUES (\(i + 1), 'https://icons.test/\(i + 1).png', 1);
                INSERT INTO icon_mapping(page_url, icon_id) VALUES ('\(icon.page)', \(i + 1));
                INSERT INTO favicon_bitmaps(icon_id, image_data, width, height) VALUES (\(i + 1), \(squarePNG(icon.side)), \(icon.side), \(icon.side));
                """
        }
        writeSQLite(profile.appendingPathComponent("Favicons"), sql)
    }

    /// A Firefox data folder whose default profile has `bookmarks` on its toolbar and an icon `side`
    /// px wide in its favicons.sqlite for each page of `icons`.
    private static func makeFirefoxData(_ root: URL, bookmarks: [String], icons: [(page: String, side: Int)]) {
        let profile = root.appendingPathComponent("Profiles/test.default", isDirectory: true)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try? Data("[Profile0]\nName=default\nIsRelative=1\nPath=Profiles/test.default\nDefault=1\n".utf8).write(to: root.appendingPathComponent("profiles.ini"))
        var places = """
            CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR);
            CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, position INTEGER,
              title LONGVARCHAR, dateAdded INTEGER, guid TEXT);
            INSERT INTO moz_bookmarks VALUES (1, 2, NULL, 0, 0, '', 0, 'root________'), (2, 2, NULL, 1, 0, 'toolbar', 0, 'toolbar_____');
            """
        for (i, url) in bookmarks.enumerated() {
            places += "INSERT INTO moz_places VALUES (\(i + 1), '\(url)', ''); INSERT INTO moz_bookmarks VALUES (\(i + 3), 1, \(i + 1), 2, \(i), 'Mark \(i)', 0, 'mark\(i)');"
        }
        writeSQLite(profile.appendingPathComponent("places.sqlite"), places)
        var sql = """
            CREATE TABLE moz_icons (id INTEGER PRIMARY KEY, icon_url TEXT NOT NULL, fixed_icon_url_hash INTEGER NOT NULL, width INTEGER NOT NULL DEFAULT 0,
              root INTEGER NOT NULL DEFAULT 0, color INTEGER, expire_ms INTEGER NOT NULL DEFAULT 0, data BLOB);
            CREATE TABLE moz_pages_w_icons (id INTEGER PRIMARY KEY, page_url TEXT NOT NULL, page_url_hash INTEGER NOT NULL);
            CREATE TABLE moz_icons_to_pages (page_id INTEGER NOT NULL, icon_id INTEGER NOT NULL, expire_ms INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (page_id, icon_id)) WITHOUT ROWID;
            """
        for (i, icon) in icons.enumerated() {
            sql += """
                INSERT INTO moz_icons(id, icon_url, fixed_icon_url_hash, width, data) VALUES (\(i + 1), 'https://icons.test/\(i + 1).png', \(i + 1), \(icon.side), \(squarePNG(icon.side)));
                INSERT INTO moz_pages_w_icons VALUES (\(i + 1), '\(icon.page)', \(i + 1));
                INSERT INTO moz_icons_to_pages(page_id, icon_id) VALUES (\(i + 1), \(i + 1));
                """
        }
        writeSQLite(profile.appendingPathComponent("favicons.sqlite"), sql)
    }

    /// A square PNG `side` px wide, as an SQL blob literal.
    private static func squarePNG(_ side: Int) -> String {
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { r in NSColor.orange.setFill(); r.fill(); return true }
        return "X'" + (FaviconCache.png(image) ?? Data()).map { String(format: "%02x", $0) }.joined() + "'"
    }

    private static func writeSQLite(_ file: URL, _ sql: String) {
        var db: OpaquePointer?
        sqlite3_open(file.path, &db)
        defer { sqlite3_close(db) }
        expect(sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK, "the test's database \(file.lastPathComponent) is written")
    }

    /// The icon a key has in Cra's Favicons folder.
    @MainActor
    private static func savedFavicon(_ key: String?) -> Data? {
        key.flatMap { try? Data(contentsOf: AppPaths.favicons.appendingPathComponent(FaviconCache.fileName($0))) }
    }

    /// How many pixels wide the image in a file is.
    private static func pixelsWide(_ path: String?) -> Int? {
        path.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }.flatMap(NSBitmapImageRep.init(data:))?.pixelsWide
    }

    // promise: #742
    /// Yab import keeps a tab whatever its address, and a kept tab pinned with a page that can't be
    /// imported comes over pinned, at the page it shows. A copy of Tests/Fixtures/Yab with such tabs.
    private static func yabKeepsAnyAddress() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("cra-yab-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: dir) }
        try fm.copyItem(at: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Yab"), to: dir)
        let session = dir.appendingPathComponent("session.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: session)) as! [String: Any]
        let rows = root["tabs"] as! [[String: Any]]
        let kept: [[String: Any]] = [
            ["id": "k", "url": "file:///Users/me/notes.html", "title": "Notes", "kept": true],
            ["id": "s", "url": "https://status.example.com/now", "title": "Status now", "kept": true, "home": "about:newtab", "homeTitle": "New Tab"],
        ]
        let open = ["javascript:void(document.title)", "chrome://settings/", "chrome://newtab/", "blob:https://news.example.com/5f1c"]
            .enumerated().map { ["id": "o\($0.offset)", "url": $0.element, "title": $0.element] as [String: Any] }
        root["tabs"] = rows.filter { $0["kept"] as? Bool == true || $0["pin"] != nil } + kept + rows.filter { $0["kept"] == nil && $0["pin"] == nil } + open
        try JSONSerialization.data(withJSONObject: root).write(to: session)

        let personal = try YabImporter.plan(supportDir: dir, pinsInEverySpace: nil).spaces[0]
        expect(personal.pinned.compactMap(\.url).contains("file:///Users/me/notes.html"), "a kept tab on a file on disk comes over")
        expect(personal.pinned.last?.url == "https://status.example.com/now" && personal.pinned.last?.pageTitle == "Status now",
               "a kept tab pinned with a new tab page comes over pinned, at the page it shows and that page's title")
        expect(personal.today.compactMap(\.url) == ["https://news.example.com/", "javascript:void(document.title)", "chrome://settings/"],
               "today's tabs come over whatever their address; about:blank, a new tab page and blob: left out")
    }

    /// Chrome-family profiles (Tests/Fixtures/Chromium/Default): the last session's open tabs,
    /// bookmarks and which extensions are turned off.
    private static func chromiumProfile() {
        let profile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Chromium/Default")
        let tabs = ChromiumImporter.openTabs(profile: profile)
        expect(tabs.map(\.url) == ["https://example.com/one", "https://example.com/two-b", "file:///Users/me/notes.html",
                                   "javascript:void(document.title)", "chrome://settings/"],
               "open tabs: the selected navigation of each, whatever its address, in window order; closed tabs, a new tab page, about:blank and blob: left out")
        expect(tabs.prefix(2).map(\.pageTitle) == ["One", "Two, then Ü"], "titles come from the session's UTF-16 strings")
        let marks = ChromiumImporter.bookmarks(profile: profile)
        expect(marks.bar.map(\.pageTitle) == ["Docs", "Reading", "Local", "Tools"] && marks.bar[1].children.map(\.url) == ["https://example.com/read"],
               "the bookmarks bar keeps file: links and folders with something in them, drops empty folders")
        expect(marks.bar[2].url == "file:///etc/hosts", "a file: bookmark comes over")
        expect(marks.bar[3].children.map(\.url) == ["javascript:void(document.title)", "chrome://settings/"],
               "a folder of a bookmarklet and a browser page comes over with both")
        expect(marks.other.map(\.url) == ["https://example.com/other"], "other and mobile bookmarks come after")
        expect(ChromiumImporter.parseSession(Data("SNSS".utf8) + Data([4, 0, 0, 0]) + Data(repeating: 1, count: 16)).isEmpty,
               "an encrypted session (version 4) gives nothing rather than garbage")
        expect(ExtensionImporter.disabledIDs(inProfile: profile).contains("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
               && !ExtensionImporter.disabledIDs(inProfile: profile).contains("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
               "an extension with disable_reasons is off, one in state 1 is on")
    }

    // promise: #742
    /// Firefox (a profile made here, as Firefox writes it): bookmarks from places.sqlite and open
    /// tabs from the session store come over whatever their address. Left out: a blank or new tab
    /// page, a blob: and the place: queries Firefox keeps as smart bookmarks.
    private static func firefoxImport() throws {
        let root = try firefoxRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try FirefoxImporter.plan(browser: "Firefox", root: root)
        let marks = plan.spaces.first?.pinned ?? []
        expect(marks.map(\.pageTitle) == ["News", "Notes", "Bookmarklet", "Settings", "Tools"],
               "toolbar bookmarks come over whatever their address; place:, about:blank and blob: left out, and a folder of only place: ones")
        expect(marks.compactMap(\.url) == ["https://example.com/news", "file:///Users/me/notes.html", "javascript:void(document.title)", "about:preferences"],
               "each at its own address")
        expect(marks.last?.children.compactMap(\.url) == ["javascript:alert(1)"], "a folder of a bookmarklet comes over")
        expect(plan.spaces.first?.today.compactMap(\.url) == ["https://example.com/news", "file:///Users/me/notes.html",
                                                              "javascript:void(document.title)", "about:preferences"],
               "open tabs come over whatever their address; about:blank, about:newtab, about:home and blob: left out")
    }

    // promise: #742
    /// Zen (a profile made here): tabs come over whatever their address, and a pinned tab whose
    /// pinned page is a new tab page comes over pinned, at the page it shows.
    private static func zenImport() throws {
        let root = try firefoxRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try ZenImporter.plan(root: root)
        let home = plan.spaces.first
        expect(home?.today.compactMap(\.url) == ["file:///Users/me/notes.html", "javascript:void(document.title)", "about:preferences"],
               "Zen's tabs come over whatever their address; about:blank, about:newtab and blob: left out")
        expect(home?.pinned.compactMap(\.url) == ["https://status.example.com/now"] && home?.pinned.first?.pageTitle == "Status now",
               "a tab pinned with a new tab page comes over pinned, at the page it shows and that page's title")
    }

    // promise: #742
    /// Safari's exported Bookmarks.html (Tests/Fixtures/Safari): bookmarks come over whatever
    /// their address, and a folder of only blank ones is left out.
    private static func safariImport() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Safari")
        let pinned = try SafariImporter.read(folder).plan.spaces.first?.pinned ?? []
        expect(pinned.map(\.pageTitle) == ["News", "Notes", "Bookmarklet", "Open in Safari", "Tools"],
               "Favorites and folders come over whatever their address; about:blank and blob: left out, and a folder of only about:blank")
        expect(pinned.compactMap(\.url) == ["https://example.com/news", "file:///Users/me/notes.html", "javascript:void(document.title)",
                                            "x-safari-https://example.com/"], "each at its own address")
    }

    /// A Firefox root as Firefox and Zen write it: profiles.ini, then one profile with
    /// places.sqlite, Firefox's session store and Zen's sidebar file, each with tabs and
    /// bookmarks at every kind of address.
    private static func firefoxRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-firefox-\(UUID().uuidString)", isDirectory: true)
        let profile = root.appendingPathComponent("abc.default-release", isDirectory: true)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try Data("[Profile0]\nName=default-release\nIsRelative=1\nPath=abc.default-release\nDefault=1\n".utf8)
            .write(to: root.appendingPathComponent("profiles.ini"))
        var db: OpaquePointer?
        sqlite3_open(profile.appendingPathComponent("places.sqlite").path, &db)
        sqlite3_exec(db, """
            CREATE TABLE moz_places (id INTEGER PRIMARY KEY, url TEXT, title TEXT);
            CREATE TABLE moz_bookmarks (id INTEGER PRIMARY KEY, type INTEGER, fk INTEGER, parent INTEGER, position INTEGER,
                                        title TEXT, guid TEXT, dateAdded INTEGER);
            INSERT INTO moz_places VALUES (1, 'https://example.com/news', 'News'), (2, 'file:///Users/me/notes.html', 'Notes'),
                (3, 'javascript:void(document.title)', ''), (4, 'about:preferences', ''), (5, 'place:sort=8&maxResults=10', ''),
                (6, 'about:blank', ''), (7, 'blob:https://example.com/5f1c', ''), (8, 'place:type=6', ''), (9, 'javascript:alert(1)', '');
            INSERT INTO moz_bookmarks VALUES (1, 2, NULL, 0, 0, '', 'root________', 0), (3, 2, NULL, 1, 0, 'toolbar', 'toolbar_____', 0),
                (10, 1, 1, 3, 0, 'News', 'b10', 0), (11, 1, 2, 3, 1, 'Notes', 'b11', 0), (12, 1, 3, 3, 2, 'Bookmarklet', 'b12', 0),
                (13, 1, 4, 3, 3, 'Settings', 'b13', 0), (14, 1, 5, 3, 4, 'Most Visited', 'b14', 0), (15, 1, 6, 3, 5, 'Blank', 'b15', 0),
                (16, 1, 7, 3, 6, 'Download', 'b16', 0), (17, 2, NULL, 3, 7, 'Smart', 'b17', 0), (18, 1, 8, 17, 0, 'Recent Tags', 'b18', 0),
                (19, 2, NULL, 3, 8, 'Tools', 'b19', 0), (20, 1, 9, 19, 0, 'Alert', 'b20', 0);
            """, nil, nil, nil)
        sqlite3_close(db)
        func entry(_ url: String) -> [String: Any] { ["entries": [["url": url, "title": url]], "index": 1, "zenWorkspace": "s1"] }
        let addresses = ["https://example.com/news", "file:///Users/me/notes.html", "javascript:void(document.title)", "about:preferences",
                         "about:blank", "about:newtab", "about:home", "blob:https://example.com/5f1c"]
        try mozLz4(["windows": [["tabs": addresses.map(entry)]]]).write(to: profile.appendingPathComponent("sessionstore.jsonlz4"))
        var pinned = entry("https://status.example.com/now")
        pinned["entries"] = [["url": "https://status.example.com/now", "title": "Status now"]]
        pinned["pinned"] = true
        pinned["_zenPinnedInitialState"] = ["entry": ["url": "about:newtab", "title": "New Tab"]]
        let zenTabs = [pinned] + ["file:///Users/me/notes.html", "javascript:void(document.title)", "about:preferences",
                                  "about:blank", "about:newtab", "blob:https://example.com/5f1c"].map(entry)
        try mozLz4(["spaces": [["uuid": "s1", "name": "Home", "position": 0]], "tabs": zenTabs, "folders": [Any]()])
            .write(to: profile.appendingPathComponent("zen-sessions.jsonlz4"))
        return root
    }

    /// Firefox's mozLz4: "mozLz40\0", the size as a little-endian uint32, one raw LZ4 block.
    private static func mozLz4(_ object: Any) throws -> Data {
        let json = try JSONSerialization.data(withJSONObject: object)
        var block = Data(count: json.count + json.count / 255 + 64)
        let n = block.withUnsafeMutableBytes { out in json.withUnsafeBytes { src in
            compression_encode_buffer(out.bindMemory(to: UInt8.self).baseAddress!, out.count,
                                      src.bindMemory(to: UInt8.self).baseAddress!, json.count, nil, COMPRESSION_LZ4_RAW)
        } }
        var size = UInt32(json.count).littleEndian
        return Data("mozLz40\0".utf8) + Data(bytes: &size, count: 4) + block.prefix(n)
    }

    /// A browser someone has already deleted still leaves its profile behind, and the import
    /// reads only that: Chrome and Firefox are offered from their data alone, as Arc, Dia and Zen
    /// are. Requiring the app too left a Chrome switcher with only Safari (X DM, 12 Nov).
    private static func deletedBrowserStillImports() {
        let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        let chrome = ImportSource(id: "chrome", name: "Chrome", bundleID: "app.cra.tests.not-installed", kind: .chromium,
                                  dataDir: fixtures.appendingPathComponent("Chromium"))
        expect(!chrome.isInstalled && chrome.isAvailable, "a Chrome profile without the app is offered")
        let firefoxRoot = FileManager.default.temporaryDirectory.appendingPathComponent("cra-firefox-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: firefoxRoot) }
        try? FileManager.default.createDirectory(at: firefoxRoot.appendingPathComponent("abc.default-release"), withIntermediateDirectories: true)
        try? Data("[Profile0]\nName=default-release\nIsRelative=1\nPath=abc.default-release\nDefault=1\n".utf8)
            .write(to: firefoxRoot.appendingPathComponent("profiles.ini"))
        FileManager.default.createFile(atPath: firefoxRoot.appendingPathComponent("abc.default-release/places.sqlite").path, contents: Data())
        let firefox = ImportSource(id: "firefox", name: "Firefox", bundleID: "app.cra.tests.not-installed", kind: .firefox, dataDir: firefoxRoot)
        expect(!firefox.isInstalled && firefox.isAvailable, "a Firefox profile without the app is offered")
        let empty = ImportSource(id: "chrome", name: "Chrome", bundleID: "app.cra.tests.not-installed", kind: .chromium,
                                 dataDir: firefoxRoot.appendingPathComponent("none"))
        expect(!empty.isAvailable, "no profile, nothing to offer")
    }

    /// Current macOS can keep Chrome's and Brave's folders from other apps. Cra listed only the
    /// browsers it could read, so Chrome vanished from the picker while Ardia, which asks for
    /// Full Disk Access instead, imported it (X DM, 15 Nov). A folder that is there but refused
    /// is offered, flagged as needing Full Disk Access.
    private static func protectedBrowserAsksForFullDiskAccess() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cra-protected-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root.appendingPathComponent("Default"), withIntermediateDirectories: true)
        fm.createFile(atPath: root.appendingPathComponent("Default/History").path, contents: Data())
        let chrome = ImportSource(id: "chrome", name: "Chrome", bundleID: "app.cra.tests.not-installed", kind: .chromium, dataDir: root)
        expect(chrome.isAvailable && !chrome.needsFullDiskAccess, "a readable Chrome folder needs nothing more")
        try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? fm.removeItem(at: root)
        }
        expect(chrome.isAvailable, "a Chrome folder macOS won't let Cra read is still offered")
        expect(chrome.needsFullDiskAccess, "and it asks for Full Disk Access")
        let missing = ImportSource(id: "brave", name: "Brave", bundleID: "app.cra.tests.not-installed", kind: .chromium,
                                   dataDir: root.deletingLastPathComponent().appendingPathComponent("cra-none-\(UUID().uuidString)"))
        expect(!missing.isAvailable && !missing.needsFullDiskAccess, "a browser never used is neither offered nor asks")
    }

    // promise: #757
    /// The import list decides from a browser's own folder being there, never from what's inside:
    /// reading inside Chrome's folder on first launch made macOS show "Data Access Blocked … tried
    /// to access your data from other apps" before anything was picked (#757). A folder with
    /// nothing readable in it is offered; reading it waits until it's picked.
    private static func importListReadsNothingInsideABrowsersFolder() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cra-757-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? fm.removeItem(at: root)
        }
        let chrome = ImportSource(id: "chrome", name: "Chrome", bundleID: "app.cra.tests.not-installed", kind: .chromium, dataDir: root)
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
        expect(chrome.isAvailable, "an empty Chrome folder that's there is offered: whether it holds a profile shows once it's picked")
        try? fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        expect(chrome.isAvailable, "and so is one macOS won't let Cra read")
        let arcHome = fm.temporaryDirectory.appendingPathComponent("cra-757-arc-\(UUID().uuidString)", isDirectory: true)
        try? fm.createDirectory(at: arcHome, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: arcHome) }
        let arc = ImportSource(id: "arc", name: "Arc", bundleID: "app.cra.tests.not-installed", kind: .arc,
                               dataDir: arcHome.appendingPathComponent("User Data"), ownFolder: arcHome)
        expect(arc.isAvailable, "Arc is offered from its own folder, not from StorableSidebar.json inside it")
        let gone = ImportSource(id: "brave", name: "Brave", bundleID: "app.cra.tests.not-installed", kind: .chromium,
                                dataDir: root.appendingPathComponent("never-made"))
        expect(!gone.isAvailable, "a browser whose folder isn't there is listed dimmed")
    }

    /// Chrome signed in to a Google account keeps the bookmarks saved there in AccountBookmarks,
    /// and Local State lists every profile folder. Ardia reads both; Cra looked only for
    /// Bookmarks, History, Cookies and Login Data in folders named Default or "Profile N".
    private static func signedInChromeProfileImports() {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("cra-signed-in-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: root) }
        let profile = root.appendingPathComponent("Work", isDirectory: true)
        try? fm.createDirectory(at: profile, withIntermediateDirectories: true)
        try? Data(#"{"profile":{"info_cache":{"Work":{"name":"Work"}},"profiles_order":["Work"]}}"#.utf8)
            .write(to: root.appendingPathComponent("Local State"))
        try? Data("{}".utf8).write(to: profile.appendingPathComponent("Preferences"))
        try? Data(#"{"roots":{"bookmark_bar":{"children":[{"type":"url","name":"Docs","url":"https://docs.example.com/"}]}}}"#.utf8)
            .write(to: profile.appendingPathComponent("AccountBookmarks"))
        let profiles = ChromiumImporter.profiles(userData: root)
        expect(profiles.map(\.id) == ["Work"] && profiles.first?.name == "Work", "a profile Local State lists is found by its folder")
        expect(ChromiumImporter.bookmarks(profile: profile).bar.map(\.url) == ["https://docs.example.com/"],
               "bookmarks saved to the Google account come over")
        let chrome = ImportSource(id: "chrome", name: "Chrome", bundleID: "app.cra.tests.not-installed", kind: .chromium, dataDir: root)
        expect(chrome.isAvailable, "a signed-in Chrome with only account bookmarks is offered")
    }

    // promise: #228
    /// Chrome 139 and later turn every Manifest V2 extension off (disable reason 1 << 23);
    /// Cra runs them (extensions-manifest-v2.patch), so an import from Chrome brings uBlock
    /// Origin over turned on unless the person had turned it off too.
    private static func chromiumManifestV2Import() {
        let profile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Chromium/Default")
        expect(ExtensionImporter.disabledIDs(inProfile: profile) == ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "dddddddddddddddddddddddddddddddd"],
               "off only for being Manifest V2 counts as on; off by the person as well stays off")
    }

    /// Arc archives unused Today tabs on a 30-minute pass; the selected tab stays.
    @MainActor
    private static func autoArchive() {
        let clock = ManualScheduler()
        let composition = AppComposition(clock: clock)
        let store = composition.store
        store.settings.autoArchiveEnabled = true
        store.settings.autoArchive = .twelveHours
        let idle = store.createTab(url: "https://example.com/idle", select: false)
        let shown = store.createTab(url: "https://example.com/shown", select: true)
        composition.startPeriodicWork {}
        func archived(_ id: UUID) -> Bool { store.item(id) == nil }
        clock.advance(by: 12 * 3600 - 1)
        expect(!archived(idle.id), "a tab is kept until it has been unused for the whole threshold")
        // The model stamps createdAt from the real clock, a moment after this one started:
        // the pass at exactly 12 h still sees the tab as fresh, the one after archives it.
        clock.advance(by: AppComposition.autoArchiveInterval + 1)
        expect(archived(idle.id), "the next pass after the threshold archives it")
        expect(!archived(shown.id), "the selected tab is never archived")
        store.settings.autoArchiveEnabled = false
        let later = store.createTab(url: "https://example.com/later", select: false)
        clock.advance(by: 48 * 3600)
        expect(!archived(later.id), "with auto-archive off nothing is archived")
    }

    /// Each pass says how many tabs it sent to the Archive, for Arc's "Auto archived N tabs" toast (X, 25 Nov 2026:
    /// tabs archived overnight looked lost). The launch's pass counts too: after a night away or an update restart it
    /// is the one that archives. An empty tab leaves nothing in the Archive and isn't counted.
    @MainActor
    private static func autoArchiveCounts() {
        let clock = ManualScheduler()
        let composition = AppComposition(clock: clock)
        let store = composition.store
        store.settings.autoArchiveEnabled = true
        store.settings.autoArchive = .twelveHours
        _ = store.createTab(url: "https://example.com/night-one", select: false)
        _ = store.createTab(url: "https://example.com/night-two", select: false)
        _ = store.createTab(url: "", select: false)
        _ = store.createTab(url: "https://example.com/shown", select: true)
        // Away all night: the next launch's pass archives them.
        clock.advance(by: 13 * 3600)
        var passes: [Int] = []
        composition.startPeriodicWork(autoArchived: { passes.append($0) }) {}
        expect(passes == [2], "the launch's pass counts the two pages, not the empty tab or the selected one: \(passes)")
        _ = store.createTab(url: "https://example.com/later", select: false)
        clock.advance(by: 12 * 3600 + AppComposition.autoArchiveInterval + 1)
        expect(passes.last == 1, "a later pass counts its own: \(passes)")
        expect(passes.dropFirst().dropLast().allSatisfy { $0 == 0 }, "passes that archive nothing say 0: \(passes)")
    }

    // promise: #278
    /// 180 days, past Arc's 30 (#278): kept until the whole threshold has passed unused, archived
    /// by the next pass after it; the selected tab and pinned tabs never are.
    @MainActor
    private static func longAutoArchive() {
        let clock = ManualScheduler()
        let composition = AppComposition(clock: clock)
        let store = composition.store
        store.settings.autoArchiveEnabled = true
        store.settings.autoArchive = .oneHundredEightyDays
        let idle = store.createTab(url: "https://example.com/idle-long", select: false)
        let pinned = store.createTab(url: "https://example.com/pinned-long", pinned: true, select: false)
        let shown = store.createTab(url: "https://example.com/shown-long", select: true)
        composition.startPeriodicWork {}
        func archived(_ id: UUID) -> Bool { store.item(id) == nil }
        clock.advance(by: 179 * 86400)
        expect(!archived(idle.id), "a Today tab unused for 179 days is kept at 180")
        clock.advance(by: 86400 + AppComposition.autoArchiveInterval + 1)
        expect(archived(idle.id), "the next pass after 180 days archives it")
        expect(!archived(shown.id), "the selected tab is never archived")
        expect(!archived(pinned.id), "pinned tabs are never auto-archived")
    }

    // promise: #693
    /// Each profile's own "Archive tabs after", as in Arc: a space on a Work profile set to 7 days keeps
    /// its tabs while the Default space's go after 12 hours, and a profile set to Never keeps them all.
    @MainActor
    private static func profileAutoArchive() {
        let clock = ManualScheduler()
        let composition = AppComposition(clock: clock)
        let store = composition.store
        let work = store.createProfile(name: "Work")
        let school = store.createProfile(name: "School")
        let profiles = store.profiles.map(\.id)
        store.settings.setAutoArchive(.after(.twelveHours), profileID: nil, otherProfiles: profiles)
        store.settings.setAutoArchive(.after(.sevenDays), profileID: work.id, otherProfiles: profiles)
        store.settings.setAutoArchive(.never, profileID: school.id, otherProfiles: profiles)
        let home = store.focusedSpaceID
        var workSpace = store.createSpace(title: "Work", emoji: "", focus: false)
        workSpace.profileID = work.id
        store.updateSpace(workSpace)
        var schoolSpace = store.createSpace(title: "School", emoji: "", focus: false)
        schoolSpace.profileID = school.id
        store.updateSpace(schoolSpace)
        let personal = store.createTab(url: "https://example.com/personal", in: home, select: false)
        let job = store.createTab(url: "https://example.com/job", in: workSpace.id, select: false)
        let homework = store.createTab(url: "https://example.com/homework", in: schoolSpace.id, select: false)
        composition.startPeriodicWork {}
        func archived(_ id: UUID) -> Bool { store.item(id) == nil }
        clock.advance(by: 12 * 3600 + AppComposition.autoArchiveInterval + 1)
        expect(archived(personal.id), "the Default space's tab goes after Default's 12 hours")
        expect(!archived(job.id), "the Work space's tab stays: Work archives after 7 days")
        clock.advance(by: 7 * 86400)
        expect(archived(job.id), "after 7 days the Work tab goes too")
        expect(!archived(homework.id), "School's Never keeps its tab")
    }

    // promise: #136
    /// Tab sleeping asks the windows once a minute; like Arc, it has no switch.
    @MainActor
    private static func tabSleepCadence() {
        let clock = ManualScheduler()
        let composition = AppComposition(clock: clock)
        var passes = 0
        composition.startPeriodicWork { passes += 1 }
        clock.advance(by: 59)
        expect(passes == 0, "no pass before the first minute")
        clock.advance(by: 1)
        expect(passes == 1, "a pass every minute")
        clock.advance(by: 9 * 60)
        expect(passes == 10, "ten passes in ten minutes")
        composition.startPeriodicWork { passes += 100 }
        expect(clock.pendingCount == 2, "starting again replaces the timers instead of adding to them")
    }

    // promise: #136
    /// Tabs rest on Arc 1.171's own numbers (#136): a page out of sight 30 minutes is voted to
    /// freeze, one out of sight 4 hours sleeps, and the 10 tabs used last are never touched.
    private static func tabRestTimes() {
        expect(AppComposition.tabFreezeAfter == 30 * 60, "a hidden page is voted to freeze after 30 minutes, Arc's timeToFreezeTab")
        expect(TabSleepPolicy.timer(AppSettings().tabSleepAfter).hiddenFor == 4 * 3600 && AppSettings().tabSleepTimerEnabled,
               "a hidden page sleeps after 4 hours, with no setting to turn on, Arc's timeToDiscardTab")
        expect(TabSleepPolicy.protectedRecentTabs == 10 && TabSleepPolicy.timer(AppSettings().tabSleepAfter).keepsRecentTabs,
               "the 10 tabs used last keep their pages, Arc's protectedLRUTabCount")
    }

    /// The integrity check stays quiet through ordinary changes and names a broken link.
    @MainActor
    private static func integrity() {
        let store = AppComposition(clock: ManualScheduler()).store
        expect(store.integrityProblems().isEmpty, "a fresh sidebar is sound")
        let a = store.createTab(url: "https://example.com/a")
        let b = store.createTab(url: "https://example.com/b", pinned: true)
        store.createTab(url: "https://example.com/c", select: false)
        store.archiveTab(a.id, reason: .manual)
        store.reopenLastArchived()
        expect(store.integrityProblems().isEmpty, "creating, pinning, archiving and reopening keep it sound")
        var parent = store.item(b.parentID!)!
        parent.children.removeAll { $0 == b.id }
        store.items[parent.id] = parent
        let problems = store.integrityProblems()
        expect(problems.count == 1 && problems[0].contains("not listed by its parent"), "a tab its parent lost is reported")
        parent.children.append(b.id)
        store.items[parent.id] = parent
        let today = store.focusedSpace.todayContainerID
        var other = store.item(today)!
        other.children.append(b.id)
        store.items[today] = other
        expect(store.integrityProblems().contains { $0.contains("listed by both") }, "a tab listed by two parents is reported")
        other.children.removeLast()
        store.items[today] = other
        let second = store.createSpace(title: "Second", emoji: "2", focus: false)
        store.prefs.windows[0].selectedTabPerSpace[second.id] = b.id
        expect(store.integrityProblems().contains { $0.contains("lives elsewhere") }, "a window selecting another space's tab is reported")
    }

    /// A pull request that left the results stays for the grace period, then goes, all on the clock.
    @MainActor
    private static func liveFolderExpiry() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        guard let folder = store.createLiveFolder(.github, inSpace: store.focusedSpaceID) else { return expect(false, "a live folder is made") }
        let one = LivePullRequest(owner: "cra", repo: "cra", number: 1, title: "One")
        let two = LivePullRequest(owner: "cra", repo: "cra", number: 2, title: "Two")
        store.applyLiveResults([one, two], to: folder.id, ssoOrganizations: [])
        expect(store.item(folder.id)?.liveFolder?.lastFetch == clock.now && store.children(of: folder.id).count == 2,
               "a refresh fills the folder and stamps the fetch with the clock")
        clock.advance(by: 600)
        store.applyLiveResults([one], to: folder.id, ssoOrganizations: [])
        let gone = store.children(of: folder.id).first { $0.tab?.liveItemURL == two.url }
        expect(gone?.tab?.liveGoneAt == clock.now, "a pull request that left the results is marked gone now")
        clock.advance(by: 3599)
        store.expireLiveItems(olderThan: 3600)
        expect(store.children(of: folder.id).count == 2, "it stays through the grace period")
        clock.advance(by: 1)
        store.expireLiveItems(olderThan: 3600)
        expect(store.children(of: folder.id).map(\.tab?.liveItemURL) == [one.url], "and goes when it ends")
        expect(store.integrityProblems().isEmpty, "live folder changes keep the sidebar sound")
    }

    @MainActor
    private static func pluginFolderResults() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        let configuration = LiveFolderPluginConfiguration(id: "custom.tasks", settings: [:], filters: ["mine"], sessionOrigins: ["https://example.test"])
        guard let folder = store.createPluginFolder(configuration, title: "Tasks", inSpace: store.focusedSpaceID) else {
            return expect(false, "a plugin folder is created")
        }
        let one = LiveFolderPluginItem(id: "one", url: "https://example.test/one", title: "One", subtitle: "alice", group: "team/app")
        let two = LiveFolderPluginItem(id: "two", url: "https://example.test/two", title: "Two", group: "protected/app")
        store.applyPluginResults(.init(items: [one, two]), to: folder.id)
        expect(store.children(of: folder.id).count == 2, "plugin results create native tabs")
        expect(store.children(of: folder.id).first?.tab?.liveSubtitle == "alice", "plugin subtitles reach the row model")
        guard let tab = store.children(of: folder.id).first(where: { $0.tab?.liveItemURL == one.url }) else {
            return expect(false, "the plugin item has a tab")
        }
        store.updateTab(tab.id, url: "https://example.test/other", title: "Other page")
        expect(store.item(tab.id)?.tab?.savedTitle == "Other page", "navigation away uses the page title")
        store.updateTab(tab.id, url: one.url)
        expect(store.item(tab.id)?.tab?.savedTitle == one.title, "returning restores the plugin title without a refresh")
        store.updateTab(tab.id, title: "Page title after returning")
        expect(store.item(tab.id)?.tab?.savedTitle == one.title, "a later page title does not replace the restored plugin title")
        store.updateTab(tab.id, url: "https://example.test/other", title: "Other page")
        store.updateTab(tab.id, url: one.url, title: "Page title on return")
        expect(store.item(tab.id)?.tab?.savedTitle == one.title, "combined URL and title events restore the plugin title")
        let context = store.liveRequestContext(folder.id)
        store.updateLiveFolder(folder.id) { $0.plugin?.filters = [] }
        store.applyPluginResults(.init(items: []), to: folder.id, context: context)
        expect(store.children(of: folder.id).allSatisfy { $0.tab?.liveGoneAt == nil }, "old-filter responses do not remove tabs")
        store.applyPluginResults(.init(items: [one], preservedGroups: ["protected/app"]), to: folder.id)
        store.applyPluginResults(.init(items: [one], preservedGroups: ["protected/app"]), to: folder.id)
        expect(store.children(of: folder.id).allSatisfy { $0.tab?.liveGoneAt == nil }, "protected groups survive consecutive partial authorizations")
        store.updateLiveFolder(folder.id) { $0.plugin?.filters = ["mine"] }
        store.applyPluginResults(.init(items: [one, two]), to: folder.id)
        store.updateLiveFolder(folder.id) { $0.plugin?.filters = [] }
        expect(store.children(of: folder.id).count == 2, "changing a filter waits for its refresh result")
        store.applyLiveFailure(.notSignedIn, to: folder.id)
        expect(store.children(of: folder.id).count == 2, "a failed filter refresh preserves existing tabs")
        store.applyPluginResults(.init(items: [one]), to: folder.id)
        expect(store.children(of: folder.id).map(\.tab?.liveItemURL) == [one.url], "a successful filter refresh removes excluded items without retention")
        store.applyPluginResults(.init(items: []), to: folder.id)
        expect(store.children(of: folder.id).first?.tab?.liveGoneAt != nil, "a later background refresh still retains disappeared items")
        store.applyPluginResults(.init(items: [one, two]), to: folder.id)
        store.updateLiveFolder(folder.id) { $0.hiddenItems = [one.url] }
        store.applyPluginResults(.init(items: [one, two]), to: folder.id)
        clock.advance(by: 121)
        store.expireLiveItems(olderThan: 120)
        expect(store.children(of: folder.id).map(\.tab?.liveItemURL) == [two.url], "hidden plugin items do not return")
        expect(store.integrityProblems().isEmpty, "plugin updates preserve sidebar integrity")
    }

    @MainActor
    private static func liveRepositoryFiltering() {
        for source in [LiveFolderSource.github, .gitlab] {
            let clock = ManualScheduler()
            let store = AppComposition(clock: clock).store
            let space = store.createSpace(title: "Repository filters", emoji: "R", focus: true)
            let server = "https://git.example.test:8443/gitlab"
            guard let folder = store.createLiveFolder(source, inSpace: space.id, serverURL: source == .gitlab ? server : nil) else {
                return expect(false, "a live folder exists for repository filtering")
            }
            let one = source == .gitlab ? gitLabRequest(70, server: server) : LivePullRequest(owner: "company", repo: "app", number: 70, title: "One")
            let two = source == .gitlab ? gitLabRequest(71, server: server) : LivePullRequest(owner: "company", repo: "app", number: 71, title: "Two")
            var other = LivePullRequest(owner: "company", repo: "other", number: 72, title: "Other")
            if source == .gitlab { other.webURL = "\(server)/company/other/-/merge_requests/72" }
            let requests = [one, two, other]
            store.applyLiveResults(requests, to: folder.id, ssoOrganizations: [])
            guard let selected = store.children(of: folder.id).first(where: { $0.tab?.liveItemURL == one.url }),
                  let navigated = store.children(of: folder.id).first(where: { $0.tab?.liveItemURL == two.url }) else {
                return expect(false, "the repository's request tabs exist")
            }
            store.selectTab(selected.id)
            store.updateTab(navigated.id, url: "https://example.test/reading", title: "Reading")
            store.updateLiveFolder(folder.id) { $0.filter.hiddenRepositories = [one.repository.uppercased()] }
            store.applyLiveResults(requests, to: folder.id, ssoOrganizations: [])
            expect(store.item(selected.id) == nil, "excluding a repository removes its request immediately after refresh, even when selected")
            expect(store.selectedTabID == nil, "excluding the selected request clears the window's selection")
            expect(Set(store.children(of: folder.id).compactMap { $0.tab?.liveItemURL }) == [two.url, other.url],
                   "excluding one repository keeps other repositories and a tab navigated away from its request")
            expect(store.item(navigated.id)?.tab?.url == "https://example.test/reading" && store.item(navigated.id)?.tab?.liveGoneAt == nil,
                   "the navigated tab stays in its live folder without an expiry timer")
            clock.advance(by: 600)
            store.expireLiveItems(olderThan: 120)
            expect(store.item(navigated.id) != nil, "the expiry pass does not remove a navigated request tab")
            store.updateLiveFolder(folder.id) { $0.filter.hiddenRepositories = [] }
            store.applyLiveResults(requests, to: folder.id, ssoOrganizations: [])
            expect(store.children(of: folder.id).count == 3 && store.item(navigated.id)?.tab?.url == "https://example.test/reading",
                   "including the repository restores its requests without replacing a navigated tab")
            store.updateLiveFolder(folder.id) { $0.filter.hiddenRepositories = [one.repository] }
            store.applyLiveResults([other], to: folder.id, ssoOrganizations: [])
            expect(store.item(navigated.id) != nil, "a navigated tab survives even when its excluded request is absent from the response")
            store.updateTab(navigated.id, url: two.url, title: "Two")
            store.applyLiveResults([other], to: folder.id, ssoOrganizations: [])
            expect(store.item(navigated.id) == nil, "returning to the excluded request removes it on the next refresh")
            expect(store.item(folder.id)?.liveFolder?.hiddenItems.isEmpty == true,
                   "excluding a repository does not permanently hide individual requests")
            expect(store.integrityProblems().isEmpty, "repository filtering keeps the sidebar sound")
        }
    }

    @MainActor
    private static func liveRepositoryMenus() {
        for source in [LiveFolderSource.github, .gitlab] {
            let store = AppComposition(clock: ManualScheduler()).store
            let space = store.createSpace(title: "Repository menu", emoji: "R", focus: true)
            let server = "https://git.example.test/gitlab"
            guard let folder = store.createLiveFolder(source, inSpace: space.id, serverURL: source == .gitlab ? server : nil) else {
                return expect(false, "a live folder exists for the repository menu")
            }
            let request = source == .gitlab ? gitLabRequest(80, server: server) : LivePullRequest(owner: "company", repo: "app", number: 80, title: "One")
            store.applyLiveResults([request], to: folder.id, ssoOrganizations: [])
            expect(store.liveRepositories(folder.id) == [request.repository],
                   "the repository menu can use saved live tabs before the manager has fetched anything")
            store.updateLiveFolder(folder.id) { $0.filter.hiddenRepositories = [request.repository.uppercased(), "company/hidden"] }
            let repositories = store.liveRepositories(folder.id)
            expect(repositories.count == 2 && repositories.contains(request.repository) && repositories.contains("company/hidden"),
                   "the repository menu includes hidden repositories without case-only duplicates")
            expect(store.liveRepositories(folder.id, fetched: []).map { $0.lowercased() }.sorted() == [request.repository, "company/hidden"].sorted(),
                   "hidden repositories stay available to reenable even after empty results")
            store.updateLiveFolder(folder.id) { $0.filter.hiddenRepositories = [] }
            expect(store.liveRepositories(folder.id, fetched: ["company/new"]) == ["company/new"],
                   "fresh results replace the saved-tab fallback")
            expect(store.liveRepositories(UUID()).isEmpty, "a deleted folder has no repository menu")
        }
    }

    // promise: #523
    /// A folder that 0.1.47 filled with merged pull requests (GitHub #523) cleans itself up after the
    /// update: the fixed plugin's first refresh leaves them out, they get the usual 120 s grace and go,
    /// except one showing in a window, which goes once the window shows something else.
    @MainActor
    private static func mergedPullRequestsLeaveAnUpdatedFolder() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        guard let folder = store.createLiveFolder(.github, inSpace: store.focusedSpaceID) else { return expect(false, "a live folder is made") }
        func pr(_ number: Int, _ title: String) -> LiveFolderPluginItem {
            let url = "https://github.com/team/app/pull/\(number)"
            return LiveFolderPluginItem(id: url, url: url, title: title, group: "team/app")
        }
        let open = pr(1, "Open"), merged = pr(2, "Merged"), shown = pr(3, "Merged and on screen")
        store.applyPluginResults(.init(items: [open, merged, shown]), to: folder.id)
        expect(store.children(of: folder.id).count == 3, "the folder as 0.1.47 left it, merged ones included")
        guard let shownTab = store.children(of: folder.id).first(where: { $0.tab?.liveItemURL == shown.url }) else {
            return expect(false, "the shown pull request has a tab")
        }
        store.prefs.windows[0].selectedTabPerSpace[store.focusedSpaceID] = shownTab.id

        clock.advance(by: 600)
        store.applyPluginResults(.init(items: [open]), to: folder.id)
        expect(store.children(of: folder.id).filter { $0.tab?.liveGoneAt == clock.now }.compactMap(\.tab?.liveItemURL).sorted()
               == [merged.url, shown.url], "the first refresh after the update marks both merged ones gone")
        clock.advance(by: 119)
        store.expireLiveItems(olderThan: 120)
        expect(store.children(of: folder.id).count == 3, "they stay through the grace period")
        clock.advance(by: 1)
        store.expireLiveItems(olderThan: 120)
        expect(store.children(of: folder.id).compactMap(\.tab?.liveItemURL).sorted() == [open.url, shown.url],
               "then the merged one goes, the one on screen stays")
        guard let openTab = store.children(of: folder.id).first(where: { $0.tab?.liveItemURL == open.url }) else {
            return expect(false, "the open pull request has a tab")
        }
        store.prefs.windows[0].selectedTabPerSpace[store.focusedSpaceID] = openTab.id
        store.expireLiveItems(olderThan: 120)
        expect(store.children(of: folder.id).compactMap(\.tab?.liveItemURL) == [open.url],
               "and it goes once the window shows another tab; only the open pull request is left")
        clock.advance(by: 600)
        store.applyPluginResults(.init(items: [open]), to: folder.id)
        store.expireLiveItems(olderThan: 120)
        expect(store.children(of: folder.id).compactMap(\.tab?.liveItemURL) == [open.url], "later refreshes don't bring them back")
        expect(store.integrityProblems().isEmpty, "the cleanup keeps the sidebar sound")
    }

    // promise: #697
    /// A pull request merged or closed while its tab sits on one of its own pages (Files changed, a
    /// comment link, owner/repo in another case, a query) leaves the folder after the grace like an
    /// unopened one. Before #697 only a tab on exactly the listed address could go, so a pull
    /// request you'd looked at stayed in the folder for good. A tab on another page stays (Arc).
    @MainActor
    private static func closedPullRequestsLeaveFromTheirOwnPages() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        guard let folder = store.createLiveFolder(.github, inSpace: store.focusedSpaceID) else { return expect(false, "a live folder is made") }
        func pr(_ number: Int) -> LiveFolderPluginItem {
            let url = "https://github.com/team/app/pull/\(number)"
            return LiveFolderPluginItem(id: url, url: url, title: "PR \(number)", group: "team/app")
        }
        let open = pr(1), files = pr(5), comment = pr(6), query = pr(7), other = pr(8), longer = pr(9)
        store.applyPluginResults(.init(items: [open, files, comment, query, other, longer]), to: folder.id)
        func tab(_ item: LiveFolderPluginItem) -> UUID? { store.children(of: folder.id).first { $0.tab?.liveItemURL == item.url }?.id }
        guard let filesTab = tab(files), let commentTab = tab(comment), let queryTab = tab(query),
              let otherTab = tab(other), let longerTab = tab(longer), let openTab = tab(open) else {
            return expect(false, "every pull request has a tab")
        }
        store.updateTab(filesTab, url: files.url + "/files", title: "Files")
        store.updateTab(commentTab, url: "https://github.com/Team/App/pull/6#issuecomment-42", title: "Comment")
        store.updateTab(queryTab, url: query.url + "?w=1", title: "Query")
        store.updateTab(otherTab, url: "https://example.test/reading", title: "Reading")
        store.updateTab(longerTab, url: "https://github.com/team/app/pull/90", title: "Another pull request")
        store.prefs.windows[0].selectedTabPerSpace[store.focusedSpaceID] = openTab

        clock.advance(by: 600)
        store.applyPluginResults(.init(items: [open]), to: folder.id)
        clock.advance(by: 120)
        store.expireLiveItems(olderThan: 120)
        let left = Set(store.children(of: folder.id).compactMap(\.tab?.liveItemURL))
        expect(left == [open.url, other.url, longer.url],
               "merged pull requests on their own pages go; one on another page or another pull request stays: \(left)")
        expect(store.item(longerTab)?.tab?.savedTitle == "Another pull request", "pull request 90's page keeps its own title, not pull request 9's")
        expect(store.item(filesTab) == nil || store.item(filesTab)?.tab?.savedTitle == "PR 5", "a pull request's own pages keep its title")
        expect(store.integrityProblems().isEmpty, "the cleanup keeps the sidebar sound")
    }

    // promise: #697
    /// The other half of #697 stays as Arc has it (its hiddenItems): a pull request closed out of the
    /// folder by hand stays out on every refresh, and Reopen Closed Tab (⇧⌘T) puts it back.
    @MainActor
    private static func closedPullRequestsStayOutAcrossRefreshes() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        guard let folder = store.createLiveFolder(.github, inSpace: store.focusedSpaceID) else { return expect(false, "a live folder is made") }
        let items = [1, 2].map { n -> LiveFolderPluginItem in
            let url = "https://github.com/team/app/pull/\(n)"
            return LiveFolderPluginItem(id: url, url: url, title: "PR \(n)", group: "team/app")
        }
        store.applyPluginResults(.init(items: items), to: folder.id)
        guard let closed = store.children(of: folder.id).first(where: { $0.tab?.liveItemURL == items[1].url }) else {
            return expect(false, "the pull request has a tab")
        }
        store.archiveTab(closed.id, reason: .manual)
        for _ in 0..<3 {
            clock.advance(by: 600)
            store.applyPluginResults(.init(items: items), to: folder.id)
            store.expireLiveItems(olderThan: 120)
        }
        expect(store.children(of: folder.id).compactMap(\.tab?.liveItemURL) == [items[0].url], "refreshes leave the closed pull request out")
        if let archived = store.archive.first(where: { $0.item.tab?.liveItemURL == items[1].url }) { store.restoreArchived(archived.id, select: false) }
        clock.advance(by: 600)
        store.applyPluginResults(.init(items: items), to: folder.id)
        expect(Set(store.children(of: folder.id).compactMap(\.tab?.liveItemURL)) == Set(items.map(\.url)),
               "Reopen Closed Tab puts it back, and the next refresh keeps it")
        expect(store.item(folder.id)?.liveFolder?.hiddenItems.isEmpty == true, "nothing is hidden once it's back")
    }

    @MainActor
    private static func liveFolderExpiryKeepsNavigatedPages() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        let space = store.createSpace(title: "Navigated live request", emoji: "R", focus: true)
        guard let folder = store.createLiveFolder(.github, inSpace: space.id) else { return expect(false, "a live folder exists") }
        let request = LivePullRequest(owner: "company", repo: "app", number: 90, title: "One")
        store.applyLiveResults([request], to: folder.id, ssoOrganizations: [])
        guard let tab = store.children(of: folder.id).first else { return expect(false, "a live request tab exists") }
        store.applyLiveResults([], to: folder.id, ssoOrganizations: [])
        store.updateTab(tab.id, url: "https://example.test/reading", title: "Reading")
        clock.advance(by: 600)
        store.expireLiveItems(olderThan: 120)
        expect(store.item(tab.id)?.tab?.url == "https://example.test/reading", "expiry preserves the page a closed request navigated to")
        store.updateTab(tab.id, url: request.url, title: "One")
        store.expireLiveItems(olderThan: 120)
        expect(store.item(tab.id) == nil, "a closed request can expire once the tab is back on its request page")
        expect(store.integrityProblems().isEmpty, "expiry of a navigated live request keeps the sidebar sound")
    }

    private static func gitLabRequest(_ number: Int, server: String = "https://git.example.test") -> LivePullRequest {
        var request = LivePullRequest(owner: "company/team", repo: "app", number: number, title: "Merge request \(number)", createdByMe: true)
        request.webURL = "\(server)/company/team/app/-/merge_requests/\(number)"
        return request
    }

    @MainActor
    private static func liveFoldersRejectStandaloneSpaces() {
        let store = AppComposition(clock: ManualScheduler()).store
        let windows = [store.addBlankWindow(frame: nil), store.addIncognitoWindow(frame: nil)]
        for window in windows {
            let space = store.focusedSpaceID(window: window.id)
            for source in [LiveFolderSource.github, .gitlab] {
                expect(store.createLiveFolder(source, inSpace: space, serverURL: source == .gitlab ? "https://gitlab.com" : nil) == nil,
                       "neither provider creates live folders inside Blank or Incognito windows")
            }
        }
        expect(store.integrityProblems().isEmpty, "rejected live folders leave standalone windows unchanged")
    }

    @MainActor
    private static func gitLabProfileChangeKeepsNavigatedPages() {
        let store = AppComposition(clock: ManualScheduler()).store
        let space = store.createSpace(title: "GitLab navigated pages", emoji: "G", focus: true)
        guard let folder = store.createLiveFolder(.gitlab, inSpace: space.id, serverURL: "https://git.example.test") else { return expect(false, "a GitLab folder exists") }
        store.applyLiveResults([gitLabRequest(60)], to: folder.id, ssoOrganizations: [])
        guard let tab = store.tabs(under: folder.id).first else { return expect(false, "an MR tab exists") }
        store.selectTab(tab.id)
        store.updateTab(tab.id, url: "https://example.test/reading", title: "Reading")
        let profile = store.createProfile(name: "Other account")
        store.setProfile(profile.id, forSpace: space.id)
        expect(store.item(tab.id)?.tab?.url == "https://example.test/reading" && store.item(tab.id)?.tab?.savedTitle == "Reading",
               "a profile change keeps the page a live tab navigated to")
        expect(store.item(tab.id)?.parentID == space.todayContainerID && store.selectedTabID == tab.id,
               "the navigated page remains selected as an ordinary Today tab")
        expect(store.item(tab.id)?.tab?.liveItemURL == nil && store.integrityProblems().isEmpty,
               "the preserved page is no longer controlled by the live folder")
    }

    @MainActor
    private static func gitLabProfileChangeClearsResults() {
        let store = AppComposition(clock: ManualScheduler()).store
        let space = store.createSpace(title: "GitLab profiles", emoji: "G", focus: true)
        guard let folder = store.createLiveFolder(.gitlab, inSpace: space.id, serverURL: "https://git.example.test") else { return expect(false, "a GitLab folder exists") }
        store.applyLiveResults([gitLabRequest(41)], to: folder.id, ssoOrganizations: [])
        let oldContext = store.liveRequestContext(folder.id)
        store.updateLiveFolder(folder.id) { $0.hiddenItems = ["https://git.example.test/private/mr"] }
        let profile = store.createProfile(name: "Other GitLab account")
        store.setProfile(profile.id, forSpace: space.id)
        expect(store.tabs(under: folder.id).isEmpty, "changing profile clears the previous account's MR tabs")
        expect(store.item(folder.id)?.liveFolder?.lastFetch == nil, "changing profile makes the folder refresh at once")
        expect(store.item(folder.id)?.liveFolder?.hiddenItems.isEmpty == true, "the new profile does not inherit another account's exclusions")
        store.applyLiveResults([gitLabRequest(41)], to: folder.id, ssoOrganizations: [], context: oldContext)
        store.applyLiveFailure(.notSignedIn, to: folder.id, context: oldContext)
        expect(store.tabs(under: folder.id).isEmpty && store.item(folder.id)?.liveFolder?.lastError == nil,
               "late successes and failures from the previous profile are ignored")
        store.setProfile(nil, forSpace: space.id)
        expect(store.liveRequestContext(folder.id) != oldContext, "switching away and back still invalidates the original request")
        store.applyLiveResults([gitLabRequest(41)], to: folder.id, ssoOrganizations: [], context: oldContext)
        expect(store.tabs(under: folder.id).isEmpty, "returning to the original profile cannot revive an obsolete response")
        expect(store.integrityProblems().isEmpty, "profile invalidation keeps the tree sound")
    }

    @MainActor
    private static func gitLabFolderMovesRejectDuplicateServers() {
        let store = AppComposition(clock: ManualScheduler()).store
        let a = store.createSpace(title: "GitLab A", emoji: "A", focus: true)
        let b = store.createSpace(title: "GitLab B", emoji: "B", focus: false)
        guard let one = store.createLiveFolder(.gitlab, inSpace: a.id, serverURL: "https://git.example.test"),
              let two = store.createLiveFolder(.gitlab, inSpace: b.id, serverURL: "https://git.example.test") else { return expect(false, "both spaces have a server folder") }
        store.moveTab(one.id, toSpace: b.id)
        expect(store.spaceID(ofItem: one.id) == a.id && store.spaceID(ofItem: two.id) == b.id, "a folder move cannot create a duplicate server in the destination")
        let wrapper = store.createFolder(named: "Work", in: a.pinnedContainerID)
        store.moveItem(one.id, to: wrapper.id, index: nil)
        store.moveTab(wrapper.id, toSpace: b.id)
        expect(store.spaceID(ofItem: wrapper.id) == a.id, "wrapping a live folder does not bypass server uniqueness")
        let c = store.createSpace(title: "GitLab C", emoji: "C", focus: false)
        let profile = store.createProfile(name: "GitLab C account")
        store.setProfile(profile.id, forSpace: c.id)
        store.applyLiveResults([gitLabRequest(42)], to: one.id, ssoOrganizations: [])
        let context = store.liveRequestContext(one.id)
        store.moveTab(wrapper.id, toSpace: c.id)
        expect(store.spaceID(ofItem: one.id) == c.id && store.tabs(under: one.id).isEmpty,
               "moving a wrapper to a different profile invalidates its live folder results")
        store.applyLiveResults([gitLabRequest(42)], to: one.id, ssoOrganizations: [], context: context)
        expect(store.tabs(under: one.id).isEmpty, "a pre-move response cannot cross into the new profile")
        expect(store.integrityProblems().isEmpty, "rejected moves keep both spaces sound")
    }

    @MainActor
    private static func gitLabMultipleServers() {
        let store = AppComposition(clock: ManualScheduler()).store
        let space = store.createSpace(title: "GitLab servers", emoji: "G", focus: true)
        guard let one = store.createLiveFolder(.gitlab, inSpace: space.id, serverURL: "https://git.example.test"),
              let two = store.createLiveFolder(.gitlab, inSpace: space.id, serverURL: "https://gitlab.com") else {
            return expect(false, "folders for two GitLab servers can be created")
        }
        expect(one.id != two.id && one.title == "Merge Requests" && two.title == "Merge Requests",
               "each server has its own folder, named like Arc's Pull Requests folder")
        expect(one.liveFolder?.filter.attributes == [.authored, .reviewRequests, .assigned], "every filter starts on, as in Arc")
        let duplicate = store.createLiveFolder(.gitlab, inSpace: space.id, serverURL: "HTTPS://GIT.EXAMPLE.TEST:443/")
        expect(duplicate?.id == one.id, "equivalent server URLs reuse the existing folder")
        expect(store.liveFolder(.gitlab, inSpace: space.id, serverURL: "gitlab.com/")?.id == two.id, "server lookup identifies the right folder")
        store.applyLiveResults([gitLabRequest(30)], to: one.id, ssoOrganizations: [])
        store.applyLiveResults([gitLabRequest(30, server: "https://gitlab.com")], to: two.id, ssoOrganizations: [])
        if let tab = store.tabs(under: one.id).first { store.archiveTab(tab.id, reason: .manual) }
        expect(store.item(one.id)?.liveFolder?.hiddenItems.count == 1 && store.item(two.id)?.liveFolder?.hiddenItems.isEmpty == true,
               "hidden lists are independent even for matching project names and MR numbers")
        let three = store.createLiveFolder(.gitlab, inSpace: space.id, serverURL: "https://git.example.test:8443/gitlab")
        expect(three != nil && three?.id != one.id, "ports and installation paths distinguish GitLab instances")
        expect(store.createLiveFolder(.gitlab, inSpace: space.id, serverURL: "file:///etc") == nil, "invalid servers are rejected")
        let github = store.createLiveFolder(.github, inSpace: space.id)
        expect(store.createLiveFolder(.github, inSpace: space.id)?.id == github?.id, "GitHub still has one folder per space")
        store.deleteFolder(one.id)
        expect(store.item(two.id) != nil && store.tabs(under: two.id).count == 1, "deleting a server folder leaves the other server untouched")
        expect(store.integrityProblems().isEmpty, "multiple server folders keep the sidebar sound")
    }

    @MainActor
    private static func gitLabHiddenItems() {
        let store = AppComposition(clock: ManualScheduler()).store
        let space = store.createSpace(title: "GitLab hidden", emoji: "G", focus: true)
        guard let folder = store.createLiveFolder(.gitlab, inSpace: space.id, serverURL: "https://git.example.test") else {
            return expect(false, "a GitLab live folder is made")
        }
        let requests = [gitLabRequest(10), gitLabRequest(11)]
        store.applyLiveResults(requests, to: folder.id, ssoOrganizations: [])
        for tab in store.tabs(under: folder.id) { store.archiveTab(tab.id, reason: .manual) }
        expect(Set(store.item(folder.id)?.liveFolder?.hiddenItems ?? []) == Set(requests.map(\.url)), "closing an MR's tab hides it, as in Arc")
        store.applyLiveResults(requests, to: folder.id, ssoOrganizations: [])
        expect(store.tabs(under: folder.id).isEmpty, "refreshing does not restore hidden merge requests")
        if let archived = store.archive.first(where: { $0.item.tab?.liveItemURL == requests[1].url }) { store.restoreArchived(archived.id, select: false) }
        expect(store.tabs(under: folder.id).map(\.tab?.liveItemURL) == [requests[1].url], "Reopen Closed Tab puts the MR back in its folder")
        expect(store.item(folder.id)?.liveFolder?.hiddenItems == [requests[0].url], "the other MR remains hidden")
        guard let moved = store.tabs(under: folder.id).first else { return expect(false, "a tab can be moved out") }
        store.moveItem(moved.id, to: space.todayContainerID, index: 0)
        expect(store.item(folder.id)?.liveFolder?.hiddenItems.count == 2 && store.item(moved.id)?.tab?.liveItemURL == nil,
               "dragging an MR out of the folder hides it too")
        expect(store.integrityProblems().isEmpty, "hide and restore keep the sidebar sound")
    }

    @MainActor
    private static func gitLabFolderExpiryAndDeletion() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        let space = store.createSpace(title: "GitLab expiry", emoji: "G", focus: true)
        guard let folder = store.createLiveFolder(.gitlab, inSpace: space.id, serverURL: "https://git.example.test") else {
            return expect(false, "a GitLab live folder is made")
        }
        let requests = [gitLabRequest(20), gitLabRequest(21)]
        store.applyLiveResults(requests, to: folder.id, ssoOrganizations: [])
        store.applyLiveResults([requests[0]], to: folder.id, ssoOrganizations: [])
        clock.advance(by: 121)
        store.expireLiveItems(olderThan: 120)
        expect(store.tabs(under: folder.id).map(\.tab?.liveItemURL) == [requests[0].url], "a merged MR leaves after the grace period")
        expect(store.item(folder.id)?.liveFolder?.hiddenItems.isEmpty == true, "automatic expiry never hides an MR")
        let tabs = store.tabs(under: folder.id).map(\.id)
        store.deleteFolder(folder.id)
        expect(store.item(folder.id) == nil && tabs.allSatisfy { store.item($0) == nil }, "deleting the folder deletes its MR tabs")
        expect(store.integrityProblems().isEmpty, "deleting a live folder leaves no orphan tabs")
    }

    /// Every date the store writes comes from its clock.
    @MainActor
    private static func stampsUseTheClock() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        clock.advance(by: 86400)
        let a = store.createTab(url: "https://example.com/a"), b = store.createTab(url: "https://example.com/b")
        expect(store.item(b.id)?.tab?.timeLastActiveAt == clock.now, "selecting a tab stamps it with the clock")
        let split = store.createSplit(with: [a.id, b.id])
        expect(split?.split?.timeLastActiveAt == clock.now, "a new split is stamped with the clock")
        store.recordVisit(url: "https://example.com/a", title: "A", profile: nil)
        expect(store.history["https://example.com/a"]?.lastVisit == clock.now, "history visits use the clock")
        store.archiveLittleWindowPage(url: "https://example.com/little", title: "Little")
        expect(store.archive.first?.archivedAt == clock.now, "a Little Window's page is archived at the clock's time")
        let incognito = store.addIncognitoWindow(frame: nil)
        expect(incognito.focusedSpaceID.flatMap { store.spaces[$0] }?.createdAt == clock.now, "an incognito space is made at the clock's time")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #609
    /// A page's history entry keeps the profiles it was visited in, so a space's ⌘T suggests only its
    /// own profile's pages (CommandBarProfileScope). One visited on two profiles is suggested on both.
    @MainActor
    private static func visitsRememberTheirProfile() {
        let store = AppComposition(clock: ManualScheduler()).store
        let work = store.createProfile(name: "Work")
        store.recordVisit(url: "https://example.com/work", title: "Work page", profile: work.id)
        store.recordVisit(url: "https://example.com/home", title: "Home page", profile: nil)
        store.recordVisit(url: "https://example.com/both", title: "Both", profile: nil)
        store.recordVisit(url: "https://example.com/both", title: "Both", profile: work.id)
        store.recordVisit(url: "https://example.com/both", title: "Both", profile: work.id)
        let suggested = { (profile: UUID?) in
            Set(store.history.values.filter { CommandBarProfileScope.suggests($0, on: profile) }.map(\.url))
        }
        expect(suggested(work.id) == ["https://example.com/work", "https://example.com/both"], "Work's bar: \(suggested(work.id))")
        expect(suggested(nil) == ["https://example.com/home", "https://example.com/both"], "Default's bar: \(suggested(nil))")
        expect(store.history["https://example.com/both"]?.profiles == ["default", work.id.uuidString], "each profile once, in visit order")
        expect(store.history["https://example.com/both"]?.visitCount == 3, "visits still count across profiles")
    }

    // promise: #729
    /// history.json from before #609 has no profiles, so every profile's ⌘T suggested it. At launch each
    /// such entry takes the profiles whose Chromium History has its page: Work's page is suggested on
    /// Work only, Default's on Default only; one no History has stays on every profile. A History that
    /// can't be read changes nothing.
    @MainActor
    private static func historyFromBeforeProfilesTakesThemFromChromium() {
        func old(_ url: String) -> HistoryEntry {
            HistoryEntry(url: url, title: "Old", lastVisit: Date(timeIntervalSince1970: 1_700_000_000), visitCount: 2)
        }
        let urls = ["https://example.com/work-only", "https://example.com/home-only", "https://example.com/expired"]
        JSONStore<[HistoryEntry]>("history.json").saveNow(urls.map(old))
        let store = AppComposition(clock: ManualScheduler()).store
        let work = store.createProfile(name: "Work")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-chromium-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func history(_ folder: String, _ pages: [String]) {
            let dir = root.appendingPathComponent(folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var db: OpaquePointer?
            sqlite3_open(dir.appendingPathComponent("History").path, &db)
            sqlite3_exec(db, "CREATE TABLE urls (id INTEGER PRIMARY KEY, url LONGVARCHAR, title LONGVARCHAR)", nil, nil, nil)
            for p in pages { sqlite3_exec(db, "INSERT INTO urls (url, title) VALUES ('\(p)', '')", nil, nil, nil) }
            sqlite3_close(db)
        }
        func attribute() {
            var finished = false
            store.attributeHistoryProfiles(chromium: root) { finished = true }
            let deadline = Date().addingTimeInterval(10)
            while !finished && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
            expect(finished, "the attribution finishes")
        }
        func suggested(_ profile: UUID?) -> Set<String> {
            Set(store.history.values.filter { urls.contains($0.url) && CommandBarProfileScope.suggests($0, on: profile) }.map(\.url))
        }
        expect(urls.allSatisfy { store.history[$0]?.profiles == nil }, "entries from before #609 load with no profile")

        // Work's History is there but isn't a Chromium History: nothing changes.
        try? FileManager.default.createDirectory(at: root.appendingPathComponent(work.directoryName), withIntermediateDirectories: true)
        try? Data("not a database".utf8).write(to: root.appendingPathComponent(work.directoryName).appendingPathComponent("History"))
        history("Default", ["https://example.com/home-only"])
        attribute()
        expect(urls.allSatisfy { store.history[$0]?.profiles == nil }, "an unreadable History changes nothing")

        try? FileManager.default.removeItem(at: root.appendingPathComponent(work.directoryName))
        history(work.directoryName, ["https://example.com/work-only", "https://example.com/other"])
        attribute()
        expect(suggested(work.id) == ["https://example.com/work-only", "https://example.com/expired"], "Work's bar: \(suggested(work.id))")
        expect(suggested(nil) == ["https://example.com/home-only", "https://example.com/expired"], "Default's bar: \(suggested(nil))")
        expect(store.history["https://example.com/work-only"]?.visitCount == 2, "the entry keeps its visits")
    }

    /// A file that can't be read or written says so (a fault) instead of failing silently.
    private static func persistenceFaults() {
        let before = CraLog.faultCount
        try? Data("{ not json".utf8).write(to: AppPaths.file("broken.json"))
        let loaded = JSONStore<[String]>("broken.json").load(or: { ["fallback"] })
        expect(loaded == ["fallback"] && FileManager.default.fileExists(atPath: AppPaths.file("broken.json.corrupt").path),
               "a corrupt file is set aside and the fallback used")
        expect(CraLog.faultCount == before + 1, "and the log has a fault for it")
        JSONStore<[Double]>("nan.json").saveNow([.nan])
        expect(CraLog.faultCount == before + 2, "a value JSON can't hold is a fault, not a silent skip")
        JSONStore<[String]>("missing-folder/x.json").saveNow(["x"])
        expect(CraLog.faultCount == before + 3, "a write that fails is a fault")
    }

    @MainActor
    private static func mcpExcludesPrivateTabs() {
        let store = AppComposition(clock: ManualScheduler()).store
        let normal = store.createTab(url: "https://example.com/public")
        let privateWindow = store.addIncognitoWindow(frame: nil)
        let secret = store.createTab(url: "https://example.com/private", window: privateWindow.id)
        expect(store.mcpTab(normal.id)?.id == normal.id, "MCP accepts a normal tab")
        expect(store.mcpTab(secret.id) == nil, "MCP refuses private tabs even by known ID")
        expect(!store.allTabs().filter { store.mcpTab($0.id) != nil }.contains { $0.id == secret.id },
               "MCP discovery excludes private tabs")
        expect(store.mcpTab(UUID()) == nil, "MCP refuses unknown IDs")
        expect(store.spaces.values.allSatisfy { store.mcpTab($0.todayContainerID) == nil },
               "MCP refuses containers")
    }

    // promise: #620
    /// Each Chrome profile has its own incognito: an incognito window opened from a space with a profile of
    /// its own loads in that profile's off-the-record one, with its extensions and their "Allow in Incognito".
    /// Cra put every incognito window in Default's, so a profile's extensions found nothing to work on there.
    @MainActor
    private static func incognitoKeepsItsSpacesProfile() {
        let store = AppComposition(clock: ManualScheduler()).store
        let work = store.createProfile(name: "Work")
        let fromWork = store.addIncognitoWindow(frame: nil, profileID: work.id)
        let space = fromWork.focusedSpaceID!
        expect(store.isIncognito(space: space), "a window of its own, incognito")
        expect(store.profileDirectoryName(space: space) == work.directoryName, "in Work's profile, whose off-the-record one it uses")
        expect(store.profilePath(space: space) == store.profilePath(profile: work.id), "its pages load from Work's folder")
        expect(store.profileID(space: space) == work.id, "and it counts as Work's for extensions and profile choices")
        let tab = store.createTab(url: "https://example.com/private", window: fromWork.id)
        expect(store.profileDirectoryName(item: tab.id) == work.directoryName && store.isIncognito(item: tab.id), "and so do its tabs")
        let fromDefault = store.addIncognitoWindow(frame: nil)
        expect(store.profileDirectoryName(space: fromDefault.focusedSpaceID!) == "Default"
               && store.profilePath(space: fromDefault.focusedSpaceID!) == nil, "from a space on Default it is Default's, as before")
        let gone = store.addIncognitoWindow(frame: nil, profileID: UUID())
        expect(store.profileDirectoryName(space: gone.focusedSpaceID!) == "Default", "a profile that is gone falls back to Default")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #412
    /// Chrome keeps chrome://extensions, settings, history and the password manager out of
    /// incognito; Cra built the incognito page for chrome://extensions and quit (#412). From an
    /// incognito window they open in the normal window in use last, which becomes the active one;
    /// pages Chrome allows there stay.
    @MainActor
    private static func chromePagesLeaveIncognito() {
        let store = AppComposition(clock: ManualScheduler()).store
        let normal = store.activeWindowID
        let normalSpace = store.focusedSpaceID(window: normal)
        let incognito = store.addIncognitoWindow(frame: nil)
        store.activeWindowID = incognito.id
        var fronted: [UUID] = []
        store.pageLeftIncognito = { fronted.append($0) }
        let extensions = store.createTab(url: "chrome://extensions", select: true, window: incognito.id)
        expect(store.spaceID(ofItem: extensions.id) == normalSpace, "chrome://extensions from incognito opens in the normal window's space")
        expect(store.selectedTabID(window: normal) == extensions.id, "and is the tab the normal window shows")
        expect(store.selectedTabID(window: incognito.id) == nil, "the incognito window keeps none")
        expect(store.activeWindowID == normal && fronted == [normal], "and the normal window comes to the front")
        let settings = store.createTab(url: "chrome://settings/privacy", in: incognito.focusedSpaceID, select: false)
        expect(store.spaceID(ofItem: settings.id) == normalSpace, "a page asked for in the incognito space by name goes too")
        store.activeWindowID = incognito.id
        let version = store.createTab(url: "chrome://version", select: true, window: incognito.id)
        expect(store.isIncognito(item: version.id) && store.activeWindowID == incognito.id, "chrome://version stays in incognito, as in Chrome")
        let web = store.createTab(url: "https://example.com", select: true, window: incognito.id)
        expect(store.isIncognito(item: web.id), "and so does a web page")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    /// Incognito tabs never reach sidebar.json (#46's review: updateTab saved every item), and
    /// what older versions left there goes on load instead of turning into a normal tab.
    @MainActor
    private static func incognitoStaysOffDisk() {
        let store = AppComposition(clock: ManualScheduler()).store
        let normal = store.createTab(url: "https://example.com/normal")
        let window = store.addIncognitoWindow(frame: nil)
        let secret = store.createTab(url: "https://example.com/secret", in: window.focusedSpaceID, select: false)
        store.updateTab(secret.id, url: "https://example.com/secret-later", title: "Secret")
        store.setThemeColor(secret.id, "#101010")
        expect(store.item(secret.id)?.tab?.themeColor == nil, "an incognito tab keeps no toolbar colour")
        store.setThemeColor(normal.id, "#203040")
        store.updateTab(normal.id, title: "Normal")
        // Both save on a 2 s debounce on the persistence queue, not on the clock.
        Thread.sleep(forTimeInterval: 2.5)
        // JSONEncoder writes "/" as "\/".
        let saved = ((try? String(contentsOf: AppPaths.file("sidebar.json"), encoding: .utf8)) ?? "").replacingOccurrences(of: "\\/", with: "/")
        expect(saved.contains("https://example.com/normal") && saved.contains("#203040"), "a normal tab and its toolbar colour are saved")
        expect(!saved.contains("example.com/secret") && !saved.contains("Secret"), "nothing of the incognito tab is")
        let reloaded = AppComposition(clock: ManualScheduler()).store
        expect(reloaded.item(normal.id)?.tab?.themeColor == "#203040", "the toolbar colour reads back after a relaunch")

        // What 0.1.23 left behind when it crashed with an incognito window open.
        var container = SidebarItem.container(.today(spaceID: UUID()))
        let leftover = SidebarItem.tab("https://example.com/left-behind", title: "Left behind", parent: container.id)
        container.children = [leftover.id]
        store.items[container.id] = container
        store.items[leftover.id] = leftover
        store.repair()
        expect(store.item(container.id) == nil && store.item(leftover.id) == nil, "a gone space's container goes with its tabs")
        expect(!store.allTabs().contains { $0.tab?.url == "https://example.com/left-behind" }, "rather than landing in a space")
        expect(store.item(secret.id) != nil, "an open incognito window keeps its tabs")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    /// An Arc sidebar that lists an item's id twice imports as if it were listed once, the later
    /// entry winning as in a dictionary decoded from Arc's key-value array. The nightly fuzzer
    /// found the importer trapping on such a file ("Duplicate values for key") every night from
    /// 3 Nov 2026.
    @MainActor
    private static func arcItemListedTwice() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json")
        let data = try Data(contentsOf: fixture)
        var root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var sidebar = root["sidebar"] as! [String: Any]
        var containers = sidebar["containers"] as! [[String: Any]]
        let main = containers.firstIndex { $0["spaces"] != nil }!
        var items = containers[main]["items"] as! [Any]
        let id = items.firstIndex { $0 is String }!
        // A stale copy of the first item, listed before the real one: the real one must win.
        var stale = items[id + 1] as! [String: Any]
        stale["title"] = "Stale copy"
        items.insert(contentsOf: [items[id], stale], at: id)
        containers[main]["items"] = items
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let twice = try JSONSerialization.data(withJSONObject: root)
        let once = try ArcImporter.plan(sidebar: data), listedTwice = try ArcImporter.plan(sidebar: twice)
        expect(String(describing: listedTwice) == String(describing: once),
               "an item listed twice imports once, as its later entry")
    }

    // promise: #215
    /// Arc's GitHub live folder (a `list` with `automaticLiveFolderData`, Arc 1.170's shape) imports
    /// as a Cra live folder with its filter, hidden repositories and closed pull requests, so it
    /// refreshes and has the live folder's menu. It used to arrive as a plain folder holding the
    /// pull requests of import day, which never changed again (#215).
    @MainActor
    private static func arcLiveFolderImportsLive() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        var sidebar = root["sidebar"] as! [String: Any]
        var containers = sidebar["containers"] as! [[String: Any]]
        let main = containers.firstIndex { $0["spaces"] != nil }!
        var items = containers[main]["items"] as! [Any]
        func item(_ id: String, parent: String, children: [String] = [], data: [String: Any], title: String? = nil) -> [Any] {
            [id, ["id": id, "title": title as Any, "parentID": parent, "childrenIds": children, "isUnread": false,
                  "originatingDevice": "FIXTURE", "createdAt": 800000000.0, "data": data] as [String: Any]]
        }
        func pr(_ n: Int) -> String { "https://github.com/example/app/pull/\(n)" }
        let live: [String: Any] = ["list": [
            "customInfo": ["iconType": ["icon": "github"]],
            "automaticLiveFolderData": [
                "dataSource": ["github": [String: Any]()],
                "filter": ["github": ["_0": ["attributes": 3, "hiddenRepositories": [["owner": "example", "name": "old", "provider": "github"]]]]],
                "hiddenItems": [["url": ["_0": pr(9)]]],
                "lastFetch": ["timestamp": 800000000.0, "status": ["success": [String: Any]()]],
            ] as [String: Any],
        ]]
        func prTab(_ n: Int) -> [String: Any] {
            ["tab": ["savedURL": pr(n), "savedTitle": "Pull \(n)", "liveItemID": ["url": ["_0": pr(n)]]]]
        }
        items += item("work-prs", parent: "work-pinned", children: ["work-pr1", "work-pr2"], data: live, title: "Pull Requests")
        items += item("work-pr1", parent: "work-prs", data: prTab(1))
        items += item("work-pr2", parent: "work-prs", data: prTab(2))
        let pinned = items.firstIndex { ($0 as? String) == "work-pinned" }! + 1
        var container = items[pinned] as! [String: Any]
        container["childrenIds"] = ["work-prs"]
        items[pinned] = container
        containers[main]["items"] = items
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let plan = try ArcImporter.plan(sidebar: JSONSerialization.data(withJSONObject: root))

        let folder = plan.spaces[1].pinned.first
        expect(folder?.liveFolder?.filter == GitHubLiveFilter(attributes: [.authored, .reviewRequests], hiddenRepositories: ["example/old"])
               && folder?.liveFolder?.hiddenItems == [pr(9)], "Arc's live folder keeps its filter and hidden pull requests")
        expect(folder?.children.map(\.liveItemURL) == [pr(1), pr(2)], "its tabs keep the pull requests they stand for")

        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        let result = store.apply(plan, includeArchive: false, includeSettings: false)
        guard let work = result.spaceIDs.last, let imported = store.liveFolder(.github, inSpace: work) else {
            return expect(false, "the Work space has a GitHub live folder after the import")
        }
        expect(imported.title == "Pull Requests" && imported.liveFolder?.lastFetch == nil,
               "it keeps its title and is due for a refresh at once")
        expect(store.children(of: imported.id).map(\.tab?.liveItemURL) == [pr(1), pr(2)], "its tabs are the folder's live items")
        store.applyLiveResults([LivePullRequest(owner: "example", repo: "app", number: 2, title: "Pull 2, renamed"),
                                LivePullRequest(owner: "example", repo: "app", number: 3, title: "Pull 3")], to: imported.id, ssoOrganizations: [])
        let kids = store.children(of: imported.id)
        expect(kids.count == 3 && kids.filter { $0.tab?.liveItemURL == pr(2) }.count == 1,
               "the first refresh updates the imported tabs instead of adding them again")
        expect(kids.first { $0.tab?.liveItemURL == pr(1) }?.tab?.liveGoneAt == clock.now,
               "an imported pull request that left the results goes like any other")
        expect(kids.allSatisfy { !$0.isUnread }, "nothing the first refresh brings is marked unread")
        expect(store.integrityProblems().isEmpty, "the imported live folder keeps the sidebar sound")
    }

    // promise: #252
    /// An Arc space with no `customInfo.iconType` (Remove Icon in Arc's picker) is a dot in Arc's
    /// dock, and imports with no icon so Cra's dock draws the same dot. It used to come over as 🗂️.
    /// A space with an icon the importer can't read still gets 🗂️ rather than a dot (#252).
    @MainActor
    private static func arcSpaceWithoutAnIconImportsAsADot() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        var sidebar = root["sidebar"] as! [String: Any]
        var containers = sidebar["containers"] as! [[String: Any]]
        let main = containers.firstIndex { $0["spaces"] != nil }!
        var spaces = containers[main]["spaces"] as! [Any]
        let home = spaces.firstIndex { ($0 as? [String: Any])?["title"] as? String == "Home" }!
        let work = spaces.firstIndex { ($0 as? [String: Any])?["title"] as? String == "Work" }!
        var homeSpace = spaces[home] as! [String: Any], workSpace = spaces[work] as! [String: Any]
        homeSpace["customInfo"] = nil
        workSpace["customInfo"] = ["iconType": ["icon": "some-future-glyph"]]
        spaces[home] = homeSpace
        spaces[work] = workSpace
        containers[main]["spaces"] = spaces
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let plan = try ArcImporter.plan(sidebar: JSONSerialization.data(withJSONObject: root))
        expect(plan.spaces.map(\.emoji) == ["", "🗂️"], "an icon-less Arc space comes over with no icon, an unreadable one as 🗂️ (#252)")

        let store = AppComposition(clock: ManualScheduler()).store
        let ids = store.apply(plan, includeArchive: false, includeSettings: false).spaceIDs
        expect(ids.first.flatMap { store.space($0) }?.icon == SpaceIcon.none, "the imported space has no icon, a dot in the dock (#252)")
        for id in ids { store.deleteSpace(id) }
    }

    /// An Arc space with a glyph from the Icon tab of Arc's picker (`iconType.icon`, e.g. "star")
    /// imports with the SF Symbol in the same slot of Cra's Icon tab, not 🗂️, so nobody picks it
    /// again. A name Cra has no symbol for (Arc's "github") still gets 🗂️.
    @MainActor
    private static func arcSpaceIconTabGlyphImports() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        var sidebar = root["sidebar"] as! [String: Any]
        var containers = sidebar["containers"] as! [[String: Any]]
        let main = containers.firstIndex { $0["spaces"] != nil }!
        var spaces = containers[main]["spaces"] as! [Any]
        for (title, icon) in [("Home", "star"), ("Work", "github")] {
            let i = spaces.firstIndex { ($0 as? [String: Any])?["title"] as? String == title }!
            var space = spaces[i] as! [String: Any]
            space["customInfo"] = ["iconType": ["icon": icon]]
            spaces[i] = space
        }
        containers[main]["spaces"] = spaces
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let plan = try ArcImporter.plan(sidebar: JSONSerialization.data(withJSONObject: root))

        let store = AppComposition(clock: ManualScheduler()).store
        let ids = store.apply(plan, includeArchive: false, includeSettings: false).spaceIDs
        let icons = ids.map { store.space($0)?.icon }
        expect(icons == [.symbol("star.fill"), .emoji("🗂️")], "Arc's Icon-tab star imports as Cra's star, an unknown glyph as 🗂️ (\(icons))")
        for id in ids { store.deleteSpace(id) }
    }

    // promise: #749
    /// A StorableSidebar.json can hold a second, older spaces container ahead of the real one: one
    /// untitled space whose only container is an empty Today (the reporter's file, with a
    /// `littleBrowser` container first). The import takes the container that holds the spaces' items,
    /// not the first with a `spaces` key, which brought over one empty "Space" and none of the
    /// real spaces (#749).
    @MainActor
    private static func arcStubContainerBeforeTheSpaces() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Arc/StorableSidebar.json")
        var root = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as! [String: Any]
        var sidebar = root["sidebar"] as! [String: Any]
        var containers = sidebar["containers"] as! [[String: Any]]
        let stub: [String: Any] = [
            "spaces": ["STUB-SPACE", ["id": "STUB-SPACE", "profile": ["default": [:]], "customInfo": [:],
                                      "containerIDs": ["unpinned", "STUB-TODAY"],
                                      "newContainerIDs": [["unpinned": ["_0": ["shared": [:]]]], "STUB-TODAY"]] as [String: Any]],
            "items": ["STUB-TODAY", ["id": "STUB-TODAY", "title": NSNull(), "parentID": NSNull(), "childrenIds": [],
                                     "data": ["itemContainer": ["containerType": ["spaceItems": ["_0": "STUB-SPACE"]]]]] as [String: Any]],
            "topAppsContainerIDs": [],
        ]
        let main = containers.firstIndex { $0["spaces"] != nil }!
        containers.insert(stub, at: main)
        containers.insert(["littleBrowser": [:]], at: 0)
        sidebar["containers"] = containers
        root["sidebar"] = sidebar
        let plan = try ArcImporter.plan(sidebar: JSONSerialization.data(withJSONObject: root))
        let titles = plan.spaces.map(\.title)
        expect(titles == ["Home", "Work"], "the spaces come from the container holding them, not the stub ahead of it (#749: \(titles))")
        expect(plan.spaces.contains { !$0.pinned.isEmpty }, "the real spaces bring their pinned tabs (#749)")
    }

    // promise: #30
    /// Arc spaces without a `windowTheme` (both in the made-up profile) import with one fixed
    /// default, not the next preset each, which shifted every later space's colour (#30).
    @MainActor
    private static func arcSpacesWithoutAThemeShareOneDefault() throws {
        let plan = try ArcImporter.plan()
        expect(plan.spaces.count == 2 && plan.spaces.allSatisfy { $0.theme == SpaceTheme.presets[0] },
               "every themeless Arc space gets the same default theme")
    }

    // promise: #172
    /// A Little Window loads in the profile of the space it opens into and a Peek in its tab's
    /// (#172): the store answers both with that profile's Chromium folder, nil for Default, and
    /// the Little Window's profile chip names the page's profile from that folder.
    @MainActor
    private static func littleWindowProfile() {
        let store = AppComposition(clock: ManualScheduler()).store
        let home = store.createSpace(title: "Little Home", emoji: "🏠", focus: false).id
        store.setProfile(nil, forSpace: home)
        let homeTab = store.createTab(url: "https://example.com/home", in: home, select: false)
        expect(store.profilePath(space: home) == nil && store.profilePath(item: homeTab.id) == nil && store.profileID(item: homeTab.id) == nil,
               "a space on the Default profile gives its Little Windows and Peeks no profile folder (#172)")

        let work = store.createProfile(name: "Little Work")
        let space = store.createSpace(title: "Little Work", emoji: "💼", focus: false).id
        store.setProfile(work.id, forSpace: space)
        let tab = store.createTab(url: "https://example.com/work", in: space, select: false)
        let folder = store.profilePath(space: space)
        expect(folder != nil && folder == store.profilePath(profile: work.id) && store.profilePath(item: tab.id) == folder,
               "a Little Window opened into a space and a Peek from its tab load in that space's profile folder (#172)")
        expect(store.profileID(item: tab.id) == work.id && store.profileID(path: folder) == work.id,
               "the page's profile reads back from its folder, for the Little Window's profile chip (#172)")
        expect(store.profileID(path: nil) == nil && store.profilePath(profile: UUID()) == nil,
               "Default, and a profile that is gone, have no folder (#172)")
        store.deleteSpace(space)
        store.deleteSpace(home)
        store.deleteProfile(work.id)
    }

    // promise: #375
    /// Arc's per-profile "New documents" (#375): the command bar offers the app of the focused space's
    /// profile, and deleting a profile drops its choice.
    @MainActor
    private static func newDocumentApps() {
        let store = AppComposition(clock: ManualScheduler()).store
        let home = store.createSpace(title: "Docs Home", emoji: "🏠", focus: false).id
        store.setProfile(nil, forSpace: home)
        let work = store.createProfile(name: "Docs Work")
        let space = store.createSpace(title: "Docs Work", emoji: "💼", focus: false).id
        store.setProfile(work.id, forSpace: space)
        store.settings.setNewDocumentApp(.notionPage, profileID: work.id)
        store.settings.setNewDocumentApp(.googleDoc, profileID: nil)
        expect(store.profileID(space: space) == work.id && store.settings.newDocumentApp(profileID: store.profileID(space: space)) == .notionPage,
               "a space on a profile makes that profile's New documents app (#375)")
        expect(store.profileID(space: home) == nil && store.settings.newDocumentApp(profileID: store.profileID(space: home)) == .googleDoc,
               "a space on Default makes Default's (#375)")
        store.deleteSpace(space)
        store.deleteProfile(work.id)
        expect(store.settings.newDocumentApps == ["Default": .googleDoc], "deleting a profile drops its New documents app (#375)")
        store.settings.setNewDocumentApp(nil, profileID: nil)
        store.deleteSpace(home)
    }

    // promise: #170
    /// The theme editor (#170): a change shows at once but goes to disk only when the editor
    /// commits; Escape or Cancel puts the stored theme back, and a save in between keeps it off disk.
    @MainActor
    private static func themePreview() {
        let store = AppComposition(clock: ManualScheduler()).store
        let id = store.focusedSpace.id, stored = store.focusedSpace.theme
        let red = SpaceThemeVariants.theme(key: ["#F25E6B"], intensity: 0.8, noise: 0, appearance: "light")
        func savedTheme() -> SpaceTheme? {
            store.save()
            Thread.sleep(forTimeInterval: 2.5)
            let d = JSONDecoder()
            d.dateDecodingStrategy = .iso8601
            let doc = try? d.decode(SidebarDocument.self, from: Data(contentsOf: AppPaths.file("sidebar.json")))
            return doc?.spaces.first { $0.id == id }?.theme
        }
        store.previewTheme(red, forSpace: id)
        expect(store.space(id)?.theme == red, "a previewed theme shows at once")
        store.rename(store.createTab(url: "https://example.com/during").id, to: "During")
        expect(savedTheme() == stored, "a save while the editor is open writes the stored theme")
        store.endThemePreview(forSpace: id, keep: false)
        expect(store.space(id)?.theme == stored, "Escape puts the stored theme back")
        let blue = SpaceThemeVariants.theme(key: ["#6CBAD9"], intensity: 0.8, noise: 0, appearance: "light")
        store.previewTheme(red, forSpace: id)
        store.previewTheme(blue, forSpace: id)
        store.endThemePreview(forSpace: id, keep: false)
        expect(store.space(id)?.theme == stored, "several changes undo to the theme from before the editor opened")
        store.previewTheme(blue, forSpace: id)
        store.endThemePreview(forSpace: id, keep: true)
        expect(store.space(id)?.theme == blue && savedTheme() == blue, "a commit keeps the theme and writes it")
        store.previewTheme(red, forSpace: id)
        if var s = store.space(id) { s.title = "Saved"; s.theme = red; store.updateSpace(s) }
        store.endThemePreview(forSpace: id, keep: false)
        expect(store.space(id)?.theme == red && savedTheme() == red, "Save in the sheet writes the theme and ends the preview")
    }

    /// Tabs on one host keep their own icons (GitHub #211: every AWS console or localhost tab
    /// took the icon the last one loaded).
    @MainActor
    private static func tabFavicons() {
        let store = AppComposition(clock: ManualScheduler()).store
        let rds = store.createTab(url: "https://console.aws.amazon.com/rds/home", pinned: true, select: false)
        let eks = store.createTab(url: "https://console.aws.amazon.com/eks/home", pinned: true, select: false)
        let rdsIcon = FaviconKey.key(site: "console.aws.amazon.com", tabID: rds.id)
        let eksIcon = FaviconKey.key(site: "console.aws.amazon.com", tabID: eks.id)
        store.setFaviconKey(rds.id, rdsIcon)
        store.setFaviconKey(eks.id, eksIcon)
        expect(store.item(rds.id)?.tab?.iconKey == rdsIcon && store.item(eks.id)?.tab?.iconKey == eksIcon && rdsIcon != eksIcon,
               "two tabs on one host show their own icons")
        store.updateTab(rds.id, url: "https://console.aws.amazon.com/rds/home#databases", title: "Databases")
        expect(store.item(rds.id)?.tab?.faviconKey == rdsIcon, "a page on the same host keeps the tab's icon until its own loads")
        store.updateTab(rds.id, url: "https://example.org/")
        expect(store.item(rds.id)?.tab?.faviconKey == "example.org", "another host shows that site's icon")
        expect(store.item(eks.id)?.tab?.faviconKey == eksIcon, "and the other tab never changes")
    }

    // promise: #54
    /// Edit Pinned URL… (#54, PR #55 by Anoninz): a new pinned URL keeps the item's
    /// name, icon, colour and place, and survives a relaunch.
    @MainActor
    private static func pinnedURL() {
        let store = AppComposition(clock: ManualScheduler()).store
        let folder = store.createFolder(named: "Links", in: store.focusedSpace.pinnedContainerID)
        let pinned = store.createTab(url: "https://example.com/old", title: "Old page", pinned: true, select: false, parent: folder.id)
        store.rename(pinned.id, to: "My link")
        store.setCustomIcon("custom-test", for: pinned.id)
        store.setTileColor("#123456", for: [pinned.id])
        let before = store.item(pinned.id)!
        let order = store.children(of: folder.id).map(\.id)
        expect(store.setPinnedURL(pinned.id, to: "https://example.org/new?q=1#section"), "a pinned tab takes a new pinned URL")
        let after = store.item(pinned.id)!
        expect(after.tab?.savedURL == "https://example.org/new?q=1#section" && after.tab?.url == after.tab?.savedURL,
               "a tab on its pinned page goes to the new one")
        expect(after.tab?.savedTitle == "" && after.tab?.faviconKey == "example.org", "and drops the old page's title and icon")
        expect(after.title == before.title && after.parentID == before.parentID && after.tab?.customIconKey == before.tab?.customIconKey
               && after.tab?.tileColor == before.tab?.tileColor && store.children(of: folder.id).map(\.id) == order,
               "its name, icon, colour and place stay")

        store.updateTab(pinned.id, url: "https://example.org/elsewhere", title: "Elsewhere")
        expect(store.setPinnedURL(pinned.id, to: "https://example.org/newer"), "a tab navigated away takes one too")
        expect(store.item(pinned.id)?.tab?.url == "https://example.org/elsewhere" && store.item(pinned.id)?.tab?.savedTitle == "Elsewhere",
               "and keeps the page it is on")
        expect(store.resetPinnedTab(pinned.id) == "https://example.org/newer", "Back to Pinned Page goes to the new URL")
        store.updateTab(pinned.id, url: "https://example.org/current")
        store.setPinnedHomeToCurrent(pinned.id)
        expect(store.item(pinned.id)?.tab?.savedURL == "https://example.org/current", "Replace Pinned URL with Current still works")

        let favorite = store.createTab(url: "https://example.com/favorite", select: false)
        store.addToFavorites(favorite.id)
        expect(store.setPinnedURL(favorite.id, to: "https://example.org/favorite") && store.isFavorite(favorite.id),
               "a favorite takes a new pinned URL and stays a favorite")
        let today = store.createTab(url: "https://example.com/today", select: false)
        expect(!store.setPinnedURL(today.id, to: "https://example.org/") && store.item(today.id)?.tab?.url == "https://example.com/today",
               "a Today tab has no pinned URL to edit")
        expect(!store.setPinnedURL(folder.id, to: "https://example.org/") && !store.setPinnedURL(UUID(), to: "https://example.org/"),
               "nor has a folder or a missing item")
        let live = store.createTab(url: "https://github.com/example/repo/pull/1", pinned: true, select: false)
        if var t = store.item(live.id)?.tab, var it = store.item(live.id) {
            t.liveItemURL = t.url
            it.data = .tab(t)
            store.items[live.id] = it
        }
        expect(!store.setPinnedURL(live.id, to: "https://example.org/"), "nor has a live folder's entry")

        store.saveAll()
        let restored = AppComposition(clock: ManualScheduler()).store
        expect([pinned.id, favorite.id].allSatisfy { restored.item($0)?.tab?.savedURL == store.item($0)?.tab?.savedURL },
               "the pinned URLs read back after a relaunch")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #157
    /// Arc's "Drag to add Favorites" card (#157): its × closes it for that space's favorites only,
    /// for good, and readers see the change.
    @MainActor
    private static func favoritesEmptyState() {
        let store = AppComposition(clock: ManualScheduler()).store
        let home = store.focusedSpaceID
        let work = store.createSpace(title: "Work", emoji: "💼", focus: false).id
        guard let homeFavorites = store.space(home)?.favoritesContainerID,
              let workFavorites = store.space(work)?.favoritesContainerID else { return expect(false, "both spaces have favorites") }
        expect(!store.isFavoritesEmptyStateDismissed(homeFavorites), "a space starts with the card")
        final class Flag: @unchecked Sendable { var on = false }
        let changed = Flag()
        withObservationTracking { _ = store.isFavoritesEmptyStateDismissed(homeFavorites) } onChange: { changed.on = true }
        store.dismissFavoritesEmptyState(homeFavorites)
        expect(changed.on && store.isFavoritesEmptyStateDismissed(homeFavorites), "the × closes it, and the grid hears about it")
        expect(!store.isFavoritesEmptyStateDismissed(workFavorites), "another space keeps its card")
        store.saveAll()
        let restored = AppComposition(clock: ManualScheduler()).store
        expect(restored.isFavoritesEmptyStateDismissed(homeFavorites) && !restored.isFavoritesEmptyStateDismissed(workFavorites),
               "and it stays closed after a relaunch")
    }

    // promise: #617
    /// ⌘T's tabs (profileTabs) were every tab walked up to its space: most of the first keystroke at 5,000
    /// tabs. Gathered space by space now; the same tabs, in folders, groups and splits, pinned, favorites
    /// shared across spaces and another profile's, and none from a Blank Window's space.
    @MainActor
    private static func profileTabsSpaceBySpace() {
        let store = AppComposition(clock: ManualScheduler()).store
        func asBefore() -> Set<UUID> {
            Set(store.allTabs().filter { store.spaceID(ofItem: $0.id).map { !store.isStandalone(space: $0) } ?? false }.map(\.id))
        }
        func now() -> [UUID] { store.profileTabs(window: nil).map(\.id) }
        let home = store.focusedSpaceID
        let work = store.createSpace(title: "PT Work", emoji: "💼", focus: false).id
        let client = store.createProfile(name: "PT Client")
        let other = store.createSpace(title: "PT Client", emoji: "🧾", focus: false).id
        store.setProfile(client.id, forSpace: other)
        let a = store.createTab(url: "https://example.com/pt-a", in: home, select: false).id
        let b = store.createTab(url: "https://example.com/pt-b", in: home, select: false).id
        _ = store.createFolder(with: [a, b], named: "PT Folder")
        let c = store.createTab(url: "https://example.com/pt-c", in: work, select: false).id
        let d = store.createTab(url: "https://example.com/pt-d", in: work, select: false).id
        _ = store.createSplit(with: [c, d])
        let e = store.createTab(url: "https://example.com/pt-e", in: other, select: false).id
        store.addToFavorites(e, in: other)
        let f = store.createTab(url: "https://example.com/pt-f", in: home, pinned: true, select: false).id
        let g = store.createTab(url: "https://example.com/pt-g", in: home, select: false).id
        let h = store.createTab(url: "https://example.com/pt-h", in: home, select: false).id
        store.applyTidy(TidyTabs.Plan(newGroups: [.init(name: "PT Group", tabs: [0, 1])], joins: [:]), tabIDs: [g, h], in: home)
        expect(Set(now()) == asBefore() && Set([a, b, c, d, e, f, g, h]).isSubset(of: Set(now())),
               "⌘T's tabs are the same, folders, splits, groups, pinned and favorites included (#617)")
        expect(now().count == Set(now()).count, "no tab twice")
        store.setFavoritesShared(true)
        expect(Set(now()) == asBefore() && now().count == Set(now()).count, "favorites shared by spaces are listed once")
        store.setFavoritesShared(false)
    }

    // promise: #806
    /// ⌘Z after Remove Favorite (#806, asked for on X): the favorite goes back where it was in the
    /// favorites, shared or a space's own, unless something closed since comes back first.
    @MainActor
    private static func removedFavoriteComesBackOnUndo() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        let sid = store.createSpace(title: "Undo Favorites", emoji: "↩️").id
        let list = store.space(sid)!.favoritesContainerID
        func favorites() -> [UUID] { store.children(of: list).map(\.id) }
        func favorite(_ url: String) -> UUID {
            let t = store.createTab(url: url, in: sid, select: false)
            store.addToFavorites(t.id, in: sid)
            return t.id
        }
        let a = favorite("https://example.com/undo-a"), b = favorite("https://example.com/undo-b"), c = favorite("https://example.com/undo-c")
        let order = favorites()
        store.setTileColor("#FF0000", for: [b])
        store.selectTab(b)
        let w = store.window(nil).id

        store.removeFavorite(b)
        expect(store.item(b) == nil && store.archive.first?.id == b && store.selectedTabID(window: w) != b,
               "Remove Favorite on a space's own favorite archives it")
        expect(store.undoRemoveFavorite(in: w), "⌘Z undoes it")
        expect(favorites() == order && store.item(b)?.tab?.tileColor == "#FF0000" && !store.archive.contains { $0.id == b }
               && store.selectedTabID(window: w) == b && store.integrityProblems().isEmpty,
               "the favorite is back in its place, with its colour, out of the archive, shown again")
        expect(!store.undoRemoveFavorite(in: w), "once")

        // Arc's undo is a stack: a tab closed after the removal comes back first, then the favorite.
        store.removeFavorite(a)
        clock.advance(by: 1)
        let today = store.createTab(url: "https://example.com/undo-today", in: sid, select: false)
        store.archiveTab(today.id, reason: .manual)
        expect(!store.undoRemoveFavorite(in: w), "a tab closed since comes first")
        expect(store.reopenLastClosed(in: w) == .archived(today.id), "⇧⌘T's reopen takes it")
        expect(store.undoRemoveFavorite(in: w) && favorites() == order, "then ⌘Z brings the favorite back")

        // The Library brought it back first: nothing left to undo.
        store.removeFavorite(c)
        _ = store.restoreArchived(c)
        expect(!store.undoRemoveFavorite(in: w), "a favorite the Library restored isn't put back twice")
        store.removeFromArchive(c)
        store.moveItem(c, to: list, index: nil)

        // Share Favorites: Remove Favorite deletes it, and ⌘Z still brings it back.
        store.setFavoritesShared(true)
        let shared = store.space(sid)!.favoritesContainerID
        let sharedOrder = store.children(of: shared).map(\.id)
        let x = sharedOrder.first!
        store.removeFavorite(x)
        expect(store.item(x) == nil && !store.archive.contains { $0.id == x }, "a shared favorite is deleted, unarchived (Arc)")
        expect(store.undoRemoveFavorite(in: w) && store.children(of: shared).map(\.id) == sharedOrder && store.integrityProblems().isEmpty,
               "⌘Z puts a shared favorite back in its place")

        // A split favorite comes back whole.
        if let split = store.createSplit(with: [sharedOrder[1], sharedOrder[2]], inPlace: true) {
            let splitOrder = store.children(of: shared).map(\.id)
            let panes = store.children(of: split.id).map(\.id)
            store.removeFavorite(panes[0])
            expect(store.item(split.id) == nil && panes.allSatisfy { store.item($0) == nil }, "Remove Favorite on a shared split deletes it")
            expect(store.undoRemoveFavorite(in: w) && store.children(of: shared).map(\.id) == splitOrder
                   && store.children(of: split.id).map(\.id) == panes && store.integrityProblems().isEmpty,
                   "⌘Z puts the split back with its panes")
        } else {
            expect(false, "two favorites make a split")
        }
        store.setFavoritesShared(false)
        store.deleteSpace(sid)
    }

    // promise: #154
    /// Settings ▸ Tabs ▸ Share Favorites (#154): Arc's one favorites list per profile.
    @MainActor
    private static func sharedFavorites() {
        let store = AppComposition(clock: ManualScheduler()).store
        let home = store.focusedSpaceID
        // Spaces earlier tests saved would share Default's list too.
        for s in store.orderedSpaces where s.id != home { store.deleteSpace(s.id) }
        let work = store.createSpace(title: "Shared Work", emoji: "💼", focus: false).id
        let client = store.createProfile(name: "Shared Client")
        let other = store.createSpace(title: "Shared Client", emoji: "🧾", focus: false).id
        store.setProfile(client.id, forSpace: other)
        func list(_ sid: UUID) -> UUID { store.space(sid)!.favoritesContainerID }
        func favorites(_ sid: UUID) -> [UUID] { store.children(of: list(sid)).map(\.id) }
        func favorite(_ url: String, in sid: UUID) -> UUID {
            let t = store.createTab(url: url, in: sid, select: false)
            store.addToFavorites(t.id, in: sid)
            return t.id
        }
        let before = favorites(home)
        let mail = favorite("https://example.com/shared-mail", in: home)
        let music = favorite("https://example.com/shared-music", in: work)
        let mailAgain = favorite("https://example.com/shared-mail", in: work)
        let jira = favorite("https://example.com/shared-jira", in: other)
        store.selectTab(mailAgain)

        store.setFavoritesShared(true)
        expect(list(home) == list(work) && list(other) != list(home), "spaces on one profile show one list, another profile its own")
        expect(store.profileFavorites.map(\.profileID) == [nil, client.id], "one list per profile")
        expect(favorites(home) == before + [mail, music] && favorites(other) == [jira],
               "the spaces' favorites in sidebar order, a page they both had once")
        expect(store.item(mailAgain) == nil && store.focusedSpaceID == work && store.selectedTabID == mail,
               "the window that had the dropped copy open shows the kept one, in the space it was in")
        expect(store.spaceID(ofItem: mail) == work && store.isInSpace(mail, home) && store.isInSpace(mail, work) && !store.isInSpace(mail, other),
               "a shared favorite is in the window's space, and in every space of its profile")
        expect(store.integrityProblems().isEmpty, "sharing leaves the sidebar sound")

        let third = store.createSpace(title: "Shared Third", emoji: "3️⃣", focus: false).id
        expect(list(third) == list(home), "a new space shows its profile's list")
        store.moveTab(music, toSpace: home)
        expect(favorites(home) == before + [mail, music], "moving a favorite to a space that shows it changes nothing")

        store.focusSpace(third)
        store.selectTab(music)
        store.focusSpace(work)
        store.selectTab(music)
        store.archiveTab(music, reason: .manual)
        expect(store.selectedTabID(in: work) != music && store.selectedTabID(in: third) != music,
               "closing a shared favorite closes it in every space that had it open")

        let defaults = list(home)
        store.selectTab(mail)
        store.setProfile(client.id, forSpace: work)
        expect(list(work) == list(other) && favorites(work) == [jira] && favorites(home) == before + [mail],
               "a space changing profile shows its new profile's list and takes nothing along (Arc)")
        expect(store.selectedTabID(in: work) == mail && store.profileDirectoryName(item: mail) == "Default"
               && store.profileDirectoryName(item: jira) == client.directoryName && store.integrityProblems().isEmpty,
               "a favorite it had open stays open in the profile it was opened in (Arc)")
        expect(store.profileID(item: mail) == nil && store.profileID(item: jira) == client.id
               && store.profileID(path: store.profilePath(item: jira)) == client.id && store.profileID(path: nil) == nil
               && store.profilePath(profile: UUID()) == nil,
               "a page's profile reads back from its folder; Default and a missing profile have none (#172)")

        store.deleteSpace(home)
        store.setProfile(client.id, forSpace: third)
        expect(store.item(defaults) != nil && store.children(of: defaults).map(\.id) == before + [mail],
               "Default's list stays while no space uses Default (Arc)")
        expect(store.spaceIDs(ofItem: mail).isEmpty && store.spaceID(ofItem: mail) == nil, "no space shows it")
        expect(!store.profileTabs(window: nil).contains { $0.id == mail }, "and the command bar doesn't offer it")
        store.setProfile(nil, forSpace: third)
        expect(list(third) == defaults, "a space back on Default shows that list again")

        store.setFavoritesShared(false)
        expect(list(work) != list(other) && favorites(work) == [jira] && favorites(other).count == 1 && favorites(other) != [jira]
               && store.item(favorites(other)[0])?.tab?.savedURL == "https://example.com/shared-jira",
               "turning it off gives each space its own copy, the first in the sidebar keeping the favorites themselves")
        expect(favorites(third) == before + [mail] && store.profileFavorites.isEmpty, "every list was shown, so none is left")
        expect(store.integrityProblems().isEmpty, "unsharing leaves the sidebar sound")
        store.setFavoritesShared(true)
        expect(list(work) == list(other) && favorites(work) == [jira], "on again, the copies fold back into one list")
        store.setProfile(nil, forSpace: other)
        let unused = store.createProfile(name: "Shared Unused")
        store.setProfile(unused.id, forSpace: other)
        store.setProfile(client.id, forSpace: other)
        let unusedList = store.profileFavorites.first { $0.profileID == unused.id }?.containerID
        store.deleteProfile(unused.id)
        expect(unusedList.map { store.item($0) == nil } == true && !store.profileFavorites.contains { $0.profileID == unused.id },
               "deleting a profile deletes its favorites")
        let moving = favorite("https://example.com/shared-move", in: work)
        store.moveFavorite(moving, toProfile: nil)
        expect(store.profileList(ofItem: moving)?.profileID == nil && !store.isInSpace(moving, work) && store.isInSpace(moving, third),
               "Move to ▸ Profile puts a favorite on the other profile's list (Arc)")
        store.removeFromFavorites(moving)
        expect(store.item(moving) == nil && !store.archive.contains { $0.id == moving }, "Remove Favorite deletes it, unarchived (Arc)")
        store.setFavoritesShared(false)
        store.saveAll()
        let reloaded = AppComposition(clock: ManualScheduler()).store
        expect(!reloaded.settings.sharedFavorites && reloaded.space(work)!.favoritesContainerID != reloaded.space(other)!.favoritesContainerID
               && reloaded.integrityProblems().isEmpty, "the lists load as they were saved")

        // A Little Window keeps the profile of the space it opens into (#172).
        let paths = store.createProfile(name: "Shared Paths")
        let pathSpace = store.createSpace(title: "Shared Paths", emoji: "🧭", focus: false).id
        store.setProfile(paths.id, forSpace: pathSpace)
        let pathTab = store.createTab(url: "https://example.com/paths", in: pathSpace, select: false)
        expect(store.profileID(item: pathTab.id) == paths.id && store.profilePath(space: pathSpace) == store.profilePath(profile: paths.id)
               && store.profileID(path: store.profilePath(space: pathSpace)) == paths.id && store.profilePath(space: pathSpace) != nil,
               "a tab in a space reads back its space's profile and folder (#172)")
        store.deleteSpace(pathSpace)
        store.deleteProfile(paths.id)
    }

    // promise: #843
    /// Selecting a shared favorite with an explicit origin space (Picture in Picture's Back to Tab,
    /// #843) focuses that space instead of staying in the current space or falling back to the
    /// first space in sidebar order, while falling back cleanly if the space no longer holds it.
    @MainActor
    private static func selectSharedFavoriteInSpace() {
        let store = AppComposition(clock: ManualScheduler()).store
        let home = store.focusedSpaceID
        for s in store.orderedSpaces where s.id != home { store.deleteSpace(s.id) }
        store.setProfile(nil, forSpace: home)
        let entertainment = store.createSpace(title: "Entertainment", emoji: "🎬", focus: false).id
        let workProfile = store.createProfile(name: "PiP Work")
        let work = store.createSpace(title: "Work", emoji: "💼", focus: false).id
        store.setProfile(workProfile.id, forSpace: work)
        store.setFavoritesShared(true)

        let video = store.createTab(url: "https://example.com/pip-video", in: entertainment, select: false).id
        store.addToFavorites(video, in: entertainment)

        // Baseline: without an origin space, selecting a shared favorite from another profile's
        // space lands on Home (the first space in sidebar order that shares it).
        store.focusSpace(work)
        store.selectTab(video)
        expect(store.focusedSpaceID == home && store.selectedTabID == video,
               "without an origin space, a shared favorite falls back to the first space that shares it")

        // From a space on a different profile: with `in: entertainment`, it returns to Entertainment.
        store.focusSpace(work)
        store.selectTab(video, in: entertainment)
        expect(store.focusedSpaceID == entertainment && store.selectedTabID == video,
               "selecting a shared favorite with its origin space returns there from another profile's space")

        // From another space on the same profile (Home also shares the favorite): returns to Entertainment.
        store.focusSpace(home)
        store.selectTab(video, in: entertainment)
        expect(store.focusedSpaceID == entertainment && store.selectedTabID == video,
               "selecting a shared favorite with its origin space returns there even when the current space shares it")

        // If the origin space no longer lists the favorite (different profile or deleted), fall back cleanly.
        store.focusSpace(work)
        store.selectTab(video, in: work)
        expect(store.focusedSpaceID == home && store.selectedTabID == video,
               "a space that no longer shares the favorite falls back to the default space lookup")

        store.deleteSpace(entertainment)
        store.focusSpace(work)
        store.selectTab(video, in: entertainment)
        expect(store.focusedSpaceID == home && store.selectedTabID == video,
               "a deleted origin space falls back cleanly instead of focusing a missing space")

        store.removeFromFavorites(video)
        store.setFavoritesShared(false)
        store.deleteSpace(work)
        store.deleteProfile(workProfile.id)
    }

    // promise: #86
    /// Move Tab to Space N (#86) and the command bar's Move Tab to <space>, like Arc's "Move to
    /// Today in <space>": the tab goes to the top of the other space's Today, the window follows
    /// it there with the tab selected, and the space it left opens another tab.
    @MainActor
    private static func moveTabToSpace() {
        let store = AppComposition(clock: ManualScheduler()).store
        let home = store.focusedSpaceID
        let work = store.createSpace(title: "Work", emoji: "💼", focus: false).id
        _ = store.createTab(url: "https://example.com/work", in: work, select: false)
        let stay = store.createTab(url: "https://example.com/stay")
        let tab = store.createTab(url: "https://example.com/move")
        let other = store.addWindow(spaceID: home, frame: nil)
        store.selectTab(tab.id, window: other.id)
        expect(store.moveTabAndFollow(tab.id, toSpace: work), "a tab moves to another space")
        expect(store.focusedSpaceID == work && store.selectedTabID == tab.id, "the window follows it there with the tab selected")
        expect(store.children(of: store.space(work)!.todayContainerID).first?.id == tab.id, "it lands at the top of Today")
        expect(store.selectedTabID(in: home) == nil, "the window that went along leaves nothing selected in the space it left (Arc)")
        expect(store.focusedSpaceID(window: other.id) == home && store.selectedTabID(in: home, window: other.id) == stay.id,
               "another window that had it open stays in its space and opens the next tab")
        expect(!store.moveTabAndFollow(tab.id, toSpace: work) && store.focusedSpaceID == work, "moving to its own space does nothing")
        expect(!store.moveTabAndFollow(tab.id, toSpace: UUID()) && store.spaceID(ofItem: tab.id) == work, "nor does a space that isn't there")

        let pinned = store.createTab(url: "https://example.com/pinned", pinned: true)
        expect(store.moveTabAndFollow(pinned.id, toSpace: home) && store.isPinned(pinned.id) && store.spaceID(ofItem: pinned.id) == home,
               "a pinned tab stays pinned in the new space")
        expect(store.selectedTabID(in: work) != pinned.id, "and leaves no selection behind")

        let left = store.createTab(url: "https://example.com/left")
        let right = store.createTab(url: "https://example.com/right", select: false)
        let split = store.createSplit(with: [left.id, right.id])!
        store.selectTab(right.id)
        expect(store.moveTabAndFollow(right.id, toSpace: work) && store.spaceID(ofItem: split.id) == work
               && store.children(of: split.id).map(\.id) == [left.id, right.id], "a pane brings its whole split")
        expect(store.focusedSpaceID == work && store.selectedTabID == right.id, "with the same pane focused")

        store.selectTab(stay.id)
        let background = store.createTab(url: "https://example.com/background", select: false)
        store.moveTab(background.id, toSpace: work, window: nil)
        expect(store.spaceID(ofItem: background.id) == work && store.focusedSpaceID == home && store.selectedTabID == stay.id,
               "the sidebar's Move to on another tab moves it and stays")
        store.moveTab(stay.id, toSpace: work, window: nil)
        expect(store.focusedSpaceID == work && store.selectedTabID == stay.id && store.selectedTabID(in: home) != stay.id,
               "on the open tab it takes the window along, like Arc")
        store.selectTab(right.id)
        store.moveTab(split.id, toSpace: home, window: nil)
        expect(store.spaceID(ofItem: split.id) == home && store.focusedSpaceID == home && store.selectedTabID == right.id,
               "and on the open tab's split too")

        store.moveTab(split.id, toSpace: work)
        expect(store.focusedSpaceID == home && store.selectedTabID(in: home) != right.id,
               "a move that doesn't follow (a drop on a space) opens another tab in the space it left")

        // Picked tabs dropped on a space go together, each section keeping their order.
        let p1 = store.createTab(url: "https://example.com/p1", pinned: true, select: false)
        let p2 = store.createTab(url: "https://example.com/p2", pinned: true, select: false)
        let t1 = store.createTab(url: "https://example.com/t1", select: false)
        let t2 = store.createTab(url: "https://example.com/t2", select: false)
        let t3 = store.createTab(url: "https://example.com/t3")
        let picks = store.listedTabIDs(in: home).filter { [p1.id, p2.id, t1.id, t2.id, t3.id].contains($0) }
        let todayOrder = picks.filter { !store.isPinned($0) }
        store.moveTabs(picks, toSpace: work)
        expect(picks.allSatisfy { store.spaceID(ofItem: $0) == work }, "every picked tab moves to the space")
        expect(Array(store.children(of: store.space(work)!.todayContainerID).map(\.id).prefix(3)) == todayOrder,
               "Today tabs lead its Today in their order")
        expect(Array(store.children(of: store.space(work)!.pinnedContainerID).map(\.id).suffix(2)) == [p1.id, p2.id],
               "pinned tabs stay pinned, in their order")
        expect(store.focusedSpaceID == home && store.selectedTabID(in: home).map { !picks.contains($0) } ?? true,
               "the window stays, with none of the moved tabs open")

        let incognito = store.addIncognitoWindow(frame: nil)
        let secret = store.createTab(url: "https://example.com/secret", window: incognito.id)
        expect(!store.moveTabAndFollow(secret.id, toSpace: home, window: incognito.id)
               && store.isIncognito(item: secret.id) && store.focusedSpaceID(window: incognito.id) != home,
               "an incognito tab never leaves its window")
        expect(store.integrityProblems().isEmpty, "the sidebar stays sound")
    }

    // promise: #662
    @MainActor
    private static func moveFolderToSpace() {
        let store = AppComposition(clock: ManualScheduler()).store
        let a = store.createSpace(title: "Folder source", emoji: "🏠", focus: false)
        let b = store.createSpace(title: "Folder destination", emoji: "💼", focus: false)
        let first = store.createTab(url: "https://example.com/first", in: a.id, pinned: true, select: false)
        let folder = store.createFolder(named: "F", in: a.pinnedContainerID)
        let last = store.createTab(url: "https://example.com/last", in: a.id, pinned: true, select: false)
        let t1 = store.createTab(url: "https://example.com/t1", pinned: true, select: false, parent: folder.id)
        let nested = store.createFolder(named: "N", in: folder.id)
        let t2 = store.createTab(url: "https://example.com/t2", pinned: true, select: false, parent: nested.id)
        let t3 = store.createTab(url: "https://example.com/t3", pinned: true, select: false, parent: folder.id)
        let existing = store.createTab(url: "https://example.com/existing", in: b.id, pinned: true, select: false)
        store.setExpanded(folder.id, true)
        store.setExpanded(nested.id, false)
        let window = store.addWindow(spaceID: a.id, frame: nil)
        store.selectTab(t2.id, window: window.id)
        store.setExpanded(nested.id, false)
        let count = store.orderedSpaces.reduce(0) { $0 + store.tabs(under: $1.pinnedContainerID).count + store.tabs(under: $1.todayContainerID).count + store.tabs(under: $1.favoritesContainerID).count }
        store.moveTab(folder.id, toSpace: b.id, window: nil)
        expect(store.children(of: b.pinnedContainerID).map(\.id) == [existing.id, folder.id], "folder appends to target pinned")
        expect(store.children(of: a.pinnedContainerID).map(\.id) == [first.id, last.id], "folder leaves source pinned")
        expect(store.children(of: folder.id).map(\.id) == [t1.id, nested.id, t3.id] && store.children(of: nested.id).map(\.id) == [t2.id], "folder subtree keeps ids and order")
        expect([folder.id, nested.id, t1.id, t2.id, t3.id].allSatisfy { store.spaceID(ofItem: $0) == b.id }, "whole subtree belongs to target")
        let after = store.orderedSpaces.reduce(0) { $0 + store.tabs(under: $1.pinnedContainerID).count + store.tabs(under: $1.todayContainerID).count + store.tabs(under: $1.favoritesContainerID).count }
        expect(count == after && store.integrityProblems().isEmpty, "moving preserves tabs and sidebar integrity")
        expect(store.isExpanded(folder.id) && !store.isExpanded(nested.id), "folder expansion states survive")
        expect(store.selectedTabID(in: a.id, window: window.id).map { ![t1.id, t2.id, t3.id].contains($0) } ?? true, "source selection does not follow moved tab")
        store.moveTab(folder.id, toSpace: b.id, window: nil)
        expect(store.children(of: b.pinnedContainerID).map(\.id) == [existing.id, folder.id] && store.children(of: folder.id).map(\.id) == [t1.id, nested.id, t3.id], "moving to own space does nothing")
    }

    // promise: #105
    /// The tab shown after ⌘W (Arc 1.171, GitHub #105): the one shown before while its page is
    /// loaded, else the Today neighbour above (below at the top), else nothing; it reads as read.
    @MainActor
    private static func closeSuccessor() {
        let store = AppComposition(clock: ManualScheduler()).store
        var loaded: Set<UUID> = []
        store.hasPage = { loaded.contains($0) }
        // Earlier tests left tabs in the data folder.
        for tab in store.tabs(under: store.focusedSpace.todayContainerID) { store.archiveTab(tab.id, reason: .manual) }
        let source = store.createTab(url: "https://example.com/list", pinned: true)
        // Opened in the background from the pinned list: Today is c, b, a.
        let a = store.createTab(url: "https://example.com/a", select: false)
        let b = store.createTab(url: "https://example.com/b", select: false)
        let c = store.createTab(url: "https://example.com/c", select: false)
        loaded = [source.id, a.id, b.id, c.id]
        store.selectTab(a.id)
        store.archiveTab(a.id, reason: .manual)
        expect(store.selectedTabID == source.id, "closing a post picked from the list goes back to the list")

        store.selectTab(c.id)
        store.selectTab(b.id)
        store.archiveTab(b.id, reason: .manual)
        expect(store.selectedTabID == c.id, "back to the tab shown before, not to the tab it was opened from")

        loaded.remove(source.id)
        let d = store.createTab(url: "https://example.com/d", select: false)
        store.selectTab(source.id)
        store.selectTab(c.id)
        expect(store.item(d.id)?.isUnread == true, "a tab opened in the background is unread")
        store.archiveTab(c.id, reason: .manual)
        expect(store.selectedTabID == d.id, "a closed pinned tab isn't reloaded: the neighbour above instead")
        expect(store.item(d.id)?.isUnread == false, "the tab a close hands over to is read")

        let e = store.createTab(url: "https://example.com/e", select: false)
        store.archiveTab(d.id, reason: .manual)
        expect(store.selectedTabID == e.id, "the tab shown before has closed: the neighbour above")
        store.archiveTab(e.id, reason: .manual)
        expect(store.selectedTabID == nil, "the last tab hands over to nothing, not to a pinned tab")

        let p2 = store.createTab(url: "https://example.com/p2", pinned: true)
        loaded = [source.id, p2.id]
        store.selectTab(source.id)
        store.selectTab(p2.id)
        expect(store.closeSuccessor(ofPinned: p2.id, window: store.activeWindowID) == source.id,
               "a closed pinned tab goes back to the tab shown before")
        loaded.remove(p2.id)
        store.selectTab(source.id)
        loaded.remove(source.id)
        expect(store.closeSuccessor(ofPinned: source.id, window: store.activeWindowID) == nil,
               "and to nothing when that one was closed too")

        // A Today folder above: its tabs are the neighbour only while it's open (Arc).
        let today = store.focusedSpace.todayContainerID
        let folder = store.createFolder(named: "Folder", in: today, index: 0)
        let x = store.createTab(url: "https://example.com/x", select: false, parent: folder.id)
        let y = store.createTab(url: "https://example.com/y", select: false, parent: folder.id, index: 1)
        let f = store.createTab(url: "https://example.com/f", select: false, index: 1)
        loaded = []
        store.setExpanded(folder.id, false)
        store.selectTab(f.id)
        expect(store.shownTabs(under: today) == [f.id], "a closed folder shows none of its tabs")
        store.archiveTab(f.id, reason: .manual)
        expect(store.selectedTabID == nil, "so a close doesn't open a tab hidden in it")
        let g = store.createTab(url: "https://example.com/g", select: false, index: 1)
        store.setExpanded(folder.id, true)
        store.selectTab(g.id)
        expect(store.shownTabs(under: today) == [x.id, y.id, g.id], "an open folder shows its tabs")
        store.archiveTab(g.id, reason: .manual)
        expect(store.selectedTabID == y.id, "and the row above it, inside the folder, takes over")

        // Two windows on one space: each goes back to the tab it showed before.
        store.setExpanded(folder.id, false)
        let main = store.activeWindowID
        let second = store.addWindow(spaceID: store.focusedSpaceID, frame: nil).id
        let h = store.createTab(url: "https://example.com/h", select: false)
        let i = store.createTab(url: "https://example.com/i", select: false)
        let j = store.createTab(url: "https://example.com/j", select: false)
        let k = store.createTab(url: "https://example.com/k", select: false)
        loaded = [h.id, i.id, j.id, k.id]
        store.selectTab(h.id, window: main)
        store.selectTab(i.id, window: main)
        store.selectTab(j.id, window: second)
        store.selectTab(k.id, window: second)
        store.archiveTab(k.id, reason: .manual)
        expect(store.selectedTabID(in: store.focusedSpaceID, window: second) == j.id
               && store.selectedTabID(in: store.focusedSpaceID, window: main) == i.id, "the second window goes back to its own previous tab")
        store.archiveTab(i.id, reason: .manual)
        expect(store.selectedTabID(in: store.focusedSpaceID, window: main) == h.id, "and the first to its own")

        // Moving the open tab to another space without following it: the space it left
        // hands over as on a close, and the tab shown there is read.
        let work = store.createSpace(title: "Work", emoji: "💼", focus: false).id
        let m = store.createTab(url: "https://example.com/m", select: false, window: main)
        let n = store.createTab(url: "https://example.com/n", select: false, window: main)
        loaded.insert(m.id)
        store.selectTab(m.id, window: main)
        store.selectTab(n.id, window: main)
        store.markUnread(m.id)
        store.moveTab(n.id, toSpace: work)
        expect(store.selectedTabID(in: store.focusedSpaceID(window: main), window: main) == m.id, "moving it away goes back to the tab shown before")
        expect(store.item(m.id)?.isUnread == false, "which is read")

        // A space switch counts as showing another tab (Arc): after going away and back, the
        // tab shown before is in the other space, so a close takes the neighbour instead.
        let space1 = store.focusedSpaceID(window: main)
        let w1 = store.createTab(url: "https://example.com/w1", select: false, window: main)
        let x1 = store.createTab(url: "https://example.com/x1", select: false, window: main)
        let y1 = store.createTab(url: "https://example.com/y1", select: false, window: main)
        let other = store.createTab(url: "https://example.com/other", in: work, select: false)
        loaded = [w1.id, x1.id, y1.id, other.id]
        store.selectTab(other.id, window: main)
        store.selectTab(w1.id, window: main)
        store.selectTab(x1.id, window: main)
        store.focusSpace(work, window: main)
        store.focusSpace(space1, window: main)
        expect(store.shownTabs(under: store.space(space1)!.todayContainerID).prefix(3) == [y1.id, x1.id, w1.id], "new tabs go to the top of Today")
        store.archiveTab(x1.id, reason: .manual)
        expect(store.selectedTabID(in: space1, window: main) == y1.id,
               "a round trip through another space: the neighbour above, not the tab picked before")

        // Closing a pane keeps the tab shown before the split.
        let before = store.createTab(url: "https://example.com/before", select: false, window: main)
        let l = store.createTab(url: "https://example.com/l", select: false, window: main)
        let r = store.createTab(url: "https://example.com/r", select: false, window: main)
        _ = store.createSplit(with: [l.id, r.id])
        loaded = [before.id, l.id, r.id]
        store.selectTab(before.id, window: main)
        store.selectTab(l.id, window: main)
        store.archiveTab(l.id, reason: .manual)
        expect(store.selectedTabID(in: space1, window: main) == r.id, "the other pane stays")
        store.archiveTab(r.id, reason: .manual)
        expect(store.selectedTabID(in: space1, window: main) == before.id, "then the split goes back to the tab shown before it")

        // A pinned split closing hands over to nothing, even with the tab shown before loaded.
        let pl = store.createTab(url: "https://example.com/pl", select: false, window: main)
        let pr = store.createTab(url: "https://example.com/pr", select: false, window: main)
        _ = store.createSplit(with: [pl.id, pr.id])
        store.togglePinned(pl.id)
        expect(store.isPinned(pl.id) && store.splitContaining(pl.id) != nil, "a pinned split")
        loaded = [before.id, pl.id, pr.id]
        store.selectTab(before.id, window: main)
        store.selectTab(pl.id, window: main)
        expect(store.closeSuccessor(ofPinned: pl.id, window: main) == nil, "a pinned split hands over to nothing (Arc)")
    }

    @MainActor
    private static func folderSymbols() {
        let store = AppComposition(clock: ManualScheduler()).store
        let folder = store.createFolder(named: "Symbols", in: store.focusedSpace.pinnedContainerID)
        let nested = store.createFolder(named: "Nested", in: folder.id)
        let tab = store.createTab(url: "https://example.com", pinned: true, select: false, parent: folder.id)
        store.setFolderIcon(.white, for: folder.id)
        store.setFolderSymbol(.code, for: folder.id)
        store.setFolderSymbol(.star, for: nested.id)
        expect(store.item(folder.id)?.folderSymbol == .code && store.item(nested.id)?.folderSymbol == .star,
               "each folder keeps its own symbol")
        store.setFolderSymbol(.heart, for: tab.id)
        store.setFolderSymbol(.heart, for: store.focusedSpace.pinnedContainerID)
        store.setFolderSymbol(.heart, for: UUID())
        expect(store.item(tab.id)?.folderSymbol == nil && store.item(store.focusedSpace.pinnedContainerID)?.folderSymbol == nil,
               "symbols are only set on folders")
        store.saveAll()
        let reloaded = AppComposition(clock: ManualScheduler()).store
        expect(reloaded.item(folder.id)?.folderSymbol == .code && reloaded.item(nested.id)?.folderSymbol == .star,
               "folder symbols survive a store reload")
        reloaded.setFolderSymbol(nil, for: folder.id)
        expect(reloaded.item(folder.id)?.folderSymbol == nil && reloaded.item(folder.id)?.folderIcon == .white,
               "removing a symbol keeps the folder color")
        reloaded.setFolderIcon(.black, for: nested.id)
        expect(reloaded.item(nested.id)?.folderIcon == .black && reloaded.item(nested.id)?.folderSymbol == .star,
               "changing the folder color keeps its symbol")
        reloaded.setFolderIcon(nil, for: folder.id)
        expect(reloaded.item(folder.id)?.folderIcon == nil && reloaded.item(folder.id)?.folderSymbol == nil,
               "removing both choices restores the default folder")
        expect(reloaded.item(folder.id)?.children == [nested.id, tab.id], "changing the icon preserves folder contents")
        reloaded.saveAll()
    }

    // promise: #85
    /// A closed folder keeps its open tab in sight (Arc, GitHub #85): picking a tab two closed
    /// folders down lists it under the outer one without opening either.
    @MainActor
    private static func folderPeek() {
        let store = AppComposition(clock: ManualScheduler()).store
        let outer = store.createFolder(named: "Outer", in: store.focusedSpace.pinnedContainerID)
        let inner = store.createFolder(named: "Inner", in: outer.id)
        let tab = store.createTab(url: "https://example.org/", pinned: true, select: false, parent: inner.id)
        let sibling = store.createTab(url: "https://example.org/sibling", pinned: true, select: false, parent: inner.id)
        let elsewhere = store.createTab(url: "https://example.net/", select: true)
        store.setExpanded(outer.id, false)
        store.setExpanded(inner.id, false)
        expect(store.peekedTabs(in: outer.id).isEmpty, "a closed folder shows nothing to begin with")

        store.selectTab(tab.id)
        expect(!store.isExpanded(outer.id) && !store.isExpanded(inner.id), "picking the tab leaves both folders closed")
        expect(store.peekedTabs(in: outer.id).map(\.id) == [tab.id] && store.peekedTabs(in: inner.id).isEmpty,
               "and lists it under the outer one")
        store.selectTab(elsewhere.id)
        expect(store.peekedTabs(in: outer.id).map(\.id) == [tab.id], "it stays there when another tab is picked")

        store.setExpanded(outer.id, true)
        expect(store.peekedTabs(in: outer.id).isEmpty && store.prefs.peekedFolders[outer.id] == nil, "opening the folder drops the peek")
        store.selectTab(tab.id)
        expect(store.peekedTabs(in: inner.id).map(\.id) == [tab.id], "with the outer one open, the inner one hosts it")
        store.setExpanded(outer.id, false)
        expect(store.peekedTabs(in: outer.id).map(\.id) == [tab.id], "closing a folder keeps the open tab in sight")
        store.selectTab(sibling.id)
        expect(store.peekedTabs(in: outer.id).map(\.id) == [tab.id, sibling.id], "a second tab joins, in sidebar order")

        store.saveAll()
        let restored = AppComposition(clock: ManualScheduler()).store
        expect(restored.peekedTabs(in: outer.id).map(\.id) == [tab.id, sibling.id], "the peek reads back after a relaunch")

        _ = store.resetPinnedTab(sibling.id)
        expect(store.peekedTabs(in: outer.id).map(\.id) == [tab.id], "closing a tab (⌘W) takes it out")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #557
    /// The steps of #557: a tab open inside an open folder, the folder closed, another tab picked. The
    /// tab stays listed under the closed folder, as in Arc; opening the folder or ⌘W takes it out.
    @MainActor
    private static func folderPeekAfterClosing() {
        let store = AppComposition(clock: ManualScheduler()).store
        let folder = store.createFolder(named: "tools", in: store.focusedSpace.pinnedContainerID)
        let pdf = store.createTab(url: "https://example.org/pdf", pinned: true, select: false, parent: folder.id)
        let cobalt = store.createTab(url: "https://example.org/cobalt", pinned: true, select: false, parent: folder.id)
        let elsewhere = store.createTab(url: "https://example.net/", select: false)
        store.setExpanded(folder.id, true)
        store.selectTab(pdf.id)
        expect(store.peekedTabs(in: folder.id).isEmpty, "an open folder keeps nothing to peek")

        store.setExpanded(folder.id, false)
        expect(store.peekedTabs(in: folder.id).map(\.id) == [pdf.id], "closing it keeps only the open tab in sight")
        store.selectTab(elsewhere.id)
        expect(store.peekedTabs(in: folder.id).map(\.id) == [pdf.id], "picking a tab outside it keeps the tab there (Arc)")
        expect(!store.isExpanded(folder.id) && !store.peekedTabs(in: folder.id).contains { $0.id == cobalt.id },
               "the folder stays closed and its other tabs stay hidden")

        store.setExpanded(folder.id, true)
        store.setExpanded(folder.id, false)
        expect(store.peekedTabs(in: folder.id).isEmpty, "opening and closing it while another tab is open drops the peek")
        store.selectTab(pdf.id)
        store.selectTab(elsewhere.id)
        _ = store.resetPinnedTab(pdf.id)
        expect(store.peekedTabs(in: folder.id).isEmpty, "closing the tab (⌘W) takes it out")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    /// A collapsed pinned section keeps the pinned tab you were last on in sight once you pick a
    /// favorite or a Today tab (Arc's peekedPinnedSidebarItemID; X DM 6 Nov 2026: Reddit vanished
    /// from under the space name as soon as YouTube was picked).
    @MainActor
    private static func collapsedPinnedPeek() {
        let store = AppComposition(clock: ManualScheduler()).store
        let space = store.focusedSpace
        let favorite = store.createTab(url: "https://youtube.com/", pinned: true, select: false, parent: space.favoritesContainerID)
        let reddit = store.createTab(url: "https://reddit.com/", pinned: true, select: false, parent: space.pinnedContainerID)
        let mail = store.createTab(url: "https://mail.example/", pinned: true, select: false, parent: space.pinnedContainerID)
        let today = store.createTab(url: "https://example.net/", select: true)
        store.togglePinnedCollapsed(space.id)
        let listed = { store.listedPinnedItems(in: store.focusedSpace).map(\.id) }
        expect(listed().isEmpty, "a collapsed section on a Today tab lists nothing")

        store.selectTab(reddit.id)
        expect(listed() == [reddit.id], "picking a pinned tab lists it")
        store.selectTab(favorite.id)
        expect(listed() == [reddit.id], "it stays in sight when a favorite is picked")
        store.selectTab(today.id)
        expect(listed() == [reddit.id], "and when a Today tab is picked")
        store.selectTab(mail.id)
        store.selectTab(favorite.id)
        expect(listed() == [mail.id], "only the last pinned tab stays, not every one you were on")

        let other = store.addWindow(spaceID: space.id, frame: nil)
        expect(store.listedPinnedItems(in: store.focusedSpace, window: other.id).isEmpty, "another window keeps its own")

        store.togglePinnedCollapsed(space.id)
        store.togglePinnedCollapsed(space.id)
        expect(listed().isEmpty, "collapsing again keeps only the open tab's row, as a closed folder does")
        store.selectTab(reddit.id)
        store.selectTab(today.id)
        _ = store.resetPinnedTab(reddit.id)
        expect(listed().isEmpty, "closing it (⌘W) takes it out")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    /// Tidy Tabs (Arc's tab groups in Today): the model's plan applied, undone, and the header's
    /// actions, on the production store.
    @MainActor
    private static func tidyTabs() {
        let store = AppComposition(clock: ManualScheduler()).store
        // A space of its own: earlier checks leave tabs in the first one.
        let sid = store.createSpace(title: "Tidy", emoji: "🧹").id
        let today = store.focusedSpace.todayContainerID
        let names = ["Mars", "Baguette", "Saturn", "Croissant", "Python", "Mail"]
        let tabs = names.map { store.createTab(url: "https://example.org/\($0)", in: sid, select: false) }
        let byName = Dictionary(uniqueKeysWithValues: zip(names, tabs.map(\.id)))
        expect(store.tabGroups(in: sid).isEmpty && store.canTidy(sid), "six loose Today tabs offer Tidy")
        let before = store.item(today)!.children
        // The model sees the loose tabs in sidebar order (new tabs at the top: Mail first).
        let loose = store.looseTodayTabs(sid).map(\.id)
        func at(_ name: String) -> Int { loose.firstIndex(of: byName[name]!)! }
        let plan = TidyTabs.plan([.init(name: "Planets", tabs: [at("Mars"), at("Saturn")]),
                                  .init(name: "Bread", tabs: [at("Baguette"), at("Croissant")])],
                                 tabCount: loose.count, existingGroups: [])
        store.applyTidy(plan, tabIDs: loose, in: sid)
        var groups = store.tabGroups(in: sid)
        expect(groups.map(\.title) == ["Bread", "Planets"], "groups follow their first tab's place")
        expect(store.item(today)!.children == [byName["Mail"]!, byName["Python"]!] + groups.map(\.id),
               "tabs left loose stay above the groups")
        expect(groups[1].children == [byName["Saturn"]!, byName["Mars"]!], "a group keeps its tabs in sidebar order")
        expect(groups.allSatisfy { store.isExpanded($0.id) } && store.tabs(under: today).count == 6, "groups are always open")
        expect(!store.canTidy(sid), "after a run Tidy waits for a new tab")
        expect(store.integrityProblems().isEmpty, "the tidied sidebar is sound")

        expect(store.undoTidy() && store.tabGroups(in: sid).isEmpty && store.item(today)!.children == before,
               "⌘Z puts every tab back and the groups go")
        expect(!store.undoTidy() && store.canTidy(sid), "once; then Tidy is offered again")

        store.applyTidy(plan, tabIDs: loose, in: sid)
        let fresh = store.createTab(url: "https://example.org/Jupiter", in: sid, select: false)
        expect(store.canTidy(sid), "a new loose tab brings Tidy back")
        let loose2 = store.looseTodayTabs(sid).map(\.id)
        let existing = store.tabGroups(in: sid).map { TidyTabs.ExistingGroup(id: $0.id, name: $0.title ?? "") }
        let join = TidyTabs.plan([.init(name: "planets", tabs: [loose2.firstIndex(of: fresh.id)!])], tabCount: loose2.count, existingGroups: existing)
        store.applyTidy(join, tabIDs: loose2, in: sid)
        groups = store.tabGroups(in: sid)
        expect(groups[1].children.last == fresh.id, "a second run adds a tab to the group the model named")

        // Moves: groups stay at the top of Today and hold tabs.
        let pinned = store.focusedSpace.pinnedContainerID
        store.moveItem(groups[0].id, to: pinned, index: 0)
        expect(store.item(groups[0].id)?.parentID == today, "a group doesn't move into the pinned tabs")
        let folder = store.createFolder(named: "F", in: pinned)
        store.moveItem(folder.id, to: groups[0].id, index: 0)
        expect(store.item(folder.id)?.parentID == pinned, "a folder doesn't go into a group")
        store.moveItem(byName["Mail"]!, to: groups[0].id, index: 0)
        expect(store.item(groups[0].id)!.children.first == byName["Mail"], "a tab dropped on a group joins it")
        store.moveItem(byName["Mail"]!, to: today, index: 0)

        // The header's actions; after one, ⌘Z no longer undoes the tidy.
        store.removeGroupHeader(groups[0].id)
        expect(!store.undoTidy(), "a header action since the tidy takes ⌘Z's undo off")

        expect(store.item(groups[0].id) == nil && store.item(today)!.children.prefix(4) == [byName["Mail"]!, byName["Python"]!, byName["Croissant"]!, byName["Baguette"]!],
               "Remove header leaves the tabs loose where the group was")
        let made = store.folderFromGroup(groups[1].id)
        expect(made?.title == "Planets" && store.item(pinned)!.children.first == made?.id && made?.children.count == 3
               && store.item(groups[1].id) == nil && store.isExpanded(made!.id) && store.isPinned(byName["Mars"]!),
               "Create Folder makes an open folder at the top of Pinned with the group's tabs, now pinned")

        store.applyTidy(TidyTabs.plan([.init(name: "Bread", tabs: [0, 1])], tabCount: 2, existingGroups: []),
                        tabIDs: [byName["Baguette"]!, byName["Croissant"]!], in: sid)
        let bread = store.tabGroups(in: sid)[0]
        store.archiveTab(byName["Baguette"]!, reason: .manual)
        expect(store.item(bread.id)?.children == [byName["Croissant"]!], "closing one tab keeps the group")
        expect(!store.undoTidy(), "a close since the tidy owns ⌘Z")
        store.saveAll()
        let restored = AppComposition(clock: ManualScheduler()).store
        expect(restored.item(bread.id)?.isTabGroup == true && restored.item(bread.id)?.title == "Bread", "a group reads back after a relaunch")
        store.archiveTab(byName["Croissant"]!, reason: .manual)
        expect(store.item(bread.id) == nil && !store.item(today)!.children.contains(bread.id), "its last tab takes the header with it")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    /// A model result retains the original destination while headers and tab membership change.
    @MainActor
    private static func tidyExistingGroupIdentity() {
        let store = AppComposition(clock: ManualScheduler()).store
        for change in ["remove earlier header", "reorder headers", "rename destination", "remove destination",
                       "replace destination", "close destination", "pin destination"] {
            let space = store.createSpace(title: "Pending tidy", emoji: "🧹")
            for i in 0..<6 { store.createTab(url: "https://example.org/identity/\(i)", in: space.id, select: false) }
            let tabs = store.looseTodayTabs(space.id).map(\.id)
            let initial = TidyTabs.plan([.init(name: "A", tabs: [0, 1]), .init(name: "B", tabs: [2, 3]),
                                         .init(name: "C", tabs: [4, 5])], tabCount: tabs.count, existingGroups: [])
            store.applyTidy(initial, tabIDs: tabs, in: space.id)
            let groups = store.tabGroups(in: space.id)
            let destination = groups[1].id
            let fresh = store.createTab(url: "https://example.org/identity/fresh", in: space.id, select: false).id
            let pending = TidyTabs.plan([.init(name: "B", tabs: [0])], tabCount: 1,
                                        existingGroups: groups.map { TidyTabs.ExistingGroup(id: $0.id, name: $0.title ?? "") })
            switch change {
            case "remove earlier header": store.removeGroupHeader(groups[0].id)
            case "reorder headers": store.moveItem(destination, to: space.todayContainerID, index: 0)
            case "rename destination": store.rename(destination, to: "Renamed B")
            case "remove destination": store.removeGroupHeader(destination)
            case "replace destination":
                store.removeGroupHeader(destination)
                let replacement = TidyTabs.plan([.init(name: "B", tabs: [0, 1])], tabCount: 2, existingGroups: [])
                store.applyTidy(replacement, tabIDs: groups[1].children, in: space.id)
            case "close destination": store.deleteFolder(destination)
            case "pin destination": store.folderFromGroup(destination)
            default: fatalError("unknown destination change")
            }
            let destinationSurvives = ["remove earlier header", "reorder headers", "rename destination"].contains(change)
            let before = store.item(space.todayContainerID)!.children
            store.applyTidy(pending, tabIDs: [fresh], in: space.id)
            expect(store.item(fresh)?.parentID == (destinationSurvives ? destination : space.todayContainerID),
                   "pending tidy uses original group identity after \(change)")
            expect(!store.item(groups[2].id)!.children.contains(fresh), "pending tidy never retargets neighboring C after \(change)")
            if destinationSurvives {
                expect(store.undoTidy() && store.item(fresh)?.parentID == space.todayContainerID
                       && store.item(space.todayContainerID)?.children == before && store.item(destination) != nil,
                       "undo restores loose order and retains original destination after \(change)")
            } else {
                expect(!store.undoTidy(), "skipping a removed destination creates no tidy undo after \(change)")
            }
            expect(store.integrityProblems().isEmpty, "pending tidy preserves sidebar integrity after \(change)")
        }

        let space = store.createSpace(title: "Changed members", emoji: "🧹")
        for i in 0..<4 { store.createTab(url: "https://example.org/members/grouped/\(i)", in: space.id, select: false) }
        let grouped = store.looseTodayTabs(space.id).map(\.id)
        store.applyTidy(TidyTabs.plan([.init(name: "Destination", tabs: [0, 1]), .init(name: "Other", tabs: [2, 3])],
                                     tabCount: grouped.count, existingGroups: []), tabIDs: grouped, in: space.id)
        let groups = store.tabGroups(in: space.id)
        let members = (0..<5).map { store.createTab(url: "https://example.org/members/pending/\($0)", in: space.id, select: false).id }
        let pending = TidyTabs.plan([.init(name: "Destination", tabs: Array(members.indices))], tabCount: members.count,
                                    existingGroups: groups.map { TidyTabs.ExistingGroup(id: $0.id, name: $0.title ?? "") })
        store.archiveTab(members[0], reason: .manual)
        store.moveItem(members[1], to: space.pinnedContainerID, index: nil)
        store.moveItem(members[2], to: groups[1].id, index: nil)
        let elsewhere = store.createSpace(title: "Elsewhere", emoji: "🌍")
        store.moveItem(members[3], to: elsewhere.todayContainerID, index: nil)
        store.applyTidy(pending, tabIDs: members, in: space.id)
        expect(store.item(groups[0].id)?.children == grouped.prefix(2) + [members[4]],
               "pending tidy joins only original members still loose in the source Today")
        expect(store.item(members[0]) == nil && store.item(members[1])?.parentID == space.pinnedContainerID
               && store.item(members[2])?.parentID == groups[1].id && store.item(members[3])?.parentID == elsewhere.todayContainerID,
               "pending tidy does not revive closed tabs or steal pinned, grouped or moved tabs")
        expect(store.undoTidy() && store.item(members[4])?.parentID == space.todayContainerID
               && store.item(groups[0].id)?.children == Array(grouped.prefix(2)), "undo moves back only the surviving joined member")
        expect(store.integrityProblems().isEmpty, "changed-member completion and undo preserve integrity")
    }

    /// Only successfully considered request IDs are consumed, including when requests fit a prefix.
    @MainActor
    private static func tidyConsideredSnapshots() {
        let store = AppComposition(clock: ManualScheduler()).store
        for groupsTabs in [false, true] {
            let space = store.createSpace(title: "Tidy snapshot", emoji: "🧹")
            for i in 0..<6 { store.createTab(url: "https://example.org/snapshot/\(i)", in: space.id, select: false) }
            let captured = store.looseTodayTabs(space.id).map(\.id)
            let plan = TidyTabs.plan(groupsTabs ? [.init(name: "Captured", tabs: [0, 1])] : [],
                                     tabCount: captured.count, existingGroups: [])
            let arrival = store.createTab(url: "https://example.org/snapshot/new", in: space.id, select: false)
            store.applyTidy(plan, tabIDs: captured, in: space.id)
            expect(store.canTidy(space.id) && store.item(arrival.id)?.parentID == space.todayContainerID,
                   "a \(groupsTabs ? "grouping" : "successful empty") request leaves an unseen arrival eligible")
            expect(store.tidiedTabs[space.id] == Set(captured), "successful tidy consumes only its captured snapshot")
            if groupsTabs {
                expect(store.undoTidy() && store.tidiedTabs[space.id] == nil && store.canTidy(space.id),
                       "undo clears considered state after a snapshot-only grouping")
            } else {
                store.applyTidy(TidyTabs.plan([], tabCount: 1, existingGroups: []), tabIDs: [arrival.id], in: space.id)
                expect(!store.canTidy(space.id) && store.tidiedTabs[space.id] == Set(captured + [arrival.id]),
                       "successfully considering the arrival retains earlier considered IDs and ends offered state")
            }
            expect(store.integrityProblems().isEmpty, "snapshot-only completion and undo preserve integrity")
        }

        let mixed = store.createSpace(title: "Prompt priority", emoji: "🧹")
        for i in 0..<6 { store.createTab(url: "https://example.org/priority/\(i)", in: mixed.id, select: false) }
        let old = store.looseTodayTabs(mixed.id).map(\.id)
        store.applyTidy(TidyTabs.plan([], tabCount: old.count, existingGroups: []), tabIDs: old, in: mixed.id)
        let fresh = (0..<2).map { store.createTab(url: "https://example.org/priority/new/\($0)", in: mixed.id, select: false).id }
        store.moveItem(old[0], to: mixed.todayContainerID, index: 0)
        let before = store.item(mixed.todayContainerID)!.children
        let request = store.tidyCandidates(mixed.id).map(\.id)
        expect(request == fresh.reversed() + old, "request priority retains unseen-first mapping even when an old tab leads Today")
        func at(_ id: UUID) -> Int { request.firstIndex(of: id)! }
        let plan = TidyTabs.plan([.init(name: "Second", tabs: [at(fresh[1]), at(old[1])]),
                                  .init(name: "First", tabs: [at(fresh[0]), at(old[0])])],
                                 tabCount: request.count, existingGroups: [])
        expect(plan.newGroups.map(\.name) == ["Second", "First"], "model plan remains in captured request order")
        store.applyTidy(plan, tabIDs: request, in: mixed.id)
        let groups = store.tabGroups(in: mixed.id)
        expect(groups.map(\.title) == ["First", "Second"], "new groups follow visible Today order, not unseen-first prompt priority")
        expect(groups[0].children == [old[0], fresh[0]] && groups[1].children == [fresh[1], old[1]],
               "group members retain Today order while resolving the captured prompt mapping")
        expect(store.undoTidy() && store.item(mixed.todayContainerID)?.children == before,
               "undo restores exact Today order after a prioritized request")
        expect(store.integrityProblems().isEmpty, "prioritized mapping and undo preserve sidebar integrity")

        for limit in [TidyTabs.maximumTabs, 7] {
            let space = store.createSpace(title: "Fitted tidy", emoji: "🧹")
            for i in 0..<75 { store.createTab(url: "https://example.org/fitted/\(i)", in: space.id, select: false) }
            let original = store.looseTodayTabs(space.id).map(\.id)
            var seen = Set<UUID>()
            let attempts = (original.count + limit - 1) / limit
            for attempt in 0..<attempts {
                expect(store.canTidy(space.id), "a fitted request leaves unconsidered tabs eligible before attempt \(attempt)")
                let selected = Array(store.tidyCandidates(space.id).prefix(limit).map(\.id))
                let unseen = original.filter { !seen.contains($0) }
                expect(Array(selected.prefix(unseen.count)) == Array(unseen.prefix(limit)),
                       "each fitted request prioritizes remaining unseen IDs in Today order")
                store.applyTidy(TidyTabs.plan([], tabCount: selected.count, existingGroups: []), tabIDs: selected, in: space.id)
                seen.formUnion(selected)
                expect(store.tidiedTabs[space.id] == seen, "successful fitted prefixes accumulate considered IDs")
                expect(store.canTidy(space.id) == (seen.count < original.count),
                       "fitted requests remain offered exactly while an unseen loose tab survives")
            }
            expect(seen == Set(original) && !store.canTidy(space.id),
                   "successful empty requests converge across all 75 tabs with prefix limit \(limit)")
            let old = original[0]
            store.archiveTab(old, reason: .manual)
            let arrival = store.createTab(url: "https://example.org/fitted/new", in: space.id, select: false)
            let selected = Array(store.tidyCandidates(space.id).prefix(limit).map(\.id))
            expect(selected.first == arrival.id, "new loose tabs precede previously considered context")
            store.applyTidy(TidyTabs.plan([], tabCount: selected.count, existingGroups: []), tabIDs: selected, in: space.id)
            expect(!store.canTidy(space.id) && store.tidiedTabs[space.id] == Set(original.filter { $0 != old } + [arrival.id]),
                   "completion prunes absent IDs while retaining all surviving considered tabs")
            expect(store.item(space.todayContainerID)?.children == [arrival.id] + original.filter { $0 != old },
                   "request prioritization never reorders the visible loose tabs")
            expect(store.integrityProblems().isEmpty, "fitted request convergence preserves sidebar integrity")
        }
    }

    /// Arc's decoded singleton example must survive live filtering, undo and empty-header pruning.
    @MainActor
    private static func tidySingletonGroups() {
        let store = AppComposition(clock: ManualScheduler()).store
        let space = store.createSpace(title: "Singleton tidy", emoji: "🧹")
        for i in 0..<6 { store.createTab(url: "https://example.org/singleton/\(i)", in: space.id, select: false) }
        let original = store.looseTodayTabs(space.id).map(\.id)
        let calendar = TidyTabs.Plan(newGroups: [.init(name: "Calendar", tabs: [0])], joins: [:])
        store.applyTidy(calendar, tabIDs: original, in: space.id)
        var groups = store.tabGroups(in: space.id)
        expect(groups.count == 1 && groups[0].children == [original[0]], "a live singleton assignment creates its named header")
        expect(store.undoTidy() && store.tabGroups(in: space.id).isEmpty
               && store.item(space.todayContainerID)?.children == original,
               "undo restores exact loose order and prunes the new singleton header")
        let pair = TidyTabs.Plan(newGroups: [.init(name: "Survivor", tabs: [0, 1])], joins: [:])
        store.archiveTab(original[0], reason: .manual)
        store.applyTidy(pair, tabIDs: original, in: space.id)
        groups = store.tabGroups(in: space.id)
        expect(groups.count == 1 && groups[0].children == [original[1]], "one eligible survivor of a pair still forms a valid group")
        let groupID = groups[0].id
        store.archiveTab(original[1], reason: .manual)
        expect(store.item(groupID) == nil && store.tabGroups(in: space.id).isEmpty, "closing the sole member prunes its empty header")
        store.applyTidy(pair, tabIDs: original, in: space.id)
        expect(store.tabGroups(in: space.id).isEmpty, "zero surviving eligible members never create an empty header")
        store.applyTidy(calendar, tabIDs: [original[2]], in: space.id)
        let removedHeader = store.tabGroups(in: space.id)[0].id
        store.removeGroupHeader(removedHeader)
        expect(store.item(removedHeader) == nil && store.item(original[2])?.parentID == space.todayContainerID,
               "Remove header leaves a singleton loose and prunes its former header")
        expect(store.integrityProblems().isEmpty, "singleton application, undo and pruning preserve sidebar integrity")
    }

    /// Tidy Tab Titles hears of a tab pinned from elsewhere, once, and only while it has no name.
    @MainActor
    private static func pinHook() {
        let store = AppComposition(clock: ManualScheduler()).store
        var heard: [UUID] = []
        store.tabPinned = { heard.append($0) }
        let sid = store.createSpace(title: "Pins", emoji: "📌").id
        let a = store.createTab(url: "https://example.org/a", in: sid, select: false)
        let b = store.createTab(url: "https://example.org/b", in: sid, select: false)
        store.rename(b.id, to: "Mine")
        store.pinTab(a.id)
        store.pinTab(b.id)
        expect(heard == [a.id], "pinning tells Tidy Tab Titles about an unnamed tab, not a named one")
        let pinned = store.focusedSpace.pinnedContainerID
        store.moveItem(a.id, to: pinned, index: 0)
        let folder = store.createFolder(named: "F", in: pinned)
        store.moveItem(a.id, to: folder.id, index: nil)
        expect(heard == [a.id], "moves inside the pinned tabs don't count")
        store.unpinTab(a.id)
        store.togglePinned(a.id)
        expect(heard == [a.id, a.id], "pinning it again does")
    }

    // promise: #191 #180
    /// A tab dropped on the middle of a pinned tab makes a split, not a folder (#191), in the
    /// pinned tab's place, as Arc 1.172 does (#180, observed live): a Today tab becomes a pinned
    /// split with it, two pinned tabs combine where the target was, inside its folder if it has
    /// one. Both tabs move into the split (no copies), the dropped one on the side it was dropped,
    /// its pane focused.
    @MainActor
    private static func dropOnPinnedTabSplits() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Drop", emoji: "🪂").id
        guard let space = store.space(sid) else { return expect(false, "the space is made") }
        let first = store.createTab(url: "https://example.com/first", title: "First", in: sid, pinned: true, select: false)
        let pinned = store.createTab(url: "https://example.com/pinned", title: "Pinned", in: sid, pinned: true, select: false)
        let last = store.createTab(url: "https://example.com/last", title: "Last", in: sid, pinned: true, select: false)
        let older = store.createTab(url: "https://example.com/older", in: sid, select: false)
        let dragged = store.createTab(url: "https://example.com/dragged", in: sid, select: false)

        // A Today tab on the left half of the pinned row: .split(with: pinned, leading: true).
        guard let split = store.combineIntoSplit(dragged.id, onto: pinned.id, leading: true) else {
            return expect(false, "the drop makes a split")
        }
        expect(store.children(of: space.pinnedContainerID).map(\.id) == [first.id, split.id, last.id],
               "the split is pinned, in the pinned tab's place")
        expect(store.children(of: space.todayContainerID).map(\.id) == [older.id], "the dropped tab left Today; nothing opened there")
        expect(store.children(of: split.id).map(\.id) == [dragged.id, pinned.id],
               "both tabs are the panes, the dropped one on the side it was dropped")
        expect(store.isPinned(dragged.id) && store.item(dragged.id)?.tab?.savedURL == "https://example.com/dragged",
               "the dropped tab is pinned, its page its home")
        expect(store.item(split.id)?.split?.focusTabID == dragged.id, "the dropped tab's pane is focused")

        // Pinned on pinned (the reporter's case), inside a folder, on the right half.
        let folder = store.createFolder(named: "F", in: space.pinnedContainerID)
        let a = store.createTab(url: "https://example.com/a", in: sid, pinned: true, select: false, parent: folder.id)
        let b = store.createTab(url: "https://example.com/b", in: sid, pinned: true, select: false, parent: folder.id)
        guard let inner = store.combineIntoSplit(last.id, onto: b.id, leading: false) else {
            return expect(false, "the second drop makes a split")
        }
        expect(store.children(of: folder.id).map(\.id) == [a.id, inner.id] && store.children(of: inner.id).map(\.id) == [b.id, last.id],
               "two pinned tabs combine in the target's folder, with no new folder and no copy")
        expect(store.children(of: space.pinnedContainerID).map(\.id) == [first.id, split.id, folder.id], "the dropped tab left its slot")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #21
    /// ⌘Z (Arc, #21) brings back the tab closed last, open, then the one closed before it, each
    /// where it was: a pinned tab closed with its ✕ comes back pinned.
    @MainActor
    private static func reopenClosedTabs() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Undo", emoji: "↩️").id
        guard let space = store.space(sid) else { return expect(false, "the space is made") }
        let pinned = store.createTab(url: "https://example.com/undo-pinned", in: sid, pinned: true, select: false)
        let first = store.createTab(url: "https://example.com/undo-first", in: sid)
        let second = store.createTab(url: "https://example.com/undo-second", in: sid)
        store.archiveTab(pinned.id, reason: .manual)
        store.archiveTab(first.id, reason: .manual)
        store.archiveTab(second.id, reason: .manual)
        expect(store.reopenLastArchived()?.id == second.id && store.selectedTabID == second.id
               && store.spaceID(ofItem: second.id) == sid && !store.isPinned(second.id),
               "⌘Z brings back the tab closed last, in its space's Today, open")
        expect(store.reopenLastArchived()?.id == first.id && store.selectedTabID == first.id, "again: the one closed before it")
        expect(store.reopenLastArchived()?.id == pinned.id && store.isPinned(pinned.id)
               && store.children(of: space.pinnedContainerID).map(\.id) == [pinned.id], "a pinned tab comes back pinned")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #566
    /// ⇧⌘T after ⌘W on the open pinned tab (Close and Keep Pinned) brings the tab back at the page
    /// it was on, not at its pinned page (#566), taking turns with archived tabs by when each
    /// closed. A pinned split comes back with every pane where it was.
    @MainActor
    private static func reopenClosedPinnedTabs() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        store.clearArchive()  // what earlier tests archived (and saved) would come back first
        let sid = store.createSpace(title: "Pinned Undo", emoji: "📌").id
        let pinned = store.createTab(url: "https://example.com/pinned", title: "Home", in: sid, pinned: true, select: false)
        let today = store.createTab(url: "https://example.com/today", in: sid)

        store.archiveTab(today.id, reason: .manual)
        clock.advance(by: 60)
        store.selectTab(pinned.id)
        store.updateTab(pinned.id, url: "https://example.com/pinned/video", title: "Video")
        store.closePinnedTab(pinned.id, wasOpen: true)
        store.selectTab(nil)
        expect(store.item(pinned.id)?.tab?.url == "https://example.com/pinned",
               "⌘W puts the pinned tab back on its pinned page")

        expect(store.reopenLastClosed() != nil && store.selectedTabID == pinned.id
               && store.item(pinned.id)?.tab?.url == "https://example.com/pinned/video"
               && store.item(pinned.id)?.tab?.savedTitle == "Video",
               "⇧⌘T brings back the pinned tab closed last at the page it was on (#566)")
        expect(store.item(pinned.id)?.tab?.savedURL == "https://example.com/pinned" && store.isPinned(pinned.id),
               "and its pinned page stays what it was")
        expect(store.reopenLastClosed() == .archived(today.id) && store.selectedTabID == today.id,
               "⇧⌘T again brings back the tab archived before it")

        // A pinned tab closed from the background isn't on the stack: only the open one is.
        store.updateTab(pinned.id, url: "https://example.com/pinned/elsewhere")
        store.closePinnedTab(pinned.id, wasOpen: false)
        expect(store.reopenLastClosed() == nil, "a pinned tab closed in the background leaves nothing to reopen")

        // A pinned split closes as one and comes back with each pane on its page.
        let left = store.createTab(url: "https://example.com/left", in: sid, pinned: true, select: false)
        let right = store.createTab(url: "https://example.com/right", in: sid, pinned: true, select: false)
        guard store.createSplit(with: [left.id, right.id], inPlace: true) != nil, store.isPinned(left.id) else { return expect(false, "the split is made") }
        store.selectTab(right.id)
        store.updateTab(left.id, url: "https://example.com/left/deep")
        store.updateTab(right.id, url: "https://example.com/right/deep")
        let panes = store.closePinnedTab(right.id, wasOpen: true)
        store.selectTab(nil)
        expect(Set(panes) == [left.id, right.id] && store.item(left.id)?.tab?.url == "https://example.com/left",
               "⌘W on a pinned split takes every pane home")
        store.reopenLastClosed()
        expect(store.selectedTabID == right.id && store.item(left.id)?.tab?.url == "https://example.com/left/deep"
               && store.item(right.id)?.tab?.url == "https://example.com/right/deep",
               "⇧⌘T brings the split back with both panes where they were")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #601
    /// Settings ▸ Tabs ▸ "Reopen tabs from this Space only" (#601, not in Arc). The issue's steps:
    /// Tab 1 closed in Space A, Tab 2 in Space B, then ⇧⌘T back in Space A. Arc switches to Space B
    /// for Tab 2, and so does Cra by default; with the switch on, Tab 1 comes back in Space A.
    @MainActor
    private static func reopenClosedTabInThisSpaceOnly() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        store.clearArchive()
        let a = store.createSpace(title: "Reopen A", emoji: "A", focus: true).id
        let b = store.createSpace(title: "Reopen B", emoji: "B", focus: false).id
        let pinnedA = store.createTab(url: "https://example.com/a-pinned", in: a, pinned: true, select: false)
        let tab1 = store.createTab(url: "https://example.com/tab1", in: a)
        store.archiveTab(tab1.id, reason: .manual)
        clock.advance(by: 60)
        store.focusSpace(b)
        let tab2 = store.createTab(url: "https://example.com/tab2", in: b)
        store.archiveTab(tab2.id, reason: .manual)
        clock.advance(by: 60)
        store.focusSpace(a)

        expect(store.reopenLastClosed() == .archived(tab2.id) && store.focusedSpaceID == b,
               "by default ⇧⌘T brings back the tab closed last, in its own Space, as in Arc")
        store.archiveTab(tab2.id, reason: .manual)
        clock.advance(by: 60)
        store.focusSpace(a)

        store.settings.reopenClosedTabCurrentSpaceOnly = true
        expect(store.reopenLastClosed() == .archived(tab1.id) && store.focusedSpaceID == a && store.selectedTabID == tab1.id,
               "with the switch on, ⇧⌘T brings back the tab closed in this Space and stays in it")

        // A pinned tab closed in B waits for B; A's own comes back first.
        store.selectTab(pinnedA.id)
        store.updateTab(pinnedA.id, url: "https://example.com/a-pinned/deep")
        store.closePinnedTab(pinnedA.id, wasOpen: true)
        clock.advance(by: 60)
        store.selectTab(nil)
        let reopened = store.reopenLastClosed()
        expect(reopened?.tabID == pinnedA.id && store.item(pinnedA.id)?.tab?.url == "https://example.com/a-pinned/deep"
               && store.focusedSpaceID == a,
               "a pinned tab closed in this Space comes back in it")
        expect(store.reopenLastClosed() == nil && store.focusedSpaceID == a,
               "with nothing left closed in this Space, ⇧⌘T stays put though Space B has a closed tab")
        store.focusSpace(b)
        expect(store.reopenLastClosed() == .archived(tab2.id) && store.focusedSpaceID == b,
               "and Space B's tab is still there for Space B")
        store.settings.reopenClosedTabCurrentSpaceOnly = false
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #600
    /// Arc's Duplicate on a tab's, a favorite's and a split's menu (#600), checked in Arc 1.173.1:
    /// the copy goes right after the original, in the same list (a pinned tab's copy is pinned), and
    /// stays in the background. A favorite's copy is a Today tab where new tabs go, not a favorite. A
    /// split comes back whole: each pane's page in order, its orientation and sizes. Duplicate on one
    /// pane of a split puts a copy of that page below the split, not a pane more inside it. `select`
    /// opens the copy (the folder preview's Duplicate).
    @MainActor
    private static func duplicateFavoritesAndSplits() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Duplicates", emoji: "🐑").id
        guard let space = store.space(sid) else { return expect(false, "the space is made") }
        let mail = store.createTab(url: "https://example.com/mail", title: "Mail", in: sid, select: false)
        let other = store.createTab(url: "https://example.com/other", title: "Other", in: sid, select: false)
        store.addToFavorites(mail.id, in: sid)
        store.addToFavorites(other.id, in: sid)
        let open = store.createTab(url: "https://example.com/open", title: "Open", in: sid)
        guard let copy = store.duplicateTab(mail.id) else { return expect(false, "a favorite duplicates") }
        expect(store.children(of: space.favoritesContainerID).map(\.id) == [mail.id, other.id],
               "a favorite's copy is no favorite (#600)")
        expect(store.children(of: space.todayContainerID).first?.id == copy.id && copy.tab?.url == "https://example.com/mail",
               "it is a Today tab of the same page, where new tabs go, as in Arc")
        expect(store.selectedTabID == open.id, "and it stays in the background")
        expect(store.item(copy.id)?.isUnread == false && store.item(copy.id)?.tab?.timeLastActiveAt == nil,
               "saved read, with no unread dot, and not among ⌃Tab's recent tabs, as Arc saves its copies")

        guard let tabCopy = store.duplicateTab(open.id) else { return expect(false, "a tab duplicates") }
        let today = store.children(of: space.todayContainerID).map(\.id)
        expect(today.firstIndex(of: tabCopy.id) == today.firstIndex(of: open.id).map { $0 + 1 } && store.selectedTabID == open.id,
               "a Today tab's copy is right after it, and the open tab stays open")
        expect(store.item(tabCopy.id)?.isUnread == false, "with no unread dot")
        let pinned = store.createTab(url: "https://example.com/pinned", in: sid, pinned: true, select: false)
        guard let pinnedCopy = store.duplicateTab(pinned.id) else { return expect(false, "a pinned tab duplicates") }
        expect(store.children(of: space.pinnedContainerID).map(\.id).suffix(2) == [pinned.id, pinnedCopy.id] && store.isPinned(pinnedCopy.id),
               "a pinned tab's copy is pinned, right after it")
        guard let opened = store.duplicateTab(open.id, select: true) else { return expect(false, "Duplicate Tab duplicates") }
        expect(store.selectedTabID == opened.id, "select opens the copy (the folder preview's Duplicate)")

        let left = store.createTab(url: "https://example.com/left", title: "Left", in: sid)
        let right = store.createTab(url: "https://example.com/right", title: "Right", in: sid)
        guard let split = store.createSplit(with: [left.id, right.id]) else { return expect(false, "the split is made") }
        store.flipSplitOrientation(split.id)
        store.setSplitWidthFactors(split.id, [left.id: 0.7, right.id: 0.3])
        store.selectTab(right.id)
        guard let twin = store.duplicateSplit(split.id), let twinData = twin.split else { return expect(false, "a split duplicates (#600)") }
        let rows = store.children(of: space.todayContainerID).map(\.id)
        expect(rows.firstIndex(of: twin.id) == rows.firstIndex(of: split.id).map { $0 + 1 }, "the split's copy goes right after it")
        let panes = twin.children.compactMap { store.item($0)?.tab?.url }
        expect(panes == ["https://example.com/left", "https://example.com/right"] && Set(twin.children).isDisjoint(with: [left.id, right.id]),
               "with a new tab for each pane's page, in order")
        expect(twinData.orientation == .vertical && twinData.widthFactors[twin.children[0]] == 0.7 && twinData.widthFactors[twin.children[1]] == 0.3,
               "the split's orientation and sizes come along")
        expect(store.selectedTabID == right.id && store.item(split.id)?.children == [left.id, right.id],
               "the original split stays open with its panes")
        expect(twin.children.allSatisfy { store.item($0)?.isUnread == false && store.item($0)?.tab?.timeLastActiveAt == nil },
               "its panes are saved read too")

        guard let paneCopy = store.duplicateTab(left.id) else { return expect(false, "a pane duplicates") }
        let after = store.children(of: space.todayContainerID).map(\.id)
        expect(store.item(split.id)?.children == [left.id, right.id] && store.splitContaining(paneCopy.id) == nil
               && after.firstIndex(of: paneCopy.id) == after.firstIndex(of: split.id).map { $0 + 1 },
               "Duplicate on a split's pane leaves the split as it was and puts the page's copy right below it")

        let pinnedLeft = store.createTab(url: "https://example.com/pl", in: sid, pinned: true, select: false)
        let pinnedRight = store.createTab(url: "https://example.com/pr", in: sid, pinned: true, select: false)
        guard let pinnedSplit = store.createSplit(with: [pinnedLeft.id, pinnedRight.id], inPlace: true),
              let pinnedTwin = store.duplicateSplit(pinnedSplit.id) else { return expect(false, "a pinned split duplicates") }
        expect(store.children(of: space.pinnedContainerID).map(\.id).suffix(2) == [pinnedSplit.id, pinnedTwin.id]
               && pinnedTwin.children.allSatisfy(store.isPinned), "a pinned split's copy is pinned, right after it")

        store.addToFavorites(pinnedSplit.id, in: sid)
        guard store.isFavorite(pinnedSplit.id), let favoriteTwin = store.duplicateSplit(pinnedSplit.id) else { return expect(false, "a favorite split duplicates") }
        expect(store.children(of: space.todayContainerID).first?.id == favoriteTwin.id && !store.isFavorite(favoriteTwin.id),
               "a favorite split's copy is a Today split, as a favorite tab's is")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #2 #4
    /// ⌘N (#2): a new window opens on the space in use, every window lists the same tabs, and
    /// each window shows a space of its own. A tab open in two windows stays selected in both (#4).
    @MainActor
    private static func windowsShareTheSidebar() {
        let store = AppComposition(clock: ManualScheduler()).store
        let home = store.createSpace(title: "Windows Home", emoji: "🏠").id
        let work = store.createSpace(title: "Windows Work", emoji: "💼", focus: false).id
        let first = store.activeWindowID
        let tab = store.createTab(url: "https://example.com/both-windows", in: home, window: first)
        let second = store.addWindow(spaceID: store.focusedSpaceID(window: first), frame: nil).id
        expect(store.focusedSpaceID(window: second) == home, "a new window opens on the space in use")
        let made = store.createTab(url: "https://example.com/second-window", window: second)
        let today = store.space(home)!.todayContainerID
        expect(store.spaceID(ofItem: made.id) == home && store.tabs(under: today).map(\.id).contains(made.id),
               "a tab opened in the new window is in the space's Today, which the first window shows too")
        store.selectTab(tab.id, window: second)
        expect(store.selectedTabID(in: home, window: second) == tab.id && store.selectedTabID(in: home, window: first) == tab.id,
               "a tab opened in the second window stays selected in the first (#4)")
        store.focusSpace(work, window: second)
        expect(store.focusedSpaceID(window: second) == work && store.focusedSpaceID(window: first) == home
               && store.selectedTabID(in: home, window: first) == tab.id, "each window shows a space of its own")
        store.removeWindow(second)
        expect(store.item(tab.id) != nil && store.item(made.id) != nil, "closing a window keeps the tabs")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #614
    /// Clear Today, auto-archive, deleting a space and Archive Tabs Above/Below archived tab by tab, each
    /// with a full touch() (the document copied, empty groups pruned, a save): quadratic at 5,000 tabs.
    /// A batch is one change, with the archive in the order one-by-one archiving gave.
    @MainActor
    private static func clearTodayArchivesInOnePass() {
        let store = SidebarStore(clock: ManualScheduler())
        let sid = store.focusedSpaceID
        let ids = (0..<50).map { store.createTab(url: "https://example.com/batch/\($0)", select: false).id }
        let shown = store.createTab(url: "https://example.com/shown").id
        let before = store.revision
        store.clearToday(sid, playing: [])
        expect(store.revision == before + 1, "Clear Today on 50 tabs is one change to the sidebar (#614), was \(store.revision - before)")
        // (The store may have loaded tabs an earlier test saved; they're archived too.)
        expect(Set(store.archive.map(\.id)).isSuperset(of: ids) && ids.allSatisfy { store.item($0) == nil } && store.item(shown) != nil,
               "the 50 tabs are archived, the one on screen stays")
        // The order sequential archiving gave: each went in at the top.
        let sequential = SidebarStore(clock: ManualScheduler())
        let again = (0..<3).map { sequential.createTab(url: "https://example.com/one/\($0)", select: false).id }
        for id in again { sequential.archiveTab(id, reason: .manual) }
        let batch = SidebarStore(clock: ManualScheduler())
        let lot = (0..<3).map { batch.createTab(url: "https://example.com/lot/\($0)", select: false).id }
        batch.archiveTabs(lot, reason: .manual)
        let one = sequential.archive.prefix(3).map { again.firstIndex(of: $0.id) ?? -1 }
        let many = batch.archive.prefix(3).map { lot.firstIndex(of: $0.id) ?? -1 }
        expect(one == many && one == [2, 1, 0], "a batch archives in the order one-by-one archiving did (\(one) vs \(many))")
    }

    /// Two Macs on one sync folder: the second takes the first's sidebar, a change on either reaches
    /// the other on its next look, a Mac never applies its own write, a half-synced bundle waits.
    @MainActor
    private static func settingsSync() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = AppComposition(clock: clockA).store
        _ = a.createSpace(title: "Studio Space", emoji: "🎛️")
        a.settings.searchEngine = .kagi
        a.settings.setDownloadLocation(DownloadLocation(folder: "/Volumes/Studio"), profileID: nil)
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder) == .synced, "the first Mac writes its bundle at once")
        let bundle = folder.appendingPathComponent(SettingsSync.folderName)
        expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent(SettingsSync.manifestName).path)
               && FileManager.default.fileExists(atPath: bundle.appendingPathComponent(SettingsSync.sidebarName).path),
               "the bundle sits in a Cra folder inside the chosen one")
        expect(syncA.isEnabled && syncA.lastSync == clockA.now, "sync is on and dated by the app's clock")
        let relaunched = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(relaunched.folder?.standardizedFileURL == bundle.standardizedFileURL,
               "after a relaunch the bundle still goes to the Cra folder, never over the chosen folder's own files")
        try? FileManager.default.removeItem(at: bundle)
        syncA.poll()
        expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent(SettingsSync.manifestName).path),
               "a Cra folder deleted from the provider is written again on the next look")

        let b = SidebarStore(clock: clockB)
        b.settings.setDownloadLocation(DownloadLocation(askWhereToSave: true), profileID: nil)
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        var reloads = 0
        syncB.keybindingsChanged = { reloads += 1 }
        guard case .bundleFound(let found) = syncB.enable(folder: folder) else { return expect(false, "the second Mac is asked about the bundle it finds") }
        expect(found.device == "Studio" && found.spaces == a.orderedSpaces.count, "the question names the other Mac and its spaces")
        expect(!syncB.isEnabled && !b.orderedSpaces.map(\.title).contains("Studio Space"), "nothing is applied before the answer")
        syncB.useRemote()
        expect(b.orderedSpaces.map(\.title) == a.orderedSpaces.map(\.title), "Use That Sidebar: the second Mac shows the first's spaces")
        expect(b.settings.searchEngine == .kagi, "and its settings")
        expect(b.settings.downloadLocation(profileID: nil).askWhereToSave, "but keeps its own download folder")
        expect(reloads == 1 && syncB.otherDevices == ["Studio"], "shortcuts are read again and the other Mac is listed")
        expect(b.integrityProblems().isEmpty, "the applied sidebar is sound")

        let own = SettingsSyncService(store: b, clock: clockB).deviceID
        expect(own.count == 32 && own == SettingsSyncService(store: a, clock: clockA).deviceID
               && own != SettingsSyncService.deviceID(hardwareUUID: "6B29FC40-CA47-1067-B31D-00DD010662DA"),
               "a Mac is known in the folder by a hash of its hardware, the same each launch")
        // Migration Assistant gives the new Mac the old one's name: the two still sync.
        let twin = SidebarStore(clock: ManualScheduler(now: clockA.now))
        let syncTwin = SettingsSyncService(store: twin, clock: clockA, device: "Studio", deviceID: "studio-new")
        guard case .bundleFound = syncTwin.enable(folder: folder) else { return expect(false, "a Mac with the same name as the writer is asked about its bundle") }
        syncTwin.useRemote()
        expect(twin.orderedSpaces.map(\.title) == a.orderedSpaces.map(\.title), "and takes its sidebar")
        syncTwin.disable()

        // A change on the first Mac reaches the second on its next look.
        clockA.advance(by: 10)
        _ = a.createSpace(title: "Studio Later", emoji: "🕐", focus: false)
        syncA.poll()
        syncB.poll()
        expect(b.orderedSpaces.map(\.title).contains("Studio Later"), "a space made on the first Mac shows on the second")
        let manifestURL = bundle.appendingPathComponent(SettingsSync.manifestName)
        let before = try? Data(contentsOf: manifestURL)
        syncB.poll()
        expect((try? Data(contentsOf: manifestURL)) == before, "a look that finds nothing new writes nothing")

        // And back: the second Mac's setting reaches the first, which never applies its own write.
        clockB.advance(by: 20)
        b.settings.httpsOnly = true
        syncB.poll()
        syncA.poll()
        expect(a.settings.httpsOnly, "a setting changed on the second Mac reaches the first")
        expect(a.settings.downloadLocation(profileID: nil).folder == "/Volumes/Studio", "the first keeps its own download folder")
        expect(a.orderedSpaces.map(\.title).contains("Studio Later"), "its spaces are the same, so nothing was lost")
        expect(syncA.otherDevices == ["MacBook"], "the first Mac now lists the second")
        let spacesA = a.orderedSpaces.map(\.title)
        syncA.poll()
        expect(a.orderedSpaces.map(\.title) == spacesA && (try? Data(contentsOf: manifestURL)) != before, "the first Mac leaves its own bundle alone")

        // A manifest that names files not yet downloaded waits.
        clockA.advance(by: 30)
        let stale = SyncManifest(device: "Mini", deviceID: "mini", writtenAt: clockA.now, files: [SettingsSync.sidebarName: "not-there"])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(stale).write(to: manifestURL)
        syncB.poll()
        expect(!syncB.otherDevices.contains("Mini"), "a bundle whose files have not all arrived is not applied")

        syncB.disable()
        expect(syncB.folder == nil && !syncB.isEnabled && b.settings.httpsOnly, "Stop Syncing keeps what is on the Mac")

        // replace(document:) repairs like a launch: a space on a profile the other Mac deleted goes to Default.
        var doc = a.document
        doc.profiles = nil
        let gone = UUID()
        doc.spaces[0].profileID = gone
        var replacedTold = 0
        let replacedObserver = NotificationCenter.default.addObserver(forName: SidebarStore.documentReplaced, object: b, queue: nil) { _ in replacedTold += 1 }
        b.replace(document: doc)
        NotificationCenter.default.removeObserver(replacedObserver)
        expect(b.orderedSpaces[0].profileID == nil && b.integrityProblems().isEmpty, "a space on a missing profile falls back to Default")
        expect(replacedTold == 1, "a replaced document is told once, for the pages to put their own addresses back")
    
        // Stopped before the tests below: every service here saves the one sync.json, and this
        // one's debounced save must not land in the middle of theirs.
        syncA.disable()
        iCloudSync(first: a, firstClock: clockA)
        syncGoesOnWithoutAsking()
        syncWritesSoonAfterAChange()
        syncLooksWithoutEncodingWhatDidNotChange()
        syncPutsAMixedBundleRight()
        syncPutsAFileThatNeverArrivesRight()
        syncLeavesAMixToItsWriterOnANewMac()
        syncKeepsAClosedTabClosed()
        syncKeepsAClosedTabClosedAfterTwoWritesThere()
        syncKeepsASettingChangedBeforeTheOtherMacWrote()
        syncKeepsATabSeenOnTheOtherMac()
        syncKeepsATabSeenHereThatTheOtherMacArchivedFirst()
        syncEasels()
    }

    /// A tab closed on one Mac came back (reported by a user, 13 Nov 2026). The other Mac still
    /// had it and wrote its own bundle (a page there changed its title) from the bundle before
    /// the close, and the first Mac took that whole sidebar. A bundle now says which bundle it was
    /// written from, and a Mac that has that one merges the two: what changed on either Mac
    /// since then is kept, and a tab closed on either stays closed.
    @MainActor
    private static func syncKeepsAClosedTabClosed() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-closed-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = SidebarStore(clock: clockA), b = SidebarStore(clock: clockB)
        let doomed = a.createTab(url: "https://example.com/doomed", title: "Doomed")
        let kept = a.createTab(url: "https://example.com/kept", title: "Kept")
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder) == .synced, "the first Mac writes its bundle")
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncB.enable(folder: folder) else { return expect(false, "the second Mac is asked once") }
        syncB.useRemote()
        expect(b.item(doomed.id) != nil && b.item(kept.id) != nil, "both Macs have both tabs")

        // The first Mac closes a tab and writes. The provider is slow: the second Mac still sees the
        // bundle before the close when a page there changes its title and a tab opens, and it writes.
        let bundle = folder.appendingPathComponent(SettingsSync.folderName)
        let names = [SettingsSync.manifestName] + SettingsSync.fileNames
        let before = Dictionary(uniqueKeysWithValues: names.map { ($0, try? Data(contentsOf: bundle.appendingPathComponent($0))) })
        clockA.advance(by: 10); clockB.advance(by: 10)
        a.archiveTab(doomed.id, reason: .manual)
        syncA.poll()
        for name in names { try? before[name]??.write(to: bundle.appendingPathComponent(name)) }
        clockB.advance(by: 5)
        b.updateTab(kept.id, title: "Kept, renamed")
        let opened = b.createTab(url: "https://example.com/opened-on-macbook", title: "Opened")
        syncB.poll()
        expect(b.item(doomed.id) != nil, "the second Mac has not seen the close yet")

        // The second Mac's bundle is what the provider keeps. The first Mac merges it with its close.
        clockA.advance(by: 10)
        syncA.poll()
        expect(a.item(doomed.id) == nil, "a tab closed on the first Mac stays closed when the second wrote before it saw the close")
        expect(a.item(kept.id)?.displayTitle == "Kept, renamed", "the title changed on the second Mac reaches the first")
        expect(a.item(opened.id) != nil, "and so does the tab opened there")
        expect(a.integrityProblems().isEmpty, "the merged sidebar is sound")

        // And the second Mac takes the merge: the closed tab goes there too.
        clockB.advance(by: 10)
        syncB.poll()
        expect(b.item(doomed.id) == nil, "the close reaches the second Mac")
        expect(b.item(kept.id)?.displayTitle == "Kept, renamed" && b.item(opened.id) != nil, "and its own changes stay")
        expect(b.integrityProblems().isEmpty, "its sidebar is sound")
        syncA.disable(); syncB.disable()
    }

    /// The same close, but the second Mac wrote twice before the first looked (it writes on each
    /// look that finds a change, and iCloud hands over only the later bundle). That bundle was
    /// written from the second Mac's own earlier one, which never reached the first Mac; it also
    /// names the bundle before that, which the first Mac has, and the merge is against that one.
    @MainActor
    private static func syncKeepsAClosedTabClosedAfterTwoWritesThere() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-twice-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = SidebarStore(clock: clockA), b = SidebarStore(clock: clockB)
        let doomed = a.createTab(url: "https://example.com/doomed", title: "Doomed")
        let kept = a.createTab(url: "https://example.com/kept", title: "Kept")
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder) == .synced, "the first Mac writes its bundle")
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncB.enable(folder: folder) else { return expect(false, "the second Mac is asked once") }
        syncB.useRemote()

        let bundle = folder.appendingPathComponent(SettingsSync.folderName)
        let names = [SettingsSync.manifestName] + SettingsSync.fileNames
        let before = Dictionary(uniqueKeysWithValues: names.map { ($0, try? Data(contentsOf: bundle.appendingPathComponent($0))) })
        clockA.advance(by: 10); clockB.advance(by: 10)
        a.archiveTab(doomed.id, reason: .manual)
        syncA.poll()
        for name in names { try? before[name]??.write(to: bundle.appendingPathComponent(name)) }
        clockB.advance(by: 5)
        b.updateTab(kept.id, title: "Kept, renamed")
        syncB.poll()
        clockB.advance(by: 30)
        let opened = b.createTab(url: "https://example.com/opened-on-macbook", title: "Opened")
        syncB.poll()
        expect(b.item(doomed.id) != nil, "the second Mac has not seen the close yet")

        clockA.advance(by: 60)
        syncA.poll()
        expect(a.item(doomed.id) == nil, "a tab closed on the first Mac stays closed when the second wrote twice before it looked")
        expect(a.item(kept.id)?.displayTitle == "Kept, renamed" && a.item(opened.id) != nil, "both of the second Mac's writes reach the first")
        expect(a.integrityProblems().isEmpty, "the merged sidebar is sound")
        clockB.advance(by: 60)
        syncB.poll()
        expect(b.item(doomed.id) == nil && b.item(opened.id) != nil, "the close reaches the second Mac and its tab stays")
        syncA.disable(); syncB.disable()
    }

    /// A setting changed on one Mac was lost when the other Mac, before iCloud brought it the change, wrote its bundle
    /// for a change of its own: the bundle's settings replaced this Mac's whole, while its sidebar was merged (X, Chris
    /// Coyier, 25 Nov 2026: "Archive tabs after" Never on one Mac, 12 hours on the other). Settings are merged field by
    /// field against the bundle both Macs had, as the sidebar is.
    @MainActor
    private static func syncKeepsASettingChangedBeforeTheOtherMacWrote() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-settings-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = SidebarStore(clock: clockA), b = SidebarStore(clock: clockB)
        a.settings.autoArchiveEnabled = true
        a.settings.autoArchive = .twelveHours
        a.settings.warnBeforeQuitting = false
        let tab = a.createTab(url: "https://example.com/kept", title: "Kept")
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder) == .synced, "the first Mac writes its bundle")
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncB.enable(folder: folder) else { return expect(false, "the second Mac is asked once") }
        syncB.useRemote()
        expect(b.settings.autoArchive(profileID: nil) == .after(.twelveHours), "both Macs start on 12 hours")

        let bundle = folder.appendingPathComponent(SettingsSync.folderName)
        let names = [SettingsSync.manifestName] + SettingsSync.fileNames
        let before = Dictionary(uniqueKeysWithValues: names.map { ($0, try? Data(contentsOf: bundle.appendingPathComponent($0))) })
        // The first Mac turns auto-archive off and writes; iCloud hasn't brought it to the second Mac yet.
        clockA.advance(by: 10); clockB.advance(by: 10)
        a.settings.setAutoArchive(.never, profileID: nil, otherProfiles: [])
        syncA.poll()
        for name in names { try? before[name]??.write(to: bundle.appendingPathComponent(name)) }
        // Meanwhile the second Mac renames a tab and changes a setting of its own, and writes.
        clockB.advance(by: 5)
        b.updateTab(tab.id, title: "Kept, renamed")
        b.settings.warnBeforeQuitting = true
        syncB.poll()

        clockA.advance(by: 60)
        syncA.poll()
        expect(a.settings.autoArchive(profileID: nil) == .never, "the first Mac keeps Never when the second Mac's bundle arrives")
        expect(a.settings.warnBeforeQuitting, "and takes the setting the second Mac changed")
        expect(a.item(tab.id)?.displayTitle == "Kept, renamed", "and its sidebar change")
        clockB.advance(by: 60)
        syncB.poll()
        expect(b.settings.autoArchive(profileID: nil) == .never, "Never reaches the second Mac")
        expect(b.settings.warnBeforeQuitting, "which keeps its own change")
        syncA.disable(); syncB.disable()
    }

    /// A tab looked at on one Mac is in use: the other Mac's archive pass doesn't take it, also when that pass ran before
    /// the other Mac's bundle arrived (at launch, after waking, iCloud still downloading). Its sidebar knew only the older
    /// look, archived the tab, and the close went back to the first Mac, where it was gone and in neither Archive there.
    @MainActor
    private static func syncKeepsATabSeenOnTheOtherMac() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-seen-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = SidebarStore(clock: clockA), b = SidebarStore(clock: clockB)
        a.settings.autoArchiveEnabled = true
        a.settings.autoArchive = .twelveHours
        let shown = a.createTab(url: "https://example.com/shown", title: "Shown", select: true)
        let seenAfterLook = a.createTab(url: "https://example.com/seen-after-look", title: "Seen, B looks first", select: false)
        let seenBeforeLook = a.createTab(url: "https://example.com/seen-before-look", title: "Seen, B archives first", select: false)
        let idle = a.createTab(url: "https://example.com/idle", title: "Idle on both", select: false)
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder) == .synced, "the first Mac writes its bundle")
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncB.enable(folder: folder) else { return expect(false, "the second Mac is asked once") }
        syncB.useRemote()
        b.selectTab(shown.id)

        // Eleven hours on, both tabs are looked at on the first Mac, which writes.
        clockA.advance(by: 11 * 3600); clockB.advance(by: 11 * 3600)
        a.selectTab(seenAfterLook.id)
        a.selectTab(seenBeforeLook.id)
        a.selectTab(shown.id)
        syncA.poll()

        // Two hours later on the second Mac: one pass after its look, as every 30 minutes.
        clockA.advance(by: 2 * 3600); clockB.advance(by: 2 * 3600)
        syncB.poll()
        b.runAutoArchive()
        expect(b.item(seenAfterLook.id) != nil, "a pass after the look keeps a tab looked at on the other Mac")
        expect(b.item(idle.id) == nil, "a tab idle on both Macs is archived")

        // The race: a pass before the look, as at launch or waking, then the look and the other Mac's.
        a.selectTab(seenBeforeLook.id)
        a.selectTab(shown.id)
        syncA.poll()
        clockA.advance(by: 13 * 3600 - 60); clockB.advance(by: 13 * 3600 - 60)
        a.selectTab(seenAfterLook.id); a.selectTab(shown.id)
        syncA.poll()
        clockB.advance(by: 60)
        b.runAutoArchive()
        syncB.poll()
        clockA.advance(by: 60)
        syncA.poll()
        expect(b.item(seenAfterLook.id) != nil, "the second Mac's early pass is undone for a tab the other Mac had looked at")
        expect(!b.archive.contains { $0.id == seenAfterLook.id }, "and it leaves the second Mac's Archive")
        expect(a.item(seenAfterLook.id) != nil, "the first Mac keeps the tab it looked at")
        expect(a.item(seenBeforeLook.id) == nil && b.item(seenBeforeLook.id) == nil, "a tab idle past the limit on both is archived")
        syncA.disable(); syncB.disable()
    }

    /// The other way round: the second Mac's pass took the tab and its bundle went up before iCloud brought it the first
    /// Mac's look. The bundle lists its auto-archives, and the first Mac, which had looked at the tab, keeps it; the second
    /// Mac then gets it back, out of its Archive.
    @MainActor
    private static func syncKeepsATabSeenHereThatTheOtherMacArchivedFirst() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-seen-here-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = SidebarStore(clock: clockA), b = SidebarStore(clock: clockB)
        a.settings.autoArchiveEnabled = true
        a.settings.autoArchive = .twelveHours
        let shown = a.createTab(url: "https://example.com/shown-here", title: "Shown", select: true)
        let seen = a.createTab(url: "https://example.com/seen-here", title: "Seen here", select: false)
        let manual = a.createTab(url: "https://example.com/closed-there", title: "Closed there", select: false)
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder) == .synced, "the first Mac writes its bundle")
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncB.enable(folder: folder) else { return expect(false, "the second Mac is asked once") }
        syncB.useRemote()
        b.selectTab(shown.id)

        let bundle = folder.appendingPathComponent(SettingsSync.folderName)
        let names = [SettingsSync.manifestName] + SettingsSync.fileNames
        let before = Dictionary(uniqueKeysWithValues: names.map { ($0, try? Data(contentsOf: bundle.appendingPathComponent($0))) })
        // Thirteen hours on, the first Mac looks at the tab and writes; iCloud hasn't brought that to the second Mac.
        clockA.advance(by: 13 * 3600); clockB.advance(by: 13 * 3600)
        a.selectTab(seen.id); a.selectTab(manual.id); a.selectTab(shown.id)
        syncA.poll()
        for name in names { try? before[name]??.write(to: bundle.appendingPathComponent(name)) }
        // Someone closes the other tab there by hand, the second Mac's pass takes this one, and it writes.
        clockB.advance(by: 60)
        b.archiveTab(manual.id, reason: .manual)
        b.runAutoArchive()
        syncB.poll()
        expect(b.item(seen.id) == nil, "the second Mac archived it, knowing only the older look")

        clockA.advance(by: 120)
        syncA.poll()
        expect(a.item(seen.id) != nil, "the first Mac keeps the tab it looked at")
        expect(a.item(manual.id) == nil, "a tab closed by hand on the other Mac still closes")
        clockB.advance(by: 120)
        syncB.poll()
        expect(b.item(seen.id) != nil, "the tab comes back on the second Mac")
        expect(!b.archive.contains { $0.id == seen.id }, "and leaves its Archive")
        syncA.disable(); syncB.disable()
    }

    /// iCloud is the same bundle in the app's container, with two differences a test folder can
    /// stand in for (CRA_SYNC_ICLOUD_DIR): the bundle goes to `Documents/Cra`, and a file iCloud
    /// has not downloaded is a placeholder, which Cra waits for instead of writing over it.
    @MainActor
    private static func iCloudSync(first a: SidebarStore, firstClock clockA: ManualScheduler) {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("cra-icloud-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        setenv("CRA_SYNC_ICLOUD_DIR", container.path, 1)
        defer { unsetenv("CRA_SYNC_ICLOUD_DIR") }

        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.iCloudAvailable, "with a container the iCloud switch is offered")
        expect(syncA.enableICloud() == .synced && syncA.location == .iCloud, "the first Mac turns iCloud on and writes its bundle")
        let bundle = container.appendingPathComponent("Documents/Cra", isDirectory: true)
        expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent(SettingsSync.manifestName).path),
               "the bundle sits in Documents/Cra of the container, where iCloud Drive shows it")

        // iCloud delivered the manifest but not yet the sidebar: a placeholder stands in for it.
        let sidebar = bundle.appendingPathComponent(SettingsSync.sidebarName)
        let placeholder = bundle.appendingPathComponent(SettingsSync.placeholderName(for: SettingsSync.sidebarName))
        try? FileManager.default.moveItem(at: sidebar, to: placeholder)
        let clockB = ManualScheduler(now: clockA.now)
        let b = SidebarStore(clock: clockB)
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        expect(syncB.enableICloud() == .downloading && syncB.awaitingDownload && !syncB.isEnabled,
               "the second Mac waits for the download instead of writing its own sidebar over it")
        expect(FileManager.default.fileExists(atPath: placeholder.path), "nothing in the bundle was touched while waiting")
        syncB.poll()
        expect(syncB.awaitingDownload && syncB.pendingChoice == nil, "a look while the file is still a placeholder keeps waiting")
        // The download finished.
        try? FileManager.default.moveItem(at: placeholder, to: sidebar)
        syncB.poll()
        expect(!syncB.awaitingDownload && syncB.pendingChoice?.device == "Studio", "once the bundle is whole the user is asked which sidebar to keep")
        syncB.useRemote()
        expect(b.orderedSpaces.map(\.title) == a.orderedSpaces.map(\.title) && syncB.isEnabled, "Use That Sidebar: the second Mac takes the first's spaces")

        // Since macOS 14 a file iCloud has not downloaded keeps its name (a dataless file), and
        // reading it waits for the download on the main thread: Cra asks for it and looks again.
        let clockC = ManualScheduler(now: clockA.now)
        let syncC = SettingsSyncService(store: SidebarStore(clock: clockC), clock: clockC, device: "Mini", deviceID: "mini")
        var downloaded = false
        syncC.downloadStatus = { url in url.lastPathComponent == SettingsSync.sidebarName && !downloaded ? .notDownloaded : nil }
        expect(syncC.enableICloud() == .downloading && syncC.awaitingDownload, "a file iCloud has not downloaded yet is waited for, not read")
        downloaded = true
        syncC.poll()
        expect(syncC.pendingChoice?.device == "Studio", "once it is current the question comes")
        syncC.disable()

        syncB.disable()
        let fresh = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        expect(fresh.location == nil, "Stop Syncing is remembered across a relaunch")
        syncA.disable()
    }

    // promise: #598
    /// A change made here was written only at the next 30-second look. It goes up 3 s after the last
    /// change; a tab switch alone (last-active times) waits for the look, as before.
    @MainActor
    private static func syncWritesSoonAfterAChange() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-soon-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualScheduler()
        let a = SidebarStore(clock: clock)
        let first = a.createTab(url: "https://example.com/one").id
        let second = a.createTab(url: "https://example.com/two").id
        let sync = SettingsSyncService(store: a, clock: clock, device: "Studio", deviceID: "studio")
        expect(sync.enable(folder: folder) == .synced, "sync is on, with this Mac's bundle written")
        let manifest = folder.appendingPathComponent(SettingsSync.folderName).appendingPathComponent(SettingsSync.manifestName)
        let written = try? Data(contentsOf: manifest)

        // A tab switch: only last-active times change. Nothing goes up before the look.
        clock.advance(by: 5)
        a.selectTab(first)
        a.selectTab(second)
        clock.advance(by: SettingsSync.writeSoonDelay + 1)
        expect((try? Data(contentsOf: manifest)) == written, "a tab switch alone waits for the 30-second look")

        // A rename: written 3 s after the last change, well before the look.
        a.rename(second, to: "Renamed here")
        clock.advance(by: 1)
        a.rename(second, to: "Renamed here, twice")
        clock.advance(by: SettingsSync.writeSoonDelay - 1)
        expect((try? Data(contentsOf: manifest)) == written, "not while changes keep coming")
        clock.advance(by: 1)
        let soon = try? Data(contentsOf: manifest)
        expect(soon != written, "the bundle is written 3 s after the last change (#598)")
        let sidebar = (try? Data(contentsOf: folder.appendingPathComponent(SettingsSync.folderName).appendingPathComponent(SettingsSync.sidebarName))) ?? Data()
        expect(String(decoding: sidebar, as: UTF8.self).contains("Renamed here, twice"), "with the change in it")
        sync.disable()
    }

    // promise: #615
    /// A look every 30 seconds sorted, encoded and hashed the whole sidebar and decoded the folder's,
    /// also when nothing had changed: with thousands of tabs, a stall on the main thread twice a
    /// minute (#615). An idle look now does neither. A title, a favicon, a setting or a shortcut
    /// changed here still goes up at the next look, encoded once and to the same bytes as before.
    @MainActor
    private static func syncLooksWithoutEncodingWhatDidNotChange() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-idle-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let shortcuts = AppPaths.file(SettingsSync.keybindingsName)
        let shortcutsBefore = try? Data(contentsOf: shortcuts)
        defer {
            if let shortcutsBefore { try? shortcutsBefore.write(to: shortcuts) } else { try? FileManager.default.removeItem(at: shortcuts) }
        }
        let clock = ManualScheduler()
        let a = SidebarStore(clock: clock)
        let tabs = (0..<1_500).map { a.createTab(url: "https://example.com/\($0)").id }
        let sync = SettingsSyncService(store: a, clock: clock, device: "Studio", deviceID: "studio")
        expect(sync.enable(folder: folder) == .synced, "sync is on, with this Mac's bundle written")
        let bundle = folder.appendingPathComponent(SettingsSync.folderName)
        func files() -> [String: Data] {
            Dictionary(uniqueKeysWithValues: ([SettingsSync.manifestName] + SettingsSync.fileNames).map {
                ($0, (try? Data(contentsOf: bundle.appendingPathComponent($0))) ?? Data())
            })
        }
        func sidebarText() -> String { String(decoding: files()[SettingsSync.sidebarName] ?? Data(), as: UTF8.self) }

        // Idle: the first look reads the bundle written; later looks encode and decode nothing.
        sync.poll()
        let written = files()
        let (encodes, decodes) = (sync.localEncodes, sync.folderDecodes)
        for _ in 0..<3 {
            clock.advance(by: 30)
            sync.poll()
        }
        expect(sync.localEncodes == encodes, "an idle look encodes nothing (\(sync.localEncodes - encodes) times)")
        expect(sync.folderDecodes == decodes, "an idle look decodes nothing (\(sync.folderDecodes - decodes) times)")
        expect(files() == written, "and writes nothing")

        // A title (updateTab moves no revision): written at the next look, encoded once, in the
        // bytes the bundle always had: pretty-printed, sorted keys, items by id string.
        a.updateTab(tabs[3], title: "Retitled here")
        sync.poll()
        expect(sync.localEncodes == encodes + 1, "one change, one encode (\(sync.localEncodes - encodes))")
        expect(sidebarText().contains("Retitled here"), "the title goes up")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var expected = a.document.forSync()
        expected.items.sort { $0.id.uuidString < $1.id.uuidString }
        expect(files()[SettingsSync.sidebarName] == (try? encoder.encode(expected)), "the same bytes as before #615")
        let afterTitle = files()
        sync.poll()
        expect(sync.localEncodes == encodes + 1 && files() == afterTitle, "and the look after it is idle again")

        // A favicon, a setting and a shortcut each go up too.
        a.setFaviconKey(tabs[5], "favicon.example")
        sync.poll()
        expect(sidebarText().contains("favicon.example"), "a favicon goes up")
        a.settings.httpsOnly.toggle()
        sync.poll()
        let settingsText = String(decoding: files()[SettingsSync.settingsName] ?? Data(), as: UTF8.self)
        expect(settingsText.contains("\"httpsOnly\" : \(a.settings.httpsOnly)"), "a setting goes up")
        try? Data(#"{"shortcuts":{"newTab":[{"key":"y","modifiers":1048576}]}}"#.utf8).write(to: shortcuts)
        sync.poll()
        expect(String(decoding: files()[SettingsSync.keybindingsName] ?? Data(), as: UTF8.self).contains("newTab"), "a shortcut goes up")
        let settled = sync.localEncodes
        sync.poll()
        expect(sync.localEncodes == settled, "idle again")
        sync.disable()
    }

    /// The question comes once, when sync is turned on. After the answer a bundle from the other
    /// Mac is applied by itself, also when iCloud delivers it in parts. Cra 0.1.38 took every
    /// later download for the first one: it asked again (only seen in Settings) and synced
    /// nothing until the answer.
    @MainActor
    private static func syncGoesOnWithoutAsking() {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent("cra-icloud-later-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: container) }
        setenv("CRA_SYNC_ICLOUD_DIR", container.path, 1)
        defer { unsetenv("CRA_SYNC_ICLOUD_DIR") }
        // Every store here loads settings.json from the one data folder, as the test before this one
        // left it once its 0.4 s save landed: with HTTPS-Only on. Under load it had landed, the second
        // Mac's change below changed nothing, and the third Mac was offered the first Mac's bundle
        // (18 Nov 2026). It is on disk every time now.
        let earlier = SidebarStore(clock: ManualScheduler())
        earlier.settings.httpsOnly = true
        earlier.saveAll()
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = SidebarStore(clock: clockA), b = SidebarStore(clock: clockB)
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enableICloud() == .synced, "the first Mac turns iCloud on")
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncB.enableICloud() else { return expect(false, "the second Mac is asked once") }
        syncB.useRemote()

        // The first Mac opens a tab. iCloud brings the manifest to the second Mac before the sidebar.
        clockA.advance(by: 10)
        let tab = a.createTab(url: "https://example.com/opened-on-studio")
        syncA.poll()
        var downloaded = false
        syncB.downloadStatus = { url in url.lastPathComponent == SettingsSync.sidebarName && !downloaded ? .notDownloaded : nil }
        syncB.poll()
        expect(syncB.pendingChoice == nil && b.document.items.first { $0.id == tab.id } == nil, "a bundle still downloading is not applied yet")
        downloaded = true
        syncB.poll()
        expect(syncB.pendingChoice == nil, "a later bundle from the other Mac brings no second question")
        expect(b.document.items.contains { $0.id == tab.id }, "the tab opened on the first Mac shows on the second")
        expect(syncB.isEnabled, "and sync stays on")

        // And back, with no question on the first Mac either.
        clockB.advance(by: 20)
        // A change whatever the loaded settings held: the second Mac turns HTTPS-Only the other way.
        let httpsOnly = !b.settings.httpsOnly
        b.settings.httpsOnly = httpsOnly
        syncB.poll()
        downloaded = false
        syncA.downloadStatus = { url in url.lastPathComponent == SettingsSync.settingsName && !downloaded ? .notDownloaded : nil }
        syncA.poll()
        downloaded = true
        syncA.poll()
        expect(syncA.pendingChoice == nil && a.settings.httpsOnly == httpsOnly, "a setting changed on the second Mac reaches the first without a question")

        // The first two Macs stop here, so that neither's debounced save of sync.json lands between
        // the third Mac's save and its relaunch.
        syncA.disable(); syncB.disable()

        // Cra quit while the first download was still coming in: the question is still asked.
        // The third Mac shares the first two's data folder here, and their 0.4 s saves of a sidebar
        // with the tab could land before it loads (under load, 18 Nov 2026): they are on disk now,
        // and the third Mac starts from a sidebar of its own, as it would on its own disk.
        a.saveAll(); b.saveAll()
        let clockC = ManualScheduler(now: clockB.now)
        let c = SidebarStore(clock: clockC)
        c.replace(document: .fresh())
        expect(!c.document.items.contains { $0.id == tab.id }, "the third Mac hasn't seen the tab")
        let syncC = SettingsSyncService(store: c, clock: clockC, device: "Mini", deviceID: "mini")
        syncC.downloadStatus = { url in url.lastPathComponent == SettingsSync.sidebarName ? .notDownloaded : nil }
        expect(syncC.enableICloud() == .downloading, "a third Mac turns iCloud on while the bundle downloads")
        let relaunched = SettingsSyncService(store: c, clock: clockC, device: "Mini", deviceID: "mini")
        relaunched.poll()
        expect(relaunched.pendingChoice?.device == "MacBook" && !c.document.items.contains { $0.id == tab.id },
               "after a relaunch the first bundle still waits for the answer")
        relaunched.disable()
        unsetenv("CRA_SYNC_ICLOUD_DIR")

        // The same in a folder a provider syncs (Dropbox, OneDrive): the manifest lands before a
        // file it names, then the file. No question, and the bundle is applied.
        let folder = container.appendingPathComponent("provider", isDirectory: true)
        let clockD = ManualScheduler(now: clockC.now), clockE = ManualScheduler(now: clockC.now)
        let d = SidebarStore(clock: clockD), e = SidebarStore(clock: clockE)
        let syncD = SettingsSyncService(store: d, clock: clockD, device: "Studio", deviceID: "studio")
        expect(syncD.enable(folder: folder) == .synced, "the first Mac syncs through a folder")
        let syncE = SettingsSyncService(store: e, clock: clockE, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncE.enable(folder: folder) else { return expect(false, "the second Mac is asked once about the folder's bundle") }
        syncE.useRemote()
        clockD.advance(by: 10)
        let later = d.createTab(url: "https://example.com/opened-on-studio-folder")
        let sidebarURL = folder.appendingPathComponent(SettingsSync.folderName).appendingPathComponent(SettingsSync.sidebarName)
        let old = try? Data(contentsOf: sidebarURL)
        syncD.poll()
        let arrived = try? Data(contentsOf: sidebarURL)
        try? old?.write(to: sidebarURL)
        syncE.poll()
        expect(syncE.pendingChoice == nil && !e.document.items.contains { $0.id == later.id }, "a bundle the provider has not finished is not applied yet")
        try? arrived?.write(to: sidebarURL)
        syncE.poll()
        expect(syncE.pendingChoice == nil && e.document.items.contains { $0.id == later.id } && syncE.isEnabled,
               "once the provider has delivered it, it is applied with no second question")
        syncD.disable(); syncE.disable()
    }

    // promise: #378
    /// Two writes that crossed leave the folder with one write's settings and the other's manifest
    /// (two Macs at once, or a provider that keeps one Mac's file and the other Mac's manifest).
    /// No download is coming, so after a short wait the Mac whose manifest it is writes its whole
    /// bundle again, with the tab opened meanwhile, and the other Mac applies it. Cra 0.1.40 took
    /// the mix for a download and both Macs stopped syncing for good.
    @MainActor
    private static func syncPutsAMixedBundleRight() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-mixed-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent(SettingsSync.folderName, isDirectory: true)
        let manifestURL = bundle.appendingPathComponent(SettingsSync.manifestName)
        let settingsURL = bundle.appendingPathComponent(SettingsSync.settingsName)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        func manifest() -> SyncManifest? { (try? Data(contentsOf: manifestURL)).flatMap { try? decoder.decode(SyncManifest.self, from: $0) } }
        /// The files are the ones the manifest names: a whole bundle.
        func whole() -> Bool {
            guard let m = manifest() else { return false }
            let hashes = Dictionary(uniqueKeysWithValues: SettingsSync.fileNames.compactMap { name in
                (try? Data(contentsOf: bundle.appendingPathComponent(name))).map { (name, SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()) }
            })
            return SettingsSync.isComplete(m, hashes: hashes)
        }
        /// Another write's settings: valid, but not the file the manifest names.
        func mixIn(httpsOnly: Bool) {
            var other = AppSettings()
            other.httpsOnly = httpsOnly
            other.searchEngine = .duckduckgo
            try? encoder.encode(other).write(to: settingsURL)
        }

        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = SidebarStore(clock: clockA), b = SidebarStore(clock: clockB)
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: root) == .synced, "the first Mac syncs through a folder")
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncB.enable(folder: root) else { return expect(false, "the second Mac is asked once") }
        syncB.useRemote()

        // The issue's steps: settings.json from another write, the manifest left as it was, a tab opened.
        // The stores read the shared test data folder: the mix is whichever httpsOnly this Mac doesn't have.
        let httpsOnly = a.settings.httpsOnly
        mixIn(httpsOnly: !httpsOnly)
        let mixed = try? Data(contentsOf: settingsURL)
        let tab = a.createTab(url: "https://example.com/opened-during-the-mix")
        syncA.poll()
        expect(!whole() && (try? Data(contentsOf: settingsURL)) == mixed, "the first look leaves the mix alone: it may still be arriving")
        clockA.advance(by: 30)
        expect((try? Data(contentsOf: settingsURL)) == mixed, "so does the next")
        clockA.advance(by: 30)
        clockA.advance(by: 30)
        expect(whole(), "a mix that stays put is written over with a whole bundle")
        expect(manifest()?.deviceID == "studio" && !syncA.awaitingDownload && syncA.error == nil, "by the Mac whose manifest it was, which syncs again")
        expect(a.settings.httpsOnly == httpsOnly, "the mixed-in file was never applied")
        clockB.advance(by: 90)
        expect(b.document.items.contains { $0.id == tab.id }, "the tab opened during the mix reaches the other Mac")

        // The writer is gone (asleep, Cra quit): the other Mac puts the mix right itself, later.
        syncA.disable()
        mixIn(httpsOnly: !b.settings.httpsOnly)
        let before = clockB.now
        let tabB = b.createTab(url: "https://example.com/opened-on-the-other-mac")
        while !whole() && clockB.now.timeIntervalSince(before) < 600 { clockB.advance(by: 30) }
        let waited = clockB.now.timeIntervalSince(before)
        expect(whole() && manifest()?.deviceID == "macbook" && waited > 90,
               "the other Mac writes its bundle too, after giving the writer time (\(waited) s)")
        expect(manifest()?.files[SettingsSync.sidebarName] != nil
               && (try? decoder.decode(SidebarDocument.self, from: Data(contentsOf: bundle.appendingPathComponent(SettingsSync.sidebarName))))?
                .items.contains { $0.id == tabB.id } == true, "with its own changes in it")

        // A newer Cra's bundle, which this Cra can't read, is never written over.
        let unreadable = Data(#"{"newTabsAtTop": {"a later Cra's": "shape"}}"#.utf8)
        try? unreadable.write(to: settingsURL)
        if var m = manifest() {
            m.files[SettingsSync.settingsName] = SHA256.hash(data: unreadable).map { String(format: "%02x", $0) }.joined()
            m.device = "Mini"; m.deviceID = "mini"
            try? encoder.encode(m).write(to: manifestURL)
        }
        _ = b.createTab(url: "https://example.com/opened-after-the-update")
        for _ in 0..<10 { clockB.advance(by: 30) }
        expect((try? Data(contentsOf: settingsURL)) == unreadable && manifest()?.deviceID == "mini",
               "a whole bundle this Cra can't read is left for the newer Cra")
        expect(syncB.error != nil, "and Settings says why this Mac stopped syncing")
        syncB.disable()
    }

    /// A sync folder in a temporary directory, and what its bundle holds, for the tests below.
    private struct SyncFolder {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-\(UUID().uuidString)", isDirectory: true)
        var bundle: URL { root.appendingPathComponent(SettingsSync.folderName, isDirectory: true) }
        func url(_ name: String) -> URL { bundle.appendingPathComponent(name) }
        func data(_ name: String) -> Data? { try? Data(contentsOf: url(name)) }
        var manifest: SyncManifest? {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return data(SettingsSync.manifestName).flatMap { try? decoder.decode(SyncManifest.self, from: $0) }
        }
        /// The files are the ones the manifest names: a whole bundle.
        var whole: Bool {
            guard let m = manifest else { return false }
            let hashes = Dictionary(uniqueKeysWithValues: SettingsSync.fileNames.compactMap { name in
                data(name).map { (name, SHA256.hash(data: $0).map { String(format: "%02x", $0) }.joined()) }
            })
            return SettingsSync.isComplete(m, hashes: hashes)
        }
        func sidebarHas(_ id: UUID) -> Bool {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return data(SettingsSync.sidebarName).flatMap { try? decoder.decode(SidebarDocument.self, from: $0) }?
                .items.contains { $0.id == id } == true
        }
    }

    // promise: #378
    /// A file the manifest names that is gone from the folder, with no iCloud placeholder for it
    /// (deleted, or left out by a provider), never arrives. The Mac that wrote the manifest writes
    /// its bundle again after a minute; another Mac waits ten, since a provider that only shows a
    /// file once it has downloaded may still be delivering it. ebce13c1 waited on it for ever.
    @MainActor
    private static func syncPutsAFileThatNeverArrivesRight() {
        let folder = SyncFolder()
        try? FileManager.default.createDirectory(at: folder.root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.root) }
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = SidebarStore(clock: clockA), b = SidebarStore(clock: clockB)
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder.root) == .synced, "the first Mac syncs through a folder")
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncB.enable(folder: folder.root) else { return expect(false, "the second Mac is asked once") }
        syncB.useRemote()

        try? FileManager.default.removeItem(at: folder.url(SettingsSync.settingsName))
        let tab = a.createTab(url: "https://example.com/opened-with-a-file-gone")
        syncA.poll()
        expect(!folder.whole && syncA.awaitingDownload, "the first look waits: the file may be on its way")
        for _ in 0..<3 { clockA.advance(by: 30) }
        expect(folder.whole && folder.manifest?.deviceID == "studio" && !syncA.awaitingDownload,
               "the Mac whose manifest names it writes its whole bundle again")
        clockB.advance(by: 90)
        expect(b.document.items.contains { $0.id == tab.id }, "and the other Mac receives it")

        // The writer is away: the other Mac puts it right itself, after waiting longer than for a mix.
        syncA.disable()
        try? FileManager.default.removeItem(at: folder.url(SettingsSync.sidebarName))
        let before = clockB.now
        let tabB = b.createTab(url: "https://example.com/opened-on-the-other-mac")
        while !folder.whole && clockB.now.timeIntervalSince(before) < 1200 { clockB.advance(by: 30) }
        let waited = clockB.now.timeIntervalSince(before)
        expect(folder.whole && folder.manifest?.deviceID == "macbook" && waited >= 600,
               "the other Mac writes its bundle after ten minutes (\(waited) s)")
        expect(folder.sidebarHas(tabB.id), "with its own changes in it")
        syncB.disable()
    }

    // promise: #378
    /// A Mac that turns sync on against another Mac's mix has not been asked yet which sidebar to
    /// keep, so it never writes over the mix: written over, its bundle would replace the other
    /// Mac's sidebar with no question. It waits for the writer, then asks as usual.
    @MainActor
    private static func syncLeavesAMixToItsWriterOnANewMac() {
        let folder = SyncFolder()
        try? FileManager.default.createDirectory(at: folder.root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder.root) }
        let clockA = ManualScheduler(), clockC = ManualScheduler(now: clockA.now)
        let a = SidebarStore(clock: clockA), c = SidebarStore(clock: clockC)
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder.root) == .synced, "the first Mac syncs through a folder")

        // A mix the first Mac has not seen yet (asleep): a valid settings.json from another write.
        var other = AppSettings()
        other.httpsOnly = !a.settings.httpsOnly
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(other).write(to: folder.url(SettingsSync.settingsName))
        let mixed = folder.data(SettingsSync.settingsName)

        let syncC = SettingsSyncService(store: c, clock: clockC, device: "Mini", deviceID: "mini")
        expect(syncC.enable(folder: folder.root) == .downloading, "the new Mac waits on the mix")
        for _ in 0..<40 { clockC.advance(by: 30) }
        expect(folder.manifest?.deviceID == "studio" && folder.data(SettingsSync.settingsName) == mixed && syncC.pendingChoice == nil,
               "twenty minutes on, the new Mac has still not written over the first Mac's bundle")

        for _ in 0..<3 { clockA.advance(by: 30) }
        expect(folder.whole && folder.manifest?.deviceID == "studio", "the first Mac puts it right when it is back")
        clockC.advance(by: 30)
        expect(syncC.pendingChoice?.device == "Studio", "and the new Mac asks which sidebar to keep, as when sync is turned on")
        syncC.useLocal()
        syncA.disable(); syncC.disable()
    }

    // MARK: Easels in the sync bundle

    /// Two Macs syncing through one folder, each with its own easel folder: the services in this
    /// process share one data folder, so each gets its own `easels:`.
    @MainActor
    private final class EaselMacs {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-easels-\(UUID().uuidString)", isDirectory: true)
        let root: URL, bundle: URL, easelsA: URL, easelsB: URL
        let clockA = ManualScheduler(), clockB: ManualScheduler
        let a: SidebarStore, b: SidebarStore
        let syncA: SettingsSyncService, syncB: SettingsSyncService

        /// Both Macs synced: the first turns sync on with `easels` saved, the second uses its sidebar.
        /// `olderSecond`: the second took that bundle on a Cra without easel sync, then updated.
        init(_ easels: [(Easel, [String: Data])] = [], olderSecond: Bool = false) {
            root = dir.appendingPathComponent("sync", isDirectory: true)
            bundle = root.appendingPathComponent(SettingsSync.folderName, isDirectory: true)
            easelsA = dir.appendingPathComponent("a/Easels", isDirectory: true)
            easelsB = dir.appendingPathComponent("b/Easels", isDirectory: true)
            clockB = ManualScheduler(now: clockA.now)
            a = SidebarStore(clock: clockA)
            b = SidebarStore(clock: clockB)
            try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for (easel, pictures) in easels { StoreTests.saveEasel(easel, pictures: pictures, in: easelsA) }
            syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio", easels: easelsA)
            syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook", easels: easelsB)
            syncA.runPictures = StoreTests.picturesInPlace
            syncB.runPictures = StoreTests.picturesInPlace
            StoreTests.expect(syncA.enable(folder: root) == .synced, "the first Mac syncs through a folder")
            let written = manifest
            if olderSecond, var unknown = written {
                unknown.easels = nil
                write(unknown)
            }
            guard case .bundleFound = syncB.enable(folder: root) else { StoreTests.expect(false, "the second Mac is asked once"); return }
            syncB.useRemote()
            if olderSecond, let written { write(written) }
        }

        var manifest: SyncManifest? {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            return (try? Data(contentsOf: bundle.appendingPathComponent(SettingsSync.manifestName))).flatMap { try? decoder.decode(SyncManifest.self, from: $0) }
        }

        func write(_ manifest: SyncManifest) {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try? encoder.encode(manifest).write(to: bundle.appendingPathComponent(SettingsSync.manifestName))
        }

        /// A change on the first Mac, then a look on each.
        func syncAToB() {
            clockA.advance(by: 10); syncA.poll()
            clockB.advance(by: 10); syncB.poll()
        }

        func done() {
            syncA.disable(); syncB.disable()
            try? FileManager.default.removeItem(at: dir)
        }
    }

    /// Runs a picture task where it is handed over: a look is done when `poll()` returns.
    @MainActor
    private static func picturesInPlace(_ work: SettingsSyncService.PictureWork,
                                        _ done: @escaping @MainActor @Sendable (SettingsSyncService.PictureWork.Result) -> Void) {
        done(work.run())
    }

    /// What Export… or Import… answers when its picture tasks run in place; nil when it hasn't answered.
    @MainActor
    private static func answer(_ start: (@escaping @MainActor (String?) -> Void) -> Void) -> String?? {
        var said: String?? = nil
        start { said = .some($0) }
        return said
    }

    /// Picture tasks handed over and not run yet: a test runs them when it chooses, as the thread they go to would.
    @MainActor
    private final class HeldPictures {
        var tasks: [() -> Void] = []

        func hold(_ sync: SettingsSyncService) {
            sync.runPictures = { [unowned self] work, done in tasks.append { done(work.run()) } }
        }

        func runAll() {
            let run = tasks
            tasks = []
            for task in run { task() }
        }
    }

    /// Saves an easel the way the canvas does: its JSON, and its pictures in the folder of its id.
    private static func saveEasel(_ easel: Easel, pictures: [String: Data] = [:], in folder: URL) {
        let pictureFolder = folder.appendingPathComponent(easel.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: pictureFolder, withIntermediateDirectories: true)
        for (name, data) in pictures { try? data.write(to: pictureFolder.appendingPathComponent(name)) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(easel).write(to: folder.appendingPathComponent(easel.id.uuidString + ".json"), options: .atomic)
    }

    private static func loadEasel(_ id: UUID, in folder: URL) -> Easel? {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: folder.appendingPathComponent(id.uuidString + ".json"))).flatMap { try? decoder.decode(Easel.self, from: $0) }
    }

    /// An easel with one picture card, and that picture's bytes by name.
    private static func pictured(_ title: String) -> (Easel, [String: Data]) {
        let name = UUID().uuidString + ".png"
        let card = Easel.Item(kind: .image(file: name), frame: .init(x: 120, y: 160, width: 200, height: 100))
        return (Easel(title: title, items: [card]), [name: Data("the picture \(name)".utf8)])
    }

    @MainActor
    private static func syncEasels() {
        syncCarriesAnEaselAndItsPicture()
        syncMergesEaselEditsFromBothMacs()
        syncDeletesAnEaselDeletedOnTheOtherMac()
        syncPrunesADeletedEaselFromTheBundle()
        syncLeavesEaselsAloneForAnOlderCrasBundle()
        syncHoldsABundleWhileAnEaselArrives()
        importNeverDeletesAnEasel()
        syncNeverTouchesABadEaselPath()
        syncWritesSoonAfterAnEaselChange()
        syncLooksWithoutReadingAnIdleEasel()
        syncChangesAnOpenEaselOnItsCanvas()
        syncKeepsTheEaselsOfTheMacThatUpdatedFirst()
        syncTakesTheRealEaselOverABlankCopy()
        importKeepsARealEaselOverABlankCopy()
        syncPutsBackAnEaselFileGoneFromTheFolder()
        syncNeverSendsAnUnreadableEaselAsDeleted()
        syncSaysWhenAnEaselCannotBeSaved()
        syncKeepsTheEaselsOfTheMacThatUpdatedFirstAfterTheOtherWroteOnAnOlderCra()
        syncNeverSendsAnUnreadableEaselAsDeletedAfterARelaunch()
        syncHoldsItsBundleWhileAnUnreadableEaselHasNoCopyToSend()
        useThatSidebarThatFailsAsksAgainOnlyForANewBundle()
        syncNeverFollowsALinkedEaselsFolder()
        syncWritesNoPictureThroughALinkedEaselFolder()
        syncNeverCopiesInALinkedPicture()
        syncNeverSendsAnEaselFolderItCannotListAsEmpty()
        syncSaysWhenItCannotListTheEaselFolder()
        syncWritesWithNoEaselFolder()
        syncClosesAnOpenEaselDeletedThereAfterAFailedTry()
        syncCopiesAPictureTheOtherMacGotBack()
        syncRewritesADamagedPictureInTheFolder()
        syncTakesNoBundleWhileItCannotListTheEaselFolder()
        syncStartsNoPictureTaskAgainForAPictureItCannotRead()
        flushWritesASaveThatWaitsOutItsDelay()
        easelFolderWatcherReportsASave()
        syncTakesAnEaselRewrittenBetweenItsLookAndItsApplyAtTheNextLook()
        syncWritesNoEaselBeforeItsPicturesAreInTheFolder()
        syncAppliesNothingBeforeThePicturesItLacksAreCopied()
        syncStartsNoSecondPictureTaskWhileOneRuns()
        syncAppliesNothingWhenAPictureCopyFails()
        syncLooksWithoutReadingAPictureOnTheMainThread()
        syncTakesABundleWrittenWhileItsPicturesCopy()
        syncWritesNoPictureThroughAFolderLinkedWhileTheTaskWaits()
        syncSendsAPictureOnceItCanBeReadAgain()
        exportCopiesItsPicturesOffTheMainThread()
        importCopiesThePicturesItLacksOffTheMainThread()
        settingsTurnsExportBackOnOnceItAnswers()
        exportKeepsThePicturesOfAnEaselDeletedWhileItCopies()
        exportKeepsAnEaselDeletedBeforeItsPictureCopied()
        exportKeepsTheFileOfAnEaselRowDeletedWhileItCopies()
        bundleWriteFollowsNoLinkSwappedInOnceItMayWrite()
        bundleDirectoryWritesThroughNoLinkAtAnyLevel()
        exportNamesAPictureItCouldNotWrite()
        syncSendsAPictureOnceTheBundleTakesItAgain()
        syncWritesThroughACraLinkTheUserMade()
        syncWritesThroughACraLinkSetUpOnAnOlderCra()
        syncPrunesATempFileAWriteLeftBehind()
        syncReadsNoPictureThroughALinkSwappedInWhileTheTaskWaits()
        syncReadsNoFIFOSwappedInWhileTheTaskWaits()
        syncReadsNoFIFONamedAsAnEaselFile()
        bundleReadWaitsOnNoFIFOSwappedInAfterItsCheck()
        bundleReadFollowsNoLinkSwappedInAfterItsCheck()
        exportWritesTheSidebarOfTheEaselsItListed()
        useThatSidebarHashesAPictureOffTheMainThread()
        importNamesAPictureGoneBeforeItApplies()
    }

    // MARK: Picture work off the main thread (#4)

    /// The other Mac writes its easels before its manifest, so a look can find a whole bundle and the apply a moment later
    /// an easel file the next manifest names (seen with two copies of Cra on one folder, PR #894 review). That is the
    /// bundle still being written: no fault and no "could not be saved" in Settings, and the next look applies it.
    @MainActor
    private static func syncTakesAnEaselRewrittenBetweenItsLookAndItsApplyAtTheNextLook() {
        let macs = EaselMacs()
        defer { macs.done() }
        let id = UUID()
        saveEasel(Easel(id: id, title: "First"), in: macs.easelsA)
        macs.syncAToB()
        expect(loadEasel(id, in: macs.easelsB)?.title == "First", "the second Mac has the easel")
        // The first Mac writes a second bundle; the second Mac looks at it, and before it applies it the first Mac
        // writes its third, easel file first.
        saveEasel(Easel(id: id, title: "Second"), in: macs.easelsA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        macs.syncB.lookedAtBundle = {
            saveEasel(Easel(id: id, title: "Third"), in: macs.easelsA)
            macs.clockA.advance(by: 10); macs.syncA.poll()
        }
        macs.clockB.advance(by: 10); macs.syncB.poll()
        macs.syncB.lookedAtBundle = {}
        expect(macs.syncB.error == nil, "a bundle still being written is no error in Settings: \(macs.syncB.error ?? "")")
        // The next look finds the third bundle whole and applies it.
        macs.clockB.advance(by: 10); macs.syncB.poll()
        expect(loadEasel(id, in: macs.easelsB)?.title == "Third", "the next look applies the easel")
        expect(macs.syncB.error == nil, "and Settings shows no error")
    }

    /// A write copies its pictures on a picture task: the easels, the files and the manifest wait for it.
    @MainActor
    private static func syncWritesNoEaselBeforeItsPicturesAreInTheFolder() {
        let macs = EaselMacs()
        defer { macs.done() }
        let held = HeldPictures()
        held.hold(macs.syncA)
        let (easel, pictures) = pictured("Its picture copied first")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        expect(!held.tasks.isEmpty && macs.manifest?.easels?["Easels/\(easel.id.uuidString).json"] == nil,
               "the bundle doesn't name the easel while its picture is being copied")
        held.runAll()
        expect(macs.manifest?.easels?["Easels/\(easel.id.uuidString)/\(pictures.keys.first!)"] != nil,
               "once the copy is done, the write names the easel and its picture")
    }

    /// An apply copies the pictures this Mac lacks on a picture task: the easels and the sidebar wait for it.
    @MainActor
    private static func syncAppliesNothingBeforeThePicturesItLacksAreCopied() {
        let macs = EaselMacs()
        defer { macs.done() }
        let (easel, pictures) = pictured("Copied in first")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        let tab = macs.a.createTab(url: "https://example.com/beside-the-easel")
        macs.clockA.advance(by: 10); macs.syncA.poll()
        let held = HeldPictures()
        held.hold(macs.syncB)
        macs.clockB.advance(by: 10); macs.syncB.poll()
        // The look hashes the folder's picture first; the apply then copies it.
        held.runAll()
        expect(!held.tasks.isEmpty && !macs.b.document.items.contains { $0.id == tab.id } && loadEasel(easel.id, in: macs.easelsB) == nil,
               "neither the sidebar nor the easel is applied while the picture is being copied")
        held.runAll()
        expect(macs.b.document.items.contains { $0.id == tab.id } && loadEasel(easel.id, in: macs.easelsB) == easel,
               "once it is here, both are")
    }

    @MainActor
    private static func syncStartsNoSecondPictureTaskWhileOneRuns() {
        let macs = EaselMacs()
        defer { macs.done() }
        let (easel, pictures) = pictured("Being copied")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        let held = HeldPictures()
        held.hold(macs.syncA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        macs.syncA.poll()
        macs.clockA.advance(by: 30)
        expect(held.tasks.count == 1, "a look while a picture task runs waits for it (\(held.tasks.count) tasks)")
    }

    /// A picture copy that fails leaves the sidebar and the easels as they were, and Settings says why.
    @MainActor
    private static func syncAppliesNothingWhenAPictureCopyFails() {
        let macs = EaselMacs()
        defer { macs.done() }
        let (easel, pictures) = pictured("Its copy fails")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        let tab = macs.a.createTab(url: "https://example.com/beside-a-failed-copy")
        macs.clockA.advance(by: 10); macs.syncA.poll()
        let held = HeldPictures()
        held.hold(macs.syncB)
        macs.clockB.advance(by: 10); macs.syncB.poll()
        held.runAll()
        // Between the look and the copy, the folder's picture changes.
        try? Data("other bytes".utf8).write(to: macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString)/\(pictures.keys.first!)"))
        held.runAll()
        expect(!macs.b.document.items.contains { $0.id == tab.id } && loadEasel(easel.id, in: macs.easelsB) == nil && macs.syncB.error != nil,
               "nothing else is applied, and Settings says the easels couldn't be saved")
    }

    /// A look hashes a picture it hasn't seen on a picture task, not on the main thread.
    @MainActor
    private static func syncLooksWithoutReadingAPictureOnTheMainThread() {
        let macs = EaselMacs()
        defer { macs.done() }
        let (easel, pictures) = pictured("Hashed off the main thread")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        let held = HeldPictures()
        held.hold(macs.syncB)
        let reads = macs.syncB.easelReads
        macs.clockB.advance(by: 10); macs.syncB.poll()
        expect(held.tasks.count == 1 && macs.syncB.easelReads == reads + 1,
               "the look reads only the easel's JSON, and hands the picture to a task (\(macs.syncB.easelReads - reads) reads)")
    }

    /// Another Mac wrote while this one copied its pictures, and the write that followed went over that bundle unseen.
    @MainActor
    private static func syncTakesABundleWrittenWhileItsPicturesCopy() {
        let macs = EaselMacs()
        defer { macs.done() }
        let held = HeldPictures()
        held.hold(macs.syncA)
        let (easel, pictures) = pictured("Copied while the other Mac writes")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        let tab = macs.b.createTab(url: "https://example.com/written-meanwhile")
        macs.clockB.advance(by: 10); macs.syncB.poll()
        held.runAll()
        expect(macs.a.document.items.contains { $0.id == tab.id }, "once its pictures are copied, the first Mac takes the bundle written meanwhile")
    }

    /// A peer put a link in place of an easel's picture folder while the picture task waited: the copy went through it.
    @MainActor
    private static func syncWritesNoPictureThroughAFolderLinkedWhileTheTaskWaits() {
        let macs = EaselMacs()
        defer { macs.done() }
        let outside = outsideFolder(in: macs)
        let held = HeldPictures()
        held.hold(macs.syncA)
        let (easel, pictures) = pictured("Relinked while its copy waits")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        let pictureFolder = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString)")
        try? FileManager.default.createDirectory(at: pictureFolder.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(at: pictureFolder, withDestinationURL: outside)
        held.runAll()
        let left = (try? FileManager.default.subpathsOfDirectory(atPath: outside.path))?.sorted()
        expect(left == ["keep.txt", "sub", "sub/x.txt"], "the folder the link points at gets no picture (\(left ?? []))")
    }

    /// A picture this Mac couldn't read stayed out of the bundle once its permissions were fixed, which change
    /// neither its size nor its date.
    @MainActor
    private static func syncSendsAPictureOnceItCanBeReadAgain() {
        let macs = EaselMacs()
        let (easel, pictures) = pictured("Readable again")
        let name = pictures.keys.first!
        let picture = macs.easelsA.appendingPathComponent("\(easel.id.uuidString)/\(name)")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: picture.path)
            macs.done()
        }
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: picture.path)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: picture.path)
        macs.clockA.advance(by: 30)
        expect(macs.manifest?.easels?["\(SettingsSync.easelsName)/\(easel.id.uuidString)/\(name)"] != nil,
               "the next look sends the picture it can read again")
    }

    /// Export… read, hashed and copied its pictures on the main thread, and Settings hung until they were done.
    @MainActor
    private static func exportCopiesItsPicturesOffTheMainThread() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-export-off-main-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let easels = dir.appendingPathComponent("Easels", isDirectory: true)
        let (easel, pictures) = pictured("Exported off the main thread")
        saveEasel(easel, pictures: pictures, in: easels)
        let clock = ManualScheduler()
        let sync = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "Studio", deviceID: "studio", easels: easels)
        let held = HeldPictures()
        held.hold(sync)
        sync.export(to: dir.appendingPathComponent("export", isDirectory: true)) { _ in }
        expect(held.tasks.count == 1, "Export… hands its picture copy to a task (\(held.tasks.count) tasks)")
    }

    /// What Export… leaves in its folder when the user deletes an easel, which has a row, while its picture copy waits;
    /// `exportedBefore`: the folder holds its pictures from an earlier Export…, and a second easel's picture is copied.
    @MainActor
    private static func exportAfterDeletingAnEaselWhileItsCopyWaits(exportedBefore: Bool)
        -> (easel: Easel, manifest: SyncManifest?, sidebar: String?, folder: URL, dir: URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-export-deleted-\(UUID().uuidString)", isDirectory: true)
        let easels = dir.appendingPathComponent("Easels", isDirectory: true), exported = dir.appendingPathComponent("export", isDirectory: true)
        let (easel, pictures) = pictured("Deleted while Export… copies")
        saveEasel(easel, pictures: pictures, in: easels)
        let clock = ManualScheduler()
        let store = SidebarStore(clock: clock)
        _ = store.createTab(url: easel.url)
        let sync = SettingsSyncService(store: store, clock: clock, device: "Studio", deviceID: "studio", easels: easels)
        if exportedBefore {
            sync.runPictures = picturesInPlace
            expect(answer { sync.export(to: exported, done: $0) } == .some(nil), "the first Export… writes the easel and its picture")
            let (other, otherPictures) = pictured("Copied by the second Export…")
            saveEasel(other, pictures: otherPictures, in: easels)
        }
        let held = HeldPictures()
        held.hold(sync)
        var said: String?? = nil
        sync.export(to: exported) { said = .some($0) }
        EaselFolder.remove(easel.id, in: easels)
        held.runAll()
        expect(said == .some(nil), "Export… answers that it exported (\(String(describing: said)))")
        let folder = exported.appendingPathComponent(SettingsSync.folderName, isDirectory: true)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let manifest = (try? Data(contentsOf: folder.appendingPathComponent(SettingsSync.manifestName)))
            .flatMap { try? decoder.decode(SyncManifest.self, from: $0) }
        let sidebar = (try? Data(contentsOf: folder.appendingPathComponent(SettingsSync.sidebarName))).map { String(decoding: $0, as: UTF8.self) }
        return (easel, manifest, sidebar, folder, dir)
    }

    /// Whether the export names the easel's JSON, and holds every file its manifest names.
    private static func exportHoldsTheEaselAndWhatItNames(_ easel: Easel, _ manifest: SyncManifest?, in folder: URL) -> Bool {
        guard let named = manifest?.easels else { return false }
        let held = named.keys.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
        return held && named["\(SettingsSync.easelsName)/\(easel.id.uuidString).json"] != nil
    }

    /// An easel deleted while Export… copied another's picture kept its JSON in the export and lost the pictures an
    /// earlier Export… had put there (Greptile, PR #894).
    @MainActor
    private static func exportKeepsThePicturesOfAnEaselDeletedWhileItCopies() {
        let (easel, manifest, _, folder, dir) = exportAfterDeletingAnEaselWhileItsCopyWaits(exportedBefore: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        expect(exportHoldsTheEaselAndWhatItNames(easel, manifest, in: folder),
               "the export holds the deleted easel and every picture it names (\(manifest?.easels?.keys.sorted() ?? []))")
    }

    /// An easel deleted while Export… waited to copy its picture went into the export naming a picture it didn't hold.
    @MainActor
    private static func exportKeepsAnEaselDeletedBeforeItsPictureCopied() {
        let (easel, manifest, _, folder, dir) = exportAfterDeletingAnEaselWhileItsCopyWaits(exportedBefore: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        expect(exportHoldsTheEaselAndWhatItNames(easel, manifest, in: folder),
               "the export holds the deleted easel and every picture it names (\(manifest?.easels?.keys.sorted() ?? []))")
    }

    /// An easel deleted while Export… copied left its row in the exported sidebar without its file: Import of that export
    /// opened the row as a blank easel.
    @MainActor
    private static func exportKeepsTheFileOfAnEaselRowDeletedWhileItCopies() {
        let (easel, manifest, sidebar, _, dir) = exportAfterDeletingAnEaselWhileItsCopyWaits(exportedBefore: false)
        defer { try? FileManager.default.removeItem(at: dir) }
        let row = sidebar?.contains(easel.id.uuidString) == true
        let file = manifest?.easels?["\(SettingsSync.easelsName)/\(easel.id.uuidString).json"] != nil
        expect(row == file, "the export holds the deleted easel's row with its file, or neither (row: \(row), file: \(file))")
    }

    /// A peer swapped an easel's picture folder in the bundle for a link once the coordinator let the write go, after
    /// any check: the write followed the link out of the bundle.
    @MainActor
    private static func bundleWriteFollowsNoLinkSwappedInOnceItMayWrite() {
        let macs = EaselMacs()
        defer { macs.done() }
        let outside = outsideFolder(in: macs)
        let id = UUID().uuidString
        let pictureFolder = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: pictureFolder, withIntermediateDirectories: true)
        try? SettingsSyncService.coordinatedWrite(Data("a picture".utf8), to: "\(SettingsSync.easelsName)/\(id)/p.png", in: macs.bundle) {
            try? FileManager.default.removeItem(at: pictureFolder)
            try? FileManager.default.createSymbolicLink(at: pictureFolder, withDestinationURL: outside)
        }
        let left = (try? FileManager.default.subpathsOfDirectory(atPath: outside.path))?.sorted()
        expect(left == ["keep.txt", "sub", "sub/x.txt"], "the folder the link points at gets no picture (\(left ?? []))")
    }

    /// A peer's link in place of `Easels`, an easel's picture folder or the picture: a bundle write puts nothing outside
    /// the bundle, and replaces a linked picture rather than writing through it.
    @MainActor
    private static func bundleDirectoryWritesThroughNoLinkAtAnyLevel() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-bundle-links-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID().uuidString
        for (level, name) in [(1, "Easels"), (2, "the picture folder"), (3, "the picture")] {
            let root = dir.appendingPathComponent("\(level)", isDirectory: true)
            let outside = root.appendingPathComponent("outside", isDirectory: true), keep = outside.appendingPathComponent("keep.txt")
            try? FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try? Data("keep".utf8).write(to: keep)
            let folder = root.appendingPathComponent("sync/\(SettingsSync.folderName)", isDirectory: true)
            let path = "\(SettingsSync.easelsName)/\(id)/p.png"
            let parts = [folder] + (1...3).map { folder.appendingPathComponent(path.split(separator: "/").prefix($0).joined(separator: "/")) }
            try? FileManager.default.createDirectory(at: parts[level].deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.createSymbolicLink(at: parts[level], withDestinationURL: level == 3 ? keep : outside)
            try? BundleDirectory.write(Data("a picture".utf8), to: path, in: folder)
            let left = (try? FileManager.default.contentsOfDirectory(atPath: outside.path))?.sorted()
            let kept = (try? Data(contentsOf: keep)) == Data("keep".utf8)
            let replaced = level < 3 || (try? Data(contentsOf: parts[3])) == Data("a picture".utf8)
            expect(left == ["keep.txt"] && kept && replaced, "a link in place of \(name) takes no write out of the bundle (\(left ?? []))")
        }
    }

    /// A picture Export… couldn't write left its easel out of the export, and Export… said it had exported.
    @MainActor
    private static func exportNamesAPictureItCouldNotWrite() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-export-unwritable-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let easels = dir.appendingPathComponent("Easels", isDirectory: true), exported = dir.appendingPathComponent("export", isDirectory: true)
        let (easel, pictures) = pictured("Its picture can't be exported")
        saveEasel(easel, pictures: pictures, in: easels)
        // A file where the easel's picture folder goes: the picture can't be written.
        let inTheWay = exported.appendingPathComponent("\(SettingsSync.folderName)/\(SettingsSync.easelsName)/\(easel.id.uuidString)")
        try? FileManager.default.createDirectory(at: inTheWay.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("in the way".utf8).write(to: inTheWay)
        let clock = ManualScheduler()
        let sync = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "Studio", deviceID: "studio", easels: easels)
        sync.runPictures = picturesInPlace
        let said = answer { sync.export(to: exported, done: $0) }
        expect(said??.contains(pictures.keys.first!) == true, "Export… names the picture it couldn't write (\(String(describing: said)))")
    }

    /// A picture sync couldn't write into the bundle stayed out of every later bundle, with no error, until a relaunch.
    @MainActor
    private static func syncSendsAPictureOnceTheBundleTakesItAgain() {
        let macs = EaselMacs()
        defer { macs.done() }
        let (easel, pictures) = pictured("Sent once the way is clear")
        let inTheWay = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString)")
        try? FileManager.default.createDirectory(at: inTheWay.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("in the way".utf8).write(to: inTheWay)
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        let said = macs.syncA.error
        try? FileManager.default.removeItem(at: inTheWay)
        macs.clockA.advance(by: 30)
        let sent = macs.manifest?.easels?["\(SettingsSync.easelsName)/\(easel.id.uuidString)/\(pictures.keys.first!)"] != nil
        expect(said != nil && sent, "sync says it couldn't write the picture, and sends it at the next look (\(said ?? "no error"), sent: \(sent))")
    }

    /// Whether sync, set up by `setUp` with the folder `<dir>/Sync` whose `Cra` links to `target`, writes its bundle into `target`.
    @MainActor
    private static func syncWritesIntoTheLinkedFolder(_ target: String, setUp: (SettingsSyncService, _ picked: URL) -> Void) -> Bool {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-linked-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let real = dir.appendingPathComponent(target, isDirectory: true), picked = dir.appendingPathComponent("Sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: picked, withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(at: picked.appendingPathComponent(SettingsSync.folderName), withDestinationURL: real)
        let clock = ManualScheduler()
        let sync = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "Studio", deviceID: "studio",
                                       easels: dir.appendingPathComponent("Easels", isDirectory: true))
        sync.runPictures = picturesInPlace
        defer { sync.disable() }
        setUp(sync, picked)
        return FileManager.default.fileExists(atPath: real.appendingPathComponent(SettingsSync.manifestName).path)
    }

    /// The user picked a folder whose `Cra` links to a folder named otherwise, or picked that link itself: every bundle
    /// write failed, or went to a new `Cra` inside the target.
    @MainActor
    private static func syncWritesThroughACraLinkTheUserMade() {
        let throughFolder = syncWritesIntoTheLinkedFolder("Dropbox/Settings") { sync, picked in _ = sync.enable(folder: picked) }
        let throughLink = syncWritesIntoTheLinkedFolder("Dropbox/Settings") { sync, picked in
            _ = sync.enable(folder: picked.appendingPathComponent(SettingsSync.folderName))
        }
        expect(throughFolder && throughLink, "sync writes into the folder the Cra link points at (picked its folder: \(throughFolder), the link: \(throughLink))")
    }

    /// Sync set up on v0.1.58 with a folder whose `Cra` is a link: after the update, every bundle write failed.
    @MainActor
    private static func syncWritesThroughACraLinkSetUpOnAnOlderCra() {
        let written = syncWritesIntoTheLinkedFolder("Dropbox/\(SettingsSync.folderName)") { sync, picked in
            sync.disable()
            // sync.json as v0.1.58 saved it: the picked folder, links unresolved.
            let json = #"{"devices":[],"location":{"folder":{"_0":"\#(picked.path)"}}}"#
            try? Data(json.utf8).write(to: AppPaths.file("sync.json"))
            let clock = ManualScheduler()
            let relaunched = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "Studio", deviceID: "studio",
                                                 easels: picked.deletingLastPathComponent().appendingPathComponent("Easels", isDirectory: true))
            relaunched.runPictures = picturesInPlace
            relaunched.poll()
            relaunched.disable()
        }
        expect(written, "sync set up on an older Cra writes into the folder its Cra link points at")
    }

    /// Temp files a bundle write left at the bundle's root and in an easel's picture folder, when Cra stopped before
    /// their rename, go at the next write.
    @MainActor
    private static func syncPrunesATempFileAWriteLeftBehind() {
        let (easel, pictures) = pictured("A write stopped beside it")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        let left = [macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString)/.\(pictures.keys.first!).\(UUID().uuidString).tmp"),
                    macs.bundle.appendingPathComponent(".\(SettingsSync.manifestName).\(UUID().uuidString).tmp")]
        for file in left { try? Data("half a file".utf8).write(to: file) }
        _ = macs.a.createTab(url: "https://example.com/a-change-to-write")
        macs.clockA.advance(by: 10); macs.syncA.poll()
        let kept = left.filter { FileManager.default.fileExists(atPath: $0.path) }.map(\.lastPathComponent)
        expect(kept.isEmpty, "the next write removes the temp files left behind (\(kept))")
    }

    /// Settings turns Export… and Import… off while one runs, and back on once it answers.
    @MainActor
    private static func settingsTurnsExportBackOnOnceItAnswers() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-export-answers-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let easels = dir.appendingPathComponent("Easels", isDirectory: true)
        let (easel, pictures) = pictured("Exported while Settings waits")
        saveEasel(easel, pictures: pictures, in: easels)
        let clock = ManualScheduler()
        let sync = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "Studio", deviceID: "studio", easels: easels)
        let held = HeldPictures()
        held.hold(sync)
        var said: String?? = nil
        sync.export(to: dir.appendingPathComponent("export", isDirectory: true)) { said = .some($0) }
        let waiting = sync.transferring && said == nil
        held.runAll()
        expect(waiting && !sync.transferring && said == .some(nil), "Export… stays off until it answers that it exported")
    }

    /// Import… hashed the bundle's pictures and copied the ones this Mac lacks on the main thread.
    @MainActor
    private static func importCopiesThePicturesItLacksOffTheMainThread() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-import-off-main-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let easelsA = dir.appendingPathComponent("a/Easels", isDirectory: true), easelsB = dir.appendingPathComponent("b/Easels", isDirectory: true)
        let exported = dir.appendingPathComponent("export", isDirectory: true)
        let (easel, pictures) = pictured("Imported off the main thread")
        saveEasel(easel, pictures: pictures, in: easelsA)
        let clock = ManualScheduler()
        let syncA = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "Studio", deviceID: "studio", easels: easelsA)
        syncA.runPictures = picturesInPlace
        syncA.export(to: exported) { _ in }
        let syncB = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "MacBook", deviceID: "macbook", easels: easelsB)
        let held = HeldPictures()
        held.hold(syncB)
        syncB.importBundle(from: exported) { _ in }
        expect(held.tasks.count == 1, "Import… hands its picture reads to a task (\(held.tasks.count) tasks)")
    }

    /// How many files the second Mac's picture task reads when `swap` replaces the folder's picture while the task waits.
    @MainActor
    private static func readsAfterSwappingThePicture(_ swap: (_ picture: URL, _ bytes: Data, _ dir: URL) -> Void) -> Int {
        let macs = EaselMacs()
        defer { macs.done() }
        let (easel, pictures) = pictured("Swapped while its task waits")
        let (name, bytes) = pictures.first!
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        let held = HeldPictures()
        held.hold(macs.syncB)
        macs.clockB.advance(by: 10); macs.syncB.poll()
        let reads = macs.syncB.easelReads
        let inFolder = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString)/\(name)")
        try? FileManager.default.removeItem(at: inFolder)
        swap(inFolder, bytes, macs.dir)
        held.runAll()
        return macs.syncB.easelReads - reads
    }

    /// A peer swapped a bundle picture for a link to a file elsewhere while the picture task waited: the task read through it.
    @MainActor
    private static func syncReadsNoPictureThroughALinkSwappedInWhileTheTaskWaits() {
        let reads = readsAfterSwappingThePicture { picture, bytes, dir in
            let elsewhere = dir.appendingPathComponent("elsewhere.png")
            try? bytes.write(to: elsewhere)
            try? FileManager.default.createSymbolicLink(at: picture, withDestinationURL: elsewhere)
        }
        expect(reads == 0, "the task reads nothing through the link (\(reads) reads)")
    }

    /// A FIFO in place of a bundle picture is never read: the read would wait for a writer for ever.
    @MainActor
    private static func syncReadsNoFIFOSwappedInWhileTheTaskWaits() {
        let reads = readsAfterSwappingThePicture { picture, _, _ in _ = mkfifo(picture.path, 0o644) }
        expect(reads == 0, "the task leaves the FIFO alone (\(reads) reads)")
    }

    /// A peer's FIFO named as an easel file in the bundle: opening it on the main thread waited for a writer for ever.
    /// The test holds it open for writing, so a read tried returns and is counted rather than hanging the suite.
    @MainActor
    private static func syncReadsNoFIFONamedAsAnEaselFile() {
        let easel = Easel(title: "Its file turned into a FIFO")
        let macs = EaselMacs([(easel, [:])])
        defer { macs.done() }
        let file = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
        _ = mkfifo(file.path, 0o644)
        let writer = open(file.path, O_RDWR)
        defer { close(writer) }
        let reads = macs.syncB.easelReads
        macs.clockB.advance(by: 30)
        expect(macs.syncB.easelReads == reads, "the look leaves the FIFO alone (\(macs.syncB.easelReads - reads) reads)")
    }

    /// A peer swapped an easel file for a FIFO after its check: the file coordinator opened it before the read and waited
    /// for a writer for ever, on the main thread. A read that waits stops the suite here.
    @MainActor
    private static func bundleReadWaitsOnNoFIFOSwappedInAfterItsCheck() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-bundle-fifo-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let path = "\(SettingsSync.easelsName)/\(UUID().uuidString).json", file = dir.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data("an easel".utf8).write(to: file)
        let read = SettingsSyncService.coordinatedRead(path, in: dir) {
            try? FileManager.default.removeItem(at: file)
            _ = mkfifo(file.path, 0o644)
        }
        expect(read == nil, "the read takes nothing from the FIFO")
    }

    /// A peer swapped an easel's picture folder in the bundle for a link after the read's check: the read took a file
    /// from outside the bundle.
    @MainActor
    private static func bundleReadFollowsNoLinkSwappedInAfterItsCheck() {
        let macs = EaselMacs()
        defer { macs.done() }
        let outside = outsideFolder(in: macs)
        try? Data("outside".utf8).write(to: outside.appendingPathComponent("p.png"))
        let id = UUID().uuidString
        let pictureFolder = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(id)", isDirectory: true)
        try? FileManager.default.createDirectory(at: pictureFolder, withIntermediateDirectories: true)
        try? Data("a picture".utf8).write(to: pictureFolder.appendingPathComponent("p.png"))
        let read = SettingsSyncService.coordinatedRead("\(SettingsSync.easelsName)/\(id)/p.png", in: macs.bundle) {
            try? FileManager.default.removeItem(at: pictureFolder)
            try? FileManager.default.createSymbolicLink(at: pictureFolder, withDestinationURL: outside)
        }
        expect(read == nil, "the read takes nothing through the link (\(read.map { String(decoding: $0, as: UTF8.self) } ?? "nothing"))")
    }

    /// An easel made while Export… copied a picture went into the exported sidebar without its file: Import of that
    /// export opened its row as a blank easel (Greptile, PR #894).
    @MainActor
    private static func exportWritesTheSidebarOfTheEaselsItListed() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-export-snapshot-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let easels = dir.appendingPathComponent("Easels", isDirectory: true), exported = dir.appendingPathComponent("export", isDirectory: true)
        let (easel, pictures) = pictured("Exported while another is made")
        saveEasel(easel, pictures: pictures, in: easels)
        let clock = ManualScheduler()
        let store = SidebarStore(clock: clock)
        let sync = SettingsSyncService(store: store, clock: clock, device: "Studio", deviceID: "studio", easels: easels)
        let held = HeldPictures()
        held.hold(sync)
        var said: String?? = nil
        sync.export(to: exported) { said = .some($0) }
        let made = Easel(title: "Made while Export… copies")
        saveEasel(made, in: easels)
        _ = store.createTab(url: made.url)
        held.runAll()
        let folder = exported.appendingPathComponent(SettingsSync.folderName, isDirectory: true)
        let sidebar = (try? Data(contentsOf: folder.appendingPathComponent(SettingsSync.sidebarName))).map { String(decoding: $0, as: UTF8.self) }
        let inSidebar = sidebar?.contains(made.id.uuidString) == true
        let file = FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(SettingsSync.easelsName)/\(made.id.uuidString).json").path)
        expect(said == .some(nil) && inSidebar == file, "the export holds the new easel's row with its file, or neither (row: \(inSidebar), file: \(file))")
    }

    /// Use That Sidebar hashed a picture that changed since the question on the main thread.
    @MainActor
    private static func useThatSidebarHashesAPictureOffTheMainThread() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-use-remote-off-main-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let easelsA = dir.appendingPathComponent("a/Easels", isDirectory: true), easelsB = dir.appendingPathComponent("b/Easels", isDirectory: true)
        let root = dir.appendingPathComponent("sync", isDirectory: true)
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let (easel, pictures) = pictured("Hashed again after the question")
        saveEasel(easel, pictures: pictures, in: easelsA)
        let syncA = SettingsSyncService(store: SidebarStore(clock: clockA), clock: clockA, device: "Studio", deviceID: "studio", easels: easelsA)
        let syncB = SettingsSyncService(store: SidebarStore(clock: clockB), clock: clockB, device: "MacBook", deviceID: "macbook", easels: easelsB)
        syncA.runPictures = picturesInPlace
        let held = HeldPictures()
        held.hold(syncB)
        defer { syncA.disable(); syncB.disable() }
        expect(syncA.enable(folder: root) == .synced, "the first Mac syncs through a folder")
        _ = syncB.enable(folder: root)
        held.runAll()
        expect(syncB.pendingChoice != nil, "the second Mac is asked once its look hashed the picture")
        // The picture's date moves after the question: its hash is unknown again.
        let inFolder = root.appendingPathComponent("\(SettingsSync.folderName)/\(SettingsSync.easelsName)/\(easel.id.uuidString)/\(pictures.keys.first!)")
        try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_000_000)], ofItemAtPath: inFolder.path)
        let reads = syncB.easelReads
        syncB.useRemote()
        expect(syncB.easelReads == reads && held.tasks.count == 1,
               "Use That Sidebar hands the picture to a task (\(syncB.easelReads - reads) reads, \(held.tasks.count) tasks)")
    }

    /// A picture Import copied went from this Mac before the import applied, and Settings said only "The file doesn't exist."
    @MainActor
    private static func importNamesAPictureGoneBeforeItApplies() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-import-gone-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let easelsA = dir.appendingPathComponent("a/Easels", isDirectory: true), easelsB = dir.appendingPathComponent("b/Easels", isDirectory: true)
        let exported = dir.appendingPathComponent("export", isDirectory: true)
        let (easel, pictures) = pictured("Its picture goes during the import")
        let name = pictures.keys.first!
        saveEasel(easel, pictures: pictures, in: easelsA)
        let clock = ManualScheduler()
        let syncA = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "Studio", deviceID: "studio", easels: easelsA)
        syncA.runPictures = picturesInPlace
        _ = answer { syncA.export(to: exported, done: $0) }
        let syncB = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "MacBook", deviceID: "macbook", easels: easelsB)
        // Each task's copy is gone again by the time its answer reaches the main thread.
        syncB.runPictures = { work, done in
            let result = work.run()
            try? FileManager.default.removeItem(at: easelsB.appendingPathComponent("\(easel.id.uuidString)/\(name)"))
            done(result)
        }
        let said = answer { syncB.importBundle(from: exported, done: $0) }
        expect(said??.contains(name) == true, "Import… names the picture that went (\(String(describing: said)))")
    }

    /// A test that reads a saved file next (a relaunch) flushes the save instead of sleeping past its delay.
    @MainActor
    private static func flushWritesASaveThatWaitsOutItsDelay() {
        let file = JSONStore<[String]>("flush-\(UUID().uuidString).json")
        defer { for url in [file.url, file.url.appendingPathExtension("bak")] { try? FileManager.default.removeItem(at: url) } }
        file.save(["waiting"])
        file.flush()
        expect((try? Data(contentsOf: file.url)).flatMap { try? JSONDecoder().decode([String].self, from: $0) } == ["waiting"],
               "a flushed save is on disk when flush returns")
    }

    /// An easel folder, unlisted since (a later date, as after a relaunch) and no longer listable.
    private static func makeEaselFolderUnlistable(_ folder: URL) {
        let fm = FileManager.default
        try? fm.setAttributes([.modificationDate: Date(timeIntervalSinceReferenceDate: 0)], ofItemAtPath: folder.path)
        try? fm.setAttributes([.posixPermissions: 0o311], ofItemAtPath: folder.path)
    }

    /// The easel folder couldn't be listed after a relaunch, and the bundle went up with no easels: the other
    /// Mac deleted every one.
    @MainActor
    private static func syncNeverSendsAnEaselFolderItCannotListAsEmpty() {
        let (easel, pictures) = pictured("In a folder this Mac can't list")
        let macs = EaselMacs([(easel, pictures)])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macs.easelsA.path)
            macs.done()
        }
        makeEaselFolderUnlistable(macs.easelsA)
        _ = macs.a.createTab(url: "https://example.com/a-change-to-write")
        macs.syncAToB()
        expect(loadEasel(easel.id, in: macs.easelsB) == easel, "the other Mac keeps the easel")
    }

    @MainActor
    private static func syncSaysWhenItCannotListTheEaselFolder() {
        let macs = EaselMacs([pictured("In a folder this Mac can't list")])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macs.easelsA.path)
            macs.done()
        }
        makeEaselFolderUnlistable(macs.easelsA)
        _ = macs.a.createTab(url: "https://example.com/a-change-to-write")
        macs.clockA.advance(by: 10); macs.syncA.poll()
        expect(macs.syncA.error?.contains(SettingsSync.easelsName) == true, "Settings says this Mac can't read its Easels folder")
    }

    /// A bundle applied while this Mac's easel folder couldn't be listed skipped the other Mac's edits, and was
    /// remembered: the next write sent the old copies back as the newer ones.
    @MainActor
    private static func syncTakesNoBundleWhileItCannotListTheEaselFolder() {
        let (easel, pictures) = pictured("Edited while the other folder can't be listed")
        let macs = EaselMacs([(easel, pictures)])
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macs.easelsB.path)
            macs.done()
        }
        var renamed = easel
        renamed.title = "Renamed on the first Mac"
        saveEasel(renamed, in: macs.easelsA)
        makeEaselFolderUnlistable(macs.easelsB)
        macs.syncAToB()
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macs.easelsB.path)
        macs.clockB.advance(by: 30)
        expect(loadEasel(easel.id, in: macs.easelsB)?.title == renamed.title, "once the folder lists again, the second Mac takes the edit")
    }

    /// A picture this Mac hashed that turns unreadable at the same size and date (its permissions changed) started
    /// picture tasks without end, and no look ran meanwhile.
    @MainActor
    private static func syncStartsNoPictureTaskAgainForAPictureItCannotRead() {
        let (easel, pictures) = pictured("Unreadable at the same size and date")
        let macs = EaselMacs([(easel, pictures)])
        let name = pictures.keys.first!
        let picture = macs.easelsA.appendingPathComponent("\(easel.id.uuidString)/\(name)")
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: picture.path)
            macs.done()
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: picture.path)
        try? FileManager.default.removeItem(at: macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString)/\(name)"))
        let held = HeldPictures()
        held.hold(macs.syncA)
        // The writing Mac finds the picture gone from its bundle and writes it again after a minute.
        _ = macs.a.createTab(url: "https://example.com/a-change-to-write")
        for _ in 0..<4 { macs.clockA.advance(by: 30) }
        held.runAll()
        expect(held.tasks.isEmpty, "the task that couldn't read the picture is not handed over again (\(held.tasks.count) waiting)")
    }

    /// No easel made yet, so no folder: that is no easels, and the bundle still goes up.
    @MainActor
    private static func syncWritesWithNoEaselFolder() {
        let macs = EaselMacs()
        defer { macs.done() }
        try? FileManager.default.removeItem(at: macs.easelsA)
        let tab = macs.a.createTab(url: "https://example.com/written-without-an-easel-folder")
        macs.syncAToB()
        expect(macs.b.document.items.contains { $0.id == tab.id }, "the other Mac takes the bundle")
    }

    /// The other Mac deleted an easel open here, and a later easel failed to save: the try that followed
    /// found the easel already gone and never closed its windows.
    @MainActor
    private static func syncClosesAnOpenEaselDeletedThereAfterAFailedTry() {
        let open = Easel(id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, title: "Open here, deleted there")
        let macs = EaselMacs([(open, [:])])
        defer { macs.done() }
        var canvas: Easel? = open
        macs.syncB.changeOpenEasel = { id, change in
            guard id == open.id, let here = canvas else { return false }
            canvas = change(here)
            if canvas == nil { EaselFolder.remove(id, in: macs.easelsB) }
            return true
        }
        var removed: Set<UUID> = []
        macs.syncB.easelsChanged = { removed.formUnion($0) }
        // An easel sorted after it that the second Mac can't save: a folder has its file's name.
        let blocked = Easel(id: UUID(uuidString: "FFFFFFFF-FFFF-4FFF-8FFF-FFFFFFFFFFFF")!, title: "Can't be saved")
        try? FileManager.default.createDirectory(at: macs.easelsB.appendingPathComponent(blocked.id.uuidString + ".json/taken"),
                                                 withIntermediateDirectories: true)
        EaselFolder.remove(open.id, in: macs.easelsA)
        saveEasel(blocked, in: macs.easelsA)
        macs.syncAToB()
        EaselFolder.remove(blocked.id, in: macs.easelsB)
        macs.clockB.advance(by: 10); macs.syncB.poll()
        expect(removed.contains(open.id), "the try after the failed one still closes the deleted easel's windows")
    }

    /// The first Mac lacked a picture, then got it back without its easel changing: the second never copied it.
    @MainActor
    private static func syncCopiesAPictureTheOtherMacGotBack() {
        let (easel, pictures) = pictured("Its picture back")
        let macs = EaselMacs([(easel, [:])])
        defer { macs.done() }
        let (name, bytes) = pictures.first!
        try? bytes.write(to: macs.easelsA.appendingPathComponent("\(easel.id.uuidString)/\(name)"))
        // The same easel saved again, as its canvas does.
        saveEasel(easel, in: macs.easelsA)
        macs.syncAToB()
        expect((try? Data(contentsOf: macs.easelsB.appendingPathComponent("\(easel.id.uuidString)/\(name)"))) == bytes,
               "the second Mac copies the picture the first one got back")
    }

    /// A damaged copy of a picture in the sync folder was kept by every later write, so no Mac could take the bundle.
    @MainActor
    private static func syncRewritesADamagedPictureInTheFolder() {
        let (easel, pictures) = pictured("Its picture damaged in the folder")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        let (name, bytes) = pictures.first!
        let inFolder = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString)/\(name)")
        try? Data("half a pic".utf8).write(to: inFolder)
        // The writing Mac finds its bundle damaged and writes it again after a minute.
        _ = macs.a.createTab(url: "https://example.com/a-change-to-write")
        for _ in 0..<4 { macs.clockA.advance(by: 30) }
        expect((try? Data(contentsOf: inFolder)) == bytes, "the write puts the picture's own bytes back")
    }

    /// Sync carried an easel's sidebar row but not the easel: on the other Mac it opened empty.
    @MainActor
    private static func syncCarriesAnEaselAndItsPicture() {
        let (easel, pictures) = pictured("Moodboard")
        var lacking = Easel(title: "Names a picture this Mac lacks")
        lacking.items = [Easel.Item(kind: .image(file: "gone.png"), frame: .init(x: 0, y: 0, width: 10, height: 10))]
        let macs = EaselMacs([(easel, pictures), (lacking, [:])])
        defer { macs.done() }
        let (name, bytes) = pictures.first!
        expect(loadEasel(easel.id, in: macs.easelsB) == easel, "an easel made on the first Mac is on the second")
        expect((try? Data(contentsOf: macs.easelsB.appendingPathComponent(easel.id.uuidString).appendingPathComponent(name))) == bytes,
               "with the picture its card shows")
        expect(Set(macs.manifest.map { Array($0.files.keys) } ?? []) == Set(SettingsSync.fileNames), "the manifest's files stay the three an older Cra reads")
        expect(macs.manifest?.easels?["Easels/\(lacking.id.uuidString)/gone.png"] == nil && loadEasel(lacking.id, in: macs.easelsB) == lacking,
               "a picture the writing Mac lacks is left out of the manifest, and its easel arrives without waiting for it")
    }

    @MainActor
    private static func syncMergesEaselEditsFromBothMacs() {
        let (easel, pictures) = pictured("Plans")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        // The first Mac renames it and writes; the second adds a card before its next look.
        var onA = easel
        onA.title = "Plans, renamed"
        saveEasel(onA, in: macs.easelsA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        var onB = easel
        onB.items.append(Easel.Item(kind: .rectangle, frame: .init(x: 400, y: 400, width: 50, height: 50)))
        saveEasel(onB, in: macs.easelsB)
        macs.clockB.advance(by: 10); macs.syncB.poll()
        let merged = loadEasel(easel.id, in: macs.easelsB)
        expect(merged?.title == "Plans, renamed" && merged?.items.map(\.id) == onB.items.map(\.id),
               "the second Mac takes the first's title and keeps its own card")
        macs.clockA.advance(by: 10); macs.syncA.poll()
        expect(merged != nil && loadEasel(easel.id, in: macs.easelsA) == merged, "and the first Mac takes the merge")
    }

    @MainActor
    private static func syncDeletesAnEaselDeletedOnTheOtherMac() {
        let (easel, pictures) = pictured("Doomed")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        var removed: Set<UUID> = []
        macs.syncB.easelsChanged = { removed = $0 }
        EaselFolder.remove(easel.id, in: macs.easelsA)
        macs.syncAToB()
        let fm = FileManager.default
        expect(!fm.fileExists(atPath: macs.easelsB.appendingPathComponent(easel.id.uuidString + ".json").path)
               && !fm.fileExists(atPath: macs.easelsB.appendingPathComponent(easel.id.uuidString).path),
               "an easel deleted in Library on the first Mac is gone from the second, pictures and all")
        expect(removed == [easel.id], "and the app hears which easel went, to close its tabs")
    }

    @MainActor
    private static func syncPrunesADeletedEaselFromTheBundle() {
        let (easel, pictures) = pictured("Pruned")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        EaselFolder.remove(easel.id, in: macs.easelsA)
        macs.clockA.advance(by: 10); macs.syncA.poll()
        let easels = macs.bundle.appendingPathComponent(SettingsSync.easelsName)
        expect(!FileManager.default.fileExists(atPath: easels.appendingPathComponent(easel.id.uuidString + ".json").path)
               && !FileManager.default.fileExists(atPath: easels.appendingPathComponent(easel.id.uuidString).path),
               "the next bundle leaves a deleted easel's file and pictures out of the sync folder")
    }

    /// An older Cra writes a manifest without `easels`: its easels are unknown, not deleted.
    @MainActor
    private static func syncLeavesEaselsAloneForAnOlderCrasBundle() {
        let (easel, pictures) = pictured("Kept")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        let file = macs.easelsB.appendingPathComponent(easel.id.uuidString + ".json")
        let before = try? Data(contentsOf: file)
        guard var old = macs.manifest else { return expect(false, "the first Mac wrote a manifest") }
        old.easels = nil
        old.device = "Old"; old.deviceID = "old"; old.id = UUID()
        old.writtenAt = macs.clockB.now.addingTimeInterval(5)
        macs.write(old)
        macs.clockB.advance(by: 10); macs.syncB.poll()
        expect(macs.syncB.otherDevices.contains("Old"), "the older Cra's bundle is applied")
        expect(before != nil && (try? Data(contentsOf: file)) == before, "and leaves this Mac's easels as they were")
        expect(macs.manifest?.easels?["Easels/\(easel.id.uuidString).json"] != nil, "this Mac's next bundle puts its easels back")
    }

    /// A bundle applies whole: a sidebar row `easel://<id>` never arrives before its easel.
    @MainActor
    private static func syncHoldsABundleWhileAnEaselArrives() {
        let macs = EaselMacs()
        defer { macs.done() }
        let (easel, pictures) = pictured("Arriving")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        let tab = macs.a.createTab(url: easel.url, title: easel.title)
        let picture = pictures.keys.first!
        macs.syncB.downloadStatus = { $0.lastPathComponent == picture ? .notDownloaded : nil }
        macs.syncAToB()
        expect(!macs.b.document.items.contains { $0.id == tab.id } && loadEasel(easel.id, in: macs.easelsB) == nil,
               "while a picture is still downloading, neither the easel nor the sidebar is applied")
        macs.syncB.downloadStatus = { _ in nil }
        macs.clockB.advance(by: 10); macs.syncB.poll()
        expect(macs.b.document.items.contains { $0.id == tab.id } && loadEasel(easel.id, in: macs.easelsB) == easel,
               "once it has arrived, both are")
    }

    /// Import… adds and overwrites easels, and removes none: the export may come from a Mac that never had them.
    @MainActor
    private static func importNeverDeletesAnEasel() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-import-easels-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let easelsA = dir.appendingPathComponent("a/Easels", isDirectory: true), easelsB = dir.appendingPathComponent("b/Easels", isDirectory: true)
        let exported = dir.appendingPathComponent("export", isDirectory: true)
        let clock = ManualScheduler()
        let (easel, pictures) = pictured("Exported")
        saveEasel(easel, pictures: pictures, in: easelsA)
        let syncA = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "Studio", deviceID: "studio", easels: easelsA)
        syncA.runPictures = picturesInPlace
        expect(answer { syncA.export(to: exported, done: $0) } == .some(nil), "the first Mac exports")
        let onlyHere = Easel(title: "Only on this Mac")
        saveEasel(onlyHere, in: easelsB)
        var older = easel
        older.title = "An older copy"
        saveEasel(older, in: easelsB)
        let syncB = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "MacBook", deviceID: "macbook", easels: easelsB)
        syncB.runPictures = picturesInPlace
        expect(answer { syncB.importBundle(from: exported, done: $0) } == .some(nil), "the second Mac imports it")
        expect(loadEasel(easel.id, in: easelsB) == easel, "Import… takes the exported easel over this Mac's copy")
        expect(loadEasel(onlyHere.id, in: easelsB) == onlyHere, "and keeps an easel the export lacks")
        let bak = (try? Data(contentsOf: easelsB.appendingPathComponent(easel.id.uuidString + ".json.bak")))
            .flatMap { try? JSONDecoder().decode(Easel.self, from: $0) }
        expect(bak == older, "and keeps the copy it replaced as .bak, as a save does")
    }

    /// The Mac that updated Cra second took the first Mac's bundle on a Cra without easel sync. Its first look
    /// wrote a bundle without them, and the first Mac read that as every easel deleted.
    @MainActor
    private static func syncKeepsTheEaselsOfTheMacThatUpdatedFirst() {
        let (easel, pictures) = pictured("Made on the Mac updated first")
        let macs = EaselMacs([(easel, pictures)], olderSecond: true)
        defer { macs.done() }
        macs.clockB.advance(by: 10); macs.syncB.poll()
        macs.clockA.advance(by: 20); macs.syncA.poll()
        expect(loadEasel(easel.id, in: macs.easelsA) == easel, "the first Mac keeps its easel when the second updates")
    }

    /// An older Cra that opens a synced `easel://` row saves a blank easel under its id. After the update,
    /// the other Mac's real easel replaces it, never the other way round.
    @MainActor
    private static func syncTakesTheRealEaselOverABlankCopy() {
        let (easel, pictures) = pictured("The real one")
        let macs = EaselMacs([(easel, pictures)], olderSecond: true)
        defer { macs.done() }
        saveEasel(Easel(id: easel.id), in: macs.easelsB)
        macs.clockB.advance(by: 10); macs.syncB.poll()
        macs.syncAToB()
        expect(loadEasel(easel.id, in: macs.easelsB) == easel, "the second Mac's blank copy gives way to the real easel")
    }

    /// With no history to merge against (Import, Use That Sidebar, a bundle an older Cra wrote last), a blank
    /// copy of an easel never replaces the real one here.
    @MainActor
    private static func importKeepsARealEaselOverABlankCopy() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-import-blank-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let easelsA = dir.appendingPathComponent("a/Easels", isDirectory: true), easelsB = dir.appendingPathComponent("b/Easels", isDirectory: true)
        let exported = dir.appendingPathComponent("export", isDirectory: true)
        let clock = ManualScheduler()
        let (easel, pictures) = pictured("Real on this Mac")
        saveEasel(Easel(id: easel.id), in: easelsA)
        saveEasel(easel, pictures: pictures, in: easelsB)
        let syncA = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "Studio", deviceID: "studio", easels: easelsA)
        syncA.runPictures = picturesInPlace
        expect(answer { syncA.export(to: exported, done: $0) } == .some(nil), "the first Mac exports its blank copy")
        let syncB = SettingsSyncService(store: SidebarStore(clock: clock), clock: clock, device: "MacBook", deviceID: "macbook", easels: easelsB)
        syncB.runPictures = picturesInPlace
        _ = answer { syncB.importBundle(from: exported, done: $0) }
        expect(loadEasel(easel.id, in: easelsB) == easel, "Import… leaves the real easel in place of the blank copy")
    }

    /// A file the writer's own manifest names goes from the folder after it looked: it writes it again after a minute.
    @MainActor
    private static func syncPutsBackAnEaselFileGoneFromTheFolder() {
        let (easel, pictures) = pictured("Gone from the folder")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        macs.clockA.advance(by: 1); macs.syncA.poll()
        let file = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString).json")
        try? FileManager.default.removeItem(at: file)
        for _ in 0..<4 { macs.clockA.advance(by: 30) }
        expect(FileManager.default.fileExists(atPath: file.path), "the writing Mac puts the easel's file back")
    }

    /// An easel file this Mac can't read at the moment (a save landing mid-read, or bytes it can't decode) is
    /// not left out of the bundle: the other Mac would delete it.
    @MainActor
    private static func syncNeverSendsAnUnreadableEaselAsDeleted() {
        let (easel, pictures) = pictured("Read mid-save")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        try? Data("{ half a save".utf8).write(to: macs.easelsA.appendingPathComponent(easel.id.uuidString + ".json"), options: .atomic)
        _ = macs.a.createTab(url: "https://example.com/a-change-to-write")
        macs.syncAToB()
        expect(loadEasel(easel.id, in: macs.easelsB) == easel, "the other Mac keeps the easel")
    }

    /// The second Mac, still on an older Cra, took the first Mac's bundle and wrote one of its own while the first
    /// slept, then updated. Its bundle names no parent it had easels for, so the first Mac deletes nothing.
    @MainActor
    private static func syncKeepsTheEaselsOfTheMacThatUpdatedFirstAfterTheOtherWroteOnAnOlderCra() {
        let (easel, pictures) = pictured("Made on the Mac updated first")
        let macs = EaselMacs([(easel, pictures)], olderSecond: true)
        defer { macs.done() }
        guard var older = macs.manifest, let first = older.id else { return expect(false, "the first Mac wrote a manifest") }
        older.easels = nil
        older.device = "MacBook"; older.deviceID = "macbook"; older.id = UUID(); older.parentIDs = [first]
        older.writtenAt = older.writtenAt.addingTimeInterval(5)
        macs.write(older)
        macs.clockB.advance(by: 10); macs.syncB.poll()
        macs.clockA.advance(by: 20); macs.syncA.poll()
        expect(loadEasel(easel.id, in: macs.easelsA) == easel, "the first Mac keeps its easel")
    }

    /// An easel file this Mac can't decode at launch still goes up as the copy the folder has, which the
    /// other Mac's base has too: it is never sent as deleted.
    @MainActor
    private static func syncNeverSendsAnUnreadableEaselAsDeletedAfterARelaunch() {
        let (easel, pictures) = pictured("Undecodable after a relaunch")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        let relaunched = relaunchWithAnUnreadableEasel(easel, macs)
        defer { relaunched.disable() }
        macs.clockB.advance(by: 30); macs.syncB.poll()
        expect(loadEasel(easel.id, in: macs.easelsB) == easel, "the other Mac keeps the easel")
    }

    /// No copy to send in its place: the Mac writes nothing and Settings names the file.
    @MainActor
    private static func syncHoldsItsBundleWhileAnUnreadableEaselHasNoCopyToSend() {
        let (easel, pictures) = pictured("Undecodable, and gone from the folder")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        let relaunched = relaunchWithAnUnreadableEasel(easel, macs, keepFolderCopy: false)
        defer { relaunched.disable() }
        macs.clockA.advance(by: 90)
        expect(relaunched.error?.contains(easel.id.uuidString + ".json") == true, "Settings names the easel file it can't read")
        expect(macs.manifest?.deviceID == "studio" && macs.manifest?.easels?["Easels/\(easel.id.uuidString).json"] != nil,
               "and the folder's bundle still names the easel")
    }

    // MARK: Links a peer plants in a shared sync folder

    /// A folder outside the sync folder, with a file and a subfolder in it, that a peer's link points at.
    private static func outsideFolder(in macs: EaselMacs) -> URL {
        let outside = macs.dir.appendingPathComponent("outside", isDirectory: true)
        try? FileManager.default.createDirectory(at: outside.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try? Data("keep".utf8).write(to: outside.appendingPathComponent("keep.txt"))
        try? Data("x".utf8).write(to: outside.appendingPathComponent("sub/x.txt"))
        return outside
    }

    /// A peer replaces the bundle's `Easels` with a link to a folder elsewhere: writes and prune never reach it.
    @MainActor
    private static func syncNeverFollowsALinkedEaselsFolder() {
        let macs = EaselMacs([pictured("Synced")])
        defer { macs.done() }
        let outside = outsideFolder(in: macs)
        let easels = macs.bundle.appendingPathComponent(SettingsSync.easelsName)
        try? FileManager.default.removeItem(at: easels)
        try? FileManager.default.createSymbolicLink(at: easels, withDestinationURL: outside)
        // The folder now lacks what the manifest names: the writing Mac writes its bundle again after a minute.
        _ = macs.a.createTab(url: "https://example.com/a-change-to-write")
        macs.clockA.advance(by: 120)
        let left = (try? FileManager.default.subpathsOfDirectory(atPath: outside.path))?.sorted()
        expect(left == ["keep.txt", "sub", "sub/x.txt"], "the folder the link points at keeps its files and gets none (\(left ?? []))")
    }

    /// A peer replaces an easel's picture folder in the bundle with a link: no picture is written through it.
    @MainActor
    private static func syncWritesNoPictureThroughALinkedEaselFolder() {
        let (easel, pictures) = pictured("Its pictures relinked")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        let outside = outsideFolder(in: macs)
        let pictureFolder = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(easel.id.uuidString)")
        try? FileManager.default.removeItem(at: pictureFolder)
        try? FileManager.default.createSymbolicLink(at: pictureFolder, withDestinationURL: outside)
        // The folder now lacks what the manifest names: the writing Mac writes its bundle again after a minute.
        _ = macs.a.createTab(url: "https://example.com/a-change-to-write")
        macs.clockA.advance(by: 120)
        let left = (try? FileManager.default.subpathsOfDirectory(atPath: outside.path))?.sorted()
        expect(left == ["keep.txt", "sub", "sub/x.txt"], "the folder the link points at gets no picture and loses nothing (\(left ?? []))")
    }

    /// A peer's bundle names a picture that is a link to a file elsewhere on this Mac, with that file's hash:
    /// it is never read through the link and copied in.
    @MainActor
    private static func syncNeverCopiesInALinkedPicture() {
        let macs = EaselMacs()
        defer { macs.done() }
        let secret = macs.dir.appendingPathComponent("secret.txt")
        let secretBytes = Data("a file of this Mac's".utf8)
        try? secretBytes.write(to: secret)
        let hash = { (data: Data) in SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        let name = UUID().uuidString + ".png"
        let planted = Easel(title: "Planted", items: [Easel.Item(kind: .image(file: name), frame: .init(x: 0, y: 0, width: 10, height: 10))])
        let json = (try? JSONEncoder().encode(planted)) ?? Data()
        let folder = macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(planted.id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? json.write(to: macs.bundle.appendingPathComponent("\(SettingsSync.easelsName)/\(planted.id.uuidString).json"))
        try? FileManager.default.createSymbolicLink(at: folder.appendingPathComponent(name), withDestinationURL: secret)
        guard var m = macs.manifest else { return expect(false, "the first Mac wrote a manifest") }
        m.easels?["\(SettingsSync.easelsName)/\(planted.id.uuidString).json"] = hash(json)
        m.easels?["\(SettingsSync.easelsName)/\(planted.id.uuidString)/\(name)"] = hash(secretBytes)
        m.device = "Mini"; m.deviceID = "mini"; m.id = UUID()
        m.writtenAt = macs.clockB.now.addingTimeInterval(5)
        macs.write(m)
        macs.clockB.advance(by: 10); macs.syncB.poll()
        expect(!FileManager.default.fileExists(atPath: macs.easelsB.appendingPathComponent("\(planted.id.uuidString)/\(name)").path),
               "the file the link points at is not copied into this Mac's easels")
    }

    /// Use That Sidebar that fails on an easel says so once: the question comes back only for a new bundle.
    @MainActor
    private static func useThatSidebarThatFailsAsksAgainOnlyForANewBundle() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-choice-\(UUID().uuidString)", isDirectory: true)
        let easelsA = dir.appendingPathComponent("a/Easels", isDirectory: true), easelsB = dir.appendingPathComponent("b/Easels", isDirectory: true)
        let root = dir.appendingPathComponent("sync", isDirectory: true)
        try? FileManager.default.createDirectory(at: easelsB, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: easelsB.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: easelsB.path)
            try? FileManager.default.removeItem(at: dir)
        }
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let (easel, pictures) = pictured("Can't be saved on the second Mac")
        saveEasel(easel, pictures: pictures, in: easelsA)
        let a = SidebarStore(clock: clockA)
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio", easels: easelsA)
        let syncB = SettingsSyncService(store: SidebarStore(clock: clockB), clock: clockB, device: "MacBook", deviceID: "macbook", easels: easelsB)
        syncA.runPictures = picturesInPlace
        syncB.runPictures = picturesInPlace
        defer { syncA.disable(); syncB.disable() }
        expect(syncA.enable(folder: root) == .synced, "the first Mac syncs through a folder")
        guard case .bundleFound = syncB.enable(folder: root) else { return expect(false, "the second Mac is asked once") }
        syncB.useRemote()
        clockB.advance(by: 30)
        expect(syncB.pendingChoice == nil && syncB.error != nil, "a failed Use That Sidebar shows its error and doesn't ask again")
        clockA.advance(by: 10)
        _ = a.createTab(url: "https://example.com/a-later-bundle")
        syncA.poll()
        clockB.advance(by: 30)
        expect(syncB.pendingChoice != nil, "a later bundle from the other Mac asks again")
    }

    /// The first Mac relaunched with `easel`'s file undecodable, after a few writes so each Mac's history and
    /// sync.json are on disk, and one look.
    @MainActor
    private static func relaunchWithAnUnreadableEasel(_ easel: Easel, _ macs: EaselMacs, keepFolderCopy: Bool = true) -> SettingsSyncService {
        _ = macs.a.createTab(url: "https://example.com/one"); macs.syncAToB()
        macs.syncB.flushSaves()
        _ = macs.a.createTab(url: "https://example.com/two"); macs.clockA.advance(by: 10); macs.syncA.poll()
        macs.syncA.flushSaves()
        try? Data("{ not an easel".utf8).write(to: macs.easelsA.appendingPathComponent(easel.id.uuidString + ".json"), options: .atomic)
        if !keepFolderCopy { try? FileManager.default.removeItem(at: macs.bundle.appendingPathComponent("Easels/\(easel.id.uuidString).json")) }
        // Quit: the first Mac's service stops, and its sync.json and history stay as it saved them.
        let saved = ["sync.json", "sync-history.json"].map { (AppPaths.file($0), try? Data(contentsOf: AppPaths.file($0))) }
        macs.syncA.disable()
        for (url, data) in saved { try? data?.write(to: url) }
        let relaunched = SettingsSyncService(store: macs.a, clock: macs.clockA, device: "Studio", deviceID: "studio", easels: macs.easelsA)
        relaunched.runPictures = picturesInPlace
        relaunched.start()
        _ = macs.a.createTab(url: "https://example.com/three")
        macs.clockA.advance(by: 30)
        return relaunched
    }

    /// An easel this Mac can't save leaves the bundle untaken, and Settings says why rather than showing sync as fine.
    @MainActor
    private static func syncSaysWhenAnEaselCannotBeSaved() {
        let macs = EaselMacs()
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: macs.easelsB.path)
            macs.done()
        }
        try? FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: macs.easelsB.path)
        let (easel, pictures) = pictured("Can't be saved")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        macs.syncAToB()
        expect(macs.syncB.error != nil, "sync on the second Mac reports the easel it couldn't save")
        let exported = macs.dir.appendingPathComponent("export", isDirectory: true)
        expect(answer { macs.syncA.export(to: exported, done: $0) } == .some(nil), "the first Mac exports")
        expect(answer { macs.syncB.importBundle(from: exported, done: $0) }??.isEmpty == false, "Import… reports the easels it couldn't save")
    }

    /// A manifest path that names no easel file or picture is never read or written, here or in the folder.
    @MainActor
    private static func syncNeverTouchesABadEaselPath() {
        let macs = EaselMacs([pictured("Safe")])
        defer { macs.done() }
        let planted = Data("not an easel".utf8)
        let target = macs.bundle.appendingPathComponent("escape.json")
        try? planted.write(to: target)
        guard var bad = macs.manifest else { return expect(false, "the first Mac wrote a manifest") }
        bad.easels?["Easels/../escape.json"] = SHA256.hash(data: planted).map { String(format: "%02x", $0) }.joined()
        bad.device = "Mini"; bad.deviceID = "mini"; bad.id = UUID()
        bad.writtenAt = macs.clockB.now.addingTimeInterval(5)
        macs.write(bad)
        let reads = macs.syncB.easelReads
        macs.clockB.advance(by: 10); macs.syncB.poll()
        expect(!macs.syncB.otherDevices.contains("Mini"), "a manifest naming a path outside the easels is not applied")
        expect(macs.syncB.easelReads == reads, "and the path is never read")
        expect(!FileManager.default.fileExists(atPath: macs.easelsB.deletingLastPathComponent().appendingPathComponent("escape.json").path),
               "nothing is written outside this Mac's easel folder")
        for _ in 0..<25 { macs.clockB.advance(by: 30) }
        expect(macs.manifest?.deviceID == "macbook" && macs.manifest?.easels?.keys.allSatisfy { SettingsSync.easelPath($0) != nil } == true,
               "the Mac puts the folder right with a bundle naming easel paths only")
        expect((try? Data(contentsOf: target)) == planted, "and leaves the file the bad path named as it was")
    }

    /// An easel saved here goes up a few seconds later, like a sidebar change: no easel code calls sync. The
    /// watcher on the easel folder reports the save (`easelFolderWatcherReportsASave`).
    @MainActor
    private static func syncWritesSoonAfterAnEaselChange() {
        let macs = EaselMacs()
        defer { macs.done() }
        let (easel, pictures) = pictured("Made after sync was on")
        saveEasel(easel, pictures: pictures, in: macs.easelsA)
        macs.syncA.changedHere()
        macs.clockA.advance(by: SettingsSync.writeSoonDelay)
        expect(macs.manifest?.easels?["Easels/\(easel.id.uuidString).json"] != nil, "an easel saved here goes up 3 s later, before the next look")
    }

    /// The watcher sync puts on the easel folder reports a save in it. It waits on the kernel's event, not on the
    /// app's clock; the bound only ends a run in which the event never comes.
    @MainActor
    private static func easelFolderWatcherReportsASave() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-easel-watch-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let reported = DispatchSemaphore(value: 0)
        let watcher = SettingsSyncService.watch(folder, on: DispatchQueue(label: "easel-watch-test")) { reported.signal() }
        defer { watcher?.cancel() }
        saveEasel(Easel(title: "Saved while watched"), in: folder)
        expect(reported.wait(timeout: .now() + 30) == .success, "a save in the easel folder is reported")
    }

    /// An idle look reads, hashes and decodes no easel or picture, on the Mac that wrote and on the one that applied.
    @MainActor
    private static func syncLooksWithoutReadingAnIdleEasel() {
        let macs = EaselMacs([pictured("One"), pictured("Two")])
        defer { macs.done() }
        macs.syncA.poll(); macs.syncB.poll()
        let (readsA, decodesA) = (macs.syncA.easelReads, macs.syncA.easelDecodes)
        let (readsB, decodesB) = (macs.syncB.easelReads, macs.syncB.easelDecodes)
        for _ in 0..<3 { macs.clockA.advance(by: 30); macs.clockB.advance(by: 30) }
        expect(macs.syncA.easelReads == readsA && macs.syncA.easelDecodes == decodesA,
               "an idle look on the writing Mac reads no easel (\(macs.syncA.easelReads - readsA) reads, \(macs.syncA.easelDecodes - decodesA) decodes)")
        expect(macs.syncB.easelReads == readsB && macs.syncB.easelDecodes == decodesB,
               "nor on the Mac that applied it (\(macs.syncB.easelReads - readsB) reads, \(macs.syncB.easelDecodes - decodesB) decodes)")
    }

    /// An easel open in a tab is up to 0.4 s ahead of its file: the change goes onto its canvas, which saves it.
    @MainActor
    private static func syncChangesAnOpenEaselOnItsCanvas() {
        let (easel, pictures) = pictured("Open in a tab")
        let macs = EaselMacs([(easel, pictures)])
        defer { macs.done() }
        var canvas = easel
        macs.syncB.changeOpenEasel = { id, change in
            guard id == easel.id else { return false }
            if let changed = change(canvas) { canvas = changed }
            return true
        }
        var onA = easel
        onA.title = "Renamed on the other Mac"
        saveEasel(onA, in: macs.easelsA)
        let file = macs.easelsB.appendingPathComponent(easel.id.uuidString + ".json")
        let before = try? Data(contentsOf: file)
        macs.syncAToB()
        expect(canvas.title == "Renamed on the other Mac", "an easel open in a tab takes the change on its canvas")
        expect(before != nil && (try? Data(contentsOf: file)) == before, "and sync writes no file for it: the canvas saves it")
    }

    // promise: #921
    /// The dead tab reported on X (27 Nov 2026): two tabs made into a split on one Mac while the other
    /// Mac looked at them. The merge gave each tab the other Mac's parent, Today, and kept the split with
    /// no panes: a row with only a close button that did nothing, synced to every Mac.
    @MainActor
    private static func syncKeepsASplitMadeWhileTheOtherMacLooked() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clockA = ManualScheduler(), clockB = ManualScheduler(now: clockA.now)
        let a = AppComposition(clock: clockA).store
        let first = a.createTab(url: "https://codepen.io/vscode", title: "VS Code Extension – CodePen")
        let second = a.createTab(url: "https://codepen.io/mcp", title: "MCP – CodePen")
        let syncA = SettingsSyncService(store: a, clock: clockA, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder) == .synced, "split sync: the first Mac writes its bundle")
        let b = SidebarStore(clock: clockB)
        let syncB = SettingsSyncService(store: b, clock: clockB, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound = syncB.enable(folder: folder) else { return expect(false, "split sync: the second Mac finds the bundle") }
        syncB.useRemote()
        expect(b.item(first.id) != nil && b.item(second.id) != nil, "split sync: both Macs have both tabs")

        // The second Mac looks at both tabs and writes; the first, not having looked yet, splits them.
        clockB.advance(by: 10)
        b.selectTab(first.id)
        b.selectTab(second.id)
        syncB.poll()
        clockA.advance(by: 20)
        guard let split = a.createSplit(with: [first.id, second.id]) else { return expect(false, "split sync: the split is made") }
        syncA.poll()
        syncB.poll()
        for (mac, store) in [("first", a), ("second", b)] {
            expect(store.item(split.id)?.children == [first.id, second.id],
                   "split sync: the split keeps both its panes on the \(mac) Mac, got \(store.item(split.id)?.children.count ?? -1)")
            expect(store.item(first.id)?.parentID == split.id && store.item(second.id)?.parentID == split.id,
                   "split sync: both tabs are in the split on the \(mac) Mac")
            expect(store.document.items.allSatisfy { !$0.isSplit || $0.children.count >= 2 }, "split sync: no split without panes on the \(mac) Mac")
            expect(store.integrityProblems().isEmpty, "split sync: the \(mac) Mac's sidebar is sound: \(store.integrityProblems())")
        }
        syncA.disable()
        syncB.disable()
    }

    // promise: #921
    /// A split with no panes, or one, as a Cra before the fix synced to every Mac: it goes when the
    /// sidebar loads or a bundle is applied, its pane in its place, so the row that could not be closed
    /// is gone.
    @MainActor
    private static func thinSplitsGoOnLoad() {
        let source = AppComposition(clock: ManualScheduler()).store
        _ = source.createTab(url: "https://codepen.io/before", title: "Before")
        let lone = source.createTab(url: "https://codepen.io/lone", title: "Lone")
        _ = source.createTab(url: "https://codepen.io/after", title: "After")
        let today = source.focusedSpace.todayContainerID
        let listed = source.item(today)?.children ?? []
        var doc = source.document
        var empty = SidebarItem.split(parent: today)
        var single = SidebarItem.split(parent: today)
        single.children = [lone.id]
        empty.children = []
        doc.items = doc.items.map { it in
            var it = it
            if it.id == lone.id { it.parentID = single.id }
            // Where the lone tab was, its split, and an empty one after it.
            if it.id == today { it.children = it.children.flatMap { $0 == lone.id ? [single.id, empty.id] : [$0] } }
            return it
        } + [empty, single]

        let synced = SidebarStore(clock: ManualScheduler())
        synced.replace(document: doc)
        expect(synced.item(empty.id) == nil && synced.item(single.id) == nil, "thin splits: an applied bundle's splits without two panes go")
        expect(synced.item(today)?.children == listed, "thin splits: the lone pane takes its split's place")
        expect(synced.item(lone.id)?.parentID == today && synced.integrityProblems().isEmpty, "thin splits: the sidebar is sound after a bundle: \(synced.integrityProblems())")

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(doc).write(to: AppPaths.file("sidebar.json"))
        let launched = SidebarStore(clock: ManualScheduler())
        expect(launched.item(empty.id) == nil && launched.item(single.id) == nil, "thin splits: a saved sidebar's splits without two panes go at launch")
        expect(launched.item(today)?.children == listed, "thin splits: at launch the lone pane takes its split's place")
        expect(launched.integrityProblems().isEmpty, "thin splits: the sidebar is sound after a launch")
    }

    /// A Blank Window is one Mac's window: its sidebar never goes to the other Mac, and a bundle
    /// from the other Mac leaves this one's Blank Windows and their tabs alone.
    @MainActor
    private static func syncLeavesBlankWindowsOnTheirMac() {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cra-sync-blank-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = ManualScheduler()
        let a = SidebarStore(clock: clock)
        let blankA = a.addBlankWindow(frame: nil).id
        _ = a.createTab(url: "https://example.com/studio-blank", window: blankA)
        let syncA = SettingsSyncService(store: a, clock: clock, device: "Studio", deviceID: "studio")
        expect(syncA.enable(folder: folder) == .synced, "the first Mac writes its bundle")

        let b = SidebarStore(clock: clock)
        let blankB = b.addBlankWindow(frame: nil).id
        let ownB = b.focusedSpaceID(window: blankB)
        let tabB = b.createTab(url: "https://example.com/macbook-blank", window: blankB)
        let syncB = SettingsSyncService(store: b, clock: clock, device: "MacBook", deviceID: "macbook")
        guard case .bundleFound(let found) = syncB.enable(folder: folder) else { return expect(false, "the second Mac finds the bundle") }
        expect(found.spaces == a.orderedSpaces.count && found.tabs == a.document.items.filter(\.isTab).count - 1,
               "the question counts only the first Mac's spaces and their tabs")
        syncB.useRemote()
        expect(b.orderedSpaces.map(\.id) == a.orderedSpaces.map(\.id), "the other Mac's Blank Window is no space here")
        expect(!b.document.items.contains { $0.tab?.url == "https://example.com/studio-blank" }, "nor are its tabs")
        expect(b.isBlank(window: blankB) && b.space(ownB) != nil && b.spaceID(ofItem: tabB.id) == ownB,
               "this Mac's Blank Window keeps its sidebar and its tab")
        expect(b.integrityProblems().isEmpty, "the sidebar stays sound")
        syncA.disable(); syncB.disable()
    }

    // promise: #220
    /// Arc's Blank Window (⌃⌘N): a sidebar of its own in the normal profile, in no space list,
    /// saved and restored with the window, and gone with its tabs when the window closes.
    @MainActor
    private static func blankWindows() {
        let store = AppComposition(clock: ManualScheduler()).store
        let home = store.createSpace(title: "Blank Home", emoji: "🏠").id
        let main = store.activeWindowID
        let spaceTab = store.createTab(url: "https://example.com/space-tab", in: home, window: main)
        let blank = store.addBlankWindow(frame: nil).id
        let own = store.focusedSpaceID(window: blank)
        expect(store.isBlank(window: blank) && store.isStandalone(window: blank) && !store.window(blank).isIncognito,
               "a Blank Window is neither a normal window nor incognito")
        expect(store.space(own)?.title == "This Window" && !store.orderedSpaces.contains { $0.id == own }
               && store.pagedSpaces(window: blank).map(\.id) == [own], "its sidebar, This Window, is in no space list")
        let tab = store.createTab(url: "https://example.com/blank-tab", window: blank)
        expect(store.spaceID(ofItem: tab.id) == own && !store.isIncognito(item: tab.id) && store.profilePath(item: tab.id) == nil,
               "a tab opened there is the window's own, in the Default profile")
        expect(store.profileTabs(window: blank).map(\.id) == [tab.id] && !store.profileTabs(window: main).contains { $0.id == tab.id },
               "its command bar offers only its tabs, and other windows' never offer them")
        store.selectTab(spaceTab.id, window: blank)
        store.focusSpace(home, window: blank)
        expect(store.selectedTabID(window: blank) == tab.id && store.focusedSpaceID(window: blank) == own,
               "a space's tab doesn't open in it, and it doesn't switch to a space")
        let blankSpace = store.space(own)!
        store.moveItem(tab.id, to: blankSpace.pinnedContainerID, index: 0)
        store.addToFavorites(tab.id)
        expect(store.item(tab.id)?.parentID == blankSpace.todayContainerID, "nothing goes into favorites or pinned there")
        store.activeWindowID = blank
        expect(store.lastNormalWindowID == main, "links from other apps keep going to the normal window")
        store.activeWindowID = main

        store.saveAll()
        let reloaded = AppComposition(clock: ManualScheduler()).store
        expect(reloaded.isBlank(window: blank) && reloaded.selectedTabID(window: blank) == tab.id
               && !reloaded.orderedSpaces.contains { $0.id == own }, "a relaunch brings it back with its tabs, still out of the space list")
        expect(reloaded.integrityProblems().isEmpty, "the reloaded sidebar is sound")

        let archived = store.archive.count
        store.removeWindow(blank)
        expect(store.item(tab.id) == nil && store.space(own) == nil && store.archive.count == archived,
               "closing it takes its tabs, as in Arc (nothing goes to the Archive)")
        expect(store.item(spaceTab.id) != nil && store.integrityProblems().isEmpty, "and leaves the spaces as they were")
        store.saveAll()
    }

    // promise: #220
    /// A Blank Window's space whose window is missing from windows.json goes at launch rather
    /// than turning into a space of the sidebar.
    @MainActor
    private static func blankWindowWithoutItsWindow() {
        let store = AppComposition(clock: ManualScheduler()).store
        let blank = store.addBlankWindow(frame: nil).id
        let own = store.focusedSpaceID(window: blank)
        let tab = store.createTab(url: "https://example.com/orphan-blank", window: blank)
        store.prefs.windows.removeAll { $0.id == blank }
        store.saveAll()
        let reloaded = AppComposition(clock: ManualScheduler()).store
        expect(reloaded.space(own) == nil && reloaded.item(tab.id) == nil && !reloaded.spaceOrder.contains(own),
               "an orphaned Blank Window space goes with its tabs")
        expect(reloaded.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #219
    /// A tab dragged out of every window moves into a new Blank Window (Arc 1.172): it leaves its
    /// space, opens there, and the window it left shows no tab. "Move to…" sends it to a space.
    @MainActor
    private static func tornOffTabMovesToABlankWindow() {
        let store = AppComposition(clock: ManualScheduler()).store
        let home = store.createSpace(title: "Tear Home", emoji: "🏠").id
        let main = store.activeWindowID
        let stays = store.createTab(url: "https://example.com/stays", in: home, window: main)
        let torn = store.createTab(url: "https://example.com/torn", in: home, window: main)
        let pinned = store.createTab(url: "https://example.com/pinned", in: home, pinned: true, select: false, window: main)
        expect(store.selectedTabID(window: main) == torn.id, "the dragged tab is open")
        let blank = store.addBlankWindow(frame: nil).id
        let own = store.focusedSpaceID(window: blank)
        store.moveToBlankWindow(torn.id, window: blank)
        expect(store.spaceID(ofItem: torn.id) == own && store.selectedTabID(window: blank) == torn.id,
               "the tab moves into the new window and opens there")
        expect(!store.tabs(under: store.space(home)!.todayContainerID).contains { $0.id == torn.id }
               && store.selectedTabID(window: main) == nil, "it leaves its space, and its old window shows no tab")
        let second = store.addBlankWindow(frame: nil).id
        store.moveToBlankWindow(pinned.id, window: second)
        expect(store.spaceID(ofItem: pinned.id) == store.focusedSpaceID(window: second) && !store.isPinned(pinned.id),
               "a pinned tab tears off too, out of the pinned section")
        let folder = store.createFolder(named: "Stays put", in: store.space(home)!.pinnedContainerID, index: 0)
        store.moveToBlankWindow(folder.id, window: second)
        expect(store.spaceID(ofItem: folder.id) == home, "a folder doesn't")

        // Dropped on a Blank Window's sidebar from a window that has it open: it leaves that
        // window and opens in the Blank Window (Arc).
        store.selectTab(stays.id, window: main)
        store.moveItem(stays.id, to: store.space(store.focusedSpaceID(window: second))!.todayContainerID, index: 0)
        store.tookTab(stays.id, into: second)
        expect(store.selectedTabID(window: main) == nil && store.selectedTabID(window: second) == stays.id,
               "a tab dropped into a Blank Window from another window opens there and leaves the other window")

        // And back onto the normal window's list: it leaves the Blank Window and opens there.
        store.moveItem(stays.id, to: store.space(home)!.todayContainerID, index: 0)
        store.tookTab(stays.id, into: main)
        expect(store.selectedTabID(window: second) == nil && store.selectedTabID(window: main) == stays.id,
               "dragged back onto another window's sidebar, it moves into that window")
        // Two windows on one space both keep a tab open (#4): a drop within the space takes it from neither.
        let third = store.addWindow(spaceID: home, frame: nil).id
        store.selectTab(stays.id, window: third)
        store.tookTab(stays.id, into: third)
        expect(store.selectedTabID(window: main) == stays.id && store.selectedTabID(window: third) == stays.id,
               "a window on the same space keeps it open")
        store.removeWindow(third)

        // Arc 1.172's Move to…: the tabs go to the top of the space's Today, the window lets go of
        // the open one (AppDelegate opens it in the main window), and closing it leaves them there.
        let extra = store.createTab(url: "https://example.com/blank-second", window: blank)
        store.selectTab(torn.id, window: blank)
        let open = store.moveBlankWindowTabs(blank, toSpace: home)
        expect(open == torn.id && store.selectedTabID(window: blank) == nil
               && store.children(of: store.space(home)!.todayContainerID).prefix(2).map(\.id).sorted() == [torn.id, extra.id].sorted(),
               "Move to… puts the window's tabs at the top of the space and hands over its open tab")
        store.removeWindow(blank)
        expect(store.item(torn.id) != nil && store.item(extra.id) != nil && store.space(own) == nil,
               "and the Blank Window closing afterwards leaves them in the space")
        expect(store.item(stays.id) != nil && store.integrityProblems().isEmpty, "and the sidebar stays sound")
        store.removeWindow(second)
        store.saveAll()
    }

    // promise: #288
    /// A tab torn off a space on another profile keeps that profile (#288): in Arc the window it
    /// opens in stays with the space's profile and the page stays signed in. Cra put the Blank
    /// Window on Default, so BrowserManager closed the page and loaded it again signed out.
    @MainActor
    private static func tornOffTabKeepsItsProfile() {
        let store = AppComposition(clock: ManualScheduler()).store
        let work = store.createProfile(name: "Torn Work")
        let sid = store.createSpace(title: "Work", emoji: "💼").id
        store.setProfile(work.id, forSpace: sid)
        let main = store.activeWindowID
        let torn = store.createTab(url: "https://example.com/signed-in", in: sid, window: main)
        let before = store.profilePath(item: torn.id)
        expect(before != nil, "the tab loads in the space's profile")

        let blank = store.addBlankWindow(frame: nil).id
        store.moveToBlankWindow(torn.id, window: blank)
        expect(store.spaceID(ofItem: torn.id) == store.focusedSpaceID(window: blank),
               "the torn-off tab is in the Blank Window")
        expect(store.profilePath(item: torn.id) == before,
               "and still in its space's profile, so its page isn't loaded again signed out")
        let next = store.createTab(url: "https://example.com/next", window: blank)
        expect(store.profilePath(item: next.id) == before, "a new tab in that window loads in the same profile")

        // From a space on Default it stays on Default.
        let home = store.createSpace(title: "Home", emoji: "🏠").id
        let plain = store.createTab(url: "https://example.com/plain", in: home, window: main)
        let second = store.addBlankWindow(frame: nil).id
        store.moveToBlankWindow(plain.id, window: second)
        expect(store.spaceID(ofItem: plain.id) == store.focusedSpaceID(window: second) && store.profilePath(item: plain.id) == nil,
               "a tab from a Default space stays on Default")
        store.removeWindow(blank)
        store.removeWindow(second)
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #257
    /// A page's "Open Link in Split View" (#257): the link opens in a new pane right after the
    /// page it was clicked in, as the open pane; a split of four panes takes no more.
    @MainActor
    private static func openLinkInSplit() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Link Split", emoji: "🔗").id
        let main = store.activeWindowID
        let today = store.space(sid)!.todayContainerID
        let list = store.createTab(url: "https://example.com/list", in: sid, window: main)
        let entry = store.openLinkInSplit("https://example.com/entry-1", from: list.id, window: main)
        let split = store.splitContaining(list.id)
        expect(entry != nil && split != nil && store.paneTabIDs(for: list.id) == [list.id, entry!.id],
               "from a lone tab the link opens in a split beside it, the page on the left")
        expect(store.item(entry!.id)?.tab?.url == "https://example.com/entry-1" && store.selectedTabID(window: main) == entry!.id,
               "the new pane loads the link and is the open one")
        expect(store.children(of: today).map(\.id) == [split!.id], "the split takes the tab's place in Today")

        let second = store.openLinkInSplit("https://example.com/entry-2", from: list.id, window: main)!
        expect(store.paneTabIDs(for: list.id) == [list.id, second.id, entry!.id],
               "from a pane of a split the link joins it right after that pane")
        let third = store.openLinkInSplit("https://example.com/entry-3", from: entry!.id, window: main)!
        expect(store.paneTabIDs(for: list.id) == [list.id, second.id, entry!.id, third.id], "up to four panes")
        expect(store.openLinkInSplit("https://example.com/entry-4", from: list.id, window: main) == nil
               && store.paneTabIDs(for: list.id).count == 4 && store.selectedTabID(window: main) == third.id,
               "a fifth is refused and nothing changes (the window says Cannot Add New Pane)")

        let pinned = store.createTab(url: "https://example.com/pinned-list", in: sid, pinned: true, window: main)
        let fromPinned = store.openLinkInSplit("https://example.com/pinned-entry", from: pinned.id, window: main)!
        expect(store.isPinned(pinned.id) && store.splitContaining(pinned.id) == nil && store.splitContaining(fromPinned.id) != nil
               && !store.isPinned(fromPinned.id) && store.paneTabIDs(for: fromPinned.id).count == 2,
               "a pinned tab stays where it is: the split goes in Today with a copy of its page, as Add Split View does")
        expect(store.openLinkInSplit("https://example.com/x", from: UUID(), window: main) == nil, "no tab, no pane")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #498
    /// A split holds Arc's four panes on every path (#498): a tab let go on a full split's sidebar
    /// row stays where it was, and a pinned tab leaves no copy behind; a split with room still
    /// takes it.
    @MainActor
    private static func fullSplitTakesNoMorePanes() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Full Split", emoji: "🪟").id
        let main = store.activeWindowID
        let today = store.space(sid)!.todayContainerID
        let tabs = (1...4).map { store.createTab(url: "https://example.com/pane-\($0)", in: sid, window: main) }
        guard let split = store.createSplit(with: tabs.map(\.id)) else { return expect(false, "four tabs make a split") }
        let panes = store.children(of: split.id).map(\.id)
        expect(panes.count == SplitDropProposal.maximumPanes, "a split of four panes")

        let fifth = store.createTab(url: "https://example.com/fifth", in: sid, window: main)
        store.moveItem(fifth.id, to: split.id, index: nil)
        expect(store.children(of: split.id).map(\.id) == panes, "a fifth tab dropped on the split's row adds no pane")
        expect(store.item(fifth.id)?.parentID == today, "and stays in Today")

        let pinned = store.createTab(url: "https://example.com/pinned", in: sid, pinned: true, window: main)
        let count = store.children(of: split.id).count
        store.addToSplit(split.id, tabID: pinned.id, at: 0)
        expect(store.children(of: split.id).count == count && store.isPinned(pinned.id),
               "a pinned tab adds no copy of itself to a full split")

        store.archiveTab(panes[3], reason: .manual)
        store.moveItem(fifth.id, to: split.id, index: nil)
        expect(store.children(of: split.id).map(\.id) == Array(panes.prefix(3)) + [fifth.id], "with room again the split takes it")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    // promise: #273
    /// Back on a tab a link opened (#273): once its page has nothing behind it, the tab closes to
    /// the archive and the tab the link was clicked in shows again, as in Arc. Pages it went on to
    /// come first, and a tab with nowhere to return to keeps Back off. The link is saved with the
    /// tab (Arc's referrerID), as its page history is, so it outlasts a relaunch and ⇧⌘T.
    @MainActor
    private static func backToReferrer() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Back", emoji: "↩️").id
        let main = store.activeWindowID
        let source = store.createTab(url: "https://example.com/list", in: sid, window: main)
        let other = store.createTab(url: "https://example.com/other", in: sid, window: main)
        store.selectTab(source.id, window: main)
        let link = store.createTab(url: "https://example.com/post", in: sid, window: main, referrer: source.id)
        expect(store.backStep(link.id, canGoBack: true) == .history, "a page with history goes back in it first")
        expect(store.backStep(link.id, canGoBack: false) == .close(returnTo: source.id),
               "on the page the link opened, Back is on and returns to the tab the link came from")
        expect(store.backStep(source.id, canGoBack: false) == .none && store.backStep(other.id, canGoBack: false) == .none,
               "a tab no link opened has nothing to go back to")
        store.closeToReferrer(link.id, referrer: source.id, window: main)
        expect(store.item(link.id) == nil && store.archive.first?.id == link.id && store.archive.first?.reason == .manual,
               "the tab goes to the archive, as ⌘W, so ⇧⌘T brings it back")
        expect(store.selectedTabID(window: main) == source.id, "and the tab the link came from is the one shown")

        // Its own tab gone: from a third tab, opened from the link's tab before it closed.
        let second = store.createTab(url: "https://example.com/post-2", in: sid, window: main, referrer: source.id)
        let third = store.createTab(url: "https://example.com/post-3", in: sid, window: main, referrer: second.id)
        store.archiveTab(second.id, reason: .manual)
        expect(store.backStep(third.id, canGoBack: false) == .none, "the tab it came from was closed: Back stays off")
        let restored = store.reopenLastArchived()
        expect(restored?.id == second.id && store.backStep(second.id, canGoBack: false) == .close(returnTo: source.id),
               "a tab ⇧⌘T brings back returns where it came from, as its history comes back with it")
        expect(store.backStep(third.id, canGoBack: false) == .close(returnTo: second.id), "and so does the tab opened from it")

        store.saveAll()
        let reloaded = AppComposition(clock: ManualScheduler()).store
        expect(reloaded.item(third.id)?.tab?.referrerID == second.id
               && reloaded.backStep(third.id, canGoBack: false) == .close(returnTo: second.id),
               "after a relaunch Back still returns to the tab the link came from (Arc saves referrerID)")

        let pinned = store.createTab(url: "https://example.com/pinned", in: sid, window: main, referrer: source.id)
        store.togglePinned(pinned.id)
        expect(store.isPinned(pinned.id) && store.backStep(pinned.id, canGoBack: false) == .none,
               "a link's tab once pinned stays: closing a pinned tab would reset its page")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    /// ⌘1…⌘9 go to sidebar items, not tabs (Arc: "Go to Sidebar Item N", X 17 Nov): a split
    /// favorite is one number and opens on the pane focused last, as a click on it does.
    @MainActor
    private static func numberedSidebarItems() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Numbers", emoji: "🔢").id
        let space = store.space(sid)!
        let x = store.createTab(url: "https://x.example/", in: sid, pinned: true, select: false, parent: space.favoritesContainerID, index: 0)
        let fb = store.createTab(url: "https://fb.example/", in: sid, pinned: true, select: false, parent: space.favoritesContainerID, index: 1)
        let tg = store.createTab(url: "https://tg.example/", in: sid, pinned: true, select: false, parent: space.favoritesContainerID, index: 2)
        let yt = store.createTab(url: "https://yt.example/", in: sid, pinned: true, select: false, parent: space.favoritesContainerID, index: 3)
        let favSplit = store.createSplit(with: [fb.id, tg.id], inPlace: true)!
        let a = store.createTab(url: "https://a.example/", in: sid, select: false, parent: space.todayContainerID, index: 0)
        let b = store.createTab(url: "https://b.example/", in: sid, select: false, parent: space.todayContainerID, index: 1)
        let c = store.createTab(url: "https://c.example/", in: sid, select: false, parent: space.todayContainerID, index: 2)
        _ = store.createSplit(with: [a.id, b.id])
        expect(store.children(of: space.favoritesContainerID).map(\.id) == [x.id, favSplit.id, yt.id], "set up: X, a split favorite, YouTube")
        expect(store.numberedTabs(in: sid) == [x.id, fb.id, yt.id, a.id, c.id], "a split takes one number, opening its first pane")
        store.selectTab(tg.id)
        expect(store.numberedTabs(in: sid) == [x.id, tg.id, yt.id, a.id, c.id], "and then the pane focused last")
    }

    /// Arc's Today tab menu: "Archive Tabs Below" archives every Today row under the one clicked.
    @MainActor
    private static func archiveTabsBelow() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Below", emoji: "⬇️").id
        let today = store.space(sid)!.todayContainerID
        let a = store.createTab(url: "https://a.example/", in: sid, select: false, parent: today, index: 0)
        let b = store.createTab(url: "https://b.example/", in: sid, select: false, parent: today, index: 1)
        let c = store.createTab(url: "https://c.example/", in: sid, select: false, parent: today, index: 2)
        let d = store.createTab(url: "https://d.example/", in: sid, select: false, parent: today, index: 3)
        let split = store.createSplit(with: [c.id, d.id])!
        let pinned = store.createTab(url: "https://p.example/", in: sid, pinned: true, select: false)
        expect(store.children(of: today).map(\.id) == [a.id, b.id, split.id], "set up: two tabs and a split in Today")
        store.archiveTabsBelow(a.id)
        expect(store.children(of: today).map(\.id) == [a.id], "the tabs and the split below it are archived")
        expect(Set(store.archive.prefix(3).compactMap(\.item.tab?.url)) == ["https://b.example/", "https://c.example/", "https://d.example/"],
               "and land in the archive")
        store.archiveTabsBelow(pinned.id)
        expect(store.item(pinned.id) != nil, "a pinned tab archives nothing below it (Arc offers it on Today tabs only)")
        expect(store.integrityProblems().isEmpty, "the sidebar stays sound")
    }

    // promise: #600
    /// Arc 1.173.1's Today tab menu has two ⌥ rows: Archive Tabs Above (under Archive Tabs Below)
    /// archives every Today row over the one clicked, Archive Other Tabs (under Archive Tab) every
    /// Today row but it. Pinned tabs and favorites stay.
    @MainActor
    private static func archiveTabsAboveAndOthers() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Above", emoji: "⬆️").id
        let today = store.space(sid)!.todayContainerID
        let a = store.createTab(url: "https://a.example/", in: sid, select: false, parent: today, index: 0)
        let b = store.createTab(url: "https://b.example/", in: sid, select: false, parent: today, index: 1)
        let c = store.createTab(url: "https://c.example/", in: sid, select: false, parent: today, index: 2)
        let d = store.createTab(url: "https://d.example/", in: sid, select: false, parent: today, index: 3)
        let e = store.createTab(url: "https://e.example/", in: sid, select: false, parent: today, index: 4)
        let split = store.createSplit(with: [a.id, b.id])!
        let pinned = store.createTab(url: "https://p.example/", in: sid, pinned: true, select: false)
        expect(store.children(of: today).map(\.id) == [split.id, c.id, d.id, e.id], "set up: a split and three tabs in Today")
        expect(store.hasTodayTabs(above: c.id) && !store.hasTodayTabs(above: split.id), "the split counts as a row above c, and nothing is above the split")
        store.archiveTabsAbove(d.id)
        expect(store.children(of: today).map(\.id) == [d.id, e.id], "Archive Tabs Above archives the split and the tab over it")
        expect(!store.hasTodayTabs(above: d.id) && store.hasTodayTabs(below: d.id), "nothing is above it now, one tab is below")
        store.archiveOtherTabs(e.id)
        expect(store.children(of: today).map(\.id) == [e.id] && store.item(pinned.id) != nil,
               "Archive Other Tabs leaves only it in Today, and the pinned tab")
        store.archiveTabsAbove(pinned.id)
        store.archiveOtherTabs(pinned.id)
        expect(store.item(pinned.id) != nil && store.children(of: today).map(\.id) == [e.id], "a pinned tab archives nothing")
        expect(store.integrityProblems().isEmpty, "the sidebar stays sound")
    }

    // promise: #600
    /// Arc 1.173.1's split menu: Change Icon… gives the split an emoji or a glyph, Reset Name and
    /// Icon takes the name and the icon away, and Duplicate keeps both.
    @MainActor
    private static func splitIconAndReset() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Icons", emoji: "🧩").id
        let a = store.createTab(url: "https://a.example/", in: sid, select: false)
        let b = store.createTab(url: "https://b.example/", in: sid, select: false)
        guard let split = store.createSplit(with: [a.id, b.id]) else { return expect(false, "the split is made") }
        store.setSplitIcon(split.id, .emoji("😀"))
        expect(store.item(split.id)?.split?.icon == .emoji("😀") && store.item(split.id)?.title == nil, "the split takes an emoji")
        store.rename(split.id, to: "Work")
        guard let twin = store.duplicateSplit(split.id) else { return expect(false, "the split duplicates") }
        expect(twin.split?.icon == .emoji("😀") && twin.title == "Work", "its copy keeps the icon and the name")
        store.setSplitIcon(split.id, .symbol("star.fill"))
        expect(store.item(split.id)?.split?.icon == .symbol("star.fill"), "a glyph replaces the emoji")
        store.resetSplitNameAndIcon(split.id)
        expect(store.item(split.id)?.split?.icon == SpaceIcon.none && store.item(split.id)?.title == nil,
               "Reset Name and Icon takes both away")
        store.setSplitIcon(a.id, .emoji("🙃"))
        expect(store.item(a.id)?.split == nil, "a tab takes no split icon")
        expect(store.integrityProblems().isEmpty, "the sidebar stays sound")
    }

    /// An incognito window's pages all load in one off-the-record context, whatever profile its
    /// space would name, so the space takes no profile; and Export into Folder can't carry its
    /// tabs into a saved space (#413).
    // promise: #413
    @MainActor
    private static func incognitoSpaceKeepsItsContext() {
        let store = AppComposition(clock: ManualScheduler()).store
        let work = store.createProfile(name: "Work")
        let home = store.createSpace(title: "Home", emoji: "🏠").id
        let incognito = store.addIncognitoWindow(frame: nil)
        let sid = incognito.focusedSpaceID!
        let secret = store.createTab(url: "https://example.com/secret", window: incognito.id)
        store.setProfile(work.id, forSpace: sid)
        expect(store.space(sid)?.profileID == nil, "an incognito space takes no profile")
        expect(store.exportSpace(sid, intoFolderIn: home) == nil, "an incognito space doesn't export into a saved space")
        expect(store.isIncognito(item: secret.id) && store.spaceID(ofItem: secret.id) == sid, "its tab stays in the incognito window")
        expect(store.integrityProblems().isEmpty, "the sidebar stays sound")
    }

    /// A new window, normal, incognito or Blank, opens with the sidebar as it was last hidden or shown,
    /// in any window (Arc's sidebarViewPreferences.sidebarMode, #644). The windows already open keep theirs.
    // promise: #644
    @MainActor
    private static func newWindowsTakeTheLastSidebarChoice() {
        let store = AppComposition(clock: ManualScheduler()).store
        let first = store.prefs.windows[0].id
        expect(store.addIncognitoWindow(frame: nil).sidebarVisible, "with no choice made, a new window shows its sidebar")
        store.chooseSidebar(visible: false, window: first)
        expect(!store.window(first).sidebarVisible, "the window hides its sidebar")
        let incognito = store.addIncognitoWindow(frame: nil)
        let normal = store.addWindow(spaceID: store.focusedSpaceID(window: first), frame: nil)
        let blank = store.addBlankWindow(frame: nil)
        expect([incognito, normal, blank].allSatisfy { !$0.sidebarVisible }, "new windows open with the sidebar hidden too")
        store.chooseSidebar(visible: true, window: normal.id)
        expect(store.addIncognitoWindow(frame: nil).sidebarVisible, "the choice made last counts, in whichever window")
        expect(!store.window(first).sidebarVisible && !store.window(incognito.id).sidebarVisible, "open windows keep their own")
    }

    /// Arc's Clear on Today ("Clear unselected Today tabs"): the tab on screen and a tab playing
    /// sound stay; a split stays whole with them.
    // promise: #406
    @MainActor
    private static func clearTodayKeepsSelectedAndPlaying() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Clear", emoji: "🧹").id
        let today = store.space(sid)!.todayContainerID
        let a = store.createTab(url: "https://a.example/", in: sid, select: false, parent: today, index: 0)
        let video = store.createTab(url: "https://video.example/", in: sid, select: false, parent: today, index: 1)
        let c = store.createTab(url: "https://c.example/", in: sid, select: false, parent: today, index: 2)
        let d = store.createTab(url: "https://d.example/", in: sid, select: false, parent: today, index: 3)
        let split = store.createSplit(with: [c.id, d.id])!
        let shown = store.createTab(url: "https://shown.example/", in: sid, parent: today, index: 3)
        expect(store.selectedTabID == shown.id, "set up: the last tab is on screen")
        store.clearToday(sid, playing: [video.id])
        expect(store.children(of: today).map(\.id) == [video.id, shown.id],
               "Clear keeps the tab on screen and the one playing sound, and archives the rest")
        expect(store.item(split.id) == nil && store.item(a.id) == nil, "the split and the idle tab are archived")

        let e = store.createTab(url: "https://e.example/", in: sid, select: false, parent: today, index: 2)
        let f = store.createTab(url: "https://f.example/", in: sid, select: false, parent: today, index: 3)
        let paneSplit = store.createSplit(with: [e.id, f.id])!
        store.selectTab(f.id)
        store.clearToday(sid, playing: [])
        expect(store.children(of: today).map(\.id) == [paneSplit.id], "a split with the selected pane stays whole")
        expect(store.integrityProblems().isEmpty, "the sidebar stays sound")
    }

    /// The Tabs menu's facts (#622) count tabs only up to what its rules need and stop at the first
    /// clearable Today row; each answer has to agree with the full lists they stand in for.
    // promise: #622
    @MainActor
    private static func tabsMenuCountsStopEarly() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Counts", emoji: "🔢").id
        let space = store.space(sid)!
        func agrees(_ label: String, playing: Set<UUID> = []) {
            let all = store.visibleTabs(in: sid).count
            for limit in 0...4 {
                expect(store.visibleTabCount(in: sid, upTo: limit) == min(all, limit), "\(label): \(limit) of \(all) tabs counted")
            }
            expect(store.todayHasClearable(sid, playing: playing) == !store.todayClearing(sid, playing: playing).isEmpty,
                   "\(label): Clear Today's answer is the full list's")
        }
        agrees("an empty space")
        let folder = store.createFolder(named: "Empty", in: space.todayContainerID, index: 0)
        agrees("a folder with no tabs")
        let pinned = store.createTab(url: "https://pinned.example/", in: sid, select: false, parent: folder.id, index: 0)
        agrees("one tab in a folder")
        let a = store.createTab(url: "https://a.example/", in: sid, select: false, parent: space.todayContainerID, index: 1)
        let b = store.createTab(url: "https://b.example/", in: sid, select: false, parent: space.todayContainerID, index: 2)
        let split = store.createSplit(with: [a.id, b.id])!
        agrees("a split after the folder")
        store.selectTab(b.id)
        agrees("the split's pane on screen")
        agrees("the folder's tab playing", playing: [pinned.id])
        let shown = store.createTab(url: "https://shown.example/", in: sid, parent: space.todayContainerID, index: 3)
        agrees("another tab on screen", playing: [pinned.id])
        expect(store.item(split.id) != nil && store.selectedTabID == shown.id, "set up: the split stays, the last tab is on screen")
        expect(store.visibleTabCount(in: UUID(), upTo: 2) == 0 && !store.todayHasClearable(UUID(), playing: []), "an unknown space has none")
    }

    /// Arc's Shortcuts list: Collapse All Folders / Expand All Folders, nested folders included.
    @MainActor
    private static func allFoldersExpanded() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Folders", emoji: "📁").id
        let pinned = store.space(sid)!.pinnedContainerID
        let outer = store.createFolder(named: "Outer", in: pinned)
        let inner = store.createFolder(named: "Inner", in: outer.id)
        let other = store.createSpace(title: "Other", emoji: "🗂️", focus: false).id
        let elsewhere = store.createFolder(named: "Elsewhere", in: store.space(other)!.pinnedContainerID)
        store.setExpanded(elsewhere.id, false)
        store.setAllFoldersExpanded(false, inSpace: sid)
        expect(!store.isExpanded(outer.id) && !store.isExpanded(inner.id), "every folder in the space closes, nested ones too")
        store.setAllFoldersExpanded(true, inSpace: sid)
        expect(store.isExpanded(outer.id) && store.isExpanded(inner.id), "and they all open again")
        expect(!store.isExpanded(elsewhere.id), "another space's folders stay as they were")
    }

    // promise: #266
    /// Tabs let go on a folder's row go in at the top, in their order, and the folder stays as it
    /// was: Arc 1.172 (offline copy, real drag, 9 Nov 2026) saved a Today tab dropped on a closed
    /// folder as its first child and left the folder closed, the dropped tab, open, in sight under
    /// it. Cra added them at the bottom and opened the folder (#266).
    @MainActor
    private static func dropIntoFolderGoesOnTop() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Drops", emoji: "📁").id
        let folder = store.createFolder(named: "Links", in: store.space(sid)!.pinnedContainerID)
        let inside = ["a", "b", "c"].map { store.createTab(url: "https://example.com/\($0)", in: sid, select: false, parent: folder.id).id }
        store.setExpanded(folder.id, false)
        let open = store.createTab(url: "https://example.com/open", in: sid, select: true).id
        let y = store.createTab(url: "https://example.com/y", in: sid, select: false).id
        let z = store.createTab(url: "https://example.com/z", in: sid, select: false).id
        let children = { store.item(folder.id)?.children ?? [] }

        let before = children()
        expect(Set(before) == Set(inside), "the folder holds its three tabs")
        store.dropIntoFolder([open], folder: folder.id)
        expect(children() == [open] + before, "a tab dropped on a folder goes in first (#266)")
        expect(!store.isExpanded(folder.id), "a closed folder stays closed (#266)")
        expect(store.peekedTabs(in: folder.id).map(\.id) == [open], "and keeps the open tab it took in sight, as Arc does")

        store.dropIntoFolder([y, z], folder: folder.id)
        expect(children() == [y, z, open] + before, "several picked tabs go in first, in their order")
        expect(!store.isExpanded(folder.id) && store.peekedTabs(in: folder.id).map(\.id) == [open], "the folder still shows only the open tab")

        store.setExpanded(folder.id, true)
        let w = store.createTab(url: "https://example.com/w", in: sid, select: false).id
        store.dropIntoFolder([w], folder: folder.id)
        expect(children().first == w && store.isExpanded(folder.id), "an open folder takes it at the top and stays open")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    /// Arc's Settings ▸ Advanced "When opening Arc, restore windows from previous session", off:
    /// launch keeps one window, the one in use last; a Blank Window's own space goes with it.
    @MainActor
    private static func oneWindowAtLaunch() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.focusedSpace.id
        let second = store.addWindow(spaceID: sid, frame: nil)
        let blank = store.addBlankWindow(frame: nil)
        let blankSpace = store.window(blank.id).focusedSpaceID!
        store.activeWindowID = second.id
        store.keepOnlyActiveWindow()
        expect(store.prefs.windows.map(\.id) == [second.id], "only the window in use last stays")
        expect(store.space(blankSpace) == nil, "the Blank Window's own space goes with it")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
    }

    /// Arc's Reveal Tab in Sidebar (⌃Space): the folders around the tab open, and a collapsed
    /// pinned section opens when the tab is in it.
    @MainActor
    private static func revealInSidebar() {
        let store = AppComposition(clock: ManualScheduler()).store
        let sid = store.createSpace(title: "Reveal", emoji: "🔦").id
        let pinned = store.space(sid)!.pinnedContainerID
        let outer = store.createFolder(named: "Outer", in: pinned)
        let inner = store.createFolder(named: "Inner", in: outer.id)
        let tab = store.createTab(url: "https://deep.example/", in: sid, pinned: true, select: false, parent: inner.id)
        store.setAllFoldersExpanded(false, inSpace: sid)
        store.togglePinnedCollapsed(sid)
        store.revealInSidebar(tab.id)
        expect(store.isExpanded(outer.id) && store.isExpanded(inner.id), "both folders around the tab open")
        expect(!store.isPinnedCollapsed(sid), "and the collapsed pinned section opens")
        let today = store.createTab(url: "https://today.example/", in: sid, select: false)
        store.togglePinnedCollapsed(sid)
        store.revealInSidebar(today.id)
        expect(store.isPinnedCollapsed(sid), "a Today tab leaves the pinned section as it is")
    }

    /// Arc's ⌃Tab after a ⌘-click: the tab the link opened in the background is next after the
    /// current one, so a tap goes to it and the next tap comes back.
    @MainActor
    private static func recentTabsTakeBackgroundTabs() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        let sid = store.createSpace(title: "Recent", emoji: "⏱️").id
        let older = store.createTab(url: "https://example.com/older", in: sid)
        clock.advance(by: 1)
        let source = store.createTab(url: "https://example.com/source", in: sid)
        clock.advance(by: 1)
        let link = store.createTab(url: "https://example.com/link", in: sid, select: false, referrer: source.id)
        expect(store.recentTabs(in: sid, limit: .max) == [source.id, link.id, older.id],
               "the background tab comes right after the current tab, before the one visited earlier")
        clock.advance(by: 1)
        store.selectTab(link.id)
        expect(store.recentTabs(in: sid, limit: .max) == [link.id, source.id, older.id], "on it, the next tab is the one it came from")
    }

    // promise: #554
    /// ⌃Tab with a split (#554): the split is one card with its panes in order, not a card per
    /// pane, and picking it goes back to the pane used last.
    @MainActor
    private static func recentCardsKeepSplitsWhole() {
        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        let sid = store.createSpace(title: "Splits", emoji: "🪟").id
        let left = store.createTab(url: "https://example.com/left", in: sid)
        clock.advance(by: 1)
        let right = store.createTab(url: "https://example.com/right", in: sid)
        clock.advance(by: 1)
        guard let split = store.createSplit(with: [left.id, right.id]) else { return expect(false, "two tabs make a split") }
        clock.advance(by: 1)
        store.selectTab(right.id)
        clock.advance(by: 1)
        let solo = store.createTab(url: "https://example.com/solo", in: sid)
        clock.advance(by: 1)
        store.selectTab(solo.id)
        let cards = store.recentCards(in: sid, limit: .max)
        expect(cards.map(\.id) == [solo.id, split.id], "the split is one card after the tab on screen")
        expect(cards.last?.panes == [left.id, right.id] && cards.last?.isSplit == true, "holding both panes in pane order")
        expect(store.recentTabs(in: sid, limit: .max) == [solo.id, right.id], "a tap goes to the pane used last")
        clock.advance(by: 1)
        store.selectTab(right.id)
        expect(store.recentCards(in: sid, limit: .max).map(\.id) == [split.id, solo.id], "on the split, the next card is the tab it came from")
    }

    /// Every store in this process loads what earlier tests' stores saved to the one data folder, with
    /// their clocks' times, and some ran hours ahead. A test that ranks tabs it didn't make (⌃⌥Tab lists
    /// every space) moves its clock past all of them first, so its own tabs are the newest.
    @MainActor
    private static func startAfterLoadedTabs(_ store: SidebarStore, _ clock: ManualScheduler) {
        guard let latest = store.document.items.compactMap({ $0.tab?.timeLastActiveAt }).max(), latest >= clock.now else { return }
        clock.advance(by: latest.timeIntervalSince(clock.now) + 1)
    }

    /// ⌃⌥Tab (#467): every space's recent tabs, the window's own first. Picking another space's tab
    /// goes to that space, and the next tap comes back to the tab it left.
    ///
    /// It lists every space, so it also sees the ones the store loaded from what earlier tests saved,
    /// some on clocks hours ahead of this one. Whether that save had landed was a race that failed this
    /// test under load (20 of 24 parallel runs, 18 Nov 2026); a newer tab is now always on disk.
    @MainActor
    private static func recentTabsInAllSpacesGoBack() {
        let earlierClock = ManualScheduler()
        let earlier = AppComposition(clock: earlierClock).store
        let leftover = earlier.createTab(url: "https://example.com/leftover", in: earlier.focusedSpaceID)
        earlierClock.advance(by: 3600)
        earlier.selectTab(leftover.id)
        earlier.saveAll()

        let clock = ManualScheduler()
        let store = AppComposition(clock: clock).store
        expect(store.item(leftover.id)?.tab?.timeLastActiveAt.map { $0 > clock.now } == true,
               "the store loaded a tab last active after this test's clock starts")
        startAfterLoadedTabs(store, clock)
        let work = store.createSpace(title: "Work", emoji: "💼").id
        let workTab = store.createTab(url: "https://example.com/work", in: work)
        clock.advance(by: 1)
        let home = store.createSpace(title: "Home", emoji: "🏠").id
        let homeOld = store.createTab(url: "https://example.com/home-old", in: home)
        clock.advance(by: 1)
        let homeTab = store.createTab(url: "https://example.com/home", in: home)
        clock.advance(by: 1)
        store.selectTab(homeTab.id)
        expect(store.recentTabs(in: home, limit: .max) == [homeTab.id, homeOld.id], "⌃Tab stays in the space")
        let all = store.recentTabsInAllSpaces(limit: .max)
        expect(all.prefix(3) == [homeTab.id, homeOld.id, workTab.id][...], "⌃⌥Tab lists the other space's tabs too")
        clock.advance(by: 1)
        store.selectTab(workTab.id)
        expect(store.focusedSpaceID == work, "picking another space's tab goes to its space")
        expect(store.recentTabsInAllSpaces(limit: 2) == [workTab.id, homeTab.id], "and the next tap comes back")
        store.archiveTab(leftover.id, reason: .manual)
        store.saveAll()
    }

    // promise: crash-zen-favicon-size
    /// Zen's favicons come from Firefox's favicons.sqlite, where the widest icon is often an SVG,
    /// and an SVG can say it is any size. Drawn at that size it ran a 0.1.43 import out of memory
    /// (two crash reports in tiffRepresentation under ZenImporter.plan); each icon is written small.
    private static func zenFaviconSize() {
        let svg = #"<svg xmlns="http://www.w3.org/2000/svg" width="3000" height="2000"><rect width="3000" height="2000" fill="orange"/></svg>"#
        guard let huge = NSImage(data: Data(svg.utf8)) else { return expect(false, "an SVG favicon loads") }
        let png = ZenImporter.faviconPNG(huge).flatMap(NSBitmapImageRep.init(data:))
        expect(png != nil, "a huge SVG favicon is written")
        expect((png?.pixelsWide ?? .max) <= 64 && (png?.pixelsHigh ?? .max) <= 64, "at favicon size, not the size the SVG declares")
        expect(png.map { $0.pixelsWide > $0.pixelsHigh } == true, "keeping its shape")

        let small = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { r in NSColor.red.setFill(); r.fill(); return true }
        let smallPNG = ZenImporter.faviconPNG(small).flatMap(NSBitmapImageRep.init(data:))
        expect(smallPNG?.pixelsWide == 16, "a 16 px favicon stays 16 px")
    }

    // promise: #868
    /// Air Traffic Control's `rerouteTab` moves a newly opened non-pinned Today tab to the target
    /// space and follows it while keeping the originating space's prior tab (`DSA Sheet`) selected,
    /// and refuses to move pinned/favorite tabs or target standalone/missing spaces (#868).
    @MainActor
    private static func rerouteTabKeepsOriginSelection() {
        let store = AppComposition(clock: ManualScheduler()).store
        let pro = store.orderedSpaces[0].id
        let personal = store.createSpace(title: "Personal", emoji: "👤").id
        let sheet = store.createTab(url: "https://docs.google.com/sheet", in: pro, pinned: true, select: true)
        let redirected = store.createTab(url: "https://www.scaler.com/problems/1", in: pro, select: true)
        expect(store.selectedTabID(in: pro) == redirected.id, "newly opened foreground tab is selected in Pro")
        store.rerouteTab(redirected.id, toSpace: personal, window: nil)
        expect(store.spaceID(ofItem: redirected.id) == personal && store.focusedSpaceID == personal
               && store.selectedTabID(in: personal) == redirected.id,
               "rerouteTab moves the Today tab to Personal and switches focus there")
        expect(store.selectedTabID(in: pro) == sheet.id,
               "originating space Pro still has DSA Sheet selected instead of going blank")

        store.rerouteTab(sheet.id, toSpace: personal, window: nil)
        expect(store.spaceID(ofItem: sheet.id) == pro, "rerouteTab never moves a pinned tab")
        let blank = store.addBlankWindow(frame: nil).focusedSpaceID!
        store.rerouteTab(redirected.id, toSpace: blank, window: nil)
        expect(store.spaceID(ofItem: redirected.id) == personal, "rerouteTab never targets a standalone space")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
