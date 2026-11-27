import CraCore
import Testing

/// The toolbar-hidden sidebar header at Arc's narrower widths (issue #287), against Arc's
/// AX frames (offsets from the sidebar's left edge).
struct SidebarHeaderLayoutTests {
    /// 220 pt: ← → ↻ at 114, 148, 182 (32 pt, 2 pt apart, 6 pt from the edge); the toggle
    /// keeps its place after the traffic lights.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func regularDownTo214() {
        #expect(!SidebarHeaderLayout.isNarrow(width: 220))
        #expect(SidebarHeaderLayout.navButtons(width: 220).map(\.x) == [114, 148, 182])
        #expect(SidebarHeaderLayout.navButtons(width: 220).map(\.size) == [32, 32, 32])
        #expect(SidebarHeaderLayout.toggleX(width: 220, afterLights: 77) == 77)
        // 214 pt: still regular, ← at 108 and the toggle moved left to 74 (Arc).
        #expect(!SidebarHeaderLayout.isNarrow(width: 214))
        #expect(SidebarHeaderLayout.navButtons(width: 214).map(\.x) == [108, 142, 176])
        #expect(SidebarHeaderLayout.toggleX(width: 214, afterLights: 77) == 74)
    }

    /// The switch, each width opened on its own: 213 and 212 regular (toggle at 73 and 72),
    /// 211 narrow (← → ••• at 121/149/177). Developer Mode pages: toggle at 71 beside ← at 105.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func switchesBetween212And211() {
        #expect(!SidebarHeaderLayout.isNarrow(width: 212))
        #expect(SidebarHeaderLayout.isNarrow(width: 211))
        #expect(SidebarHeaderLayout.toggleX(width: 213, afterLights: 77) == 73)
        #expect(SidebarHeaderLayout.toggleX(width: 212, afterLights: 77) == 72)
        #expect(SidebarHeaderLayout.navButtons(width: 211).map(\.x) == [121, 149, 177])
        #expect(SidebarHeaderLayout.toggleX(width: 212, afterLights: 77, developer: true) == 71)
        #expect(SidebarHeaderLayout.toggleX(width: 260, afterLights: 77, developer: true) == 77)
    }

    /// 208 pt and down to Arc's 164 pt minimum: ← → ••• as touching 28 pt boxes, 6 pt from
    /// the edge (Arc: 118/146/174 at 208, 74/102/130 at 164), where Cra's 32 pt row would have
    /// run over the traffic lights and the toggle.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func narrowAt208AndDown() {
        #expect(SidebarHeaderLayout.isNarrow(width: 208))
        #expect(SidebarHeaderLayout.navButtons(width: 208).map(\.x) == [118, 146, 174])
        #expect(SidebarHeaderLayout.navButtons(width: 164).map(\.x) == [74, 102, 130])
        #expect(SidebarHeaderLayout.navButtons(width: 164).map(\.size) == [28, 28, 28])
    }

    /// The ••• popover's tones from Arc's "Lab" theme (shadedDark 0.437, 0.336, −0.080):
    /// fill (17, 13, 0) and hovered row (81, 70, 26), within a channel step.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/287"))
    func moreMenuTones() {
        let ink = RGB(0.437, 0.336, -0.080)
        func bytes(_ c: RGB) -> [Double] { [c.r, c.g, c.b].map { ($0 * 255).rounded() } }
        let fill = bytes(SidebarMoreMenu.fill(shadedDark: ink)), hi = bytes(SidebarMoreMenu.highlight(shadedDark: ink))
        for (got, want) in zip(fill + hi, [17, 13, 0, 81, 70, 26] as [Double]) { #expect(abs(got - want) <= 2) }
        #expect(SidebarMoreMenu.height(rows: 2) == 96)
    }

    /// #822: the ••• menu is Arc's ArcMenu, the + menu's, whose dark tones it measured ((17,13,0) and (81,70,26) on the
    /// gold space, (5,6,39) and (47,51,145) on JYSK, both the + menu's). In Light mode it takes the space's light palette
    /// with black titles, as the + menu does (Arc 1.174.2, 26 Nov 2026); in Dark mode it keeps what was measured.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/822"))
    func moreMenuFollowsTheMacsAppearance() {
        let gold = SpaceTheme(colors: ["#E9B300"], intensity: 0.5, noise: 0, appearance: "light")
        let light = SidebarMoreMenu.tones(theme: gold, dark: false)
        #expect(light == ArcMenuTones(theme: gold, dark: false))
        #expect(min(light.fill.r, light.fill.g, light.fill.b) > 0.9, "light fill: \(light.fill)")
        #expect(light.ink == .black)
        let dark = SidebarMoreMenu.tones(theme: gold, dark: true)
        #expect(dark.fill == SidebarMoreMenu.fill(shadedDark: gold.shadedDark))
        #expect(dark.hover == SidebarMoreMenu.highlight(shadedDark: gold.shadedDark))
        #expect(dark.ink == .white && dark.disabled == ArcMenuTones.disabledInk)
    }
}
