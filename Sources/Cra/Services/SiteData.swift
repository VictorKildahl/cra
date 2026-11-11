import CraCEF
import Foundation

extension CraBrowser {
    /// View ▸ Developer ▸ View Source (⌥⌘U): the page's view-source: in a new tab in front, for a
    /// Chromium page and a WebKit one alike. CEF's own CefFrame::ViewSource() opened no tab in Cra,
    /// so the command did nothing (#348).
    func viewSource() {
        guard let url = ViewSource.address(for: currentURL) else { return }
        delegate?.browser(self, requestsNewTabWithURL: url, inBackground: false)
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
