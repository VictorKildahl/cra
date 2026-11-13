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

        try arcImport()
        try diaImport()
        chromiumProfile()
        deletedBrowserStillImports()
        chromiumManifestV2Import()
        autoArchive()
        longAutoArchive()
        tabSleepCadence()
        tabRestTimes()
        integrity()
        liveFolderExpiry()
        pluginFolderResults()
        liveRepositoryFiltering()
        liveRepositoryMenus()
        liveFolderExpiryKeepsNavigatedPages()
        gitLabHiddenItems()
        gitLabFolderExpiryAndDeletion()
        gitLabMultipleServers()
        liveFoldersRejectStandaloneSpaces()
        gitLabProfileChangeClearsResults()
        gitLabFolderMovesRejectDuplicateServers()
        gitLabProfileChangeKeepsNavigatedPages()
        stampsUseTheClock()
        persistenceFaults()
        incognitoStaysOffDisk()
        mcpExcludesPrivateTabs()
        pinnedURL()
        tabFavicons()
        folderSymbols()
        moveTabToSpace()
        folderPeek()
        collapsedPinnedPeek()
        closeSuccessor()
        favoritesEmptyState()
        sharedFavorites()
        newDocumentApps()
        themePreview()
        try arcSpacesWithoutAThemeShareOneDefault()
        try arcItemListedTwice()
        try arcLiveFolderImportsLive()
        try arcSpaceWithoutAnIconImportsAsADot()
        littleWindowProfile()
        tidyTabs()
        tidyExistingGroupIdentity()
        tidyConsideredSnapshots()
        tidySingletonGroups()
        pinHook()
        dropOnPinnedTabSplits()
        reopenClosedTabs()
        windowsShareTheSidebar()
        settingsSync()
        syncLeavesBlankWindowsOnTheirMac()
        blankWindows()
        blankWindowWithoutItsWindow()
        tornOffTabMovesToABlankWindow()
        tornOffTabKeepsItsProfile()
        archiveTabsBelow()
        clearTodayKeepsSelectedAndPlaying()
        allFoldersExpanded()
        dropIntoFolderGoesOnTop()
        revealInSidebar()
        oneWindowAtLaunch()
        openLinkInSplit()
        backToReferrer()
        recentTabsTakeBackgroundTabs()
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
        expect(plan.archive.map(\.pageTitle) == ["Old two", "Old one"], "archived tabs are newest first")
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
        expect(home.today.compactMap(\.url) == ["https://example.com/open", "https://example.com/left", "https://example.com/right"],
               "open tabs come over, a split as its tabs, a new tab page left out")
        expect(work.pinned.count == 1 && work.pinned[0].customTitle == "Tools" && work.pinned[0].children.compactMap(\.url) == ["https://example.com/ci"],
               "edits still in the -wal come over")

        expect((try? DiaImporter.plan(secret: "wrong")) == nil,
               "a secret that opens no sidebar database fails instead of importing Dia's stale older files")
        expect((try? DiaImporter.plan())?.spaces.contains { $0.title == "Home" } == false, "without the secret nothing comes from the database")

        let clock = ManualScheduler()
        let composition = AppComposition(clock: clock)
        let result = composition.store.apply(plan, includeArchive: false, includeSettings: false)
        expect(result.spaces == 2 && result.folders == 3, "applying adds both spaces and their folders")
        let homeSpace = composition.store.orderedSpaces.first { $0.title == "Home" }
        let open = homeSpace.map { composition.store.tabs(under: $0.todayContainerID) } ?? []
        expect(open.count == 3 && open.allSatisfy { $0.tab?.timeLastActiveAt == clock.now },
               "open tabs count as active at the import, so auto-archive doesn't take weeks-old Dia tabs at once")
        expect(composition.store.integrityProblems().isEmpty, "the imported sidebar is sound")
    }

    /// Chrome-family profiles (Tests/Fixtures/Chromium/Default): the last session's open tabs,
    /// bookmarks and which extensions are turned off.
    private static func chromiumProfile() {
        let profile = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/Chromium/Default")
        let tabs = ChromiumImporter.openTabs(profile: profile)
        expect(tabs.map(\.url) == ["https://example.com/one", "https://example.com/two-b"],
               "open tabs: the selected navigation of each, closed tabs and chrome:// pages left out, in window order")
        expect(tabs.map(\.pageTitle) == ["One", "Two, then Ü"], "titles come from the session's UTF-16 strings")
        let marks = ChromiumImporter.bookmarks(profile: profile)
        expect(marks.bar.map(\.pageTitle) == ["Docs", "Reading"] && marks.bar[1].children.map(\.url) == ["https://example.com/read"],
               "the bookmarks bar keeps folders with web pages, drops empty folders and file: links")
        expect(marks.other.map(\.url) == ["https://example.com/other"], "other and mobile bookmarks come after")
        expect(ChromiumImporter.parseSession(Data("SNSS".utf8) + Data([4, 0, 0, 0]) + Data(repeating: 1, count: 16)).isEmpty,
               "an encrypted session (version 4) gives nothing rather than garbage")
        expect(ExtensionImporter.disabledIDs(inProfile: profile).contains("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb")
               && !ExtensionImporter.disabledIDs(inProfile: profile).contains("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"),
               "an extension with disable_reasons is off, one in state 1 is on")
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
        store.recordVisit(url: "https://example.com/a", title: "A")
        expect(store.history["https://example.com/a"]?.lastVisit == clock.now, "history visits use the clock")
        store.archiveLittleWindowPage(url: "https://example.com/little", title: "Little")
        expect(store.archive.first?.archivedAt == clock.now, "a Little Window's page is archived at the clock's time")
        let incognito = store.addIncognitoWindow(frame: nil)
        expect(incognito.focusedSpaceID.flatMap { store.spaces[$0] }?.createdAt == clock.now, "an incognito space is made at the clock's time")
        expect(store.integrityProblems().isEmpty, "and the sidebar stays sound")
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
        b.replace(document: doc)
        expect(b.orderedSpaces[0].profileID == nil && b.integrityProblems().isEmpty, "a space on a missing profile falls back to Default")
    
        // Stopped before the tests below: every service here saves the one sync.json, and this
        // one's debounced save must not land in the middle of theirs.
        syncA.disable()
        iCloudSync(first: a, firstClock: clockA)
        syncGoesOnWithoutAsking()
        syncPutsAMixedBundleRight()
        syncPutsAFileThatNeverArrivesRight()
        syncLeavesAMixToItsWriterOnANewMac()
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
        b.settings.httpsOnly = true
        syncB.poll()
        downloaded = false
        syncA.downloadStatus = { url in url.lastPathComponent == SettingsSync.settingsName && !downloaded ? .notDownloaded : nil }
        syncA.poll()
        downloaded = true
        syncA.poll()
        expect(syncA.pendingChoice == nil && a.settings.httpsOnly, "a setting changed on the second Mac reaches the first without a question")

        // The first two Macs stop here, so that neither's debounced save of sync.json lands between
        // the third Mac's save and its relaunch.
        syncA.disable(); syncB.disable()

        // Cra quit while the first download was still coming in: the question is still asked.
        let clockC = ManualScheduler(now: clockB.now)
        let c = SidebarStore(clock: clockC)
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
