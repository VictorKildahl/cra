import CraCore
import UIKit
import WebKit

protocol WebPageDelegate: AnyObject {
    func webPageDidChange(_ page: WebPage)
    func webPage(_ page: WebPage, didFinishLoading success: Bool)
    func webPage(_ page: WebPage, didDragBy drag: CGFloat)
    /// A finger came down on the page: the bottom bar's next travel is this drag's own.
    func webPageDidBeginDrag(_ page: WebPage)
    /// The page's content changed height: it may now fit its screen, or have more to scroll.
    func webPageDidResizeContent(_ page: WebPage)
    /// The finger let go at `velocity` points a second, positive with the page moving down: a
    /// quick flick picks the bottom bar's end, else it settles by the way it was last going.
    func webPageDidEndDrag(_ page: WebPage, velocity: CGFloat)
    /// The page reached its top: the bottom bar is always there.
    func webPageDidReachTop(_ page: WebPage)
    /// Pull to refresh: how far the page is pulled below its top, for the band behind it.
    func webPage(_ page: WebPage, didPull pull: CGFloat)
    /// The pull's finger let go: the band goes back to the status bar. `full` says the pull
    /// reached the refresh line, so the ring leaves with its own turn.
    func webPageDidEndPull(_ page: WebPage, full: Bool)
    /// A link that asked for a new window.
    func webPage(_ page: WebPage, openInNewTab url: URL)
    /// "Open in Background Tab" on a link: a tab in the row, the page stays on screen (#572).
    func webPage(_ page: WebPage, openInBackground url: URL)
    /// "Open in Incognito" on a link: a new private tab, shown (#572).
    func webPage(_ page: WebPage, openInIncognito url: URL)
    /// WebKit keeps the original navigation (including POST and window.opener) in this view.
    func webPage(_ page: WebPage, createPopupWith configuration: WKWebViewConfiguration, request: URLRequest) -> WKWebView?
    func webPageDidClose(_ page: WebPage)
    /// The query capsule on a Browse for Me page: edit the question.
    func webPage(_ page: WebPage, editQuery query: String)
}

/// One tab's web view and what the chrome needs to know about it.
final class WebPage: NSObject, WKNavigationDelegate, WKUIDelegate, UIScrollViewDelegate, WKScriptMessageHandler {
    let tabID: UUID
    let webView: WKWebView
    /// The tab is incognito: its links open incognito too.
    let isIncognito: Bool
    /// The page that opened this one as a popup. Weak: the store keeps an open tab's page
    /// (`TabStore.changed()` keeps a private popup's openers), and a closed or archived opener
    /// must not keep running off screen. WebKit then gives the popup a null `window.opener`.
    weak var opener: WebPage?
    let webKitOwnsInitialNavigation: Bool
    weak var delegate: WebPageDelegate?
    private var observations: [NSKeyValueObservation] = []
    /// Where the finger was on the last drag event, to read how far it has moved since: the bar's
    /// travel comes from the finger, so a bounce or a deceleration moves nothing.
    private var lastDragTranslation: CGFloat?
    private var pullHaptics = MobilePullHaptics()
    /// How far the page has been pulled down below its top, from the drag's own translation.
    private var pull: CGFloat = 0
    /// Where the drag began, in the window's coordinates: the pull is measured from there, so
    /// it follows the finger back up by the same amount it came down.
    private var pullStartTranslation: CGFloat = 0
    private var isPulling = false
    /// Pinning the content offset calls this delegate again; this stops the recursion.
    private var isPinningScroll = false

    /// Hosts whose unverifiable certificate the user chose to go on with, for this run of the app.
    static var certificateExceptions = MobileCertificateExceptions()
    /// Browse for Me is making this tab's page.
    var isBrowsing = false
    /// The page's saved history is being restored and the saved scroll is small: put it at the
    /// top when the scroll view reports the restored position.
    var restoresAtTop = false
    /// Called when the main frame's document has drawn (`drawnScript`): what a new tab from the search sheet waits
    /// for under its cover (`MobileSheetLeave`).
    var onDrawn: (() -> Void)?
    private(set) var isLoading = false
    private(set) var progress: Double = 0
    /// "Request Desktop Site": applied to every navigation of this tab while it is on.
    var wantsDesktopSite = false
    /// App Settings ▸ Open App Links in...
    var appLinks: () -> MobileAppLinks = { .nativeApp }
    /// The page shows Translate's words (MobileTranslate); a new page starts untranslated.
    var isTranslated = false
    /// What applies on a site: the app's settings, asked at every navigation.
    var siteOptions: (String?) -> MobileSiteOptions = { _ in MobileSiteOptions() }
    /// "Reload without ad blockers": the site this tab shows unblocked until it leaves it.
    private(set) var unblockedSite: String?
    /// Requests the blockers stopped on the page now showing.
    private(set) var blockedCount = 0
    private var countedHosts = Set<String>()
    /// The address the main frame last asked for, to tell WebKit's empty about:blank for an
    /// address it refuses from a page (`answerRefusalShownAsBlank`).
    private var requestedURL: URL?
    /// The address the error page is being put up at: its own navigation is let through.
    var errorPageAddress: URL?
    /// Captured before WebKit opens the link menu; its interaction location is no longer reliable afterwards.
    var linkPressPoint: CGPoint?

    init(tab: MobileTab, configuration supplied: WKWebViewConfiguration? = nil, opener: WebPage? = nil) {
        tabID = tab.id
        isIncognito = tab.isIncognito
        self.opener = opener
        webKitOwnsInitialNavigation = supplied != nil
        let configuration = supplied ?? WKWebViewConfiguration()
        if supplied == nil { configuration.websiteDataStore = tab.isIncognito ? .nonPersistent() : .default() }
        // The supplied related configuration can share its opener's content controller. Each
        // page needs its own one handler, script and site-specific blocker lists.
        configuration.userContentController = WKUserContentController()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.defaultWebpagePreferences.preferredContentMode = .mobile
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        // Opaque, so WebKit paints the page's canvas as Safari does: white for a page that sets no
        // colours and doesn't opt into dark, dark for one that does. See-through, a plain page's
        // black text sat on the app's black background in dark mode.
        webView.isOpaque = true
        webView.backgroundColor = .systemBackground
        // The app sets the page's scroll insets itself (the bar and the safe areas), so the
        // viewport does not change when the page is transformed behind the search sheet.
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        super.init()
        if let opener {
            siteOptions = opener.siteOptions
            appLinks = opener.appLinks
            wantsDesktopSite = opener.wantsDesktopSite
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        if UIDevice.current.userInterfaceIdiom == .pad {
            let press = UILongPressGestureRecognizer()
            press.delegate = self
            webView.addGestureRecognizer(press)
        }
        webView.scrollView.delegate = self
        // The bar rides the finger itself, not the scroll view's own events: a page with nothing
        // to scroll (one exactly as tall as the screen) still drags it away, and a resize of the
        // page while it moves cannot interrupt the bar's travel.
        webView.scrollView.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
        let controller = webView.configuration.userContentController
        controller.add(WeakScriptHandler(self), name: "craBlocked")
        controller.addUserScript(WKUserScript(source: Self.failedRequestScript, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        controller.add(WeakScriptHandler(self), name: "craDrawn")
        controller.addUserScript(WKUserScript(source: Self.drawnScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
            // The band behind the status bar takes these colours (MobileStatusBand, #657).
            webView.observe(\.themeColor) { [weak self] _, _ in self?.changed() },
            webView.observe(\.underPageBackgroundColor) { [weak self] _, _ in self?.changed() },
            // A page whose content shrinks until it fits its screen has nothing behind the bar
            // to hide, so its bar comes back (`MobileBarCollapse.contentChanged`).
            webView.scrollView.observe(\.contentSize) { [weak self] _, _ in
                guard let self else { return }
                self.delegate?.webPageDidResizeContent(self)
            },
        ]
        applyBlocking(for: URL(string: tab.url))
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
    /// a list or a filter covers.
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

    /// Tells the app once the document has been parsed and two frames have gone by, so its first paint is on screen:
    /// before that a committed page shows its bare canvas, white for one that hasn't yet said it is dark.
    /// A page Back or Forward restores from WebKit's back-forward cache is drawn again without being parsed again,
    /// so its `pageshow` tells the app as well, and the page swipe's picture comes off it then.
    private static let drawnScript = """
    (() => {
      const drawn = () => requestAnimationFrame(() => requestAnimationFrame(() => {
        try { window.webkit.messageHandlers.craDrawn.postMessage(location.href); } catch (e) {}
      }));
      if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', drawn, { once: true });
      else drawn();
      // A page brought back from the back-forward cache runs no script again, only this.
      addEventListener('pageshow', e => { if (e.persisted) drawn(); });
    })();
    """

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "craDrawn" {
            onDrawn?()
            return
        }
        guard unblockedSite == nil, let address = message.body as? String,
              ContentBlocker.shared.stops(url: address, onPage: webView.url?.host, with: siteOptions(webView.url?.host)),
              countedHosts.insert(address).inserted else { return }
        blockedCount += 1
        changed()
    }

    private func changed() {
        delegate?.webPageDidChange(self)
    }

    /// The page as a picture, for the tab stack and the tab cards, `height` tall: the whole page
    /// view, the part under the bar too, so a tab that grows into the page has its bottom from the
    /// first frame.
    func takeSnapshot(height: CGFloat, _ done: @escaping (UIImage?) -> Void) {
        // A web view that is hidden, or under a hidden page, snapshots black. That black picture
        // would then be the tab's preview until the next capture, so keep the last good one.
        var view: UIView? = webView
        while let current = view {
            if current.isHidden || current.alpha < 0.01 { return done(nil) }
            view = current.superview
        }
        guard webView.window != nil, webView.bounds.width > 0 else { return done(nil) }
        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Double(webView.bounds.width))
        let shown = min(max(0, height), webView.bounds.height)
        configuration.rect = CGRect(x: 0, y: 0, width: webView.bounds.width, height: shown)
        // A page laid out above the bar has a view shorter than a tab's picture: the picture
        // keeps the tab's shape, the strip the bar covers in the page's own background.
        let fill: UIColor = webView.underPageBackgroundColor ?? .systemBackground
        webView.takeSnapshot(with: configuration) { image, _ in
            guard let image, shown > 0, height > shown + 0.5 else { return done(image) }
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            let size = CGSize(width: image.size.width, height: (image.size.height * height / shown).rounded())
            done(UIGraphicsImageRenderer(size: size, format: format).image { context in
                fill.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                image.draw(at: .zero)
            })
        }
    }

    /// The picture kept of a history item, for the page swipe to show under the page and over the
    /// web view until the page it goes to has drawn (`HistoryPictures`).
    func historyPicture(for item: WKBackForwardListItem) -> UIImage? {
        HistoryPictures.shared.picture(for: item)
    }

    /// Keeps the page as it is on screen as the picture of the current history item. It draws what
    /// is already on screen, at 2× at most, without asking for a redraw, so it costs next to nothing
    /// as the page is left. It draws the page's container, the band the app puts behind the status
    /// bar included, as the page looks when it comes back; only while that container is at rest, not
    /// pushed back behind the search sheet or carried by a swipe, where the picture would be of
    /// something else. A web view that isn't on screen draws black or nothing, and that capture is
    /// dropped rather than shown as the page.
    func keepPictureOfCurrentItem() {
        var view: UIView? = webView
        while let current = view {
            if current.isHidden || current.alpha < 0.01 { return }
            view = current.superview
        }
        let page: UIView = webView.superview ?? webView
        let bounds = page.bounds
        guard webView.window != nil, bounds.width >= 1, bounds.height >= 1, page.transform == .identity else { return }
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = min(format.scale, 2)
        format.opaque = true
        let picture = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            page.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        keepPicture(picture)
    }

    /// Keeps `picture`, the page as it is on screen now, for the current history item.
    func keepPicture(_ picture: UIImage) {
        guard let item = webView.backForwardList.currentItem, !picture.looksBlank else { return }
        HistoryPictures.shared.keep(picture, for: item)
    }

    /// Lets a main-frame navigation go ahead, then keeps the picture of the page it leaves: that
    /// page stays on screen until the new one commits, and deciding first keeps the navigation from
    /// waiting on the capture. A jump to a fragment of the same page leaves nothing behind.
    private func allowMainFrame(_ navigationAction: WKNavigationAction, preferences: WKWebpagePreferences,
                                decisionHandler: (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        decisionHandler(.allow, preferences)
        // Back and Forward are left out: WebKit may already count the page gone to as the current item, which would
        // file this page's picture under it, and the swipe keeps the page's picture as it starts anyway. So is a
        // reload, which leaves the page where it is (and a pull to refresh has it pulled down as it starts).
        guard navigationAction.targetFrame?.isMainFrame == true,
              navigationAction.navigationType != .backForward, navigationAction.navigationType != .reload,
              let target = navigationAction.request.url,
              !MobileHistoryPictures.isFragmentJump(from: webView.url?.absoluteString, to: target.absoluteString) else { return }
        keepPictureOfCurrentItem()
    }

    /// The icons the page names for itself, best first (`MobileFavicons.bestFirst`): its own
    /// favicon, in its own shape, before the touch icon, which is an app-icon square.
    func iconCandidates(_ done: @escaping ([String]) -> Void) {
        guard let page = webView.url else { return done([]) }
        let script = """
        [...document.querySelectorAll('head link[rel][href]')]
          .map(l => ({rel: l.rel, href: l.href, sizes: l.getAttribute('sizes') || '', type: l.type || ''}))
        """
        webView.evaluateJavaScript(script) { value, _ in
            let links = (value as? [[String: String]] ?? []).compactMap { link in
                link["rel"].flatMap { rel in
                    link["href"].map { MobileFavicons.IconLink(rel: rel, href: $0, sizes: link["sizes"], type: link["type"]) }
                }
            }
            done(MobileFavicons.bestFirst(links, page: page))
        }
    }

    // MARK: Navigation

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        preferences.preferredContentMode = wantsDesktopSite ? .desktop : .mobile
        if navigationAction.shouldPerformDownload {
            return decisionHandler(.download, preferences)
        }
        // A Browse for Me page's follow-up chip: a new Browse for Me in a tab of its own.
        if let url = navigationAction.request.url, url.scheme == "cra-edit" {
            if navigationAction.navigationType == .linkActivated, let query = MobileBrowseForMe.query(fromEditAddress: url.absoluteString) {
                delegate?.webPage(self, editQuery: query)
            }
            return decisionHandler(.cancel, preferences)
        }
        if let url = navigationAction.request.url, url.scheme == "cra-browse" {
            if navigationAction.navigationType == .linkActivated { delegate?.webPage(self, openInNewTab: url) }
            return decisionHandler(.cancel, preferences)
        }
        // The error page itself, at the address that failed: not answered again.
        let isErrorPage = navigationAction.request.url != nil && navigationAction.request.url == errorPageAddress
        if isErrorPage { errorPageAddress = nil }
        if let url = navigationAction.request.url, !isErrorPage {
            // mailto:, tel:, an app's own scheme: to that app, before WebKit fails it with -1002.
            // No target frame is a new window, which the page's main frame is asking for.
            let tapped = navigationAction.navigationType == .linkActivated || navigationAction.navigationType == .formSubmitted
            switch MobileExternalLinks.answer(address: url.absoluteString, isMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
                                              isUserGesture: tapped) {
            case .load: break
            case .stay: return decisionHandler(.cancel, preferences)
            case .open:
                decisionHandler(.cancel, preferences)
                return openInApp(url)
            case .ask(let app):
                decisionHandler(.cancel, preferences)
                return askToOpenInApp(url, app: app)
            }
            // An address WebKit refuses: the error page now, rather than after the empty
            // about:blank iOS 26.5's WebKit commits for it, which Back then landed on.
            if MobileLoadFailure.answersBeforeLoading(url.absoluteString, isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
                                                      isBackForward: navigationAction.navigationType == .backForward) {
                decisionHandler(.cancel, preferences)
                return answerRefusal(of: url)
            }
        }
        if navigationAction.targetFrame?.isMainFrame == true {
            requestedURL = navigationAction.request.url
            applyBlocking(for: navigationAction.request.url)
        }
        // "Open App Links in... Native App": a tapped link to another site goes to its app when
        // one claims it (universal links only); otherwise it loads here.
        if let url = navigationAction.request.url,
           appLinks().offersApp(isLinkTap: navigationAction.navigationType == .linkActivated,
                                isMainFrame: navigationAction.targetFrame?.isMainFrame == true,
                                from: webView.url?.absoluteString, to: url.absoluteString) {
            // Exactly one answer: the system's, or loading here if it hasn't answered in time.
            var answered = false
            let answer: (Bool) -> Void = { opened in
                guard !answered else { return }
                answered = true
                if opened { return decisionHandler(.cancel, preferences) }
                self.allowMainFrame(navigationAction, preferences: preferences, decisionHandler: decisionHandler)
            }
            UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in answer(opened) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { answer(false) }
            return
        }
        allowMainFrame(navigationAction, preferences: preferences, decisionHandler: decisionHandler)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        blockedCount = 0
        countedHosts = []
        isTranslated = false
        changed()
        answerRefusalShownAsBlank(requested: requestedURL)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        delegate?.webPage(self, didFinishLoading: true)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        delegate?.webPage(self, didFinishLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        answerLoadFailure(error)
        delegate?.webPage(self, didFinishLoading: false)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        return delegate?.webPage(self, createPopupWith: configuration, request: navigationAction.request)
    }

    func webViewDidClose(_ webView: WKWebView) {
        delegate?.webPageDidClose(self)
    }

    // MARK: Scrolling

    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        // Each pull starts from silence, and warming the generator keeps the first tick prompt.
        pull = 0
        isPulling = false
        pullHaptics.reset()
        PressHaptics.preparePull()
        // A finger on the page ends any wait for a place being put back.
        restoresAtTop = false
    }

    /// The finger on the page: the bar's travel comes from here, a point for a point.
    @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            lastDragTranslation = 0
            delegate?.webPageDidBeginDrag(self)
        case .changed:
            let translation = dragTranslation(of: webView.scrollView)
            if let last = lastDragTranslation, last != translation {
                // The finger moving up scrolls the page down and closes the bar: positive.
                delegate?.webPage(self, didDragBy: last - translation)
            }
            lastDragTranslation = translation
        case .ended, .cancelled:
            lastDragTranslation = nil
            // A finger moving up sends the page down: positive, as for the drag. A touch taken
            // away was never a flick.
            let velocity = pan.state == .ended ? -pan.velocity(in: webView.window ?? webView).y : 0
            delegate?.webPageDidEndDrag(self, velocity: velocity)
        default:
            break
        }
    }

    /// The drag's vertical translation in the window, which does not move when the page's frame
    /// does: the pull reads the finger exactly, both down and back up.
    private func dragTranslation(of scrollView: UIScrollView) -> CGFloat {
        scrollView.panGestureRecognizer.translation(in: webView.window ?? webView).y
    }

    /// Puts the content back at its top, where the page's frame begins: a pull moves the frame,
    /// not the content, so the scroll view is never left scrolled.
    private func pinToTop(_ scrollView: UIScrollView) {
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: -scrollView.adjustedContentInset.top),
                                    animated: false)
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard isPulling else { return }
        // A slow pull's last scroll event can be short of where the finger actually let go.
        pull = max(0, max(pull, dragTranslation(of: scrollView) - pullStartTranslation))
        // Put the ring at the release's pull before it goes back, so a full one bumps.
        delegate?.webPage(self, didPull: pull)
        // Pull to refresh acts on release: dragged back up first, nothing happens.
        let full = MobileSwipe.refreshes(pullAtRelease: pull)
        if full {
            PressHaptics.pullRefresh()
            webView.reload()
        }
        // The line's tick may not have played before a slow pull's finger lifted; play it last.
        if let tick = pullHaptics.tickOnRelease(pull: pull) {
            PressHaptics.pullDetent(tick)
        }
        // The page's content stays at its top; the page's frame is what moved, and it goes back.
        pinToTop(scrollView)
        pull = 0
        isPulling = false
        pullHaptics.reset()
        delegate?.webPageDidEndPull(self, full: full)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
        // A page being put back reports places that are not its saved one on the way (the empty
        // page's own bounce, the load's jumps). The saved place is a small positive scroll, and
        // that is the one to put back at the top; a finger on the page ends the wait
        // (`scrollViewWillBeginDragging`), so a later scroll is never mistaken for it.
        if restoresAtTop, offset > 0.5, offset < CGFloat(PageHistory.restoreAtTopBelow) {
            restoresAtTop = false
            pinToTop(scrollView)
            return
        }
        // The top of a page always has its bar, however the page got there — but not while a
        // finger is on the page, which moves the bar itself. A page that fits has nothing to
        // scroll, so its bar cannot be away in the first place.
        if !scrollView.isDragging, offset <= 0 {
            delegate?.webPageDidReachTop(self)
        }
        // A downward drag at the top moves the page's frame, not its content: the scroll view's
        // own downward movement is gathered, and its content is pinned back at the top.
        if scrollView.isTracking, isPulling || offset < -0.5 {
            if !isPulling {
                // The pull begins where the page reaches its top, so an earlier scroll up the
                // page does not have to be retraced, and the overshoot that brought it there
                // already counts as pull.
                pullStartTranslation = dragTranslation(of: scrollView) + offset
            }
            isPulling = true
            guard !isPinningScroll else { return }
            let translation = dragTranslation(of: scrollView)
            let pull = max(0, translation - pullStartTranslation)
            if MobileSwipe.pullHandsOff(pull: pull) {
                // Pushing back up past the top hands the rest of the drag to the page's own
                // scrolling, so it continues into a normal scroll without a second gesture.
                isPulling = false
                self.pull = 0
                pullHaptics.reset()
                pinToTop(scrollView)
                delegate?.webPageDidEndPull(self, full: false)
                return
            }
            self.pull = pull
            if abs(offset) > 0.01 {
                isPinningScroll = true
                pinToTop(scrollView)
                isPinningScroll = false
            }
            if let tick = pullHaptics.tick(pull: pull) {
                PressHaptics.pullDetent(tick)
            }
            delegate?.webPage(self, didPull: pull)
            return
        }
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
