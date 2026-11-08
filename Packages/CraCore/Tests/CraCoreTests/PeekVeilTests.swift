import CoreGraphics
import CraCore
import Foundation
import Testing

/// The page behind a Peek: who it is veiled for, and what it looks like (PR #221).
struct PeekVeilTests {
    let a = UUID(), b = UUID()

    @Test func showsOnceAndComesBackAnimated() {
        var veil = PeekVeil()
        do { let changed = veil.show(for: a); #expect(changed) }
        do { let changed = veil.show(for: a); #expect(!changed) }
        #expect(veil.isOn)
        do { let changed = veil.hide(for: a); #expect(changed) }
        #expect(!veil.isOn)
    }

    /// A Peek waiting on its tab lets the page go and veils it again when its tab is back (#242).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/242"))
    func aPeekBackWithItsTabVeilsThePageAgain() {
        var veil = PeekVeil()
        _ = veil.show(for: a)
        do { let changed = veil.hide(for: a); #expect(changed) }
        do { let changed = veil.show(for: a); #expect(changed) }
        #expect(veil.owner == a)
    }

    /// Expand, Add To Split or a close in the 30 ms before the open's veil starts: the Peek is gone
    /// first, and the late show used to leave the page faded and shrunk with no Peek over it.
    @Test func aPeekThatHasEndedNeverVeilsThePage() {
        var veil = PeekVeil()
        do { let changed = veil.end(for: a); #expect(!changed) }
        do { let changed = veil.show(for: a); #expect(!changed) }
        #expect(!veil.isOn)
    }

    /// Closing fades the page back over 0.2 s while the card lands in 0.16 s; the Peek ending then
    /// must leave that fade running instead of snapping it, and the card's close keeps Arc's length.
    @Test func endingAfterTheCloseLeavesItsFadeAlone() {
        var veil = PeekVeil()
        _ = veil.show(for: a)
        do { let changed = veil.hide(for: a); #expect(changed) }
        do { let changed = veil.end(for: a); #expect(!changed) }
    }

    /// Expand and Add To Split end a Peek without its close: the page snaps back.
    @Test func endingWhileVeiledSnapsBack() {
        var veil = PeekVeil()
        _ = veil.show(for: a)
        do { let changed = veil.end(for: a); #expect(changed) }
        #expect(!veil.isOn)
    }

    /// A Peek still closing ends after the next one veiled the page: the new Peek keeps it.
    @Test func anotherPeekEndingLeavesTheVeil() {
        var veil = PeekVeil()
        _ = veil.show(for: a)
        _ = veil.hide(for: a)
        do { let changed = veil.show(for: b); #expect(changed) }
        do { let changed = veil.end(for: a); #expect(!changed) }
        do { let changed = veil.hide(for: a); #expect(!changed) }
        #expect(veil.isOn)
        do { let changed = veil.end(for: b); #expect(changed) }
    }

    @Test func pageFadesAndShrinksUnlessEdgeToEdge() {
        #expect(PeekLayout.backdrop(veiled: true, edgeToEdge: false) == .init(alpha: PeekLayout.pageAlpha, scale: PeekLayout.pageScale))
        #expect(PeekLayout.backdrop(veiled: true, edgeToEdge: true) == .init(alpha: PeekLayout.pageAlpha, scale: 1))
        #expect(PeekLayout.backdrop(veiled: false, edgeToEdge: false) == .init(alpha: 1, scale: 1))
        #expect(PeekLayout.pageScale < 1 && PeekLayout.pageScale > 0.95)
    }

    /// The scale holds `center` still and pulls the corners in around it, whatever the anchor.
    @Test(arguments: [CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0, y: 0)])
    func shrinksAroundTheCentre(anchorPoint: CGPoint) {
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 600)
        let anchor = CGPoint(x: bounds.width * anchorPoint.x, y: bounds.height * anchorPoint.y)
        let center = CGPoint(x: 400, y: 250)
        let t = PeekLayout.backdropTransform(scale: 0.9, around: center, anchor: anchor)
        // A sublayer transform applies about the anchor: p' = anchor + T(p - anchor).
        func apply(_ p: CGPoint) -> CGPoint {
            let q = CGPoint(x: p.x - anchor.x, y: p.y - anchor.y).applying(t)
            return CGPoint(x: q.x + anchor.x, y: q.y + anchor.y)
        }
        let c = apply(center), o = apply(.zero), e = apply(CGPoint(x: 1000, y: 600))
        #expect(abs(c.x - 400) < 1e-9 && abs(c.y - 250) < 1e-9)
        #expect(abs(o.x - 40) < 1e-9 && abs(o.y - 25) < 1e-9)
        #expect(abs(e.x - 940) < 1e-9 && abs(e.y - 565) < 1e-9)
        #expect(PeekLayout.backdropTransform(scale: 1, around: center, anchor: anchor).isIdentity)
    }

    /// Arc's measured close stays its own length; the page's slower fade back runs on its own.
    @Test func closeKeepsArcsLength() {
        #expect(PeekLayout.closeDuration() == PeekLayout.closeScaleDuration)
        #expect(PeekLayout.closeDuration(scale: PeekLayout.closeToAreaDuration) == PeekLayout.closeFadeDelay + PeekLayout.closeFadeDuration)
    }
}
