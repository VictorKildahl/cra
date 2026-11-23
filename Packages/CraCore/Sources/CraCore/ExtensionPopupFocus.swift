import Foundation

/// Which windows taking focus leave an extension's popup open (GitHub #701). Chrome closes a popup when
/// it loses focus, except to the DevTools inspecting it: Inspect in the popup's menu opens Chromium's own
/// DevTools window, titled "DevTools - chrome-extension://<id>/<page>", and the popup stays while it's
/// inspected. Cra closed it as for any other window, so Inspect did nothing.
public enum ExtensionPopupFocus {
    public static func isDevTools(title: String) -> Bool {
        title == "DevTools" || title.hasPrefix("DevTools - ")
    }
}
