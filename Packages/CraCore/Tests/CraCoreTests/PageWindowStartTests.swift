import CoreGraphics
import CraCore
import Testing

/// A new page's Chromium window is first shown on a Cra window, not in the primary display's
/// corner (#354).
struct PageWindowStartTests {
    typealias Window = PageWindowStart.Window
    let page = CGSize(width: 10, height: 10)
    // The reporter's desk: the MacBook's display is the primary one (another app full screen on
    // it), Cra is on the external display to its right.
    let primary = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    let onExternal = CGRect(x: 1928, y: 100, width: 1400, height: 880)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/354"))
    func aNewPageWindowStartsOnTheWindowInUseNotOnThePrimaryDisplay() throws {
        let frame = try #require(PageWindowStart.frame(page, among: [Window(frame: onExternal, isInUse: true, isOnScreen: true)]))
        #expect(frame == CGRect(x: 2623, y: 535, width: 10, height: 10))
        #expect(onExternal.contains(frame))
        #expect(!primary.intersects(frame))
    }

    @Test func theWindowInUseWinsOverOneInFrontOfIt() {
        // A Little Window floats in front on the primary display; the click was in the big window.
        let little = Window(frame: CGRect(x: 300, y: 200, width: 800, height: 600), isInUse: false, isOnScreen: true)
        let big = Window(frame: onExternal, isInUse: true, isOnScreen: true)
        #expect(PageWindowStart.frame(page, among: [little, big]) == CGRect(x: 2623, y: 535, width: 10, height: 10))
    }

    @Test func withCraInTheBackgroundItIsTheFrontmostWindowOnScreen() {
        // No window is in use while another app is: a page opened behind, a Calendar favorite read.
        let minimized = Window(frame: CGRect(x: 100, y: 100, width: 1000, height: 700), isInUse: false, isOnScreen: false)
        let shown = Window(frame: onExternal, isInUse: false, isOnScreen: true)
        #expect(PageWindowStart.frame(page, among: [minimized, shown]) == CGRect(x: 2623, y: 535, width: 10, height: 10))
    }

    @Test func aWindowOnAnotherSpaceLosesToOneOnScreen() {
        // The main window sits on a desktop that isn't in front; a window on screen has the page.
        let elsewhere = Window(frame: CGRect(x: 100, y: 100, width: 1000, height: 700), isInUse: true, isOnScreen: false)
        let shown = Window(frame: onExternal, isInUse: false, isOnScreen: true)
        #expect(PageWindowStart.frame(page, among: [elsewhere, shown]) == CGRect(x: 2623, y: 535, width: 10, height: 10))
    }

    @Test func aWindowNotShownYetStillPlacesThePagesRestoredAtLaunch() {
        // Launch: the window has its saved frame before it is on screen.
        let restoring = Window(frame: onExternal, isInUse: false, isOnScreen: false)
        #expect(PageWindowStart.frame(page, among: [restoring]) == CGRect(x: 2623, y: 535, width: 10, height: 10))
        let other = Window(frame: CGRect(x: 100, y: 100, width: 1000, height: 700), isInUse: false, isOnScreen: false)
        let main = Window(frame: onExternal, isInUse: true, isOnScreen: false)
        #expect(PageWindowStart.frame(page, among: [other, main]) == CGRect(x: 2623, y: 535, width: 10, height: 10))
    }

    @Test func withNoWindowItIsChromiumsPlace() {
        #expect(PageWindowStart.frame(page, among: []) == nil)
        // A window without a frame yet is no place either.
        #expect(PageWindowStart.frame(page, among: [Window(frame: .zero, isInUse: true, isOnScreen: true)]) == nil)
    }

    @Test func thePageWindowKeepsItsSizeAndSitsOnWholePoints() {
        let odd = Window(frame: CGRect(x: -1919.5, y: 40, width: 1001, height: 701), isInUse: true, isOnScreen: true)
        #expect(PageWindowStart.frame(CGSize(width: 10, height: 10), among: [odd]) == CGRect(x: -1424, y: 386, width: 10, height: 10))
    }
}
