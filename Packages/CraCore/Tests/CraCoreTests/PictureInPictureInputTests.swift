import Testing
@testable import CraCore

/// Chromium's video PiP window under Arc's controls takes no input and never becomes key, so
/// Chrome's own controls can't show under Cra's (GitHub #460).
@Suite struct PictureInPictureInputTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/460"))
    func chromiumWindowTakesNoInput() {
        // Each of these makes VideoOverlayWindowViews show its controls, or starts a drag or a
        // resize of its own; Cra's overlay handles them all.
        for kind in [PictureInPictureInput.Kind.mouseMove, .mouseButton, .trackingArea, .cursorUpdate, .scroll, .key, .gesture] {
            #expect(!PictureInPictureInput.chromiumTakes(kind), "\(kind)")
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/460"))
    func systemEventsStillReachIt() {
        // AppKit's own (screen and Space changes, window moves) keep Chromium's window working.
        #expect(PictureInPictureInput.chromiumTakes(.system))
        #expect(PictureInPictureInput.Kind.allCases.filter(PictureInPictureInput.chromiumTakes) == [.system])
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/460"))
    func chromiumWindowNeverBecomesKey() {
        #expect(!PictureInPictureInput.chromiumCanBecomeKey)
    }
}
