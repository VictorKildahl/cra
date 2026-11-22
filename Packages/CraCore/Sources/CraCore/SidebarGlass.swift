import Foundation

/// Settings ▸ Tabs ▸ "Translucent sidebar" (not in Arc, Ideas #366): the sidebar, and the window's
/// ground around the pages, become a thin glass over what is behind the window, and the floating
/// sidebar a glass over the page it covers.
///
/// Arc draws a preset or imported theme opaque and a one-colour theme at `SpaceTheme.solidAlpha` over
/// its grey material, which passes about half of the desktop. The glass keeps the space's colours
/// but thinner, for every kind of theme, over a darker blur on a dark theme (a paler one on a light
/// theme), so the desktop shows through without the grey cast. It stays glass while the window is
/// inactive, because that's when the person asked for it to show what is behind, and goes flat only
/// with Reduce transparency, as every macOS material does.
public enum SidebarGlass {
    /// The space colours' opacity over the glass: Arc's one-colour curve (SpaceTheme.solidAlpha) at
    /// 60 %, so a theme's intensity still reads as thicker or thinner glass: 0.11 to 0.44, and 0.37
    /// to 0.41 for the presets.
    public static func alpha(intensity: Double) -> Double { 0.6 * SpaceTheme.solidAlpha(intensity: intensity) }

    /// Under a dark theme: the blur behind dimmed 68 % toward black, a touch of lift. A preset like
    /// Phantom then reads about 55/255 over a white window and 10/255 over black: dark over anything,
    /// with the colours behind still showing (half dimmed, an earlier try, was mid-grey over white).
    public static let dark = SidebarBackdrop(source: .blur, dim: 0.68, liftTop: 0.02, liftBottom: 0.02)
    /// Under a light theme: the blur behind lifted 60 % toward white, barely dimmed.
    public static let light = SidebarBackdrop(source: .blur, dim: 0.04, liftTop: 0.6, liftBottom: 0.6)
    /// Reduce transparency: one flat fill, dark grey or near-white, under the space colour.
    public static let darkReduced = SidebarBackdrop(source: .none, dim: 1, liftTop: 0.12, liftBottom: 0.12)
    public static let lightReduced = SidebarBackdrop(source: .none, dim: 1, liftTop: 0.9, liftBottom: 0.9)

    /// What the docked sidebar's backdrop layer draws (ShellView). In full screen nothing is behind
    /// the window, so the desktop tint stands in for the capture, as in SidebarBackdrop.resolve.
    public static func backdrop(dark isDark: Bool, fullscreen: Bool, reduceTransparency: Bool,
                                tintAvailable: Bool) -> SidebarBackdrop {
        if reduceTransparency { return isDark ? darkReduced : lightReduced }
        var b = isDark ? dark : light
        if fullscreen && tintAvailable { b.source = .desktopTint }
        return b
    }

    /// The white lift over the floating sidebar's blur (an NSVisualEffectView over the page). Arc's
    /// floating panel lifts a dark theme by 0.15, which greys the page under it; the glass doesn't.
    /// Reduce transparency makes the material opaque, so the lift is what Arc's would be.
    public static func floatingLift(dark: Bool, reduceTransparency: Bool, lift: Double) -> Double {
        if reduceTransparency { return SidebarBackdrop.floatingLift(dark: dark, reduceTransparency: true, lift: lift) }
        return dark ? 0 : lift
    }

    /// The grey the space colours are judged over for the palette's opaque tones (folder fills):
    /// about what the glass shows over a typical desktop.
    public static func ground(dark: Bool) -> Double { dark ? 0.1 : 0.8 }
}
