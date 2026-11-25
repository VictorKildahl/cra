import CoreGraphics
import Foundation

/// How the search sheet comes up from the pill, from Arc Search and Cra recorded at 60 fps on the same iPhone
/// (Nov 2026).
public enum MobileSearchMotion {
    /// Tapped, the sheet sets off at once: eased out over this long, at its fastest from the first frame, towards
    /// where it sits without a keyboard. The keyboard's own animation takes it over when its notification comes,
    /// 75 to 150 ms after the tap. The move goes to the render server before the keyboard is asked for, which keeps
    /// the main thread busy for tens of milliseconds: Arc Search's sheet moves on the frame after the finger lifts,
    /// and is a third of the way to that spot two frames later. Cra's waited for the keyboard, about 130 ms on the
    /// phone.
    public static let leadDuration: TimeInterval = 0.25

    /// The bar pill's plus while the pill grows into the field: its centre's distance from the field's left end.
    /// It keeps to the leading end, from the pill's middle (closed) to 2 pt in (open), with the placeholder coming
    /// in to its right ("+ Search..."), as in Arc Search. Cra's stayed in the middle, over the placeholder.
    public static func plusCenter(closedWidth: CGFloat, openness: CGFloat) -> CGFloat {
        let open = min(1, max(0, openness))
        return closedWidth / 2 * (1 - open) + 2 * open
    }

    /// Where the field's text starts while the field grows: 22.5 pt right of the plus, so 24.5 pt in once open.
    public static func textInset(closedWidth: CGFloat, openness: CGFloat) -> CGFloat {
        plusCenter(closedWidth: closedWidth, openness: openness) + 22.5
    }

    /// The stretch of the sheet's openness (0 closed, 1 open) over which its own surface goes from clear to solid:
    /// the first quarter, as Arc Search's panel is solid from the first frame, so the page doesn't show between the
    /// rows. Faded in with the field all the way, Cra's let the page's text show through its suggestions.
    public static let surfaceSpan: ClosedRange<CGFloat> = 0...0.25
    /// The stretch over which the field's buttons at its right end (mic, incognito, clear) come in: the second half,
    /// as Arc Search's mic shows once the field is most of the way across. From the start, they sat in the pill.
    public static let accessorySpan: ClosedRange<CGFloat> = 0.5...1

    /// How far in something faded over `span` is at `openness`, 0...1: for the sheet pulled by a finger.
    public static func opacity(openness: CGFloat, over span: ClosedRange<CGFloat>) -> CGFloat {
        min(1, max(0, (openness - span.lowerBound) / (span.upperBound - span.lowerBound)))
    }

    /// The part of an animated move of the sheet from openness `from` to `to` in which something faded over `span`
    /// changes, as shares of the move's time: opening, the surface in the first quarter, the buttons in the second
    /// half; closing, the buttons in the first half and the surface in the last quarter.
    public static func fadeWindow(from: CGFloat, to: CGFloat, over span: ClosedRange<CGFloat>) -> ClosedRange<Double> {
        guard from != to else { return 0...0 }
        let ends = [span.lowerBound, span.upperBound].map { Double(min(1, max(0, ($0 - from) / (to - from)))) }
        return ends.min()!...ends.max()!
    }
}
