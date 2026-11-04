import CoreGraphics

/// How many pinned extensions the toolbar hides so the address keeps its whole width. Arc
/// 1.171's toolbar works out `numberOfExtensionsThatFit` (with `urlDomainHasRoom`) and drops
/// pins from the front of the list, the ones farthest from its right end: with ten pins it
/// showed the last seven in a 1100 pt window and the last two at 800 pt, the URL whole and
/// centred both times (live, 4 Nov 2026). The hidden ones stay in the Extensions menu.
public enum ToolbarExtensionFit {
    /// `widths`: the pinned buttons, in pin order. `room(hiddenWidth)`: the space the address
    /// gets once that much of the pins' width is gone. `needed`: the address's whole width.
    public static func hiddenCount(widths: [CGFloat], needed: CGFloat, room: (CGFloat) -> CGFloat) -> Int {
        var hidden = 0, freed: CGFloat = 0
        while hidden < widths.count, room(freed) < needed {
            freed += widths[hidden]
            hidden += 1
        }
        return hidden
    }
}
