import CoreGraphics

/// The window a screenshot app takes when it captures "the window under the pointer" (#346).
///
/// Apps like iShot list the screen's windows front to back (`CGWindowListCopyWindowInfo`), take
/// the first ordinary one under the pointer, and capture that window on its own. Over a Cra page
/// the first one used to be a clear window, the status bubble's page-sized panel or the empty
/// Chromium window whose page moved into the card, so the shot came out blank white. Pages
/// draw in the main window's card, and that is the window a pick over a page has to find.
public enum ScreenshotPick {
    public struct Window: Equatable, Sendable {
        public var number: Int
        /// Screen frame, from the top left (CGWindowList's bounds).
        public var frame: CGRect
        /// Window level; 0 is the level of ordinary windows (and of their child windows).
        public var layer: Int
        public var alpha: Double
        /// False for `NSWindow.sharingType == .none`: screen capture leaves the window out, and the
        /// window list says so (kCGWindowSharingState 0), which is how pickers skip it.
        public var shared: Bool

        public init(number: Int, frame: CGRect, layer: Int = 0, alpha: Double = 1, shared: Bool = true) {
            self.number = number
            self.frame = frame
            self.layer = layer
            self.alpha = alpha
            self.shared = shared
        }
    }

    /// The first window, front to back, that a picker takes at `point`: an ordinary window
    /// that shows, can be captured and contains the point.
    public static func window(at point: CGPoint, in frontToBack: [Window]) -> Window? {
        frontToBack.first { $0.layer == 0 && $0.alpha > 0 && $0.shared && $0.frame.contains(point) }
    }
}

/// Where the link status bubble's panel goes over the focused page: just the bubble's strip at
/// the page's bottom left, not the whole page. A page-sized clear panel was the window
/// screenshot apps took over the page (#346).
public enum StatusBubbleStrip {
    public static let maxWidth: CGFloat = 540
    public static let height: CGFloat = 34

    /// The strip in `page`'s coordinates, which run up from the bottom left (AppKit's).
    public static func frame(inPage page: CGRect) -> CGRect {
        CGRect(x: page.minX, y: page.minY, width: max(0, min(maxWidth, page.width)), height: max(0, min(height, page.height)))
    }
}
