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
        window(at: point, in: frontToBack, readsSharing: true)
    }

    /// The same for a picker that does or doesn't read sharing state and alpha. One that lists
    /// windows through ScreenCaptureKit (`SCShareableContent`, iShot on macOS 27) gets neither:
    /// an `SCWindow` has no sharing state and no alpha, so a window left out of capture or fully
    /// transparent is an ordinary window there, and capturing it on its own gives a blank image.
    /// On the engine that was the window holding a profile's pages, over the whole Cra window
    /// (#346 again, 0.1.48), so Cra's own windows have to be first wherever they show.
    public static func window(at point: CGPoint, in frontToBack: [Window], readsSharing: Bool) -> Window? {
        frontToBack.first {
            $0.layer == 0 && $0.frame.contains(point) && (!readsSharing || ($0.alpha > 0 && $0.shared))
        }
    }
}

/// Where the engine's window that holds a profile's pages goes over the Cra window it rides with
/// (#346). That window of Chrome's is never seen, but stays on screen as a child of the Cra window
/// in use: Chrome anchors bubbles (an extension's popup) to its toolbar, and only shows them over a
/// window that is on screen. Laid over the whole Cra window, it was the window a screenshot app
/// took there, captured blank. A strip along the Cra window's top edge keeps its top left, so
/// Chrome's bubbles still open where they did, and leaves the rest of the window to Cra's own.
public enum PageHostStrip {
    public static let height: CGFloat = 1

    /// The strip over `window`, both in AppKit's screen coordinates (y up).
    public static func frame(over window: CGRect) -> CGRect {
        let h = min(height, max(window.height, 0))
        return CGRect(x: window.minX, y: window.maxY - h, width: window.width, height: h)
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
