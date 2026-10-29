import Foundation

/// Both the shell's tracking area and the floating panel's pointer poll use the
/// same window-local boundaries.
enum FloatingSidebarGeometry {
    /// Arc 1.170, measured with the pointer on a window away from the screen edge (29 Oct):
    /// the hidden sidebar comes out within 5 pt of the window's left edge (not at 6 or 9 pt)
    /// and from just outside it (2–4 pt).
    static let revealInside: CGFloat = 5
    static let revealOutside: CGFloat = 4
    static let margin: CGFloat = 8
    static let leaveSlack: CGFloat = 24

    static func shouldReveal(at point: CGPoint, in bounds: CGRect) -> Bool {
        point.y >= bounds.minY && point.y <= bounds.maxY
            && point.x >= bounds.minX - revealOutside && point.x <= bounds.minX + revealInside
    }

    static func shouldHide(at point: CGPoint, in bounds: CGRect, sidebarWidth: CGFloat,
                           pressedMouseButtons: Int) -> Bool {
        // Window movement can put the pointer outside the panel briefly. Preserve
        // the active drag/context gesture; the next released-pointer check dismisses.
        guard pressedMouseButtons == 0, !shouldReveal(at: point, in: bounds) else { return false }
        return !bounds.contains(point) || point.x > bounds.minX + sidebarWidth + margin + leaveSlack
    }
}
