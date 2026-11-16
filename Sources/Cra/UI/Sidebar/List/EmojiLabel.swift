import AppKit

/// A space's emoji in the dock and the space header: a sidebar label that draws its own text
/// instead of leaving it to its cell.
///
/// Apple Color Emoji draws below the system font's line: at 13 pt its picture is a 16.25 pt square
/// that ends 3.25 pt under the baseline, and the label's line has 3 pt there. On the reporter's
/// macOS 27.2 the dock showed every emoji cut flat near the baseline, in 0.1.41 and again in 0.1.42
/// after `frameHoldingInk` had grown the frame to hold the picture (#399). So the cut isn't the
/// view's edge but the label's own text drawing. This label draws the string itself, from the
/// cell's text rect (the same place, to the pixel, on macOS 26), and nothing but its frame bounds
/// the picture.
final class EmojiLabel: NSTextField {
    static func sidebar(size: CGFloat) -> EmojiLabel {
        let l = EmojiLabel(labelWithString: "")
        l.font = .systemFont(ofSize: size)
        l.lineBreakMode = .byTruncatingTail
        l.usesSingleLineMode = true
        l.maximumNumberOfLines = 1
        l.cell?.truncatesLastVisibleLine = true
        return l
    }

    /// The cell's text rect: its 2 pt inset at the sides, from the top edge down. It's open at the
    /// bottom, so no line box clips the picture; the label's frame does, and `frameHoldingInk`
    /// makes that tall enough. The label is flipped, so the top edge is y = 0.
    var textRect: NSRect {
        let inset: CGFloat = 2
        // Taller than the label by a font size: no line box clips the picture, and a context that isn't
        // flipped (a layer rendered for a component snapshot) doesn't put the text at the far end of an
        // endless rect.
        return NSRect(x: inset, y: 0, width: max(0, bounds.width - 2 * inset),
                      height: bounds.height + (font?.pointSize ?? 13) * 2)
    }

    /// Drawn twice: a stock label's text reaches the screen composited twice (its antialiased edges
    /// are a + a(1 − a) of one pass, byte for byte at 1x and 2x), while a label that draws itself
    /// composites once, and the dock and header snapshots showed the emoji's edges fainter. Two
    /// passes keep the look that shipped.
    override func draw(_ dirtyRect: NSRect) {
        guard !stringValue.isEmpty else { return }
        let text = attributedStringValue, rect = textRect
        for _ in 0..<2 { text.draw(with: rect, options: [.usesLineFragmentOrigin]) }
    }
}

extension NSTextField {
    /// `frame`, in the label's superview, grown down until it holds every pixel of the label's
    /// glyphs, top edge kept (flipped or not).
    ///
    /// A label's line is as tall as its font's, but Apple Color Emoji draws below it: at 13 pt the
    /// picture ends 3.25 pt under the baseline and the line 3 pt. A label clipped to its frame loses
    /// that bottom row (#399). A label draws its text from the top, so a taller frame leaves the
    /// emoji in place.
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
