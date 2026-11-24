import Foundation
import Testing
@testable import CraCore

/// Ideas #366: the now-playing cards can take the sidebar's colour instead of Arc's near-white/black.
@Suite struct NowPlayingTintTests {
    /// Arc's by default, an older settings.json without the key loads Arc's, and it's not reported.
    @Test func arcByDefault() throws {
        #expect(AppSettings().nowPlayingTint == .arc)
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(s.nowPlayingTint == .arc)
        #expect(UsageStats.unreportedSettings.contains("nowPlayingTint"))
    }

    /// Saved and read back; a value from a newer Cra loads Arc's instead of failing the file.
    @Test func savedAndReadBack() throws {
        var s = AppSettings()
        s.nowPlayingTint = .theme
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        #expect(back.nowPlayingTint == .theme)
        let unknown = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"nowPlayingTint":"rainbow","translucentSidebar":true}"#.utf8))
        #expect(unknown.nowPlayingTint == .arc)
        #expect(unknown.translucentSidebar)
    }

    /// The theme fill is the sidebar's colour under a selected tab's white: it keeps the space's hue,
    /// lighter on a light space and only a little lighter on a dark one.
    @Test func themeFillIsASelectedTabOverTheSidebar() {
        let lilac = (r: 0.80, g: 0.70, b: 0.95)
        let light = NowPlayingTint.themeFill(ground: lilac, dark: false)
        #expect(abs(light.r - (0.80 * 0.26 + 0.74)) < 1e-9)
        #expect(abs(light.b - (0.95 * 0.26 + 0.74)) < 1e-9)
        #expect(light.b > light.r && light.r > light.g)   // still lilac

        let navy = (r: 0.10, g: 0.12, b: 0.30)
        let dark = NowPlayingTint.themeFill(ground: navy, dark: true)
        #expect(abs(dark.b - (0.30 * 0.87 + 0.13)) < 1e-9)
        #expect(dark.b > dark.g && dark.g > dark.r)        // still navy
        #expect(dark.r < 0.3)                              // still a dark card

        let clamped = NowPlayingTint.themeFill(ground: (r: 1.4, g: -0.2, b: 0.5), dark: true)
        #expect(clamped.r == 1 && abs(clamped.g - 0.13) < 1e-9)
    }
}
