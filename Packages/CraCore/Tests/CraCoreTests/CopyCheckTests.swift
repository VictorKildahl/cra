import CoreGraphics
import CraCore
import Foundation
import Testing

/// Arc's link → checkmark → link on the Copy URL glyph (#361), as measured.
struct CopyCheckTests {
    /// The ink (stroke included) is a 0.83 square on the glyph's centre: 10 pt for the toolbar's
    /// 12 pt link, 11.6 pt for the sidebar's 14 pt one.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/361"), arguments: [12.0, 14.0] as [CGFloat])
    func inkFillsTheMeasuredSquare(glyph: CGFloat) {
        let p = CopyCheck.points(glyphSize: glyph), half = CopyCheck.lineWidth(glyphSize: glyph) / 2
        let minX = p.map(\.x).min()! - half, maxX = p.map(\.x).max()! + half
        let minY = p.map(\.y).min()! - half, maxY = p.map(\.y).max()! + half
        let side = CopyCheck.side(glyphSize: glyph)
        #expect(abs((maxX - minX) - side) < 0.01, "width \(maxX - minX)")
        #expect(abs((maxY - minY) - side) < 0.01, "height \(maxY - minY)")
        #expect(abs(minX + maxX) < 0.01 && abs(minY + maxY) < 0.01, "centred on the glyph")
        #expect(maxX - minX < glyph, "inside the link's box")
    }

    /// A checkmark: the short leg runs down to the vertex at the bottom, the long leg up to the
    /// top-right corner, and it is the longer one.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/361"))
    func shapeIsACheckmark() {
        let p = CopyCheck.points(glyphSize: 12)
        #expect(p[1].y > p[0].y && p[1].y > p[2].y, "vertex lowest (y down)")
        #expect(p[0].x < p[1].x && p[1].x < p[2].x, "left to right")
        let short = hypot(p[1].x - p[0].x, p[1].y - p[0].y), long = hypot(p[2].x - p[1].x, p[2].y - p[1].y)
        #expect(long > 1.8 * short)
    }

    /// The phases follow each other as in Arc: the link is gone before the check draws, the check is
    /// whole well before it un-draws, and the link returns as the un-draw ends.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/361"))
    func phasesInOrder() {
        #expect(CopyCheck.linkOutDuration < CopyCheck.checkInStart)
        let whole = CopyCheck.checkInStart + max(CopyCheck.checkDrawDuration, CopyCheck.checkFadeInDuration)
        #expect(whole < CopyCheck.holdUntil - 0.5, "about 0.7 s fully shown")
        #expect(abs(CopyCheck.holdUntil + CopyCheck.checkUndrawDuration - CopyCheck.linkInStart) < 0.02)
    }

    /// The link's spring, stepped like Core Animation's: from 0.5 it peaks at ~1.15 about 0.125 s
    /// in (both captures: 1.14 sidebar, 1.17 toolbar) and is within 2 % by 0.45 s.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/361"))
    func springMatchesTheCapture() {
        var x = Double(CopyCheck.linkInScale), v = 0.0, t = 0.0, peak = 0.0, peakAt = 0.0, late = 0.0
        let k = Double(CopyCheck.springStiffness), c = Double(CopyCheck.springDamping), dt = 1.0 / 2000
        while t < 0.8 {
            v += (-k * (x - 1) - c * v) * dt
            x += v * dt
            t += dt
            if x > peak { peak = x; peakAt = t }
            if t > 0.45 { late = max(late, abs(x - 1)) }
        }
        #expect(peak > 1.12 && peak < 1.19, "peak \(peak)")
        #expect(abs(peakAt - 0.125) < 0.015, "peak at \(peakAt)")
        #expect(late < 0.02, "settled \(late)")
    }
}
