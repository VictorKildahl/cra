import CraCore
import Testing

/// A mouse's back and forward buttons over the sidebar switch spaces like Arc 1.171 (issue #233).
struct MouseButtonSpaceSwitchTests {
    /// Arc's `SidebarView.otherMouseUp:` sends `focusPreviousSpace` for button 3 (back) and
    /// `focusNextSpace` for button 4 (forward), the actions behind Spaces ▸ Previous/Next Space.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/233"))
    func backGoesToThePreviousSpaceAndForwardToTheNext() {
        #expect(MouseButtonSpaceSwitch.offset(buttonNumber: 3) == -1)
        #expect(MouseButtonSpaceSwitch.offset(buttonNumber: 4) == 1)
    }

    /// Left, right and middle buttons keep their own jobs (a middle click closes a tab, #208).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/233"))
    func otherButtonsDoNotSwitch() {
        for button in [0, 1, 2, 5, 6, -1] {
            #expect(MouseButtonSpaceSwitch.offset(buttonNumber: button) == nil)
        }
    }

    /// An MX Master with Logi Options+ never emits button 3 or 4. Its Back assignment types ⌥←
    /// (key code 123) and Forward types ⌥→ (124). ⌥⌘← is already Previous Space, and ⌥⇧← selects
    /// a word, so only Option alone counts.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/233"))
    func optionLeftIsBackAndOptionRightIsForward() {
        let option = KeyChord.Modifiers.option.rawValue
        #expect(MouseButtonSpaceSwitch.offset(key: KeyChord.left, keyCode: 123, modifiers: option) == -1)
        #expect(MouseButtonSpaceSwitch.offset(key: KeyChord.right, keyCode: 124, modifiers: option) == 1)
        // The injector may leave the characters empty; the arrow's key code is enough.
        #expect(MouseButtonSpaceSwitch.offset(key: "", keyCode: 123, modifiers: option) == -1)
        #expect(MouseButtonSpaceSwitch.offset(key: "", keyCode: 124, modifiers: option) == 1)
    }

    /// ⌘← is Go Back, ⌥⌘← is Previous Space, and ⌥⇧← selects. None of those is the mouse's key.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/233"))
    func otherChordsAreNotTheMouseKey() {
        let option = KeyChord.Modifiers.option.rawValue
        let command = KeyChord.Modifiers.command.rawValue
        let shift = KeyChord.Modifiers.shift.rawValue
        #expect(MouseButtonSpaceSwitch.offset(key: KeyChord.left, keyCode: 123, modifiers: command) == nil)
        #expect(MouseButtonSpaceSwitch.offset(key: KeyChord.left, keyCode: 123, modifiers: option | command) == nil)
        #expect(MouseButtonSpaceSwitch.offset(key: KeyChord.left, keyCode: 123, modifiers: option | shift) == nil)
        #expect(MouseButtonSpaceSwitch.offset(key: KeyChord.left, keyCode: 123, modifiers: 0) == nil)
        #expect(MouseButtonSpaceSwitch.offset(key: "[", keyCode: 33, modifiers: option) == nil)
        // Caps Lock is not a shortcut modifier; ⌥← still counts with it held.
        #expect(MouseButtonSpaceSwitch.offset(key: KeyChord.left, keyCode: 123, modifiers: option | (1 << 16)) == -1)
    }

    /// The same key switches spaces when the pointer is over the sidebar, and goes back or
    /// forward over a page. A text field always keeps ⌥← (it moves by word), wherever the
    /// pointer rests: someone renaming a tab has the pointer on the sidebar.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/233"))
    func optionArrowSwitchesSpaceOverTheSidebarAndGoesBackOverAPage() {
        #expect(MouseButtonSpaceSwitch.action(offset: -1, pointerOverSidebar: true, editingText: false, isRepeat: false) == .switchSpace(-1))
        #expect(MouseButtonSpaceSwitch.action(offset: 1, pointerOverSidebar: true, editingText: false, isRepeat: false) == .switchSpace(1))
        #expect(MouseButtonSpaceSwitch.action(offset: -1, pointerOverSidebar: false, editingText: false, isRepeat: false) == .history(-1))
        #expect(MouseButtonSpaceSwitch.action(offset: 1, pointerOverSidebar: false, editingText: false, isRepeat: false) == .history(1))
        #expect(MouseButtonSpaceSwitch.action(offset: -1, pointerOverSidebar: false, editingText: true, isRepeat: false) == nil)
        #expect(MouseButtonSpaceSwitch.action(offset: 1, pointerOverSidebar: true, editingText: true, isRepeat: false) == nil)
    }

    /// Holding the button must not walk every space or the whole history, so a repeat of a key
    /// the button acts on is swallowed. A repeat in a text field is someone holding ⌥← to move
    /// word by word, and goes through like the first press.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/233"))
    func aHeldButtonActsOnceButAHeldKeyInTextKeepsMoving() {
        #expect(MouseButtonSpaceSwitch.action(offset: -1, pointerOverSidebar: true, editingText: false, isRepeat: true) == .swallow)
        #expect(MouseButtonSpaceSwitch.action(offset: 1, pointerOverSidebar: false, editingText: false, isRepeat: true) == .swallow)
        #expect(MouseButtonSpaceSwitch.action(offset: -1, pointerOverSidebar: false, editingText: true, isRepeat: true) == nil)
        #expect(MouseButtonSpaceSwitch.action(offset: -1, pointerOverSidebar: true, editingText: true, isRepeat: true) == nil)
    }
}
