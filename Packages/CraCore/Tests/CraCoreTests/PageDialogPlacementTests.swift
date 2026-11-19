import CoreGraphics
import CraCore
import Testing

struct PageDialogPlacementTests {
    /// A 1200 × 800 pt window and its page card, inside the sidebar and the window's 8 pt margins.
    static let window = CGRect(x: 100, y: 100, width: 1200, height: 800)
    static let page = CGRect(x: 368, y: 108, width: 924, height: 784)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/574")) func anAlertOverThePageIsOnThePage() {
        // Chrome's alert, centred on the page with its top at the page's top.
        let alert = CGRect(x: 700, y: 760, width: 260, height: 132)
        #expect(PageDialogPlacement.of(alert, page: Self.page, window: Self.window) == .page)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/574")) func whatTheStripMadeOfOneIsASliver() {
        // 0.1.49: print preview, sized to the never-seen 1 pt window, came out 1000 × 3 pt.
        let collapsed = CGRect(x: 520, y: 815, width: 260, height: 3)
        #expect(PageDialogPlacement.of(collapsed, page: Self.page, window: Self.window) == .sliver)
        #expect(PageDialogPlacement.of(CGRect(x: 600, y: 500, width: 30, height: 200), page: Self.page, window: Self.window) == .sliver)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/574")) func aBubbleOverTheSidebarIsOnTheWindow() {
        // A chooser hanging from where Chrome's toolbar would be, the strip's top left.
        let bubble = CGRect(x: 110, y: 560, width: 240, height: 300)
        #expect(PageDialogPlacement.of(bubble, page: Self.page, window: Self.window) == .window)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/574")) func elsewhereIsOff() {
        let away = CGRect(x: 1500, y: 100, width: 300, height: 200)
        #expect(PageDialogPlacement.of(away, page: Self.page, window: Self.window) == .off)
        // No page on screen (a tab still loading into the window): only the window counts.
        #expect(PageDialogPlacement.of(CGRect(x: 600, y: 500, width: 300, height: 200), page: nil, window: Self.window) == .window)
    }
}
