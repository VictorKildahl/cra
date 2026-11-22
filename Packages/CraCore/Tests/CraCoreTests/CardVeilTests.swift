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

    /// Arc's empty card follows Arc's appearance: nearly white on Light whatever the theme, a faint +20 per
    /// channel on Dark, also over a light theme. Cra drew the light theme's white card on a dark Mac (#669).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/669"))
    func aWindowWithNoTabFollowsArcsAppearance() {
        let pastel = CardVeil.lightness(of: ["#FFCBD1"]), navy = CardVeil.lightness(of: ["#26456B"])
        #expect(CardVeil.noTabCard(light: true, groundLightness: pastel) == 0.65)
        #expect(CardVeil.noTabCard(light: true, groundLightness: navy) == 0.65)
        // On Dark a light theme's card is faint, not white: Arc's pastel card was its sidebar's colour + 18 to 19.
        let onPastel = CardVeil.noTabCard(light: false, groundLightness: pastel)
        #expect(onPastel < 0.5)
        #expect(abs(onPastel * (255 - 206) - 19) < 5, "about Arc's +19 over a pastel ground of 206")
        // A navy ground of 103 got + 22 in Arc.
        let onNavy = CardVeil.noTabCard(light: false, groundLightness: navy)
        #expect(abs(onNavy * (255 - 103) - 22) < 6)
        #expect(CardVeil.noTabCard(light: false, groundLightness: 0) == CardVeil.addedOnDark)
        #expect(CardVeil.noTabCard(light: false, groundLightness: 1) == CardVeil.maxOnDark)
    }
}
