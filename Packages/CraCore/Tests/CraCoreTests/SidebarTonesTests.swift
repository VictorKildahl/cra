import CraCore
import Testing

/// GitHub #293: the sidebar's section titles, URL pill and favorite tiles in Arc 1.172.1's tones.
@Suite struct SidebarTonesTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/293")) func sectionTitlesAreDimmerThanSecondaryText() {
        #expect(SidebarTones.sectionTitle(dark: false) == .init(white: false, alpha: 0.46))
        #expect(SidebarTones.sectionTitle(dark: true) == .init(white: true, alpha: 0.45))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/293")) func pillAndTilesShareArcsHover() {
        #expect(SidebarTones.pill(dark: false) == .init(white: false, alpha: 0.045))
        #expect(SidebarTones.pill(dark: true) == .init(white: true, alpha: 0.095))
        // Hovered, the pill darkens on a light theme like a tile does; it no longer goes near-white.
        #expect(SidebarTones.pillHover(dark: false) == .init(white: false, alpha: 0.09))
        #expect(SidebarTones.pillHover(dark: true) == .init(white: true, alpha: 0.145))
    }
}
