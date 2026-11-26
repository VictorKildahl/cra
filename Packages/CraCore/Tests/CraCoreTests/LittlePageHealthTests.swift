import CoreGraphics
import Testing
@testable import CraCore

@Suite struct LittlePageHealthTests {
    private func look(shown: Bool = true, meantHidden: Bool = false, viewHidden: Bool = false, visibility: String? = "visible",
                      frameRate: Int? = 120, viewport: CGSize? = CGSize(width: 1400, height: 860),
                      view: CGSize = CGSize(width: 1400, height: 860), loading: Bool = false) -> LittlePageHealth.Look {
        .init(windowShown: shown, pageMeantHidden: meantHidden, viewHidden: viewHidden, visibility: visibility, frameRate: frameRate,
              viewport: viewport, viewSize: view, loading: loading)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/848"))
    func aPageInSightThatDoesntDrawIsStuck() {
        #expect(LittlePageHealth.judge(look()) == .drawing)
        #expect(LittlePageHealth.judge(look(visibility: "hidden", frameRate: 0)) == .stuck(["it says hidden", "no frames"]))
        #expect(LittlePageHealth.judge(look(frameRate: 0)) == .stuck(["no frames"]))
        #expect(LittlePageHealth.judge(look(viewHidden: true, visibility: "hidden", frameRate: 0))
            == .stuck(["its view is hidden", "it says hidden", "no frames"]))
        // Laid out for the window's 48 x 30 start of its grow-in, in its full-size view: white past the corner.
        #expect(LittlePageHealth.judge(look(viewport: CGSize(width: 48, height: 30)))
            == .stuck(["laid out at 48x30 in a 1400x860 view"]))
        // A loaded page that doesn't answer: Chromium hid it a while ago and it runs no frames (seen after 2 minutes white).
        #expect(LittlePageHealth.judge(look(visibility: nil, frameRate: nil)) == .stuck(["it didn't answer"]))
        #expect(LittlePageHealth.judge(look(viewHidden: true, visibility: nil, frameRate: nil)) == .stuck(["its view is hidden", "it didn't answer"]))
        // Scrollbars and rounding are no reason.
        #expect(LittlePageHealth.judge(look(viewport: CGSize(width: 1385, height: 860))) == .drawing)
    }

    @Test func outOfSightOrMeantHiddenIsNotJudged() {
        #expect(LittlePageHealth.judge(look(shown: false, visibility: "hidden", frameRate: 0)) == .notJudged)
        #expect(LittlePageHealth.judge(look(meantHidden: true, viewHidden: true, visibility: "hidden", frameRate: 0)) == .notJudged)
        // No answer while loading says nothing; a hidden view still does.
        #expect(LittlePageHealth.judge(look(visibility: nil, frameRate: nil, loading: true)) == .notJudged)
        #expect(LittlePageHealth.judge(look(viewHidden: true, visibility: nil, frameRate: nil, loading: true)) == .stuck(["its view is hidden"]))
    }

    @Test func viewportReadsPageProbesText() {
        #expect(LittlePageHealth.viewport("1400x860@2", backingScale: 2) == CGSize(width: 1400, height: 860))
        // Zoomed to 125 %: fewer CSS pixels, the same points, so a zoomed page isn't "laid out at another size".
        #expect(LittlePageHealth.viewport("1120x688@2.5", backingScale: 2) == CGSize(width: 1400, height: 860))
        #expect(LittlePageHealth.viewport("1400x860@1", backingScale: 1) == CGSize(width: 1400, height: 860))
        #expect(LittlePageHealth.viewport("?", backingScale: 2) == nil)
    }

    @Test func triesAreLimitedPerShowing() {
        var tries = LittlePageHealth.Tries()
        let first = tries.take(), second = tries.take(), third = tries.take()
        #expect(first && second && !third)
        tries.reset()
        let again = tries.take()
        #expect(again)
    }
}
