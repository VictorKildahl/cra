import Foundation

/// Whether a button in Cra's window acts on the click that makes the window key (AppKit's
/// acceptsFirstMouse; a click it does not hand over only gives the window focus).
///
/// DevTools and the page are Chromium child windows of the main window. Chrome draws all of it
/// in one window, so after a click in them the next click on a toolbar button counts (GitHub
/// #42). An extension's popup is a child window too, but like Arc's it takes focus (the window
/// greys out), and Arc 1.170's toolbar then only takes focus back, which closes the popup: its
/// own button does not open it again, and another extension's button or Split View needs a
/// second click (GitHub #87). A click into an inactive Cra only activates it.
public enum FirstClick {
    /// `focusInWindow`: the key window is this window or one of its child windows.
    /// `closedPopup`: this mouse-down took focus from an extension's popup.
    public static func takes(appActive: Bool, focusInWindow: Bool, closedPopup: Bool) -> Bool {
        appActive && focusInWindow && !closedPopup
    }
}
