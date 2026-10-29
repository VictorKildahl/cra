import Foundation

/// Both the shell's tracking area and the floating panel's pointer poll use the
/// same window-local boundaries. Revealing uses only the existing page gutter.
enum FloatingSidebarGeometry {
    static let revealWidth = CraMetrics.contentInset
    static let margin: CGFloat = 8
    static let leaveSlack: CGFloat = 24

    static func shouldReveal(at point: CGPoint, in bounds: CGRect) -> Bool {
        bounds.contains(point) && point.x <= bounds.minX + revealWidth
    }

    static func shouldHide(at point: CGPoint, in bounds: CGRect, sidebarWidth: CGFloat,
                           pressedMouseButtons: Int) -> Bool {
        // Window movement can put the pointer outside the panel briefly. Preserve
        // the active drag/context gesture; the next released-pointer check dismisses.
        guard pressedMouseButtons == 0 else { return false }
        return !bounds.contains(point) || point.x > bounds.minX + sidebarWidth + margin + leaveSlack
    }
}
