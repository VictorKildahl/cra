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
}
