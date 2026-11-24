import Foundation
import CraCore
import Testing

/// #430: a Little Window opened from another app gives that app the keyboard back when it closes,
/// as Arc's Little Arc does, instead of bringing the browser window (and its Space) forward.
struct LittleWindowReturnTests {
    static let slack: Int32 = 501, mail: Int32 = 502, cra: Int32 = 900
    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/430"))
    func aLinkFromAnotherAppClosesBackToThatApp() {
        var history = FrontmostAppHistory()
        history.activated(Self.slack, isCra: false, at: Self.t0)
        // The link arrives before Cra comes forward…
        #expect(history.returnApp(at: Self.t0 + 5) == Self.slack)
        // …or just after LaunchServices brought it forward for the link.
        history.activated(Self.cra, isCra: true, at: Self.t0 + 10)
        #expect(history.returnApp(at: Self.t0 + 10.3) == Self.slack)

        var back = LittleWindowReturn(app: history.returnApp(at: Self.t0 + 10.3))
        // AppKit makes the browser window key as Cra comes forward, before the Little Window shows.
        back.otherWindowBecameKey()
        back.littleWindowBecameKey()
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: false) == Self.slack)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/430"))
    func aLittleWindowOpenedInCraClosesBackToTheBrowser() {
        var history = FrontmostAppHistory(frontmost: Self.slack)
        history.activated(Self.cra, isCra: true, at: Self.t0)
        // ⌥⌘N or a page's popup, with the browser in use for a while.
        #expect(history.returnApp(at: Self.t0 + 30) == nil)
        #expect(LittleWindowReturn(app: nil).target(closingKeyWindow: true, craActive: true, movedToTab: false) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/430"))
    func usingTheBrowserWindowMeanwhileKeepsItInFront() {
        var back = LittleWindowReturn(app: Self.slack)
        back.littleWindowBecameKey()
        back.otherWindowBecameKey()
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: false) == nil)
        // Not even after the Little Window has the keyboard again.
        back.littleWindowBecameKey()
        back.craCameForward(from: Self.mail)
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: false) == nil)
    }

    /// #659: another link, or a click back from another app, brings Cra forward, and AppKit makes the browser
    /// window key on the way, before the Little Window it gives the keyboard back to. That isn't the browser in
    /// use: a Little Window that already had the keyboard still closes back to the app.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/659"))
    func theBrowserWindowKeyWhileCraComesForwardIsNotUse() {
        var back = LittleWindowReturn(app: Self.slack)
        back.littleWindowBecameKey()
        back.otherWindowBecameKey(whileComingForward: true)
        back.craCameForward(from: Self.slack)
        back.littleWindowBecameKey()
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: false) == Self.slack)
        // Once Cra is in front, the browser window taking the keyboard is the browser in use, as before (#430).
        back.otherWindowBecameKey(whileComingForward: false)
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: false) == nil)
    }

    /// #659: Slack in front, the Little Window beside it on another display, its close button clicked. The window
    /// server brings Cra forward for the click, but the button closes the window before AppKit makes Cra active.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/659"))
    func closeButtonClickedFromAnotherAppGoesBackToIt() {
        let close = LittleWindowClose(keyIsThisWindow: false, craActive: false, craFrontmost: true, clickedInWindow: true)
        #expect(close.closingKeyWindow && close.craActive)
        var back = LittleWindowReturn(app: Self.slack)
        back.littleWindowBecameKey()
        #expect(back.target(closingKeyWindow: close.closingKeyWindow, craActive: close.craActive, movedToTab: false) == Self.slack)
        // Closed in the background without a click (archived, the page's window.close()): Cra stays behind.
        let idle = LittleWindowClose(keyIsThisWindow: false, craActive: false, craFrontmost: false, clickedInWindow: false)
        #expect(!idle.closingKeyWindow && !idle.craActive)
        // A click elsewhere while Cra comes forward isn't this window in use.
        let other = LittleWindowClose(keyIsThisWindow: false, craActive: false, craFrontmost: true, clickedInWindow: false)
        #expect(!other.closingKeyWindow && !other.craActive)
        // In front as usual: as before.
        let usual = LittleWindowClose(keyIsThisWindow: true, craActive: true, craFrontmost: true, clickedInWindow: false)
        #expect(usual.closingKeyWindow && usual.craActive)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/430"))
    func comingBackFromAnotherAppReturnsThere() {
        var back = LittleWindowReturn(app: Self.slack)
        back.littleWindowBecameKey()
        // ⌘Tab to Mail, then back to the Little Window.
        back.craCameForward(from: Self.mail)
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: false) == Self.mail)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/430"))
    func onlyAClosedKeyWindowInFrontHandsTheKeyboardOver() {
        var back = LittleWindowReturn(app: Self.slack)
        back.littleWindowBecameKey()
        // Archived after sitting idle behind another window, or closed while Cra is behind.
        #expect(back.target(closingKeyWindow: false, craActive: true, movedToTab: false) == nil)
        #expect(back.target(closingKeyWindow: true, craActive: false, movedToTab: false) == nil)
        // Moved into a tab: the browser window is where the page went.
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: true) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/430"))
    func anotherAppComingForwardResetsCrasTime() {
        var history = FrontmostAppHistory()
        history.activated(Self.cra, isCra: true, at: Self.t0)
        history.activated(Self.mail, isCra: false, at: Self.t0 + 60)
        #expect(history.craFrontSince == nil)
        #expect(history.returnApp(at: Self.t0 + 61) == Self.mail)
        history.activated(Self.cra, isCra: true, at: Self.t0 + 62)
        #expect(history.beforeCra == Self.mail)
        #expect(history.returnApp(at: Self.t0 + 62 + FrontmostAppHistory.linkGrace) == Self.mail)
        #expect(history.returnApp(at: Self.t0 + 62 + FrontmostAppHistory.linkGrace + 0.1) == nil)
    }
}

/// #646: ⌘W on one of several Little Windows opened from another app.
struct LittleWindowCloseNextTests {
    static let slack: Int32 = 501

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/646"))
    func theNextLittleWindowTakesTheKeyboardNotTheApp() {
        var back = LittleWindowReturn(app: Self.slack)
        back.littleWindowBecameKey()
        // Two more are open: Slack stays where it is, and the front one of them takes the keyboard.
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: false, littleWindowsLeft: true) == nil)
        #expect(LittleWindowReturn.nextTakesKeyboard(closingKeyWindow: true, craActive: true, movedToTab: false, littleWindowsLeft: true))
        // The last one closes back to Slack (#430).
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: false, littleWindowsLeft: false) == Self.slack)
        #expect(!LittleWindowReturn.nextTakesKeyboard(closingKeyWindow: true, craActive: true, movedToTab: false, littleWindowsLeft: false))
    }

    /// Little Windows on two desktops: closing the last one on this desktop goes back to the app in use here. The one
    /// on the other desktop took the keyboard instead, and macOS switched to that desktop (#738). One showing on
    /// another display is on a Space in front, so it still takes the keyboard (#646).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/738"))
    func aLittleWindowOnAnotherDesktopDoesntTakeTheKeyboard() {
        #expect(LittleWindowReturn.canTakeKeyboard(isPeek: false, visible: true, miniaturized: false, onActiveSpace: true))
        #expect(!LittleWindowReturn.canTakeKeyboard(isPeek: false, visible: true, miniaturized: false, onActiveSpace: false))
        #expect(!LittleWindowReturn.canTakeKeyboard(isPeek: true, visible: true, miniaturized: false, onActiveSpace: true))
        #expect(!LittleWindowReturn.canTakeKeyboard(isPeek: false, visible: false, miniaturized: false, onActiveSpace: true))
        #expect(!LittleWindowReturn.canTakeKeyboard(isPeek: false, visible: true, miniaturized: true, onActiveSpace: true))
        // None left on this desktop: the closing window's app comes back, as when the last one closes.
        var back = LittleWindowReturn(app: Self.slack)
        back.littleWindowBecameKey()
        #expect(back.target(closingKeyWindow: true, craActive: true, movedToTab: false, littleWindowsLeft: false) == Self.slack)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/646"))
    func aCloseInTheBackgroundMovesNothingForward() {
        // An idle archive or a close while another app is in front: no window is raised.
        #expect(!LittleWindowReturn.nextTakesKeyboard(closingKeyWindow: false, craActive: true, movedToTab: false, littleWindowsLeft: true))
        #expect(!LittleWindowReturn.nextTakesKeyboard(closingKeyWindow: true, craActive: false, movedToTab: false, littleWindowsLeft: true))
        // Moved into a tab: the browser window is in use.
        #expect(!LittleWindowReturn.nextTakesKeyboard(closingKeyWindow: true, craActive: true, movedToTab: true, littleWindowsLeft: true))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/659"))
    func theKeyboardStaysHeldUntilCraLetsGoOfTheFront() {
        // The close button clicked with the browser window on another display, under the app in use there: Cra
        // becomes active only after the window closed, and the hold keeps the keyboard from the browser window.
        let hold = KeyboardHold(at: LittleWindowReturnTests.t0)
        #expect(!hold.releases(craResigned: false, at: LittleWindowReturnTests.t0))
        #expect(!hold.releases(craResigned: false, at: LittleWindowReturnTests.t0 + 0.07))
        #expect(hold.releases(craResigned: true, at: LittleWindowReturnTests.t0 + 0.07))
        // Slack never took the front: the hold still goes, and AppKit picks Cra's window as before.
        #expect(hold.releases(craResigned: false, at: LittleWindowReturnTests.t0 + KeyboardHold.limit))
    }
}
