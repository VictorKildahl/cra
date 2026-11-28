import CraCore
import Foundation
import Testing

/// The sync folder's manifest and when a bundle in it is applied.
struct SettingsSyncTests {
    let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    func manifest(_ device: String, at: TimeInterval = 0, version: Int = SyncManifest.currentVersion) -> SyncManifest {
        SyncManifest(version: version, device: device, deviceID: "id-\(device)", writtenAt: t0.addingTimeInterval(at), files: ["sidebar.json": "a"])
    }

    @Test func manifestRoundTrips() throws {
        let m = SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: t0, files: ["sidebar.json": "abc", "settings.json": "def"])
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        #expect(try d.decode(SyncManifest.self, from: e.encode(m)) == m)
    }

    /// The bundle's items are sorted by their ids' bytes, no longer by `uuidString` (a string made on
    /// every comparison, ~50 ms at 5,000 tabs): the order, and so the bytes written, stay the same.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/615"))
    func itemsSortAsTheirIDStringsDo() {
        var ids = (0..<2_000).map { _ in UUID() }
        // Ids that differ only late, or only in a digit against a letter, as hex sorts them.
        ids += ["00000000-0000-0000-0000-000000000009", "00000000-0000-0000-0000-00000000000A",
                "00000000-0000-0000-0000-0000000000A0", "90000000-0000-0000-0000-000000000000",
                "A0000000-0000-0000-0000-000000000000", "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"].map { UUID(uuidString: $0)! }
        ids.append(ids[7])
        #expect(ids.sorted { SettingsSync.precedes($0, $1) } == ids.sorted { $0.uuidString < $1.uuidString })
        #expect(!SettingsSync.precedes(ids[7], ids[7]))

        var doc = SidebarDocument(spaceOrder: [], spaces: [], items: ids.prefix(300).map { id in
            var item = SidebarItem.tab("https://example.com/\(id)", parent: nil)
            item.id = id
            return item
        })
        let byString = doc.items.sorted { $0.id.uuidString < $1.id.uuidString }
        doc.sortItemsForSync()
        #expect(doc.items == byString)
    }

    @Test func aMacNeverAppliesItsOwnWrite() {
        #expect(!SettingsSync.shouldApply(remote: manifest("Studio"), lastApplied: nil, deviceID: "id-Studio"))
        #expect(SettingsSync.shouldApply(remote: manifest("Studio"), lastApplied: nil, deviceID: "id-MacBook"))
    }

    /// Migration Assistant carries the computer name to the new Mac, so the old and the new one
    /// can both be "Peter's MacBook Pro": the name is only what the question shows.
    @Test func twoMacsWithTheSameNameStillSync() {
        var other = manifest("Peter's MacBook Pro")
        other.deviceID = "old-mac"
        #expect(SettingsSync.shouldApply(remote: other, lastApplied: nil, deviceID: "new-mac"))
        #expect(!SettingsSync.shouldApply(remote: other, lastApplied: nil, deviceID: "old-mac"))
    }


    /// A Blank Window is one Mac's window (Arc's "This Window"): its space and tabs stay there.
    @Test func aBlankWindowsSidebarIsNotSynced() {
        var doc = SidebarDocument.fresh()
        let space = doc.spaces[0]
        let folder = SidebarItem.folder("Work", parent: space.pinnedContainerID)
        let inFolder = SidebarItem.tab("https://example.com/kept", title: "Kept", parent: folder.id)
        doc.items += [folder, inFolder]
        let (blank, containers) = BlankWindow.space(window: UUID(), at: t0)
        let blankTab = SidebarItem.tab("https://example.com/blank", title: "Blank", parent: blank.todayContainerID)
        doc.spaces.append(blank)
        doc.items += containers + [blankTab]
        let synced = doc.forSync()
        #expect(synced.spaces.map(\.id) == [space.id] && synced.spaceOrder == doc.spaceOrder)
        let ids = Set(synced.items.map(\.id))
        #expect(ids.isDisjoint(with: containers.map(\.id) + [blankTab.id]))
        #expect(ids.isSuperset(of: [folder.id, inFolder.id, space.pinnedContainerID]))
        #expect(doc.items.count - synced.items.count == 4)
    }

    @Test func onlyABundleNewerThanTheLastAppliedOneIsApplied() {
        let applied = manifest("Studio", at: 10)
        #expect(!SettingsSync.shouldApply(remote: manifest("Studio", at: 10), lastApplied: applied, deviceID: "id-MacBook"))
        #expect(!SettingsSync.shouldApply(remote: manifest("Studio", at: 5), lastApplied: applied, deviceID: "id-MacBook"))
        #expect(SettingsSync.shouldApply(remote: manifest("Studio", at: 11), lastApplied: applied, deviceID: "id-MacBook"))
        #expect(SettingsSync.shouldApply(remote: manifest("Mini", at: 11), lastApplied: applied, deviceID: "id-MacBook"))
    }

    @Test func aBundleFromANewerCraIsLeftAlone() {
        #expect(!SettingsSync.shouldApply(remote: manifest("Studio", version: SyncManifest.currentVersion + 1), lastApplied: nil, deviceID: "id-MacBook"))
        #expect(SettingsSync.shouldApply(remote: manifest("Studio", version: SyncManifest.currentVersion), lastApplied: nil, deviceID: "id-MacBook"))
    }

    @Test func aBundleIsCompleteOnlyWhenEveryFileMatchesItsHash() {
        let m = SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: t0, files: ["sidebar.json": "a", "settings.json": "b"])
        #expect(SettingsSync.isComplete(m, hashes: ["sidebar.json": "a", "settings.json": "b", "keybindings.json": "c"]))
        #expect(!SettingsSync.isComplete(m, hashes: ["sidebar.json": "a"]))
        #expect(!SettingsSync.isComplete(m, hashes: ["sidebar.json": "a", "settings.json": "old"]))
        #expect(!SettingsSync.isComplete(SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: t0, files: [:]), hashes: [:]))
    }

    // MARK: What a look at the folder found (#378)

    func folder(_ m: SyncManifest, _ files: [String: SyncFileState]) -> SyncFolderState {
        SettingsSync.folderState(manifest: .read(m), files: files, readable: true)
    }
    var written: SyncManifest {
        SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: t0, files: ["sidebar.json": "a", "settings.json": "b", "keybindings.json": "c"])
    }
    let wholeFiles: [String: SyncFileState] = ["sidebar.json": .present(hash: "a"), "settings.json": .present(hash: "b"), "keybindings.json": .present(hash: "c")]

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/378"))
    func aFileOnItsWayIsWaitedFor() {
        var files = wholeFiles
        files["settings.json"] = .downloading
        #expect(folder(written, files) == .arriving, "an iCloud placeholder or a file not downloaded yet")
        files["settings.json"] = .missing
        #expect(folder(written, files) == .arriving, "a file the manifest names that has not landed yet")
        files["settings.json"] = nil
        #expect(folder(written, files) == .arriving)
        #expect(SettingsSync.folderState(manifest: .downloading, files: wholeFiles, readable: true) == .arriving)
        #expect(SettingsSync.folderState(manifest: .missing, files: ["sidebar.json": .downloading], readable: false) == .arriving)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/378"))
    func everyFileThereButNotTheManifestsIsAMix() {
        var files = wholeFiles
        files["settings.json"] = .present(hash: "from-the-other-write")
        #expect(folder(written, files) == .mixed, "files from two writes stay that way: no download is coming")
        #expect(SettingsSync.folderState(manifest: .read(written), files: files, readable: false) == .mixed,
                "a mixed file need not decode: it is written over all the same")
        #expect(SettingsSync.folderState(manifest: .unreadable(version: nil), files: wholeFiles, readable: false) == .mixed,
                "a manifest that is not one is no download either")
        #expect(SettingsSync.folderState(manifest: .unreadable(version: SyncManifest.currentVersion), files: wholeFiles, readable: false) == .mixed)
        #expect(folder(SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: t0, files: [:]), wholeFiles) == .mixed,
                "a manifest that names no files")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/378"))
    func aWholeBundleIsAppliedAndAnEmptyFolderWritten() {
        #expect(folder(written, wholeFiles) == .whole)
        #expect(SettingsSync.folderState(manifest: .missing, files: [:], readable: false) == .empty)
        #expect(SettingsSync.folderState(manifest: .missing, files: wholeFiles, readable: false) == .empty, "files with no manifest are no bundle")
    }

    /// An older Cra never writes over what a newer one wrote: the newer one reads the older
    /// format, not the other way round, and puts a mix right itself.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/378"))
    func aNewerCrasBundleIsNeverWrittenOver() {
        var newer = written
        newer.version = SyncManifest.currentVersion + 1
        #expect(folder(newer, wholeFiles) == .newer)
        var files = wholeFiles
        files["sidebar.json"] = .present(hash: "mixed")
        #expect(folder(newer, files) == .newer, "not even when its files are mixed")
        #expect(SettingsSync.folderState(manifest: .read(written), files: wholeFiles, readable: false) == .newer,
                "the manifest's own files that this Cra can't decode are a newer format")
        #expect(SettingsSync.folderState(manifest: .unreadable(version: SyncManifest.currentVersion + 1), files: wholeFiles, readable: false) == .newer)
        files["sidebar.json"] = .downloading
        #expect(folder(newer, files) == .arriving, "still on its way: looked at again once it is there")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/378"))
    func aManifestsVersionReadsWithoutTheRest() {
        #expect(SettingsSync.manifestVersion(in: Data(#"{"version": 7, "files": "a new shape"}"#.utf8)) == 7)
        #expect(SettingsSync.manifestVersion(in: Data("not json".utf8)) == nil)
    }

    /// A mix that stays put is written over after two looks of the 30-second poll by the Mac
    /// whose manifest it is, after four by another Mac; one that changes waits from the start.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/378"))
    func aMixThatStaysPutIsWrittenOverAfterAWhile() {
        let mix = ["manifest.json": "m", "settings.json": "x"], later = ["manifest.json": "m", "settings.json": "y"]
        /// Whether each look (seconds after the first, files seen) writes, for one Mac.
        func looks(_ steps: [(TimeInterval, [String: String])], wroteManifest: Bool, resetBefore: Int? = nil) -> [Bool] {
            var wait = SyncMixWait()
            return steps.enumerated().map { i, step in
                if i == resetBefore { wait.reset() }
                return wait.shouldRewrite(step.1, at: t0.addingTimeInterval(step.0), wroteManifest: wroteManifest)
            }
        }
        #expect(looks([(0, mix), (30, mix), (60, mix)], wroteManifest: true) == [false, false, true],
                "the Mac whose manifest it is writes its bundle again on the third look")
        #expect(looks([(0, mix), (90, mix), (120, mix)], wroteManifest: false) == [false, false, true],
                "another Mac leaves the writer time first, but does not wait for ever")
        #expect(looks([(0, mix), (50, later), (100, later), (110, later)], wroteManifest: true) == [false, false, false, true],
                "a file changed: a provider is still delivering, and the wait starts again")
        #expect(looks([(0, mix), (60, mix), (200, mix)], wroteManifest: true, resetBefore: 2) == [false, true, false],
                "after a whole bundle a later mix waits from the start")
    }

    /// A file the manifest names that isn't there, with nothing on its way, is no download: it is
    /// waited for like a mix, not for ever.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/378"))
    func aFileWithNothingOnItsWayIsLacking() {
        var files = wholeFiles
        #expect(!SettingsSync.isLacking(manifest: .read(written), files: files), "a whole bundle")
        files["settings.json"] = .missing
        #expect(SettingsSync.isLacking(manifest: .read(written), files: files), "deleted, or left out by a provider")
        files["settings.json"] = nil
        #expect(SettingsSync.isLacking(manifest: .read(written), files: files))
        files["sidebar.json"] = .downloading
        #expect(!SettingsSync.isLacking(manifest: .read(written), files: files), "another file is still downloading: looked at once it is there")
        var newer = written
        newer.version = SyncManifest.currentVersion + 1
        #expect(!SettingsSync.isLacking(manifest: .read(newer), files: ["sidebar.json": .present(hash: "a")]), "a newer Cra's bundle is never written over")
        #expect(!SettingsSync.isLacking(manifest: .downloading, files: [:]))
        #expect(!SettingsSync.isLacking(manifest: .missing, files: [:]), "no manifest: an empty folder, written at once")
    }

    /// A lacking file waits a minute on the Mac that wrote the manifest and ten on another Mac;
    /// a Mac that has not synced yet never writes over another Mac's bundle.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/378"))
    func aLackingFileWaitsLongerAndANewMacLeavesItToTheWriter() {
        let lacking = ["manifest.json": "m", "sidebar.json": "a"]
        func looks(_ times: [TimeInterval], wroteManifest: Bool, lacking isLacking: Bool, synced: Bool) -> [Bool] {
            var wait = SyncMixWait()
            return times.map { wait.shouldRewrite(lacking, at: t0.addingTimeInterval($0), wroteManifest: wroteManifest, lacking: isLacking, synced: synced) }
        }
        #expect(looks([0, 30, 60], wroteManifest: true, lacking: true, synced: true) == [false, false, true],
                "the Mac that wrote the manifest knows nothing more is coming")
        #expect(looks([0, 120, 570, 600], wroteManifest: false, lacking: true, synced: true) == [false, false, false, true],
                "another Mac gives a provider ten minutes to list the file")
        #expect(looks([0, 120, 600, 3600], wroteManifest: false, lacking: false, synced: false) == [false, false, false, false],
                "a Mac not asked yet which sidebar to keep never writes over a mix")
        #expect(looks([0, 600, 3600], wroteManifest: false, lacking: true, synced: false) == [false, false, false],
                "nor over a lacking bundle")
        #expect(looks([0, 60], wroteManifest: true, lacking: false, synced: false) == [false, true],
                "its own manifest it writes again: sync was turned off and on on the Mac that wrote it")
    }

    // MARK: Easels in the bundle

    let easelID = UUID(uuidString: "9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F")!
    var easelJSON: String { "Easels/\(easelID.uuidString).json" }
    var easelPicture: String { "Easels/\(easelID.uuidString)/D0D0D0D0-0000-4000-8000-000000000000.png" }
    /// `written`, carrying one easel and its picture.
    var withEasel: SyncManifest {
        var m = written
        m.easels = [easelJSON: "e", easelPicture: "p"]
        return m
    }
    var withEaselFiles: [String: SyncFileState] {
        wholeFiles.merging([easelJSON: .present(hash: "e"), easelPicture: .present(hash: "p")]) { a, _ in a }
    }

    /// Easels go under their own key, so an older Cra, which reads only the three names in `files`,
    /// still finds its bundle whole; a manifest without the key comes from such a Cra.
    @Test func aManifestCarriesItsEaselsBesideItsFiles() throws {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        #expect(try d.decode(SyncManifest.self, from: e.encode(withEasel)) == withEasel)
        #expect(withEasel.files == written.files && withEasel.version == 1)
        let older = try d.decode(SyncManifest.self, from: e.encode(written))
        #expect(older.easels == nil)
        let json = try #require(JSONSerialization.jsonObject(with: e.encode(written)) as? [String: Any])
        #expect(json["easels"] == nil, "nothing new in a manifest without easels")
        #expect(SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: t0, files: [:], easels: [easelJSON: "e"]).easels == [easelJSON: "e"])
    }

    @Test func aBundlePathNamesAnEaselOrOneOfItsPictures() throws {
        let json = try #require(SettingsSync.easelPath(easelJSON))
        #expect(json.id == easelID && json.picture == nil)
        let picture = try #require(SettingsSync.easelPath(easelPicture))
        #expect(picture.id == easelID && picture.picture == "D0D0D0D0-0000-4000-8000-000000000000.png")
    }

    /// The service reads and writes only what this lets through, so a manifest can't name a file
    /// outside the bundle's easels or the data folder's.
    @Test(arguments: [
        "Easels/../sidebar.json", "Easels/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F/../../x", "Easels/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F/..",
        "/Easels/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F.json", "Easels//9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F.json",
        "Easels/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F//a.png", "Easels/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F/a/b.png",
        "Easels/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F/", "Easels/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F/.a.png.icloud",
        "Easels/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F.json.bak", "Easels/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F",
        "Easels/9b1c6c2e-3e9a-4d2b-9d7e-1a2b3c4d5e6f.json", "Easels/Board.json", "Easels/Board/a.png", "Easels/.json",
        "Easels", "Easels/", "sidebar.json", "Pictures/9B1C6C2E-3E9A-4D2B-9D7E-1A2B3C4D5E6F.json", "",
    ])
    func anyOtherPathIsNoEasel(path: String) {
        #expect(SettingsSync.easelPath(path) == nil)
    }

    @Test func aBundleWithEaselsIsCompleteOnlyWhenTheyMatchToo() {
        let hashes = ["sidebar.json": "a", "settings.json": "b", "keybindings.json": "c", easelJSON: "e", easelPicture: "p"]
        #expect(SettingsSync.isComplete(withEasel, hashes: hashes))
        #expect(!SettingsSync.isComplete(withEasel, hashes: hashes.filter { $0.key != easelPicture }))
        #expect(!SettingsSync.isComplete(withEasel, hashes: hashes.merging([easelJSON: "old"]) { _, b in b }))
        var bad = withEasel
        bad.easels?["Easels/../sidebar.json"] = "a"
        #expect(!SettingsSync.isComplete(bad, hashes: hashes.merging(["Easels/../sidebar.json": "a"]) { _, b in b }))
    }

    @Test func aWholeBundleWithEaselsIsApplied() {
        #expect(folder(withEasel, withEaselFiles) == .whole)
        #expect(SettingsSync.folderState(manifest: .read(withEasel), files: withEaselFiles, readable: false) == .newer)
    }

    @Test func anEaselOnItsWayIsWaitedFor() {
        var files = withEaselFiles
        files[easelPicture] = .downloading
        #expect(folder(withEasel, files) == .arriving, "a picture iCloud has not downloaded yet")
        #expect(!SettingsSync.isLacking(manifest: .read(withEasel), files: files))
        files[easelPicture] = .missing
        #expect(folder(withEasel, files) == .arriving)
        files[easelPicture] = nil
        #expect(folder(withEasel, files) == .arriving)
    }

    @Test func anEaselWithNothingOnItsWayIsLacking() {
        #expect(!SettingsSync.isLacking(manifest: .read(withEasel), files: withEaselFiles))
        var files = withEaselFiles
        files[easelJSON] = .missing
        #expect(SettingsSync.isLacking(manifest: .read(withEasel), files: files))
        files[easelJSON] = nil
        #expect(SettingsSync.isLacking(manifest: .read(withEasel), files: files))
    }

    @Test func anEaselFromAnotherWriteIsAMix() {
        var files = withEaselFiles
        files[easelJSON] = .present(hash: "from-the-other-write")
        #expect(folder(withEasel, files) == .mixed)
    }

    /// A manifest path that is no easel's is never read: it counts as missing, so the bundle is
    /// waited for and then written over, which leaves the path out.
    @Test func aPathThatIsNoEaselsCountsAsMissing() {
        var bad = withEasel
        bad.easels?["Easels/../sidebar.json"] = "a"
        var files = withEaselFiles
        files["Easels/../sidebar.json"] = .present(hash: "a")
        #expect(folder(bad, files) == .arriving)
        #expect(SettingsSync.isLacking(manifest: .read(bad), files: files))
    }

    /// A bundle an older Cra wrote names no easels: it is whole on its three files, whatever easel
    /// files the folder still holds.
    @Test func aManifestWithoutEaselsLooksAsBefore() {
        #expect(written.easels == nil)
        #expect(folder(written, withEaselFiles) == .whole)
        var files = withEaselFiles
        files[easelJSON] = .missing
        files[easelPicture] = .present(hash: "changed")
        #expect(folder(written, files) == .whole)
        #expect(!SettingsSync.isLacking(manifest: .read(written), files: files))
        #expect(SettingsSync.isComplete(written, hashes: ["sidebar.json": "a", "settings.json": "b", "keybindings.json": "c"]))
    }

    @Test func anICloudPlaceholderHasTheFilesNameWithADotAndIcloud() {
        #expect(SettingsSync.placeholderName(for: "sidebar.json") == ".sidebar.json.icloud")
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
        let m = SyncManifest(device: "Studio", deviceID: "id-Studio", writtenAt: t0, files: [:])
        let summary = SyncBundleSummary(manifest: m, document: doc)
        #expect(summary.device == "Studio" && summary.spaces == 1 && summary.tabs == 1)
    }

    /// GitHub #598: a change made here waited for the next 30-second look before it was written. It is
    /// written 3 s after the last change, unless all that changed is when tabs were last active (a tab
    /// switch), which goes up with the next look as before.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/598"))
    func onlyARealChangeIsWrittenSoon() {
        #expect(SettingsSync.writeSoonDelay == 3)
        var tab = SidebarItem.tab("https://example.com", title: "Example", parent: nil)
        var split = SidebarItem.split(parent: nil)
        let doc = SidebarDocument(spaceOrder: [], spaces: [], items: [tab, split])
        // A tab switch: last active times and a split's focused pane.
        if case .tab(var t) = tab.data { t.timeLastActiveAt = t0; tab.data = .tab(t) }
        if case .split(var s) = split.data { s.timeLastActiveAt = t0; s.focusTabID = tab.id; split.data = .split(s) }
        let switched = SidebarDocument(spaceOrder: [], spaces: [], items: [tab, split])
        #expect(switched != doc && switched.withoutActivity() == doc.withoutActivity())
        // A rename, a mute, a move: written soon.
        var renamed = switched
        renamed.items[0].title = "Renamed"
        #expect(renamed.withoutActivity() != switched.withoutActivity())
        var muted = switched
        if case .tab(var t) = muted.items[0].data { t.muted = true; muted.items[0].data = .tab(t) }
        #expect(muted.withoutActivity() != switched.withoutActivity())
    }

    // MARK: An easel file on this Mac, as a write sends it

    @Test func anEaselReadNowIsSent() {
        #expect(SettingsSync.easelChoice(readable: true, lastCopy: true, remembered: true) == .send)
    }

    /// Read mid-save, or bytes that don't decode: never sent as deleted while a copy from before is at hand.
    @Test func anEaselNotReadNowCarriesItsLastCopy() {
        #expect(SettingsSync.easelChoice(readable: false, lastCopy: true, remembered: true) == .carry)
    }

    /// Left out, an easel a remembered bundle holds would be deleted on the other Mac.
    @Test func anEaselNotReadWithNoCopyThatABundleHeldHoldsTheWrite() {
        #expect(SettingsSync.easelChoice(readable: false, lastCopy: false, remembered: true) == .hold)
    }

    /// No bundle held it, so no Mac merges against it: leaving it out deletes nothing.
    @Test func anEaselNotReadThatNoBundleHeldIsLeftOut() {
        #expect(SettingsSync.easelChoice(readable: false, lastCopy: false, remembered: false) == .leaveOut)
    }

    /// A listing that failed is not proof that every easel was deleted: the other Mac would delete its copies.
    @Test func anEaselFolderThatCannotBeListedHoldsTheWrite() {
        #expect(SettingsSync.unlistedEaselsChoice(missing: false) == .hold)
    }

    /// No easel made yet: the folder isn't there, and that is no easels.
    @Test func aMissingEaselFolderListsAsNoEasels() {
        #expect(SettingsSync.unlistedEaselsChoice(missing: true) == .leaveOut)
    }

    @Test func theHistoryKnowsTheEaselsItsBundlesHeld() {
        var history = SyncHistory()
        let held = Easel(title: "Held"), other = UUID()
        history.remember(UUID(), .fresh(), easels: [held])
        history.remember(UUID(), .fresh())
        #expect(history.remembers(easel: held.id) && !history.remembers(easel: other))
    }
}
