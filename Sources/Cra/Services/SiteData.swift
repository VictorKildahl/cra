import CraCEF
import Foundation

extension CraBrowser {
    /// View ▸ Developer ▸ View Source (⌥⌘U): the page's view-source: in a new tab in front, for a
    /// Chromium page and a WebKit one alike. CEF's own CefFrame::ViewSource() opened no tab in Cra,
    /// so the command did nothing (#348).
    func viewSource() { viewSource(of: currentURL) }

    /// The source of `address` (the page's, or a frame's from the page's right-click menu) in a new
    /// tab in front. Chromium's own menu command opened a tab of the page itself (#348).
    func viewSource(of address: String) {
        guard let url = ViewSource.address(for: address) else { return }
        delegate?.browser(self, requestsNewTabWithURL: url, inBackground: false)
    }

    /// Sends the page menu's View Page Source and View Frame Source here (CraCEF's OnContextMenuCommand).
    static func installViewSourceHandler() {
        CraCEFRuntime.setViewSourceHandler { browser, url in
            MainActor.assumeIsolated { browser.viewSource(of: url) }
        }
    }

    /// Arc's "Clear Cookies and Refresh" and "Clear Cache and Refresh", and Cra's "Clear Site Data and Refresh"
    /// (#853): what SiteDataClearing says for the page in front, then its reload.
    func clearSiteDataAndReload(_ kind: SiteDataClearing.Kind) {
        guard let plan = SiteDataClearing.plan(kind, address: currentURL) else { return }
        let params = String(decoding: (try? JSONSerialization.data(withJSONObject: plan.call.params, options: .sortedKeys)) ?? Data("{}".utf8),
                            as: UTF8.self)
        CraLog.note("clearing \(kind.rawValue) for \(CraLog.host(currentURL)): \(plan.call.method) \(plan.call.params["storageTypes"] ?? "")")
        sendDevToolsMethod(plan.call.method, params: params) { [weak self] _, error in
            if let error { NSLog("Cra: clearing site data failed: %@", error) }
            DispatchQueue.main.async {
                switch plan.reload {
                case .normal: self?.reload()
                case .ignoringCache: self?.reloadIgnoringCache()
                }
            }
        }
    }
}
