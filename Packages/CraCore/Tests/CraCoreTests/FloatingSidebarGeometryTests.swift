import CoreGraphics
import CraCore
import Testing

/// Where the pointer brings the hidden sidebar out, and where it lets it go (Arc 1.170–1.172.2).
/// The controller's side of it runs in Tests/FloatingSidebarTests.swift.
struct FloatingSidebarGeometryTests {
    /// The shell's bounds, away from zero so window-local and shell-local can't be mixed up.
    let bounds = CGRect(x: 20, y: 10, width: 1400, height: 880)

    @Test(arguments: [(20.0, true), (30.0, true), (30.1, false), (16.0, true), (15.9, false)])
    func theStripIsTheMarginAndFourPointsOutside(x: Double, reveals: Bool) {
        #expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: x, y: 100), in: bounds) == reveals)
    }

    @Test func edgeToEdgeTheStripIsFivePoints() {
        #expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 25, y: 100), in: bounds, edgeToEdge: true))
        #expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 25.1, y: 100), in: bounds, edgeToEdge: true))
        #expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 22, y: 9.9), in: bounds))
        #expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 22, y: 890.1), in: bounds))
    }

    @Test func itComesOutOverAFullscreenPage() {
        #expect(FloatingSidebarGeometry.mayReveal(sidebarShown: false, pageFullscreen: false))
        #expect(FloatingSidebarGeometry.mayReveal(sidebarShown: true, pageFullscreen: true))
        #expect(!FloatingSidebarGeometry.mayReveal(sidebarShown: true, pageFullscreen: false))
    }

    /// Arc 1.172.2, a 264 pt sidebar: out with the pointer 250 pt left of the window, not at 270,
    /// and a sidebar that is out leaves at 252–257.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/350"),
          arguments: [(15.9, 100.0, true), (16.0, 100.0, false), (-80.0, 100.0, true), (-236.0, 100.0, true),
                      (-236.1, 100.0, false), (-80.0, 9.9, false), (-80.0, 890.1, false), (300.0, 100.0, false)])
    func besideTheWindowIsOffTheEdge(x: Double, y: Double, off: Bool) {
        #expect(FloatingSidebarGeometry.isOffLeftEdge(CGPoint(x: x, y: y), in: bounds, sidebarWidth: 264) == off)
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/350"))
    func aSidebarThatIsOutStaysWhileThePointerIsBesideTheWindow() {
        func hides(_ x: CGFloat, _ y: CGFloat, buttons: Int = 0) -> Bool {
            FloatingSidebarGeometry.shouldHide(at: CGPoint(x: x, y: y), in: bounds, sidebarWidth: 264, pressedMouseButtons: buttons)
        }
        #expect(!hides(-80, 100))
        #expect(!hides(18, 100), "the strip's 4 pt outside the window keep it too")
        #expect(hides(-236.1, 100), "further left than the sidebar is wide")
        #expect(hides(-80, 890.1) && hides(-80, 9.9), "above and below the window")
        #expect(!hides(-80, 890.1, buttons: 1), "a held button keeps it wherever the pointer is")
        #expect(!hides(365, 100) && hides(365.1, 100), "over the window: 81 pt past the sidebar (#293)")
    }

    @Test func theStripWaitsATenthOfASecond() {
        var dwell = FloatingSidebarRevealDwell()
        // In the strip, out of it at 10.095 (the wait starts over), back in.
        let samples: [(Bool, Double)] = [(true, 10), (true, 10.09), (false, 10.095), (true, 10.1), (true, 10.19), (true, 10.21)]
        let over = samples.map { dwell.sample(inStrip: $0.0, at: $0.1) }
        #expect(over == [false, false, false, false, false, true])
        dwell.reset()
        #expect(dwell.since == nil)
        let again = dwell.sample(inStrip: true, at: 11)
        #expect(!again)
    }

    // MARK: Past the edge (#350)

    private func run(_ samples: [(x: CGFloat, y: CGFloat, t: Double)], sidebarWidth: CGFloat = 264) -> [FloatingSidebarOffEdge.Step] {
        var off = FloatingSidebarOffEdge()
        return samples.map { off.sample(CGPoint(x: $0.x, y: $0.y), in: bounds, sidebarWidth: sidebarWidth, at: $0.t) }
    }

    /// Arc: ~150 ms after a pointer thrown 100 pt past the edge comes to rest.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/350"))
    func aThrowPastTheEdgeBringsItOutOnceThePointerRests() {
        let steps = run([(300, 400, 0), (-80, 400, 0.03), (-80, 400, 0.063), (-80, 400, 0.097), (-80, 400, 0.13)])
        #expect(steps == [.away, .waiting, .waiting, .waiting, .reveal], "three looks of the 30 Hz poll after the first")
    }

    /// Arc: ~222 ms after the pointer crossed the edge when it keeps moving, whatever its speed.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/350"))
    func aPointerThatKeepsMovingWaitsLonger() {
        let steps = run([(300, 400, 0), (22, 400, 0.03), (-30, 400, 0.06), (-60, 400, 0.093), (-90, 400, 0.127),
                         (-120, 400, 0.16), (-150, 400, 0.193), (-180, 400, 0.227)])
        #expect(steps == [.away, .away, .waiting, .waiting, .waiting, .waiting, .waiting, .reveal],
                "five looks of the 30 Hz poll after the first")
    }

    /// Arc: a pointer that reaches the zone from above, from below or from further left brings
    /// nothing out, however long it stays and moves there.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/350"),
          arguments: [CGPoint(x: -80, y: 950), CGPoint(x: -80, y: -50), CGPoint(x: -330, y: 400)])
    func onlyAPointerThatLeftTheWindowCounts(from start: CGPoint) {
        let steps = run([(start.x, start.y, 0), (-80, 400, 0.1), (-81, 400, 0.5), (-82, 402, 1), (-82, 402, 2)])
        #expect(steps.allSatisfy { $0 == .away })
    }

    /// Arc: out 40 pt and in again within 30 ms shows nothing, and going back out starts over.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/350"))
    func backOverThePageBeforeTheWaitEndsIsNothing() {
        let steps = run([(300, 400, 0), (-40, 400, 0.02), (60, 400, 0.05), (60, 400, 0.3), (-40, 400, 0.33), (-40, 400, 0.39)])
        #expect(steps == [.away, .waiting, .away, .away, .waiting, .waiting])
    }

    /// Leaving the zone outside the window (above it, or further left) ends it: coming back beside
    /// the window doesn't bring the sidebar out (Arc: T1c then T1d of the 11 Nov run).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/350"))
    func leavingTheZoneOutsideTheWindowEndsIt() {
        let steps = run([(300, 400, 0), (-80, 400, 0.03), (-80, 920, 0.06), (-80, 400, 0.1), (-80, 400, 0.4),
                         (-300, 400, 0.5), (-80, 400, 0.6), (-80, 400, 1)])
        #expect(steps == [.away, .waiting, .away, .away, .away, .away, .away, .away])
    }

    /// A slow exit goes through the strip (the window's own 4 pt outside it included) and on.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/350"))
    func theStripLeadsOutToo() {
        let steps = run([(-300, 400, 0), (18, 400, 0.1), (10, 400, 0.13), (10, 400, 0.3)])
        #expect(steps == [.away, .away, .waiting, .reveal])
    }

    @Test func aResetForgetsWhereThePointerWas() {
        var off = FloatingSidebarOffEdge()
        let overThePage = off.sample(CGPoint(x: 300, y: 400), in: bounds, sidebarWidth: 264, at: 0)
        off.reset()
        let besideTheWindow = off.sample(CGPoint(x: -80, y: 400), in: bounds, sidebarWidth: 264, at: 0.03)
        #expect(overThePage == .away && besideTheWindow == .away)
    }
}
