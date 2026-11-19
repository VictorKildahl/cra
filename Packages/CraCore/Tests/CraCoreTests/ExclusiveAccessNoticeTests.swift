import CraCore
import Foundation
import Testing

/// Arc's notices for a page's full screen and pointer lock (docs/web-features.md; Arc 1.173.1, 19 Nov 2026).
struct ExclusiveAccessNoticeTests {
    @Test(.bug(id: "web-page-exclusive-access-notices")) func arcsWordsForEachNotice() {
        #expect(ExclusiveAccessNotice.fullscreen.toast(inLittleWindow: false) == .exitFullscreen)
        #expect(ExclusiveAccessNotice.Toast.exitFullscreen.text == "To exit full screen, press ⎋.")
        #expect(ExclusiveAccessNotice.pointerLock.toast(inLittleWindow: false) == .pointerHidden)
        #expect(ExclusiveAccessNotice.Toast.pointerHidden.text == "Your cursor is hidden. Press 'esc' to show cursor.")
        // Under a keyboard lock Arc says the same as for full screen, not Chrome's "press and hold Esc".
        #expect(ExclusiveAccessNotice.keyboardLock.toast(inLittleWindow: false) == .exitFullscreen)
        #expect(ExclusiveAccessNotice.fullscreenPointerLock.toast(inLittleWindow: false) == .pointerHidden)
    }

    @Test(.bug(id: "web-page-exclusive-access-notices")) func littleWindowsSayNothingAboutFullScreen() {
        // Little Arc: no toast for a page's full screen, the pointer one still.
        #expect(ExclusiveAccessNotice.fullscreen.toast(inLittleWindow: true) == nil)
        #expect(ExclusiveAccessNotice.keyboardLock.toast(inLittleWindow: true) == nil)
        #expect(ExclusiveAccessNotice.pointerLock.toast(inLittleWindow: true) == .pointerHidden)
    }

    @Test(.bug(id: "web-page-exclusive-access-notices")) func notTheBrowsersOwnFullScreenOrNone() {
        for n in [ExclusiveAccessNotice.none, .browserFullscreen, .extensionFullscreen] {
            #expect(n.toast(inLittleWindow: false) == nil)
        }
        // The engine's values are Chrome's ExclusiveAccessBubbleType.
        #expect(ExclusiveAccessNotice(rawValue: 3) == .pointerLock)
        #expect(ExclusiveAccessNotice(rawValue: 4) == .keyboardLock)
    }

    @Test(.bug(id: "web-page-exclusive-access-notices")) func showsWhenItChangesOrChromeAsksAgain() {
        var n = ExclusiveAccessNotices()
        #expect(n.update(.fullscreen, force: false, inLittleWindow: false) == .exitFullscreen)
        // Chrome repeats the current notice whenever anything changes: once is enough.
        #expect(n.update(.fullscreen, force: false, inLittleWindow: false) == nil)
        // The page asked for full screen again.
        #expect(n.update(.fullscreen, force: true, inLittleWindow: false) == .exitFullscreen)
        // Then it takes the pointer too.
        #expect(n.update(.fullscreenPointerLock, force: false, inLittleWindow: false) == .pointerHidden)
        // Out of full screen, and back in: shown again.
        #expect(n.update(.none, force: false, inLittleWindow: false) == nil)
        #expect(n.current == .none)
        #expect(n.update(.fullscreen, force: false, inLittleWindow: false) == .exitFullscreen)
    }

    @Test(.bug(id: "web-page-fullscreen-keyboard-lock")) func escapeUnderAKeyboardLockLeavesOnTheSecondPress() {
        var esc = KeyboardLockEscape()
        // The first press is the page's, and Arc offers the next one.
        #expect(esc.press(at: 10, offerTime: 4.85) == .offerAgain)
        // A press while that toast shows leaves full screen.
        #expect(esc.press(at: 12, offerTime: 4.85) == .exitFullscreen)
        // After it, it starts over.
        #expect(esc.press(at: 13, offerTime: 4.85) == .offerAgain)
        // Too late: the toast had gone, so it is the page's again and offers again.
        #expect(esc.press(at: 30, offerTime: 4.85) == .offerAgain)
        esc.reset()
        #expect(esc.press(at: 31, offerTime: 4.85) == .offerAgain)
        #expect(KeyboardLockEscape.againKeys == "⎋")
        #expect(KeyboardLockEscape.againText == "again to exit fullscreen")
    }
}
