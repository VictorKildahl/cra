import CraCore
import SwiftUI
import UIKit
import WebKit

/// The whole browser: the page, the bar under it, and the search sheet that grows out of the
/// bar's pill when the keyboard comes up.
final class BrowserViewController: UIViewController, SearchSheetDelegate, WebPageDelegate, TabSwitcherDelegate, PageMenuDelegate {
    let store: TabStore
    let settings: MobileSettingsStore
    let suggestions = SuggestionService()
    let favicons = FaviconStore()
    lazy var favorites = FavoritesStore(directory: LaunchOptions.dataDirectory)

    let backdrop = BackdropView()
    let logo = FidgetLogoView(image: UIImage(named: "LaunchMark"))
    let pageContainer = PassthroughView()
    /// Darkens the page while it sits pushed back behind the search sheet.
    let pageDim = UIView()
    var pagePushedBack = false
    let dismissArea = UIControl()
    let bar = BottomBar()
    let sheet = SearchSheet()

    var shownPage: WebPage?
    var switcher: TabSwitcherView?
    var menuHost: SheetHost?
    var menuView: PageMenuView?
    // Swipes (BrowserGestures.swift).
    var swipeNeighbour: UIImageView?
    var swipeNeighbourStep = 0
    var tabArchivedBySwipe: UUID?
    var barSwipeOpensRow = false
    // Voice search (BrowserGestures.swift).
    var voice: VoiceSearch?
    var voiceOverlay: VoiceOverlayView?
    // Reader and Summarize (BrowserReading.swift).
    var readerView: ReaderView?
    var summaryHost: UIViewController?
    var browseLoading: BrowseLoadingView?
    /// The switch between Browse for Me and the search engine (BrowserReading.swift).
    let browseToggle = BrowseToggleView()
    var browseToggleState: (side: MobileBrowseToggle.Side, query: String)?
    var isSearching = false
    var incognitoSearch = false
    var keyboardHeight: CGFloat = 0
    var keyboardDroveLayout = false
    var barHiddenByScroll = false
    var scrollTravel: CGFloat = 0

    init(store: TabStore, settings: MobileSettingsStore) {
        self.store = store
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Life cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(backdrop)
        view.addSubview(logo)
        view.addSubview(pageContainer)
        pageDim.backgroundColor = .black
        pageDim.alpha = 0
        pageDim.isUserInteractionEnabled = false
        pageContainer.addSubview(pageDim)
        pageContainer.layer.cornerCurve = .continuous
        pageContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        dismissArea.addTarget(self, action: #selector(dismissSearch), for: .touchUpInside)
        dismissArea.isHidden = true
        dismissArea.accessibilityIdentifier = "search-dismiss"
        view.addSubview(dismissArea)

        bar.tabsButton.addTarget(self, action: #selector(showTabs), for: .touchUpInside)
        bar.pill.addTarget(self, action: #selector(startSearch), for: .touchUpInside)
        bar.menuButton.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
        bar.spacesButton.addTarget(self, action: #selector(showSpaces), for: .touchUpInside)
        bar.settingsButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        browseToggle.alpha = 0
        browseToggle.onPick = { [weak self] side in self?.browseTogglePicked(side) }
        view.addSubview(browseToggle)
        view.addSubview(bar)

        sheet.delegate = self
        sheet.siteIcon = { [weak self] address in self?.favicons.icon(for: address) }
        sheet.isHidden = true
        view.addSubview(sheet)

        installGestures()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        Self.saveFakeShareForTest()
        center.addObserver(self, selector: #selector(performLaunchAction), name: LaunchAction.notification, object: nil)

        ContentBlocker.shared.prepare()
        DownloadManager.shared.load(from: LaunchOptions.dataDirectory)
        DownloadManager.shared.onFinish = { [weak self] item in self?.downloadFinished(item) }
        store.archiveStale(after: settings.value.archiveAfter)
        if let tab = store.selected { show(tab) }
        refreshTabStack()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Arc Search opens ready to type: the sheet comes up with the keyboard on launch.
        if !didOfferSearchOnLaunch, !didShowOnboarding, LaunchOptions.showsOnboarding(seen: settings.value.hasSeenOnboarding),
           presentedViewController == nil {
            // First launch: onboarding first; the search sheet comes up when it is done.
            didShowOnboarding = true
            return showOnboarding()
        }
        if !didOfferSearchOnLaunch {
            didOfferSearchOnLaunch = true
            if LaunchAction.pending != nil { return performLaunchAction() }
            let wantsSearch = (settings.value.opensKeyboardOnLaunch && !LaunchOptions.skipsSearch) || store.selected == nil
            if wantsSearch { setSearching(true, incognito: false) }
            if LaunchOptions.showsVoiceOverlay {
                let overlay = VoiceOverlayView(frame: view.bounds)
                view.addSubview(overlay)
                overlay.appear()
                overlay.setLevel(0.6)
                if let heard = LaunchOptions.fakeVoice {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { overlay.setTranscript(heard) }
                }
            }
            if isSearching, let typed = LaunchOptions.typedText {
                sheet.text = typed
                searchSheet(sheet, didChangeText: typed)
            }
        }
    }

    var didOfferSearchOnLaunch = false
    var didSummarizeFirstPage = false
    var didShowOnboarding = false

    /// Selected text on a page gets "Browse for Me" in its edit menu (Arc Search 1.23), where the
    /// device's own model can answer. WebKit's edit menu asks the responder chain.
    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system != .main, BrowseForMe.isAvailable, shownPage != nil, !isSearching else { return }
        let browse = UIAction(title: "Browse for Me", image: UIImage(systemName: "sparkles")) { [weak self] _ in
            self?.browseForSelection()
        }
        builder.insertSibling(UIMenu(options: .displayInline, children: [browse]), afterMenu: .standardEdit)
    }

    private func browseForSelection() {
        guard let page = shownPage else { return }
        page.webView.evaluateJavaScript("String(window.getSelection())") { [weak self] result, _ in
            guard let self, let text = result as? String else { return }
            let query = MobileBrowseForMe.query(fromSelection: text)
            guard !query.isEmpty else { return }
            self.incognitoSearch = self.store.tabs.first { $0.id == page.tabID }?.isIncognito ?? false
            self.open(MobileBrowseForMe.tabAddress(query: query))
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutChrome()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // MARK: Layout

    /// Puts the bar and the sheet where the current state says. Called inside animation blocks.
    func layoutChrome() {
        let bounds = view.bounds
        backdrop.frame = bounds
        // Bounds and centre, not frame: the container may be transformed (pushed back, swiped).
        pageContainer.bounds = CGRect(origin: .zero, size: bounds.size)
        pageContainer.center = CGPoint(x: bounds.midX, y: bounds.midY)
        switcher?.frame = bounds
        shownPage?.webView.frame = pageContainer.bounds
        pageDim.frame = pageContainer.bounds
        let logoSide: CGFloat = 132
        logo.bounds = CGRect(x: 0, y: 0, width: logoSide, height: logoSide)
        logo.center = CGPoint(x: bounds.midX, y: bounds.height * 0.505)

        // While the search sheet is up over a page, the page sits back as a dimmed card under
        // the status bar (Arc Search's look; `MobilePageBehindSearch`).
        if isSearching, shownPage != nil, switcher == nil {
            let placed = MobilePageBehindSearch.transform(in: bounds.size, safeTop: view.safeAreaInsets.top)
            pageContainer.transform = CGAffineTransform(translationX: 0, y: placed.shiftDown).scaledBy(x: placed.scale, y: placed.scale)
            pageContainer.layer.cornerRadius = MobilePageBehindSearch.cornerRadius / placed.scale
            pageContainer.clipsToBounds = true
            pageDim.alpha = MobilePageBehindSearch.dim
            pagePushedBack = true
        } else if pagePushedBack {
            pageContainer.transform = .identity
            pageContainer.layer.cornerRadius = 0
            pageDim.alpha = 0
            pagePushedBack = false
        }

        let safeBottom = view.safeAreaInsets.bottom
        let frames = MobileBottomBar.frames(in: bounds.size, safeBottom: safeBottom)
        var barFrame = frames.bar
        let keyboardUpForPage = keyboardHeight > safeBottom && !isSearching
        if (barHiddenByScroll || keyboardUpForPage) && !isSearching { barFrame.origin.y = bounds.height }
        bar.frame = barFrame
        bar.controlsVisibility = isSearching ? 0 : 1

        let keyboard = max(keyboardHeight, safeBottom)
        let top = isSearching ? MobileSearchSheet.top(screenHeight: bounds.height, keyboardHeight: keyboard) : barFrame.minY
        sheet.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(MobileSearchSheet.height + keyboard, bounds.height - top))
        sheet.collapsedFieldFrame = bar.pillFrame
        sheet.openness = isSearching ? 1 : 0
        dismissArea.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, top))
        logo.alpha = isSearching || store.selected != nil || switcher != nil ? 0 : 1
        layoutBrowseToggle(barTop: barFrame.minY)
        updatePageInsets()
    }

    /// Lets the page scroll clear of the bar.
    func updatePageInsets() {
        guard let scroll = shownPage?.webView.scrollView else { return }
        let inset = barHiddenByScroll ? 0 : MobileBottomBar.height
        if scroll.contentInset.bottom != inset {
            scroll.contentInset.bottom = inset
            scroll.verticalScrollIndicatorInsets.bottom = inset
        }
    }

    func animateChrome(duration: TimeInterval, options: UIView.AnimationOptions) {
        UIView.animate(withDuration: duration, delay: 0, options: options.union([.beginFromCurrentState, .allowUserInteraction])) {
            self.layoutChrome()
            self.bar.layoutIfNeeded()
            self.sheet.layoutIfNeeded()
        } completion: { _ in
            self.chromeSettled()
        }
    }

    func chromeSettled() {
        guard !isSearching else { return }
        sheet.isHidden = true
        bar.pill.alpha = 1
    }

    @objc func keyboardWillChange(_ note: Notification) {
        guard let info = note.userInfo, let end = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let local = view.convert(end, from: nil)
        keyboardHeight = max(0, view.bounds.height - local.minY)
        keyboardDroveLayout = true
        if duration > 0 {
            animateChrome(duration: duration, options: UIView.AnimationOptions(rawValue: curve << 16))
        } else {
            layoutChrome()
            chromeSettled()
        }
    }

    @objc func appDidBecomeActive() {
        takeSharedLinks()
    }

    @objc func appWillResignActive() {
        captureSnapshot()
        store.saveNow()
    }

    // MARK: Search

    @objc func startSearch() {
        setSearching(true, incognito: store.selected?.isIncognito ?? false)
    }

    /// Puts the sheet away. With no page behind it that leaves the empty home screen: the
    /// backdrop, the logo and the bar.
    @objc func dismissSearch() {
        setSearching(false)
    }

    func setSearching(_ searching: Bool, incognito: Bool? = nil) {
        guard searching != isSearching else { return }
        if searching {
            if let incognito { incognitoSearch = incognito }
            sheet.isIncognito = incognitoSearch
            backdrop.isIncognito = incognitoSearch
            sheet.text = ""
            sheet.setRows([])
            sheet.offersBrowseForMe = BrowseForMe.isAvailable
            sheet.setFavorites(favorites.value.shown().map { ($0, favicons.icon(for: $0.url)) })
            sheet.isHidden = false
            bar.pill.alpha = 0
            // Starts from the pill: lay the closed state out before anything animates.
            UIView.performWithoutAnimation {
                self.layoutChrome()
                self.sheet.layoutIfNeeded()
            }
        } else {
            suggestions.cancel()
        }
        isSearching = searching
        dismissArea.isHidden = !searching
        keyboardDroveLayout = false
        if searching {
            sheet.field.becomeFirstResponder()
        } else {
            sheet.field.resignFirstResponder()
        }
        // No software keyboard (a hardware one is attached): move the chrome ourselves.
        if !keyboardDroveLayout {
            animateChrome(duration: 0.35, options: .curveEaseInOut)
        }
    }

    func searchSheet(_ sheet: SearchSheet, didChangeText text: String) {
        let engine = settings.value.searchEngine
        // Incognito keeps what is typed on the phone until Go, and leaves the phone's own pages out.
        let sites = incognitoSearch ? [] : knownSites()
        sheet.setRows(MobileSuggestions.rows(typed: text, completions: [], sites: sites))
        guard !incognitoSearch else { return }
        suggestions.completions(for: text, engine: engine) { [weak self, weak sheet] found in
            guard let self, let sheet, self.isSearching, sheet.text == text else { return }
            sheet.setRows(MobileSuggestions.rows(typed: text, completions: found, sites: sites))
        }
    }

    /// The pages a typed word can match, most wanted first: favorites, open tabs from the most
    /// recent, then archived ones.
    private func knownSites() -> [MobileSuggestions.Site] {
        let favoriteSites = favorites.value.sites.map { MobileSuggestions.Site(title: $0.title, url: $0.url) }
        let tabs = (store.rowTabs + store.archived).sorted { $0.lastActive > $1.lastActive }
        return favoriteSites + tabs.map { MobileSuggestions.Site(title: $0.displayTitle, url: $0.url) }
    }

    /// Browse for Me is the search engine and this device can run it.
    var searchesWithBrowseForMe: Bool { settings.value.searchesWithBrowseForMe && BrowseForMe.isAvailable }

    /// Where a typed or spoken search goes: an address opens, a search goes to the engine or makes
    /// a Browse for Me page.
    func searchDestination(_ typed: String) -> String {
        MobileSuggestions.destination(forTyped: typed, engine: settings.value.searchEngine, browsesForMe: searchesWithBrowseForMe)
    }

    func searchSheet(_ sheet: SearchSheet, didSubmit text: String) {
        open(searchDestination(text))
    }

    func searchSheet(_ sheet: SearchSheet, didPick row: MobileSuggestions.Row) {
        open(MobileSuggestions.destination(for: row, engine: settings.value.searchEngine, browsesForMe: searchesWithBrowseForMe))
    }

    func searchSheet(_ sheet: SearchSheet, didPickFavorite site: MobileFavorites.Site) {
        open(site.url)
    }

    func searchSheet(_ sheet: SearchSheet, didAskToBrowseFor row: MobileSuggestions.Row) {
        open(MobileBrowseForMe.tabAddress(query: row.text))
    }

    func searchSheetDidToggleIncognito(_ sheet: SearchSheet) {
        incognitoSearch.toggle()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        UIView.transition(with: sheet, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction]) {
            sheet.isIncognito = self.incognitoSearch
        }
        UIView.transition(with: backdrop, duration: 0.25, options: [.transitionCrossDissolve]) {
            self.backdrop.isIncognito = self.incognitoSearch
        }
    }

    // MARK: Tabs and pages

    /// Opens an address in a new tab and shows it.
    func open(_ address: String) {
        captureSnapshot()
        let tab = store.open(url: address, incognito: incognitoSearch)
        show(tab)
        // Opened from the tab row: the row gives way to the new page.
        leaveSwitcherForPage()
        setSearching(false)
        refreshTabStack()
    }

    func show(_ tab: MobileTab) {
        let page = store.page(for: tab)
        page.siteOptions = { [weak self] host in self?.settings.value.options(for: host) ?? MobileSiteOptions() }
        guard page !== shownPage else { return }
        closeReader()
        shownPage?.webView.removeFromSuperview()
        shownPage?.delegate = nil
        shownPage = page
        page.delegate = self
        page.webView.allowsBackForwardNavigationGestures = false
        page.webView.frame = pageContainer.bounds
        pageContainer.insertSubview(page.webView, belowSubview: pageDim)
        if page.webView.url == nil, !page.isBrowsing {
            if let query = MobileBrowseForMe.query(fromTabAddress: tab.url) {
                browse(for: query, in: page)
            } else {
                page.load(tab.url)
            }
        }
        if let browseLoading {
            browseLoading.isHidden = browseLoading.tabID != page.tabID
            pageContainer.insertSubview(browseLoading, belowSubview: pageDim)
        }
        barHiddenByScroll = false
        scrollTravel = 0
        updateBrowseToggle()
    }

    func refreshTabStack() {
        let tabs = store.rowTabs
        let front = store.selected ?? tabs.last
        let back = tabs.last { $0.id != front?.id }
        bar.tabsButton.setSnapshots(front: front.flatMap { store.snapshot($0.id) }, back: back.flatMap { store.snapshot($0.id) })
    }

    func captureSnapshot() {
        guard let page = shownPage else { return }
        let id = page.tabID
        page.takeSnapshot { [weak self] image in
            guard let self, let image else { return }
            self.store.setSnapshot(image, for: id)
            self.refreshTabStack()
        }
    }

    // MARK: Tab switcher

    @objc func showTabs() {
        guard switcher == nil, !isSearching else { return }
        guard let page = shownPage else { return settleSwitcher(prepareSwitcher()) }
        let id = page.tabID
        page.takeSnapshot { [weak self] image in
            guard let self, self.switcher == nil else { return }
            if let image { self.store.setSnapshot(image, for: id) }
            self.settleSwitcher(self.prepareSwitcher())
        }
    }

    /// Puts the tab row up looking exactly like the page: the focused card fills the screen.
    /// From there it settles into the row (`settleSwitcher`) or follows a finger first.
    func prepareSwitcher() -> TabSwitcherView {
        let switcher = TabSwitcherView(frame: view.bounds)
        switcher.delegate = self
        let onRow = store.selected.map { !$0.isIncognito } ?? false
        switcher.setTabs(store.rowTabs, focus: store.selected?.id, snapshot: store.snapshot, favicon: { self.favicons.icon(for: $0.url) })
        // An incognito page has no card to shrink into; the row just appears.
        switcher.expandedID = onRow ? store.selected?.id : nil
        switcher.expansion = onRow ? 1 : 0
        view.insertSubview(switcher, aboveSubview: pageContainer)
        switcher.layoutIfNeeded()
        self.switcher = switcher
        pageContainer.isHidden = true
        barHiddenByScroll = false
        return switcher
    }

    func settleSwitcher(_ switcher: TabSwitcherView) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIView.animate(spring: MobileMotion.tabRowSettle) {
            switcher.expansion = 0
            switcher.layoutIfNeeded()
            self.bar.mode = .tabs
            self.layoutChrome()
            self.bar.layoutIfNeeded()
        }
    }

    /// Back from a row that was only peeked at: the card grows into its page again.
    func cancelSwitcher(_ switcher: TabSwitcherView) {
        UIView.animate(spring: MobileMotion.tabOpen) {
            switcher.expansion = 1
            switcher.layoutIfNeeded()
        } completion: {
            self.pageContainer.isHidden = false
            switcher.removeFromSuperview()
            if self.switcher === switcher { self.switcher = nil }
        }
    }

    func tabSwitcher(_ switcher: TabSwitcherView, didSelect id: UUID) {
        store.select(id)
        guard let tab = store.selected else { return }
        show(tab)
        switcher.expandedID = id
        switcher.isUserInteractionEnabled = false
        UIView.animate(spring: MobileMotion.tabOpen) {
            switcher.expansion = 1
            switcher.layoutIfNeeded()
            self.bar.mode = .page
            self.layoutChrome()
            self.bar.layoutIfNeeded()
        } completion: {
            self.pageContainer.isHidden = false
            switcher.removeFromSuperview()
            if self.switcher === switcher { self.switcher = nil }
            self.refreshTabStack()
        }
    }

    func tabSwitcher(_ switcher: TabSwitcherView, didClose id: UUID) {
        if shownPage?.tabID == id {
            shownPage?.webView.removeFromSuperview()
            shownPage?.delegate = nil
            shownPage = nil
        }
        store.archive(id)
        refreshTabStack()
        guard store.tabs.isEmpty else { return }
        // The last tab is gone: back to the backdrop, ready to type.
        self.switcher = nil
        pageContainer.isHidden = false
        bar.mode = .page
        UIView.animate(withDuration: 0.25) { switcher.alpha = 0 } completion: { _ in switcher.removeFromSuperview() }
        setSearching(true, incognito: false)
    }

    // MARK: Onboarding and launch actions

    func showOnboarding() {
        let model = OnboardingModel(canUseAI: BrowseForMe.isAvailable, icon: MobileAppIcon(alternateName: UIApplication.shared.alternateIconName))
        model.setIcon = { AppIconPicker.apply($0) }
        model.openDefaultBrowserSettings = {
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        }
        model.finish = { [weak self] blocks in
            guard let self else { return }
            self.settings.update {
                $0.hasSeenOnboarding = true
                $0.siteDefaults.blockAds = blocks
                $0.siteDefaults.blockTrackers = blocks
            }
            self.topPresenter.dismiss(animated: true) {
                // Now the app opens as it always will: ready to type.
                if !self.didOfferSearchOnLaunch {
                    self.didOfferSearchOnLaunch = true
                    self.setSearching(true, incognito: false)
                }
            }
        }
        let host = UIHostingController(rootView: OnboardingView(model: model))
        host.modalPresentationStyle = .fullScreen
        host.isModalInPresentation = true
        topPresenter.present(host, animated: presentedViewController != nil)
    }

    /// A quick action, shortcut or Siri request, once the browser is on screen.
    @objc func performLaunchAction() {
        guard isViewLoaded, view.window != nil, let action = LaunchAction.pending else { return }
        LaunchAction.pending = nil
        didOfferSearchOnLaunch = true
        switch action {
        case .search(let query):
            if let query, !query.trimmingCharacters(in: .whitespaces).isEmpty {
                incognitoSearch = false
                open(searchDestination(query))
            } else {
                setSearching(true, incognito: false)
            }
        case .browseForMe(let question):
            let query = MobileBrowseForMe.query(fromSelection: question)
            guard !query.isEmpty else { return setSearching(true, incognito: false) }
            incognitoSearch = false
            open(BrowseForMe.isAvailable ? MobileBrowseForMe.tabAddress(query: query) : settings.value.searchEngine.searchURL(query))
        case .voiceSearch:
            setSearching(false)
            beginVoiceSearch(handsFree: true)
        case .spaces:
            setSearching(false)
            showSpaces()
        case .changeIcon:
            let picker = UINavigationController(rootViewController: UIHostingController(rootView: AppIconPicker()))
            picker.sheetPresentationController?.detents = [.medium(), .large()]
            topPresenter.present(picker, animated: true)
        }
    }

    // MARK: Spaces

    /// The Mac's Spaces, from the tab row's left button. A tap on a tab there opens it here.
    @objc func showSpaces() {
        let model = SpacesModel()
        model.favicon = { [weak self] in self?.favicons.icon(for: $0) }
        model.close = { [weak self] in self?.dismiss(animated: true) }
        model.open = { [weak self] address in
            guard let self else { return }
            self.dismiss(animated: true)
            self.incognitoSearch = false
            self.open(address)
        }
        let sheet = UIHostingController(rootView: SpacesView(model: model))
        sheet.sheetPresentationController?.detents = [.large()]
        topPresenter.present(sheet, animated: true)
    }

    // MARK: Settings and archive

    @objc func showArchive() {
        let model = ArchiveModel(tabs: store.archived)
        model.favicon = { [weak self] in self?.favicons.icon(for: $0.url) }
        model.removeTabs = { [weak self] in self?.store.removeArchived($0) }
        model.done = { [weak self] in self?.dismiss(animated: true) }
        model.restore = { [weak self] id in
            guard let self else { return }
            self.dismiss(animated: true)
            self.captureSnapshot()
            self.store.restore(id)
            guard let tab = self.store.selected else { return }
            self.show(tab)
            self.leaveSwitcherForPage()
            self.refreshTabStack()
        }
        let sheet = UIHostingController(rootView: ArchiveView(model: model))
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        topPresenter.present(sheet, animated: true)
    }

    /// App Settings from the tab switcher's gear; Site Settings (which leads on to them) from a page.
    @objc func showSettings() {
        presentSettings(site: nil, startingAtSite: false)
    }

    /// `host` is the page's site; a page without one (a `data:` page, say) edits the global options.
    func presentSettings(site host: String?, startingAtSite: Bool) {
        let model = SettingsModel(store: settings, host: host, canSummarize: BrowseForMe.isAvailable)
        model.done = { [weak self] in self?.dismiss(animated: true) }
        model.showArchive = { [weak self] in self?.showArchive() }
        model.showOnboarding = { [weak self] in self?.showOnboarding() }
        model.showDownloads = { [weak self] in self?.showDownloads() }
        model.exportData = { [weak self] in
            guard let self else { return }
            let share = UIActivityViewController(activityItems: [self.store.document.exportText], applicationActivities: nil)
            share.popoverPresentationController?.sourceView = self.bar
            self.topPresenter.present(share, animated: true)
        }
        model.clearData = { [weak self] history, siteData in
            if history { self?.store.clearArchive() }
            if siteData {
                WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast) {}
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        let sheet: UIViewController
        if startingAtSite {
            sheet = UIHostingController(rootView: SiteSettingsView(model: model))
            // Arc Search's Site Settings stops 465 pt up, leaving the page menu's capsule in view above it.
            sheet.sheetPresentationController?.detents = [.custom { _ in 465 }, .large()]
        } else {
            sheet = UIHostingController(rootView: AppSettingsView(model: model))
            sheet.sheetPresentationController?.detents = [.medium(), .large()]
        }
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        sheet.view.backgroundColor = .clear
        topPresenter.present(sheet, animated: true)
    }

    // MARK: Handoff

    /// Offers the page on screen to the user's other devices. Never an incognito page.
    func offerHandoff(for page: WebPage) {
        let incognito = store.tabs.first { $0.id == page.tabID }?.isIncognito ?? false
        guard !incognito, let url = page.webView.url, url.scheme == "https" || url.scheme == "http" else {
            userActivity?.invalidate()
            userActivity = nil
            return
        }
        let activity = userActivity ?? NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        activity.webpageURL = url
        userActivity = activity
        activity.becomeCurrent()
    }

    // MARK: Downloads

    @objc func showDownloads() {
        let model = DownloadsModel()
        model.done = { [weak self] in self?.dismiss(animated: true) }
        model.open = { [weak self] item in
            guard let self else { return }
            DownloadManager.shared.open(item, from: self.topPresenter)
        }
        let sheet = UIHostingController(rootView: DownloadsView(model: model))
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        topPresenter.present(sheet, animated: true)
    }

    /// A finished download says so in a capsule above the bar; a tap opens the file.
    func downloadFinished(_ item: MobileDownloads.Item) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        announce("Downloaded \(item.name)", symbol: "arrow.down.circle.fill", id: "download-toast") { [weak self] in
            guard let self else { return }
            DownloadManager.shared.open(item, from: self.topPresenter)
        }
    }

    /// A capsule above the bar that says what just happened, gone after four seconds; a tap runs `tap`.
    func announce(_ title: String, symbol: String, id: String, tap: (() -> Void)? = nil) {
        let toast = UIButton(type: .system)
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: symbol)
        configuration.imagePadding = 8
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = Palette.dynamic(light: Palette.rgb(0x2d2c31), dark: Palette.rgb(0xececee))
        configuration.baseForegroundColor = Palette.dynamic(light: .white, dark: .black)
        configuration.titleLineBreakMode = .byTruncatingMiddle
        toast.configuration = configuration
        toast.accessibilityIdentifier = id
        toast.addAction(UIAction { [weak toast] _ in
            toast?.removeFromSuperview()
            tap?()
        }, for: .touchUpInside)
        let width = min(view.bounds.width - 40, 320)
        toast.frame = CGRect(x: (view.bounds.width - width) / 2, y: bar.frame.minY - 54, width: width, height: 42)
        toast.alpha = 0
        view.addSubview(toast)
        UIView.animate(withDuration: 0.25) { toast.alpha = 1 }
        // Faded later by a timer, not a delayed animation: that would set the alpha to zero at
        // once and hide the toast from VoiceOver for the whole time it is on screen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak toast] in
            UIView.animate(withDuration: 0.3) { toast?.alpha = 0 } completion: { _ in toast?.removeFromSuperview() }
        }
    }

    /// The controller on top, so a sheet can be put over another sheet.
    var topPresenter: UIViewController {
        var top: UIViewController = self
        while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
        return top
    }

    /// Drops the tab row at once because a page is taking its place.
    func leaveSwitcherForPage() {
        guard let switcher else { return }
        self.switcher = nil
        pageContainer.isHidden = false
        bar.mode = .page
        UIView.animate(withDuration: 0.2) { switcher.alpha = 0 } completion: { _ in switcher.removeFromSuperview() }
    }

    // MARK: Page menu

    @objc func showMenu() {
        guard let page = shownPage, menuHost == nil, !isSearching else { return }
        let menu = PageMenuView(state: menuState(for: page))
        menu.delegate = self
        let host = SheetHost(content: menu, cornerRadius: MobilePageMenu.cornerRadius) { MobilePageMenu.height(safeBottom: $0) }
        host.onDismiss = { [weak self] in
            self?.menuHost = nil
            self?.menuView = nil
        }
        menuHost = host
        menuView = menu
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        host.present(in: view)
    }

    func menuState(for page: WebPage) -> PageMenuState {
        let host = page.webView.url?.host.map(MobileSettings.siteKey) ?? ""
        return PageMenuState(host: host, canGoBack: page.webView.canGoBack, canGoForward: page.webView.canGoForward,
                             zoom: Double(page.webView.pageZoom), isDesktopSite: page.wantsDesktopSite,
                             canSummarize: BrowseForMe.isAvailable, blockedCount: page.blockedCount,
                             isFavorite: page.webView.url.map { favorites.value.contains($0.absoluteString) } ?? false,
                             isTranslated: page.isTranslated)
    }

    func refreshMenu() {
        guard let page = shownPage, let menuView else { return }
        menuView.apply(menuState(for: page))
    }

    /// The page's address as it is handed out: without tracking parameters.
    var shareableAddress: String? {
        shownPage?.webView.url.map { CleanURL.withoutTrackers($0.absoluteString) }
    }

    func copyLink() {
        guard let address = shareableAddress else { return }
        UIPasteboard.general.string = address
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        menuHost?.dismiss()
    }

    func pageMenuGoBack() { shownPage?.webView.goBack() }
    func pageMenuGoForward() { shownPage?.webView.goForward() }
    func pageMenuReload() {
        shownPage?.webView.reload()
        menuHost?.dismiss()
    }
    func pageMenuToggleFavorite() {
        guard let page = shownPage, let address = shareableAddress else { return }
        favorites.toggle(url: address, title: page.webView.title ?? "")
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        refreshMenu()
    }

    func pageMenu(didPick tile: MobilePageMenu.Tile) {
        switch tile {
        case .copyLink:
            copyLink()
        case .share:
            guard let address = shareableAddress, let url = URL(string: address) else { return }
            menuHost?.dismiss { [weak self] in
                guard let self else { return }
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = self.bar.menuButton
                self.present(share, animated: true)
            }
        case .reader:
            menuHost?.dismiss()
            toggleReader()
        case .summarize:
            menuHost?.dismiss()
            summarize()
        }
    }

    func pageMenu(didPick row: MobilePageMenu.Row) {
        guard let page = shownPage else { return }
        switch row {
        case .findOnPage:
            menuHost?.dismiss {
                page.webView.isFindInteractionEnabled = true
                page.webView.findInteraction?.presentFindNavigator(showingReplace: false)
            }
        case .requestDesktopSite:
            page.wantsDesktopSite.toggle()
            page.webView.reload()
            menuHost?.dismiss()
        case .siteSettings:
            presentSettings(site: page.webView.url?.host.flatMap { $0.isEmpty ? nil : $0 }, startingAtSite: true)
        case .translate:
            menuHost?.dismiss()
            translate(page)
        case .pageZoom:
            break
        }
    }

    func pageMenuZoom(up: Bool) {
        guard let page = shownPage else { return }
        page.webView.pageZoom = CGFloat(MobilePageMenu.zoom(Double(page.webView.pageZoom), stepping: up))
        UISelectionFeedbackGenerator().selectionChanged()
        refreshMenu()
    }

    func pageMenuResetZoom() {
        shownPage?.webView.pageZoom = 1
        refreshMenu()
    }

    func pageMenuReloadWithoutBlockers() {
        shownPage?.reloadWithoutBlockers()
        menuHost?.dismiss()
    }

    // MARK: WebPageDelegate

    func webPageDidChange(_ page: WebPage) {
        if page === shownPage {
            refreshMenu()
            // Reader belongs to the page it was opened on.
            if page.isLoading { closeReader() }
        }
        if page === shownPage { offerHandoff(for: page) }
        // A Browse for Me page has no address of its own: the tab keeps the one that names its query.
        let address = page.webView.url?.absoluteString
        store.update(page.tabID, url: address == "about:blank" ? nil : address, title: page.webView.title)
        if page === shownPage { updateBrowseToggle() }
    }

    func webPage(_ page: WebPage, didFinishLoading success: Bool) {
        if success, store.tabs.first(where: { $0.id == page.tabID })?.isIncognito == false, let address = page.webView.url?.absoluteString {
            page.iconCandidates { [weak self] candidates in self?.favicons.fetch(for: address, candidates: candidates) }
        }
        guard page === shownPage else { return }
        if success, LaunchOptions.summarizesFirstPage, !didSummarizeFirstPage {
            didSummarizeFirstPage = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.summarize() }
        }
        // A moment for the page to paint before its picture is taken.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard page === self?.shownPage else { return }
            self?.captureSnapshot()
        }
    }

    func webPage(_ page: WebPage, didScrollBy delta: CGFloat, atTop: Bool) {
        guard page === shownPage, !isSearching else { return }
        // The bar leaves after 24 pt of scrolling down and returns on the way back up.
        scrollTravel = delta * scrollTravel < 0 ? delta : scrollTravel + delta
        let collapses = settings.value.options(for: page.webView.url?.host).collapseBottomBar
        let hide: Bool
        if atTop || !collapses { hide = false } else if scrollTravel > 24 { hide = true } else if scrollTravel < -24 { hide = false } else { return }
        guard hide != barHiddenByScroll else { return }
        barHiddenByScroll = hide
        animateChrome(duration: 0.25, options: .curveEaseInOut)
    }

    func webPage(_ page: WebPage, openInNewTab url: URL) {
        incognitoSearch = store.selected?.isIncognito ?? false
        open(url.absoluteString)
    }
}
