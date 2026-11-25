import CoreGraphics
import Foundation

/// What the screen does once something is chosen in the search sheet, from Arc Search and Cra recorded at 60 fps on
/// the same iPhone (Nov 2026).
public enum MobileSheetLeave {
    /// The sheet rises this far as it fades out, eased in and out over `leaveDuration`, while the keyboard goes down.
    /// Arc Search's field went up 150 to 200 pt and was gone in a quarter of a second. Cra's sank into the pill
    /// behind the keyboard.
    public static let leaveRise: CGFloat = 160
    public static let leaveDuration: TimeInterval = 0.25

    /// A new tab opened from the sheet waits under the canvas colour (black with websites dark), faded in over
    /// `leaveDuration`, until its page has drawn: Arc Search's screen goes black without ever lightening and the page
    /// appears on it. Cra cut to the new page at once, which showed white before a dark site drew. The page itself
    /// stays out of sight under the cover, as does the band behind the status bar (`MobileStatusBand.shown`): WebKit
    /// paints a new page white before its own colours come. Not longer than this, though: a page that takes its time
    /// is shown as it is.
    public static let coverLongestHold: TimeInterval = 1.5

    /// How long the cover stays once the page says it has drawn: WebKit puts that paint on screen a frame or two
    /// later. Lifted at once, the cover showed the page's white canvas for two frames before its colours came.
    public static let drawnSettle: TimeInterval = 0.1

    /// Whether that cover comes off, `elapsed` seconds after the choice and `sinceDrawn` after the page said it had
    /// drawn (nil while it hasn't): once that paint has had time to reach the screen and the fade has run, or at the
    /// longest hold.
    public static func liftsCover(elapsed: TimeInterval, sinceDrawn: TimeInterval?) -> Bool {
        if elapsed >= coverLongestHold { return true }
        guard let sinceDrawn else { return false }
        return sinceDrawn >= drawnSettle && elapsed >= leaveDuration
    }
}
