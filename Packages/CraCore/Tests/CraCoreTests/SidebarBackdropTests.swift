import CraCore
import Testing

/// The sidebar's backdrop layer through activation, fullscreen and Reduce Transparency (GitHub #156).
struct SidebarBackdropTests {
    let vibrant = SidebarBackdrop.Vibrant(dim: 0.36, liftTop: 0.35, liftBottom: 0.37, dimInactive: 1, liftInactive: 0.28)

    func resolve(solid: Bool, active: Bool = true, fullscreen: Bool = false, reduce: Bool = false, tint: Bool = true) -> SidebarBackdrop {
        SidebarBackdrop.resolve(solid: solid, active: active, fullscreen: fullscreen, reduceTransparency: reduce, tintAvailable: tint, vibrant: vibrant)
    }

    /// An inactive window's solid sidebar keeps no capture under its flat fill, as AppKit's material
    /// doesn't, so no stale capture shows for a frame on activation (#132).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/132"))
    func solidThemesBlurWhileActiveAndGoFlatWhileInactive() {
        #expect(resolve(solid: true) == SidebarBackdrop(source: .blur, dim: 0.30, liftTop: 0.26, liftBottom: 0.26))
        #expect(resolve(solid: true, active: false) == SidebarBackdrop(source: .none, dim: 1, liftTop: 0.83, liftBottom: 0.83))
    }

    /// What a solid sidebar shows under its colour over a plain backdrop (0–255): the capture through the
    /// black dim, then the white lift.
    func material(_ b: SidebarBackdrop, over backdrop: Double) -> Double {
        backdrop * (1 - b.dim) * (1 - b.liftTop) + 255 * b.liftTop
    }

    /// A one-colour space on Light is drawn over Arc's light material, on Dark over its dark one, as Arc
    /// draws it under View ▸ Appearance ▸ Light or Dark (offline Arc, 17 Nov 2026, navy, red and pastel
    /// over white and black: light 166 + 0.315 · backdrop, dark 63 + 0.529 · backdrop, each within
    /// 1/255; inactive flat 252 and 207). Cra drew every space over the dark one, so Light and Dark looked the same and a Light
    /// space came out darker and less see-through than Arc's (#455).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/455"))
    func solidThemesOnLightUseArcsLightMaterial() {
        let light = SidebarBackdrop.resolve(solid: true, active: true, fullscreen: false, reduceTransparency: false,
                                            tintAvailable: true, vibrant: vibrant, lightMaterial: true)
        #expect(light.source == .blur)
        #expect(abs(material(light, over: 0) - 166) < 3)
        #expect(abs(material(light, over: 255) - (166 + 0.315 * 255)) < 3)
        let dark = resolve(solid: true)
        #expect(abs(material(dark, over: 0) - 63) < 4)
        #expect(abs(material(dark, over: 255) - (63 + 0.529 * 255)) < 4)
        // Inactive, both are flat: Arc's 252 on Light, 207–212 on Dark.
        let inactive = SidebarBackdrop.resolve(solid: true, active: false, fullscreen: false, reduceTransparency: false,
                                               tintAvailable: true, vibrant: vibrant, lightMaterial: true)
        #expect(inactive.source == .none && abs(material(inactive, over: 128) - 252) < 3)
        #expect(abs(material(resolve(solid: true, active: false), over: 128) - 210) < 4)
        // Only solid themes take the light material; light vibrant themes keep their own calibration.
        #expect(SidebarBackdrop.resolve(solid: false, active: true, fullscreen: false, reduceTransparency: false,
                                        tintAvailable: true, vibrant: vibrant, lightMaterial: true) == resolve(solid: false))
        // Full screen swaps the capture for the desktop tint on either material.
        #expect(SidebarBackdrop.resolve(solid: true, active: true, fullscreen: true, reduceTransparency: false,
                                        tintAvailable: true, vibrant: vibrant, lightMaterial: true).source == .desktopTint)
    }

    /// The material follows the space's Light or Dark, as Arc's follows its own appearance, and Auto
    /// follows macOS, as Arc on Automatic does (#455).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/455"))
    func materialFollowsTheSpacesAppearance() {
        let light = SpaceThemeVariants.theme(key: ["#26456B"], intensity: 0.8, noise: 0, appearance: "light")
        let dark = SpaceThemeVariants.theme(key: ["#26456B"], intensity: 0.8, noise: 0, appearance: "dark")
        let auto = SpaceThemeVariants.theme(key: ["#26456B"], intensity: 0.8, noise: 0, appearance: "auto")
        for systemDark in [false, true] {
            #expect(light.usesLightMaterial(systemDark: systemDark))
            #expect(!dark.usesLightMaterial(systemDark: systemDark))
            #expect(auto.usesLightMaterial(systemDark: systemDark) == !systemDark)
        }
        // A navy space on Light keeps white text: the material changes, not the colour's own reading.
        #expect(light.isDark && dark.isDark)
    }

    /// In full screen the desktop tint takes the capture's place, which reads black there (#83, #132).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/83"), .bug("https://github.com/VictorKildahl/cra/issues/132"))
    func fullscreenSwapsTheBlurForTheDesktopTint() {
        #expect(resolve(solid: true, fullscreen: true).source == .desktopTint)
        #expect(resolve(solid: false, fullscreen: true).source == .desktopTint)
        // Without CAChameleonLayer the blur stays.
        #expect(resolve(solid: true, fullscreen: true, tint: false).source == .blur)
        #expect(resolve(solid: true, active: false, fullscreen: true).source == .none)
    }

    /// Under Reduce transparency the sidebar is one flat fill, active or not, windowed or full screen,
    /// like Arc's (#156).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/156"))
    func reduceTransparencyNeverShowsACapture() {
        for solid in [true, false] {
            for active in [true, false] {
                for fullscreen in [true, false] {
                    let b = resolve(solid: solid, active: active, fullscreen: fullscreen, reduce: true)
                    #expect(b.source == .none)
                    #expect(b.dim == 1)
                }
            }
        }
        // Solid: Arc's opaque grey under the space colour, darker than the inactive fill, and the
        // same while inactive, so neither an activation nor a Space swipe steps.
        #expect(resolve(solid: true, reduce: true) == SidebarBackdrop.solidReduced)
        #expect(resolve(solid: true, active: false, fullscreen: true, reduce: true) == SidebarBackdrop.solidReduced)
        #expect(SidebarBackdrop.solidReduced.liftTop < SidebarBackdrop.solidInactive.liftTop)
        // Light vibrant: the inactive look, active or not.
        #expect(resolve(solid: false, reduce: true) == resolve(solid: false, active: false))
        #expect(resolve(solid: false, active: false, reduce: true) == resolve(solid: false, active: false))
    }

    /// Light vibrant themes keep their calibration through the backdrop changes (#83).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/83"))
    func lightVibrantThemesKeepTheirCalibration() {
        #expect(resolve(solid: false) == SidebarBackdrop(source: .blur, dim: 0.36, liftTop: 0.35, liftBottom: 0.37))
        #expect(resolve(solid: false, active: false) == SidebarBackdrop(source: .none, dim: 1, liftTop: 0.28, liftBottom: 0.28))
    }

    /// The hidden sidebar's panel drops its lift under Reduce transparency: Arc's darker panel (#156).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/156"))
    func floatingSidebarDropsItsLiftUnderReduceTransparency() {
        #expect(SidebarBackdrop.floatingLift(dark: false, reduceTransparency: false, lift: 0.35) == 0.35)
        #expect(SidebarBackdrop.floatingLift(dark: false, reduceTransparency: true, lift: 0.35) == 0)
        #expect(SidebarBackdrop.floatingLift(dark: true, reduceTransparency: false, lift: 0.35) == 0.15)
        #expect(SidebarBackdrop.floatingLift(dark: true, reduceTransparency: true, lift: 0.35) == 0.15)
    }

    /// AppKit's material follows its window, not the app (GitHub #156): a window restored from the Dock
    /// is miniaturized and holds neither key nor main for the whole genie, although the app is active.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/156"))
    func activeLookFollowsTheWindowLikeAppKit() {
        #expect(SidebarBackdrop.windowActive(appActive: true, miniaturized: false, holdsKeyOrMain: true))
        // Restore from the Dock: the app activates first, the window becomes main at the end.
        #expect(!SidebarBackdrop.windowActive(appActive: true, miniaturized: true, holdsKeyOrMain: false))
        // Minimized while the app stays active, or another window of the app in front.
        #expect(!SidebarBackdrop.windowActive(appActive: true, miniaturized: false, holdsKeyOrMain: false))
        // Another app in front: the window stays main but the app isn't active.
        #expect(!SidebarBackdrop.windowActive(appActive: false, miniaturized: false, holdsKeyOrMain: true))
    }

    /// A full screen window keeps AppKit's active appearance while its Space slides away (GitHub #156):
    /// the app resigns active and the window loses key and main, but the material stays active.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/156"))
    func fullScreenWindowKeepsAppKitsActiveAppearance() {
        #expect(SidebarBackdrop.windowActive(appActive: false, miniaturized: false, holdsKeyOrMain: false, activeAppearance: true))
        // A page window holding key: AppKit's answer for the parent may be off, Cra's rule still counts.
        #expect(SidebarBackdrop.windowActive(appActive: true, miniaturized: false, holdsKeyOrMain: true, activeAppearance: false))
        // Minimized wins.
        #expect(!SidebarBackdrop.windowActive(appActive: true, miniaturized: true, holdsKeyOrMain: true, activeAppearance: true))
        #expect(!SidebarBackdrop.windowActive(appActive: false, miniaturized: false, holdsKeyOrMain: false, activeAppearance: false))
    }

    /// cra.log names the backdrop's source, the window state and the dim on each change (#83, #132),
    /// and Reduce transparency (#156).
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/83"), .bug("https://github.com/VictorKildahl/cra/issues/132"), .bug("https://github.com/VictorKildahl/cra/issues/156"))
    func logLineNamesTheState() {
        #expect(resolve(solid: true).logLine(active: true, reduceTransparency: false) == "blur, active, dim 0.30")
        #expect(resolve(solid: true, fullscreen: true).logLine(active: true, reduceTransparency: false) == "desktop tint, active, dim 0.30")
        #expect(resolve(solid: true, active: false).logLine(active: false, reduceTransparency: false) == "flat, inactive, dim 1.00")
        #expect(resolve(solid: true, reduce: true).logLine(active: true, reduceTransparency: true) == "flat, active, dim 1.00, reduce transparency")
    }
}
