import CraCore
import UIKit
import WebKit

protocol WebPageDelegate: AnyObject {
    func webPageDidChange(_ page: WebPage)
    func webPage(_ page: WebPage, didFinishLoading success: Bool)
    func webPage(_ page: WebPage, didScrollBy delta: CGFloat, atTop: Bool)
    /// A link that asked for a new window.
    func webPage(_ page: WebPage, openInNewTab url: URL)
}

/// One tab's web view and what the chrome needs to know about it.
final class WebPage: NSObject, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate, WKScriptMessageHandler {
    let tabID: UUID
    let webView: WKWebView
    weak var delegate: WebPageDelegate?
    private var observations: [NSKeyValueObservation] = []
    private var lastOffset: CGFloat = 0

    private(set) var isLoading = false
    private(set) var progress: Double = 0
    /// "Request Desktop Site": applied to every navigation of this tab while it is on.
    var wantsDesktopSite = false
    /// What applies on a site: the app's settings, asked at every navigation.
    var siteOptions: (String?) -> MobileSiteOptions = { _ in MobileSiteOptions() }
    /// "Reload without ad blockers": the site this tab shows unblocked until it leaves it.
    private(set) var unblockedSite: String?
    /// Requests the blockers stopped on the page now showing.
    private(set) var blockedCount = 0
    private var countedHosts = Set<String>()

    init(tab: MobileTab) {
        tabID = tab.id
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = tab.isIncognito ? .nonPersistent() : .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.delegate = self
        let controller = webView.configuration.userContentController
        controller.add(WeakScriptHandler(self), name: "craBlocked")
        controller.addUserScript(WKUserScript(source: Self.failedRequestScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        observations = [
            webView.observe(\.title) { [weak self] _, _ in self?.changed() },
            webView.observe(\.url) { [weak self] _, _ in self?.changed() },
            webView.observe(\.estimatedProgress) { [weak self] view, _ in
                self?.progress = view.estimatedProgress
                self?.changed()
            },
            webView.observe(\.isLoading) { [weak self] view, _ in
                self?.isLoading = view.isLoading
                self?.changed()
            },
        ]
    }

    func load(_ address: String) {
        guard let url = URL(string: address) else { return }
        // The very first page waits for the block lists; after that they are there at once.
        ContentBlocker.shared.whenReady { [weak self] in self?.webView.load(URLRequest(url: url)) }
    }

    /// Shows the current site without ad, tracker or cookie-banner blocking until the tab leaves it.
    func reloadWithoutBlockers() {
        unblockedSite = webView.url?.host.map(MobileSettings.siteKey)
        webView.reload()
    }

    private func applyBlocking(for url: URL?) {
        let site = url?.host.map(MobileSettings.siteKey)
        if site != unblockedSite { unblockedSite = nil }
        let options = unblockedSite == nil ? siteOptions(url?.host) : nil
        ContentBlocker.shared.apply(options, to: webView.configuration.userContentController)
    }

    /// Reports the address of every request that fails, from every frame. Requests stopped by a
    /// block rule fail like any other; `userContentController(_:didReceive:)` keeps the ones
    /// whose host is on the list.
    private static let failedRequestScript = """
    (() => {
      const report = url => { try { window.webkit.messageHandlers.craBlocked.postMessage(String(url)); } catch (e) {} };
      window.addEventListener('error', event => {
        const node = event.target;
        if (node && node !== window && (node.src || node.href)) report(node.src || node.href);
      }, true);
      const nativeFetch = window.fetch;
      if (nativeFetch) window.fetch = function (input, init) {
        const url = typeof input === 'string' ? input : (input && input.url) || '';
        return nativeFetch.call(this, input, init).catch(error => { report(new URL(url, location.href).href); throw error; });
      };
      const open = XMLHttpRequest.prototype.open;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.addEventListener('error', () => { try { report(new URL(url, location.href).href); } catch (e) {} });
        return open.apply(this, arguments);
      };
    })();
    """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard unblockedSite == nil, let address = message.body as? String, let host = URL(string: address)?.host,
              ContentBlocker.shared.list.stops(host: host, with: siteOptions(webView.url?.host)),
              countedHosts.insert(address).inserted else { return }
        blockedCount += 1
        changed()
    }

    private func changed() {
        delegate?.webPageDidChange(self)
    }

    /// The page as a picture, for the tab stack and the tab cards.
    func takeSnapshot(_ done: @escaping (UIImage?) -> Void) {
        guard webView.window != nil, webView.bounds.width > 0 else { return done(nil) }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width))
        webView.takeSnapshot(with: configuration) { image, _ in done(image) }
    }

    /// The icons the page names for itself, largest first.
    func iconCandidates(_ done: @escaping ([String]) -> Void) {
        let script = """
        (() => {
          const links = [...document.querySelectorAll('link[rel~="apple-touch-icon"], link[rel~="apple-touch-icon-precomposed"], link[rel~="icon"]')];
          const size = l => parseInt((l.getAttribute('sizes') || '0').split('x')[0]) || (l.rel.includes('apple') ? 180 : 16);
          return links.filter(l => l.href && !l.href.endsWith('.svg')).sort((a, b) => size(b) - size(a)).slice(0, 3).map(l => l.href);
        })()
        """
        webView.evaluateJavaScript(script) { value, _ in done(value as? [String] ?? []) }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = wantsDesktopSite ? .desktop : .mobile
        if navigationAction.targetFrame?.isMainFrame == true {
            applyBlocking(for: navigationAction.request.url)
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        blockedCount = 0
        countedHosts = []
        changed()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        delegate?.webPage(self, didFinishLoading: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        delegate?.webPage(self, didFinishLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        delegate?.webPage(self, didFinishLoading: false)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { delegate?.webPage(self, openInNewTab: url) }
        return nil
    }

    // MARK: Scrolling

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        let delta = offset - lastOffset
        lastOffset = offset
        guard scrollView.isTracking || scrollView.isDecelerating else { return }
        delegate?.webPage(self, didScrollBy: delta, atTop: offset <= 0)
    }
}

/// A script message handler that does not keep its page alive (the controller holds handlers strongly).
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) { self.target = target }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
