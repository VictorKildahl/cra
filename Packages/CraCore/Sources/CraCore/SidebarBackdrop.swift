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
    public static let solidActive = SidebarBackdrop(source: .blur, dim: 0.30, liftTop: 0.26, liftBottom: 0.26)
    public static let solidInactive = SidebarBackdrop(source: .none, dim: 1, liftTop: 0.83, liftBottom: 0.83)
    /// Solid themes with Reduce Transparency: Arc's flat grey under the space colour, active or not
    /// (GitHub #156: 160 in both of the reporter's solid spaces, windowed and fullscreen, and the
    /// same through a Space swipe, where the app is inactive until it lands).
    public static let solidReduced = SidebarBackdrop(source: .none, dim: 1, liftTop: 0.63, liftBottom: 0.63)

    public static func resolve(
        solid: Bool, active: Bool, fullscreen: Bool, reduceTransparency: Bool,
        tintAvailable: Bool, vibrant: Vibrant
    ) -> SidebarBackdrop {
        if solid {
            if reduceTransparency { return solidReduced }
            guard active else { return solidInactive }
            var b = solidActive
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
    public static func windowActive(appActive: Bool, miniaturized: Bool, holdsKeyOrMain: Bool) -> Bool {
        appActive && !miniaturized && holdsKeyOrMain
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
