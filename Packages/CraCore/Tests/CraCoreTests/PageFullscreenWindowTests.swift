import CraCore
import Testing

/// A main window's full screen for a page's own (a video's full-screen button), as in Arc and Chrome.
struct PageFullscreenWindowTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/636")) func aWindowTheVideoTookFullScreenComesBack() {
        var w = PageFullscreenWindow()
        #expect(w.page(fullscreen: true, windowFullscreen: false, closing: false) == .enter)
        #expect(w.enteredForPage, "not remembered for the next launch (#426): the video took it there")
        // ⌘W on the video's tab: its page leaves full screen with it.
        #expect(w.page(fullscreen: false, windowFullscreen: true, closing: false) == .leave)
        #expect(!w.enteredForPage)
        // The window's own word that it left changes nothing more.
        #expect(w.page(fullscreen: false, windowFullscreen: false, closing: false) == .stay)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/636")) func aWindowTheUserMadeFullScreenStays() {
        var w = PageFullscreenWindow()
        #expect(w.page(fullscreen: true, windowFullscreen: true, closing: false) == .stay)
        #expect(!w.enteredForPage)
        #expect(w.page(fullscreen: false, windowFullscreen: true, closing: false) == .stay)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/636")) func aClosingWindowLeavesItsFullScreenItself() {
        // ⌘Q putting the window in the menu bar, or the window closing, closes its pages first: the window
        // takes itself out of full screen once, so a page leaving on the way doesn't toggle it as well.
        var w = PageFullscreenWindow()
        _ = w.page(fullscreen: true, windowFullscreen: false, closing: false)
        #expect(w.page(fullscreen: false, windowFullscreen: true, closing: true) == .stay)
        #expect(w.enteredForPage, "still the page's full screen, so it isn't remembered for the next launch")
        w.windowLeftFullScreen()
        #expect(!w.enteredForPage)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/636")) func theUserLeavingFirstForgetsThePage() {
        // The green button or ⌃⌘F while the video is full screen: the window is the user's again.
        var w = PageFullscreenWindow()
        _ = w.page(fullscreen: true, windowFullscreen: false, closing: false)
        w.windowLeftFullScreen()
        #expect(w.page(fullscreen: false, windowFullscreen: false, closing: false) == .stay)
        #expect(w.page(fullscreen: true, windowFullscreen: true, closing: false) == .stay)
        #expect(w.page(fullscreen: false, windowFullscreen: true, closing: false) == .stay)
    }
}
