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

    public static let tab = "\t"
    // AppKit's function-key characters (NSLeftArrowFunctionKey...).
    public static let left = "\u{F702}"
    public static let right = "\u{F703}"
    public static let up = "\u{F700}"
    public static let down = "\u{F701}"

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
        default: s += key.uppercased()
        }
        return s
    }
}
