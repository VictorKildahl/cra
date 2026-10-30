import Foundation

/// Both the shell's tracking area and the floating panel's pointer poll use the
/// same window-local boundaries.
enum FloatingSidebarGeometry {
    /// The hidden sidebar comes out over the whole 10 pt margin left of the page and from just
    /// outside the window (2–4 pt, as in Arc). Arc 1.170's own strip is 5 pt (measured 29 Oct:
    /// out at 1–5 pt, not at 6 or 9 pt); the full margin is a deliberate choice, easier to hit.
    static let revealInside: CGFloat = 10
    /// Edge to edge there is no margin: the strip over the page is Arc's 5 pt.
    static let revealInsideEdgeToEdge: CGFloat = 5
    static let revealOutside: CGFloat = 4
    static let margin: CGFloat = 8
    static let leaveSlack: CGFloat = 24

    static func shouldReveal(at point: CGPoint, in bounds: CGRect, edgeToEdge: Bool = false) -> Bool {
        point.y >= bounds.minY && point.y <= bounds.maxY
            && point.x >= bounds.minX - revealOutside && point.x <= bounds.minX + (edgeToEdge ? revealInsideEdgeToEdge : revealInside)
    }

    static func shouldHide(at point: CGPoint, in bounds: CGRect, sidebarWidth: CGFloat,
                           pressedMouseButtons: Int, edgeToEdge: Bool = false) -> Bool {
        // Window movement can put the pointer outside the panel briefly. Preserve
        // the active drag/context gesture; the next released-pointer check dismisses.
        guard pressedMouseButtons == 0, !shouldReveal(at: point, in: bounds, edgeToEdge: edgeToEdge) else { return false }
        return !bounds.contains(point) || point.x > bounds.minX + sidebarWidth + margin + leaveSlack
    }
}
