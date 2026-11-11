import CoreGraphics
import CraCore
import Testing

/// Where a page goes beside its docked DevTools: in a pane of the browser window, and in a Little
/// Window or a Peek (GitHub #348, where their DevTools never left the corner of the screen).
struct DevToolsPlaceholderTests {

    /// Docked on the right, Chrome's default: the page keeps the left of its area. The frontend
    /// counts from its top left, the area from its bottom left.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/348"))
    func dockedRightLeavesThePageTheLeft() {
        let hole = DevToolsPlaceholder(bounds: CGRect(x: 0, y: 0, width: 600, height: 800), frontendSize: CGSize(width: 1000, height: 800))
        let area = CGRect(x: 200, y: 100, width: 1000, height: 800)
        #expect(hole.pageRect(in: area) == CGRect(x: 200, y: 100, width: 600, height: 800))
    }

    /// Docked at the bottom: the page keeps the top, which is the high end of AppKit's y axis.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/348"))
    func dockedBottomLeavesThePageTheTop() {
        let hole = DevToolsPlaceholder(bounds: CGRect(x: 0, y: 0, width: 1000, height: 500), frontendSize: CGSize(width: 1000, height: 800))
        let area = CGRect(x: 200, y: 100, width: 1000, height: 800)
        #expect(hole.pageRect(in: area) == CGRect(x: 200, y: 400, width: 1000, height: 500))
    }

    /// Device mode puts the page in the middle: its distance from each edge is kept.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/348"))
    func aHoleInTheMiddleKeepsItsMargins() {
        let hole = DevToolsPlaceholder(bounds: CGRect(x: 50, y: 40, width: 400, height: 300), frontendSize: CGSize(width: 1000, height: 800))
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        // 50 from the left, 40 from the top, 550 from the right, 460 from the bottom.
        #expect(hole.pageRect(in: area) == CGRect(x: 50, y: 460, width: 400, height: 300))
    }

    /// The window grew before the frontend laid out again: DevTools keep their width, the page
    /// takes the rest.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/348"))
    func aResizedAreaGrowsThePageNotDevTools() {
        let hole = DevToolsPlaceholder(bounds: CGRect(x: 0, y: 0, width: 600, height: 800), frontendSize: CGSize(width: 1000, height: 800))
        let area = CGRect(x: 0, y: 0, width: 1300, height: 900)
        // DevTools were 400 wide and stay so.
        #expect(hole.pageRect(in: area) == CGRect(x: 0, y: 0, width: 900, height: 900))
    }

    /// An area narrower than DevTools were: the page keeps a sliver inside the area, never a
    /// rect outside it or an empty one.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/348"))
    func aSmallAreaStillHoldsThePage() {
        let hole = DevToolsPlaceholder(bounds: CGRect(x: 0, y: 0, width: 600, height: 800), frontendSize: CGSize(width: 1000, height: 800))
        let area = CGRect(x: 10, y: 10, width: 300, height: 200)
        let page = hole.pageRect(in: area)
        #expect(area.contains(page))
        #expect(page == CGRect(x: 10, y: 10, width: 1, height: 200))
    }

    /// A hole off the frontend altogether gives the page the whole area.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/348"))
    func aHoleOutsideTheAreaGivesThePageAllOfIt() {
        let hole = DevToolsPlaceholder(bounds: CGRect(x: 5000, y: 0, width: 100, height: 100), frontendSize: CGSize(width: 1000, height: 800))
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(hole.pageRect(in: area) == area)
    }

    /// The page rounds the corners it shares with its area; where it meets DevTools it is square.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/348"))
    func thePageRoundsOnlyTheCornersItSharesWithItsArea() {
        let area = CGRect(x: 0, y: 0, width: 1000, height: 800)
        #expect(AreaCorners.shared(by: area, with: area) == [.bottomLeft, .bottomRight, .topLeft, .topRight])
        // DevTools on the right.
        #expect(AreaCorners.shared(by: CGRect(x: 0, y: 0, width: 600, height: 800), with: area) == [.bottomLeft, .topLeft])
        // DevTools on the left.
        #expect(AreaCorners.shared(by: CGRect(x: 400, y: 0, width: 600, height: 800), with: area) == [.bottomRight, .topRight])
        // DevTools at the bottom.
        #expect(AreaCorners.shared(by: CGRect(x: 0, y: 300, width: 1000, height: 500), with: area) == [.topLeft, .topRight])
        // Device mode, in the middle.
        #expect(AreaCorners.shared(by: CGRect(x: 50, y: 460, width: 400, height: 300), with: area) == [])
        // Rounding in the layout doesn't cost a corner.
        #expect(AreaCorners.shared(by: CGRect(x: 0.25, y: -0.25, width: 600, height: 800), with: area).contains(.bottomLeft))
        #expect(AreaCorners.bottom == [.bottomLeft, .bottomRight])
    }
}
