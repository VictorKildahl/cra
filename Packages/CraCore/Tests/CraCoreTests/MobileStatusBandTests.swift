import CraCore
import Testing

/// The band behind the status bar over a page (#657).
struct MobileStatusBandTests {
    /// The page's theme-color, else its own background; the status bar's text reads on it; it is there
    /// only over a page shown full size.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/657"))
    func theBandTakesThePagesColour() {
        #expect(MobileStatusBand.fill(themeColor: "#7F6BAB", underPage: "#FFFFFF") == "#7F6BAB")
        #expect(MobileStatusBand.fill(themeColor: nil, underPage: "#1C1C1E") == "#1C1C1E")
        #expect(MobileStatusBand.fill(themeColor: nil, underPage: nil) == nil)
        #expect(MobileStatusBand.lightContent(fill: "#1C1C1E"))
        #expect(MobileStatusBand.lightContent(fill: "#5B3E96"))
        #expect(!MobileStatusBand.lightContent(fill: "#FFFFFF"))
        #expect(!MobileStatusBand.lightContent(fill: "#F8D558"))
        #expect(MobileStatusBand.shown(hasPage: true, switching: false))
        #expect(!MobileStatusBand.shown(hasPage: false, switching: false))
        #expect(!MobileStatusBand.shown(hasPage: true, switching: true))
    }

    /// A tab's band in the row or a swipe: its page's colour once it has loaded, its picture's
    /// top before then, and whichever there is when the other is missing.
    @Test func aTabsBandComesFromItsPageOnceLoaded() {
        #expect(MobileStatusBand.tabFill(pageFill: "#7F6BAB", pictureTop: "#FFFFFF", loaded: true) == "#7F6BAB")
        #expect(MobileStatusBand.tabFill(pageFill: "#000000", pictureTop: "#7F6BAB", loaded: false) == "#7F6BAB")
        #expect(MobileStatusBand.tabFill(pageFill: nil, pictureTop: "#7F6BAB", loaded: true) == "#7F6BAB")
        #expect(MobileStatusBand.tabFill(pageFill: "#7F6BAB", pictureTop: nil, loaded: false) == "#7F6BAB")
        #expect(MobileStatusBand.tabFill(pageFill: nil, pictureTop: nil, loaded: false) == nil)
    }

    /// No band over a new page from the search sheet while it draws under its cover: it took WebKit's
    /// white before the page had a colour, a white strip under the Dynamic Island as the screen went black.
    @Test func noBandOverAPageStillDrawingUnderItsCover() {
        #expect(!MobileStatusBand.shown(hasPage: true, switching: false, covered: true))
        #expect(MobileStatusBand.shown(hasPage: true, switching: false, covered: false))
    }
}
