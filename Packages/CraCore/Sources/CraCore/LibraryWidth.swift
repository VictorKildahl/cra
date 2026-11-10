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
    /// What the page keeps beside the Spaces page, whatever the window's width (Arc 1.171).
    public static let pageRoom: Double = 56
    /// The narrowest page Arc shows beside its Library: its narrowest window (926 pt) less 417.
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
}
