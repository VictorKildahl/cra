import CoreGraphics
import CraCore
import Testing

/// GitHub #346: a screenshot app's "window under the pointer" over a page is the main window,
/// whose card draws the page, not a clear window laid over it.
struct ScreenshotPickTests {
    /// A 1200×800 window at (100, 50) from the top left; its page area 862×780 at (428, 60).
    static let main = ScreenshotPick.Window(number: 1, frame: CGRect(x: 100, y: 50, width: 1200, height: 800))
    static let page = CGRect(x: 428, y: 60, width: 862, height: 780)
    static let pageCentre = CGPoint(x: 859, y: 450)

    /// The status bubble's strip in screen coordinates from the top left.
    static var strip: CGRect {
        let s = StatusBubbleStrip.frame(inPage: CGRect(origin: .zero, size: page.size))
        return CGRect(x: page.minX + s.minX, y: page.maxY - s.maxY, width: s.width, height: s.height)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/346")) func aPickOverThePageTakesTheMainWindow() {
        // Front to back, as Cra orders its children: status panel, then the page's Chrome window.
        let windows = [
            ScreenshotPick.Window(number: 3, frame: Self.strip),
            ScreenshotPick.Window(number: 2, frame: Self.page, shared: false),
            Self.main,
        ]
        #expect(ScreenshotPick.window(at: Self.pageCentre, in: windows) == Self.main)
        // The bubble's own strip is still a window of its own, as small as the bubble.
        let inStrip = CGPoint(x: Self.page.minX + 10, y: Self.page.maxY - 10)
        #expect(ScreenshotPick.window(at: inStrip, in: windows)?.number == 3)
    }

    @Test func aPageSizedClearWindowWasTheOneTaken() {
        // What 0.1.38 had: both clear windows covered the whole page and could be captured.
        let windows = [
            ScreenshotPick.Window(number: 3, frame: Self.page),
            ScreenshotPick.Window(number: 2, frame: Self.page),
            Self.main,
        ]
        #expect(ScreenshotPick.window(at: Self.pageCentre, in: windows)?.number == 3)
    }

    @Test func pickersSkipOtherLevelsHiddenWindowsAndPointsOutside() {
        let windows = [
            ScreenshotPick.Window(number: 5, frame: Self.page, layer: 101),
            ScreenshotPick.Window(number: 4, frame: Self.page, alpha: 0),
            Self.main,
        ]
        #expect(ScreenshotPick.window(at: Self.pageCentre, in: windows) == Self.main)
        #expect(ScreenshotPick.window(at: CGPoint(x: 10, y: 10), in: windows) == nil)
    }

    @Test func theStripIsTheBubbleAtThePagesBottomLeft() {
        #expect(StatusBubbleStrip.frame(inPage: CGRect(x: 0, y: 0, width: 862, height: 780)) == CGRect(x: 0, y: 0, width: 540, height: 34))
        #expect(StatusBubbleStrip.frame(inPage: CGRect(x: 20, y: 30, width: 300, height: 20)) == CGRect(x: 20, y: 30, width: 300, height: 20))
        #expect(StatusBubbleStrip.frame(inPage: .zero) == .zero)
    }
}
