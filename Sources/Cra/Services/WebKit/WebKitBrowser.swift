import AppKit
import CraCEF
import WebKit

/// A page drawn by the Mac's WebKit instead of Chromium, for the sites in ProtectedMediaSites:
/// WebKit plays their DRM with Apple's FairPlay, which needs no certificate (Chromium's Widevine
/// needs a paid Verified Media Path one for these services).
///
/// It is a CraBrowser, so BrowserManager, split view, Little Windows, Peek, tab sleeping, the
/// tab switcher, the sidebar player and Picture in Picture drive it exactly like a Chromium page:
/// it hosts like Alloy (its view in `containerView`, no `hostWindow`), sends the same delegate
/// callbacks, and answers the few DevTools Protocol methods Cra calls (`sendDevToolsMethod`) from
/// WebKit's own API. What WebKit can't do answers an error, and each caller already has a path
/// for that (a page Chromium can't discard closes instead, for one).
///
/// Not here: Chrome extensions (WebKit pages have none), Chromium's site settings, content
/// blocking and HTTPS-Only (Chromium's network stack), Chrome's DevTools (WebKit's Web Inspector
/// opens instead). Cookies are WebKit's own, per profile (WebKitStores): a service is signed into
/// once more the first time it opens here.
final class WebKitBrowser: CraBrowser, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    private let container: NSView
    private(set) var webView: CraWebView?
    private let incognitoPage: Bool
    private let profile: String?
    /// The address before the web view has one (a page not created yet, a failed load).
    private var pendingURL: String
    private var failedURL: String?
    private var created = false
    private var closed = false
    private var pageClosedItself = false
    private var committed = false
    /// The page's own navigation to another app's address asked already (decidePolicyFor).
    private var askedForAppOnThisPage = false
    private var lastStatus = 0
    private var lastLoadingState: [Bool] = []
    private var observations: [NSKeyValueObservation] = []
    private var observesPlayingAudio = false
    private var audibleHold = AudibleHold()
    private var audibleOff: DispatchWorkItem?
    private var capturing = false
    /// Muted before the web view existed (a popup host's): applied in makeWebView (#387).
    private var audioMuted = false
    /// The service this page opened for ("Spotify"), kept while it signs in elsewhere: what the
    /// toast, the Site Control Center and the dimmed extension buttons name (PageEngines).
    var serviceName = ""
    /// WebKit took the page to its own fullscreen window (Chromium's fullscreen is Cra's window).
    private(set) var isContentFullscreen = false
    private var inPictureInPicture = false
    private var pictureInPicturePlaying = false
    private var hoverURL = ""
    /// Page.getNavigationHistory's entry ids for this page's back-forward items (#416).
    private var historyIDs: [ObjectIdentifier: Int] = [:]
    private var historyItems: [Int: WKBackForwardListItem] = [:]
    private var findQuery = ""
    private var findCount = 0
    private var findIndex = 0
    private var messages: ScriptMessageProxy?
    /// Downloads in flight, with their info for the sidebar.
    private var downloads: [ObjectIdentifier: (download: WKDownload, info: CraDownloadInfo, progress: NSKeyValueObservation?)] = [:]
    private static var nextDownloadID: UInt32 = 0x7000_0000

    /// Cra's isolated world: PageScript's own script, plus what WebKit doesn't report natively.
    static let world = WKContentWorld.world(name: PageScript.world)

    override convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool, profilePath: String?) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: profilePath, interactionState: nil)
    }

    /// `interactionState`: the back and forward list WKWebView saved for this tab (PageHistory,
    /// #273). It goes in instead of loading `url`, and WebKit loads its current page.
    init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool, profilePath: String?, interactionState: Data?) {
        container = NSView(frame: frame)
        incognitoPage = incognito
        profile = incognito ? nil : profilePath
        pendingURL = url ?? ""
        super.init()
        self.delegate = delegate
        container.wantsLayer = true
        container.autoresizesSubviews = true
        container.layer?.backgroundColor = CraBrowser.pageCanvasColor.cgColor
        // nil: a popup host, filled by adoptPopup(configuration:) when WebKit opens the popup.
        if let url {
            MainActor.assumeIsolated {
                makeWebView(configuration: nil)
                if let interactionState, !incognito {
                    webView?.interactionState = interactionState
                }
                let list = webView?.backForwardList
                let count = list?.currentItem == nil ? 0 : (list?.backList.count ?? 0) + 1 + (list?.forwardList.count ?? 0)
                if count == 0 { load(url) }
                // Reported once the page is its tab's (BrowserManager registers it after init).
                if interactionState != nil {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.delegate?.browser?(self, didRestoreHistoryEntries: count, error: count > 0 ? nil : "WebKit couldn't read it")
                    }
                }
            }
        }
    }

    /// The back and forward list as WKWebView saves it (PageHistory), nil before there is a page.
    var savedInteractionState: Data? {
        MainActor.assumeIsolated { webView?.backForwardList.currentItem == nil ? nil : webView?.interactionState as? Data }
    }

    override convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: false, profilePath: nil)
    }

    override convenience init(frame: NSRect, url: String?, delegate: CraBrowserDelegate?, incognito: Bool) {
        self.init(frame: frame, url: url, delegate: delegate, incognito: incognito, profilePath: nil)
    }

    // MARK: Web view

    @MainActor
    private func makeWebView(configuration given: WKWebViewConfiguration?) {
        let configuration = given ?? WKWebViewConfiguration()
        if given == nil {
            configuration.websiteDataStore = WebKitStores.store(profilePath: profile, incognito: incognitoPage)
        }
        // A popup's configuration is its opener's copy: it gets its own scripts and handler.
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: PageScript.mediaSessionWrapper + PageScript.mainWorld, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        content.addUserScript(WKUserScript(source: PageScript.isolatedWorld + Self.isolatedAddOn, injectionTime: .atDocumentStart,
                                           forMainFrameOnly: false, in: Self.world))
        let proxy = ScriptMessageProxy(owner: self)
        content.add(proxy, contentWorld: Self.world, name: "cra")
        messages = proxy
        configuration.userContentController = content
        configuration.preferences.isElementFullscreenEnabled = true
        // Off for apps other than Safari: video.requestPictureInPicture() answered NotSupportedError,
        // so the sidebar player's button and auto Picture in Picture did nothing.
        if configuration.preferences.responds(to: NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")) {
            configuration.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.applicationNameForUserAgent = Self.safariProduct

        let web = CraWebView(frame: container.bounds, configuration: configuration)
        web.owner = self
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        web.uiDelegate = self
        web.allowsBackForwardNavigationGestures = true
        web.allowsMagnification = true
        web.isInspectable = true
        container.addSubview(web)
        webView = web
        created = true
        observe(web)
        if audioMuted { setAudioMuted(true) }
    }

    /// The popup WebKit opens for window.open in an opener page: it must be a web view made with
    /// WebKit's configuration, so the popup keeps window.opener (sign-in windows post back).
    @MainActor
    func adoptPopup(configuration: WKWebViewConfiguration) -> WKWebView? {
        guard webView == nil, !closed else { return nil }
        makeWebView(configuration: configuration)
        return webView
    }

    /// Safari's own product token, so the services see Safari and pick FairPlay (Spotify, Netflix
    /// and Disney+ refuse browsers they don't know). Safari's version is the Mac's.
    static let safariProduct: String = {
        let paths = ["/Applications/Safari.app", "/System/Volumes/Preboot/Cryptexes/App/System/Applications/Safari.app"]
        let version = paths.lazy.compactMap { Bundle(path: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }.first
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let fallback = os.majorVersion >= 26 ? "\(os.majorVersion).0" : "18.0"
        let parts = (version ?? fallback).split(separator: ".")
        return "Version/\(parts.prefix(2).joined(separator: ".")) Safari/605.1.15"
    }()

    @MainActor
    private func observe(_ web: WKWebView) {
        observations = [
            web.observe(\.title, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated {
                    // A page starting to load has no title yet; Chromium says nothing until it has one.
                    guard let self, !self.closed, let title = web.title, !title.isEmpty else { return }
                    self.delegate?.browser(self, didChangeTitle: title)
                }
            },
            web.observe(\.url, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.closed, let url = web.url?.absoluteString else { return }
                    self.delegate?.browser(self, didChangeURL: url)
                }
            },
            web.observe(\.isLoading, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reportLoading() }
            },
            web.observe(\.canGoBack, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reportLoading() }
            },
            web.observe(\.canGoForward, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reportLoading() }
            },
            web.observe(\.estimatedProgress, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated {
                    guard let self, !self.closed, web.isLoading else { return }
                    self.delegate?.browser(self, didChangeProgress: web.estimatedProgress)
                }
            },
            web.observe(\.themeColor, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reportThemeColor() }
            },
            web.observe(\.cameraCaptureState, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reportCapture() }
            },
            web.observe(\.microphoneCaptureState, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.reportCapture() }
            },
            web.observe(\.fullscreenState, options: [.new]) { [weak self] web, _ in
                MainActor.assumeIsolated { self?.isContentFullscreen = web.fullscreenState != .notInFullscreen }
            },
        ]
        // WebKit's own "playing audio" (Safari's tab speaker), when this macOS has it; the
        // isolated world's media events stand in otherwise.
        if web.responds(to: NSSelectorFromString("_isPlayingAudio")) {
            web.addObserver(self, forKeyPath: "_isPlayingAudio", options: [.new], context: nil)
            observesPlayingAudio = true
        }
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
        guard keyPath == "_isPlayingAudio", let web = object as? WKWebView else {
            return super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
        MainActor.assumeIsolated { setPlaying((web.value(forKey: "_isPlayingAudio") as? Bool) ?? false) }
    }

    // MARK: State

    override var containerView: NSView { container }
    override var hostWindow: NSWindow? { nil }
    override var currentURL: String {
        MainActor.assumeIsolated { failedURL ?? webView?.url?.absoluteString ?? pendingURL }
    }
    override var currentTitle: String { MainActor.assumeIsolated { webView?.title ?? "" } }
    override var isLoading: Bool { MainActor.assumeIsolated { webView?.isLoading ?? false } }
    override var hasCommittedLoad: Bool { committed }
    override var canGoBack: Bool { MainActor.assumeIsolated { webView?.canGoBack ?? false } }
    override var canGoForward: Bool { MainActor.assumeIsolated { webView?.canGoForward ?? false } }
    override var isCreated: Bool { created && !closed }
    override var isClosed: Bool { closed }
    override var closedByPage: Bool { pageClosedItself }
    override var hasDevTools: Bool { false }
    override var isIncognito: Bool { incognitoPage }
    override var profilePath: String? { profile }
    override var isInPictureInPicture: Bool { inPictureInPicture }
    override var isPictureInPicturePlaying: Bool { pictureInPicturePlaying }
    override var isCapturingMedia: Bool { capturing }
    override var isAudible: Bool { audibleHold.audible }
    /// WebKit reports no media session: the sidebar player follows the audible hold.
    override var reportsMediaSession: Bool { false }
    /// WebKit has no Chromium media session to call a sound uncontrollable: its sounds are the page's media
    /// (`audibleHold`), and they make a card (the Chromium engine's own pages default to uncontrollable).
    override var hasUncontrollableSound: Bool { false }

    /// Once per change of the three, as CEF's OnLoadingStateChange (each of them is observed).
    @MainActor
    private func reportLoading() {
        guard let web = webView, !closed else { return }
        let now = [web.isLoading, web.canGoBack, web.canGoForward]
        guard now != lastLoadingState else { return }
        lastLoadingState = now
        delegate?.browser(self, didChangeLoading: web.isLoading, canGoBack: web.canGoBack, canGoForward: web.canGoForward)
    }

    @MainActor
    private func reportCapture() {
        guard let web = webView, !closed else { return }
        let now = web.cameraCaptureState == .active || web.microphoneCaptureState == .active
        guard now != capturing else { return }
        capturing = now
        delegate?.browser?(self, didChangeMediaCapture: now)
    }

    /// Chrome's audible state: on as sound starts, off 2 s after it stops (AudibleHold).
    @MainActor
    private func setPlaying(_ now: Bool) {
        audibleOff?.cancel()
        audibleOff = nil
        delegate?.browser?(self, didChangeSoundPlaying: now)
        switch audibleHold.setPlaying(now) {
        case .announce:
            delegate?.browser?(self, didChangeAudible: true)
        case .holdThenQuiet:
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, !self.closed, self.audibleHold.quietEnded() else { return }
                    self.delegate?.browser?(self, didChangeAudible: false)
                }
            }
            audibleOff = work
            DispatchQueue.main.asyncAfter(deadline: .now() + AudibleHold.quiet, execute: work)
        case .nothing:
            break
        }
    }

    @MainActor
    private func reportThemeColor() {
        guard let web = webView, !closed else { return }
        if let color = web.themeColor, let hex = Self.hex(color) {
            delegate?.browser(self, didReportThemeColor: hex)
        }
    }

    // MARK: Navigation

    override func loadURL(_ url: String) {
        MainActor.assumeIsolated {
            guard !closed else { return }
            // Cra's own navigation (the URL bar, a pinned tab's home) to a page the other engine
            // shows: the tab's page moves there.
            if delegate?.browser?(self, handsOffNavigationToURL: url, method: "GET") == true { return }
            load(url)
        }
    }

    @MainActor
    private func load(_ url: String) {
        guard let web = webView else { pendingURL = url; return }
        failedURL = nil
        pendingURL = url
        guard let u = URL(string: url) ?? URL(string: url.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? "") else { return }
        web.load(URLRequest(url: u))
    }

    override func goBack() { MainActor.assumeIsolated { _ = webView?.goBack() } }
    override func goForward() { MainActor.assumeIsolated { _ = webView?.goForward() } }
    override func reload() {
        MainActor.assumeIsolated {
            if let failedURL { load(failedURL) } else { _ = webView?.reload() }
        }
    }
    override func reloadIgnoringCache() {
        MainActor.assumeIsolated {
            if let failedURL { load(failedURL) } else { _ = webView?.reloadFromOrigin() }
        }
    }
    override func stopLoading() { MainActor.assumeIsolated { webView?.stopLoading() } }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        // Before WebKit's download: an Option-clicked link with `download` opens a pane, as in Chromium.
        if opensLittleWindow(action) || opensSplit(action) { return decisionHandler(.cancel, preferences) }
        if action.shouldPerformDownload { return decisionHandler(.download, preferences) }
        guard let url = action.request.url else { return decisionHandler(.allow, preferences) }
        let scheme = url.scheme?.lowercased() ?? ""
        // A web page never opens local files (Chromium's rule; Cra's own file:// pages are Chromium's).
        if scheme == "file" { return decisionHandler(.cancel, preferences) }
        if !["http", "https", "about", "blob", "data"].contains(scheme) {
            // zoommtg:, spotify:, itms-apps: go to their app after Chrome's "Open <app>?". A click
            // asks each time; the page's own redirect (Spotify's "open in the app" when a link
            // to it opens) asks once per page it loads, from the main frame, as Chrome's flood
            // guard lets it.
            let click = action.navigationType == .linkActivated
            let redirect = !click && action.targetFrame?.isMainFrame == true && !askedForAppOnThisPage
            if redirect { askedForAppOnThisPage = true }
            AppLinkPrompt.handle(url.absoluteString, from: self, userGesture: click || redirect)
            return decisionHandler(.cancel, preferences)
        }
        guard action.navigationType == .linkActivated else { return decisionHandler(.allow, preferences) }
        let s = url.absoluteString
        let mods = action.modifierFlags
        // ⌘-click and middle-click: a new tab, in the background unless ⇧ is down too (Chrome).
        if mods.contains(.command) || action.buttonNumber == 2 {
            delegate?.browser(self, requestsNewTabWithURL: s, inBackground: !mods.contains(.shift))
            return decisionHandler(.cancel, preferences)
        }
        guard action.targetFrame?.isMainFrame ?? true else { return decisionHandler(.allow, preferences) }
        // Arc's Peek, and Shift-click (Chrome's new window).
        if delegate?.browser?(self, opensPeekForURL: s, shiftClick: mods.contains(.shift), newTab: false) == true {
            return decisionHandler(.cancel, preferences)
        }
        if mods.contains(.shift) {
            delegate?.browser(self, requestsNewTabWithURL: s, inBackground: false)
            return decisionHandler(.cancel, preferences)
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let http = response.response as? HTTPURLResponse
        if response.isForMainFrame { lastStatus = http?.statusCode ?? 0 }
        let attachment = (http?.value(forHTTPHeaderField: "Content-Disposition") ?? "").lowercased().hasPrefix("attachment")
        decisionHandler(attachment || !response.canShowMIMEType ? .download : .allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failedURL = nil
        setCommitted(false)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        askedForAppOnThisPage = false
        setCommitted(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !closed else { return }
        let url = webView.url?.absoluteString ?? pendingURL
        delegate?.browser(self, didFinishLoadingURL: url, title: webView.title ?? "", statusCode: lastStatus)
        reportThemeColor()
        probeBackgroundColor()
        loadFavicon()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failed(webView, error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failed(webView, error)
    }

    @MainActor
    private func failed(_ webView: WKWebView, _ error: Error) {
        let e = error as NSError
        // Cancelled by a new navigation, a download or Peek: not a failure.
        if e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled { return }
        if e.domain == "WebKitErrorDomain" && (e.code == 102 || e.code == 204) { return }
        let url = (e.userInfo[NSURLErrorFailingURLStringErrorKey] as? String) ?? webView.url?.absoluteString ?? pendingURL
        delegate?.browser?(self, didFailLoadingURL: url, errorCode: Self.netError(e))
        guard !closed, e.domain == NSURLErrorDomain, let failing = URL(string: url) else { return }
        // Chrome's error page shows the address that failed; Reload tries it again (reload()).
        failedURL = url
        webView.loadSimulatedRequest(URLRequest(url: failing), responseHTML: Self.errorPage(host: failing.host ?? url, message: e.localizedDescription))
    }

    @MainActor
    private func setCommitted(_ now: Bool) {
        guard committed != now else { return }
        committed = now
        delegate?.browser?(self, didChangeCommittedLoad: now)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        CraLog.note("WebKit page process ended: \(incognitoPage ? "(incognito)" : CraLog.host(currentURL)), reloading")
        webView.reload()
    }

    /// ⌥⌘-click with Settings ▸ Links' "⌥⌘-click opens a Little Window" on: a Little Window, as in a Chromium tab
    /// (#373). WebKit hands over the click's own keys, so it is just now.
    private func opensLittleWindow(_ action: WKNavigationAction) -> Bool {
        guard action.navigationType == .linkActivated, action.buttonNumber != 2, let url = action.request.url?.absoluteString
        else { return false }
        return delegate?.browser?(self, opensLittleWindowForURL: url, clickModifiers: UInt(action.modifierFlags.rawValue), clickAge: 0) == true
    }

    /// Option-click on a link (Arc) or ⌘⌥-click (Chromium): a pane beside this page, as in a
    /// Chromium tab (#298). Not where the delegate has no split (a Little Window).
    private func opensSplit(_ action: WKNavigationAction) -> Bool {
        guard action.navigationType == .linkActivated, action.buttonNumber != 2, let url = action.request.url?.absoluteString,
              LinkSplitClick.opensSplit(url, modifiers: action.modifierFlags.rawValue),
              delegate?.responds(to: #selector(CraBrowserDelegate.browser(_:requestsSplitPaneWithURL:))) == true else { return false }
        delegate?.browser?(self, requestsSplitPaneWithURL: url)
        return true
    }

    // MARK: Windows and popups

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = action.request.url?.absoluteString ?? ""
        // Another app's address (Spotify's "Open in Desktop app" #207): no tab, "Open <app>?" over
        // this page. WebKit asks here only for a click (javaScriptCanOpenWindowsAutomatically is off).
        if AppLinkPrompt.handle(url, from: self, userGesture: true) { return nil }
        // A target=_blank link: a new tab without an opener, like Chrome's noopener default.
        if action.navigationType == .linkActivated {
            if opensLittleWindow(action) || opensSplit(action) { return nil }
            let mods = action.modifierFlags
            if mods.contains(.command) || action.buttonNumber == 2 {
                delegate?.browser(self, requestsNewTabWithURL: url, inBackground: !mods.contains(.shift))
            } else if delegate?.browser?(self, opensPeekForURL: url, shiftClick: mods.contains(.shift), newTab: true) != true {
                delegate?.browser(self, requestsNewTabWithURL: url, inBackground: false)
            }
            return nil
        }
        // window.open: a popup that keeps its opener (sign-in windows).
        guard let host = delegate?.browser(self, popupHostForURL: url, inBackground: false) as? WebKitBrowser else { return nil }
        return host.adoptPopup(configuration: configuration)
    }

    /// window.close(): the tab goes, like Chrome.
    func webViewDidClose(_ webView: WKWebView) {
        pageClosedItself = true
        close()
    }

    // MARK: Dialogs and permissions

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor () -> Void) {
        runAlert(message, frame: frame, buttons: ["OK"]) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor (Bool) -> Void) {
        runAlert(message, frame: frame, buttons: ["OK", "Cancel"]) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (String?) -> Void) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        runAlert(prompt, frame: frame, buttons: ["OK", "Cancel"], accessory: field) {
            completionHandler($0 == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    @MainActor
    private func runAlert(_ message: String, frame: WKFrameInfo, buttons: [String], accessory: NSView? = nil,
                          done: @escaping (NSApplication.ModalResponse) -> Void) {
        let alert = NSAlert()
        alert.messageText = frame.securityOrigin.host.isEmpty ? "This page says" : "\(frame.securityOrigin.host) says"
        alert.informativeText = message
        for b in buttons { alert.addButton(withTitle: b) }
        alert.accessoryView = accessory
        guard let window = container.window else { return done(.alertSecondButtonReturn) }
        alert.beginSheetModal(for: window, completionHandler: done)
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping @MainActor ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        guard let window = container.window else { return completionHandler(nil) }
        panel.beginSheetModal(for: window) { completionHandler($0 == .OK ? panel.urls : nil) }
    }

    /// Camera and microphone ask through Cra's prompt, as Chromium's pages do (kinds 1 and 2).
    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType, decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        let kinds: UInt
        switch type {
        case .camera: kinds = 1
        case .microphone: kinds = 2
        case .cameraAndMicrophone: kinds = 3
        @unknown default: kinds = 16
        }
        let port = origin.port == 0 ? "" : ":\(origin.port)"
        guard let delegate else { return decisionHandler(.deny) }
        delegate.browser(self, requestsPermissionForOrigin: "\(origin.protocol)://\(origin.host)\(port)", kinds: kinds) { allowed in
            DispatchQueue.main.async { decisionHandler(allowed ? .grant : .deny) }
        }
    }

    // MARK: Focus, zoom, find, sound

    override func setFocused(_ focused: Bool) {
        MainActor.assumeIsolated {
            guard focused, let web = webView, let window = web.window else { return }
            if window.firstResponder !== web { window.makeFirstResponder(web) }
        }
    }

    /// Chromium's zoom level is log base 1.2 of the factor (0 = 100 %, 1 = 120 %).
    override func zoomLevel() -> Double {
        MainActor.assumeIsolated { log(Double(webView?.pageZoom ?? 1)) / log(1.2) }
    }

    override func setZoomLevel(_ level: Double) {
        MainActor.assumeIsolated { webView?.pageZoom = CGFloat(pow(1.2, level)) }
    }

    override func findText(_ text: String, forward: Bool, matchCase: Bool, findNext: Bool) {
        MainActor.assumeIsolated {
            guard let web = webView, !text.isEmpty else { return }
            let config = WKFindConfiguration()
            config.backwards = !forward
            config.caseSensitive = matchCase
            config.wraps = true
            let fresh = !findNext || text != findQuery
            findQuery = text
            web.find(text, configuration: config) { [weak self] result in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    guard result.matchFound else {
                        self.findCount = 0
                        self.findIndex = 0
                        self.delegate?.browser?(self, didFindMatches: 0, activeMatch: 0)
                        return
                    }
                    let step = { [weak self] (count: Int) in
                        guard let self else { return }
                        self.findCount = max(count, 1)
                        if fresh { self.findIndex = forward ? 1 : self.findCount } else {
                            self.findIndex = forward ? self.findIndex % self.findCount + 1 : (self.findIndex + self.findCount - 2) % self.findCount + 1
                        }
                        self.delegate?.browser?(self, didFindMatches: self.findCount, activeMatch: self.findIndex)
                    }
                    if !fresh, self.findCount > 0 { return step(self.findCount) }
                    // WebKit's find doesn't count: the page's text does, the way find sees it.
                    web.callAsyncJavaScript(Self.countMatches, arguments: ["q": text, "cs": matchCase], in: nil, in: Self.world) { r in
                        MainActor.assumeIsolated { step((try? r.get()) as? Int ?? 1) }
                    }
                }
            }
        }
    }

    private static let countMatches = """
    const t = document.body ? document.body.innerText : '';
    const a = cs ? t : t.toLowerCase(), b = cs ? q : q.toLowerCase();
    let n = 0, i = 0;
    while (b && (i = a.indexOf(b, i)) !== -1) { n++; i += b.length; }
    return n;
    """

    override func stopFinding(_ clearSelection: Bool) {
        MainActor.assumeIsolated {
            findQuery = ""
            findCount = 0
            findIndex = 0
            if clearSelection { webView?.evaluateJavaScript("getSelection().removeAllRanges()", in: nil, in: Self.world) { _ in } }
        }
    }

    /// WebKit's page mute (Safari's tab mute), else every media element. Before the web view
    /// exists it waits for makeWebView.
    override func setAudioMuted(_ muted: Bool) {
        audioMuted = muted
        MainActor.assumeIsolated {
            guard let web = webView else { return }
            let sel = NSSelectorFromString("_setPageMuted:")
            if let m = class_getInstanceMethod(type(of: web), sel) {
                typealias Fn = @convention(c) (AnyObject, Selector, UInt) -> Void
                unsafeBitCast(method_getImplementation(m), to: Fn.self)(web, sel, muted ? 1 : 0)
            } else {
                web.evaluateJavaScript("document.querySelectorAll('video,audio').forEach(m => m.muted = \(muted))", in: nil, in: Self.world) { _ in }
            }
        }
    }

    /// WebKit's own page mute state (_mediaMutedState's audio bit), else what Cra asked for.
    override func isAudioMuted() -> Bool {
        MainActor.assumeIsolated {
            let sel = NSSelectorFromString("_mediaMutedState")
            guard let web = webView, let m = class_getInstanceMethod(type(of: web), sel) else { return audioMuted }
            typealias Fn = @convention(c) (AnyObject, Selector) -> UInt
            return unsafeBitCast(method_getImplementation(m), to: Fn.self)(web, sel) & 1 != 0
        }
    }

    override func exitFullscreen() {
        MainActor.assumeIsolated { webView?.closeAllMediaPresentations {} }
    }

    // MARK: Picture in Picture (WebKit's own, the system's floating window)

    override func requestPictureInPicture(automatic: Bool) {
        // BrowserManager asked the page first; WebKit has no other way in.
    }

    override func exitPictureInPicture() {
        runPictureInPicture("if (document.pictureInPictureElement) document.exitPictureInPicture();")
    }

    override func closePictureInPicture() {
        runPictureInPicture("const v = document.pictureInPictureElement; if (v) { v.pause(); document.exitPictureInPicture(); }")
    }

    override func togglePictureInPicturePlayback() {
        runPictureInPicture("const v = document.pictureInPictureElement; if (v) { v.paused ? v.play() : v.pause(); }")
    }

    override func skipPictureInPicture(by seconds: Double) {
        runPictureInPicture("const v = document.pictureInPictureElement; if (v) v.currentTime = Math.max(0, v.currentTime + \(seconds));")
    }

    private func runPictureInPicture(_ js: String) {
        MainActor.assumeIsolated { webView?.evaluateJavaScript(js, in: nil, in: Self.world) { _ in } }
    }

    // MARK: Messages from the isolated world

    @MainActor
    fileprivate func receive(_ body: Any) {
        guard !closed, let m = body as? [String: Any], let kind = m["t"] as? String else { return }
        switch kind {
        case "media":
            if !observesPlayingAudio { setPlaying(m["playing"] as? Bool ?? false) }
        case "pip":
            let on = m["on"] as? Bool ?? false
            guard on != inPictureInPicture else { return }
            inPictureInPicture = on
            pictureInPicturePlaying = on && (m["playing"] as? Bool ?? true)
            delegate?.browser?(self, didChangePictureInPicture: on)
        case "pipPlaying":
            let on = m["on"] as? Bool ?? false
            guard inPictureInPicture, on != pictureInPicturePlaying else { return }
            pictureInPicturePlaying = on
            delegate?.browser?(self, didChangePictureInPicturePlayback: on)
        case "hover":
            let url = m["url"] as? String ?? ""
            guard url != hoverURL else { return }
            hoverURL = url
            delegate?.browser(self, didChangeStatusMessage: url)
        case "colors":
            if let bg = m["bg"] as? String { delegate?.browser?(self, didReportBackgroundColor: bg) }
        default: break
        }
    }

    /// Added to PageScript's isolated world here: what Chromium reports natively.
    static let isolatedAddOn = """

    (() => {
      if (window.__craWebKit) return;
      window.__craWebKit = true;
      const post = m => { try { webkit.messageHandlers.cra.postMessage(m); } catch {} };
      const media = () => [...document.querySelectorAll('video,audio')];
      let was = false;
      const report = () => {
        const now = media().some(m => !m.paused && !m.ended && !m.muted && m.volume > 0);
        if (now !== was) { was = now; post({ t: 'media', playing: now }); }
      };
      for (const ev of ['play', 'playing', 'pause', 'ended', 'volumechange', 'emptied']) addEventListener(ev, e => {
        report();
        const v = document.pictureInPictureElement;
        if (v && e.target === v && (ev === 'play' || ev === 'pause')) post({ t: 'pipPlaying', on: ev === 'play' });
      }, true);
      addEventListener('enterpictureinpicture', e => post({ t: 'pip', on: true, playing: !e.target.paused }), true);
      addEventListener('leavepictureinpicture', () => post({ t: 'pip', on: false }), true);
      if (window.top === window) {
        let last = '';
        addEventListener('mouseover', e => {
          const a = e.target instanceof Element ? e.target.closest('a[href]') : null;
          const url = a ? a.href : '';
          if (url !== last) { last = url; post({ t: 'hover', url }); }
        }, true);
        document.addEventListener('mouseleave', () => { if (last) { last = ''; post({ t: 'hover', url: '' }); } });
      }
    })();
    """

    /// The page's own background (root, then body), else its color scheme's canvas, as Chromium reports it.
    override func probeBackgroundColor() {
        MainActor.assumeIsolated {
            webView?.evaluateJavaScript(Self.backgroundProbe, in: nil, in: Self.world) { [weak self] r in
                MainActor.assumeIsolated {
                    guard let self, !self.closed, let hex = (try? r.get()) as? String, !hex.isEmpty else { return }
                    self.delegate?.browser?(self, didReportBackgroundColor: hex)
                    if self.webView?.themeColor == nil { self.delegate?.browser(self, didReportThemeColor: hex) }
                }
            }
        }
    }

    private static let backgroundProbe = """
    (() => {
      const hex = el => {
        if (!el) return '';
        const m = getComputedStyle(el).backgroundColor.match(/rgba?\\(\\s*([\\d.]+)[ ,]+([\\d.]+)[ ,]+([\\d.]+)(?:[ ,/]+([\\d.]+))?/);
        if (!m || (m[4] !== undefined && +m[4] === 0)) return '';
        return '#' + [m[1], m[2], m[3]].map(x => Math.round(+x).toString(16).padStart(2, '0')).join('');
      };
      const dark = getComputedStyle(document.documentElement).colorScheme.includes('dark') && matchMedia('(prefers-color-scheme: dark)').matches;
      return hex(document.documentElement) || hex(document.body) || (dark ? '#121212' : '#ffffff');
    })()
    """

    // MARK: Favicon

    /// The page's own icon (the largest it declares, else /favicon.ico), fetched without cookies.
    @MainActor
    private func loadFavicon() {
        let js = """
        (() => {
          const links = [...document.querySelectorAll('link[rel~="icon"], link[rel="apple-touch-icon"], link[rel="shortcut icon"]')];
          const size = l => Math.max(0, ...(l.getAttribute('sizes') || '').split(/\\s+/).map(s => parseInt(s, 10) || 0));
          links.sort((a, b) => size(b) - size(a));
          const svgless = links.filter(l => !/\\.svg(\\?|$)/i.test(l.href));
          return (svgless[0] || links[0])?.href || new URL('/favicon.ico', location.href).href;
        })()
        """
        webView?.evaluateJavaScript(js, in: nil, in: Self.world) { [weak self] r in
            guard let s = (try? r.get()) as? String, let url = URL(string: s), ["http", "https", "data"].contains(url.scheme ?? "") else { return }
            Self.iconSession.dataTask(with: url) { data, _, _ in
                guard let data, let image = NSImage(data: data), image.size.width > 0 else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        guard let self, !self.closed else { return }
                        self.delegate?.browser(self, didLoadFavicon: image, forURL: s)
                    }
                }
            }.resume()
        }
    }

    private static let iconSession: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.httpCookieStorage = nil
        c.httpShouldSetCookies = false
        c.timeoutIntervalForRequest = 15
        return URLSession(configuration: c)
    }()

    // MARK: Scripts and the DevTools Protocol methods Cra uses

    override func executeJavaScript(_ script: String) {
        MainActor.assumeIsolated { webView?.evaluateJavaScript(script) { _, _ in } }
    }

    override func executeJavaScript(_ script: String, inDevTools: Bool) {
        if !inDevTools { executeJavaScript(script) }
    }

    override func evaluate(inIsolatedWorld world: String, params: String, completion: @escaping (String?, String?) -> Void) {
        MainActor.assumeIsolated { evaluate(params, in: WKContentWorld.world(name: world), completion: completion) }
    }

    override func sendDevToolsMethod(_ method: String, params: String, completion: @escaping (String?, String?) -> Void) {
        MainActor.assumeIsolated {
            guard let web = webView, !closed else { return reply(completion, nil, "\(method): the page is closed") }
            switch method {
            case "Runtime.evaluate":
                evaluate(params, in: .page, completion: completion)
            case "Page.captureScreenshot":
                captureScreenshot(web, params: Self.object(params), completion: completion)
            case "Page.getLayoutMetrics":
                let js = """
                (() => { const e = document.documentElement, v = window.visualViewport;
                  return JSON.stringify({ cssContentSize: { x: 0, y: 0, width: e.scrollWidth, height: e.scrollHeight },
                    cssVisualViewport: { pageX: scrollX, pageY: scrollY, clientWidth: v ? v.width : innerWidth,
                      clientHeight: v ? v.height : innerHeight, scale: v ? v.scale : 1 } }); })()
                """
                web.evaluateJavaScript(js, in: nil, in: Self.world) { [weak self] r in
                    self?.reply(completion, (try? r.get()) as? String, "Page.getLayoutMetrics failed")
                }
            case "Storage.clearDataForOrigin":
                clearCookies(origin: Self.object(params)["origin"] as? String ?? "", completion: completion)
            case "Network.clearBrowserCache":
                let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]
                web.configuration.websiteDataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
                    self?.reply(completion, "{}", nil)
                }
            case "Page.getNavigationHistory":
                reply(completion, navigationHistory(web.backForwardList), nil)
            case "Page.navigateToHistoryEntry":
                let id = Self.object(params)["entryId"] as? Int ?? -1
                let list = web.backForwardList
                guard let item = historyItems[id], (list.backList + list.forwardList).contains(where: { $0 === item }) else {
                    return reply(completion, nil, "no history entry \(id)")
                }
                web.go(to: item)
                reply(completion, "{}", nil)
            case "Cra.setFreezingVote", "Cra.load":
                // WebKit decides when a hidden page sleeps; tab sleeping closes the page instead.
                reply(completion, "{}", nil)
            default:
                // Cra.discard, Cra.getFreezingState, Target.*: Chromium only. Each caller has a path for this.
                reply(completion, nil, "\(method) is not available in a WebKit page")
            }
        }
    }

    /// Page.getNavigationHistory as Chromium answers it, from WebKit's back-forward list: the
    /// pages oldest first, `currentIndex` the one showing. An item keeps its id while it lives.
    @MainActor
    private func navigationHistory(_ list: WKBackForwardList) -> String {
        guard let current = list.currentItem else { return #"{"currentIndex":0,"entries":[]}"# }
        let items = list.backList + [current] + list.forwardList
        var live: [ObjectIdentifier: Int] = [:]
        var byID: [Int: WKBackForwardListItem] = [:]
        let entries: [[String: Any]] = items.map { item in
            let key = ObjectIdentifier(item)
            let id = historyIDs[key] ?? ((historyIDs.values.max() ?? 0) + live.count + 1)
            live[key] = id
            byID[id] = item
            return ["id": id, "url": item.url.absoluteString, "title": item.title ?? ""]
        }
        historyIDs = live
        historyItems = byID
        let object: [String: Any] = ["currentIndex": list.backList.count, "entries": entries]
        return (try? JSONSerialization.data(withJSONObject: object)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    /// Completions come on the main queue, a turn later, as CraCEF's do.
    @MainActor
    private func reply(_ completion: @escaping (String?, String?) -> Void, _ result: String?, _ error: String?) {
        DispatchQueue.main.async { result != nil ? completion(result, nil) : completion(nil, error ?? "failed") }
    }

    /// Runtime.evaluate's params (`expression`, `awaitPromise`, `returnByValue`), answered as
    /// Chromium does: {"result":{"type":…,"value":…}} or {"exceptionDetails":{…}}. Scripts run as a
    /// user gesture (WebKit's evaluateJavaScript always does), so play() and requestPictureInPicture work.
    @MainActor
    private func evaluate(_ params: String, in world: WKContentWorld, completion: @escaping (String?, String?) -> Void) {
        guard let web = webView, !closed else { return reply(completion, nil, "the page is closed") }
        let p = Self.object(params)
        guard let expression = p["expression"] as? String else { return reply(completion, nil, "no expression") }
        let done: (Result<Any, Error>) -> Void = { [weak self] r in
            MainActor.assumeIsolated { self?.reply(completion, Self.evaluationResult(r), nil) }
        }
        if p["awaitPromise"] as? Bool == true {
            web.callAsyncJavaScript("return await (\n\(expression)\n);", arguments: [:], in: nil, in: world, completionHandler: done)
        } else {
            web.evaluateJavaScript(expression, in: nil, in: world, completionHandler: done)
        }
    }

    static func evaluationResult(_ r: Result<Any, Error>) -> String {
        let out: [String: Any]
        switch r {
        case .success(let value):
            switch value {
            case is NSNull: out = ["result": ["type": "object", "subtype": "null", "value": NSNull()]]
            case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): out = ["result": ["type": "boolean", "value": n.boolValue]]
            case let n as NSNumber: out = ["result": ["type": "number", "value": n]]
            case let s as String: out = ["result": ["type": "string", "value": s]]
            default: out = ["result": ["type": "object", "value": JSONSerialization.isValidJSONObject(value) ? value : NSNull()]]
            }
        case .failure(let error):
            let e = error as NSError
            // "JavaScript execution returned a result of an unsupported type": undefined, a promise, a node.
            if e.domain == WKErrorDomain && e.code == WKError.javaScriptResultTypeIsUnsupported.rawValue {
                out = ["result": ["type": "undefined"]]
            } else {
                let text = e.userInfo["WKJavaScriptExceptionMessage"] as? String ?? e.localizedDescription
                out = ["exceptionDetails": ["text": text, "exception": ["type": "object", "description": text]]]
            }
        }
        return String(decoding: (try? JSONSerialization.data(withJSONObject: out, options: [.fragmentsAllowed])) ?? Data("{}".utf8), as: UTF8.self)
    }

    /// The viewport (or `clip`, in CSS pixels), as {"data": base64}. `captureBeyondViewport`
    /// (Capture's full page) renders the whole document through WebKit's PDF path.
    @MainActor
    private func captureScreenshot(_ web: WKWebView, params: [String: Any], completion: @escaping (String?, String?) -> Void) {
        let png = (params["format"] as? String ?? "png") == "png"
        let quality = Double(params["quality"] as? Int ?? 80) / 100
        let clip = params["clip"] as? [String: Any]
        let encode: (CGImage?) -> Void = { [weak self] image in
            guard let image else { return MainActor.assumeIsolated { self?.reply(completion, nil, "no image") } }
            let rep = NSBitmapImageRep(cgImage: image)
            let data = png ? rep.representation(using: .png, properties: [:])
                : rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
            let json = data.map { #"{"data":""# + $0.base64EncodedString() + #""}"# }
            MainActor.assumeIsolated { self?.reply(completion, json, "encoding failed") }
        }
        if params["captureBeyondViewport"] as? Bool == true, let clip {
            let rect = NSRect(x: clip["x"] as? Double ?? 0, y: clip["y"] as? Double ?? 0,
                              width: clip["width"] as? Double ?? Double(web.bounds.width), height: clip["height"] as? Double ?? Double(web.bounds.height))
            let config = WKPDFConfiguration()
            config.rect = rect
            web.createPDF(configuration: config) { r in encode((try? r.get()).flatMap(Self.render(pdf:))) }
            return
        }
        let config = WKSnapshotConfiguration()
        if let clip {
            config.rect = NSRect(x: clip["x"] as? Double ?? 0, y: clip["y"] as? Double ?? 0,
                                 width: clip["width"] as? Double ?? 0, height: clip["height"] as? Double ?? 0)
        }
        config.afterScreenUpdates = false
        web.takeSnapshot(with: config) { image, _ in
            encode(image?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        }
    }

    /// The first page of a PDF at 2× (Capture's full page).
    static func render(pdf data: Data) -> CGImage? {
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider), let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let scale: CGFloat = min(2, 16384 / max(box.height, 1))
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard w > 0, h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        ctx.drawPDFPage(page)
        return ctx.makeImage()
    }

    /// Arc's "Clear Cookies and Refresh" for this site (its registrable domain's records).
    @MainActor
    private func clearCookies(origin: String, completion: @escaping (String?, String?) -> Void) {
        guard let store = webView?.configuration.websiteDataStore, let host = URL(string: origin)?.host?.lowercased() else {
            return reply(completion, nil, "no origin")
        }
        let types: Set<String> = [WKWebsiteDataTypeCookies]
        store.fetchDataRecords(ofTypes: types) { [weak self] records in
            let mine = records.filter { r in
                let d = r.displayName.lowercased()
                return host == d || host.hasSuffix("." + d)
            }
            store.removeData(ofTypes: types, for: mine) { MainActor.assumeIsolated { self?.reply(completion, "{}", nil) } }
        }
    }

    static func object(_ json: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]) ?? [:]
    }

    // MARK: DevTools, printing, source, connection

    /// WebKit's Web Inspector, in its own window (Chrome's DevTools dock is Chromium's).
    override func showDevTools() { MainActor.assumeIsolated { inspector(perform: "show") } }
    override func closeDevTools() { MainActor.assumeIsolated { inspector(perform: "close") } }
    override func applyDevToolsAction() { devToolsAction = nil }

    @MainActor
    private func inspector(perform name: String) {
        guard let web = webView, web.responds(to: NSSelectorFromString("_inspector")),
              let inspector = web.value(forKey: "_inspector") as? NSObject, inspector.responds(to: NSSelectorFromString(name)) else { return }
        inspector.perform(NSSelectorFromString(name))
    }

    override func print() {
        MainActor.assumeIsolated {
            guard let web = webView, let window = web.window else { return }
            let op = web.printOperation(with: NSPrintInfo.shared)
            op.view?.frame = web.bounds
            op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        }
    }

    override func sslStatus() -> CraSSLStatus? {
        MainActor.assumeIsolated {
            guard let web = webView, web.url != nil else { return nil }
            let s = CraSSLStatus()
            guard web.url?.scheme == "https", let trust = web.serverTrust else { return s }
            s.secureConnection = true
            s.certificates = (SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []).map { SecCertificateCopyData($0) as Data }
            // net::SSLStatus::DISPLAYED_INSECURE_CONTENT: something on the page came over http.
            s.contentStatus = web.hasOnlySecureContent ? 0 : 1
            return s
        }
    }

    override func notifyMoveOrResizeStarted() {}

    // MARK: Close

    override func close() {
        MainActor.assumeIsolated {
            guard !closed else { return }
            closed = true
            audibleOff?.cancel()
            for (_, d) in downloads { d.progress?.invalidate() }
            if let web = webView {
                observations.forEach { $0.invalidate() }
                observations = []
                if observesPlayingAudio { web.removeObserver(self, forKeyPath: "_isPlayingAudio") }
                observesPlayingAudio = false
                web.closeAllMediaPresentations {}
                web.pauseAllMediaPlayback()
                web.stopLoading()
                web.navigationDelegate = nil
                web.uiDelegate = nil
                web.configuration.userContentController.removeAllScriptMessageHandlers()
                web.configuration.userContentController.removeAllUserScripts()
                web.owner = nil
                web.removeFromSuperview()
            }
            webView = nil
            // Like CEF, -browserDidClose: comes once the page is gone, a turn later.
            DispatchQueue.main.async { [self] in delegate?.browserDidClose(self) }
        }
    }

    // MARK: Downloads

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { download.delegate = self }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { download.delegate = self }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
                  completionHandler: @escaping @MainActor (URL?) -> Void) {
        // The profile's Download location, or a save panel when it asks for each file (#190).
        let profilePath = incognitoPage ? nil : profile
        let asked = DownloadDestinations.location(profileID: DownloadDestinations.profileID(profilePath: profilePath)).askWhereToSave
        DownloadDestinations.destination(profilePath: profilePath, suggestedName: suggestedFilename) { [weak self] dest in
            guard let self, let dest else { return completionHandler(nil) }
            // A save panel picks a taken name only after the user agreed to replace it, and
            // WebKit won't write over a file. (Without a panel the name is a free one.)
            if asked, FileManager.default.fileExists(atPath: dest.path) { try? FileManager.default.trashItem(at: dest, resultingItemURL: nil) }
            self.startDownload(download, response: response, to: dest, completionHandler: completionHandler)
        }
    }

    private func startDownload(_ download: WKDownload, response: URLResponse, to dest: URL,
                               completionHandler: @escaping @MainActor (URL?) -> Void) {
        Self.nextDownloadID &+= 1
        let info = CraDownloadInfo()
        info.identifier = Self.nextDownloadID
        info.url = response.url?.absoluteString ?? ""
        info.fullPath = dest.path
        info.suggestedName = dest.lastPathComponent
        info.totalBytes = response.expectedContentLength
        info.state = .inProgress
        let key = ObjectIdentifier(download)
        let progress = download.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, let d = self.downloads[key] else { return }
                    d.info.receivedBytes = p.completedUnitCount
                    if p.totalUnitCount > 0 { d.info.totalBytes = p.totalUnitCount }
                    d.info.percent = d.info.totalBytes > 0 ? Int(d.info.receivedBytes * 100 / d.info.totalBytes) : -1
                    self.delegate?.browser(self, didUpdateDownload: d.info)
                }
            }
        }
        downloads[key] = (download, info, progress)
        delegate?.browser(self, didUpdateDownload: info)
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(download, .complete)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let e = error as NSError
        finish(download, e.domain == NSURLErrorDomain && e.code == NSURLErrorCancelled ? .cancelled : .interrupted)
    }

    @MainActor
    private func finish(_ download: WKDownload, _ state: CraDownloadState) {
        guard let d = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        d.progress?.invalidate()
        d.info.state = state
        if state == .complete {
            d.info.receivedBytes = max(d.info.receivedBytes, d.info.totalBytes)
            d.info.percent = 100
        }
        delegate?.browser(self, didUpdateDownload: d.info)
    }

    // MARK: Helpers

    static func hex(_ color: NSColor) -> String? {
        guard let c = color.usingColorSpace(.sRGB), c.alphaComponent > 0 else { return nil }
        return String(format: "#%02x%02x%02x", Int((c.redComponent * 255).rounded()), Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// Chromium's net error for a URL loading error, for the log and ExtensionPageRetry.
    static func netError(_ e: NSError) -> Int {
        guard e.domain == NSURLErrorDomain else { return -2 }
        switch e.code {
        case NSURLErrorNotConnectedToInternet: return -106
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: return -105
        case NSURLErrorTimedOut: return -7
        case NSURLErrorCannotConnectToHost: return -102
        case NSURLErrorNetworkConnectionLost: return -101
        case NSURLErrorSecureConnectionFailed: return -107
        case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid: return -202
        default: return -2
        }
    }

    static func errorPage(host: String, message: String) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        return """
        <!doctype html><meta charset="utf-8"><meta name="color-scheme" content="light dark"><title>\(esc(host))</title>
        <style>body{font:15px -apple-system,system-ui,sans-serif;margin:0;display:grid;place-items:center;height:100vh;color:CanvasText;background:Canvas}
        div{max-width:520px;padding:24px}h1{font-size:20px;font-weight:600;margin:0 0 8px}p{opacity:.7;margin:0}</style>
        <div><h1>This page couldn’t load</h1><p>\(esc(host)): \(esc(message))</p></div>
        """
    }
}

/// WKUserContentController holds its handlers strongly; the browser is held weakly here.
private final class ScriptMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: WebKitBrowser?
    init(owner: WebKitBrowser) { self.owner = owner }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { owner?.receive(message.body) }
    }
}

/// The page view: tells its browser about focus and keys the way CEF's view does.
final class CraWebView: WKWebView {
    weak var owner: WebKitBrowser?
    /// The ⌘-key WebKit is offering the page; WebKit sends it again if the page leaves it alone.
    private weak var offered: NSEvent?

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let owner { owner.delegate?.browserDidReceiveFocus(owner) }
        return ok
    }

    /// Chrome's order: Cra's reserved shortcuts before the page sees the key, the page next,
    /// then the menu bar and Cra's other shortcuts for keys the page left alone.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // AppKit offers a key equivalent to every view in the window: only the focused page takes it,
        // not one in a hidden tab or the other split pane.
        guard let owner, event.type == .keyDown, window?.firstResponder === self, !isHiddenOrHasHiddenAncestor else {
            return super.performKeyEquivalent(with: event)
        }
        if let offered, offered === event {
            self.offered = nil
            if NSApp.mainMenu?.performKeyEquivalent(with: event) == true { return true }
            return owner.delegate?.browser(owner, handleUnhandledKeyEvent: event) ?? false
        }
        if owner.delegate?.browser(owner, handleKeyEvent: event) == true { return true }
        offered = event
        return super.performKeyEquivalent(with: event)
    }

    /// "Open Link in New Window" opens a tab in Cra.
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        for item in menu.items {
            switch item.identifier?.rawValue {
            case "WKMenuItemIdentifierOpenLinkInNewWindow": item.title = "Open Link in New Tab"
            case "WKMenuItemIdentifierOpenImageInNewWindow": item.title = "Open Image in New Tab"
            case "WKMenuItemIdentifierOpenMediaInNewWindow": item.title = "Open Video in New Tab"
            case "WKMenuItemIdentifierOpenFrameInNewWindow": item.title = "Open Frame in New Tab"
            default: break
            }
        }
    }
}
