import CoreGraphics

/// Where one of Chromium's windows for a page sits: a tab-modal dialog (alert, confirm, prompt,
/// "Leave site?", the HTTP sign-in prompt, the screen-share picker, passkeys), a bubble (a device
/// chooser, "Save password?") or a page's popup (a date picker). On the engine Chromium hangs them
/// on a profile's Browser window, which Cra never shows: since 0.1.49 a 1 pt strip along the top of
/// Cra's window (PageHostStrip, #346). Chromium's print preview sized itself to that window and came
/// out 3 pt tall, and its tab-modal dialogs were centred on the whole window rather than on the page
/// that asked: over the other pane of a split (#574). `cra://debug?pageDialogs` reads each window
/// with this rule.
public enum PageDialogPlacement: String, Sendable {
    /// Over the page: its centre on the page, and big enough to read and answer.
    case page
    /// On the page's window, outside the page (a bubble from where Chrome's toolbar would be).
    case window
    /// Too small to read or answer, wherever it is.
    case sliver
    /// Nowhere on the page's window.
    case off

    /// Smaller than this in either direction, no dialog can be read: Chrome's smallest, an alert
    /// with one line and OK, is about 260 × 130 pt.
    public static let smallest: CGFloat = 40

    /// All in one coordinate space (screen coordinates).
    public static func of(_ dialog: CGRect, page: CGRect?, window: CGRect) -> PageDialogPlacement {
        if dialog.width < smallest || dialog.height < smallest { return .sliver }
        let centre = CGPoint(x: dialog.midX, y: dialog.midY)
        if let page, page.contains(centre) { return .page }
        return window.contains(centre) ? .window : .off
    }
}
