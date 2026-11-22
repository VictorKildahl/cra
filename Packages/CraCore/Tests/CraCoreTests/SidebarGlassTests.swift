import CraCore
import Foundation
import Testing

/// Settings ▸ Tabs ▸ "Translucent sidebar" (Ideas #366): a thin glass over what is behind the window.
struct SidebarGlassTests {
    /// Every theme turns to glass, thinner than Arc's one-colour opacity, and intensity still counts.
    @Test func theSpaceColoursAreThinnerThanArcsAndFollowIntensity() {
        for intensity in stride(from: 0.0, through: 1.0, by: 0.25) {
            #expect(SidebarGlass.alpha(intensity: intensity) < SpaceTheme.solidAlpha(intensity: intensity))
        }
        #expect(SidebarGlass.alpha(intensity: 0) < SidebarGlass.alpha(intensity: 1))
        // A preset (intensity 0.75 to 0.9), drawn opaque without the setting, lets most of the backdrop through.
        for preset in SpaceTheme.presets {
            #expect(SidebarGlass.alpha(intensity: preset.intensity) < 0.45)
        }
        // Clamped like Arc's curve.
        #expect(SidebarGlass.alpha(intensity: 3) == SidebarGlass.alpha(intensity: 1))
    }

    /// The reference in #366 is a near-black sidebar with the desktop showing through: a dark theme
    /// dims the blur toward black instead of Arc's grey lift; a light one goes pale instead.
    @Test func aDarkThemeIsDarkGlassAndALightOnePale() {
        let dark = SidebarGlass.backdrop(dark: true, fullscreen: false, reduceTransparency: false, tintAvailable: true)
        #expect(dark.source == .blur)
        #expect(dark.dim > SidebarBackdrop.solidActive.dim)
        #expect(dark.liftTop < SidebarBackdrop.solidActive.liftTop)
        let light = SidebarGlass.backdrop(dark: false, fullscreen: false, reduceTransparency: false, tintAvailable: true)
        #expect(light.source == .blur)
        #expect(light.liftTop > dark.liftTop)
        #expect(light.dim < dark.dim)
    }

    /// Full screen has nothing behind the window to blur: the desktop tint stands in, as for Arc's material.
    @Test func fullScreenUsesTheDesktopTint() {
        #expect(SidebarGlass.backdrop(dark: true, fullscreen: true, reduceTransparency: false, tintAvailable: true).source == .desktopTint)
        #expect(SidebarGlass.backdrop(dark: true, fullscreen: true, reduceTransparency: false, tintAvailable: false).source == .blur)
    }

    /// Reduce transparency wins over the setting, as over every macOS material: one flat fill.
    @Test func reduceTransparencyIsFlat() {
        for dark in [false, true] {
            let b = SidebarGlass.backdrop(dark: dark, fullscreen: false, reduceTransparency: true, tintAvailable: true)
            #expect(b.source == .none)
            #expect(b.dim == 1)
        }
    }

    /// The floating sidebar over a page: no grey lift on a dark theme, so the page shows through darkened.
    @Test func theFloatingSidebarDropsTheGreyLift() {
        #expect(SidebarGlass.floatingLift(dark: true, reduceTransparency: false, lift: 0.2) == 0)
        #expect(SidebarBackdrop.floatingLift(dark: true, reduceTransparency: false, lift: 0.2) > 0)
        #expect(SidebarGlass.floatingLift(dark: false, reduceTransparency: false, lift: 0.2) == 0.2)
        #expect(SidebarGlass.floatingLift(dark: true, reduceTransparency: true, lift: 0.2)
                == SidebarBackdrop.floatingLift(dark: true, reduceTransparency: true, lift: 0.2))
    }

    /// Off by default, and an older settings.json without the key loads it off.
    @Test func offByDefault() throws {
        #expect(!AppSettings().translucentSidebar)
        let s = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        #expect(!s.translucentSidebar)
        #expect(UsageStats.unreportedSettings.contains("translucentSidebar"))
    }
}
