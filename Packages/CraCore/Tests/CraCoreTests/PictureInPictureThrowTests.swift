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

    /// Fingers gliding at 600 pt/s whose moves come unevenly (4 ms, then 12 ms apart, the way a
    /// trackpad's land against a 120 Hz screen): the window on screen still steps the same
    /// distance every frame, where showing the latest move steps 0, 5 or 10 points. Moves and
    /// frames are replayed in time order, so a frame only sees the moves that came before it.
    @Test func eachFrameStepsEvenly() {
        var s = PictureInPictureThrow(frame: window, at: 0)
        var shown: [CGFloat] = [], latest: [CGFloat] = []
        var t = 0.0, i = 0
        var frame = 1.0 / 120
        while t < 0.5 {
            let next = t + (i % 2 == 0 ? 0.004 : 0.012)
            while frame < next {
                if frame > 0.1 {
                    shown.append(s.origin(at: frame).x)
                    latest.append(s.frame.minX)
                }
                frame += 1.0 / 120
            }
            _ = s.move(dx: CGFloat((next - t) * 600), dy: 0, at: next)
            t = next
            i += 1
        }
        let steps = zip(shown.dropFirst(), shown).map { $0 - $1 }
        let latestSteps = zip(latest.dropFirst(), latest).map { $0 - $1 }
        #expect(steps.allSatisfy { abs($0 - 5) < 0.01 })
        #expect(latestSteps.contains { abs($0 - 5) > 2 })
        // About a move behind the fingers, no more.
        #expect(s.lag < 0.015)
    }

    /// Fingers that stop leave the window where they stopped, not past it.
    @Test func theWindowStopsWithTheFingers() {
        var s = PictureInPictureThrow(frame: window, at: 0)
        for i in 1...10 { _ = s.move(dx: 8, dy: 0, at: Double(i) / 120) }
        #expect(s.origin(at: 1).x == window.minX + 80)
        // Resting, then moving again: the window doesn't creep there over the rest.
        _ = s.move(dx: 8, dy: 0, at: 1)
        #expect(s.origin(at: 0.9).x == window.minX + 80)
        #expect(s.origin(at: 1.05).x == window.minX + 88)
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

    /// The pointer hides and rides along at its spot in the window while the fingers move it,
    /// because scroll events go to the window under the pointer. It can't go past the screen's
    /// edge, so a window swiped on past it slid out from under the pointer: the lift went to
    /// another window, and the window stayed off the screen with the pointer hidden for good
    /// (#516). The fingers now take the window only as far as the pointer can follow it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/516"))
    func theWindowStopsWhereThePointerMeetsTheScreenEdge() {
        // A 1728 × 1117 display under a 33 pt menu bar.
        let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        // The pointer 100 pt in from the window's left edge and 50 pt up from its bottom.
        var s = PictureInPictureThrow(frame: window, at: 0, pointer: CGVector(dx: 100, dy: 50), displays: [visible])
        var t = 0.0
        for _ in 0..<40 {
            t += 1.0 / 120
            _ = s.move(dx: 30, dy: 0, at: t)
        }
        // The pointer's spot stops on the screen's last column, 1727; most of the window is
        // past the edge, but it is still under the pointer.
        #expect(s.frame.minX == 1627)
        #expect(s.frame.minY == window.minY)
        #expect(visible.contains(CGPoint(x: s.frame.minX + 100, y: s.frame.minY + 50)))
        // Its speed is the window's, not the fingers' pushing on at the edge.
        #expect(s.velocity(at: t).dx == 0)
        // The fingers moved: lifting them throws the window into a corner.
        #expect(s.hasMoved)

        // Up toward the menu bar, which lies above the window and would take the scroll events:
        // the pointer stops on the row below it, 1083. Back the other way, the window moves at once.
        for _ in 0..<40 {
            t += 1.0 / 120
            _ = s.move(dx: 0, dy: 30, at: t)
        }
        #expect(s.frame.minY == 1033)
        t += 1.0 / 120
        _ = s.move(dx: -10, dy: -10, at: t)
        #expect(s.frame.origin == CGPoint(x: 1617, y: 1023))
    }

    /// The Dock lies above the window as well: the pointer stops at its edge.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/516"))
    func theWindowStopsAtTheDock() {
        // A 70 pt Dock along the bottom.
        let visible = CGRect(x: 0, y: 70, width: 1728, height: 1014)
        var s = PictureInPictureThrow(frame: CGRect(x: 936, y: 200, width: 782, height: 440), at: 0,
                                      pointer: CGVector(dx: 300, dy: 20), displays: [visible])
        for i in 1...20 { _ = s.move(dx: -5, dy: -30, at: Double(i) / 120) }
        #expect(s.frame.origin == CGPoint(x: 836, y: 50))
    }

    /// With a second display beside the first, the window carries on onto it; past that one's
    /// own edges, where the two displays' heights differ, it stops again.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/516"))
    func theWindowCrossesOntoAnotherDisplay() {
        let main = CGRect(x: 0, y: 0, width: 1728, height: 1084)
        // 1920 × 1080 under a 25 pt menu bar.
        let right = CGRect(x: 1728, y: 0, width: 1920, height: 1055)
        var s = PictureInPictureThrow(frame: window, at: 0, pointer: CGVector(dx: 100, dy: 50), displays: [main, right])
        var t = 0.0
        for _ in 0..<40 {
            t += 1.0 / 120
            _ = s.move(dx: 30, dy: 0, at: t)
        }
        #expect(s.frame.minX == 2136)
        for _ in 0..<40 {
            t += 1.0 / 120
            _ = s.move(dx: 0, dy: 30, at: t)
        }
        // The right display's last row under its menu bar, 1054, less 50.
        #expect(s.frame.minY == 1004)
    }

    /// A long stall (the Mac busy for a quarter of a second) doesn't fling the window away.
    @Test func aDroppedFrameStaysStable() {
        var f = PictureInPictureFlight(from: CGPoint(x: 900, y: 600), velocity: .zero, to: CGPoint(x: 10, y: 10))
        let p = f.step(0.25)
        #expect(p.x >= 10 && p.x <= 900)
        #expect(p.y >= 10 && p.y <= 600)
    }
}
