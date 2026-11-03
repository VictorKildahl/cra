import CraCore
import Testing

/// The sidebar's backdrop layer through activation, fullscreen and Reduce Transparency (GitHub #156).
struct SidebarBackdropTests {
    let vibrant = SidebarBackdrop.Vibrant(dim: 0.36, liftTop: 0.35, liftBottom: 0.37, dimInactive: 1, liftInactive: 0.28)

    func resolve(solid: Bool, active: Bool = true, fullscreen: Bool = false, reduce: Bool = false, tint: Bool = true) -> SidebarBackdrop {
        SidebarBackdrop.resolve(solid: solid, active: active, fullscreen: fullscreen, reduceTransparency: reduce, tintAvailable: tint, vibrant: vibrant)
    }

    @Test func solidThemesBlurWhileActiveAndGoFlatWhileInactive() {
        #expect(resolve(solid: true) == SidebarBackdrop(source: .blur, dim: 0.30, liftTop: 0.26, liftBottom: 0.26))
        #expect(resolve(solid: true, active: false) == SidebarBackdrop(source: .none, dim: 1, liftTop: 0.83, liftBottom: 0.83))
    }

    @Test func fullscreenSwapsTheBlurForTheDesktopTint() {
        #expect(resolve(solid: true, fullscreen: true).source == .desktopTint)
        #expect(resolve(solid: false, fullscreen: true).source == .desktopTint)
        // Without CAChameleonLayer the blur stays.
        #expect(resolve(solid: true, fullscreen: true, tint: false).source == .blur)
        #expect(resolve(solid: true, active: false, fullscreen: true).source == .none)
    }

    @Test func reduceTransparencyNeverShowsACapture() {
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

    @Test func lightVibrantThemesKeepTheirCalibration() {
        #expect(resolve(solid: false) == SidebarBackdrop(source: .blur, dim: 0.36, liftTop: 0.35, liftBottom: 0.37))
        #expect(resolve(solid: false, active: false) == SidebarBackdrop(source: .none, dim: 1, liftTop: 0.28, liftBottom: 0.28))
    }

    @Test func logLineNamesTheState() {
        #expect(resolve(solid: true).logLine(active: true, reduceTransparency: false) == "blur, active, dim 0.30")
        #expect(resolve(solid: true, fullscreen: true).logLine(active: true, reduceTransparency: false) == "desktop tint, active, dim 0.30")
        #expect(resolve(solid: true, active: false).logLine(active: false, reduceTransparency: false) == "flat, inactive, dim 1.00")
        #expect(resolve(solid: true, reduce: true).logLine(active: true, reduceTransparency: true) == "flat, active, dim 1.00, reduce transparency")
    }
}
