import QuartzCore

/// How split panes move on screen. The layout itself is CraCore's SplitPaneLayout.
extension SplitPaneLayout.Constants {
    /// Add/remove pane transition. Arc lays the new pane out within a single
    /// frame (window recording at 27 fps, 24 Oct 2026); 0 = no transition.
    static let transitionDuration: TimeInterval = 0
    static let transitionTiming = CAMediaTimingFunction(controlPoints: 0.2, 0.85, 0.25, 1)
}
