import CoreGraphics
import CraCore
import Testing

/// A two-finger swipe throws the Picture in Picture window into a corner (Arc, reported on X 4 Nov).
struct PictureInPictureThrowTests {
    /// A 1728 × 1084 visible frame (Arc's measurement display) and Arc's 782 × 440 window in the top right.
    private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)
    private let window = CGRect(x: 936, y: 634, width: 782, height: 440)

    /// 120 Hz moves of `dx, dy` each for `count` frames, the fingers lifting on the last.
    private func swipe(_ dx: CGFloat, _ dy: CGFloat, frames count: Int) -> (PictureInPictureThrow, Double) {
        var s = PictureInPictureThrow(frame: window, at: 0)
        var t = 0.0
        for _ in 0..<count {
            t += 1.0 / 120
            _ = s.move(dx: dx, dy: dy, at: t)
        }
        return (s, t)
    }

    @Test func theWindowFollowsTheFingers() {
        let (s, _) = swipe(-4, 2, frames: 10)
        #expect(s.frame == window.offsetBy(dx: -40, dy: 20))
    }

    @Test func speedComesFromTheLastMoves() {
        let (s, t) = swipe(-10, 0, frames: 30)
        let v = s.velocity(at: t)
        #expect(abs(v.dx + 1200) < 1)
        #expect(v.dy == 0)
        // Fingers that rest before lifting throw nothing.
        #expect(s.velocity(at: t + 0.2) == .zero)
    }

    /// A short flick from the top right toward the left lands top left; resting in place keeps
    /// the nearest corner.
    @Test func aFlickPicksTheCornerItCarriesTo() {
        let (s, t) = swipe(-12, 0, frames: 6)
        let v = s.velocity(at: t)
        #expect(s.frame.midX > visible.midX)
        #expect(PictureInPictureThrow.corner(for: s.frame, velocity: v, in: visible) == .topLeft)
        #expect(PictureInPictureThrow.corner(for: s.frame, velocity: .zero, in: visible) == .topRight)
        let down = PictureInPictureThrow.corner(for: window, velocity: CGVector(dx: 0, dy: -2000), in: visible)
        #expect(down == .bottomRight)
        let diagonal = PictureInPictureThrow.corner(for: window, velocity: CGVector(dx: -3000, dy: -2000), in: visible)
        #expect(diagonal == .bottomLeft)
    }

    @Test func cornersKeepArcsMargin() {
        let size = window.size
        let f = { (c: PictureInPictureThrow.Corner) in PictureInPictureThrow.frame(in: c, size: size, visible: visible, margin: 10) }
        #expect(f(.topRight) == CGRect(x: 936, y: 634, width: 782, height: 440))
        #expect(f(.topLeft).origin == CGPoint(x: 10, y: 634))
        #expect(f(.bottomLeft).origin == CGPoint(x: 10, y: 10))
        #expect(f(.bottomRight).origin == CGPoint(x: 936, y: 10))
        // A second screen to the left of the main one.
        let left = CGRect(x: -1440, y: 100, width: 1440, height: 875)
        #expect(PictureInPictureThrow.frame(in: .bottomLeft, size: size, visible: left, margin: 10).origin == CGPoint(x: -1430, y: 110))
    }

    /// The flight starts at the fingers' speed and comes to rest exactly in the corner within a second.
    @Test func theFlightLandsInTheCorner() {
        var f = PictureInPictureFlight(from: CGPoint(x: 700, y: 634), velocity: CGVector(dx: -1500, dy: 0), to: CGPoint(x: 10, y: 634))
        var p = f.position
        var t = 0.0
        var furthestLeft = p.x
        while !f.isSettled && t < 2 {
            p = f.step(1.0 / 120)
            furthestLeft = min(furthestLeft, p.x)
            t += 1.0 / 120
        }
        #expect(f.isSettled)
        #expect(p == CGPoint(x: 10, y: 634))
        #expect(t < 1)
        // At most a few points past the corner, never off the screen.
        #expect(furthestLeft > 0)
    }

    /// A long stall (the Mac busy for a quarter of a second) doesn't fling the window away.
    @Test func aDroppedFrameStaysStable() {
        var f = PictureInPictureFlight(from: CGPoint(x: 900, y: 600), velocity: .zero, to: CGPoint(x: 10, y: 10))
        let p = f.step(0.25)
        #expect(p.x >= 10 && p.x <= 900)
        #expect(p.y >= 10 && p.y <= 600)
    }
}
