import AppKit

extension NSTextField {
    /// `frame`, in the label's superview, grown down until it holds every pixel of the label's
    /// glyphs, top edge kept (flipped or not).
    ///
    /// A label's line is as tall as its font's, but Apple Color Emoji draws below it: at 13 pt the
    /// picture ends 3.25 pt under the baseline and the line 3 pt. macOS 26 lets a label draw past
    /// its frame; on the reporter's macOS 27.2 a space's emoji lost its bottom row in the dock, as
    /// it does here with `clipsToBounds` on (#399). A label draws its text from the top, so a
    /// taller frame leaves the emoji in place.
    /// One point more covers the baseline snapping to a whole pixel: on a 1x screen, from the
    /// header's half-point origin, it lands a pixel lower.
    func frameHoldingInk(_ frame: NSRect) -> NSRect {
        let line = CTLineCreateWithAttributedString(attributedStringValue)
        let inkBelowBaseline = -CTLineGetBoundsWithOptions(line, .useGlyphPathBounds).minY
        let roomBelowBaseline = frame.height - firstBaselineOffsetFromTop
        guard inkBelowBaseline > roomBelowBaseline else { return frame }
        let extra = (inkBelowBaseline - roomBelowBaseline + 1).rounded(.up)
        let y = superview?.isFlipped == true ? frame.minY : frame.minY - extra
        return NSRect(x: frame.minX, y: y, width: frame.width, height: frame.height + extra)
    }
}
