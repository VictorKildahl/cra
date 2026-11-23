import Foundation

/// Settings ▸ General ▸ Pages ▸ Margin (Ideas #366, whyady; not in Arc): how much room is left round the
/// page card in a window, from 1 pt to Arc's 10 pt. Edge to edge (#24) is the margin's zero: it keeps its own
/// switch, because more than the margin hangs on it (no shadow, the window's own corner round, the page's
/// top standing in for the title bar), and every value here is that card in a smaller inset. The card keeps
/// its round and its shadow at every margin.
public enum PageMargin {
    /// Arc's inset: the card 10 pt in from every edge of the window (measured 25 Oct 2026).
    public static let arc: Double = 10
    /// What the slider offers. Whole points; 0 is Edge to edge's.
    public static let range: ClosedRange<Double> = 1...10

    /// A stored margin as the window draws it: whole points within `range`; anything unreadable is Arc's.
    public static func clamped(_ margin: Double) -> Double {
        guard margin.isFinite else { return arc }
        return min(range.upperBound, max(range.lowerBound, margin.rounded()))
    }

    /// How far in from the window's edges the card sits: none where it fills the window (edge to edge, or
    /// full screen with the sidebar hidden, `CardFill.fillsWindow`), the margin elsewhere.
    public static func inset(margin: Double, fillsWindow: Bool) -> Double {
        fillsWindow ? 0 : clamped(margin)
    }

    /// The card's corner radius at a margin: Arc's `base` (6 pt), or more where the window's own round corner
    /// needs it. A page is a window of its own that the main window doesn't clip, so a card corner that meets a
    /// window corner has to stay inside it: concentric, `windowRadius` less the margin. At Arc's 10 pt in a 16 pt
    /// window corner that is Arc's 6 pt; at 3 pt it is 13 (Victor, 23 Nov 2026: the page's corners stood out
    /// past the window's at a 3 pt margin). A window with square corners (full screen) passes 0.
    public static func cardRadius(margin: Double, windowRadius: Double, base: Double) -> Double {
        max(base, windowRadius - clamped(margin))
    }

    /// The strip under the window's top edge where a click is the title bar's (a double click zooms, a drag
    /// moves the window): the margin above the card and 4 pt of the card's top, 4 pt alone edge to edge.
    public static func titleStrip(margin: Double, edgeToEdge: Bool) -> Double {
        (edgeToEdge ? 0 : clamped(margin)) + 4
    }

    /// How far into the window, on the sidebar's side, the pointer brings the hidden sidebar out. Arc's own
    /// strip is 5 pt; Cra takes the whole margin when it is wider, so it never reaches into the page further
    /// than that 5 pt, and at Arc's margin it is the 10 pt it always was (`FloatingSidebarGeometry`).
    public static func revealInside(margin: Double, fillsWindow: Bool) -> Double {
        max(Double(FloatingSidebarGeometry.revealInsideEdgeToEdge), inset(margin: margin, fillsWindow: fillsWindow))
    }

    /// Whether the card's leading edge stands where the sidebar puts it rather than where the margin does:
    /// further in from the window's edge than the margin (half a point of slack for a rounded frame).
    public static func besideSidebar(cardEdge: Double, margin: Double, fillsWindow: Bool) -> Bool {
        cardEdge > inset(margin: margin, fillsWindow: fillsWindow) + 0.5
    }
}
