import CoreGraphics
import CraCore
import Testing

/// The Library button's glyph moves like Arc's when hovered (GitHub #608). The numbers are Arc 1.173's,
/// measured from 120 fps captures of its button.
@Suite struct LibraryGlyphMotionTests {
    typealias G = LibraryGlyph

    /// How far the star has turned from rest toward hovered.
    func starTurn(_ m: G.Motion, _ t: Double) -> Double {
        (m.frame(at: t).pose.starAngle - G.rest.starAngle) / (G.hovered.starAngle - G.rest.starAngle)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/608")) func restsUntilHovered() {
        let m = G.Motion()
        for t in [0.0, 0.1, 5, 1000] {
            let f = m.frame(at: t)
            #expect(f.pose == G.rest)
            #expect(f.dotVisible && f.triangleScale == 1 && f.triangleOpacity == 1)
            #expect(m.isSettled(at: t))
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/608")) func hoverLiftsAndTurnsTheStarOnArcsSpring() {
        var m = G.Motion()
        m.head(to: G.hovered, at: 10)
        #expect(!m.isSettled(at: 10.5))
        #expect(m.frame(at: 10).pose == G.rest)
        // Arc: 20 % at 50 ms, 42 % at 0.1 s, 77 % at 0.2 s, 92.5 % at 0.3 s, 99 % at 0.4 s, no overshoot.
        for (t, arc) in [(0.05, 0.20), (0.1, 0.42), (0.2, 0.77), (0.3, 0.925), (0.4, 0.99)] {
            #expect(abs(starTurn(m, 10 + t) - arc) < 0.04, "at \(t) s")
        }
        var last = 0.0
        for i in 0...100 {
            let turn = starTurn(m, 10 + Double(i) / 100)
            #expect(turn >= last - 1e-9 && turn <= 1 + 1e-9)
            last = turn
        }
        #expect(m.frame(at: 11).pose == G.hovered)
        #expect(m.isSettled(at: 11))
        // The star comes up out of the box and turns clockwise; the triangle turns the other way.
        #expect(G.hovered.star.y < G.rest.star.y - 1.5)
        #expect(G.hovered.starAngle - G.rest.starAngle > 100)
        #expect(G.hovered.triangleAngle - G.rest.triangleAngle < -120)
        #expect(G.hovered.dot.y < G.rest.dot.y)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/608")) func dotAndTriangleAreSwappedPartWay() {
        var m = G.Motion()
        m.head(to: G.hovered, at: 0)
        let before = m.frame(at: 0.13)
        #expect(before.dotVisible)
        #expect(before.triangleScale < 0.6 && before.triangleOpacity < 0.6)
        let after = m.frame(at: 0.15)
        #expect(!after.dotVisible)
        #expect(after.triangleScale > 1.3 && after.triangleOpacity == 1)
        #expect(!m.frame(at: 0.29).dotVisible)
        let back = m.frame(at: 0.31)
        #expect(back.dotVisible && back.pose.dot == G.hovered.dot)
        #expect(back.triangleScale > 1 && back.triangleScale < 1.15)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/608")) func leavingHalfwayTurnsBackWithoutAJump() {
        var m = G.Motion()
        m.head(to: G.hovered, at: 0)
        let at = m.frame(at: 0.2).pose.components, next = m.frame(at: 0.201).pose.components
        m.head(to: G.rest, at: 0.2)
        let now = m.frame(at: 0.2).pose.components, then = m.frame(at: 0.201).pose.components
        for i in at.indices {
            #expect(abs(now[i] - at[i]) < 1e-9)
            #expect(abs(then[i] - next[i]) < 0.05)  // points or degrees; a jump would be several
        }
        #expect(m.frame(at: 1.2).pose == G.rest)
        // Hovering again while it is still going back keeps going the same way: to the target given last.
        m.head(to: G.rest, at: 0.5)
        #expect(m.target == G.rest && !m.isSettled(at: 1.1))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/608")) func starSinksIntoTheBoxAtRest() {
        // Only the star's top is above the line the shapes are cut off at; hovered, most of it is.
        let rest = G.starPath(center: G.rest.star, angle: G.rest.starAngle).boundingBox
        let hovered = G.starPath(center: G.hovered.star, angle: G.hovered.starAngle).boundingBox
        #expect(rest.minY < G.clipBottom && rest.maxY > G.clipBottom)
        #expect((G.clipBottom - rest.minY) / rest.height < 0.6)
        #expect((G.clipBottom - hovered.minY) / hovered.height > 0.6)
        #expect(G.clipBottom < G.box.minY)
        // The box's slot shows through; the box is filled around it.
        let box = G.boxPath()
        #expect(!box.contains(CGPoint(x: G.slot.midX, y: G.slot.midY), using: .evenOdd))
        #expect(box.contains(CGPoint(x: 0, y: G.box.maxY - 2), using: .evenOdd))
    }
}

extension LibraryGlyph.Pose {
    var components: [Double] {
        [star.x, star.y, starAngle, dot.x, dot.y, triangle.x, triangle.y, triangleAngle]
    }
}
