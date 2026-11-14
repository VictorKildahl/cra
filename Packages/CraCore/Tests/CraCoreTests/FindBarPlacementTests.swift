import CoreGraphics
import CraCore
import Testing

/// Where the find bar (and Ask on Page's card in its place) sits over the focused page.
struct FindBarPlacementTests {
    /// A 1000 × 700 page, y growing upward: its top edge is at y 710.
    let page = CGRect(x: 290, y: 10, width: 1000, height: 700)
    let size = CGSize(width: 300, height: 38)
    let inset: CGFloat = 10

    @Test func sitsInThePagesTopTrailingCorner() {
        let frame = FindBarPlacement.frame(page: page, size: size, inset: inset)
        #expect(frame == CGRect(x: 980, y: 662, width: 300, height: 38))
    }

    /// Beside the Library the page keeps its width and goes past the window's edge: the corner is
    /// that of the part the window shows (#340).
    @Test func aPagePastTheWindowsEdgeKeepsTheBarInTheWindow() {
        let frame = FindBarPlacement.frame(page: page, visibleMaxX: 1100, size: size, inset: inset)
        #expect(frame.maxX == 1090)
        #expect(frame.maxY == 700)
        // A window edge beyond the page changes nothing.
        #expect(FindBarPlacement.frame(page: page, visibleMaxX: 1400, size: size, inset: inset)
            == FindBarPlacement.frame(page: page, size: size, inset: inset))
    }

    /// The floating toolbar slides out over the page's top (Settings ▸ Pages ▸ "Hide the toolbar
    /// until you need it"). The find bar's window is above everything in Cra's window, so it
    /// covered the toolbar's right end (noted on #405): it hangs under the toolbar instead, and is
    /// back in the corner once the toolbar has gone.
    @Test func hangsUnderAFloatingToolbarThatIsOut() {
        let under = FindBarPlacement.frame(page: page, size: size, inset: inset, toolbarOverPage: 32)
        #expect(under == CGRect(x: 980, y: 630, width: 300, height: 38))
        // Nothing of it is where the toolbar is (y 678…710).
        #expect(under.maxY <= 710 - 32)
        #expect(FindBarPlacement.frame(page: page, size: size, inset: inset, toolbarOverPage: 0).maxY == 700)
    }

    /// Ask on Page's card takes the find bar's place and grows downward: its top stays put.
    @Test func aTallerCardKeepsItsTop() {
        let card = FindBarPlacement.frame(page: page, size: CGSize(width: 340, height: 220), inset: inset, toolbarOverPage: 32)
        #expect(card.maxY == 668)
        #expect(card.maxX == 1280)
        #expect(card.minY == 448)
    }
}
