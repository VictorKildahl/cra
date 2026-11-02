import Foundation

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
        integrity()
        liveFolderExpiry()
        stampsUseTheClock()
        persistenceFaults()
        incognitoStaysOffDisk()
        pinnedURL()
        moveTabToSpace()
        folderPeek()
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

    /// Tab sleeping asks the windows once a minute, and only while it is turned on.
    @MainActor
    private static func tabSleepCadence() {
        let clock = ManualScheduler()
        let composition = AppComposition(clock: clock)
        composition.store.settings.tabSleepEnabled = true
        var passes = 0
        composition.startPeriodicWork { passes += 1 }
        clock.advance(by: 59)
        expect(passes == 0, "no pass before the first minute")
        clock.advance(by: 1)
        expect(passes == 1, "a pass every minute")
        clock.advance(by: 9 * 60)
        expect(passes == 10, "ten passes in ten minutes")
        composition.store.settings.tabSleepEnabled = false
        clock.advance(by: 10 * 60)
        expect(passes == 10, "no passes while tab sleeping is off")
        composition.startPeriodicWork { passes += 100 }
        expect(clock.pendingCount == 2, "starting again replaces the timers instead of adding to them")
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
        expect(store.selectedTabID(in: home) == stay.id, "the space it left goes back to the tab it came from")
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

        let incognito = store.addIncognitoWindow(frame: nil)
        let secret = store.createTab(url: "https://example.com/secret", window: incognito.id)
        expect(!store.moveTabAndFollow(secret.id, toSpace: home, window: incognito.id)
               && store.isIncognito(item: secret.id) && store.focusedSpaceID(window: incognito.id) != home,
               "an incognito tab never leaves its window")
        expect(store.integrityProblems().isEmpty, "the sidebar stays sound")
    }

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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
