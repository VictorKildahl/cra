import CraCore
import Testing

/// ⌥← / ⌥→ typed on the keyboard belong to whoever has the keyboard, as in Arc, Chrome and Safari: YouTube's
/// previous and next chapter, a word in a text field. Cra went back or forward in the tab's history with them, so a
/// YouTube video left its page (#714). Only the keystrokes another app posts (Logi Options+ types them for a mouse's
/// side buttons, #233) still go back and forward over a page and switch spaces over the sidebar.
@Suite struct OptionArrowsOnThePageTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/714"))
    func theKeyboardsOptionArrowsGoToThePage() {
        for offset in [-1, 1] {
            #expect(MouseButtonSpaceSwitch.action(offset: offset, pointerOverSidebar: false, editingText: false, isRepeat: false, typedOnKeyboard: true) == nil)
            #expect(MouseButtonSpaceSwitch.action(offset: offset, pointerOverSidebar: true, editingText: false, isRepeat: false, typedOnKeyboard: true) == nil)
            #expect(MouseButtonSpaceSwitch.action(offset: offset, pointerOverSidebar: false, editingText: false, isRepeat: true, typedOnKeyboard: true) == nil)
        }
    }

    /// A mouse driver's ⌥← still goes back over a page and switches spaces over the sidebar (#233).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/714"))
    func aMouseDriversOptionArrowsStillGoBack() {
        #expect(MouseButtonSpaceSwitch.action(offset: -1, pointerOverSidebar: false, editingText: false, isRepeat: false, typedOnKeyboard: false) == .history(-1))
        #expect(MouseButtonSpaceSwitch.action(offset: 1, pointerOverSidebar: true, editingText: false, isRepeat: false, typedOnKeyboard: false) == .switchSpace(1))
    }

    /// A key the keyboard typed comes from the window server (source process 0); one another app posted carries that
    /// app's process ID (CGEvent's eventSourceUnixProcessID).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/714"))
    func theKeyboardIsSourceProcessZero() {
        #expect(MouseButtonSpaceSwitch.typedOnKeyboard(sourcePID: 0))
        #expect(!MouseButtonSpaceSwitch.typedOnKeyboard(sourcePID: 4321))
    }
}
