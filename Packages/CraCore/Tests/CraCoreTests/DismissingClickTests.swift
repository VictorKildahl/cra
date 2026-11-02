import CraCore
import Testing

/// The click that closes the command bar doesn't reopen it (#88).
struct DismissingClickTests {
    @Test func theClosingClickDoesNotReopen() {
        var d = DismissingClick()
        d.panelClosed(byMouseDownAt: 100)
        let first = d.isClosingClick(lastMouseDown: 100.01)
        let second = d.isClosingClick(lastMouseDown: 100.01)
        #expect(first, "the same click's mouse-up: stays closed")
        #expect(!second, "asked once per close")
    }

    @Test func theNextClickOpens() {
        var d = DismissingClick()
        d.panelClosed(byMouseDownAt: 100)
        let later = d.isClosingClick(lastMouseDown: 101.2)
        #expect(!later, "a later click opens the bar")
    }

    @Test func closedWithoutAClick() {
        var d = DismissingClick()
        d.panelClosed(byMouseDownAt: nil)
        let next = d.isClosingClick(lastMouseDown: 100)
        var fresh = DismissingClick()
        let none = fresh.isClosingClick(lastMouseDown: 0)
        #expect(!next, "Esc or another app: the next click opens")
        #expect(!none, "never closed")
    }
}
