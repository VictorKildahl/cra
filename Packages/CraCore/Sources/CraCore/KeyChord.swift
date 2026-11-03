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
    public var display: String {
        var s = ""
        if keys.contains(.control) { s += "⌃" }
        if keys.contains(.option) { s += "⌥" }
        if keys.contains(.shift) { s += "⇧" }
        if keys.contains(.command) { s += "⌘" }
        switch key {
        case Self.tab: s += "⇥"
        case Self.left: s += "←"
        case Self.right: s += "→"
        case Self.up: s += "↑"
        case Self.down: s += "↓"
        case Self.delete: s += "⌫"
        default: s += key.uppercased()
        }
        return s
    }
}
