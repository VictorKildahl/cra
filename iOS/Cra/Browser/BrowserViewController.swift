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

    let backdrop = BackdropView()
    let logo = UIImageView(image: UIImage(named: "LaunchMark"))
    let pageContainer = UIView()
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
    // Reader and Summarize (BrowserReading.swift).
    var readerView: ReaderView?
    var summaryHost: UIViewController?
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
        logo.contentMode = .scaleAspectFit
        view.addSubview(logo)
        view.addSubview(pageContainer)

        dismissArea.addTarget(self, action: #selector(dismissSearch), for: .touchUpInside)
        dismissArea.isHidden = true
        dismissArea.accessibilityIdentifier = "search-dismiss"
        view.addSubview(dismissArea)

        bar.tabsButton.addTarget(self, action: #selector(showTabs), for: .touchUpInside)
        bar.pill.addTarget(self, action: #selector(startSearch), for: .touchUpInside)
        bar.menuButton.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
        bar.archiveButton.addTarget(self, action: #selector(showArchive), for: .touchUpInside)
        bar.settingsButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        view.addSubview(bar)

        sheet.delegate = self
        sheet.isHidden = true
        view.addSubview(sheet)

        installGestures()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)

        ContentBlocker.shared.prepare()
        store.archiveStale(after: settings.value.archiveAfter)
        if let tab = store.selected { show(tab) }
        refreshTabStack()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Arc Search opens ready to type: the sheet comes up with the keyboard on launch.
        if !didOfferSearchOnLaunch {
            didOfferSearchOnLaunch = true
            let wantsSearch = (settings.value.opensKeyboardOnLaunch && !LaunchOptions.skipsSearch) || store.selected == nil
            if wantsSearch { setSearching(true, incognito: false) }
            if isSearching, let typed = LaunchOptions.typedText {
                sheet.text = typed
                searchSheet(sheet, didChangeText: typed)
            }
        }
    }

    var didOfferSearchOnLaunch = false
    var didSummarizeFirstPage = false

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
        pageContainer.frame = bounds
        switcher?.frame = bounds
        shownPage?.webView.frame = pageContainer.bounds
        let logoSide: CGFloat = 132
        logo.frame = CGRect(x: bounds.midX - logoSide / 2, y: bounds.height * 0.505 - logoSide / 2, width: logoSide, height: logoSide)

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

    @objc func appWillResignActive() {
        captureSnapshot()
        store.saveNow()
    }

    // MARK: Search

    @objc func startSearch() {
        setSearching(true, incognito: store.selected?.isIncognito ?? false)
    }

    @objc func dismissSearch() {
        // With no page or tab row to go back to, the sheet stays: there is nothing else to show.
        guard store.selected != nil || switcher != nil else { return }
        setSearching(false)
    }

    func setSearching(_ searching: Bool, incognito: Bool? = nil) {
        guard searching != isSearching else { return }
        if searching {
            if let incognito { incognitoSearch = incognito }
            sheet.isIncognito = incognitoSearch
            sheet.text = ""
            sheet.setRows([])
            sheet.offersBrowseForMe = BrowseForMe.isAvailable
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
        sheet.setRows(MobileSuggestions.rows(typed: text, completions: []))
        // Incognito keeps what is typed on the phone until Go.
        guard !incognitoSearch else { return }
        suggestions.completions(for: text, engine: engine) { [weak self, weak sheet] found in
            guard let self, let sheet, self.isSearching, sheet.text == text else { return }
            sheet.setRows(MobileSuggestions.rows(typed: text, completions: found))
        }
    }

    func searchSheet(_ sheet: SearchSheet, didSubmit text: String) {
        open(MobileSuggestions.destination(forTyped: text, engine: settings.value.searchEngine))
    }

    func searchSheet(_ sheet: SearchSheet, didPick row: MobileSuggestions.Row) {
        open(MobileSuggestions.destination(for: row, engine: settings.value.searchEngine))
    }

    func searchSheet(_ sheet: SearchSheet, didAskToBrowseFor row: MobileSuggestions.Row) {
        open(MobileSuggestions.destination(for: row, engine: settings.value.searchEngine))
    }

    func searchSheetDidToggleIncognito(_ sheet: SearchSheet) {
        incognitoSearch.toggle()
        sheet.isIncognito = incognitoSearch
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
        pageContainer.addSubview(page.webView)
        if page.webView.url == nil { page.load(tab.url) }
        barHiddenByScroll = false
        scrollTravel = 0
        view.setNeedsLayout()
    }

    func refreshTabStack() {
        let tabs = store.tabs
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
        let present = { [self] in
            let switcher = TabSwitcherView(frame: view.bounds)
            switcher.delegate = self
            switcher.setTabs(store.tabs, focus: store.selected?.id, snapshot: store.snapshot, favicon: { self.favicons.icon(for: $0.url) })
            // Starts as the page itself: the focused card fills the screen, then shrinks into the row.
            switcher.expandedID = store.selected?.id
            switcher.expansion = store.selected == nil ? 0 : 1
            view.insertSubview(switcher, aboveSubview: pageContainer)
            switcher.layoutIfNeeded()
            self.switcher = switcher
            pageContainer.isHidden = true
            barHiddenByScroll = false
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0,
                           options: [.allowUserInteraction]) {
                switcher.expansion = 0
                switcher.layoutIfNeeded()
                self.bar.mode = .tabs
                self.layoutChrome()
                self.bar.layoutIfNeeded()
            }
        }
        guard let page = shownPage else { return present() }
        let id = page.tabID
        page.takeSnapshot { [weak self] image in
            if let image { self?.store.setSnapshot(image, for: id) }
            present()
        }
    }

    func tabSwitcher(_ switcher: TabSwitcherView, didSelect id: UUID) {
        store.select(id)
        guard let tab = store.selected else { return }
        show(tab)
        switcher.expandedID = id
        switcher.isUserInteractionEnabled = false
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
            switcher.expansion = 1
            switcher.layoutIfNeeded()
            self.bar.mode = .page
            self.layoutChrome()
            self.bar.layoutIfNeeded()
        } completion: { _ in
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
                             canSummarize: BrowseForMe.isAvailable, blockedCount: page.blockedCount)
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
    func pageMenuCopyLinkFromCapsule() { copyLink() }

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
        case .pageZoom, .translate:
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
        store.update(page.tabID, url: page.webView.url?.absoluteString, title: page.webView.title)
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
