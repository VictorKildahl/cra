/// The windows a keyboard window manager moves and resizes for Cra.
///
/// Raycast's window management, Rectangle, Magnet and the like take the frontmost app's
/// focused window through accessibility and set its AXPosition and AXSize. They leave alone a
/// window that isn't a standard one: Rectangle refuses sheets and system dialogs. AppKit
/// reports a non-activating panel as a system dialog, and the Little Window is one (it opens
/// over another app's full-screen Space, #186), so Raycast's shortcuts did nothing to it while
/// they moved other browsers' windows (X, 17 Nov 2026). Docked Chromium windows answer as
/// groups inside the window they sit on (DockedWindowAccessibility, #391), so they are never
/// a window manager's target.
public enum WindowManagers {
    public struct Window: Equatable, Sendable {
        public var role: String?
        public var subrole: String?
        /// Whether AXPosition and AXSize are settable.
        public var canMove: Bool
        public var canResize: Bool

        public init(role: String? = "AXWindow", subrole: String?, canMove: Bool, canResize: Bool) {
            self.role = role
            self.subrole = subrole
            self.canMove = canMove
            self.canResize = canResize
        }
    }

    /// Whether a window manager's shortcuts move and resize `window`, the focused window of the
    /// frontmost app: a standard window whose position and size can be set.
    public static func handles(_ window: Window) -> Bool {
        window.role == "AXWindow" && window.subrole == "AXStandardWindow" && window.canMove && window.canResize
    }
}
