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

    @Test(arguments: ["sidebar.json", "sidebar-legacy.json"])
    func sidebarLoadsAsRecorded(name: String) throws {
        let (loaded, recorded) = try Self.load(name, as: SidebarDocument.self)
        #expect(loaded == recorded)
        #expect(try Self.roundTrips(loaded))
    }

    @Test(arguments: ["settings.json", "settings-legacy.json", "settings-empty.json", "settings-bad-routes.json"])
    func settingsLoadAsRecorded(name: String) throws {
        let (loaded, recorded) = try Self.loadSettings(name)
        #expect(loaded == recorded)
        #expect(try Self.roundTrips(loaded))
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
    @Test func keybindingsSaveByteForByte() throws {
        let loaded = try Self.decoder.decode([String: [KeyChord]].self, from: Self.data("input", "keybindings.json"))
        #expect(try Self.encoder.encode(loaded) == Self.data("recorded", "keybindings.json"))
        #expect(loaded["nextTab"] == [KeyChord(key: KeyChord.tab, modifiers: 1 << 18), KeyChord(key: KeyChord.right, modifiers: 1 << 20 | 1 << 19)])
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
        #expect(legacy.tabSleep == .oneHour, "a sleep threshold this version doesn't know falls back")
        #expect(legacy.showToolbar, "Arc's toolbar preference wins over the 0.1.0 value")

        let bad = try Self.loadSettings("settings-bad-routes.json").loaded
        #expect(bad.defaultLinkDestination == .littleWindow && bad.linkRoutes.isEmpty)
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
