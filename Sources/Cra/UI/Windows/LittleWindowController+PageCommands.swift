import AppKit
import CraCEF

/// The commands on a Little Window's own page and window (#333): Stay On Top, Share…, Save Page As…,
/// the captures, Copy URL as Quote and the rest of LittleWindowRouting's own-page list. They used to
/// fall through to the browser window and act on its selected tab.
extension LittleWindowController {
    /// The Little Window and its page (a child window of Chromium's) float together.
    var staysOnTop: Bool {
        window?.level == .floating && (browser?.hostWindow.map { $0.level == .floating } ?? true)
    }

    private func toggleStayOnTop() {
        guard let window else { return }
        let level: NSWindow.Level = staysOnTop ? .normal : .floating
        window.level = level
        browser?.hostWindow?.level = level
    }

    private var pageToast: PageCommands.Toast { { [weak self] text, action in self?.showToast(text, action: action) } }

    /// File ▸ Share…: the system's share list for the page, hanging from the top centre of the page.
    private func sharePage() {
        guard let url = URL(string: currentURL), let content = window?.contentView else { return }
        let anchor = NSRect(x: content.bounds.midX - 1, y: content.bounds.height - LittleMetrics.barHeight - 1, width: 2, height: 1)
        NSSharingServicePicker(items: [url]).show(relativeTo: anchor, of: content, preferredEdge: .minY)
    }

    /// `id` is one of LittleWindowRouting's own-page commands; it is always taken, with or without a page.
    func handleOwnPage(action id: String) -> Bool {
        guard let window else { return true }
        if id == "stayOnTop" { toggleStayOnTop(); return true }
        guard hasPage, let b = browser else {
            if id == "cast" { showToast("Nothing to Cast") }
            if id == "taskManager" { showToast("Open a Page First") }
            return true
        }
        switch id {
        case "share": sharePage()
        case "savePageAs": PageCommands.savePageAs(browser: b, title: browser?.currentTitle ?? state.title, over: window, toast: pageToast)
        case "captureFullPage": PageCommands.captureFullPage(browser: b, over: window, toast: pageToast)
        case "capturePortrait": PageCommands.capturePortrait(browser: b, over: window, toast: pageToast)
        case "copyURLQuote": PageCommands.copyURLAsQuote(browser: b, url: currentURL, toast: pageToast)
        case "jumpToSelection": PageCommands.jumpToSelection(browser: b)
        case "pictureInPicture": b.requestPictureInPicture(automatic: false)
        case "cast": if !b.runChromeCommand("IDC_ROUTE_MEDIA") { showToast("Nothing to Cast") }
        case "taskManager": if !b.runChromeCommand("IDC_TASK_MANAGER") { showToast("Open a Page First") }
        case "toggleDeveloperMode": store.settings.toggleDeveloperMode(url: currentURL)
        case "networkPanel":
            b.devToolsAction = "network"
            b.showDevTools()
        default:
            CraLog.fault("Little Window: \(id) is routed to the window, which has no handler for it")
        }
        return true
    }

    /// The menu rows of those commands while this window is in front: on for its page, not the browser
    /// window's selection. nil for any other command.
    func validate(_ id: String, item: NSMenuItem) -> Bool? {
        guard LittleWindowRouting.ownPage.contains(id) else { return nil }
        switch id {
        case "stayOnTop":
            item.state = staysOnTop ? .on : .off
            return true
        case "pictureInPicture":
            item.title = browser?.isInPictureInPicture == true ? "Exit Picture in Picture" : "Picture in Picture"
        case "toggleDeveloperMode":
            let on = hasPage && store.settings.isDeveloperMode(url: currentURL)
            item.title = on ? "Turn off Developer Mode for this Site" : "Turn on Developer Mode for this Site"
        default:
            break
        }
        return hasPage
    }
}
