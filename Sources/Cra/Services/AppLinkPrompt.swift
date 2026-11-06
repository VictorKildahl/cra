import AppKit
import CraCEF

/// Chrome's external protocol dialog for a page in either engine: a link, target=_blank link or
/// window.open to another app's address (AppLinks) opens no tab. "Open Spotify?" comes up over
/// the page that asked, and macOS opens the app, as in Arc (GitHub #207: Spotify's "Open in
/// Desktop app" left a blank spotify: tab). A Chromium page's same-tab links keep Chrome's own
/// dialog (CraCEF's OnProtocolExecution).
@MainActor
enum AppLinkPrompt {
    /// Chromium's new tabs and windows (CraCEF's OnBeforePopup) come here first.
    static func install() {
        CraCEFRuntime.setAppLinkHandler { browser, url, userGesture in
            MainActor.assumeIsolated { handle(url, from: browser, userGesture: userGesture) }
        }
    }

    /// Whether `url` is another app's. Then it is dealt with here (asked about, opened or
    /// refused) and must not load or open a tab. Without a click (`userGesture`) nothing opens.
    @discardableResult
    static func handle(_ url: String, from browser: CraBrowser, userGesture: Bool) -> Bool {
        let kind = AppLinks.kind(of: url)
        if kind == .page { return false }
        let page = browser.isIncognito ? "(incognito)" : CraLog.host(browser.currentURL)
        let scheme = url.prefix { $0 != ":" }.lowercased() + ":"
        guard kind != .refused, userGesture, let target = URL(string: url) else {
            CraLog.note("page \(page) can't open \(scheme) \(kind == .refused ? "(refused)" : "(no click)")")
            return true
        }
        // No app for it: nothing happens, as in Chrome.
        guard let app = NSWorkspace.shared.urlForApplication(toOpen: target) else {
            CraLog.note("page \(page) wants \(scheme), no app opens it")
            return true
        }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        if kind == .opens {
            CraLog.note("page \(page) opens \(name) for \(scheme)")
            NSWorkspace.shared.open(target)
            return true
        }
        // One question at a time: a page asking again while it is up gets nothing.
        guard let window = browser.containerView.window, window.attachedSheet == nil else {
            CraLog.note("page \(page) asks for \(name) again, already asking")
            return true
        }
        CraLog.note("page \(page) asks to open \(name) for \(scheme)")
        let alert = NSAlert()
        alert.messageText = "Open \(name)?"
        alert.informativeText = "\(URL(string: browser.currentURL)?.host ?? "This site") wants to open this application."
        alert.addButton(withTitle: "Open \(name)")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(target) }
        }
        return true
    }
}
