import CraCore
import Testing

struct CommandBarClosingTests {
    /// GitHub #429: ⌘L in window 1, then a click in window 2. The bar lost the keys to window 2 and
    /// closed, and closing gave them back to window 1 in the middle of window 2 taking them: typing and
    /// paste went to window 1's page until Cra was left and reopened. Arc leaves them with window 2.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/429"))
    func anotherWindowKeepsTheKeysItTook() {
        #expect(!CommandBarClosing.lostKeys(to: .otherWindow).barsWindowTakesKeys)
    }

    /// GitHub #551: ⌘T, some typing, another app and back: the bar was gone with what was typed.
    /// Arc 1.173.1 (measured 18 Nov 2026) keeps it open, its text kept and its field focused again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/551"))
    func leavingCraKeepsTheBarOpen() {
        #expect(!CommandBarClosing.closesBar(lostKeysTo: .none))
    }

    /// A click on the bar's window or another Cra window still closes it.
    @Test func aClickInCraClosesTheBar() {
        #expect(CommandBarClosing.closesBar(lostKeysTo: .barsWindow))
        #expect(CommandBarClosing.closesBar(lostKeysTo: .otherWindow))
    }

    /// A pick or Escape hands the keys back to the window's page, as before.
    @Test func closedByTheBarFocusesItsWindow() {
        #expect(CommandBarClosing.byBar.barsWindowTakesKeys)
    }

    /// A click on the bar's own window (its page, sidebar or Peek) closes the bar and keeps the page
    /// focused; leaving Cra leaves the window ready for the keys when Cra comes back.
    @Test func ownWindowOrNoWindowTakesThemBack() {
        #expect(CommandBarClosing.lostKeys(to: .barsWindow).barsWindowTakesKeys)
        #expect(CommandBarClosing.lostKeys(to: .none).barsWindowTakesKeys)
    }
}
