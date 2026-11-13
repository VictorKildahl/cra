import Foundation

/// Arc's Shortcuts field takes an action's name or its keys typed as words: "command e" finds the action on ⌘E.
/// Words for the modifiers are command, shift, option (or alt) and control (or ctrl) and their glyphs, one key
/// after them (a letter, or tab, left, space and the other names a chord holds). The modifiers must be exactly the
/// chord's: ⇧⌘E isn't "command e".
public enum ShortcutSearch {
    public static func matches(_ query: String, name: String, shortcuts: [KeyChord]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty || name.lowercased().contains(q) { return true }
        guard let typed = chord(q) else { return false }
        return shortcuts.contains { $0.keys == typed.keys && $0.key == typed.key }
    }

    private static let modifierWords: [String: KeyChord.Modifiers] = [
        "command": .command, "cmd": .command, "⌘": .command,
        "shift": .shift, "⇧": .shift,
        "option": .option, "opt": .option, "alt": .option, "⌥": .option,
        "control": .control, "ctrl": .control, "⌃": .control,
    ]

    private static let keyWords: [String: String] = [
        "tab": KeyChord.tab, "left": KeyChord.left, "right": KeyChord.right, "up": KeyChord.up, "down": KeyChord.down,
        "delete": KeyChord.delete, "backspace": KeyChord.delete, "space": KeyChord.space, "f12": KeyChord.f12,
    ]

    /// The modifiers and the key a lowercase query spells, or nil when it isn't a chord.
    private static func chord(_ q: String) -> (keys: KeyChord.Modifiers, key: String)? {
        var keys: KeyChord.Modifiers = []
        var key: String?
        for word in q.split(whereSeparator: { $0 == " " || $0 == "+" }).map(String.init) {
            if let m = modifierWords[word] { keys.insert(m); continue }
            // Glyphs typed together, "⌘e" or "⇧⌘4".
            var rest = Substring(word)
            while let first = rest.first, let m = modifierWords[String(first)] { keys.insert(m); rest = rest.dropFirst() }
            if rest.isEmpty { continue }
            guard key == nil else { return nil }
            key = keyWords[String(rest)] ?? (rest.count == 1 ? String(rest) : nil)
            if key == nil { return nil }
        }
        guard let key, !keys.isEmpty else { return nil }
        return (keys, key)
    }
}
