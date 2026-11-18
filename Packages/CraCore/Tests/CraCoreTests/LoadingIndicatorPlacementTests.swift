import CoreGraphics
import CraCore
import Testing

/// The loading bar stays at the window's top middle when the card fills the window, as in Arc
/// (Arc 1.172.2, 18 Nov 2026, #548).
struct LoadingIndicatorPlacementTests {
    let window = CGRect(x: 0, y: 0, width: 1728, height: 1084)

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/548"))
    func barSitsInTheMarginAboveACardInItsInset() {
        // Sidebar shown, 10 pt inset: the bar is centred over the card in the margin, 3–7 pt down.
        let card = CGRect(x: 240, y: 10, width: 1478, height: 1064)
        let f = LoadingIndicator.frame(window: window, card: card)
        #expect(f == CGRect(x: 913, y: 1074, width: 132, height: 10))
        #expect(f.midX.rounded() == card.midX.rounded())
        #expect(!LoadingIndicator.overCard(window: window, card: card))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/548"))
    func barStaysAtTheTopOverACardThatFillsTheWindow() {
        // Full screen with the sidebar hidden, or edge to edge: same rows, over the card's top.
        let f = LoadingIndicator.frame(window: window, card: window)
        #expect(f == CGRect(x: 798, y: 1074, width: 132, height: 10))
        #expect(LoadingIndicator.overCard(window: window, card: window))
        // Edge to edge beside the sidebar: centred over the card, not the window.
        let beside = CGRect(x: 240, y: 0, width: 1488, height: 1084)
        #expect(LoadingIndicator.frame(window: window, card: beside).midX == beside.midX)
        #expect(LoadingIndicator.overCard(window: window, card: beside))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/548"))
    func inkFollowsWhatIsUnderTheBar() {
        func light(_ g: LoadingIndicator.Ground, theme: Bool = false, canvas: Bool = false) -> Bool {
            LoadingIndicator.lightInk(on: g, themeDark: theme, canvasDark: canvas)
        }
        // The margin is the theme's.
        #expect(light(.margin, theme: true))
        #expect(!light(.margin, theme: false))
        // A toolbar: dark bars take white, light ones and Arc's white bar black, whatever the theme.
        #expect(light(.toolbar("#3D45C9"), theme: false))
        #expect(!light(.toolbar("#FFFFFF"), theme: true))
        #expect(!light(.toolbar(nil), theme: true))
        #expect(light(.developerBar))
        // The page: its colour, else the canvas the appearance gives it.
        #expect(!light(.page("#FFFFFF"), theme: true))
        #expect(light(.page("#121212")))
        #expect(light(.page(nil), canvas: true))
        #expect(!light(.page(nil), theme: true, canvas: false))
    }
}
