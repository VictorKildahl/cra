import CoreGraphics

/// The titled window Cra puts around an extension's popup (Arc's BrowserExtensionWindow, #701): the
/// popup's page sits `border` inside the window's sides and bottom, so the window's own border line
/// shows around it, and the page's bottom corners are rounded to follow the window's.
public enum ExtensionPopupFrame {
    public static let border: CGFloat = 1

    /// The page's corner radius inside a window whose corners macOS rounds by `windowRadius`.
    public static func pageCornerRadius(windowRadius: CGFloat) -> CGFloat {
        max(0, windowRadius - border)
    }
}
