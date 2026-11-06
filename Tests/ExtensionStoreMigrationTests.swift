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

    static func main() throws {
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

        print("ExtensionStoreMigrationTests: \(checks) checks, \(failures.count) failures")
        if !failures.isEmpty { exit(1) }
    }
}
