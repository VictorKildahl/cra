import CoreGraphics
import CraCore
import Foundation
import Testing

/// #607: a Little Window opened from another app leaves the browser window behind that app's
/// windows, as Arc's Little Arc does, on whichever display each is.
struct LittleWindowRaiseTests {
    static let cra: Int32 = 900, slack: Int32 = 501, mail: Int32 = 502
    // Two displays side by side: the browser window on the left one, the Little Window on the right.
    static let left = CGRect(x: 100, y: 100, width: 1200, height: 800)
    static let right = CGRect(x: 2000, y: 200, width: 900, height: 700)

    static func browser(_ n: Int = 10) -> StackedWindow { StackedWindow(number: n, pid: cra, bounds: left) }
    static func little() -> StackedWindow { StackedWindow(number: 20, pid: cra, bounds: right) }
    static func slackOverBrowser() -> StackedWindow { StackedWindow(number: 30, pid: slack, bounds: left.insetBy(dx: 50, dy: 50)) }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/607"))
    func theBrowserWindowGoesBackBehindTheAppTheLinkCameFrom() {
        // Before: Slack over the browser window on the left display.
        let before = [Self.slackOverBrowser(), Self.browser()]
        let anchor = LittleWindowRaise.anchor(for: 10, in: before, pid: Self.cra)
        #expect(anchor == 30)
        #expect(LittleWindowRaise.othersOver(10, in: before, pid: Self.cra) == 1)
        // After: the Little Window on the right, and the browser window risen over Slack. It goes back behind Slack.
        let after = [Self.little(), Self.browser(), Self.slackOverBrowser()]
        #expect(LittleWindowRaise.othersOver(10, in: after, pid: Self.cra) == 0)
        #expect(LittleWindowRaise.goesBack(10, behind: 30, in: after))
        // Also while the window server's list doesn't show the raise yet: ordered behind Slack, it stays where it was.
        #expect(LittleWindowRaise.goesBack(10, behind: 30, in: [Self.little(), Self.slackOverBrowser(), Self.browser()]))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/607"))
    func itGoesBackBehindTheNearestWindowOverIt() {
        // Mail over Slack over the browser window: it goes back just behind Slack, the window in front of it.
        let mailWindow = StackedWindow(number: 31, pid: Self.mail, bounds: Self.left)
        #expect(LittleWindowRaise.anchor(for: 10, in: [mailWindow, Self.slackOverBrowser(), Self.browser()], pid: Self.cra) == 30)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/607"))
    func itGoesBackAsTheLinkArrivesThoughItIsKeyFromCraComingForward() {
        // Cra coming forward gives the browser window the keys back: it goes back as the link arrives, before the
        // Little Window has had them. Skipping key windows left it in front until the Little Window had grown in.
        let after = [Self.browser(), Self.slackOverBrowser()]
        #expect(LittleWindowRaise.goesBack(10, behind: 30, in: after, isKey: true, clickedIfKey: false))
        // Once the Little Window has had the keys, a key browser window was clicked: it is in use and stays in front.
        #expect(!LittleWindowRaise.goesBack(10, behind: 30, in: after, isKey: true, clickedIfKey: true))
        #expect(LittleWindowRaise.goesBack(10, behind: 30, in: after, isKey: false, clickedIfKey: true))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/607"))
    func onlyOtherAppsNormalWindowsOverItCount() {
        let elsewhere = StackedWindow(number: 32, pid: Self.slack, bounds: Self.right)        // on the other display
        let menuBar = StackedWindow(number: 33, pid: Self.mail, layer: 25, bounds: Self.left) // a status item, a floating panel
        let ownPanel = StackedWindow(number: 34, pid: Self.cra, bounds: Self.left)            // Cra's own
        let stack = [elsewhere, menuBar, ownPanel, Self.browser()]
        #expect(LittleWindowRaise.anchor(for: 10, in: stack, pid: Self.cra) == nil)
        #expect(LittleWindowRaise.othersOver(10, in: stack, pid: Self.cra) == 0)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/607"))
    func nothingMovesWhenTheBrowserWindowWasInFrontOrTheOtherWindowWent() {
        // In front already: nothing to go back behind.
        #expect(LittleWindowRaise.anchor(for: 10, in: [Self.browser(), Self.slackOverBrowser()], pid: Self.cra) == nil)
        // Slack's window closed (or went to another Space) while the Little Window came up.
        #expect(!LittleWindowRaise.goesBack(10, behind: 30, in: [Self.little(), Self.browser()]))
        // The browser window itself went (closed, minimized).
        #expect(!LittleWindowRaise.goesBack(10, behind: 30, in: [Self.little(), Self.slackOverBrowser()]))
        #expect(LittleWindowRaise.anchor(for: 99, in: [Self.slackOverBrowser()], pid: Self.cra) == nil)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/607"))
    func readsTheWindowServersList() {
        let info: [[String: Any]] = [
            [kCGWindowNumber as String: 30, kCGWindowOwnerPID as String: Self.slack, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: CGRect(x: 150, y: 150, width: 400, height: 300).dictionaryRepresentation],
            [kCGWindowNumber as String: 40, kCGWindowOwnerPID as String: Self.mail],   // no bounds: left out
            [kCGWindowNumber as String: 10, kCGWindowOwnerPID as String: Self.cra, kCGWindowLayer as String: 0,
             kCGWindowBounds as String: Self.left.dictionaryRepresentation],
        ]
        let stack = StackedWindow.stack(from: info)
        #expect(stack.map(\.number) == [30, 10])
        #expect(stack.first?.bounds == CGRect(x: 150, y: 150, width: 400, height: 300))
        #expect(LittleWindowRaise.othersOver(10, in: info, pid: Self.cra) == 1)
    }
}
