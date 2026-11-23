import QuartzCore

/// The mask over the sidebar's space pages (DownloadsTrayMask). It is the only thing that keeps the
/// other spaces' columns, side by side on the pager's strip, from showing past the column, so its size
/// follows the column at once and only the downloads list's fade eases. Eased with the fade, a column
/// narrowing from the Library's 417 pt to the tab list's width left the next space's column showing past
/// its edge for the ease's 0.13 s: at the screen's edge after a swipe out of a Library a hidden sidebar
/// had opened, where the hidden column's right neighbour lies (#679).
enum PagerMask {
    /// The mask at `frame`, with the downloads list's fade at `locations` and `colors`; `opening` picks
    /// the list's ease (0.18 s opening, 0.13 s closing).
    static func place(_ mask: CAGradientLayer, frame: CGRect, locations: [NSNumber], colors: [CGColor], opening: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = frame
        CATransaction.commit()
        CATransaction.begin()
        CATransaction.setAnimationDuration(opening ? 0.18 : 0.13)
        if !opening { CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut)) }
        mask.locations = locations
        mask.colors = colors
        CATransaction.commit()
    }

    /// Whether the mask's size or place is still easing toward the column's: while it narrows, the next
    /// space's column shows past the column's edge.
    static func trails(_ mask: CALayer) -> Bool {
        ["bounds", "position", "bounds.size", "frame"].contains { mask.animation(forKey: $0) != nil }
    }
}
