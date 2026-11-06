import CraCore
import Testing

/// Which clicks the browser window's buttons take while focus is somewhere else.
struct FirstClickTests {
    /// After a click in DevTools or the page, one click on a toolbar button counts (GitHub #42).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/42"))
    func focusInTheWindowOrItsChildren() {
        #expect(FirstClick.takes(appActive: true, focusInWindow: true, closedPopup: false))
    }

    /// The click that takes focus from an extension's popup only closes it, as in Arc: the
    /// popup's own button does not open it again (GitHub #87).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/87"))
    func closingAPopupIsAllTheClickDoes() {
        #expect(!FirstClick.takes(appActive: true, focusInWindow: true, closedPopup: true))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/42"))
    func otherwiseTheClickOnlyFocuses() {
        #expect(!FirstClick.takes(appActive: false, focusInWindow: true, closedPopup: false))
        #expect(!FirstClick.takes(appActive: true, focusInWindow: false, closedPopup: false))
    }
}
