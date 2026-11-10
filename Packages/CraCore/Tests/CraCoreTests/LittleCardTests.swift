import CoreGraphics
import CraCore
import Testing

/// Where Arc's compact Little Window sits and how it grows (#337). Numbers measured on Arc 1.172.1
/// (10 Nov 2026) on a 1728 × 1117 pt screen whose menu bar is 33 pt tall: y runs up here, so the
/// visible frame is (0, 0, 1728, 1084).
struct LittleCardTests {
    let visible = CGRect(x: 0, y: 0, width: 1728, height: 1084)

    /// Arc: x 1218, y 53 from the top (1117 - 735 - 329), 490 × 329.
    @Test func sitsAtTheTopRightTwentyPointsIn() {
        let card = LittleCard.frame(in: visible)
        #expect(card == CGRect(x: 1218, y: 735, width: 490, height: 329))
        #expect(visible.maxX - card.maxX == 20)
        #expect(visible.maxY - card.maxY == 20)
    }

    /// Arc: after Enter x 523 to 1708 and y 53, 1185 × 832: the corner did not move.
    @Test func growsWithItsTopRightCornerWhereItWas() {
        let card = LittleCard.frame(in: visible)
        let grown = LittleCard.grown(from: card, to: CGSize(width: 1185, height: 832), in: visible)
        #expect(grown == CGRect(x: 523, y: 232, width: 1185, height: 832))
        #expect(grown.maxX == card.maxX && grown.maxY == card.maxY)
    }

    @Test func staysOnTheScreenWhenTheWindowIsBigger() {
        let small = CGRect(x: 100, y: 50, width: 800, height: 500)
        let card = LittleCard.frame(in: small)
        let grown = LittleCard.grown(from: card, to: CGSize(width: 1400, height: 900), in: small)
        #expect(grown == CGRect(x: 120, y: 70, width: 760, height: 460))
        #expect(small.contains(grown))
    }

    /// A card on a screen that starts right of the origin (a second display) is placed from its own frame.
    @Test func followsItsScreen() {
        let second = CGRect(x: 1728, y: -200, width: 1920, height: 1055)
        let card = LittleCard.frame(in: second)
        #expect(card.maxX == second.maxX - 20 && card.maxY == second.maxY - 20)
    }
}
