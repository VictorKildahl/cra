import CraCEF
import Foundation

@main
@MainActor
enum ExtensionStoreMigrationTests {
    static var checks = 0
    static var failures: [String] = []
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/ExtensionMigration", isDirectory: true)
    static let key = "dGVzdC1leHRlbnNpb24ta2V5"

    @MainActor
    struct Install {
        let id: String
        let copy: URL
        let profile: URL
        var destination: URL { profile.appendingPathComponent("Extensions/\(id)/1.0_0", isDirectory: true) }
        var relativePath: String { "\(id)/1.0_0" }

        func settings(path: String? = nil) -> [String: Any] {
            [id: ["location": 1, "from_webstore": true, "path": path ?? relativePath]]
        }

        func writeSettings(_ settings: [String: Any], in directory: URL? = nil) throws {
            let directory = directory ?? profile
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["extensions": ["settings": settings]])
                .write(to: directory.appendingPathComponent("Secure Preferences"))
        }

        func liveSettings(_ settings: [String: Any], profile: String = "Default") throws {
            let key = profile == "Default" ? profile : AppPaths.chromiumCache.appendingPathComponent(profile, isDirectory: true).path
            CraCEFRuntime.settingsByProfile[key] = String(decoding: try JSONSerialization.data(withJSONObject: settings), as: UTF8.self)
        }

        func installStoreCopy() throws {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: fixture, to: destination)
        }
    }

    static func check(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition {
            failures.append(message)
            print("FAIL: \(message)")
        }
    }

    static func run(_ name: String, _ body: (Install) throws -> Void) throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CRA_DATA_DIR"]!, isDirectory: true)
        AppPaths.supportDir = root.appendingPathComponent(name, isDirectory: true)
        CraCEFRuntime.settingsByProfile = [:]
        let id = ExtensionStore.chromiumID(key: key, folder: fixture)
        let copy = ExtensionStore.directory.appendingPathComponent(id, isDirectory: true)
        let profile = AppPaths.chromiumCache.appendingPathComponent("Default", isDirectory: true)
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: copy)
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try body(Install(id: id, copy: copy, profile: profile))
    }

    /// A data folder with a keyless extension's own folder, "Load unpacked" in Default, and the
    /// copy Add Unpacked Extension… made of it in Extensions/ (GitHub #299).
    static func unpackedCopy(_ name: String, manifestName: String = "My Extension",
                             _ body: (_ copy: URL, _ original: URL, _ profile: URL) throws -> Void) throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CRA_DATA_DIR"]!, isDirectory: true)
        AppPaths.supportDir = root.appendingPathComponent(name, isDirectory: true)
        CraCEFRuntime.settingsByProfile = [:]
        let fm = FileManager.default
        let original = root.appendingPathComponent("\(name)-code/my-extension", isDirectory: true)
        let copy = ExtensionStore.directory.appendingPathComponent("my-extension", isDirectory: true)
        for (folder, title) in [(original, "My Extension"), (copy, manifestName)] {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["manifest_version": 3, "name": title, "version": "1.0"])
                .write(to: folder.appendingPathComponent("manifest.json"))
        }
        let profile = AppPaths.chromiumCache.appendingPathComponent("Default", isDirectory: true)
        try fm.createDirectory(at: profile, withIntermediateDirectories: true)
        try body(copy, original, profile)
    }

    static func writeSettings(_ settings: [String: Any], in profile: URL) throws {
        try FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: ["extensions": ["settings": settings]])
            .write(to: profile.appendingPathComponent("Secure Preferences"))
    }

    // promise: #299
    static func unpackedCopiesStepAside() throws {
        func inPlace(_ original: URL) -> [String: Any] {
            [ExtensionStore.chromiumID(key: nil, folder: original): ["location": 4, "path": original.path]]
        }
        func asCommandLine(_ copy: URL) -> [String: Any] {
            [ExtensionStore.chromiumID(key: nil, folder: copy): ["location": 8, "path": copy.path]]
        }

        try unpackedCopy("unpacked-copy-in-place") { copy, original, profile in
            try writeSettings(inPlace(original).merging(asCommandLine(copy)) { a, _ in a }, in: profile)
            check(ExtensionStore.loadList().paths.isEmpty,
                  "a copy of a folder Default loads unpacked is not loaded again with --load-extension (#299)")
            check(!FileManager.default.fileExists(atPath: copy.path), "a copy no profile loads goes")
            check(FileManager.default.fileExists(atPath: original.appendingPathComponent("manifest.json").path), "the person's own folder stays")
            let entries = ExtensionStore().entries
            check(entries.count == 1 && entries.first?.url.standardizedFileURL == original.standardizedFileURL,
                  "the extension is listed once, from its own folder")
        }

        try unpackedCopy("unpacked-copy-profile-busy") { copy, original, profile in
            try writeSettings(inPlace(original), in: profile)
            check(ExtensionStore.loadList(profileIsFree: false).paths == [copy.path],
                  "another Cra that owns the profile keeps the copy it may be reading")
            check(FileManager.default.fileExists(atPath: copy.path), "nothing is deleted while the profile is in use")
        }

        try unpackedCopy("unpacked-copy-other-profile") { copy, original, profile in
            try writeSettings(inPlace(original), in: profile)
            try writeSettings(asCommandLine(copy), in: AppPaths.chromiumCache.appendingPathComponent("Profile 1", isDirectory: true))
            let list = ExtensionStore.loadList()
            check(list.paths == [copy.path] && list.profiles == "Profile 1",
                  "the copy keeps loading in a profile that doesn't load the folder in place")
        }

        try unpackedCopy("unpacked-copy-live") { copy, original, _ in
            // This session loaded the copy, then the person loaded the folder in chrome://extensions.
            let live = inPlace(original).merging(asCommandLine(copy)) { a, _ in a }
            CraCEFRuntime.settingsByProfile["Default"] = String(decoding: try JSONSerialization.data(withJSONObject: live), as: UTF8.self)
            let store = ExtensionStore()
            store.reload()
            check(store.entries.count == 1 && store.entries.first?.managedByChrome == true,
                  "Cra's extension list shows the extension once while both are loaded")
            check(FileManager.default.fileExists(atPath: copy.path), "the copy Chromium has loaded stays until the next launch")
        }

        try unpackedCopy("unpacked-copy-other-extension", manifestName: "Not My Extension") { copy, original, profile in
            try writeSettings(inPlace(original), in: profile)
            check(ExtensionStore.loadList().paths == [copy.path], "another extension in a folder of the same name keeps loading")
        }
    }

    /// Remove in chrome://extensions deletes only Chromium's record of an extension it loaded with
    /// --load-extension; Cra's folder stays and loaded it again at the next launch, so an imported
    /// extension could be turned off but not removed.
    static func removedCopiesStayRemoved() throws {
        func loaded(_ install: Install) -> [String: Any] { [install.id: ["location": 8, "path": install.copy.path]] }

        try run("copy-removed-in-chrome-extensions") { install in
            try install.liveSettings(loaded(install))
            let store = ExtensionStore()
            try install.liveSettings([:])
            store.reload()
            check(!FileManager.default.fileExists(atPath: install.copy.path), "a removed imported extension's copy goes")
            check(ExtensionStore.loadList().paths.isEmpty, "a removed imported extension does not come back at the next launch")
            check(store.entries.isEmpty, "the removed extension leaves Cra's list at once")
        }

        try run("copy-removed-in-one-profile") { install in
            try FileManager.default.createDirectory(at: AppPaths.chromiumCache.appendingPathComponent("Profile 1", isDirectory: true),
                                                    withIntermediateDirectories: true)
            try install.liveSettings(loaded(install))
            try install.liveSettings(loaded(install), profile: "Profile 1")
            let store = ExtensionStore()
            try install.liveSettings([:])
            store.reload()
            check(FileManager.default.fileExists(atPath: install.copy.appendingPathComponent("payload.txt").path),
                  "a copy another profile still loads stays")
            check(ExtensionStore.loadProfiles().profiles(ofFolder: install.id) == ["Profile 1"],
                  "only the profile it was removed from stops loading it")
        }

        try run("copy-turned-off-not-removed") { install in
            try install.liveSettings(loaded(install))
            let store = ExtensionStore()
            try install.liveSettings([install.id: ["location": 8, "path": install.copy.path, "disable_reasons": [1]]])
            store.reload()
            check(ExtensionStore.loadList().paths == [install.copy.path], "a turned-off extension keeps loading (off)")
        }

        try run("copy-live-settings-gone") { install in
            try install.liveSettings(loaded(install))
            let store = ExtensionStore()
            CraCEFRuntime.settingsByProfile = [:]
            store.reload()
            check(ExtensionStore.loadList().paths == [install.copy.path], "a profile shutting down removed nothing")
        }

        try unpackedCopy("added-unpacked-removed") { copy, _, _ in
            CraCEFRuntime.settingsByProfile["Default"] = String(decoding: try JSONSerialization.data(withJSONObject:
                [ExtensionStore.chromiumID(key: nil, folder: copy): ["location": 8, "path": copy.path]]), as: UTF8.self)
            let store = ExtensionStore()
            CraCEFRuntime.settingsByProfile["Default"] = "{}"
            store.reload()
            check(!FileManager.default.fileExists(atPath: copy.path), "Add Unpacked Extension…'s copy goes when it is removed")
            check(ExtensionStore.loadList().paths.isEmpty, "and stays removed")
        }
    }

    /// An incognito window lists, pins and runs only the extensions its profile allows in incognito
    /// (chrome://extensions ▸ Allow in Incognito, `incognito` in extensions.settings), as Chrome's toolbar
    /// does for an off-the-record profile. Cra listed every turned-on one there, and those did nothing.
    // promise: #620
    static func incognitoListsOnlyAllowed() throws {
        let root = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CRA_DATA_DIR"]!, isDirectory: true)
        AppPaths.supportDir = root.appendingPathComponent("incognito-allowed", isDirectory: true)
        CraCEFRuntime.settingsByProfile = [:]
        let fm = FileManager.default
        var ids: [String: String] = [:]
        for name in ["ublock", "proton-pass", "dark-reader"] {
            let folder = ExtensionStore.directory.appendingPathComponent(name, isDirectory: true)
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["manifest_version": 3, "name": name, "version": "1.0"])
                .write(to: folder.appendingPathComponent("manifest.json"))
            ids[name] = ExtensionStore.chromiumID(key: nil, folder: folder)
        }
        func loaded(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
            ["location": 8, "path": ExtensionStore.directory.appendingPathComponent(name).path].merging(extra) { _, b in b }
        }
        // uBlock allowed in incognito, Proton Pass not, Dark Reader allowed but turned off.
        let settings: [String: Any] = [
            ids["ublock"]!: loaded("ublock", ["incognito": true]),
            ids["proton-pass"]!: loaded("proton-pass"),
            ids["dark-reader"]!: loaded("dark-reader", ["incognito": true, "state": 0, "disable_reasons": [1]]),
        ]
        let profile = AppPaths.chromiumCache.appendingPathComponent("Default", isDirectory: true)
        try writeSettings(settings, in: profile)
        // Profile 1 allows Proton Pass in incognito and nothing else.
        let work = AppPaths.chromiumCache.appendingPathComponent("Profile 1", isDirectory: true)
        try writeSettings([ids["ublock"]!: loaded("ublock"), ids["proton-pass"]!: loaded("proton-pass", ["incognito": true])], in: work)

        let store = ExtensionStore()
        let names = { (profile: String, incognito: Bool) in
            Set(store.entries(inProfile: profile, incognito: incognito).map(\.name))
        }
        check(names("Default", false) == ["ublock", "proton-pass"], "a normal window lists every turned-on extension")
        check(names("Default", true) == ["ublock"], "an incognito window lists only the ones allowed in incognito (#620)")
        check(names("Profile 1", true) == ["proton-pass"], "and that is its own profile's Allow in Incognito")

        // Allow in Incognito switched on in chrome://extensions: the live settings say so at once.
        var live = settings
        live[ids["proton-pass"]!] = loaded("proton-pass", ["incognito": true])
        CraCEFRuntime.settingsByProfile["Default"] = String(decoding: try JSONSerialization.data(withJSONObject: live), as: UTF8.self)
        store.reload()
        check(names("Default", true) == ["ublock", "proton-pass"], "switching Allow in Incognito on lists it in incognito")
    }

    // promise: #757
    /// Arc's pinned extensions seed Cra's toolbar only once the person imported from Arc: before
    /// that, Cra reads nothing in Arc's folder (macOS showed "Data Access Blocked" on first launch).
    static func pinnedComeOnlyFromAnImportedBrowser() throws {
        for imported in [false, true] {
            try run("pinned-from-arc-\(imported)") { install in
                try install.installStoreCopy()
                try install.writeSettings(install.settings())
                let arcProfile = ImportSource.arc.dataDir.appendingPathComponent("Default", isDirectory: true)
                try FileManager.default.createDirectory(at: arcProfile, withIntermediateDirectories: true)
                try JSONSerialization.data(withJSONObject: ["extensions": ["pinned_extensions": [install.id]]])
                    .write(to: arcProfile.appendingPathComponent("Preferences"))
                if imported { try Data(#"["arc"]"#.utf8).write(to: AppPaths.file("imported-browsers.json")) }
                let pinned = ExtensionStore().pinnedIDs(inProfile: "Default")
                if imported {
                    check(pinned == [install.id], "after importing from Arc, Arc's pinned extensions seed the toolbar")
                } else {
                    check(pinned.isEmpty, "without an import from Arc, Cra must not read Arc's pinned extensions (#757)")
                    check(!FileManager.default.fileExists(atPath: AppPaths.file("pinned-extensions.json").path),
                          "nothing is taken over, so nothing is saved")
                }
            }
        }
    }

    /// Shared extensions (discussion #595): what Settings' Share, profile checkmarks and Remove do to each profile.
    static func sharedExtensions() throws {
        let work = "Profile W"
        let workPath = { AppPaths.chromiumCache.appendingPathComponent(work, isDirectory: true).path }
        /// A store install in Default only, Work loaded with nothing; Settings lists Default and Work.
        func setUp(_ install: Install) throws -> ExtensionStore {
            try FileManager.default.removeItem(at: install.copy)
            try install.installStoreCopy()
            try install.liveSettings(install.settings())
            try install.liveSettings([:], profile: work)
            CraCEFRuntime.managed = [:]
            CraCEFRuntime.installs = []
            ExtensionStore.profileFoldersSource = { ["Default", work] }
            let store = ExtensionStore()
            store.reload()
            return store
        }
        func liveIDs(_ key: String) -> Set<String> {
            let json = CraCEFRuntime.settingsByProfile[key] ?? "{}"
            return Set(((try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] ?? [:]).keys)
        }
        func savedShares() -> SharedExtensions { ExtensionStore.loadShared() }

        try run("shared-into-every-profile") { install in
            let store = try setUp(install)
            guard let e = store.entries.first(where: { $0.extensionID == install.id }) else { return check(false, "the store install is listed") }
            check(e.fromWebStore && e.managedByChrome, "a store install is one Settings can share")
            store.share(e)
            check(savedShares().isShared(install.id), "the share is saved, so it survives a relaunch")
            check(CraCEFRuntime.managed == ["Default": [install.id], work: [install.id]], "Chrome keeps it in both profiles")
            check(CraCEFRuntime.installs.map(\.profile) == [workPath()], "only the profile that lacks it gets the store's install")
            check(CraCEFRuntime.uninstallExtension(install.id, profilePath: nil) == false && liveIDs("Default").contains(install.id),
                  "chrome://extensions can't remove it while it is shared")
        }

        try run("shared-taken-out-of-a-loaded-profile") { install in
            let store = try setUp(install)
            guard let e = store.entries.first(where: { $0.extensionID == install.id }) else { return check(false, "listed") }
            store.share(e)
            try install.liveSettings(install.settings(), profile: work)  // the store installed it there
            store.setShared(e, profile: work, included: false)
            check(!liveIDs(workPath()).contains(install.id), "taken out of Work: removed there")
            check(liveIDs("Default").contains(install.id), "Default keeps it")
            check(CraCEFRuntime.managed == ["Default": [install.id]], "Chrome lets go of it in Work only")
            store.reload()
            check(savedShares().removals.isEmpty, "the removal is done, so a later install in Work stays")
        }

        try run("shared-removal-waits-for-the-profile") { install in
            let store = try setUp(install)
            guard let e = store.entries.first(where: { $0.extensionID == install.id }) else { return check(false, "listed") }
            store.share(e)
            CraCEFRuntime.settingsByProfile[workPath()] = nil  // Work not loaded this session
            let onDisk = AppPaths.chromiumCache.appendingPathComponent(work, isDirectory: true)
            try install.writeSettings(install.settings(), in: onDisk)
            store.setShared(e, profile: work, included: false)
            check(savedShares().removals[work] == [install.id], "Work owes the removal until it loads")
            try install.liveSettings(install.settings(), profile: work)  // a space on Work opens
            store.reconcileShared(profile: work)
            check(!liveIDs(workPath()).contains(install.id), "removed from Work once it loaded")
            check(savedShares().removals.isEmpty, "and owed no more")
        }

        try run("shared-removed-everywhere") { install in
            let store = try setUp(install)
            guard let e = store.entries.first(where: { $0.extensionID == install.id }) else { return check(false, "listed") }
            store.share(e)
            try install.liveSettings(install.settings(), profile: work)
            store.removeShared(e)
            check(!liveIDs("Default").contains(install.id) && !liveIDs(workPath()).contains(install.id), "Remove takes it out of every profile")
            check(!savedShares().isShared(install.id) && CraCEFRuntime.managed.isEmpty, "and stops sharing it")
        }

        // Discussion #595's follow-up: shared from the profile it was set up in, with the profiles picked.
        try run("shared-from-a-home") { install in
            let store = try setUp(install)
            CraCEFRuntime.storage = [:]
            CraCEFRuntime.switched = []
            guard let e = store.entries.first(where: { $0.extensionID == install.id }) else { return check(false, "listed") }
            store.share(e, from: "Default", with: [work])
            check(savedShares().home(of: install.id) == "Default", "the share keeps where it was set up")
            check(CraCEFRuntime.managed == ["Default": [install.id], work: [install.id]], "Chrome keeps it in both picked profiles")
            check((CraCEFRuntime.storage[install.id]?["home"] as? String) == "Default"
                  && (CraCEFRuntime.storage[install.id]?["profiles"] as? [String]) == ["Default", work],
                  "the engine is told whose data both profiles use")
            check(CraCEFRuntime.installs.map(\.profile) == [workPath()], "Work gets the store's install")
            store.stopSharing(e)
            check(savedShares().isShared(install.id), "Stop Sharing waits while two profiles use Default's data")
            store.setSharedOn(e, false)
            check(Set(CraCEFRuntime.switched.filter { !$0.on }.map(\.profile)) == ["Default", workPath()],
                  "one switch: off in both loaded profiles")
            store.setSharedOn(e, true)
            try install.liveSettings(install.settings(), profile: work)  // the store installed it there
            store.setShared(e, profile: work, included: false)
            check(!liveIDs(workPath()).contains(install.id), "taken out of Work: removed there")
            store.stopSharing(e)
            check(!savedShares().isShared(install.id) && CraCEFRuntime.storage.isEmpty, "with Default alone it stops, on its own data")
        }

        try run("stop-sharing-keeps-installs") { install in
            let store = try setUp(install)
            guard let e = store.entries.first(where: { $0.extensionID == install.id }) else { return check(false, "listed") }
            store.share(e)
            store.stopSharing(e)
            check(liveIDs("Default").contains(install.id), "Stop Sharing removes nothing")
            check(CraCEFRuntime.managed.isEmpty, "chrome://extensions manages it again")
            check(!FileManager.default.fileExists(atPath: AppPaths.file("shared-extensions.json").path), "nothing shared: no file")
        }
    }

    static func main() throws {
        try sharedExtensions()
        try removedCopiesStayRemoved()
        try pinnedComeOnlyFromAnImportedBrowser()

        try run("live-reload") { install in
            try install.installStoreCopy()
            try install.writeSettings(install.settings())
            let store = ExtensionStore()
            store.reload()
            check(FileManager.default.fileExists(atPath: install.copy.appendingPathComponent("payload.txt").path),
                  "refreshing the live extension list must not delete files Chromium can still be reading")
            check(store.entries.contains { $0.extensionID == install.id }, "the extension stays listed during migration")
        }

        try run("live-store-ownership") { install in
            try install.writeSettings([install.id: ["location": 8, "path": install.copy.path]])
            let store = ExtensionStore()
            try install.installStoreCopy()
            try install.liveSettings(install.settings())
            store.reload()
            check(store.entries.first?.managedByChrome == true,
                  "a live store installation exposes Chromium's removal flow instead of deleting its backup")
            check(store.entries.first?.url == install.destination, "the displayed entry uses the live store installation")
            check(FileManager.default.fileExists(atPath: install.copy.path), "showing the store entry does not delete the loaded backup")
        }

        try run("stale-import-path") { install in
            try install.writeSettings(install.settings(path: install.copy.path))
            let list = ExtensionStore.loadList()
            check(list.paths == [install.copy.path], "Web Store flags with the original imported path must not delete the only copy")
            check(FileManager.default.fileExists(atPath: install.copy.appendingPathComponent("payload.txt").path),
                  "an imported path mislabeled as a store install remains readable")
        }

        try run("missing-store-files") { install in
            try install.writeSettings(install.settings())
            let list = ExtensionStore.loadList()
            check(list.paths == [install.copy.path], "a store record without its installed files keeps the imported copy")
        }

        try run("invalid-store-manifest") { install in
            try install.installStoreCopy()
            try Data("not JSON".utf8).write(to: install.destination.appendingPathComponent("manifest.json"))
            try install.writeSettings(install.settings())
            check(ExtensionStore.loadList().paths == [install.copy.path], "an unreadable store manifest cannot replace an imported copy")
        }

        try run("store-path-aliases-import") { install in
            try FileManager.default.createDirectory(at: install.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: install.destination, withDestinationURL: install.copy)
            try install.writeSettings(install.settings())
            check(ExtensionStore.loadList().paths == [install.copy.path], "a symlink to the imported copy is not an independent store installation")
        }

        try run("completed-store-install") { install in
            try install.installStoreCopy()
            try install.writeSettings(install.settings())
            check(ExtensionStore.loadList().paths.isEmpty, "a verified independent store install replaces the imported copy before Chromium starts")
            check(!FileManager.default.fileExists(atPath: install.copy.path), "completed migration removes the redundant copy at startup")
            check(FileManager.default.fileExists(atPath: install.destination.appendingPathComponent("payload.txt").path), "store resources survive cleanup")
            let store = ExtensionStore()
            check(store.entries.first?.managedByChrome == true, "the migrated entry belongs to Chromium")
        }

        try run("migration-finishes-while-running") { install in
            try install.writeSettings([install.id: ["location": 8, "path": install.copy.path]])
            let store = ExtensionStore()
            try install.installStoreCopy()
            try install.writeSettings(install.settings())
            store.reload()
            check(FileManager.default.fileExists(atPath: install.copy.appendingPathComponent("payload.txt").path),
                  "completing a store install does not invalidate a loaded extension's resource paths")
            _ = ExtensionStore.loadList(profileIsFree: false)
            check(FileManager.default.fileExists(atPath: install.copy.appendingPathComponent("payload.txt").path),
                  "another launch must not delete files while a process still owns the profile")
            check(ExtensionStore.loadList(profileIsFree: true).paths.isEmpty,
                  "the imported copy is retired only after the profile becomes free")
            let restarted = ExtensionStore()
            check(restarted.entries.first?.extensionID == install.id && restarted.entries.first?.managedByChrome == true,
                  "the extension remains installed after the startup handover")
        }

        try run("crash-before-store-preferences-flush") { install in
            try install.writeSettings([install.id: ["location": 8, "path": install.copy.path]])
            let store = ExtensionStore()
            try install.installStoreCopy()
            try install.liveSettings(install.settings())
            store.reload()
            check(ExtensionStore.loadProfiles().loads(folder: install.id, inProfile: "Default"),
                  "live store preferences must not retire an import before the installation is persisted")
            CraCEFRuntime.settingsByProfile = [:]
            let list = ExtensionStore.loadList()
            check(list.paths == [install.copy.path], "a crash before Chromium flushes its store preferences preserves a usable registered import")
            check(FileManager.default.fileExists(atPath: install.copy.appendingPathComponent("payload.txt").path),
                  "unflushed store installation metadata cannot delete the imported resources")
            check(ExtensionStore().entries.contains { $0.extensionID == install.id }, "the extension remains visible after an unflushed migration crashes")
        }

        try run("crash-before-first-preferences-flush") { install in
            let store = ExtensionStore()
            try install.installStoreCopy()
            try install.liveSettings(install.settings())
            store.reload()
            CraCEFRuntime.settingsByProfile = [:]
            check(ExtensionStore.loadList().paths == [install.copy.path], "an absent on-disk record after a crash must not be mistaken for an uninstall")
        }

        try run("live-preferences-unavailable-during-shutdown") { install in
            let store = ExtensionStore()
            try install.installStoreCopy()
            try install.liveSettings(install.settings())
            store.reload()
            CraCEFRuntime.settingsByProfile = [:]
            store.reload()
            check(ExtensionStore.loadProfiles().loads(folder: install.id, inProfile: "Default"),
                  "an unavailable live snapshot is not evidence that the user uninstalled the extension")
            check(ExtensionStore.loadList().paths == [install.copy.path],
                  "a queued reload during shutdown must not retire the only persisted extension registration")
            check(FileManager.default.fileExists(atPath: install.copy.appendingPathComponent("payload.txt").path),
                  "resources remain available after an interrupted shutdown with unavailable live preferences")
        }

        try run("store-install-removed-before-restart") { install in
            let store = ExtensionStore()
            try install.installStoreCopy()
            try install.liveSettings(install.settings())
            store.reload()
            check(FileManager.default.fileExists(atPath: install.copy.path), "the copy waits for the next launch while the store install is live")
            try install.liveSettings([:])
            store.reload()
            check(!FileManager.default.fileExists(atPath: install.copy.path),
                  "removing the store install in chrome://extensions also retires the copy that waited for the next launch")
            check(ExtensionStore.loadList().paths.isEmpty, "an extension removed after its store install does not come back at the next launch")
            check(store.entries.isEmpty, "the removed extension leaves the list at once")
        }

        try run("store-install-removed-in-one-profile") { install in
            let other = AppPaths.chromiumCache.appendingPathComponent("Profile 1", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            let store = ExtensionStore()
            try install.installStoreCopy()
            try install.liveSettings(install.settings())
            try install.liveSettings([install.id: ["location": 8, "path": install.copy.path]], profile: "Profile 1")
            store.reload()
            try install.liveSettings([:])
            store.reload()
            check(FileManager.default.fileExists(atPath: install.copy.appendingPathComponent("payload.txt").path),
                  "a copy another profile still loads stays when the store install is removed in one profile")
            check(ExtensionStore.loadProfiles().profiles(ofFolder: install.id) == ["Profile 1"],
                  "only the profile it was removed from stops loading the copy")
        }

        try run("live-settings-gone-after-store-install") { install in
            let store = ExtensionStore()
            try install.installStoreCopy()
            try install.liveSettings(install.settings())
            store.reload()
            CraCEFRuntime.settingsByProfile = [:]
            store.reload()
            check(FileManager.default.fileExists(atPath: install.copy.appendingPathComponent("payload.txt").path),
                  "live settings going away (shutdown) is not a removal of the store install")
        }

        try run("one-profile-still-imported") { install in
            try install.installStoreCopy()
            try install.writeSettings(install.settings())
            let other = AppPaths.chromiumCache.appendingPathComponent("Profile 1", isDirectory: true)
            try install.writeSettings([install.id: ["location": 8, "path": install.copy.path]], in: other)
            let list = ExtensionStore.loadList()
            check(list.paths == [install.copy.path], "a copy another profile still loads is retained")
            check(list.profiles == "Profile 1", "only the migrated profile stops loading the imported copy")
            check(ExtensionStore.loadProfiles().profiles(ofFolder: install.id) == ["Profile 1"], "profile migration scope persists")
            let listAgain = ExtensionStore.loadList()
            check(listAgain.paths == list.paths && listAgain.profiles == list.profiles, "a second launch preserves the remaining profile's copy")
        }

        try unpackedCopiesStepAside()
        try incognitoListsOnlyAllowed()

        print("ExtensionStoreMigrationTests: \(checks) checks, \(failures.count) failures")
        if !failures.isEmpty { exit(1) }
    }
}
