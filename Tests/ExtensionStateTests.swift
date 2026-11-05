import Foundation

/// GitHub #41: which extensions a Chromium profile has turned off (chrome://extensions).
@main
enum ExtensionStateTests {
    static func main() throws {
        let fm = FileManager.default
        let profile = fm.temporaryDirectory.appendingPathComponent("cra-extension-state-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: profile) }
        try fm.createDirectory(at: profile, withIntermediateDirectories: true)
        func write(_ name: String, _ settings: [String: Any]) throws {
            let json = try JSONSerialization.data(withJSONObject: ["extensions": ["settings": settings]])
            try json.write(to: profile.appendingPathComponent(name))
        }
        // A Web Store install with a folder, so extensions(inProfile:) lists it too.
        let store = profile.appendingPathComponent("Extensions/store/1.0", isDirectory: true)
        try fm.createDirectory(at: store, withIntermediateDirectories: true)
        try Data(#"{"name":"Store","version":"1.0"}"#.utf8).write(to: store.appendingPathComponent("manifest.json"))
        try write("Preferences", [
            "old": ["location": 1, "state": 0, "path": "/nowhere"],          // older Chromium: state 0
        ])
        try write("Secure Preferences", [
            "cmdoff": ["location": 8, "disable_reasons": [1], "path": "/x"], // --load-extension, turned off
            "cmdon": ["location": 8, "disable_reasons": [], "path": "/y"],
            "plain": ["location": 8, "path": "/z"],                          // no reasons at all
            "store": ["location": 1, "disable_reasons": [1], "path": "store/1.0"],
        ])
        var checks = 0
        func check(_ value: Bool, _ message: String) {
            precondition(value, message)
            checks += 1
        }
        let off = ExtensionImporter.disabledIDs(inProfile: profile)
        check(off == ["cmdoff", "old", "store"], "disabled IDs: \(off.sorted())")
        let listed = ExtensionImporter.extensions(inProfile: profile)
        check(listed.map(\.id) == ["store"], "importable: \(listed.map(\.id))")
        check(listed.first?.isEnabled == false, "the turned-off Web Store install reads as off")
        check(ExtensionImporter.disabledIDs(inProfile: profile.appendingPathComponent("missing")).isEmpty, "no prefs, nothing off")

        // GitHub #43: Cra's own profiles pass Chromium's live extensions.settings instead of the
        // files, which lag ~10 s behind an install. The same dictionary reads the same.
        let unpacked = profile.appendingPathComponent("unpacked", isDirectory: true)
        try fm.createDirectory(at: unpacked.appendingPathComponent("_locales/en"), withIntermediateDirectories: true)
        try Data(#"{"name":"__MSG_appName__","version":"1.0","default_locale":"en"}"#.utf8).write(to: unpacked.appendingPathComponent("manifest.json"))
        try Data(#"{"appName":{"message":"Unpacked"}}"#.utf8).write(to: unpacked.appendingPathComponent("_locales/en/messages.json"))
        let live = ExtensionImporter.settings(inProfile: profile).merging([
            "fresh": ["location": 4, "disable_reasons": [], "path": unpacked.path],   // just loaded unpacked
            "component": ["location": 5, "path": unpacked.path],
            "gone": ["location": 4, "path": profile.appendingPathComponent("removed").path],
            "noise": "not a dictionary",
        ]) { _, new in new }
        let fromLive = ExtensionImporter.extensions(settings: live, inProfile: profile)
        check(Set(fromLive.map(\.id)) == ["store", "fresh"], "live importable: \(fromLive.map(\.id).sorted())")
        let fresh = fromLive.first { $0.id == "fresh" }
        check(fresh?.isEnabled == true && fresh?.name == "Unpacked" && fresh?.folder.path == unpacked.path,
              "a just-loaded unpacked extension: on, localized name, its own folder")
        check(fromLive.first { $0.id == "store" }?.folder.path == store.path, "a relative path sits in the profile's Extensions")
        check(ExtensionImporter.disabledIDs(settings: live) == off, "live disabled IDs match the files'")

        // Settings must show extension descriptions, not manifest message keys (1Password and
        // LanguageTool). An unavailable optional description is hidden; names retain their fallback.
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/LocalizedExtension")
        let localizedFolder = profile.appendingPathComponent("localized")
        try fm.copyItem(at: fixture, to: localizedFolder)
        let manifestData = try Data(contentsOf: localizedFolder.appendingPathComponent("manifest.json"))
        let manifest = try JSONSerialization.jsonObject(with: manifestData) as! [String: Any]
        check(ExtensionImporter.localizedDescription(manifest: manifest, folder: localizedFolder) == "Passwörter sicher verwalten.",
              "the actual fixture manifest resolves its description for Settings")
        func messages(_ locale: String, _ contents: String) throws {
            let dir = localizedFolder.appendingPathComponent("_locales/\(locale)")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(contents.utf8).write(to: dir.appendingPathComponent("messages.json"))
        }
        func description(_ value: String, folder: URL? = nil) -> String {
            var input = manifest
            input["description"] = value
            return ExtensionImporter.localizedDescription(manifest: input, folder: folder ?? localizedFolder)
        }
        check(description("__MSG_extDescription__") == "Passwörter sicher verwalten.", "default locale before English")
        check(description("__MSG_appDesc__") == "Texte prüfen – überall.", "LanguageTool key and Unicode")
        check(description("__MSG_EXTDESCRIPTION__") == "Passwörter sicher verwalten.", "case-insensitive message keys")
        check(description("A plain description") == "A plain description", "literal descriptions stay unchanged")
        check(description("").isEmpty, "empty descriptions stay empty")
        check(ExtensionImporter.localizedDescription(manifest: [:], folder: localizedFolder).isEmpty,
              "absent descriptions stay empty")
        check(ExtensionImporter.localizedDescription(manifest: ["description": 42], folder: localizedFolder).isEmpty,
              "invalid description type stays empty")
        check(description("__MSG_englishOnly__") == "English fallback", "missing default key falls back to English")
        check(description("__MSG_usOnly__") == "US fallback", "en_US fallback")
        check(description("__MSG_missing__").isEmpty, "missing key never appears in settings")
        try messages("en_US", #"{"invalid":{"message":42}}"#)
        check(description("__MSG_invalid__").isEmpty, "non-string translation is hidden")
        check(description("__MSG_extDescription__", folder: profile.appendingPathComponent("missing")).isEmpty,
              "missing locale files do not expose the key")
        check(ExtensionImporter.localized("__MSG_missing__", manifest: manifest, folder: unpacked) == "__MSG_missing__",
              "existing name fallback remains unchanged")
        try messages("de", "not JSON")
        check(description("__MSG_extDescription__") == "Manage passwords.", "invalid catalog falls back to English")
        check(description("__MSG_appDesc__").isEmpty, "invalid catalog without a fallback message hides the key")
        print("ExtensionStateTests: \(checks) checks passed")
    }
}
