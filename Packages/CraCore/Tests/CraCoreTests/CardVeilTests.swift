import CraCore
import Testing

/// The white veil over the space's colour on a card with no page in it, as Arc draws it.
struct CardVeilTests {
    /// A window with no tab shows a white card in Arc. Cra drew no card there at all.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/483"))
    func aWindowWithNoTabShowsAWhiteCard() {
        #expect(CardVeil.white(noTab: true, dark: false) == 0.65)
        #expect(CardVeil.white(noTab: true, dark: true) == 0.10)
    }

    /// An empty pane (a tab whose page isn't there) keeps its fainter veil.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/483"))
    func anEmptyPaneKeepsItsFaintVeil() {
        #expect(CardVeil.white(noTab: false, dark: false) == 0.2)
        #expect(CardVeil.white(noTab: false, dark: true) == 0.08)
    }
}
