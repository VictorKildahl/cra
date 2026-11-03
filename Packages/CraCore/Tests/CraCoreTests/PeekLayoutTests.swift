import CoreGraphics
import CraCore
import Testing

/// Arc's Peek as measured (docs/arc-reverse-engineering.md, "Peek and the copy toast's Share
/// button"): a 1728 × 1084 pt window, sidebar edge at 347, AX frames turned y-up.
struct PeekLayoutTests {
    static let window = CGSize(width: 1728, height: 1084)

    @Test func cardMatchesArc() {
        let card = PeekLayout.card(in: PeekLayout.area(window: Self.window, contentMinX: 347))
        // Arc: x 485…1590, 12 pt under the window's top, 12.5 above its bottom.
        #expect(card == CGRect(x: 485, y: 12, width: 1105, height: 1060))
    }

    @Test func buttonsMatchArc() {
        let card = PeekLayout.card(in: PeekLayout.area(window: Self.window, contentMinX: 347))
        let buttons = PeekLayout.buttons(beside: card)
        // Arc's tops, 19 / 63 / 106 pt under the window's top (y down).
        let topsFromWindowTop = buttons.map { Self.window.height - $0.maxY }
        #expect(buttons.allSatisfy { $0.minX == 1603 && $0.size == PeekLayout.buttonSize })
        #expect(zip(topsFromWindowTop, [19.0, 63, 106]).allSatisfy { abs($0 - $1) <= 0.5 })
        #expect(PeekLayout.column(beside: card) == CGRect(x: 1603, y: buttons[2].minY, width: 34, height: buttons[0].maxY - buttons[2].minY))
    }

    @Test func hiddenSidebarCentresOnTheWindow() {
        let card = PeekLayout.card(in: PeekLayout.area(window: Self.window, contentMinX: 0))
        #expect(card.midX == Self.window.width / 2)
        #expect(card.width == (Self.window.width * 0.8).rounded())
    }
}
