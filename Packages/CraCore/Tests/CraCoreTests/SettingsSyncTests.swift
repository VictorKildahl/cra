import CraCore
import Foundation
import Testing

/// The sync folder's manifest and when a bundle in it is applied.
struct SettingsSyncTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    func manifest(_ device: String, at: TimeInterval = 0, version: Int = SyncManifest.currentVersion) -> SyncManifest {
        SyncManifest(version: version, device: device, writtenAt: t0.addingTimeInterval(at), files: ["sidebar.json": "a"])
    }

    @Test func manifestRoundTrips() throws {
        let m = SyncManifest(device: "Studio", writtenAt: t0, files: ["sidebar.json": "abc", "settings.json": "def"])
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        #expect(try d.decode(SyncManifest.self, from: e.encode(m)) == m)
    }

    @Test func aMacNeverAppliesItsOwnWrite() {
        #expect(!SettingsSync.shouldApply(remote: manifest("Studio"), lastApplied: nil, device: "Studio"))
        #expect(SettingsSync.shouldApply(remote: manifest("Studio"), lastApplied: nil, device: "MacBook"))
    }

    @Test func onlyABundleNewerThanTheLastAppliedOneIsApplied() {
        let applied = manifest("Studio", at: 10)
        #expect(!SettingsSync.shouldApply(remote: manifest("Studio", at: 10), lastApplied: applied, device: "MacBook"))
        #expect(!SettingsSync.shouldApply(remote: manifest("Studio", at: 5), lastApplied: applied, device: "MacBook"))
        #expect(SettingsSync.shouldApply(remote: manifest("Studio", at: 11), lastApplied: applied, device: "MacBook"))
        #expect(SettingsSync.shouldApply(remote: manifest("Mini", at: 11), lastApplied: applied, device: "MacBook"))
    }

    @Test func aBundleFromANewerCraIsLeftAlone() {
        #expect(!SettingsSync.shouldApply(remote: manifest("Studio", version: SyncManifest.currentVersion + 1), lastApplied: nil, device: "MacBook"))
        #expect(SettingsSync.shouldApply(remote: manifest("Studio", version: SyncManifest.currentVersion), lastApplied: nil, device: "MacBook"))
    }

    @Test func aBundleIsCompleteOnlyWhenEveryFileMatchesItsHash() {
        let m = SyncManifest(device: "Studio", writtenAt: t0, files: ["sidebar.json": "a", "settings.json": "b"])
        #expect(SettingsSync.isComplete(m, hashes: ["sidebar.json": "a", "settings.json": "b", "keybindings.json": "c"]))
        #expect(!SettingsSync.isComplete(m, hashes: ["sidebar.json": "a"]))
        #expect(!SettingsSync.isComplete(m, hashes: ["sidebar.json": "a", "settings.json": "old"]))
        #expect(!SettingsSync.isComplete(SyncManifest(device: "Studio", writtenAt: t0, files: [:]), hashes: [:]))
    }

    @Test func providersConflictCopiesAreNeverRead() {
        #expect(SettingsSync.isConflictCopy("manifest 2.json"))
        #expect(SettingsSync.isConflictCopy("manifest (Peter's conflicted copy 2026-11-06).json"))
        #expect(SettingsSync.isConflictCopy("manifest-MacBook.json"))
        #expect(!SettingsSync.isConflictCopy("manifest.json"))
        #expect(!SettingsSync.isConflictCopy("sidebar.json"))
    }

    @Test func anICloudPlaceholderHasTheFilesNameWithADotAndIcloud() {
        #expect(SettingsSync.placeholderName(for: "sidebar.json") == ".sidebar.json.icloud")
        #expect(!SettingsSync.isConflictCopy(SettingsSync.placeholderName(for: "manifest.json")))
    }

    @Test func settingsForSyncLeaveOutWhatIsEachMacsOwn() {
        var s = AppSettings()
        s.httpsOnly = true
        s.searchEngine = .duckduckgo
        s.setDownloadLocation(DownloadLocation(folder: "/Volumes/Work"), profileID: nil)
        s.hasSeenImportPrompt = true
        s.perfRecording = !AppSettings.perfRecordingDefault
        s.perfHidesSiteNames = true
        let synced = s.forSync()
        #expect(synced.httpsOnly && synced.searchEngine == .duckduckgo)
        #expect(synced.downloadLocations.isEmpty && !synced.hasSeenImportPrompt)
        #expect(synced.perfRecording == AppSettings.perfRecordingDefault && !synced.perfHidesSiteNames)
    }

    @Test func applyingSyncedSettingsKeepsThisMacsOwn() {
        var mine = AppSettings()
        mine.setDownloadLocation(DownloadLocation(askWhereToSave: true), profileID: nil)
        mine.hasSeenImportPrompt = true
        mine.chromeEngine = false
        mine.perfHidesSiteNames = true
        var remote = AppSettings()
        remote.httpsOnly = true
        remote.autoArchive = .sevenDays
        remote.toolbarDefaultMigrated = false
        let merged = mine.applyingSynced(remote)
        #expect(merged.httpsOnly && merged.autoArchive == .sevenDays)
        #expect(merged.downloadLocation(profileID: nil).askWhereToSave && merged.hasSeenImportPrompt)
        #expect(!merged.chromeEngine && merged.perfHidesSiteNames)
        #expect(merged.toolbarDefaultMigrated, "a migration never runs again because of a synced file")
    }

    @Test func aBundleSummaryCountsSpacesAndTabs() {
        var doc = SidebarDocument.fresh()
        let space = doc.spaces[0]
        doc.items.append(SidebarItem.tab("https://example.com", title: "Example", parent: space.pinnedContainerID))
        let m = SyncManifest(device: "Studio", writtenAt: t0, files: [:])
        let summary = SyncBundleSummary(manifest: m, document: doc)
        #expect(summary.device == "Studio" && summary.spaces == 1 && summary.tabs == 1)
    }
}
