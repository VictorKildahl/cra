import AppKit
import CraCEF

/// Chrome's external protocol dialog for a page in either engine: a link, target=_blank link or
/// window.open to another app's address (AppLinks) opens no tab. "Open Spotify?" comes up over
/// the page that asked, and macOS opens the app, as in Arc (GitHub #207: Spotify's "Open in
/// Desktop app" left a blank spotify: tab). A Chromium page's same-tab links keep Chrome's own
/// dialog (CraCEF's OnProtocolExecution).
@MainActor
enum AppLinkPrompt {
    /// Chromium's new tabs and windows (CraCEF's OnBeforePopup) and a page's own navigation to
    /// another app (the engine's HandleExternalProtocol) come here first. The page's own redirect
    /// gets Chrome's flood guard, as WebKit pages do: asked once per page load. Slack's
    /// "Launching…" page after a browser sign-in has no button to click, so it was dropped (#560).
    static func install() {
        CraCEFRuntime.setAppLinkHandler { browser, url, userGesture in
            MainActor.assumeIsolated {
                handle(url, from: browser, userGesture: userGesture || mayAskWithoutClick(url, from: browser))
            }
        }
    }

    /// An address typed in a command bar and sent with Return (#604): another app's opens it here and
    /// needs no tab; the caller loads a page, searches an address no app opens, and drops a refused one.
    static func openTyped(_ url: String) -> AppLinks.Typed {
        let target = URL(string: url)
        let app = target.flatMap { NSWorkspace.shared.urlForApplication(toOpen: $0) }
        let typed = AppLinks.typed(url, hasApp: app != nil)
        let scheme = url.prefix { $0 != ":" }.lowercased() + ":"
        switch typed {
        case .load: break
        case .openApp:
            let name = app.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? "?"
            CraLog.note("command bar opens \(name) for \(scheme)")
            if let target { NSWorkspace.shared.open(target) }
        case .search: CraLog.note("command bar: no app opens \(scheme), searched")
        case .refuse: CraLog.note("command bar can't open \(scheme) (refused)")
        }
        return typed
    }

    /// A Chromium page committed in its main frame (a new page or a reload; its tab's or Little
    /// Window's delegate says so): its own redirect may ask once again.
    static func pageLoaded(_ browser: CraBrowser) {
        redirectGuards.object(forKey: browser)?.value.pageLoaded()
    }

    /// Only another app's address or mail spends the page's one go (#684); a refused scheme doesn't, and a
    /// boost still needs a click.
    private static func mayAskWithoutClick(_ url: String, from browser: CraBrowser) -> Bool {
        guard AppLinks.mayGoWithoutClick(url), !BoostInstall.isBoostLink(url) else { return false }
        return redirectGuard(for: browser).value.mayAsk(userGesture: false)
    }

    /// Each Chromium page's `AppLinks.RedirectGuard`, gone with its page.
    private static let redirectGuards = NSMapTable<CraBrowser, GuardBox>.weakToStrongObjects()
    private final class GuardBox { var value = AppLinks.RedirectGuard() }
    private static func redirectGuard(for browser: CraBrowser) -> GuardBox {
        if let box = redirectGuards.object(forKey: browser) { return box }
        let box = GuardBox()
        redirectGuards.setObject(box, forKey: browser)
        return box
    }

    /// Whether `url` is another app's. Then it is dealt with here (asked about, opened or
    /// refused) and must not load or open a tab. Without a click (`userGesture`) nothing opens.
    @discardableResult
    static func handle(_ url: String, from browser: CraBrowser, userGesture: Bool) -> Bool {
        // The gallery's Open in Cra, clicked in Cra itself: no "Open Cra?" first, straight to the
        // question about the boost. Without a click nothing is asked.
        if BoostInstall.isBoostLink(url) {
            let page = browser.isIncognito ? "(incognito)" : CraLog.host(browser.currentURL)
            if userGesture { BoostInstall.offer(url, over: browser.containerView.window, from: page) }
            else { CraLog.note("page \(page) can't offer a boost (no click)") }
            return true
        }
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
            closeIfBlank(browser, scheme: scheme)
            return true
        }
        let name = FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
        if kind == .opens {
            CraLog.note("page \(page) opens \(name) for \(scheme)")
            NSWorkspace.shared.open(target)
            closeIfBlank(browser, scheme: scheme)
            return true
        }
        // One question at a time: a page asking again while it is up gets nothing.
        guard let window = browser.containerView.window, window.attachedSheet == nil else {
            CraLog.note("page \(page) asks for \(name) again, already asking")
            return true
        }
        CraLog.note("page \(page) asks to open \(name) for \(scheme)")
        let alert = AppDialog(title: "Open \(name)?",
                              message: "\(URL(string: browser.currentURL)?.host ?? "This site") wants to open this application.",
                              actions: [DialogAction("Open \(name)"), .cancel])
        alert.present(over: window) { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(target)
                closeIfBlank(browser, scheme: scheme)
            }
        }
        return true
    }

    /// A new tab or window that never showed a page and was only sent to the app's address goes, as Chrome
    /// closes it (AppLinks.closesRequester, #684). It closes itself, as a finished sign-in pop-up does, so its
    /// tab or Little Window goes the way window.close() takes it.
    private static func closeIfBlank(_ browser: CraBrowser, scheme: String) {
        guard AppLinks.closesRequester(currentURL: browser.currentURL, canGoBack: browser.canGoBack) else { return }
        CraLog.note("blank page closes: it only took \(scheme) to an app")
        browser.executeJavaScript("window.close()")
    }
}
