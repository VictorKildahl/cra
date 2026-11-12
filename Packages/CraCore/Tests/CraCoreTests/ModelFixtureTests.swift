import CraCore
import Foundation
import Testing

/// Fixtures/Model/input holds made-up data-folder files: current ones and the shapes older Cra
/// versions wrote. Fixtures/Model/recorded is what Cra saved after loading each of them, recorded
/// from the model code on main (c02cffa) before it moved into CraCore (#51), with JSONStore's
/// encoder and Arc's View ▸ Show Toolbar stubbed on. A file that loads differently from its
/// recording changes what people's settings or sidebars turn into on update.
struct ModelFixtureTests {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// JSONStore's encoder.
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static func data(_ folder: String, _ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures/Model/\(folder)"))
        return try Data(contentsOf: url)
    }

    /// The input as Cra loads it, and the recording, each decoded.
    static func load<T: Codable>(_ name: String, as type: T.Type) throws -> (loaded: T, recorded: T) {
        (try decoder.decode(T.self, from: data("input", name)), try decoder.decode(T.self, from: data("recorded", name)))
    }

    /// Ids the decoder makes up are random per process; the recordings have them zeroed.
    static let zero = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// What SidebarStore does with settings.json: decode, then the one-time toolbar migration.
    static func loadSettings(_ name: String, arcShowsToolbar: Bool? = true) throws -> (loaded: AppSettings, recorded: AppSettings) {
        var (loaded, recorded) = try load(name, as: AppSettings.self)
        loaded.migrateToolbarDefault(arcShowsToolbar: arcShowsToolbar)
        for i in loaded.linkRoutes.indices where loaded.linkRoutes[i].id == LinkRoute.googleMeet.id { loaded.linkRoutes[i].id = zero }
        return (loaded, recorded)
    }

    /// Saving what was loaded and loading it again changes nothing.
    static func roundTrips<T: Codable & Equatable>(_ value: T) throws -> Bool {
        try decoder.decode(T.self, from: encoder.encode(value)) == value
    }

    @Test(arguments: ["sidebar.json", "sidebar-legacy.json", "sidebar-stacked-icon.json", "sidebar-auto-theme.json",
                     "sidebar-plugin-folder.json", "sidebar-image-icon.json"])
    func sidebarLoadsAsRecorded(name: String) throws {
        let (loaded, recorded) = try Self.load(name, as: SidebarDocument.self)
        #expect(loaded == recorded)
        #expect(try Self.roundTrips(loaded))
    }

    /// sidebar.json as Cra 0.1.37 reads it: a live folder's `source` is github or gitlab, and any
    /// other value fails the whole file (it is set aside as corrupt and the sidebar starts empty).
    private struct OlderSidebar: Decodable {
        struct Item: Decodable {
            struct Live: Decodable {
                enum Source: String, Decodable { case github, gitlab }
                var source: Source?
            }
            var id: UUID
            var liveFolder: Live?
        }
        var items: [Item]
    }

    /// A plugin's own folder (Jira here) saves under `pluginFolder`, so an older Cra still opens the
    /// sidebar and shows it as a plain folder with its tabs; a migrated GitHub folder stays a GitHub one.
    @Test func pluginFoldersStayReadableByOlderCra() throws {
        let (loaded, _) = try Self.load("sidebar-plugin-folder.json", as: SidebarDocument.self)
        let saved = try Self.encoder.encode(loaded)
        let older = try Self.decoder.decode(OlderSidebar.self, from: saved)
        let jira = UUID(uuidString: "D0000000-0000-0000-0000-0000000000A1")!
        let github = UUID(uuidString: "D0000000-0000-0000-0000-000000000005")!
        #expect(older.items.first { $0.id == jira }.map { $0.liveFolder == nil } == true)
        #expect(older.items.first { $0.id == github }?.liveFolder?.source == .github)
        let reloaded = try Self.decoder.decode(SidebarDocument.self, from: saved)
        #expect(reloaded.items.first { $0.id == jira }?.liveFolder?.plugin?.id == "cra.jira")
        #expect(reloaded.items.first { $0.id == jira }?.liveFolder?.source == .plugin)
    }

    /// A newer Cra's source this one doesn't know loads as a plugin folder, not as a corrupt file.
    @Test func unknownLiveFolderSourceLoads() throws {
        let live = try Self.decoder.decode(LiveFolderData.self, from: Data(#"{"source":"notion"}"#.utf8))
        #expect(live.source == .plugin)
    }

    /// Auto spaces keep both halves through a load (#155). A dark half without its optional fields
    /// gets them off, and one that can't be read is dropped with its space kept: until 0.1.33 either
    /// set the whole sidebar.json aside as corrupt.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/155"))
    func autoSpacesKeepBothHalves() throws {
        let (loaded, _) = try Self.load("sidebar-auto-theme.json", as: SidebarDocument.self)
        #expect(loaded.spaces.map(\.title) == ["Editor Auto", "Short half", "Broken half"])
        #expect(loaded.spaces.map { $0.theme.followsSystem } == [true, true, true])
        #expect(loaded.spaces.map { $0.theme.dark != nil } == [true, true, false])
        for space in loaded.spaces.prefix(2) {
            #expect(!space.theme.resolved(systemDark: false).isDark && space.theme.resolved(systemDark: true).isDark)
        }
    }

    /// 0.1.31's Edit Space… → Save wrote 🌱 beside an imported space's symbol (#205): the symbol
    /// stays and the emoji goes, so the sidebar draws one icon again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/205"))
    func stackedSpaceIconLoadsAsItsSymbol() throws {
        let (loaded, _) = try Self.load("sidebar-stacked-icon.json", as: SidebarDocument.self)
        #expect(loaded.spaces.map(\.emoji) == [""])
        #expect(loaded.spaces.map(\.icon) == [.symbol("square.on.square.fill")])
    }

    @Test(arguments: ["settings.json", "settings-legacy.json", "settings-empty.json", "settings-bad-routes.json", "settings-long-archive.json"])
    func settingsLoadAsRecorded(name: String) throws {
        let (loaded, recorded) = try Self.loadSettings(name)
        #expect(loaded == recorded)
        #expect(try Self.roundTrips(loaded))
    }

    /// Easels/<id>.json. Since the Easels parity work (Nov 2026) an item carries its place in the stack
    /// as `z`, and link cards and captures sit in `cards`, which Cra 0.1.40 and older don't read
    /// (they'd fail on the whole easel if those were in `items`).
    @Test(arguments: ["easel-0140.json", "easel.json"])
    func easelsLoadAsRecorded(name: String) throws {
        let (loaded, recorded) = try Self.load(name, as: Easel.self)
        #expect(loaded == recorded)
        #expect(try Self.roundTrips(loaded))
        let saved = try #require(JSONSerialization.jsonObject(with: Self.encoder.encode(loaded)) as? [String: Any])
        let file = try #require(JSONSerialization.jsonObject(with: Self.data("recorded", name)) as? [String: Any])
        #expect(NSDictionary(dictionary: saved).isEqual(to: file))
    }

    @Test func easelStackOrderSurvivesTheSplit() throws {
        let (easel, _) = try Self.load("easel.json", as: Easel.self)
        // z: link 0, rectangle 1, capture 2, picture 3, though they are saved in two lists.
        #expect(easel.items.map(\.id.uuidString.first) == ["7", "9", "8", "A"])
        #expect(easel.palette == .vibrant && easel.items[1].shade == .purple && easel.items[3].altText == "A cat")
    }

    @Test func windowsLoadAsRecorded() throws {
        let (loaded, recorded) = try Self.load("windows.json", as: WindowPrefs.self)
        #expect(loaded == recorded)
        #expect(try Self.roundTrips(loaded))

        var (legacy, legacyRecorded) = try Self.load("windows-legacy.json", as: WindowPrefs.self)
        legacy.windows[0].id = Self.zero
        #expect(legacy == legacyRecorded)
    }

    @Test func archiveHistoryAndRankingLoadAsRecorded() throws {
        let archive = try Self.load("archive.json", as: [ArchivedItem].self)
        #expect(archive.loaded == archive.recorded)
        let history = try Self.load("history.json", as: [HistoryEntry].self)
        #expect(history.loaded == history.recorded)
        let ranking = try Self.load("commandbar.json", as: RankingData.self)
        #expect(ranking.loaded == ranking.recorded)
        #expect(try Self.roundTrips(archive.loaded) && Self.roundTrips(history.loaded) && Self.roundTrips(ranking.loaded))
    }

    /// keybindings.json keeps its bytes: KeyChord encodes exactly as the AppKit Shortcut did.
    /// A file from before the priorities (#374) loads with every action at its default.
    @Test func keybindingsSaveByteForByte() throws {
        let loaded = try Self.decoder.decode(KeyBindingOverrides.self, from: Self.data("input", "keybindings.json"))
        #expect(try Self.encoder.encode(loaded) == Self.data("recorded", "keybindings.json"))
        #expect(loaded.shortcuts["nextTab"] == [KeyChord(key: KeyChord.tab, modifiers: 1 << 18), KeyChord(key: KeyChord.right, modifiers: 1 << 20 | 1 << 19)])
        #expect(loaded.priorities.isEmpty)
    }

    /// keybindings.json with priorities (#374): each action's on its chords, kept as written; a value
    /// this Cra doesn't know ("askEveryTime" on reload) loads as the default and is dropped on save.
    /// Cra from before the priorities reads the same shortcuts from it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/374"))
    func keybindingsPrioritiesLoadAsRecorded() throws {
        let input = try Self.data("input", "keybindings-priority.json")
        let loaded = try Self.decoder.decode(KeyBindingOverrides.self, from: input)
        #expect(try Self.encoder.encode(loaded) == Self.data("recorded", "keybindings-priority.json"))
        #expect(loaded.priorities == ["closeTab": .preferWebsites, "find": .useBoth, "nextTab": .preferCra])
        #expect(loaded.priority(for: "reload") == .preferWebsites && loaded.priority(for: "newTab") == .preferCra)
        #expect(try Self.decoder.decode([String: [KeyChord]].self, from: input) == loaded.shortcuts)
        #expect(try Self.roundTrips(loaded))
    }

    /// pinned-extensions.json: the one list of before #107 loads as every profile's and stays an
    /// array when saved; per-profile lists keep an emptied profile's empty list.
    /// protected-media.json (docs/protected-media.md): the Safari's Engine choices and closed toasts,
    /// kept as written; a file from before a key existed loads with that list empty.
    @Test func protectedMediaChoicesLoadAsRecorded() throws {
        let (loaded, recorded) = try Self.load("protected-media.json", as: ProtectedMediaChoices.self)
        #expect(loaded == recorded)
        #expect(try Self.roundTrips(loaded))
        #expect(try Self.encoder.encode(loaded) == Self.data("recorded", "protected-media.json").dropLast(
            try Self.data("recorded", "protected-media.json").last == 0x0A ? 1 : 0))
        let sites = ProtectedMediaSites(extraHosts: loaded.added, removedHosts: loaded.removed)
        #expect(sites.engine(for: "https://www.viaplay.dk/film") == .webKit)
        #expect(sites.engine(for: "https://stream.example.org/") == .webKit)
        #expect(sites.engine(for: "https://www.netflix.com/") == .chromium)
        let empty = try Self.decoder.decode(ProtectedMediaChoices.self, from: Data(#"{"told":["Netflix"]}"#.utf8))
        #expect(empty == ProtectedMediaChoices(told: ["Netflix"]))
        #expect(empty.telling("Netflix") == empty && empty.telling("Max").told == ["Netflix", "Max"])
        #expect(empty.choosing(.webKit, for: "https://www.viaplay.dk/").added == ["www.viaplay.dk"])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/107"), arguments: ["pinned-extensions.json", "pinned-extensions-profiles.json"])
    func pinnedExtensionsLoadAsRecorded(name: String) throws {
        let (loaded, recorded) = try Self.load(name, as: PinnedExtensions.self)
        #expect(loaded == recorded)
        #expect(try Self.roundTrips(loaded))
        if loaded.profiles.isEmpty {
            #expect(try JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) is [String])
            #expect(loaded.ids(inProfile: "Profile B0000000-0000-0000-0000-000000000001") == loaded.shared)
        } else {
            #expect(loaded.ids(inProfile: "Default").isEmpty && loaded.ids(inProfile: "Profile 9") == loaded.shared)
        }
    }

    /// extension-profiles.json (#131): a folder's profiles; a folder it doesn't name loads everywhere.
    @Test func extensionProfilesLoadAsRecorded() throws {
        let (loaded, recorded) = try Self.load("extension-profiles.json", as: ExtensionProfiles.self)
        #expect(loaded == recorded)
        #expect(try Self.roundTrips(loaded))
        #expect(!loaded.loads(folder: "aeblfdkhhhdcdjpifhhbdiojplfjncoa", inProfile: "Default"))
        #expect(loaded.loads(folder: "some-folder", inProfile: "Profile 9"))
    }

    // MARK: What the old shapes turn into

    @Test func legacySidebarGetsWhatTheStoreRepairsFrom() throws {
        let doc = try Self.load("sidebar-legacy.json", as: SidebarDocument.self).loaded
        #expect(doc.favoritesContainerID != nil && doc.profiles == nil)
        let shared = try #require(doc.items.first { $0.id == doc.favoritesContainerID })
        #expect(shared.container == .favorites(spaceID: ContainerKind.sharedFavoritesSpaceID),
                "favorites without a space stand for the container every space shared")
        let tab = try #require(doc.items.first { $0.isTab }?.tab)
        #expect(tab.savedURL == tab.url && tab.savedTitle.isEmpty && !tab.muted)
        #expect(tab.faviconKey == "Calendar.Example.com", "a missing favicon key is the host as written")
        let live = try #require(doc.items.first { $0.isLiveFolder }?.liveFolder)
        #expect(live.lastError == nil, "an error this version doesn't know is dropped, not fatal")
        #expect(live.filter.attributes == .reviewRequests && live.hiddenItems.isEmpty && live.ssoOrganizations.isEmpty)
        let split = try #require(doc.items.first { $0.isSplit }?.split)
        #expect(split == SplitData())
    }

    @Test func legacySettingsMigrate() throws {
        let legacy = try Self.loadSettings("settings-legacy.json").loaded
        #expect(legacy.defaultLinkDestination == .mostRecentSpace && !legacy.openExternalLinksInLittleWindow,
                "Links from other apps → Little Window off becomes the most recent space")
        #expect(legacy.linkRoutes.map(\.text) == ["meet.google.com"], "settings from before Air Traffic Control get Arc's Meet route")
        #expect(legacy.newTabButtonAtTop, "the New Tab row goes back above Today once")
        #expect(legacy.showToolbar, "Arc's toolbar preference wins over the 0.1.0 value")

        let bad = try Self.loadSettings("settings-bad-routes.json").loaded
        #expect(bad.defaultLinkDestination == .littleWindowInUse && bad.linkRoutes.isEmpty)
    }

    @Test func legacyWindowsBecomeOneWindow() throws {
        let prefs = try Self.load("windows-legacy.json", as: WindowPrefs.self).loaded
        #expect(prefs.windows.count == 1 && prefs.sidebarWidth == 300 && prefs.littleWindowSize == nil)
        let w = prefs.windows[0]
        #expect(!w.sidebarVisible && w.frame == "{{0, 0}, {1200, 800}}" && !w.isIncognito)
        #expect(w.selectedTabPerSpace[try #require(w.focusedSpaceID)] != nil)
    }

    // MARK: The toolbar migration, moved out of the decoder

    @Test func decodingNeverReadsArc() throws {
        let settings = try Self.decoder.decode(AppSettings.self, from: Self.data("input", "settings-empty.json"))
        #expect(!settings.toolbarDefaultMigrated && !settings.showToolbar, "the decoder leaves the toolbar for the migration")
    }

    @Test(arguments: [(true as Bool?, true), (false, false), (nil, false)])
    func unmarkedSettingsTakeArcsToolbarOnce(arc: Bool?, shown: Bool) throws {
        var settings = try Self.decoder.decode(AppSettings.self, from: Self.data("input", "settings-legacy.json"))
        settings.migrateToolbarDefault(arcShowsToolbar: arc)
        #expect(settings.showToolbar == shown && settings.toolbarDefaultMigrated)
        settings.migrateToolbarDefault(arcShowsToolbar: !shown)
        #expect(settings.showToolbar == shown, "a second launch keeps the migrated value")
    }

    @Test func markedSettingsNeverAskArc() throws {
        var settings = try Self.decoder.decode(AppSettings.self, from: Self.data("input", "settings.json"))
        settings.migrateToolbarDefault(arcShowsToolbar: { Issue.record("Arc's preference was read"); return false }())
        #expect(settings.showToolbar)
        var fresh = AppSettings()
        fresh.migrateToolbarDefault(arcShowsToolbar: { Issue.record("Arc's preference was read"); return true }())
        #expect(!fresh.showToolbar, "a first launch (no settings.json) starts with the toolbar off")
    }
}
