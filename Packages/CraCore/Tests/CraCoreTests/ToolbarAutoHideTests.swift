import CoreGraphics
import CraCore
import Foundation
import Testing

/// Settings ▸ Tabs ▸ "Hide the toolbar until the pointer reaches the top of the page": the toolbar
/// floats over the page and the pointer at the card's top edge brings it out.
struct ToolbarAutoHideTests {
    /// A 1000 × 700 card 10 pt inside a 1300 × 720 container, as beside a sidebar. y grows upward.
    let container = CGRect(x: 0, y: 0, width: 1300, height: 720)
    let card = CGRect(x: 290, y: 10, width: 1000, height: 700)
    let bar: CGFloat = 32

    // MARK: The setting

    @Test func offByDefaultAndKeptInSettingsJSON() throws {
        #expect(!AppSettings().autoHideToolbar)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"showToolbar": true, "toolbarDefaultMigrated": true}"#.utf8))
        #expect(!old.autoHideToolbar)
        var settings = AppSettings()
        settings.showToolbar = true
        settings.autoHideToolbar = true
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(saved.autoHideToolbar)
        #expect(saved == settings)
    }

    @Test func onlyAShownToolbarHides() {
        var settings = AppSettings()
        settings.autoHideToolbar = true
        // The address bar is in the sidebar: there is no toolbar to hide.
        #expect(!settings.hidesToolbar(above: "https://example.com/"))
        settings.showToolbar = true
        #expect(settings.hidesToolbar(above: "https://example.com/"))
        #expect(settings.hidesToolbar(above: nil))
        settings.autoHideToolbar = false
        #expect(!settings.hidesToolbar(above: "https://example.com/"))
    }

    /// The developer bar is there to be seen: it stays above the page.
    @Test func theDeveloperBarStays() {
        var settings = AppSettings()
        settings.showToolbar = true
        settings.autoHideToolbar = true
        #expect(!settings.hidesToolbar(above: "http://localhost:3000/"))
        settings.toggleDeveloperMode(url: "https://example.com/")
        #expect(!settings.hidesToolbar(above: "https://example.com/page"))
        #expect(settings.hidesToolbar(above: "https://example.org/"))
    }

    // MARK: When it floats

    @Test func floatsOnlyOverAPageShownAlone() {
        func floats(enabled: Bool = true, toolbarShown: Bool = true, panes: Int = 1, developerBar: Bool = false,
                    devToolsOpen: Bool = false, pageFullscreen: Bool = false) -> Bool {
            ToolbarAutoHide.floats(enabled: enabled, toolbarShown: toolbarShown, panes: panes, developerBar: developerBar,
                                   devToolsOpen: devToolsOpen, pageFullscreen: pageFullscreen)
        }
        #expect(floats())
        #expect(!floats(enabled: false))
        #expect(!floats(toolbarShown: false))
        // A split's panes keep their bars.
        #expect(!floats(panes: 2))
        #expect(!floats(developerBar: true))
        // With DevTools open the page is in its own window, which nothing of Cra's floats over.
        #expect(!floats(devToolsOpen: true))
        #expect(!floats(pageFullscreen: true))
    }

    // MARK: Where the pointer counts

    @Test func theStripIsTheTopOfTheCardAndTheMarginAboveIt() {
        func strip(_ x: CGFloat, _ y: CGFloat) -> Bool { ToolbarAutoHide.inRevealStrip(CGPoint(x: x, y: y), card: card, container: container) }
        // The card's top edge is at y 710.
        #expect(strip(700, 710))
        #expect(strip(700, 710 - ToolbarAutoHide.revealInside))
        #expect(!strip(700, 710 - ToolbarAutoHide.revealInside - 1))
        // The margin above the card, and just outside the window.
        #expect(strip(700, 715))
        #expect(strip(700, 720 + ToolbarAutoHide.revealOutside))
        #expect(!strip(700, 720 + ToolbarAutoHide.revealOutside + 1))
        // Above the sidebar is not above the page.
        #expect(!strip(289, 712))
        #expect(strip(290, 712))
        #expect(strip(1290, 712))
        #expect(!strip(1291, 712))
    }

    @Test func aToolbarThatIsOutIsKeptFromOnItAndALittleUnderIt() {
        func keep(_ x: CGFloat, _ y: CGFloat) -> Bool {
            ToolbarAutoHide.inKeepZone(CGPoint(x: x, y: y), card: card, container: container, barHeight: bar)
        }
        // The bar covers y 678…710.
        #expect(keep(700, 700))
        #expect(keep(700, 678))
        #expect(keep(700, 678 - ToolbarAutoHide.leaveSlack))
        #expect(!keep(700, 678 - ToolbarAutoHide.leaveSlack - 1))
        #expect(keep(700, 718))
        #expect(!keep(100, 700))
    }

    @Test func classifyTellsTheStripTheBarAndThePageApart() {
        func classify(_ y: CGFloat, shown: Bool) -> ToolbarAutoHide.Pointer {
            ToolbarAutoHide.classify(CGPoint(x: 700, y: y), card: card, container: container, barHeight: bar, shown: shown)
        }
        #expect(classify(708, shown: false) == .strip)
        #expect(classify(708, shown: true) == .strip)
        // Where the bar would be counts only while it is out.
        #expect(classify(690, shown: false) == .away)
        #expect(classify(690, shown: true) == .bar)
        #expect(classify(400, shown: true) == .away)
    }

    /// A popover under one of the bar's buttons keeps the bar out; the page's window and the
    /// overlay panel, which cover the card, are not hanging from it.
    @Test func aPopoverUnderTheBarHangsFromItAndThePageDoesNot() {
        func hangs(_ frame: CGRect) -> Bool { ToolbarAutoHide.hangsFromBar(frame, card: card, barHeight: bar) }
        // The bar's bottom is at y 678; Cra's popovers overlap it by 4 pt.
        #expect(hangs(CGRect(x: 900, y: 382, width: 320, height: 300)))
        #expect(hangs(CGRect(x: 900, y: 370, width: 320, height: 300)))
        // Too far under it, or over the bar itself.
        #expect(!hangs(CGRect(x: 900, y: 340, width: 320, height: 300)))
        #expect(!hangs(CGRect(x: 900, y: 420, width: 320, height: 300)))
        // The page's own window: under the bar when it sits above the page, and as wide as the card.
        #expect(!hangs(CGRect(x: 290, y: 10, width: 1000, height: 668)))
        // Beside the card, over the sidebar.
        #expect(!hangs(CGRect(x: 0, y: 382, width: 280, height: 300)))
    }

    /// The find bar hangs under a toolbar that is out (`FindBarPlacement`). A pointer on it keeps the
    /// toolbar, so the find bar doesn't slide back to the corner from under the pointer; the find
    /// bar itself brings nothing out, and off it the pointer lets the toolbar go as before.
    @Test func thePointerOnWhatFollowsTheBarKeepsIt() {
        // Under the bar (y 678…710) with the find bar's 10 pt inset: y 630…668, far below the 16 pt slack.
        let findBar = CGRect(x: 980, y: 630, width: 300, height: 38)
        func classify(_ x: CGFloat, _ y: CGFloat, shown: Bool, followers: [CGRect]) -> ToolbarAutoHide.Pointer {
            ToolbarAutoHide.classify(CGPoint(x: x, y: y), card: card, container: container, barHeight: bar, shown: shown,
                                     followers: followers)
        }
        #expect(classify(1100, 640, shown: true, followers: []) == .away)
        #expect(classify(1100, 640, shown: true, followers: [findBar]) == .bar)
        #expect(classify(700, 640, shown: true, followers: [findBar]) == .away)
        #expect(classify(1100, 600, shown: true, followers: [findBar]) == .away)
        // While the toolbar is away the find bar is only the find bar.
        #expect(classify(1100, 640, shown: false, followers: [findBar]) == .away)
    }

    // MARK: Coming out and going

    @Test func comesOutOnceThePointerHasRestedInTheStrip() {
        var tracker = ToolbarAutoHideTracker()
        let look = tracker.sample(.strip, at: 10)
        #expect(!tracker.shown)
        #expect(look == 10 + ToolbarAutoHide.revealDwell)
        // The pointer rests: no more samples, only the look the first one asked for.
        #expect(tracker.tick(at: 10 + ToolbarAutoHide.revealDwell) == nil)
        #expect(tracker.shown)
    }

    @Test func aPointerPassingOverTheEdgeBringsNothingOut() {
        var tracker = ToolbarAutoHideTracker()
        tracker.sample(.strip, at: 10)
        #expect(tracker.sample(.away, at: 10.04) == nil)
        tracker.tick(at: 10 + ToolbarAutoHide.revealDwell)
        #expect(!tracker.shown)
        // Coming back starts the wait over.
        #expect(tracker.sample(.strip, at: 10.08) == 10.08 + ToolbarAutoHide.revealDwell)
        tracker.tick(at: 10 + ToolbarAutoHide.revealDwell + 0.01)
        #expect(!tracker.shown)
        tracker.tick(at: 10.08 + ToolbarAutoHide.revealDwell)
        #expect(tracker.shown)
    }

    @Test func staysWhileThePointerIsOnItAndGoesAWhileAfterItLeft() {
        var tracker = ToolbarAutoHideTracker()
        tracker.bringOut()
        #expect(tracker.sample(.bar, at: 20) == nil)
        #expect(tracker.tick(at: 30) == nil)
        #expect(tracker.shown)
        let look = tracker.sample(.away, at: 31)
        #expect(look == 31 + ToolbarAutoHide.hideDelay)
        #expect(tracker.shown)
        tracker.tick(at: 31 + ToolbarAutoHide.hideDelay)
        #expect(!tracker.shown)
    }

    @Test func aHandThatSlipsOffAndComesBackKeepsIt() {
        var tracker = ToolbarAutoHideTracker()
        tracker.bringOut()
        tracker.sample(.away, at: 40)
        tracker.sample(.bar, at: 40.2)
        tracker.tick(at: 40 + ToolbarAutoHide.hideDelay)
        #expect(tracker.shown)
        // Leaving again waits the whole delay again.
        tracker.sample(.away, at: 41)
        tracker.tick(at: 41 + ToolbarAutoHide.hideDelay - 0.01)
        #expect(tracker.shown)
        tracker.tick(at: 41 + ToolbarAutoHide.hideDelay)
        #expect(!tracker.shown)
    }

    /// A mouse button held down (a drag from the bar, a menu being pulled) or something hanging
    /// under the bar keeps it out, however far the pointer goes.
    @Test func heldStaysOut() {
        var tracker = ToolbarAutoHideTracker()
        tracker.bringOut()
        #expect(tracker.sample(.away, held: true, at: 50) == nil)
        tracker.tick(at: 60)
        #expect(tracker.shown)
        // Let go: the delay counts from there, not from when the pointer left.
        #expect(tracker.tick(held: false, at: 60) == 60 + ToolbarAutoHide.hideDelay)
        tracker.tick(at: 60 + ToolbarAutoHide.hideDelay)
        #expect(!tracker.shown)
    }

    /// Over a popover or a menu hanging from the window there is no telling where the pointer is
    /// to the toolbar: nothing changes either way.
    @Test func elsewhereChangesNothing() {
        var hidden = ToolbarAutoHideTracker()
        #expect(hidden.sample(.elsewhere, at: 70) == nil)
        hidden.tick(at: 80)
        #expect(!hidden.shown)
        var out = ToolbarAutoHideTracker()
        out.bringOut()
        out.sample(.away, at: 70)
        #expect(out.sample(.elsewhere, at: 70.1) == nil)
        out.tick(at: 80)
        #expect(out.shown)
    }

    // MARK: Keyboard focus

    /// Tab (with Full Keyboard Access) onto one of the hidden bar's buttons: the bar comes out at once,
    /// without the pointer's wait, so the focused button is seen.
    @Test func focusOnTheBarBringsItOutAtOnce() {
        var tracker = ToolbarAutoHideTracker()
        #expect(tracker.focus(true, at: 100) == nil)
        #expect(tracker.shown)
        #expect(tracker.focused)
    }

    /// While a button has the focus the bar stays, wherever the pointer is.
    @Test func theBarStaysOutWhileItHasTheFocus() {
        var tracker = ToolbarAutoHideTracker()
        tracker.focus(true, at: 100)
        #expect(tracker.sample(.away, at: 100.1) == nil)
        tracker.tick(at: 130)
        #expect(tracker.shown)
        // A pointer that came by and left again doesn't take it away either.
        tracker.sample(.bar, at: 131)
        tracker.sample(.away, at: 132)
        tracker.tick(at: 132 + ToolbarAutoHide.hideDelay)
        #expect(tracker.shown)
    }

    /// Focus moves on to the page (Tab past the last button): the bar goes the usual way, a moment
    /// after, as it does once the pointer has left it.
    @Test func theBarGoesAMomentAfterTheFocusLeaves() {
        var tracker = ToolbarAutoHideTracker()
        tracker.focus(true, at: 100)
        tracker.sample(.away, at: 101)
        #expect(tracker.focus(false, at: 110) == 110 + ToolbarAutoHide.hideDelay)
        #expect(tracker.shown)
        #expect(!tracker.focused)
        tracker.tick(at: 110 + ToolbarAutoHide.hideDelay - 0.01)
        #expect(tracker.shown)
        tracker.tick(at: 110 + ToolbarAutoHide.hideDelay)
        #expect(!tracker.shown)
    }

    /// The focus leaves while the pointer rests on the bar: the pointer keeps it.
    @Test func thePointerKeepsTheBarTheFocusLeft() {
        var tracker = ToolbarAutoHideTracker()
        tracker.focus(true, at: 100)
        tracker.sample(.bar, at: 101)
        #expect(tracker.focus(false, at: 102) == nil)
        tracker.tick(at: 110)
        #expect(tracker.shown)
    }

    /// The pointer brought the bar out first, then Tab went into it: leaving with the pointer keeps
    /// it while it has the focus.
    @Test func focusKeepsABarThePointerBroughtOut() {
        var tracker = ToolbarAutoHideTracker()
        tracker.sample(.strip, at: 100)
        tracker.tick(at: 100 + ToolbarAutoHide.revealDwell)
        #expect(tracker.shown)
        tracker.focus(true, at: 101)
        #expect(tracker.sample(.away, at: 102) == nil)
        tracker.tick(at: 110)
        #expect(tracker.shown)
    }

    /// The same focus said twice changes nothing; focus that was never on the bar leaving it neither.
    @Test func focusSaidAgainChangesNothing() {
        var hidden = ToolbarAutoHideTracker()
        #expect(hidden.focus(false, at: 100) == nil)
        #expect(hidden == ToolbarAutoHideTracker())
        var out = ToolbarAutoHideTracker()
        out.focus(true, at: 100)
        out.sample(.away, at: 100.5)
        let before = out
        #expect(out.focus(true, at: 101) == nil)
        #expect(out == before)
    }

    /// The app went to the background (or the bar stopped floating): the bar goes and the focus is
    /// forgotten, so whoever still sees it on the bar says so again and it comes back out.
    @Test func resetForgetsTheFocus() {
        var tracker = ToolbarAutoHideTracker()
        tracker.focus(true, at: 100)
        tracker.reset()
        #expect(!tracker.shown)
        #expect(!tracker.focused)
        tracker.focus(true, at: 105)
        #expect(tracker.shown)
    }

    @Test func resetHidesAndForgetsTheWait() {
        var tracker = ToolbarAutoHideTracker()
        tracker.sample(.strip, at: 90)
        tracker.reset()
        tracker.tick(at: 91)
        #expect(!tracker.shown)
        tracker.bringOut()
        tracker.reset()
        #expect(!tracker.shown)
        #expect(tracker == ToolbarAutoHideTracker())
    }
}

/// Settings ▸ Links ▸ "Hide the Little Window toolbar until you need it" (GitHub #435): the Little
/// Window's page takes the toolbar's room, and the toolbar comes out the way the browser window's does.
struct LittleWindowToolbarAutoHideTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/435"))
    func offByDefaultAndKeptInSettingsJSON() throws {
        #expect(!AppSettings().autoHideLittleWindowToolbar)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"autoHideToolbar": true}"#.utf8))
        #expect(!old.autoHideLittleWindowToolbar)
        var settings = AppSettings()
        settings.autoHideLittleWindowToolbar = true
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(saved.autoHideLittleWindowToolbar)
        #expect(saved == settings)
        // Its own switch: the browser window's toolbar is left as it was.
        #expect(!saved.autoHideToolbar)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/435"))
    func floatsOnlyOverAPageInTheWindowsOwnView() {
        func floats(enabled: Bool = true, card: Bool = false, peek: Bool = false, pageFullscreen: Bool = false,
                    devToolsOpen: Bool = false, pageInOwnWindow: Bool = false) -> Bool {
            ToolbarAutoHide.littleWindowFloats(enabled: enabled, card: card, peek: peek, pageFullscreen: pageFullscreen,
                                               devToolsOpen: devToolsOpen, pageInOwnWindow: pageInOwnWindow)
        }
        #expect(floats())
        #expect(!floats(enabled: false))
        // ⌥⌘N's card is the command bar and nothing else.
        #expect(!floats(card: true))
        // A Peek has a bar of its own.
        #expect(!floats(peek: true))
        #expect(!floats(pageFullscreen: true))
        // DevTools and a Chrome-style page window sit above anything the Little Window draws.
        #expect(!floats(devToolsOpen: true))
        #expect(!floats(pageInOwnWindow: true))
    }

    /// A video in full screen in a Little Window or a Peek has the whole screen, as in the browser
    /// window: the bar neither floats over it nor sits above it, whatever the switch says. With the
    /// Chromium engine the page is a view under the bar, so the bar stayed on top of the video
    /// (X post, 18 Nov 2026, #540).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/540"))
    func aPageInFullScreenHasNoBar() {
        #expect(ToolbarAutoHide.littleWindowHasBar(barless: false, pageFullscreen: false))
        #expect(!ToolbarAutoHide.littleWindowHasBar(barless: false, pageFullscreen: true))
        // ⌥⌘N's card and an easel's Peek have none to begin with.
        #expect(!ToolbarAutoHide.littleWindowHasBar(barless: true, pageFullscreen: false))
        #expect(!ToolbarAutoHide.littleWindowHasBar(barless: true, pageFullscreen: true))
    }

    /// The Little Window's page sits 1 pt inside the window on every side once the bar floats (46 pt bar):
    /// that rim and the page's first 6 pt bring the bar out; the bar and 16 pt under it keep it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/435"))
    func theStripIsTheWindowsTopEdge() {
        let container = CGRect(x: 0, y: 0, width: 700, height: 600)
        let page = container.insetBy(dx: 1, dy: 1)
        func classify(_ y: CGFloat, shown: Bool) -> ToolbarAutoHide.Pointer {
            ToolbarAutoHide.classify(CGPoint(x: 350, y: y), card: page, container: container, barHeight: 46, shown: shown)
        }
        #expect(classify(600, shown: false) == .strip)
        #expect(classify(599 - ToolbarAutoHide.revealInside, shown: false) == .strip)
        #expect(classify(599 - ToolbarAutoHide.revealInside - 1, shown: false) == .away)
        #expect(classify(599 - 46 - ToolbarAutoHide.leaveSlack, shown: true) == .bar)
        #expect(classify(599 - 46 - ToolbarAutoHide.leaveSlack - 1, shown: true) == .away)
    }
}

/// Settings ▸ Links ▸ "Hide the Peek toolbar until you need it" (GitHub #493): #435's floating bar on a
/// Peek's card, under a switch of its own.
struct PeekToolbarAutoHideTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/493"))
    func offByDefaultAndKeptInSettingsJSON() throws {
        #expect(!AppSettings().autoHidePeekToolbar)
        // A settings.json from before the switch, with the Little Window's on: the Peek keeps its bar.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"autoHideLittleWindowToolbar": true}"#.utf8))
        #expect(!old.autoHidePeekToolbar)
        var settings = AppSettings()
        settings.autoHidePeekToolbar = true
        let saved = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(saved.autoHidePeekToolbar)
        #expect(saved == settings)
        // Its own switch: the Little Window's and the browser window's bars are left as they were.
        #expect(!saved.autoHideLittleWindowToolbar)
        #expect(!saved.autoHideToolbar)
        #expect(UsageStats.unreportedSettings.contains("autoHidePeekToolbar"))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/493"))
    func floatsOverAPeeksPageUnderItsOwnSwitch() {
        func floats(enabled: Bool = true, hasBar: Bool = true, pageFullscreen: Bool = false, devToolsOpen: Bool = false,
                    pageInOwnWindow: Bool = false) -> Bool {
            ToolbarAutoHide.peekFloats(enabled: enabled, hasBar: hasBar, pageFullscreen: pageFullscreen, devToolsOpen: devToolsOpen,
                                       pageInOwnWindow: pageInOwnWindow)
        }
        #expect(floats())
        #expect(!floats(enabled: false))
        // An easel's Peek has no bar.
        #expect(!floats(hasBar: false))
        #expect(!floats(pageFullscreen: true))
        #expect(!floats(devToolsOpen: true))
        #expect(!floats(pageInOwnWindow: true))
        // The Little Window's switch still leaves a Peek's bar alone (#435).
        #expect(!ToolbarAutoHide.littleWindowFloats(enabled: true, card: false, peek: true, pageFullscreen: false, devToolsOpen: false,
                                                    pageInOwnWindow: false))
    }

    /// A Peek's page fills its card edge to edge once the bar floats (32 pt bar): the card's first 6 pt and
    /// 4 pt above it bring the bar out; the bar and 16 pt under it keep it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/493"))
    func theStripIsTheCardsTopEdge() {
        let card = CGRect(x: 0, y: 0, width: 900, height: 700)
        func classify(_ y: CGFloat, shown: Bool) -> ToolbarAutoHide.Pointer {
            ToolbarAutoHide.classify(CGPoint(x: 450, y: y), card: card, container: card, barHeight: PeekLayout.barHeight, shown: shown)
        }
        #expect(classify(700 + ToolbarAutoHide.revealOutside, shown: false) == .strip)
        #expect(classify(700 - ToolbarAutoHide.revealInside, shown: false) == .strip)
        #expect(classify(700 - ToolbarAutoHide.revealInside - 1, shown: false) == .away)
        #expect(classify(700 - 32 - ToolbarAutoHide.leaveSlack, shown: true) == .bar)
        #expect(classify(700 - 32 - ToolbarAutoHide.leaveSlack - 1, shown: true) == .away)
    }
}

/// The toolbar's buttons from the keyboard: Tab reaches them with Full Keyboard Access, a click leaves
/// the keys where they were, and Space, Return or Enter press the focused one.
struct ToolbarKeyboardTests {
    @Test func tabStopsOnlyWithFullKeyboardAccessAndAtAButtonThatWorks() {
        #expect(ToolbarKeyboard.tabStops(fullKeyboardAccess: true, enabled: true))
        #expect(!ToolbarKeyboard.tabStops(fullKeyboardAccess: false, enabled: true))
        #expect(!ToolbarKeyboard.tabStops(fullKeyboardAccess: true, enabled: false))
    }

    /// Clicking Back with the pointer must leave the keys with the page: only the keyboard focuses a button.
    @Test func aClickNeverTakesTheFocus() {
        #expect(ToolbarKeyboard.takesFocus(enabled: true, byClick: false))
        #expect(!ToolbarKeyboard.takesFocus(enabled: true, byClick: true))
        #expect(!ToolbarKeyboard.takesFocus(enabled: false, byClick: false))
    }

    @Test func spaceReturnAndEnterPressTheFocusedButton() {
        func presses(_ c: String, command: Bool = false, option: Bool = false, control: Bool = false) -> Bool {
            ToolbarKeyboard.presses(characters: c, command: command, option: option, control: control)
        }
        #expect(presses(" "))
        #expect(presses("\r"))
        #expect(presses("\u{3}"))
        #expect(!presses("\t"))
        #expect(!presses("a"))
        #expect(!presses("\u{1b}"))
        // Shortcuts go on to the menus: ⌘Return, ⌥Space, ⌃Space.
        #expect(!presses("\r", command: true))
        #expect(!presses(" ", option: true))
        #expect(!presses(" ", control: true))
    }
}
