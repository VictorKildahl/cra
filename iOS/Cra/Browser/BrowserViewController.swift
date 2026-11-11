import CraCore
import UIKit
import WebKit

/// The whole browser: the page, the bar under it, and the search sheet that grows out of the
/// bar's pill when the keyboard comes up.
final class BrowserViewController: UIViewController, SearchSheetDelegate, WebPageDelegate {
    let store: TabStore
    private let settings: MobileSettingsStore
    private let suggestions = SuggestionService()

    private let backdrop = BackdropView()
    private let logo = UIImageView(image: UIImage(named: "LaunchMark"))
    private let pageContainer = UIView()
    private let dismissArea = UIControl()
    private let bar = BottomBar()
    private let sheet = SearchSheet()

    private var shownPage: WebPage?
    private(set) var isSearching = false
    private var incognitoSearch = false
    private var keyboardHeight: CGFloat = 0
    private var keyboardDroveLayout = false
    private var barHiddenByScroll = false
    private var scrollTravel: CGFloat = 0

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
        view.addSubview(bar)

        sheet.delegate = self
        sheet.isHidden = true
        view.addSubview(sheet)

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        center.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)

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

    private var didOfferSearchOnLaunch = false

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutChrome()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // MARK: Layout

    /// Puts the bar and the sheet where the current state says. Called inside animation blocks.
    private func layoutChrome() {
        let bounds = view.bounds
        backdrop.frame = bounds
        pageContainer.frame = bounds
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
        logo.alpha = isSearching || store.selected != nil ? 0 : 1
        updatePageInsets()
    }

    /// Lets the page scroll clear of the bar.
    private func updatePageInsets() {
        guard let scroll = shownPage?.webView.scrollView else { return }
        let inset = barHiddenByScroll ? 0 : MobileBottomBar.height
        if scroll.contentInset.bottom != inset {
            scroll.contentInset.bottom = inset
            scroll.verticalScrollIndicatorInsets.bottom = inset
        }
    }

    private func animateChrome(duration: TimeInterval, options: UIView.AnimationOptions) {
        UIView.animate(withDuration: duration, delay: 0, options: options.union([.beginFromCurrentState, .allowUserInteraction])) {
            self.layoutChrome()
            self.bar.layoutIfNeeded()
            self.sheet.layoutIfNeeded()
        } completion: { _ in
            self.chromeSettled()
        }
    }

    private func chromeSettled() {
        guard !isSearching else { return }
        sheet.isHidden = true
        bar.pill.alpha = 1
    }

    @objc private func keyboardWillChange(_ note: Notification) {
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

    @objc private func appWillResignActive() {
        captureSnapshot()
        store.saveNow()
    }

    // MARK: Search

    @objc private func startSearch() {
        setSearching(true, incognito: store.selected?.isIncognito ?? false)
    }

    @objc private func dismissSearch() {
        // With no page to go back to, the sheet stays: there is nothing else to show.
        guard store.selected != nil else { return }
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
        setSearching(false)
        refreshTabStack()
    }

    private func show(_ tab: MobileTab) {
        let page = store.page(for: tab)
        guard page !== shownPage else { return }
        shownPage?.webView.removeFromSuperview()
        shownPage?.delegate = nil
        shownPage = page
        page.delegate = self
        page.webView.frame = pageContainer.bounds
        pageContainer.addSubview(page.webView)
        if page.webView.url == nil { page.load(tab.url) }
        barHiddenByScroll = false
        scrollTravel = 0
        view.setNeedsLayout()
    }

    private func refreshTabStack() {
        let tabs = store.tabs
        let front = store.selected ?? tabs.last
        let back = tabs.last { $0.id != front?.id }
        bar.tabsButton.setSnapshots(front: front.flatMap { store.snapshot($0.id) }, back: back.flatMap { store.snapshot($0.id) })
    }

    private func captureSnapshot() {
        guard let page = shownPage else { return }
        let id = page.tabID
        page.takeSnapshot { [weak self] image in
            guard let self, let image else { return }
            self.store.setSnapshot(image, for: id)
            self.refreshTabStack()
        }
    }

    @objc private func showTabs() {
        captureSnapshot()
    }

    @objc private func showMenu() {
    }

    // MARK: WebPageDelegate

    func webPageDidChange(_ page: WebPage) {
        store.update(page.tabID, url: page.webView.url?.absoluteString, title: page.webView.title)
    }

    func webPage(_ page: WebPage, didFinishLoading success: Bool) {
        guard page === shownPage else { return }
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
        let hide: Bool
        if atTop { hide = false } else if scrollTravel > 24 { hide = true } else if scrollTravel < -24 { hide = false } else { return }
        guard hide != barHiddenByScroll else { return }
        barHiddenByScroll = hide
        animateChrome(duration: 0.25, options: .curveEaseInOut)
    }

    func webPage(_ page: WebPage, openInNewTab url: URL) {
        incognitoSearch = store.selected?.isIncognito ?? false
        open(url.absoluteString)
    }
}
