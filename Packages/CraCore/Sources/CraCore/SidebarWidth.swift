import Foundation

/// How wide the sidebar can be. Arc 1.17x clamps a drag of the sidebar's edge to 164–500 pt
/// (`WindowLayoutController.handleSidebarResizePanGestureRecognizer:`, read from the arm64
/// binary; issue #287). Cra used 220–520, so a sidebar people kept narrow in Arc came out wider.
/// A double-click of the edge restores Arc's "default" width — the same 228 pt as the drag snap
/// (`SidebarResizeState.canSnapToDefaultWidth`; issue #819), not `initial`.
public enum SidebarWidth {
    public static let minimum: Double = 164
    public static let maximum: Double = 500
    /// Width a fresh window starts at when none is saved (older Arc notes; not the double-click target).
    public static let initial: Double = 328

    /// `width` held inside Arc's range: for a drag, and for a width imported from Arc.
    public static func clamped(_ width: Double) -> Double {
        min(max(width, minimum), maximum)
    }
}
