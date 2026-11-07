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
        autoArchive()
        tabSleepCadence()
        tabRestTimes()
        integrity()
        liveFolderExpiry()
        liveFolderSignIn()
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
        pinnedURL()
        tabFavicons()
        moveTabToSpace()
        folderPeek()
        collapsedPinnedPeek()
        closeSuccessor()
        favoritesEmptyState()
        sharedFavorites()
        themePreview()
        try arcSpacesWithoutAThemeShareOneDefault()
        try arcItemListedTwice()
        try arcLiveFolderImportsLive()
        littleWindowProfile()
        tidyTabs()
        pinHook()
        dropOnPinnedTabSplits()
        reopenClosedTabs()
        windowsShareTheSidebar()
        blankWindows()
        blankWindowWithoutItsWindow()
        tornOffTabMovesToABlankWindow()
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
        arcProfiles(plan: plan, store: composition.store)
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
        expect(ExtensionImporter.disabledIDs(inProfile: profile) == ["bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"],
               "an extension with disable_reasons is off, one in state 1 is on")
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

    /// GitHub's answers that mean "sign in" never read as an empty folder (6 Nov 2026: a lapsed
    /// Enterprise Managed User session landed on the enterprise's SSO page and emptied the folder).
    private static func liveFolderSignIn() {
        let ssoPage = #"<html><meta name="user-login" content="vkp_jysk"><script type="application/json" id="client-env">{"locale":"en"}</script></html>"#
        expect(GitHubLiveClient.read(status: 200, finalURL: "https://github.com/enterprises/jysk-emu/sso?return_to=%2Fpulls", body: ssoPage) == .failure(.notSignedIn),
               "a fetch sent to the enterprise's single sign-on needs a sign-in")
        expect(GitHubLiveClient.read(status: 200, finalURL: "https://github.com/orgs/jysk-dev/sso", body: ssoPage) == .failure(.notSignedIn),
               "so does an organization's")
        expect(GitHubLiveClient.enterprise(inSSO: "https://github.com/enterprises/jysk-emu/sso?return_to=%2Fpulls") == "jysk-emu",
               "the folder learns the enterprise from where its fetch landed")
        expect(GitHubLiveClient.read(status: 200, finalURL: "https://github.com/dashboard", body: ssoPage) == .failure(.unexpectedPage),
               "an empty page that isn't the pulls or search page is no answer")
        let empty = #"{"payload":{"pullsDashboardSurfaceContentRoute":{"results":[],"pageInfo":{},"error":null}}}"#
        expect(GitHubLiveClient.read(status: 200, finalURL: "https://github.com/pulls?q=is%3Apr", body: empty) == .success(.init()),
               "the pulls page with no results is an empty folder")
        expect(GitHubLiveClient.read(status: 404, finalURL: "https://github.com/pulls?q=is%3Apr", body: #"{"error":"Couldn’t authenticate you"}"#) == .failure(.notSignedIn),
               "signed out, the pulls page can't authenticate you")
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
        let rds = store.createTab(url: "https://console.aws.amazon.com/rds/home", select: false)
        let eks = store.createTab(url: "https://console.aws.amazon.com/eks/home", select: false)
        let rdsIcon = FaviconKey.key(for: "https://console.aws.amazon.com/rds/home", iconURL: "https://console.aws.amazon.com/rds/favicon.ico")!
        let eksIcon = FaviconKey.key(for: "https://console.aws.amazon.com/eks/home", iconURL: "https://console.aws.amazon.com/eks/favicon.ico")!
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
        let existing = store.tabGroups(in: sid).map { $0.title ?? "" }
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
