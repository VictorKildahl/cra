import CraCore
import Foundation
import Testing

/// Settings ▸ General ▸ Pages ▸ Margin (Ideas #366, whyady): the room round the pages, 1 to 10 pt, with
/// Edge to edge as its zero.
struct PageMarginTests {
    /// Nobody's window changes: a settings file from before the slider loads at Arc's 10 pt.
    @Test func arcsMarginByDefault() throws {
        #expect(AppSettings().pageMargin == 10)
        #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).pageMargin == 10)
        #expect(PageMargin.arc == 10)
        #expect(PageMargin.inset(margin: AppSettings().pageMargin, fillsWindow: false) == 10)
    }

    /// The setting is saved and read back, and not in Arc, so a report never names it.
    @Test func savedAndReadBack() throws {
        var s = AppSettings()
        s.pageMargin = 4
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.pageMargin == 4)
        #expect(UsageStats.unreportedSettings.contains("pageMargin"))
    }

    /// The card sits that many points in; where it fills the window (edge to edge, or full screen with the
    /// sidebar hidden) there is none, whatever the slider says.
    @Test(arguments: [1.0, 4, 7, 10])
    func theCardSitsTheMarginIn(margin: Double) {
        #expect(PageMargin.inset(margin: margin, fillsWindow: false) == margin)
        #expect(PageMargin.inset(margin: margin, fillsWindow: true) == 0)
    }

    /// A hand-edited or synced value outside the slider's range draws as the nearest one it offers, in whole
    /// points; one that isn't a number is Arc's. 0 stays Edge to edge's switch, not the margin's.
    @Test(arguments: [(0.0, 1.0), (-3, 1), (0.4, 1), (3.4, 3), (3.6, 4), (10, 10), (25, 10), (.nan, 10), (.infinity, 10)])
    func outOfRangeValuesClamp(stored: Double, drawn: Double) {
        #expect(PageMargin.clamped(stored) == drawn)
        #expect(PageMargin.inset(margin: stored, fillsWindow: false) == drawn)
    }

    /// A click in the margin above the card is the title bar's, as it was with Arc's 10 pt: the strip follows
    /// the margin, and edge to edge it is the card's top 4 pt.
    @Test func theTitleStripFollowsTheMargin() {
        #expect(PageMargin.titleStrip(margin: 10, edgeToEdge: false) == 14)
        #expect(PageMargin.titleStrip(margin: 3, edgeToEdge: false) == 7)
        #expect(PageMargin.titleStrip(margin: 3, edgeToEdge: true) == 4)
    }

    /// The hidden sidebar comes out over the whole margin, as before at 10 pt, and never reaches more than
    /// Arc's 5 pt into the page at a narrow one.
    @Test func theRevealStripTakesTheMarginButReachesNoFurtherIntoThePage() {
        #expect(PageMargin.revealInside(margin: 10, fillsWindow: false) == Double(FloatingSidebarGeometry.revealInside))
        #expect(PageMargin.revealInside(margin: 8, fillsWindow: false) == 8)
        #expect(PageMargin.revealInside(margin: 2, fillsWindow: false) == 5)
        #expect(PageMargin.revealInside(margin: 10, fillsWindow: true) == Double(FloatingSidebarGeometry.revealInsideEdgeToEdge))
        for margin in stride(from: 1.0, through: 10, by: 1) {
            let reach = PageMargin.revealInside(margin: margin, fillsWindow: false) - margin
            #expect(reach <= 5)
        }
    }

    /// Peek knows the sidebar is beside the page when the card starts further in than the margin; a card
    /// resting in a narrow margin with the sidebar hidden doesn't count as beside it.
    @Test func besideTheSidebarIsPastTheMargin() {
        #expect(!PageMargin.besideSidebar(cardEdge: 3, margin: 3, fillsWindow: false))
        #expect(PageMargin.besideSidebar(cardEdge: 240, margin: 3, fillsWindow: false))
        #expect(!PageMargin.besideSidebar(cardEdge: 10, margin: 10, fillsWindow: false))
        #expect(!PageMargin.besideSidebar(cardEdge: 0, margin: 10, fillsWindow: true))
        #expect(PageMargin.besideSidebar(cardEdge: 240, margin: 10, fillsWindow: true))
    }
}

/// The hidden sidebar's strip at the window's edge follows the margin (Ideas #366).
struct PageMarginRevealTests {
    let bounds = CGRect(x: 0, y: 0, width: 1200, height: 800)

    /// At Arc's margin nothing moves: out over the whole 10 pt, not at 11; 5 pt edge to edge.
    @Test func arcsMarginKeepsTheStrip() {
        #expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 10, y: 400), in: bounds))
        #expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 11, y: 400), in: bounds))
        #expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 5, y: 400), in: bounds, edgeToEdge: true, pageMargin: 3))
        #expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 6, y: 400), in: bounds, edgeToEdge: true, pageMargin: 3))
    }

    /// At a 3 pt margin the page starts 3 pt in: a pointer 8 pt in is on the page, not in the strip, and the
    /// sidebar that is out leaves when the pointer goes there.
    @Test func aNarrowMarginLeavesThePageItsPointer() {
        #expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 5, y: 400), in: bounds, pageMargin: 3))
        #expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 8, y: 400), in: bounds, pageMargin: 3))
        #expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 8, y: 400), in: bounds, pageMargin: 8))
        // Mirrored when the sidebar docks on the right (#464).
        #expect(FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 1195, y: 400), in: bounds, side: .right, pageMargin: 3))
        #expect(!FloatingSidebarGeometry.shouldReveal(at: CGPoint(x: 1192, y: 400), in: bounds, side: .right, pageMargin: 3))
    }
}

/// Victor, trying the slider (23 Nov 2026): at a 3 pt margin the page's top-right and bottom-right corners stood out
/// past the window's round corners. A page is a window of its own the main window doesn't clip, so its 6 pt round
/// 3 pt in from a 16 pt window corner reaches outside it. The card's round follows the window's, concentric.
struct PageMarginCornerTests {
    /// At Arc's 10 pt in a 16 pt window corner the round is Arc's 6 pt: nothing changes by default.
    @Test func arcsMarginKeepsArcsRound() {
        #expect(PageMargin.cardRadius(margin: 10, windowRadius: 16, base: 6) == 6)
    }

    /// Narrower margins round the card more, so its corner stays inside the window's.
    @Test(arguments: [(3.0, 13.0), (1, 15), (4, 12), (8, 8)])
    func narrowerMarginsRoundTheCardWithTheWindow(margin: Double, round: Double) {
        let r = PageMargin.cardRadius(margin: margin, windowRadius: 16, base: 6)
        #expect(r == round)
        #expect(r + margin >= 16, "concentric with the window's corner, or inside it")
    }

    /// Never squarer than Arc's round; a window with no round corners (full screen) keeps Arc's.
    @Test func neverLessThanArcsRound() {
        #expect(PageMargin.cardRadius(margin: 3, windowRadius: 0, base: 6) == 6)
        #expect(PageMargin.cardRadius(margin: 10, windowRadius: 10, base: 6) == 6)
        #expect(PageMargin.cardRadius(margin: 30, windowRadius: 16, base: 6) == 6)
    }
}
