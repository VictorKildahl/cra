import CoreGraphics
import CraCore
import Testing

/// CRA_TEST_SCREEN: a test instance's windows open on one display, not the one in use.
struct TestScreenTests {
    // Victor's desk: the menu bar's 527pq in the middle, a Z24nf left, the other 527pq right.
    let middle = TestScreen.Display(name: "HP 527pq (2)", frame: CGRect(x: 0, y: 0, width: 2560, height: 1440),
                                    visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1415))
    let left = TestScreen.Display(name: "HP Z24nf G2", frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080),
                                  visibleFrame: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
    let right = TestScreen.Display(name: "HP 527pq (1)", frame: CGRect(x: 2560, y: 0, width: 2560, height: 1440),
                                   visibleFrame: CGRect(x: 2560, y: 0, width: 2560, height: 1440))
    var displays: [TestScreen.Display] { [middle, left, right] }

    @Test func theDisplayIsPickedBySideOrName() {
        #expect(TestScreen.pick("left", among: displays) == 1)
        #expect(TestScreen.pick("RIGHT", among: displays) == 2)
        #expect(TestScreen.pick("main", among: displays) == 0)
        #expect(TestScreen.pick("HP Z24nf G2", among: displays) == 1)
        #expect(TestScreen.pick("z24nf", among: displays) == 1)
        #expect(TestScreen.pick(" hp 527pq (1) ", among: displays) == 2)
    }

    @Test func unsetAmbiguousOrMissingChangesNothing() {
        #expect(TestScreen.pick(nil, among: displays) == nil)
        #expect(TestScreen.pick("", among: displays) == nil)
        #expect(TestScreen.pick("527pq", among: displays) == nil)  // two displays have it
        #expect(TestScreen.pick("Studio Display", among: displays) == nil)
        #expect(TestScreen.pick("left", among: []) == nil)
    }

    @Test func aWindowWithoutAPlaceIsCentredOnTheTestDisplay() {
        // A fresh data folder's first window (1400 × 880 at the origin, on the middle display).
        let f = TestScreen.centre(CGSize(width: 1400, height: 880), on: left)
        #expect(f == CGRect(x: -1920 + 260, y: 100, width: 1400, height: 880))
        // A frame on no display at all is centred too.
        #expect(TestScreen.place(CGRect(x: 9000, y: 9000, width: 1400, height: 880), on: left, among: displays) == f)
    }

    @Test func aSavedFrameKeepsItsPlaceOnTheTestDisplay() {
        // 40 pt from the left, 30 pt below the menu bar of the middle display.
        let saved = CGRect(x: 40, y: 1415 - 30 - 800, width: 1000, height: 800)
        #expect(TestScreen.place(saved, on: left, among: displays) == CGRect(x: -1880, y: 1080 - 30 - 800, width: 1000, height: 800))
        // Already on the test display: it stays put, so new windows cascade off the last one.
        let there = CGRect(x: -1800, y: 100, width: 900, height: 700)
        #expect(TestScreen.place(there, on: left, among: displays) == there)
    }

    @Test func aWindowTooBigForTheTestDisplayShrinksAndFits() {
        let big = CGRect(x: 600, y: 200, width: 2400, height: 1200)
        let f = TestScreen.place(big, on: left, among: displays)
        #expect(f.size == CGSize(width: 1920, height: 1080))
        #expect(left.visibleFrame.contains(f))
    }
}
