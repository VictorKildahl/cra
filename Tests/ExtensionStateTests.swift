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
        print("ExtensionStateTests: \(checks) checks passed")
    }
}
