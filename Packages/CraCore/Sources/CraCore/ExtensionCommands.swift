import Foundation

/// Extensions' keyboard shortcuts (chrome://extensions/shortcuts, the manifest's "commands") outside
/// Global scope (GitHub #701). Chrome catches them on its own browser window, which Cra never shows,
/// so they never fired; Global ones are system hot keys and did. Chromium keeps a profile's in its
/// extensions.commands pref, keyed "mac:<accelerator>". Cra catches the key itself and runs the ones
/// that open the extension's popup (_execute_action), as a click on its toolbar button does. An
/// extension's own commands (chrome.commands.onCommand) need the engine to deliver them.
public enum ExtensionCommands {
    public struct Binding: Equatable, Sendable {
        public let extensionID: String
        public let command: String
        public let global: Bool
        /// "Y", "5", or a Chromium key name ("Period", "Up", "Space").
        public let key: String
        public let modifiers: KeyChord.Modifiers
    }

    /// The Mac bindings in Chromium's extensions.commands pref (JSON).
    public static func bindings(prefJSON: String) -> [Binding] {
        guard let data = prefJSON.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        return root.compactMap { name, value in
            guard name.hasPrefix("mac:"), let entry = value as? [String: Any],
                  let id = entry["extension"] as? String, let command = entry["command_name"] as? String else { return nil }
            var parts = name.dropFirst(4).split(separator: "+").map(String.init)
            guard let key = parts.popLast(), !key.isEmpty else { return nil }
            var modifiers: KeyChord.Modifiers = []
            for p in parts {
                switch p {
                // On a Mac, Chromium's "Ctrl" is ⌘ and "MacCtrl" is ⌃.
                case "Command", "Ctrl": modifiers.insert(.command)
                case "MacCtrl": modifiers.insert(.control)
                case "Alt": modifiers.insert(.option)
                case "Shift": modifiers.insert(.shift)
                default: return nil
                }
            }
            return Binding(extensionID: id, command: command, global: entry["global"] as? Bool ?? false, key: key, modifiers: modifiers)
        }
    }

    /// Chromium's names for keys that aren't a letter or digit, by virtual key code.
    static let keyNames: [UInt16: String] = [
        43: "Comma", 47: "Period", 49: "Space", 48: "Tab", 126: "Up", 125: "Down", 123: "Left", 124: "Right",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown", 114: "Insert", 117: "Delete",
    ]

    /// The binding a key press is, outside Global scope. `characters`: the event's characters ignoring
    /// modifiers; `modifiers`: AppKit's flags.
    public static func binding(in bindings: [Binding], characters: String, keyCode: UInt16, modifiers: UInt) -> Binding? {
        let held = KeyChord.Modifiers(rawValue: modifiers).intersection([.shift, .control, .option, .command])
        guard !held.isDisjoint(with: [.control, .option, .command]) else { return nil }
        let key = keyNames[keyCode] ?? characters.uppercased()
        return bindings.first { !$0.global && $0.key == key && $0.modifiers == held }
    }

    /// The commands that are a click on the extension's toolbar button.
    public static func opensPopup(_ command: String) -> Bool {
        ["_execute_action", "_execute_browser_action", "_execute_page_action"].contains(command)
    }
}
