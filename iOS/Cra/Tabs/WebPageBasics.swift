import CraCore
import UIKit
import WebKit

/// What every browser has to answer for a page: its dialogs, its sign-in prompts, a certificate
/// it can't check, a file it wants to hand over, and a long press on a link.
extension WebPage: WKDownloadDelegate {
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

    /// A page whose certificate can't be verified: say so, and let the user go on if they insist
    /// (Arc Search 1.12's bypass). Returns whether the error was one of those.
    func offerCertificateBypass(for error: Error) -> Bool {
        let failure = error as NSError
        let codes = [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
                     NSURLErrorServerCertificateNotYetValid, NSURLErrorSecureConnectionFailed]
        guard failure.domain == NSURLErrorDomain, codes.contains(failure.code),
              let url = failure.userInfo[NSURLErrorFailingURLErrorKey] as? URL, let host = url.host, let presenter else { return false }
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

    func webView(_ webView: WKWebView, contextMenuConfigurationFor elementInfo: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        guard let url = elementInfo.linkURL else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            UIMenu(children: [
                UIAction(title: "Open", image: UIImage(systemName: "arrow.up.right")) { _ in self?.webView.load(URLRequest(url: url)) },
                UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { _ in
                    guard let self else { return }
                    self.delegate?.webPage(self, openInNewTab: url)
                },
                UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
                    UIPasteboard.general.string = CleanURL.withoutTrackers(url.absoluteString)
                },
                UIAction(title: "Share...", image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    guard let self, let presenter = self.presenter else { return }
                    let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                    share.popoverPresentationController?.sourceView = self.webView
                    presenter.present(share, animated: true)
                },
            ])
        }
    }
}
