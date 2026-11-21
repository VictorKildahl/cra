import CraCore
import UIKit
import WebKit

/// What every browser has to answer for a page: its dialogs, its sign-in prompts, a certificate
/// it can't check, a file it wants to hand over, and a long press on a link.
extension WebPage: WKDownloadDelegate, UIGestureRecognizerDelegate {
    private var presenter: UIViewController? {
        var top = webView.window?.rootViewController
        while let next = top?.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    private var pageName: String {
        webView.url?.host.map(MobileSettings.siteKey) ?? "This page"
    }

    // MARK: JavaScript dialogs

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        guard let presenter else { return completionHandler() }
        let alert = UIAlertController(title: pageName, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        guard let presenter else { return completionHandler(false) }
        let alert = UIAlertController(title: pageName, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
        presenter.present(alert, animated: true)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        guard let presenter else { return completionHandler(nil) }
        let alert = UIAlertController(title: pageName, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(alert.textFields?.first?.text ?? "") })
        presenter.present(alert, animated: true)
    }

    // MARK: Sign-in prompts and certificates

    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            // A host the user chose to go on to keeps working until the app quits.
            if WebPage.certificateExceptions.allows(space.host), let trust = space.serverTrust {
                return completionHandler(.useCredential, URLCredential(trust: trust))
            }
            completionHandler(.performDefaultHandling, nil)
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest:
            guard let presenter, challenge.previousFailureCount < 3 else { return completionHandler(.cancelAuthenticationChallenge, nil) }
            let alert = UIAlertController(title: "Sign in to \(space.host)", message: space.realm, preferredStyle: .alert)
            alert.addTextField { $0.placeholder = "User Name"; $0.autocapitalizationType = .none; $0.autocorrectionType = .no }
            alert.addTextField { $0.placeholder = "Password"; $0.isSecureTextEntry = true }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(.cancelAuthenticationChallenge, nil) })
            alert.addAction(UIAlertAction(title: "Sign In", style: .default) { _ in
                let credential = URLCredential(user: alert.textFields?[0].text ?? "", password: alert.textFields?[1].text ?? "", persistence: .forSession)
                completionHandler(.useCredential, credential)
            })
            presenter.present(alert, animated: true)
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

    /// A page that failed before any of it showed (`MobileLoadFailure`): a certificate warning, or
    /// a page that says it couldn't load and why. Before #568 anything but a certificate error left
    /// the tab a blank white page.
    func answerLoadFailure(_ error: Error) {
        let failure = error as NSError
        let url = (failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (failure.userInfo[NSURLErrorFailingURLStringErrorKey] as? String).flatMap(URL.init(string:))
        // Another app's address (mailto: and the like) that got through to WebKit says nothing.
        let answer = MobileLoadFailure.answer(domain: failure.domain, code: failure.code, address: url?.absoluteString)
        if answer == .nothing || (answer == .certificateWarning && offerCertificateBypass(for: failure)) { return }
        guard let url else { return }
        // At the failing address, so the address shows it and Reload tries it again.
        errorPageAddress = url
        webView.loadSimulatedRequest(URLRequest(url: url),
                                     responseHTML: MobileLoadFailure.page(host: url.host ?? url.absoluteString, message: failure.localizedDescription))
    }

    /// iOS 26.5's WebKit answers an address it refuses (a restricted port, an address of only
    /// zeros) with an empty about:blank instead of failing: answer it as the 103 a newer WebKit
    /// fails it with (`MobileLoadFailure.isRefusedAsBlank`). A load the tab starts is answered
    /// before that (`answerRefusal(of:)`); this is left for going back or forward to one.
    func answerRefusalShownAsBlank(requested: URL?) {
        guard let requested, let committed = webView.url?.absoluteString,
              MobileLoadFailure.isRefusedAsBlank(requested: requested.absoluteString, committed: committed) else { return }
        answerRefusal(of: requested)
    }

    /// The error page for an address WebKit refuses, with the 103 a newer WebKit fails it with.
    func answerRefusal(of url: URL) {
        answerLoadFailure(NSError(domain: MobileLoadFailure.webKitErrorDomain, code: MobileLoadFailure.restrictedPortCode, userInfo: [
            NSURLErrorFailingURLErrorKey: url, NSLocalizedDescriptionKey: MobileLoadFailure.restrictedPortMessage,
        ]))
    }

    // MARK: Other apps' addresses

    /// To the app that handles it (`MobileExternalLinks`). iOS asks before a call itself. With no
    /// app for it, nothing happens and the page stays as it is.
    func openInApp(_ url: URL) {
        UIApplication.shared.open(url)
    }

    /// A page that sent itself to another app's address without a tap: Safari's question first.
    /// Nothing if the page isn't on screen, or if the question is already up (a page repeating
    /// the redirect gets one question).
    func askToOpenInApp(_ url: URL, app: String?) {
        guard let presenter, !(presenter is UIAlertController) else { return }
        let alert = UIAlertController(title: MobileExternalLinks.question(app: app), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: MobileExternalLinks.cancelButton, style: .cancel))
        alert.addAction(UIAlertAction(title: MobileExternalLinks.openButton, style: .default) { [weak self] _ in self?.openInApp(url) })
        presenter.present(alert, animated: true)
    }

    /// A page whose certificate can't be verified: say so, and let the user go on if they insist
    /// (Arc Search 1.12's bypass). Returns whether the warning showed.
    private func offerCertificateBypass(for failure: NSError) -> Bool {
        guard let url = failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL, let host = url.host, let presenter else { return false }
        let alert = UIAlertController(title: MobileCertificateExceptions.warningTitle(host: host),
                                      message: MobileCertificateExceptions.warningMessage(host: host), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Go Back", style: .cancel))
        alert.addAction(UIAlertAction(title: "Continue Anyway", style: .destructive) { [weak self] _ in
            WebPage.certificateExceptions.allow(host)
            self?.webView.load(URLRequest(url: url))
        })
        presenter.present(alert, animated: true)
        return true
    }

    // MARK: Downloads

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        let attachment = disposition.lowercased().hasPrefix("attachment")
        decisionHandler(!navigationResponse.canShowMIMEType || attachment ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = DownloadManager.shared
    }

    // Unused: every download is handed to the manager. Here so the page can stand in as a delegate type.
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        DownloadManager.shared.download(download, decideDestinationUsing: response, suggestedFilename: suggestedFilename, completionHandler: completionHandler)
    }

    // MARK: Long press on a link

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        linkPressPoint = touch.location(in: webView)
        // Observe the initial touch without competing with WebKit's own recognizers.
        return false
    }

    func webView(_ webView: WKWebView, contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        guard let url = elementInfo.linkURL else { return nil }
        var sourceRect: CGRect?
        if let point = linkPressPoint {
            // DOM viewport coordinates exclude the web view's safe-area content inset.
            let inset = webView.scrollView.adjustedContentInset
            let result = try? await webView.callAsyncJavaScript("""
                const scale = window.innerWidth / width;
                const link = document.elementFromPoint(x * scale, y * scale)?.closest('a');
                if (!link) return null;
                const range = document.createRange();
                range.selectNodeContents(link);
                const rect = range.getBoundingClientRect();
                return [rect.x / scale, rect.y / scale, rect.width / scale, rect.height / scale];
                """, arguments: ["x": point.x - inset.left, "y": point.y - inset.top, "width": webView.bounds.width],
                in: nil, contentWorld: .defaultClient)
            if let rect = result as? [Double], rect.count == 4 {
                sourceRect = CGRect(x: rect[0] + inset.left, y: rect[1] + inset.top, width: rect[2], height: rect[3])
            }
        }
        let items = MobileLinkMenu.items(incognito: isIncognito)
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: items.map { item in
                UIAction(title: item.title, image: UIImage(systemName: item.symbol)) { _ in self?.linkMenu(picked: item, url: url, from: sourceRect) }
            })
        }
    }

    private func linkMenu(picked item: MobileLinkMenu.Item, url: URL, from sourceRect: CGRect?) {
        switch item {
        case .open:
            webView.load(URLRequest(url: url))
        case .openInNewTab:
            delegate?.webPage(self, openInNewTab: url)
        case .openInBackgroundTab:
            delegate?.webPage(self, openInBackground: url)
        case .openInIncognito:
            delegate?.webPage(self, openInIncognito: url)
        case .copyLink:
            UIPasteboard.general.string = CleanURL.withoutTrackers(url.absoluteString)
        case .share:
            guard let presenter else { return }
            let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = webView
            if let sourceRect {
                share.popoverPresentationController?.sourceRect = sourceRect
            }
            presenter.present(share, animated: true)
        }
    }
}
