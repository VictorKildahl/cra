import AppKit
import CraCEF

/// Pop-ups Chromium's pop-up blocker held back (BlockedPopups, scripts/cef-patches/blocked-popups.patch):
/// Cra keeps the list per page for the toolbar's button and the sidebar's URL field, and opens a
/// pop-up as a new tab below the page, the way a link from it opens.
extension BrowserManager {
    func browser(_ browser: CraBrowser, didChangeBlockedPopups ids: [NSNumber], urls: [String]) {
        guard let id = tabID(of: browser), let rt = runtimes[id] else { return }
        let before = rt.blockedPopups.waiting.count
        rt.blockedPopups.update(ids: ids.map(\.intValue), urls: urls)
        let after = rt.blockedPopups.waiting.count
        if after > before {
            CraLog.note("page \(browser.isIncognito ? "(incognito)" : CraLog.host(browser.currentURL)) blocked \(after - before) pop-up\(after - before == 1 ? "" : "s")")
        }
        if after != before { delegate?.browserManagerDidUpdate(id) }
    }

    /// The page's blocked pop-ups still to open.
    func blockedPopups(_ id: UUID) -> [BlockedPopups.Popup] { runtimes[id]?.blockedPopups.waiting ?? [] }

    /// Opens one blocked pop-up (`popup` is Chromium's id) or all of them, as tabs below the page in
    /// the page's order; the first one is shown.
    func openBlockedPopups(_ id: UUID, popup: Int? = nil) {
        guard let rt = runtimes[id] else { return }
        let picked = rt.blockedPopups.open(popup)
        guard !picked.isEmpty else { return }
        // Each new tab goes right below the page, so the last one opens first.
        for (index, p) in picked.enumerated().reversed() {
            openLinkTab(p.url, from: id, inBackground: index > 0)
        }
        delegate?.browserManagerDidUpdate(id)
    }

    /// Chrome's pop-up setting for the page's site.
    func popupsAllowed(_ id: UUID) -> Bool { runtimes[id]?.browser.popupsAllowed ?? false }

    func setPopupsAllowed(_ id: UUID, _ allowed: Bool) {
        guard let rt = runtimes[id] else { return }
        rt.browser.setPopupsAllowed(allowed)
        CraLog.note("page \(rt.browser.isIncognito ? "(incognito)" : CraLog.host(rt.browser.currentURL)) pop-ups \(allowed ? "always allowed" : "blocked again")")
        delegate?.browserManagerDidUpdate(id)
    }
}
