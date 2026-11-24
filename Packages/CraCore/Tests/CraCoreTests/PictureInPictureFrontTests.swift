import Foundation
import CraCore
import Testing

/// A press on Picture in Picture's window with Cra in the background brings Cra forward, as Arc 1.173.1's does, so a
/// pinch after it reaches the window (#741: macOS gives a pinch only to the app in front, and Cra's non-activating
/// window left Cra behind on a click).
struct PictureInPictureFrontTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/741"))
    func aPressWithCraBehindBringsItForward() {
        var front = PictureInPictureFront()
        #expect(front.pressed(craActive: false) == .comeForward)
        #expect(front.inFrontForWindow)
    }

    /// Cra already in front: a press is only a press.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/741"))
    func aPressWithCraInFrontChangesNothing() {
        var front = PictureInPictureFront()
        #expect(front.pressed(craActive: true) == .none)
        #expect(!front.inFrontForWindow)
        #expect(front.browserKeyIsUse)
    }

    /// In front for the window only, a browser window AppKit gives the keyboard isn't the user in it: an automatic
    /// Picture in Picture's video stays out. Once the user uses Cra, or Cra goes behind, it counts again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/741"))
    func theBrowserWindowCountsOnceCraIsUsedOrLeft() {
        var front = PictureInPictureFront()
        _ = front.pressed(craActive: false)
        #expect(!front.browserKeyIsUse)
        front.craUsed()
        #expect(front.browserKeyIsUse)

        var left = PictureInPictureFront()
        _ = left.pressed(craActive: false)
        left.craLeft()
        #expect(left.browserKeyIsUse)
    }
}
