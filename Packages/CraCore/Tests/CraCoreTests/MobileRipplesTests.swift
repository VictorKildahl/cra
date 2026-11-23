import CoreGraphics
import CraCore
import Foundation
import Testing

/// The empty home screen's dots and the rings a finger sends through them.
struct MobileRipplesTests {
    private func level(_ field: MobileRipples, _ x: CGFloat, _ y: CGFloat, at time: Double) -> Double {
        field.state(at: CGPoint(x: x, y: y), time: time).level
    }

    /// The recording: a 430 × 932 pt screen with 21 columns from 15 pt in and 46 rows from 16 pt down,
    /// a dot every 20 pt. A narrower phone keeps the spacing and centres the grid.
    @Test func theGridMatchesTheRecording() {
        let grid = MobileRipples.grid(in: CGSize(width: 430, height: 932))
        #expect(grid.count == 21 * 46)
        #expect(grid.first == CGPoint(x: 15, y: 16))
        #expect(grid[1] == CGPoint(x: 35, y: 16))
        #expect(grid[21] == CGPoint(x: 15, y: 36))
        #expect(grid.last == CGPoint(x: 415, y: 916))

        let narrow = MobileRipples.grid(in: CGSize(width: 393, height: 852))
        #expect(narrow.count == 19 * 42)
        #expect(narrow.first?.x == 16.5)
        #expect(narrow[18].x == 393 - 16.5)
        #expect(MobileRipples.grid(in: .zero).isEmpty)
    }

    @Test func dotsAreSmallAtRestAndSwellToTheRecordingsSize() {
        #expect(MobileRipples.diameter(level: 0) == 2)
        #expect(MobileRipples.diameter(level: 1) == 6.5)
        #expect(MobileRipples.diameter(level: 3) == 6.5)
        let field = MobileRipples()
        #expect(field.isStill)
        #expect(level(field, 100, 100, at: 5) == 0)
        #expect(field.state(at: CGPoint(x: 100, y: 100), time: 5).offset == .zero)
    }

    /// The swell starts on touch-down: a tenth of a second in, the dot under the finger is most of
    /// the way up, its neighbour a little less, and a dot across the screen hasn't moved.
    @Test func aPressSwellsTheDotsUnderTheFingerAtOnce() {
        var field = MobileRipples()
        field.press(1, at: CGPoint(x: 200, y: 400), time: 10)
        #expect(!field.isStill)
        let under = level(field, 200, 400, at: 10.1)
        let beside = level(field, 220, 400, at: 10.1)
        #expect(under > 0.7)
        #expect(beside > 0.4 && beside < under)
        #expect(level(field, 200, 700, at: 10.1) == 0)
        #expect(field.ringsStarted == 0)
    }

    /// Lifted, the swell leaves as a ring: half a second later the crest is about 210 pt out,
    /// brighter there than at the finger or beyond it, and a moment later it is further out.
    @Test func liftingSendsARingOutward() {
        var field = MobileRipples()
        field.press(1, at: CGPoint(x: 200, y: 400), time: 0)
        field.lift(1, time: 0.1)
        #expect(field.ringsStarted == 1)
        let half = 0.6
        let crest = level(field, 200, 400 + 210, at: half)
        #expect(crest > 0.2)
        #expect(crest > level(field, 200, 400, at: half))
        #expect(crest > level(field, 200, 400 + 400, at: half))

        func brightest(at time: Double) -> CGFloat {
            stride(from: CGFloat(0), through: 600, by: 5).max { level(field, 200, 400 + $0, at: time) < level(field, 200, 400 + $1, at: time) } ?? 0
        }
        #expect(brightest(at: 0.4) < brightest(at: 0.8))
        #expect(brightest(at: 0.8) < brightest(at: 1.2))
    }

    /// A second, weaker ring follows the first, as in water, with a dark gap between them.
    @Test func aWeakerRingFollowsTheFirst() {
        var field = MobileRipples()
        field.press(1, at: .zero, time: 0)
        field.lift(1, time: 0.05)
        let age = 0.8, time = 0.05 + age
        let front = CGFloat(MobileRipples.speed * age)
        let gap = CGFloat(MobileRipples.echoGap * MobileRipples.width * (1 + MobileRipples.spread * age))
        let first = level(field, 0, front, at: time)
        let second = level(field, 0, front - gap, at: time)
        let between = level(field, 0, front - gap / 2, at: time)
        #expect(second < first)
        #expect(between < second * 0.8)
    }

    @Test func aLongerPressSendsAStrongerRing() {
        var tap = MobileRipples(), hold = MobileRipples()
        tap.press(1, at: .zero, time: 0)
        tap.lift(1, time: 0.06)
        hold.press(1, at: .zero, time: 0)
        hold.lift(1, time: 0.8)
        #expect(tap.rings[0].strength >= 0.5)
        #expect(hold.rings[0].strength > tap.rings[0].strength)
        #expect(abs(hold.rings[0].strength - 1) < 1e-9)
    }

    /// The crest pushes the dots it passes away from where the finger was.
    @Test func theCrestPushesDotsOutward() {
        var field = MobileRipples()
        field.press(1, at: CGPoint(x: 100, y: 100), time: 0)
        field.lift(1, time: 0.3)
        let time = 0.3 + 0.5
        let right = field.state(at: CGPoint(x: 100 + 210, y: 100), time: time).offset
        let above = field.state(at: CGPoint(x: 100, y: 100 - 210), time: time).offset
        #expect(right.dx > 1 && abs(right.dy) < 1e-6)
        #expect(above.dy < -1 && abs(above.dx) < 1e-6)
        #expect(hypot(right.dx, right.dy) <= MobileRipples.push * 1.5 + 1e-9)
    }

    /// Where two rings cross the dots brighten more than under either, but never past full.
    @Test func crossingRingsAddUpWithoutGoingPastFull() {
        func ring(from x: CGFloat, finger: Int, into field: inout MobileRipples) {
            field.press(finger, at: CGPoint(x: x, y: 0), time: 0)
            field.lift(finger, time: 0.5)
        }
        var one = MobileRipples()
        ring(from: 0, finger: 1, into: &one)
        var two = one
        ring(from: 400, finger: 2, into: &two)
        let meeting = CGPoint(x: 200, y: 0), time = 0.5 + 200 / MobileRipples.speed
        let single = one.state(at: meeting, time: time).level
        let both = two.state(at: meeting, time: time).level
        #expect(both > single)
        #expect(both <= 1)

        var pile = MobileRipples()
        for finger in 0..<20 { ring(from: 0, finger: finger, into: &pile) }
        #expect(pile.state(at: .zero, time: 0.5).level <= 1)
    }

    /// Rings fade and go, and then the field is still, so the view stops drawing.
    @Test func ringsFadeAndTheFieldGoesStill() {
        var field = MobileRipples()
        field.press(1, at: .zero, time: 0)
        field.lift(1, time: 0.1)
        field.prune(time: 1)
        #expect(!field.isStill)
        field.prune(time: 6)
        #expect(field.isStill)
        #expect(field.ringsStarted == 1)
    }

    /// A drag leaves a small ring every 34 pt of the way, weaker than a lift's.
    @Test func aDragLeavesAWake() {
        var field = MobileRipples()
        field.press(1, at: .zero, time: 0)
        for step in 1...10 {
            field.move(1, to: CGPoint(x: CGFloat(step) * 10, y: 0), time: 0.3 + Double(step) * 0.01)
        }
        #expect(field.ringsStarted == 2)
        #expect(field.rings.map(\.origin.x) == [40, 80])
        #expect(field.rings.allSatisfy { $0.strength < 0.5 })
        // The swell went with the finger.
        #expect(level(field, 100, 0, at: 0.4) > level(field, 0, 0, at: 0.4))
        field.lift(1, time: 0.5)
        #expect(field.ringsStarted == 3)
    }

    /// With Reduce Motion nothing travels: a lift fades where it is, and a drag leaves no wake.
    @Test func withoutMotionALiftFadesInPlace() {
        var field = MobileRipples(travels: false)
        field.press(1, at: .zero, time: 0)
        field.move(1, to: CGPoint(x: 100, y: 0), time: 0.2)
        #expect(field.ringsStarted == 0)
        field.lift(1, time: 0.3)
        for time in stride(from: 0.3, through: 2, by: 0.1) {
            #expect(level(field, 300, 0, at: time) == 0)
            #expect(field.state(at: CGPoint(x: 110, y: 0), time: time).offset == .zero)
        }
        #expect(level(field, 100, 0, at: 0.3) > 0.7)
        #expect(level(field, 100, 0, at: 1.5) < 0.02)
        field.prune(time: 2)
        #expect(field.isStill)
    }

    /// Hammering the screen keeps at most `maximumRings`, dropping the oldest.
    @Test func theOldestRingsGiveWay() {
        var field = MobileRipples()
        for finger in 0..<(MobileRipples.maximumRings + 5) {
            field.press(finger, at: CGPoint(x: finger, y: 0), time: Double(finger) * 0.01)
            field.lift(finger, time: Double(finger) * 0.01 + 0.05)
        }
        #expect(field.rings.count == MobileRipples.maximumRings)
        #expect(field.rings.first?.origin.x == 5)
        #expect(field.ringsStarted == MobileRipples.maximumRings + 5)
    }

    /// A view leaving the screen drops its fingers without sending rings.
    @Test func liftingEveryFingerAtOnceSendsNothing() {
        var field = MobileRipples()
        field.press(1, at: .zero, time: 0)
        field.liftAll()
        #expect(field.isStill)
        #expect(field.ringsStarted == 0)
    }
}

struct MobileEmptyHomeTests {
    /// Arc Search's empty home (its gradient and the logo) stays the default; Rippling Dots is an App Setting, off
    /// in a settings file from an older build, and keeps the logo over the dots (Victor, 23 Nov 2026, PR #708).
    @Test func theDotsAreASettingAndTheLogoStays() throws {
        #expect(MobileSettings().homeDots == false)
        let older = try JSONDecoder().decode(MobileSettings.self, from: Data(#"{"opensKeyboardOnLaunch":false}"#.utf8))
        #expect(older.homeDots == false)
        var on = MobileSettings()
        on.homeDots = true
        #expect(try JSONDecoder().decode(MobileSettings.self, from: JSONEncoder().encode(on)).homeDots)

        let arc = MobileEmptyHome(dots: false, home: true, searching: false, incognitoSearch: false, pulling: false)
        #expect(arc.backdrop == .arcSearch && arc.showsLogo && !arc.showsDots && !arc.showsSearchHint && !arc.barFloats)

        let dots = MobileEmptyHome(dots: true, home: true, searching: false, incognitoSearch: false, pulling: false)
        #expect(dots.backdrop == .dots && dots.showsLogo && dots.showsDots && dots.showsSearchHint && dots.barFloats)
    }

    @Test func theSheetAndPagesCoverIt() {
        let searching = MobileEmptyHome(dots: true, home: true, searching: true, incognitoSearch: false, pulling: false)
        #expect(!searching.showsLogo && searching.showsDots && !searching.showsSearchHint, "the dots stay behind the sheet")
        let incognito = MobileEmptyHome(dots: true, home: true, searching: true, incognitoSearch: true, pulling: false)
        #expect(!incognito.showsDots, "not behind incognito's grey")
        let pulling = MobileEmptyHome(dots: true, home: true, searching: false, incognitoSearch: false, pulling: true)
        #expect(!pulling.showsSearchHint)
        let page = MobileEmptyHome(dots: true, home: false, searching: false, incognitoSearch: false, pulling: false)
        #expect(!page.showsLogo && !page.showsDots && !page.showsSearchHint && !page.barFloats)
    }
}
