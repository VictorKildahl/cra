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
final class WebPage: NSObject, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate {
    let tabID: UUID
    let webView: WKWebView
    weak var delegate: WebPageDelegate?
    private var observations: [NSKeyValueObservation] = []
    private var lastOffset: CGFloat = 0

    private(set) var isLoading = false
    private(set) var progress: Double = 0
    /// "Request Desktop Site": applied to every navigation of this tab while it is on.
    var wantsDesktopSite = false

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
        webView.load(URLRequest(url: url))
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
        decisionHandler(.allow, preferences)
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
