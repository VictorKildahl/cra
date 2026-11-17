import CraCore
import Testing

/// The browser window's traffic lights keep the system's spacing (issue #445).
struct TrafficLightLayoutTests {
    /// macOS 15 lays the buttons out 20 pt apart (14 pt wide, 6 pt gaps); they move to x 13 and
    /// stay 20 pt apart, not Cra's old 24.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/445"))
    func sequoiaKeepsItsSpacing() {
        #expect(TrafficLightLayout.originsX(system: [7, 27, 47]) == [13, 33, 53])
    }

    /// macOS 26 lays them out 23 pt apart (AppKit at 9/32/55 in this window style); Arc's lights
    /// sit at 13/36/59 (AX 12/35/58, 1 pt outset).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/445"))
    func tahoeMatchesArc() {
        #expect(TrafficLightLayout.originsX(system: [9, 32, 55]) == [13, 36, 59])
    }

    /// Already in place (each layout pass runs this again): nothing moves.
    @Test func alreadyPlacedStaysPut() {
        #expect(TrafficLightLayout.originsX(system: [13, 33, 53]) == [13, 33, 53])
        #expect(TrafficLightLayout.originsX(system: []) == [])
    }
}
