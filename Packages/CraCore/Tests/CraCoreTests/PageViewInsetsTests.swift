import CoreGraphics
import CraCore
import Testing

/// The page's input view keeps the place Chromium gave it below a views-side bar, wherever Cra
/// lays it out (GitHub #241).
struct PageViewInsetsTests {
    /// The debugger infobar, 40 pt, above a page in a 1000×700 Chrome window: Chromium sets the
    /// view to (0, 0, 1000, 660) in an unflipped superview and (0, 40, 1000, 660) in a flipped one.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/241"))
    func readsTheBarAboveThePageInEitherSuperview() {
        let client = CGSize(width: 1000, height: 700)
        let bar = PageViewInsets(top: 40, left: 0, bottom: 0, right: 0)
        #expect(PageViewInsets(chromiumFrame: CGRect(x: 0, y: 0, width: 1000, height: 660), superviewFlipped: false, clientSize: client) == bar)
        #expect(PageViewInsets(chromiumFrame: CGRect(x: 0, y: 40, width: 1000, height: 660), superviewFlipped: true, clientSize: client) == bar)
    }

    /// The card's web area is the size the page's compositor fills, not always the Chrome window's
    /// (a frozen card while panes animate): the view stays under the bar, not one bar-height low.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/241"))
    func placesTheViewBelowTheBarInTheCard() {
        let bar = PageViewInsets(top: 40, left: 0, bottom: 0, right: 0)
        let area = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(bar.frame(in: area, flipped: false) == CGRect(x: 0, y: 0, width: 800, height: 560))
        #expect(bar.frame(in: area, flipped: true) == CGRect(x: 0, y: 40, width: 800, height: 560))
        #expect(PageViewInsets.zero.frame(in: area, flipped: false) == area)
    }

    /// Reading back what was placed gives the same insets, on every edge.
    @Test func roundTrips() {
        let insets = PageViewInsets(top: 36, left: 12, bottom: 8, right: 300)
        let client = CGSize(width: 1200, height: 800)
        for flipped in [false, true] {
            let placed = insets.frame(in: CGRect(origin: .zero, size: client), flipped: flipped)
            #expect(PageViewInsets(chromiumFrame: placed, superviewFlipped: flipped, clientSize: client) == insets)
        }
    }

    /// A page filling its window has none, also when the window's height isn't whole points.
    @Test func aFullPageHasNone() {
        #expect(PageViewInsets(chromiumFrame: CGRect(x: 0, y: 0, width: 1000, height: 700), superviewFlipped: false,
                               clientSize: CGSize(width: 1000.5, height: 700.75)) == .zero)
    }

    /// Frames that aren't Chromium's layout of this window are ignored: bigger than the client
    /// area, outside it, or empty (CEF's 10 pt window before the first layout).
    @Test func ignoresFramesThatDoNotFit() {
        let client = CGSize(width: 1000, height: 700)
        #expect(PageViewInsets(chromiumFrame: CGRect(x: 0, y: 0, width: 1000, height: 800), superviewFlipped: false, clientSize: client) == nil)
        #expect(PageViewInsets(chromiumFrame: CGRect(x: -20, y: 0, width: 500, height: 700), superviewFlipped: false, clientSize: client) == nil)
        #expect(PageViewInsets(chromiumFrame: CGRect(x: 0, y: 0, width: 0, height: 0), superviewFlipped: false, clientSize: client) == nil)
        #expect(PageViewInsets(chromiumFrame: CGRect(x: 0, y: 0, width: 10, height: 10), superviewFlipped: false, clientSize: .zero) == nil)
    }
}
