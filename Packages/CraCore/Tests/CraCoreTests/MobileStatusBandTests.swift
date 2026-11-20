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
        #expect(MobileStatusBand.shown(hasPage: true, searching: false, switching: false))
        #expect(!MobileStatusBand.shown(hasPage: false, searching: false, switching: false))
        #expect(!MobileStatusBand.shown(hasPage: true, searching: true, switching: false))
        #expect(!MobileStatusBand.shown(hasPage: true, searching: false, switching: true))
    }
}
