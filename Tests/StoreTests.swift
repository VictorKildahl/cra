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

        try arcImport()
        chromiumProfile()
        autoArchive()
        tabSleepCadence()
        integrity()
        liveFolderExpiry()
        stampsUseTheClock()
        persistenceFaults()
        incognitoStaysOffDisk()
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

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
            exit(1)
        }
        checks += 1
    }
}
