import CoreGraphics
import CraCore
import Testing

/// ⌥⌘N's compact card, measured on Arc 1.172.1 (#337).
struct LittleCardTests {
    /// Arc's display: 1728 × 1117 pt with a 33 pt menu bar and the Dock hidden.
    let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)

    /// 490 × 329 pt, 20 pt from the screen's right edge and 20 pt below the menu bar: x 1218, y 53
    /// from the top in Arc's capture. Cra opened a 1400 × 900 pt window in the middle.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/337"))
    func cardSitsTopRight() {
        let f = LittleCard.frame(in: visible)
        #expect(f.size == CGSize(width: 490, height: 329))
        #expect(f.minX == 1218)
        #expect(visible.maxY - f.maxY == 20)
        #expect(visible.maxX - f.maxX == 20)
    }

    /// On a second screen to the left, and below a menu bar: the card is on that screen's corner.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/337"))
    func cardFollowsTheScreen() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1055)
        let f = LittleCard.frame(in: left)
        #expect(f.maxX == -20)
        #expect(f.maxY == 1035)
    }

    /// Enter on a row: 1185 × 832 pt (Arc's size) with the card's top-right corner, x 523 to 1708.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/337"))
    func enterKeepsTheTopRightCorner() {
        let card = LittleCard.frame(in: visible)
        let f = LittleCard.expanded(from: card, to: CGSize(width: 1185, height: 832), in: visible)
        #expect(f.maxX == card.maxX)
        #expect(f.maxY == card.maxY)
        #expect(f.minX == 523)
        #expect(f.size == CGSize(width: 1185, height: 832))
    }

    /// A window too big for the screen keeps 20 pt clear on each side and stays on it, as a Little
    /// Window placed in the middle does.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/337"))
    func bigWindowsStayOnScreen() {
        let small = CGRect(x: 0, y: 0, width: 1280, height: 775)
        let card = LittleCard.frame(in: small)
        let f = LittleCard.expanded(from: card, to: CGSize(width: 1400, height: 900), in: small)
        #expect(f.size == CGSize(width: 1240, height: 735))
        #expect(f.maxX == card.maxX)
        #expect(f.maxY == card.maxY)
        #expect(small.contains(f))
        // A card dragged to the left edge: the window grows rightward rather than off the screen.
        let moved = card.offsetBy(dx: -card.minX, dy: 0)
        let g = LittleCard.expanded(from: moved, to: CGSize(width: 1000, height: 700), in: small)
        #expect(g.minX == 0)
        #expect(g.maxY == moved.maxY)
    }

    /// With nothing typed Cra's five rows fill the card (64 + 5 × 46 + 4 × 4 + 18 = 328 pt): the bar
    /// takes the card's lower corners. One typed row is a 128 pt bar with the window below it.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/337"))
    func barFillsTheCardUntilItShrinks() {
        let card = LittleCard.frame(in: visible)
        let full = LittleCard.barFrame(height: 328, in: card, inset: 1)
        #expect(full.fills)
        #expect(full.frame == card.insetBy(dx: 1, dy: 1))
        let one = LittleCard.barFrame(height: 128, in: card, inset: 1)
        #expect(!one.fills)
        #expect(one.frame.height == 128)
        #expect(one.frame.maxY == card.maxY - 1)
        #expect(one.frame.width == 488)
    }
}
