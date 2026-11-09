import Foundation

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
        let registry = KeyBindingRegistry.shared
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
}
