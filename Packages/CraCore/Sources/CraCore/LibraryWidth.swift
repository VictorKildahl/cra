import Foundation

/// How wide the sidebar is while the Library is in it.
///
/// Arc's Library is 417 pt whatever the tab sidebar's width: measured over AX on an offline
/// Arc 1.172 with the tab sidebar at 200, 347 and 450 pt (10 Nov 2026, issue #302). Cra added
/// 70 pt to the user's own width, so a narrow sidebar left the list beside the 113 pt rail
/// too narrow to read.
public enum LibraryWidth {
    /// Arc's Library sidebar.
    public static let standard: Double = 417
    /// The page rail on the Library's left.
    public static let rail: Double = 113
    /// The slice of the page that shows beside the Spaces page, whatever the window's width
    /// (Arc 1.171). The page itself keeps its width and goes on past the window's edge (`page`).
    public static let pageRoom: Double = 56
    /// The narrowest slice of the page Arc shows beside its Library: its narrowest window (926 pt) less 417.
    public static let pageMinimum: Double = 509
    /// The narrowest the Library gets in a narrow window: a 207 pt list beside the rail.
    public static let minimum: Double = 320

    /// The sidebar's width with the Library open. The Spaces page widens to fit `spacesCards`
    /// (the width its cards need, rail included) while the window leaves the page `pageRoom`;
    /// its cards scroll sideways when they don't fit.
    ///
    /// The other pages are 417 pt in any window Arc allows. Cra's window goes down to 640 pt,
    /// narrower than Arc's 926: there the Library gives way so the page keeps `pageMinimum`,
    /// down to `minimum`, where the two share what is left (#302).
    public static func sidebar(spacesCards: Double? = nil, window: Double) -> Double {
        guard let spacesCards else { return min(standard, max(minimum, window - pageMinimum)) }
        return max(standard, min(spacesCards, window - pageRoom))
    }

    /// The page's width while the Library is in the sidebar: what it had beside the tab sidebar
    /// (`tabSidebar` wide), or the whole card's when the Library brought out a hidden sidebar
    /// (`nil`), less the card's `inset` on the window's edges. Arc 1.172.2 moves the page with
    /// the Library's right edge and lets the window cut off what goes past its own, so the site
    /// is never laid out again in a narrow column (#340). A Library narrower than the tab sidebar
    /// leaves no gap: the page fills what it leaves.
    public static func page(window: Double, library: Double, tabSidebar: Double?, inset: Double) -> Double {
        max(window - (tabSidebar ?? inset) - inset, window - library - inset)
    }
}
