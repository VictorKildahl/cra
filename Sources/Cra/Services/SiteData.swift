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

    /// Arc's "Clear Cookies and Refresh" and "Clear Cache and Refresh": this site's cookies, or
    /// the HTTP cache, then a reload.
    func clearSiteDataAndReload(cookies: Bool) {
        guard let u = URL(string: currentURL), let host = u.host, let scheme = u.scheme else { return }
        let done: (String?, String?) -> Void = { [weak self] _, error in
            if let error { NSLog("Cra: clearing site data failed: %@", error) }
            DispatchQueue.main.async { self?.reload() }
        }
        if cookies {
            let params = ["origin": "\(scheme)://\(host)\(u.port.map { ":\($0)" } ?? "")", "storageTypes": "cookies"]
            let json = String(decoding: (try? JSONSerialization.data(withJSONObject: params)) ?? Data("{}".utf8), as: UTF8.self)
            sendDevToolsMethod("Storage.clearDataForOrigin", params: json, completion: done)
        } else {
            sendDevToolsMethod("Network.clearBrowserCache", params: "{}", completion: done)
        }
    }
}
