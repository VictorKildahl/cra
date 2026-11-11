import CoreGraphics

/// Chromium's window-modal dialogs: the extension install prompt, the prompt to remove one, the
/// one that turns an extension back on after it asks for more. Chromium shows each as a sheet on
/// the Chromium browser window its page is in. Cra embeds pages in its own window, which is no
/// Chromium window, so the dialog gets no parent and Chromium shows it free-standing instead, as
/// its own source warns (ui/views/widget/native_widget_mac.mm: "Otherwise, it will not be
/// displayed as a sheet. Then it will show a native titlebar, which will cover the content"):
/// placed against the screen, unmovable, with macOS's title bar over its top 32 pt, where the
/// prompt's title is (GitHub #349). Cra shows it the way a sheet would be.
public enum ChromiumDialog {
    /// The style Chromium gives a window-modal dialog (native_widget_mac.mm StyleMaskForParams):
    /// NSWindowStyleMaskTitled | NSWindowStyleMaskFullSizeContentView and nothing else. Its own
    /// browser and app windows are closable, miniaturizable and resizable as well; its bubbles and
    /// popups are borderless.
    public static let windowModalStyle: UInt = 1 << 0 | 1 << 15

    /// Chromium's NSWindow class for every widget it makes.
    public static let windowClass = "NativeWidgetMacNSWindow"

    /// Whether a window is such a dialog that came without a parent: Chromium's window class
    /// with exactly the window-modal style, neither a sheet nor attached to a window.
    public static func isParentless(className: String, styleMask: UInt, isSheet: Bool, hasParent: Bool) -> Bool {
        className == windowClass && styleMask == windowModalStyle && !isSheet && !hasParent
    }

    /// Where it goes, in screen coordinates (AppKit's, origin bottom left): where AppKit hangs a
    /// sheet on `window`, centred on it with its top at the bottom of the window's title bar,
    /// then moved onto `screen` (the visible frame of the window's screen). Taller than the
    /// screen, its top stays on it: that is where its title is.
    public static func frame(size: CGSize, over window: CGRect, titleBarHeight: Double, screen: CGRect) -> CGRect {
        var x = window.midX - size.width / 2
        var y = window.maxY - titleBarHeight - size.height
        x = max(screen.minX, min(x, screen.maxX - size.width))
        y = min(screen.maxY - size.height, max(y, screen.minY))
        if size.height > screen.height { y = screen.maxY - size.height }
        if size.width > screen.width { x = screen.minX }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
