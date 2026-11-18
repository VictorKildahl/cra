import CoreGraphics
import CraCore
import Testing

/// A two-finger pinch on the Picture in Picture window resizes it, as Arc's does (#534).
struct PictureInPicturePinchTests {
    /// A 1728 × 1117 display with a 33 pt menu bar.
    private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    private var limits: (min: CGSize, max: CGSize) {
        PictureInPictureLayout.sizeLimits(aspect: 16.0 / 9, screen: CGRect(x: 0, y: 0, width: 1728, height: 1117), visible: visible)
    }

    /// The window after pinches of `steps`, from `frame`.
    private func pinch(_ frame: CGRect, _ steps: [CGFloat]) -> (PictureInPicturePinch, CGRect) {
        var p = PictureInPicturePinch(frame: frame)
        var f = frame
        for m in steps { f = p.magnify(by: m, minSize: limits.min, maxSize: limits.max, visible: visible) }
        return (p, f)
    }

    /// Fingers apart make the window larger, together smaller, around its centre and in the
    /// video's shape.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/534")) func apartGrowsTogetherShrinksAroundTheCentre() {
        let middle = CGRect(x: 600, y: 400, width: 448, height: 252)
        let (_, larger) = pinch(middle, [0.25])
        #expect(larger == CGRect(x: 544, y: 369, width: 560, height: 315))
        let (_, smaller) = pinch(middle, [-0.2])
        #expect(smaller.width == 358 && smaller.height == 201)
        #expect(abs(smaller.midX - middle.midX) <= 1 && abs(smaller.midY - middle.midY) <= 1)
    }

    /// Each event's magnification is relative to the last, and the window follows every one
    /// (smooth, not one jump at the end).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/534")) func eventsCompound() {
        let middle = CGRect(x: 600, y: 400, width: 448, height: 252)
        let (p, f) = pinch(middle, [0.1, 0.1, 0.1])
        #expect(abs(p.scale - 1.331) < 0.0001)
        #expect(f.width == 596 && f.height == 335)
    }

    /// No smaller than Arc's 224 × 126, and the fingers turning back take it back at once: the
    /// scale stops where the window did.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/534")) func stopsAtTheSmallestAndComesStraightBack() {
        let middle = CGRect(x: 600, y: 400, width: 448, height: 252)
        let (_, smallest) = pinch(middle, [-0.5, -0.5, -0.5])
        #expect(smallest.size == CGSize(width: 224, height: 126))
        let (p, back) = pinch(middle, [-0.5, -0.5, -0.5, 0.1])
        #expect(p.scale == 0.55)
        #expect(back.width == 246)
    }

    /// A window resting in the top-right corner, 10 pt in, keeps that corner as it grows.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/534")) func aWindowInACornerGrowsOutOfIt() {
        let corner = CGRect(x: 1728 - 10 - 448, y: 1084 - 10 - 252, width: 448, height: 252)
        let (_, f) = pinch(corner, [0.5])
        #expect(f.size == CGSize(width: 672, height: 378))
        #expect(f.maxX == 1718 && f.maxY == 1074)
        let (_, shrunk) = pinch(corner, [-0.25])
        #expect(shrunk.width == 336)
        #expect(abs(shrunk.midX - corner.midX) <= 1)   // shrinking leaves the corner, around the centre
    }

    /// It grows no larger than its display has room for (less the gaps it keeps), and then
    /// comes back as soon as the fingers turn.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/534")) func stopsAtTheDisplaysEdges() {
        let corner = CGRect(x: 1728 - 10 - 448, y: 1084 - 10 - 252, width: 448, height: 252)
        let (p, f) = pinch(corner, [2, 2, 2])
        #expect(f.width == 1708 && f.height == 961)
        #expect(visible.insetBy(dx: 10, dy: 10).contains(f))
        let (_, back) = pinch(corner, [2, 2, 2, -0.5])
        #expect(back.width == 854)
        #expect(p.scale * 448 == 1708)
    }

    /// A pinch that rests (magnification 0) changes nothing.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/534")) func restingFingersChangeNothing() {
        let middle = CGRect(x: 600, y: 400, width: 448, height: 252)
        #expect(pinch(middle, [0, 0]).1 == middle)
        let corner = CGRect(x: 1270, y: 822, width: 448, height: 252)
        #expect(pinch(corner, [0]).1 == corner)
    }
}
