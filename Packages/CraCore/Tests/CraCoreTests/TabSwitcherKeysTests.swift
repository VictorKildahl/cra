import CraCore
import Testing

/// What a key does while the tab switcher is open with ⌃ held (Arc's ModalItemSwitcher).
struct TabSwitcherKeysTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/696"))
    func graveGoesBackLikeTheAppSwitcher() {
        // ⌃` steps back, as ` does in macOS's ⌘Tab switcher and in Arc; ⌃⇧` forward again.
        // The key above Tab: kVK_ANSI_Grave (50), and 10 on an ISO keyboard (§, a Danish Mac's ½).
        #expect(TabSwitcherKeys.action(keyCode: 50, shift: false) == .move(-1))
        #expect(TabSwitcherKeys.action(keyCode: 10, shift: false) == .move(-1))
        #expect(TabSwitcherKeys.action(keyCode: 50, shift: true) == .move(1))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/696"))
    func theOtherKeysStayAsTheyWere() {
        #expect(TabSwitcherKeys.action(keyCode: 48, shift: false) == .move(1))   // Tab
        #expect(TabSwitcherKeys.action(keyCode: 48, shift: true) == .move(-1))   // ⇧Tab
        #expect(TabSwitcherKeys.action(keyCode: 124, shift: false) == .move(1))  // →
        #expect(TabSwitcherKeys.action(keyCode: 123, shift: false) == .move(-1)) // ←
        #expect(TabSwitcherKeys.action(keyCode: 53, shift: false) == .cancel)    // Esc
        #expect(TabSwitcherKeys.action(keyCode: 36, shift: false) == .commit)    // Return
        #expect(TabSwitcherKeys.action(keyCode: 76, shift: false) == .commit)    // Enter
        #expect(TabSwitcherKeys.action(keyCode: 0, shift: false) == nil)         // A
    }
}
