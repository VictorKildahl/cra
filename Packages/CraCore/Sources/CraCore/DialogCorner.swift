import CoreGraphics

/// The corners of the card a Cra dialog draws in its sheet (GitHub #753). The sheet is macOS's own window, with its
/// light background and 1 pt edge, and the card covers it. Arc's cards round at 16–24 pt, which macOS 26's sheets
/// match or exceed; macOS 11–15's sheets round at 10 pt, so a rounder card left the sheet's light background showing
/// in its corners, a white rim around ⌘Q's Quit Cra? on macOS 15. There the card rounds no more than its sheet.
public enum DialogCorner {
    /// The corner radius of a sheet on macOS 11 to 15.
    public static let legacySheetRadius: CGFloat = 10

    public static func radius(_ wanted: CGFloat, macOSMajor: Int) -> CGFloat {
        macOSMajor >= 26 ? wanted : min(wanted, legacySheetRadius)
    }
}
