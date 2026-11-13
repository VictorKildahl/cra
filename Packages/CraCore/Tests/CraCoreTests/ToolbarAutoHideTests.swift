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
