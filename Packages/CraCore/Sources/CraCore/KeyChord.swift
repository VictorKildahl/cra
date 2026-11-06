/// A keyboard shortcut as keybindings.json stores it: `key` is the lowercase character or a
/// special key (`tab`, `left`...), `modifiers` the device-independent modifier bits of
/// AppKit's NSEvent.ModifierFlags. The app reads events into it (Shortcut in KeyBindings.swift).
public struct KeyChord: Codable, Hashable {
    public var key: String
    public var modifiers: UInt

    public init(key: String, modifiers: UInt) {
        self.key = key
        self.modifiers = modifiers
    }

    /// NSEvent.ModifierFlags' bits for the four keys a shortcut can hold.
    public struct Modifiers: OptionSet, Hashable {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let shift = Modifiers(rawValue: 1 << 17)
        public static let control = Modifiers(rawValue: 1 << 18)
        public static let option = Modifiers(rawValue: 1 << 19)
        public static let command = Modifiers(rawValue: 1 << 20)
    }

    public var keys: Modifiers { Modifiers(rawValue: modifiers) }

    /// Return or the keypad's Enter (key codes 36, 76) with ⌘ and no other modifier: the command
    /// bar opens the row in a background tab (Arc, GitHub #85). A text field has no key binding
    /// for it and reports noop:, so the bar reads the event with this.
    public static func isCommandReturn(keyCode: UInt16, modifiers: UInt) -> Bool {
        [36, 76].contains(keyCode) && Modifiers(rawValue: modifiers).intersection([.shift, .control, .option, .command]) == .command
    }

    // MARK: Matching a key press

    /// What a key press gives to match against: AppKit's charactersIgnoringModifiers, the
    /// key's virtual key code and its device-independent modifier bits.
    public struct Press: Hashable {
        public var characters: String
        public var keyCode: UInt16
        public var modifiers: UInt

        public init(characters: String, keyCode: UInt16, modifiers: UInt) {
            self.characters = characters
            self.keyCode = keyCode
            self.modifiers = modifiers
        }

        /// The key as a chord stores it: lowercase, with Shift's character turned back into
        /// the key's own ("{" is "["), Shift-Tab's backtab as Tab and the Delete key's U+007F
        /// as `delete`.
        public var key: String {
            let lower = characters.lowercased()
            return KeyChord.unshift[lower] ?? lower
        }
    }

    static let unshift: [String: String] = [
        "\u{19}": tab, "\u{7F}": delete, "{": "[", "}": "]", "<": ",", ">": ".", "?": "/", "+": "=", "_": "-",
        "~": "`", ":": ";", "\"": "'", "|": "\\",
    ]

    /// Where each punctuation key sits on an ANSI keyboard (virtual key codes). On layouts that
    /// can't type the character without ⌥ (Danish and German "[" is ⌥8) the shortcut takes the
    /// key in that place instead, as Arc and Chrome do for ⌘[ and ⌘].
    static let ansiKeyCode: [String: UInt16] = [
        "[": 33, "]": 30, "=": 24, "-": 27, ",": 43, ".": 47, "/": 44, ";": 41, "'": 39, "`": 50, "\\": 42,
    ]

    /// How a press matches this chord: by the character it types, or by the key's place when
    /// the layout can't type the chord's character (`typable` says what the layout types
    /// without ⌥, on its own or with Shift). Nil when it doesn't match. Caps Lock and the
    /// function-key bit don't count.
    public func match(_ press: Press, typable: (String) -> Bool) -> Match? {
        let four: Modifiers = [.shift, .control, .option, .command]
        guard Modifiers(rawValue: press.modifiers).intersection(four) == keys.intersection(four),
              !press.characters.isEmpty else { return nil }
        if press.key == key { return .character }
        // Turkish Q types "-" on the ANSI "=" key, and "=" itself as ⇧0: matching "=" by place
        // turned ⌘- into Zoom In (GitHub #212).
        if let code = Self.ansiKeyCode[key], press.keyCode == code, !typable(key) { return .position }
        return nil
    }

    public enum Match: Comparable { case character, position }

    /// The first entry with a chord the press types; failing that, the first one a key matches
    /// by place. A character match anywhere wins over a place match earlier in the list.
    public static func first<T>(in entries: [T], chords: (T) -> [KeyChord], press: Press,
                                typable: (String) -> Bool) -> T? {
        var byPlace: T?
        for entry in entries {
            let matches = chords(entry).compactMap { $0.match(press, typable: typable) }
            if matches.contains(.character) { return entry }
            if byPlace == nil, !matches.isEmpty { byPlace = entry }
        }
        return byPlace
    }

    public static let tab = "\t"
    // AppKit's function-key characters (NSLeftArrowFunctionKey...).
    public static let left = "\u{F702}"
    public static let right = "\u{F703}"
    public static let up = "\u{F700}"
    public static let down = "\u{F701}"
    /// The Delete key as a menu's key equivalent wants it (NSBackspaceCharacter), shown ⌫.
    /// Its key events carry U+007F, which the app reads as this.
    public static let delete = "\u{8}"

    /// How menus and the command bar show it: ⌃⌥⇧⌘ in Apple's order, then the key.
    public var display: String { caps.joined() }

    /// One glyph per key, as a tooltip's key caps show them: ⌃3 is ["⌃", "3"].
    public var caps: [String] {
        var s: [String] = []
        if keys.contains(.control) { s.append("⌃") }
        if keys.contains(.option) { s.append("⌥") }
        if keys.contains(.shift) { s.append("⇧") }
        if keys.contains(.command) { s.append("⌘") }
        switch key {
        case Self.tab: s.append("⇥")
        case Self.left: s.append("←")
        case Self.right: s.append("→")
        case Self.up: s.append("↑")
        case Self.down: s.append("↓")
        case Self.delete: s.append("⌫")
        default: s.append(key.uppercased())
        }
        return s
    }
}
