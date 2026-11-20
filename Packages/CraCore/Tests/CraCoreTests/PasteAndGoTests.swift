import CraCore
import Testing

/// ⌥⌘V opens the clipboard as a new tab, or pastes while you type (#610).
struct PasteAndGoTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/610"))
    func opensTheClipboardUnlessTyping() {
        #expect(PasteAndGo.outcome(typing: false, clipboard: "https://example.com/a") == .open("https://example.com/a"))
        #expect(PasteAndGo.outcome(typing: false, clipboard: "  best pizza\n in town ") == .open("best pizza in town"))
        #expect(PasteAndGo.outcome(typing: true, clipboard: "https://example.com/a") == .paste, "a text field just pastes")
        #expect(PasteAndGo.outcome(typing: true, clipboard: nil) == .paste)
        #expect(PasteAndGo.outcome(typing: false, clipboard: nil) == .nothing)
        #expect(PasteAndGo.outcome(typing: false, clipboard: " \n\t") == .nothing)
        #expect(PasteAndGo.outcome(typing: false, clipboard: String(repeating: "a", count: 2049)) == .nothing)
        // Cra takes the press before the page: a page that has the keys never hands an unused ⌥⌘V back
        // (real keys, 20 Nov 2026; the paste-and-go scenario).
        #expect(ShortcutPriority.defaultPriority(for: "pasteAndGo") == .preferCra)
    }
}
