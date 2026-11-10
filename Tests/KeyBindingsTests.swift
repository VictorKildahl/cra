import AppKit

/// The command list KeyBindingRegistry keeps: the built-in actions, the live folder plugins' commands
/// after New Folder, and the user's shortcuts on both, through every way the list is rebuilt.
@main
enum KeyBindingsTests {
    static var failures = 0
    static var checks = 0
    static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { failures += 1; print("FAIL: \(message)") }
    }

    @MainActor
    static func main() {
        recordedShortcuts()
        let registry = KeyBindingRegistry.shared
        // A Little Window in front handles each action, ignores it or leaves it to the app on purpose, so
        // a new one can't fall through to the browser window behind it by default (#333).
        for action in registry.actions {
            expect(LittleWindowRouting.isClassified(action.id), "\(action.id) is decided on for a Little Window (CraCore LittleWindowRouting)")
        }
        let builtIn = registry.actions.count
        let github = KeyAction(id: "newGitHubLiveFolder", name: "New GitHub Live Folder", section: .file, shortcuts: [], triggers: ["github"])
        let jira = KeyAction(id: "liveFolderPlugin:cra.jira", name: "New Jira Live Folder", section: .file, shortcuts: [], triggers: ["jira"])
        registry.setPluginActions([github, jira])
        let ids = registry.actions.map(\.id)
        expect(registry.actions.count == builtIn + 2, "the plugins' commands join the list")
        if let folder = ids.firstIndex(of: "newFolder") {
            expect(Array(ids[(folder + 1)...(folder + 2)]) == [github.id, jira.id], "right after New Folder, in the plugins' order")
        } else { expect(false, "New Folder is a built-in action") }

        let chord = Shortcut("j", [.command, .option])
        registry.setShortcuts([chord], for: jira.id)
        expect(registry.action(jira.id)?.shortcuts == [chord], "a plugin command takes a shortcut")

        // keybindings.json written by another Mac (settings sync): the plugins' commands stay, with
        // the shortcuts that file gives them.
        let synced = Shortcut("k", [.command, .option])
        let file = URL(fileURLWithPath: ProcessInfo.processInfo.environment["CRA_DATA_DIR"]!).appendingPathComponent("keybindings.json")
        try! JSONEncoder().encode([jira.id: [synced]]).write(to: file)
        registry.reloadOverrides()
        expect(registry.action(github.id) != nil && registry.action(jira.id) != nil, "a synced keybindings.json keeps the plugins' commands")
        expect(registry.action(jira.id)?.shortcuts == [synced], "and their shortcuts from the synced file")

        registry.resetShortcuts(for: jira.id)
        expect(registry.action(jira.id)?.shortcuts == [], "a reset command goes back to no shortcut")
        registry.resetOverrides()
        expect(registry.action(github.id) != nil, "Reset All keeps the plugins' commands")

        registry.setPluginActions([])
        expect(registry.actions.count == builtIn && registry.action(github.id) == nil, "a disabled plugin's command goes")

        print("Key bindings: \(checks) checks, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    @MainActor
    static func recordedShortcuts() {
        let shifted: NSEvent.ModifierFlags = [.command, .shift]
        let digits: [(UInt16, String, String)] = [
            (18, "!", "1"), (19, "@", "2"), (20, "#", "3"), (21, "$", "4"), (23, "%", "5"),
            (22, "^", "6"), (26, "&", "7"), (28, "*", "8"), (25, "(", "9"), (29, ")", "0"),
            (19, "\"", "2"), (21, "¤", "4"),
        ]
        let cases = digits.map { ($0.0, $0.1, shifted, Optional($0.2)) } + [
            (19, "2", .command, "2"), (0, "A", shifted, "a"),
            (33, "{", shifted, "["), (24, "+", shifted, "="),
            (48, "\u{19}", .shift, Shortcut.tab), (0, "a", [], nil),
            (19, "@", .shift, nil),
        ]
        for (code, chars, flags, key) in cases {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                        timestamp: 0, windowNumber: 0, context: nil, characters: chars,
                                        charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code)!
            let shortcut = Shortcut.from(event: event)
            expect(shortcut?.key == key, "record \(chars) with \(flags.rawValue) as \(key ?? "none")")
            guard let shortcut else { continue }
            expect(shortcut.flags == flags, "recording keeps the modifiers")
            expect(shortcut.matches(event), "the recorded shortcut matches its original press")
            let saved = try! JSONEncoder().encode(shortcut)
            expect(try! JSONDecoder().decode(Shortcut.self, from: saved) == shortcut, "the recorded shortcut survives saving")
            if let digit = digits.first(where: { $0.0 == code })?.2, flags.contains(.shift) {
                expect(shortcut.display == "⇧⌘\(digit)", "show the digit alongside Shift and Command")
            }
        }
    }
}
