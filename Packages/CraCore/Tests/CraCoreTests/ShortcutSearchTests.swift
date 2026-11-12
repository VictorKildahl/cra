import CraCore
import Testing

/// Arc's Settings ▸ Shortcuts field ("Type a feature name or shortcut (like “Command E”)"): "command e" found
/// Open Extensions, whose key is ⌘E (Arc 1.172.2, 11 Nov 2026).
struct ShortcutSearchTests {
    static let cmd = KeyChord.Modifiers.command.rawValue
    static let shift = KeyChord.Modifiers.shift.rawValue
    static let option = KeyChord.Modifiers.option.rawValue
    static let control = KeyChord.Modifiers.control.rawValue
    static let openExtensions = [KeyChord(key: "e", modifiers: cmd)]

    static func matches(_ q: String, _ name: String = "Open Extensions", _ keys: [KeyChord] = openExtensions) -> Bool {
        ShortcutSearch.matches(q, name: name, shortcuts: keys)
    }

    @Test func theKeysTypedAsWordsFindTheAction() {
        #expect(Self.matches("command e"))
        #expect(Self.matches("Command E"))
        #expect(Self.matches("cmd e"))
        #expect(Self.matches("cmd+e"))
        #expect(Self.matches("⌘E"))
        #expect(Self.matches("⌘ e"))
    }

    @Test func theModifiersHaveToBeTheSameOnesNotJustPartOfThem() {
        #expect(!Self.matches("shift command e"))
        #expect(!Self.matches("e", "Cast", Self.openExtensions), "a bare key isn't the chord ⌘E")
        #expect(!Self.matches("command r"))
        #expect(Self.matches("shift command e", "X", [KeyChord(key: "e", modifiers: Self.cmd | Self.shift)]))
        #expect(Self.matches("control option command n", "X", [KeyChord(key: "n", modifiers: Self.cmd | Self.option | Self.control)]))
        #expect(Self.matches("alt command n", "X", [KeyChord(key: "n", modifiers: Self.cmd | Self.option)]))
    }

    @Test func namedKeysAreFoundByTheirNames() {
        #expect(Self.matches("control tab", "Tab Switcher", [KeyChord(key: KeyChord.tab, modifiers: Self.control)]))
        #expect(Self.matches("command left", "Go Back", [KeyChord(key: KeyChord.left, modifiers: Self.cmd)]))
        #expect(Self.matches("shift command delete", "Clear Browsing Data…", [KeyChord(key: KeyChord.delete, modifiers: Self.cmd | Self.shift)]))
    }

    @Test func theNameStillMatchesAsBefore() {
        #expect(Self.matches("extensions"))
        #expect(Self.matches("OPEN ext"))
        #expect(!Self.matches("downloads"))
        #expect(Self.matches("", "Anything", []), "an empty field lists everything")
        #expect(Self.matches("   ", "Anything", []))
    }

    @Test func anActionWithoutAKeyIsOnlyFoundByName() {
        #expect(!Self.matches("command e", "Cast", []))
        #expect(Self.matches("cast", "Cast", []))
    }
}
