import CraCore
import Testing

/// The click that closes the command bar doesn't reopen it (#88).
struct DismissingClickTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/88"))
    func theClosingClickDoesNotReopen() {
        var d = DismissingClick()
        d.panelClosed(byMouseDownAt: 100)
        let first = d.isClosingClick(lastMouseDown: 100.01)
        let second = d.isClosingClick(lastMouseDown: 100.01)
        #expect(first, "the same click's mouse-up: stays closed")
        #expect(!second, "asked once per close")
    }

    /// The next click on the address opens the bar again (#88).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/88"))
    func theNextClickOpens() {
        var d = DismissingClick()
        d.panelClosed(byMouseDownAt: 100)
        let later = d.isClosingClick(lastMouseDown: 101.2)
        #expect(!later, "a later click opens the bar")
    }

    /// Closed by Escape or another app, the next click opens it (#88).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/88"))
    func closedWithoutAClick() {
        var d = DismissingClick()
        d.panelClosed(byMouseDownAt: nil)
        let next = d.isClosingClick(lastMouseDown: 100)
        var fresh = DismissingClick()
        let none = fresh.isClosingClick(lastMouseDown: 0)
        #expect(!next, "Esc or another app: the next click opens")
        #expect(!none, "never closed")
    }
}
