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

    static func shouldHide(at point: CGPoint, in bounds: CGRect, sidebarWidth: CGFloat) -> Bool {
        !bounds.contains(point) || point.x > bounds.minX + sidebarWidth + margin + leaveSlack
    }
}
