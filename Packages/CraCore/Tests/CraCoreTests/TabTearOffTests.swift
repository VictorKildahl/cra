import CoreGraphics
import CraCore
import Testing

/// A tab dragged out of every window opens in a Blank Window where it was dropped (Arc 1.172, #219).
struct TabTearOffTests {
    // Victor's built-in display: 1728 × 1117, the menu bar takes the top 33 pt.
    let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/219"))
    func onlyATabLetGoOutsideEveryWindowTearsOff() {
        #expect(TabTearOff.tearsOff(isTab: true, incognito: false, dropAccepted: false, overAppWindow: false))
        // Dropped on a sidebar, or let go over a Cra window (its page, its toolbar): no new window.
        #expect(!TabTearOff.tearsOff(isTab: true, incognito: false, dropAccepted: true, overAppWindow: false))
        #expect(!TabTearOff.tearsOff(isTab: true, incognito: false, dropAccepted: false, overAppWindow: true))
        // Folders and splits stay; incognito pages can't load in a Blank Window.
        #expect(!TabTearOff.tearsOff(isTab: false, incognito: false, dropAccepted: false, overAppWindow: false))
        #expect(!TabTearOff.tearsOff(isTab: true, incognito: true, dropAccepted: false, overAppWindow: false))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/219"))
    func nearTheTopLeftTheWindowStopsTwentyPointsInside() {
        // Arc: a 1000 × 760 window's tab let go at (350, 300) from the top left opened at
        // (20, 53) from the top left: 20 pt inside the visible frame on both sides.
        let f = TabTearOff.frame(size: CGSize(width: 1000, height: 760), droppedAt: CGPoint(x: 350, y: 1117 - 300), visible: visible)
        #expect(f == CGRect(x: 20, y: 1117 - 53 - 760, width: 1000, height: 760))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/219"))
    func arcsDropsInTheOpenCentreOnThePointer() {
        // Arc 1.172: a 926 × 500 window's tab let go at (1100, 700) and (500, 820) from the top left
        // opened at (637, 450) and (37, 570) from the top left.
        let size = CGSize(width: 926, height: 500)
        for (drop, origin) in [(CGPoint(x: 1100, y: 700), CGPoint(x: 637, y: 450)), (CGPoint(x: 500, y: 820), CGPoint(x: 37, y: 570))] {
            let f = TabTearOff.frame(size: size, droppedAt: CGPoint(x: drop.x, y: 1117 - drop.y), visible: visible)
            #expect(f == CGRect(x: origin.x, y: 1117 - origin.y - 500, width: 926, height: 500))
        }
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/219"))
    func inTheOpenTheWindowCentresOnThePointer() {
        let f = TabTearOff.frame(size: CGSize(width: 700, height: 500), droppedAt: CGPoint(x: 900, y: 500), visible: visible)
        #expect(f == CGRect(x: 550, y: 250, width: 700, height: 500))
        // Bottom right: held inside too.
        let g = TabTearOff.frame(size: CGSize(width: 700, height: 500), droppedAt: CGPoint(x: 1720, y: 5), visible: visible)
        #expect(g == CGRect(x: 1728 - 20 - 700, y: 20, width: 700, height: 500))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/219"))
    func aWindowLargerThanTheScreenShrinksToFit() {
        let f = TabTearOff.frame(size: CGSize(width: 2560, height: 1440), droppedAt: CGPoint(x: 900, y: 500), visible: visible)
        #expect(f == CGRect(x: 20, y: 20, width: 1688, height: 1044))
    }
}
