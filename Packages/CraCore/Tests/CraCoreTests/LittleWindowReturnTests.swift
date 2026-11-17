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
