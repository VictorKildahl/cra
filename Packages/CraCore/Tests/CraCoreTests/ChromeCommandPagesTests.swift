import Testing
@testable import CraCore

@Suite struct ChromeCommandPagesTests {
    final class Page { let name: String; init(_ name: String) { self.name = name } }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/855"))
    func theTaskManagerOpensWithNoPageInFront() {
        let a = Page("a"), b = Page("b"), little = Page("little")
        // No tab selected: the window's other pages, then the Little Window's, are asked.
        #expect(ChromeCommandPages.order(front: nil, sameWindow: [a], elsewhere: [little]).map(\.name) == ["a", "little"])
        #expect(ChromeCommandPages.order(front: nil, sameWindow: [], elsewhere: [little]).map(\.name) == ["little"])
        // The page in front goes first, and no page is asked twice.
        #expect(ChromeCommandPages.order(front: b, sameWindow: [a, b], elsewhere: [b, little]).map(\.name) == ["b", "a", "little"])
        // No page at all: nothing to ask ("Open a Page First").
        #expect(ChromeCommandPages.order(front: nil as Page?, sameWindow: [], elsewhere: []).isEmpty)
    }
}

@Suite struct EscapeShortcutTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/855"))
    func shiftEscapeCanBeTheTaskManagersShortcut() {
        let shift = KeyChord.Modifiers.shift.rawValue
        // Settings ▸ Shortcuts: ⇧⎋ is recorded, plain Esc still stops recording, ⌫ still clears.
        #expect(KeyChord.recordingStep(keyCode: 53, modifiers: shift) == .record)
        #expect(KeyChord.recordingStep(keyCode: 53, modifiers: 0) == .cancel)
        #expect(KeyChord.recordingStep(keyCode: 51, modifiers: 0) == .clear)
        #expect(KeyChord.isRecordable(key: KeyChord.escape, modifiers: shift))
        #expect(!KeyChord.isRecordable(key: KeyChord.escape, modifiers: 0))
        #expect(KeyChord(key: KeyChord.escape, modifiers: shift).display == "⇧⎋")
        // As before: a bare letter or ⇧ with a letter is typing, ⌘ makes it a shortcut, Tab and F-keys stand alone.
        #expect(!KeyChord.isRecordable(key: "a", modifiers: shift))
        #expect(KeyChord.isRecordable(key: "a", modifiers: KeyChord.Modifiers.command.rawValue))
        #expect(KeyChord.isRecordable(key: KeyChord.tab, modifiers: 0))
        #expect(KeyChord.isRecordable(key: KeyChord.f12, modifiers: 0))
    }
}
