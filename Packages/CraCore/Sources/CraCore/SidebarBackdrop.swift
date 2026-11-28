import Foundation

/// What the sidebar's backdrop layer draws for light vibrant and solid themes (ShellView's
/// CABackdropLayer path): which capture is in the tree, and the black dim and white lift over it.
///
/// AppKit's material, and with it Arc's sidebar, keeps only the layer it draws from in the tree:
/// no capture under an opaque fill, the desktop tint instead of the blur in fullscreen, and no
/// capture at all with Reduce Transparency, where every material is one opaque fill (GitHub #156).
public struct SidebarBackdrop: Equatable, Sendable {
    public enum Source: String, Sendable {
        case none = "flat"
        case blur
        case desktopTint = "desktop tint"
    }

    /// The light vibrant themes' calibration (CraTuning: blurDim, liftActive, …).
    public struct Vibrant: Equatable, Sendable {
        public var dim: Double
        public var liftTop: Double
        public var liftBottom: Double
        public var dimInactive: Double
        public var liftInactive: Double

        public init(dim: Double, liftTop: Double, liftBottom: Double, dimInactive: Double, liftInactive: Double) {
            self.dim = dim
            self.liftTop = liftTop
            self.liftBottom = liftBottom
            self.dimInactive = dimInactive
            self.liftInactive = liftInactive
        }
    }

    public var source: Source
    public var dim: Double
    public var liftTop: Double
    public var liftBottom: Double

    public init(source: Source, dim: Double, liftTop: Double, liftBottom: Double) {
        self.source = source
        self.dim = dim
        self.liftTop = liftTop
        self.liftBottom = liftBottom
    }

    /// Solid themes: Arc's material is grey 66 passing 52 % of the backdrop, flat 212 while inactive.
    /// That is its dark material, the one under View ▸ Appearance ▸ Dark (re-fitted 17 Nov 2026: 63 +
    /// 0.529 · backdrop), and Cra's for a space on Dark, with macOS on Light. On macOS Dark a one-colour space
    /// takes `solidActiveDarkOneColour` instead (#876).
    public static let solidActive = SidebarBackdrop(source: .blur, dim: 0.30, liftTop: 0.26, liftBottom: 0.26)
    /// Arc's light material, under View ▸ Appearance ▸ Light: grey 166 passing 31.5 % of the backdrop
    /// (offline Arc 1.172, 17 Nov 2026, navy, red and pastel over white and black, within 1/255), for a
    /// space on Light (#455).
    public static let solidActiveLight = SidebarBackdrop(source: .blur, dim: 0.10, liftTop: 0.65, liftBottom: 0.65)
    /// Arc's material under a gradient whose colours read dark (its editor saves those with `translucencyStyle`
    /// dark, Brand9's pair among its presets), under Dark: grey 40 passing 35 % of the backdrop, darker than a
    /// light gradient's or one colour's 63 + 0.529 · backdrop (Arc 1.174 on a fake home, 20 Nov 2026, #666789 /
    /// #7F6589 at 0.8: 112/112/134 over white, 79/78/100 over black at the top, every channel within 2/255 of
    /// solidAlpha(0.8) of the colour over it; #643).
    public static let solidActiveDarkGradient = SidebarBackdrop(source: .blur, dim: 0.585, liftTop: 0.157, liftBottom: 0.157)
    /// Arc's material under a one-colour space while macOS shows Dark: grey 35 passing 35 % of the backdrop, a little
    /// darker than the dark gradient's (Arc 1.174 on a fake home, 28 Nov 2026, View ▸ Appearance on Automatic, a white
    /// or black window behind: black at full intensity 9 over black and 32 over white, at 0.5 18 and 68, navy #26456B at
    /// full 42/60/86 and 66/83/110; #876). Cra had macOS Light's 63 + 0.529 · backdrop there: 19 and 51 for that black.
    public static let solidActiveDarkOneColour = SidebarBackdrop(source: .blur, dim: 0.5955, liftTop: 0.137, liftBottom: 0.137)
    /// Its inactive look, flat 252 (Light) where the dark one is 212 (same run: 252 over navy, red and
    /// pastel, 207 under Dark).
    public static let solidInactiveLight = SidebarBackdrop(source: .none, dim: 1, liftTop: 0.99, liftBottom: 0.99)
    public static let solidInactive = SidebarBackdrop(source: .none, dim: 1, liftTop: 0.83, liftBottom: 0.83)
    /// The inactive look on macOS Dark (#876). Arc 1.174.3 offline, 27 Nov 2026, macOS 26.7 on Dark, View ▸ Appearance
    /// on Automatic and on Dark alike, another app in front: a one-colour space sits on a flat 25 (navy #26456B at 0.8
    /// read 33/53/77, with dark or light content alike), so it goes darker when the window loses focus, not lighter.
    public static let solidInactiveDark = SidebarBackdrop(source: .none, dim: 1, liftTop: 0.10, liftBottom: 0.10)
    /// The same for a gradient whose colours read dark: a flat 27.5 (#666789 / #7F6589 read 75/75/96 at 0.8 and 54/54/67
    /// at 0.3). A light gradient stays on about 210 there (#6CBAD9 / #7F7EDC: 146/193/215), as `solidInactive`.
    public static let solidInactiveDarkGradient = SidebarBackdrop(source: .none, dim: 1, liftTop: 0.108, liftBottom: 0.108)
    /// Solid themes with Reduce Transparency: Arc's flat grey under the space colour, active or not
    /// (GitHub #156: 160 in both of the reporter's solid spaces, windowed and fullscreen, and the
    /// same through a Space swipe, where the app is inactive until it lands).
    public static let solidReduced = SidebarBackdrop(source: .none, dim: 1, liftTop: 0.63, liftBottom: 0.63)

    public static func resolve(
        solid: Bool, active: Bool, fullscreen: Bool, reduceTransparency: Bool,
        tintAvailable: Bool, vibrant: Vibrant, lightMaterial: Bool = false, darkGradient: Bool = false,
        oneColour: Bool = false, macOSDark: Bool = false
    ) -> SidebarBackdrop {
        if solid {
            if reduceTransparency { return solidReduced }
            // On macOS Light, Arc's inactive fills are the 252 and 207 measured on 17 Nov; on macOS Dark a one-colour
            // space and a dark gradient go to a dark grey instead, whatever Arc's own appearance says (#876).
            guard active else {
                if lightMaterial { return solidInactiveLight }
                if macOSDark && darkGradient { return solidInactiveDarkGradient }
                return macOSDark && oneColour ? solidInactiveDark : solidInactive
            }
            // On macOS Dark a one-colour space is drawn over a darker material (Arc 1.174, 28 Nov 2026, #876); the
            // 63 + 0.529 · backdrop one is macOS Light's.
            var b = lightMaterial ? solidActiveLight : darkGradient ? solidActiveDarkGradient
                : macOSDark && oneColour ? solidActiveDarkOneColour : solidActive
            if fullscreen && tintAvailable { b.source = .desktopTint }
            return b
        }
        // Reduce Transparency turns the material into its inactive look, without a capture.
        let full = active && !reduceTransparency
        let dim = reduceTransparency ? 1 : active ? vibrant.dim : vibrant.dimInactive
        return SidebarBackdrop(
            source: dim >= 1 ? .none : fullscreen && tintAvailable ? .desktopTint : .blur, dim: dim,
            liftTop: full ? vibrant.liftTop : vibrant.liftInactive,
            liftBottom: full ? vibrant.liftBottom : vibrant.liftInactive)
    }

    /// Whether a window's sidebar draws its active look. It is AppKit's `followsWindowActiveState`, and so
    /// Arc's sidebar: the app is active and the window holds key or main. Cra's page windows are children of
    /// the window and take key while a page has focus, so they count as the window. Measured on
    /// NSVisualEffectView (GitHub #156): minimizing goes inactive at once, while the app is still active,
    /// and a restore from the Dock keeps the flat fill through the genie until the window is main again,
    /// about 0.4 s after the app became active. Following the app instead asked for a live capture of a
    /// window still flying out of the Dock, which showed matte or sharp frames as it landed.
    ///
    /// `activeAppearance` is AppKit's own answer for the window, read from a material that follows it. A full
    /// screen window keeps its active appearance while its Space slides away and the app resigns active, so
    /// Arc's sidebar keeps the desktop tint through a ⌃← / ⌃→ round trip (probe, 5 Nov 2026). Cra's own rule
    /// dropped to the flat fill there and stepped back about 5 frames after the slide had landed. The rule
    /// above still counts on its own, because AppKit's answer doesn't know about Cra's child page windows.
    public static func windowActive(
        appActive: Bool, miniaturized: Bool, holdsKeyOrMain: Bool, activeAppearance: Bool = false
    ) -> Bool {
        !miniaturized && (appActive && holdsKeyOrMain || activeAppearance)
    }

    /// The white lift over the floating sidebar's material (dark hudWindow), light themes. Under
    /// Reduce transparency that material is its opaque dark fill, 38, which is Arc's floating panel
    /// under the space colour (GitHub #156: 156/64/72 at #F25E6B 0.8), so the lift goes.
    public static func floatingLift(dark: Bool, reduceTransparency: Bool, lift: Double) -> Double {
        dark ? 0.15 : reduceTransparency ? 0 : lift
    }

    /// One cra.log line per change, so a report of a sharp or off-colour sidebar can be matched to
    /// the window's state.
    public func logLine(active: Bool, reduceTransparency: Bool) -> String {
        var s = "\(source.rawValue), \(active ? "active" : "inactive"), dim \(String(format: "%.2f", dim))"
        if reduceTransparency { s += ", reduce transparency" }
        return s
    }
}
