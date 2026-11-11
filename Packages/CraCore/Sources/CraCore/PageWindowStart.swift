import CoreGraphics

/// Where a new page's window is first shown (GitHub #354). Every page is a Chromium window of its
/// own, which Chromium shows before Cra lays it over the window the page is for. Left to Chromium
/// it showed in the top left corner of the primary display, and a window shown on a display
/// brings that display to a desktop: with Cra on a second display and another app full screen on
/// the primary one, every new tab, Peek, popup and DevTools pulled the primary display off its
/// full-screen Space.
///
/// A new page window starts on the middle of a Cra window instead, so on that window's display
/// and Space: the one in use (the user just clicked a link or a tab in it), else the frontmost
/// one on screen (a page opened behind, a Calendar favorite read in the background).
public enum PageWindowStart {
    /// One of Cra's own windows (a browser window or a Little Window), in screen coordinates.
    public struct Window: Equatable, Sendable {
        public var frame: CGRect
        /// The key window, or the one whose panel is key; else the main window.
        public var isInUse: Bool
        /// Showing, on the Space in front on its display.
        public var isOnScreen: Bool

        public init(frame: CGRect, isInUse: Bool, isOnScreen: Bool) {
            self.frame = frame
            self.isInUse = isInUse
            self.isOnScreen = isOnScreen
        }
    }

    /// The frame a new page window of `size` is shown at, `windows` being Cra's from front to
    /// back. nil with no window to show it on (none made yet): Chromium's place then.
    public static func frame(_ size: CGSize, among windows: [Window]) -> CGRect? {
        let windows = windows.filter { !$0.frame.isEmpty }
        guard let host = windows.first(where: { $0.isInUse && $0.isOnScreen })
            ?? windows.first(where: \.isOnScreen)
            ?? windows.first(where: \.isInUse)
            ?? windows.first else { return nil }
        return CGRect(x: (host.frame.midX - size.width / 2).rounded(), y: (host.frame.midY - size.height / 2).rounded(),
                      width: size.width, height: size.height)
    }
}
