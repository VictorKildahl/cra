import Foundation

/// Whether the page card fills the window: no margin around it, square corners, no shadow.
///
/// Arc keeps the card in its 10 pt inset in a window. In full screen it keeps the inset while the
/// sidebar is shown, and drops it once the sidebar is hidden: the card then fills the screen edge to
/// edge, with the floating sidebar over it when it comes out. Measured on an offline Arc 1.172.1 at
/// 1x, full screen on a 1920 × 1080 display (10 Nov 2026, issue #315): sidebar shown, card at
/// x 228–1910, y 10–1070; View ▸ Hide Sidebar, card at 0–1920 × 0–1080, square.
public enum CardFill {
    /// - Parameters:
    ///   - edgeToEdge: Settings ▸ "Pages fill the window edge to edge" (#24), which fills it always.
    ///   - fullScreen: the window is in macOS full screen (not a page's element full screen).
    ///   - sidebarShown: the sidebar is docked beside the page. The floating sidebar doesn't count:
    ///     it hovers over the page and the card stays where it is.
    public static func fillsWindow(edgeToEdge: Bool, fullScreen: Bool, sidebarShown: Bool) -> Bool {
        edgeToEdge || (fullScreen && !sidebarShown)
    }
}
