import CoreGraphics
import CraCore
import Testing

/// Arc's image editor for a capture (Capture ▸ Edit, Arc 1.174, measured live on 26 Nov 2026 at 2x, #851).
struct CaptureEditorLayoutTests {
    /// The capture shows a point per pixel, in the middle of the page: a 260 × 180 pt selection on a 2x screen (about
    /// 520 × 359 px) was a 520 × 359.5 pt card centred in a 1688 × 1044 pt Little Arc, with Easel's seven tools 12 pt in
    /// from its bottom left.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/851"))
    func theCaptureShowsAtItsPixelSizeInTheMiddle() {
        let card = CaptureEditorLayout.card(pixels: CGSize(width: 520, height: 359), in: CGSize(width: 1688, height: 1044))
        #expect(card == CGRect(x: 584, y: 342.5, width: 520, height: 359))
        let bar = CaptureEditorLayout.toolbar(in: card.size)
        #expect(bar == CGRect(x: 12, y: 359 - 12 - 44, width: 272, height: 44))
        #expect(CaptureEditorLayout.toolbarWidth == 272)
    }

    /// A capture bigger than the page shrinks to fit inside its margins, keeping its shape; one smaller than the
    /// toolbar still has room for it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/851"))
    func bigCapturesFitAndSmallOnesHoldTheToolbar() {
        let big = CaptureEditorLayout.card(pixels: CGSize(width: 4000, height: 2000), in: CGSize(width: 1000, height: 800))
        #expect(big.width == 1000 - 2 * CaptureEditorLayout.margin)
        #expect(abs(big.width / big.height - 2) < 0.001)
        #expect(big.midX == 500 && big.midY == 400)
        let small = CaptureEditorLayout.card(pixels: CGSize(width: 100, height: 40), in: CGSize(width: 1000, height: 800))
        #expect(small.width >= CaptureEditorLayout.toolbarWidth + 24 && small.height >= 44 + 24)
    }
}
