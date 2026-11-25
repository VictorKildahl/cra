import CraCore
import SwiftUI
import UIKit
import WebKit

/// The whole browser: the page, the bar under it, and the search sheet that grows out of the
/// bar's pill when the keyboard comes up.
/// The canvas colour over a new tab from the search sheet while its page draws (`coverUntilDrawn`), with an opaque
/// curtain of it right over the page. For a UI test (`-CraTraceCover YES`) it says whether that page and the band
/// behind the status bar are out of sight under it.
final class NewPageCover: UIView {
    let curtain = UIView()
    weak var band: UIView?

    override var accessibilityValue: String? {
        get {
            let bandShows = band.map { !$0.isHidden } ?? false
            return (curtain.superview != nil ? "page hidden" : "page showing") + (bandShows ? ", band showing" : ", band hidden")
        }
        set {}
    }
}

final class BrowserViewController: UIViewController, SearchSheetDelegate, WebPageDelegate, TabSwitcherDelegate, PageMenuDelegate {
    let store: TabStore
    let settings: MobileSettingsStore
    let suggestions = SuggestionService()
    let favicons = FaviconStore()
    lazy var favorites = FavoritesStore(directory: LaunchOptions.dataDirectory)

    let backdrop = BackdropView()
    /// The empty home screen: Cra's logo, which spins when flicked, and with Rippling Dots on (`MobileEmptyHome`)
    /// dots a finger stirs under it and "Tap to search" over the pill.
    let logo = FidgetLogoView(image: UIImage(named: "LaunchMark"))
    let dotField = DotFieldView()
    let searchHint = SearchHintView()
    let pageContainer = PassthroughView()
    /// Darkens the page while it sits pushed back behind the search sheet.
    let pageDim = UIView()
    /// The band behind the status bar over a page (updateStatusBand), and the colour it shows.
    let statusBand = UIView()
    /// Darkens the status band with the page behind the search sheet's dim.
    let statusBandDim = UIView()
    private var statusBandFill: String?
    var pagePushedBack = false
    /// The chrome's moves under way: the sheet is put away when the last ends (`MobileSearchSheet.Settling`).
    private var chromeMoves = MobileSearchSheet.Settling()
    /// The sheet is opening: keep the page as it is until the open animation lays it out, so a
    /// layout pass in between cannot apply the push-back in one frame.
    var pageOpening = false
    /// How far the search drawer is open, 0…1: the page is pushed back exactly as far.
    var drawerProgress: CGFloat = 0
    /// The sheet is closing: keep the page as the pushed-back card until the close animation
    /// lays it out, so a layout pass in between cannot snap its top to the display's top.
    var pageClosing = false
    let dismissArea = UIControl()
    /// Over a new tab opened from the search sheet until its page has drawn (`MobileSheetLeave.liftsCover`): the
    /// page it covers, when the cover went up, and when the page said it had drawn.
    let newPageCover = NewPageCover()
    var coveredPage: (page: WebPage, since: CFTimeInterval, drawnAt: CFTimeInterval?)?
    /// For UI tests (`-CraTraceSheetDrag YES`): of the last drag down on the open sheet, how many frames had the sheet
    /// out of sight under the keyboard (#655).
    let sheetDragTraceView = UIView()
    var sheetDragTrace = (frames: 0, hidden: 0)
    /// How far above the bar the open sheet's top was when a drag down on it started (#655).
    var sheetDragStartPull: CGFloat?
    /// Over the home indicator's strip while scrolling has put the bar away: a tap there brings
    /// it back (#509). A button, since a plain control there loses its tap to the page's gestures.
    let barReveal = UIButton(type: .custom)
    let bar = BottomBar()
    let sheet = SearchSheet()

    /// The page on screen. The Browse for Me switch follows it, so a closed tab takes its switch with it.
    var shownPage: WebPage? {
        didSet { if shownPage !== oldValue { updateBrowseToggle() } }
    }
    var switcher: TabSwitcherView?
    var menuHost: SheetHost?
    var menuView: PageMenuView?
    /// Arc Search's blocker notices (`BlockerNotices.swift`): the one-time tip, and the question
    /// after a page was restored without blockers, with the tab that was restored.
    var blockTip: BlockTipView?
    var fixPill: FixQuestionPill?
    var fixPending: UUID?
    /// "Tap Browse for Me for a faster answer" over the sheet while the starter questions show.
    let coachMark = CoachMarkView()
    // Swipes (BrowserGestures.swift).
    var swipeNeighbour: UIImageView?
    var flick = FlickState()
    /// When the page on screen was last swapped in: its web view takes a moment to draw, and a
    /// picture taken before then is black.
    var pageShownAt: CFTimeInterval = 0

    /// The tab's visible area: under the iOS status bar and above the app's bottom bar.
    var tabArea: CGRect {
        let top = view.safeAreaInsets.top
        let bottom = view.bounds.height - (MobileBottomBar.height + view.safeAreaInsets.bottom)
        return CGRect(x: 0, y: top, width: view.bounds.width, height: max(0, bottom - top))
    }

    var swipeNeighbourStep = 0
    var tabArchivedBySwipe: UUID?
    /// What the finger was on when the swipe across the page started (#627).
    weak var pageSwipeTouchView: UIView?
    /// Where the bar swipe's finger came down, in the bar's coordinates (#537): the pan begins
    /// only after a few points of travel, so its location at `.began` is not the start.
    var barSwipeStart: CGPoint?
    var barSwipeOpensRow = false
    var barSwipePullsSearch = false
    /// How far up the search sheet is being pulled out of the pill, while it is (#623).
    var searchPull: CGFloat?
    /// A pulled sheet let go: where it stays, and how open its field is, until the keyboard comes (#623).
    var pulledSheetHold: (top: CGFloat, openness: CGFloat)?
    /// A drag up from the tab button: the tab it brings back (#537).
    var barSwipeTarget: MobileTab?
    // Voice search (BrowserGestures.swift).
    var voice: VoiceSearch?
    var voiceOverlay: VoiceOverlayView?
    /// Whether what is heard opens incognito: the tab's state, or the search sheet's when the mic there started it.
    var voiceIsIncognito = false
    // Reader and Summarize (BrowserReading.swift).
    var readerView: ReaderView?
    var summaryHost: UIViewController?
    var browseLoading: BrowseLoadingView?
    /// The switch between Browse for Me and the search engine (BrowserReading.swift).
    let browseToggle = BrowseToggleView()
    var browseToggleState: (side: MobileBrowseToggle.Side, query: String)?
    var isSearching = false
    var incognitoSearch = false
    /// The sheet is editing the address of the page on screen (#572): what it opens loads there.
    var editsShownTab = false
    var keyboardHeight: CGFloat = 0
    /// The last height the software keyboard showed at: the page's push-back follows the drawer
    /// to where it opens with the keyboard, even on the frame before the keyboard is measured.
    var lastKeyboardHeight: CGFloat = 0
    var keyboard = MobileKeyboard()
    var keyboardDroveLayout = false
    /// Scrolling puts the bar away where Collapse Bottom Bar is on (`MobileBarCollapse`).
    var barCollapse = MobileBarCollapse()
    var barHiddenByScroll: Bool { barCollapse.isHidden }

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
        view.addSubview(dotField)
        view.addSubview(logo)
        view.addSubview(searchHint)
        view.addSubview(pageContainer)
        pageDim.backgroundColor = .black
        pageDim.alpha = 0
        pageDim.isUserInteractionEnabled = false
        pageContainer.addSubview(pageDim)
        // Over the page, under nothing: pages, the reader and the loading views go in below pageDim.
        statusBand.isUserInteractionEnabled = false
        pageContainer.addSubview(statusBand)
        statusBandDim.backgroundColor = .black
        statusBandDim.alpha = 0
        statusBandDim.isUserInteractionEnabled = false
        pageContainer.addSubview(statusBandDim)
        pageContainer.layer.cornerCurve = .continuous
        pageContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        dismissArea.addTarget(self, action: #selector(dismissSearch), for: .touchUpInside)
        dismissArea.isHidden = true
        dismissArea.accessibilityIdentifier = "search-dismiss"
        view.addSubview(dismissArea)
        if LaunchOptions.value("CraTraceSheetDrag") == "YES" {
            sheetDragTraceView.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            sheetDragTraceView.isAccessibilityElement = true
            sheetDragTraceView.accessibilityIdentifier = "sheet-drag-trace"
            sheetDragTraceView.isUserInteractionEnabled = false
            view.addSubview(sheetDragTraceView)
        }
        PressHaptics.installCounter(in: view)

        bar.tabsButton.addTarget(self, action: #selector(showTabs), for: .touchUpInside)
        bar.pill.addTarget(self, action: #selector(startSearch), for: .touchUpInside)
        bar.menuButton.addTarget(self, action: #selector(showMenu), for: .touchUpInside)
        bar.spacesButton.addTarget(self, action: #selector(showSpaces), for: .touchUpInside)
        bar.settingsButton.addTarget(self, action: #selector(showSettings), for: .touchUpInside)
        browseToggle.alpha = 0
        browseToggle.onPick = { [weak self] side in self?.browseTogglePicked(side) }
        view.addSubview(browseToggle)
        barReveal.addTarget(self, action: #selector(revealBar), for: .touchUpInside)
        barReveal.isHidden = true
        barReveal.accessibilityIdentifier = "bar-reveal"
        barReveal.accessibilityLabel = "Show Bottom Bar"
        view.addSubview(barReveal)
        view.addSubview(bar)

        sheet.delegate = self
        sheet.siteIcon = { [weak self] address in self?.favicons.icon(for: address) }
        sheet.isHidden = true
        view.addSubview(sheet)
        view.addSubview(coachMark)

        installGestures()

        let center = NotificationCenter.default
        for name in [UIResponder.keyboardWillShowNotification, UIResponder.keyboardWillChangeFrameNotification,
                     UIResponder.keyboardWillHideNotification, UIResponder.keyboardDidHideNotification] {
            center.addObserver(self, selector: #selector(keyboardWillChange(_:)), name: name, object: nil)
        }
        center.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        Self.saveFakeShareForTest()
        center.addObserver(self, selector: #selector(performLaunchAction), name: LaunchAction.notification, object: nil)
        center.addObserver(self, selector: #selector(faviconsChanged), name: FaviconStore.didChange, object: nil)

        ContentBlocker.shared.prepare()
        BlockLists.shared.set(addresses: settings.value.customBlocklists)
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
            if LaunchOptions.holdsPill { bar.pill.isHighlighted = true }
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
        // The sheet's own animation lays the chrome out from the page's current state.
        guard !pageClosing, !pageOpening else { return }
        layoutChrome()
    }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        // While a tab is flying in, the bar over it is that tab's, not the page still behind; it
        // keeps it until that page's own band is known, so the bar does not flash on landing.
        if let fill = flick.statusFill {
            return MobileStatusBand.lightContent(fill: fill) ? .lightContent : .darkContent
        }
        guard !statusBand.isHidden, let fill = statusBandFill else { return .default }
        return MobileStatusBand.lightContent(fill: fill) ? .lightContent : .darkContent
    }

    /// The solid band behind the status bar over a page, in the page's colour, as in Arc Search (#657).
    func updateStatusBand() {
        let page = shownPage
        let fill = page.flatMap { MobileStatusBand.fill(themeColor: Palette.hex($0.webView.themeColor, traits: traitCollection),
                                                        underPage: Palette.hex($0.webView.underPageBackgroundColor, traits: traitCollection)) }
        // The page the flick brought now knows its band: it takes the bar back from the estimate.
        if let id = flick.statusPage, page?.tabID == id, fill != nil {
            flick.statusPage = nil
            flick.statusFill = nil
            setNeedsStatusBarAppearanceUpdate()
        }
        // The band is the page's top: it shrinks from the status bar to nothing as the page is
        // pushed back, its bottom staying at the card's top edge.
        let shown = fill != nil && MobileStatusBand.shown(hasPage: page != nil, searching: false,
                                                        switching: switcher != nil, covered: coveredPage != nil)
        let safeTop = view.safeAreaInsets.top
        let pageScale = MobilePageBehindSearch.transform(in: pageContainer.bounds.size, safeTop: safeTop,
                                                         progress: drawerProgress).scale
        let bandHeight = shown ? safeTop * (1 - drawerProgress) / max(pageScale, 0.001) : 0
        // Keep it in the hierarchy until its height is zero: hiding it when the target height
        // reaches zero would make it vanish instead of shrinking with the animation.
        let visible = shown
        statusBand.frame = CGRect(x: 0, y: 0, width: pageContainer.bounds.width, height: bandHeight)
        statusBandDim.frame = statusBand.frame
        statusBandDim.alpha = visible ? MobilePageBehindSearch.dim * drawerProgress : 0
        if let color = fill.flatMap(Palette.color(hex:)) {
            statusBand.backgroundColor = color
        }
        if statusBand.isHidden == visible || statusBandFill != fill {
            statusBand.isHidden = !visible
            statusBandFill = fill
            setNeedsStatusBarAppearanceUpdate()
        }
    }

    // MARK: Layout

    /// Puts the bar and the sheet where the current state says. Called inside animation blocks.
    func layoutChrome() {
        let bounds = view.bounds
        let sides = MobileSideInsets.applied(size: bounds.size, safeLeft: view.safeAreaInsets.left, safeRight: view.safeAreaInsets.right)
        sheet.sideInsets = sides
        let safeBottom = view.safeAreaInsets.bottom
        let safeTop = view.safeAreaInsets.top
        let frames = MobileBottomBar.frames(in: bounds.size, safeBottom: safeBottom)
        // The drawer's progress from closed to fully open: the page is pushed back exactly that
        // far, so opening and closing follow the sheet's position. The last keyboard height lets
        // the first frame aim for where the drawer opens with the keyboard.
        let keyboard = max(keyboardHeight, safeBottom)
        let expectedKeyboard = max(keyboardHeight, lastKeyboardHeight, safeBottom)
        let closedTop = frames.bar.minY
        let currentTop = isSearching
            ? MobileSearchSheet.openingTop(screenHeight: bounds.height, keyboardHeight: keyboard,
                                           safeTop: safeTop, heldAt: pulledSheetHold?.top)
            : closedTop - max(0, searchPull ?? 0)
        let openTop = MobileSearchSheet.openingTop(screenHeight: bounds.height, keyboardHeight: expectedKeyboard,
                                                   safeTop: safeTop, heldAt: nil)
        drawerProgress = min(1, max(0, (closedTop - currentTop) / max(1, closedTop - openTop)))

        backdrop.frame = bounds
        // Bounds and centre, not frame: the container may be transformed (pushed back, swiped).
        // While a flick's arriving tab flies in, it owns the container's place and shape.
        if !flick.incoming {
            pageContainer.bounds = CGRect(origin: .zero, size: bounds.size)
            pageContainer.center = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        switcher?.frame = bounds
        // The page's viewport stays the one it had before the push-back. The web view keeps its
        // size and slides up inside the page as the card comes down, so its content's top stays
        // at the card's top with no empty space, without changing the viewport.
        if let page = shownPage, !pageClosing, !pageOpening, !flick.incoming {
            let scale = drawerProgress > 0.001
                ? MobilePageBehindSearch.transform(in: bounds.size, safeTop: safeTop, progress: drawerProgress).scale
                : 1
            let webTop = drawerProgress > 0.001
                ? safeTop * ((1 - drawerProgress) / max(scale, 0.001) - 1)
                : 0
            page.webView.frame = CGRect(x: 0, y: webTop, width: bounds.width, height: bounds.height)
        }
        pageDim.frame = pageContainer.bounds
        dotField.frame = bounds
        updateStatusBand()
        let logoSide: CGFloat = 132
        logo.bounds = CGRect(x: 0, y: 0, width: logoSide, height: logoSide)
        logo.center = CGPoint(x: bounds.midX, y: bounds.height * 0.505)

        // While the search sheet is up over a page, the page sits back as a dimmed card under
        // the status bar (Arc Search's look; `MobilePageBehindSearch`), as far back as the sheet
        // is open. Editing the page's own address keeps it still, only dimmed.
        if flick.incoming {
            // The arriving tab is the page itself, on its way into place.
        } else if pageOpening, isSearching {
            // The open animation owns the page's way back; leave it as it is until then.
        } else if pageClosing, !isSearching {
            // The close animation owns the page's way back; leave the card where it is until then.
        } else if editsShownTab, isSearching || drawerProgress > 0.001 || pageClosing {
            pageContainer.transform = .identity
            pageContainer.layer.cornerRadius = 0
            pageDim.alpha = MobilePageBehindSearch.dim * drawerProgress
            pagePushedBack = drawerProgress > 0.001
        } else if drawerProgress > 0.001, shownPage != nil, switcher == nil {
            let card = MobilePageBehindSearch.transform(in: bounds.size, safeTop: safeTop, progress: drawerProgress)
            pageContainer.transform = CGAffineTransform(translationX: 0, y: card.shiftDown)
                .scaledBy(x: card.scale, y: card.scale)
            // The card's rounding is at its fullest the moment the page goes back; only the
            // card's movement is eased, not its corners growing in.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pageContainer.layer.cornerRadius = MobilePageBehindSearch.cornerRadius / card.scale
            CATransaction.commit()
            pageDim.alpha = MobilePageBehindSearch.dim * drawerProgress
            pageContainer.clipsToBounds = true
            pagePushedBack = true
        } else if pagePushedBack {
            pageContainer.transform = .identity
            pageContainer.layer.cornerRadius = 0
            pageDim.alpha = 0
            pagePushedBack = false
        }

        var barFrame = frames.bar
        let keyboardUpForPage = keyboardHeight > safeBottom && !isSearching
        if (barHiddenByScroll || keyboardUpForPage) && !isSearching { barFrame.origin.y = bounds.height }
        bar.frame = barFrame
        let home = store.selected == nil && switcher == nil
        let pull = isSearching ? nil : searchPull
        let emptyHome = MobileEmptyHome(dots: settings.value.homeDots, home: home, searching: isSearching,
                                        incognitoSearch: incognitoSearch, pulling: pull != nil)
        backdrop.style = emptyHome.backdrop
        // With the dots the bar has no slab: its buttons float on them.
        bar.overBackdrop = emptyHome.barFloats
        searchHint.place(centerX: bounds.midX, pillTop: frames.pill.minY + barFrame.minY - frames.bar.minY)
        // Pulled out of the pill (#623), the sheet's top follows the finger and its field grows
        // from the pill on the way up.
        let pulled = pull.map { MobileSwipe.searchPullProgress(dragUp: $0) }
        bar.controlsVisibility = isSearching ? 0 : 1 - (pulled ?? 0)
        barReveal.frame = MobileBottomBar.revealStrip(in: bounds.size, safeBottom: safeBottom)
        barReveal.isHidden = !barHiddenByScroll || isSearching || switcher != nil || shownPage == nil
        placeBlockerNotices()
        placeCoachMark()

        sheet.rowsInView = MobileSearchSheet.rowsInView(screenHeight: bounds.height, keyboardHeight: keyboard, safeTop: safeTop)
        let top = isSearching ? currentTop : barFrame.minY - max(0, pull ?? 0)
        sheet.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(MobileSearchSheet.height(rows: sheet.rowsInView) + keyboard, bounds.height - top))
        sheet.collapsedFieldFrame = bar.pillFrame
        sheet.openness = isSearching ? pulledSheetHold?.openness ?? 1 : pulled ?? 0
        dismissArea.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, top))
        logo.alpha = emptyHome.showsLogo ? 1 : 0
        dotField.alpha = emptyHome.showsDots ? 1 : 0
        searchHint.alpha = emptyHome.showsSearchHint ? 1 : 0
        layoutBrowseToggle(barTop: barFrame.minY)
        if !isSearching, !pageClosing, !pageOpening, !flick.incoming, drawerProgress <= 0.001 { updatePageInsets() }
    }

    /// Lets the page scroll clear of the bar and the status bar. While the search sheet is up
    /// the bar's space stays in the page: the viewport must not grow as the page is pushed back.
    func updatePageInsets() {
        guard let scroll = shownPage?.webView.scrollView else { return }
        let safe = view.safeAreaInsets
        let bar = (barHiddenByScroll && !isSearching) ? 0 : MobileBottomBar.height
        let insets = UIEdgeInsets(top: safe.top, left: safe.left, bottom: bar + safe.bottom, right: safe.right)
        if scroll.contentInset != insets {
            scroll.contentInset = insets
        }
        // The indicator's track already follows the content inset, so insetting it by the safe
        // area as well put it a whole status bar too low. Only the bar needs its own room.
        scroll.verticalScrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: bar, right: 0)
    }

    func animateChrome(duration: TimeInterval, options: UIView.AnimationOptions) {
        chromeMoves.began()
        UIView.animate(withDuration: duration, delay: 0, options: options.union([.beginFromCurrentState, .allowUserInteraction])) {
            self.pageOpening = false
            self.pageClosing = false
            self.layoutChrome()
            self.bar.layoutIfNeeded()
            self.sheet.layoutIfNeeded()
        } completion: { _ in
            // Only once every move has ended: one that moved nothing (a second keyboard notice) ends at once.
            guard self.chromeMoves.ended() else { return }
            self.chromeSettled()
        }
    }

    func chromeSettled() {
        guard !isSearching, searchPull == nil else { return }
        sheet.isHidden = true
        bar.pill.alpha = 1
    }

    @objc func keyboardWillChange(_ note: Notification) {
        guard let info = note.userInfo, let end = info[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let duration = info[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let curve = info[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let event: MobileKeyboard.Event
        switch note.name {
        case UIResponder.keyboardWillShowNotification: event = .willShow
        case UIResponder.keyboardWillHideNotification: event = .willHide
        case UIResponder.keyboardDidHideNotification: event = .didHide
        default: event = .willChangeFrame
        }
        keyboard.apply(event, endFrame: view.convert(end, from: nil))
        let height = keyboard.height(in: view.bounds)
        // The did-hide is only a backstop: nothing to move when the will-hide already counted it gone.
        guard event != .didHide || height != keyboardHeight else { return }
        keyboardHeight = height
        if height > 0 { lastKeyboardHeight = height }
        keyboardDroveLayout = true
        pulledSheetHold = nil
        if duration > 0 {
            animateChrome(duration: duration, options: UIView.AnimationOptions(rawValue: curve << 16))
        } else {
            pageOpening = false
            pageClosing = false
            layoutChrome()
            if chromeMoves.running == 0 { chromeSettled() }
        }
    }

    @objc func appDidBecomeActive() {
        takeSharedLinks()
        BlockLists.shared.refreshDue()
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
    /// backdrop, the logo (over the dots and "Tap to search" with Rippling Dots on) and the bar.
    @objc func dismissSearch() {
        setSearching(false)
    }

    /// `keepingPull`: closing, the sheet stays this far above the bar under the finger (a drag down on it, #655)
    /// instead of going into the pill; the drag moves it on from there.
    /// `replacingMenuAt`: the sheet takes the page menu's place: its top starts where the menu's
    /// panel was, its field already full size, so the address turns editable in place.
    /// `editingAddress`: the sheet edits the page on screen; the page behind stays where it is
    /// instead of being pushed back, as only a search from the + button does.
    func setSearching(_ searching: Bool, incognito: Bool? = nil, keepingPull: CGFloat? = nil,
                      replacingMenuAt replacingTop: CGFloat? = nil, editingAddress: Bool = false) {
        guard searching != isSearching else { return }
        if searching { liftCover() }
        // A sheet pulled out of the pill is already laid out under the finger: it goes on from there.
        let pulled = searchPull != nil
        let replacing = searching ? replacingTop : nil
        searchPull = searching ? nil : keepingPull
        pulledSheetHold = searching && (pulled || replacing != nil)
            ? (replacing ?? sheet.frame.minY, replacing != nil ? 1 : sheet.openness)
            : nil
        if searching, !pulled {
            prepareSearchSheet(incognito: incognito)
            editsShownTab = editingAddress
            // Starts from the pill: lay the closed state out before anything animates. Taking
            // the menu's place, it is laid out below, where the menu was.
            if replacing == nil {
                UIView.performWithoutAnimation {
                    self.layoutChrome()
                    self.sheet.layoutIfNeeded()
                }
            }
        } else if !searching {
            suggestions.cancel()
            // `editsShownTab` stays until the next search: while this sheet drags down, the page
            // behind an edited address must stay still, not push back.
        }
        isSearching = searching
        pageOpening = searching && !pulled && shownPage != nil
        pageClosing = !searching && keepingPull == nil && pagePushedBack
            && pageContainer.transform != .identity && switcher == nil
        dismissArea.isHidden = !searching
        keyboardDroveLayout = false
        // Off on the tap's next frame, at its fastest, as Arc Search's (`MobileSearchMotion.leadDuration`): the move
        // goes to the render server before the keyboard is asked for, which keeps the main thread busy for tens of
        // milliseconds on a phone, and the keyboard's own animation takes it over when it comes.
        let leads = searching && !pulled && replacing == nil
        if leads {
            animateChrome(duration: MobileSearchMotion.leadDuration, options: .curveEaseOut)
            CATransaction.flush()
        }
        if searching {
            if replacing != nil {
                // Same drawer, new content: the field sits where the address capsule was.
                UIView.performWithoutAnimation {
                    self.layoutChrome()
                    self.sheet.layoutIfNeeded()
                }
            }
            sheet.field.becomeFirstResponder()
        } else {
            sheet.field.resignFirstResponder()
        }
        // No software keyboard (a hardware one is attached): move the chrome ourselves. A pulled
        // sheet waits a moment for the keyboard, whose animation takes it up (#623).
        if !keyboardDroveLayout {
            if pulledSheetHold != nil {
                // The page behind sits back now; the sheet stays where it was let go.
                animateChrome(duration: 0.35, options: .curveEaseInOut)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, self.isSearching, self.pulledSheetHold != nil else { return }
                    self.pulledSheetHold = nil
                    self.animateChrome(duration: 0.35, options: .curveEaseInOut)
                }
            } else if !leads {
                animateChrome(duration: 0.35, options: .curveEaseInOut)
            }
        }
    }

    /// Fills the sheet for a new search and puts it in place of the pill, still closed.
    func prepareSearchSheet(incognito: Bool? = nil) {
        dropBlockerNotices()
        editsShownTab = false
        if let incognito { incognitoSearch = incognito }
        sheet.isIncognito = incognitoSearch
        backdrop.isIncognito = incognitoSearch
        sheet.text = ""
        sheet.setRows([])
        sheet.offersBrowseForMe = BrowseForMe.isOffered
        sheet.setFavorites(favorites.value.shown().map { ($0, favicons.icon(for: $0.url)) })
        updateRecentTabs()
        SyncedSidebar.hasSpaces { [weak self] _ in
            guard let self, self.isSearching else { return }
            if self.sheet.text.isEmpty { self.updateRecentTabs() }
            else { self.searchSheet(self.sheet, didChangeText: self.sheet.text) }
        }
        sheet.setStarters(MobileSuggestions.starterRows(favorites: favorites.value.sites.count,
                                                        hasSearched: settings.value.hasSearched, incognito: incognitoSearch))
        sheet.isHidden = false
        // Faded out under its picture when a choice was made (leaveSheetRising).
        sheet.alpha = 1
        bar.pill.alpha = 0
    }

    private func updateRecentTabs() {
        let mac: SidebarDocument?
        if case .spaces(let document) = SyncedSidebar.sheet.opening { mac = document } else { mac = nil }
        let rows = MobileRecentTabs.rows(phone: store.tabs, selected: store.selected?.id, mac: mac)
        for row in rows where row.source == .mac && favicons.icon(for: row.url) == nil {
            favicons.fetchFromHomePage(for: row.url)
        }
        sheet.setRecentTabs(rows.map { ($0, favicons.icon(for: $0.url)) })
    }

    /// A Mac tab's icon, asked of its site, arrived while the recent tabs show.
    @objc private func faviconsChanged() {
        guard isSearching else { return }
        if sheet.text.isEmpty { updateRecentTabs() } else { sheet.refreshRows() }
    }

    func searchSheet(_ sheet: SearchSheet, didChangeText text: String) {
        defer { placeCoachMark() }
        let engine = settings.value.search
        // Incognito keeps what is typed on the phone until Go, and leaves the phone's own pages out.
        let sites = incognitoSearch ? [] : knownSites()
        showSuggestions(typed: text, completions: [], sites: sites)
        guard !incognitoSearch else { return }
        suggestions.completions(for: text, engine: engine) { [weak self, weak sheet] found in
            guard let self, let sheet, self.isSearching, sheet.text == text else { return }
            self.showSuggestions(typed: text, completions: found, sites: self.incognitoSearch ? [] : self.knownSites())
        }
    }

    private func showSuggestions(typed: String, completions: [String], sites: [MobileSuggestions.Site]) {
        let rows = MobileSuggestions.rows(typed: typed, completions: completions, sites: sites, limit: MobileSearchSheet.listedRows)
        sheet.setRows(rows)
        for row in rows where row.place != nil {
            if case .site(let url) = row.kind, favicons.icon(for: url) == nil { favicons.fetchFromHomePage(for: url) }
        }
    }

    /// The pages a typed word can match, most wanted first: favorites, open tabs from the most
    /// recent, then archived ones.
    private func knownSites() -> [MobileSuggestions.Site] {
        let favoriteSites = favorites.value.sites.map { MobileSuggestions.Site(title: $0.title, url: $0.url) }
        let tabs = (store.rowTabs + store.archived).sorted { $0.lastActive > $1.lastActive }
        let mac: [MobileSuggestions.Site]
        if case .spaces(let document) = SyncedSidebar.sheet.opening { mac = MobileSuggestions.macSites(in: document) } else { mac = [] }
        return favoriteSites + tabs.map { MobileSuggestions.Site(title: $0.displayTitle, url: $0.url) } + mac
    }

    /// Browse for Me is the search engine and this device can run it.
    var searchesWithBrowseForMe: Bool { settings.value.searchesWithBrowseForMe && BrowseForMe.isAvailable }

    /// Where a typed or spoken search goes: an address opens, a search goes to the engine or makes
    /// a Browse for Me page.
    func searchDestination(_ typed: String) -> String {
        MobileSuggestions.destination(forTyped: typed, engine: settings.value.search, browsesForMe: searchesWithBrowseForMe)
    }

    /// A search made from the sheet: the starter questions are done with.
    private func noteSearched() {
        if !settings.value.hasSearched { settings.update { $0.hasSearched = true } }
    }

    func searchSheet(_ sheet: SearchSheet, didSubmit text: String) {
        noteSearched()
        go(searchDestination(text))
    }

    func searchSheet(_ sheet: SearchSheet, didPick row: MobileSuggestions.Row) {
        noteSearched()
        go(MobileSuggestions.destination(for: row, engine: settings.value.search, browsesForMe: searchesWithBrowseForMe))
    }

    func searchSheet(_ sheet: SearchSheet, didPickRecentTab row: MobileRecentTabs.Row) {
        switch row.source {
        case .phone(let id):
            store.bringToFront(id)
            guard let tab = store.selected else { return }
            show(tab)
            setSearching(false)
            refreshTabStack()
        case .mac:
            go(row.url)
        }
    }

    func searchSheet(_ sheet: SearchSheet, didPickFavorite site: MobileFavorites.Site) {
        go(site.url)
    }

    func searchSheet(_ sheet: SearchSheet, didAskToBrowseFor row: MobileSuggestions.Row) {
        guard appleIntelligenceIsReady() else { return }
        noteSearched()
        go(MobileBrowseForMe.tabAddress(query: row.text))
    }

    /// Where the sheet's choice loads: in the page on screen when its address is being edited
    /// (`MobileAddressEdit`), otherwise in a new tab, as + does. The sheet rises and fades out as it goes.
    func go(_ address: String) {
        leaveSheetRising()
        guard let page = shownPage, let tab = store.tabs.first(where: { $0.id == page.tabID }),
              MobileAddressEdit.target(editing: editsShownTab, tabIsIncognito: tab.isIncognito, sheetIsIncognito: incognitoSearch) == .currentTab
        else {
            open(address)
            // A new page has nothing to show until it draws. Browse for Me puts up its own loading at once.
            if MobileBrowseForMe.query(fromTabAddress: address) == nil, let page = shownPage { coverUntilDrawn(page) }
            return
        }
        setSearching(false)
        if let query = MobileBrowseForMe.query(fromTabAddress: address) {
            store.update(page.tabID, url: address, title: query)
            browse(for: query, in: page)
        } else {
            page.load(address)
        }
        updateBrowseToggle()
    }

    /// The search sheet over the page with `text` (its address, or a Browse for Me page's
    /// question) in the field, selected, ready to change; what is chosen loads in this tab.
    /// `replacingMenuAt`: it takes the page menu's place, starting where the menu's panel was.
    func editAddress(of page: WebPage, text: String, replacingMenuAt top: CGFloat? = nil) {
        setSearching(true, incognito: page.isIncognito, replacingMenuAt: top, editingAddress: true)
        editsShownTab = true
        sheet.text = text
        if MobileBrowseForMe.query(fromTabAddress: store.tabs.first { $0.id == page.tabID }?.url ?? "") != nil {
            // A question: its suggestions, as for any typed question.
            searchSheet(sheet, didChangeText: text)
        } else {
            // An address is not sent to the engine for suggestions until it is changed.
            showSuggestions(typed: text, completions: [], sites: incognitoSearch ? [] : knownSites())
        }
        DispatchQueue.main.async { [weak self] in self?.sheet.field.selectAll(nil) }
    }

    // MARK: Leaving the sheet for what was chosen (MobileSheetLeave)

    /// The sheet rises and fades out from where it is, as Arc Search's does once something is chosen in it. A picture
    /// of it does: the sheet itself, hidden, closes into the pill under it as the keyboard goes.
    func leaveSheetRising() {
        guard isSearching, let picture = sheet.snapshotView(afterScreenUpdates: false) else { return }
        picture.frame = sheet.frame
        picture.isUserInteractionEnabled = false
        view.insertSubview(picture, aboveSubview: sheet)
        sheet.alpha = 0
        UIView.animate(withDuration: MobileSheetLeave.leaveDuration, delay: 0, options: [.curveEaseInOut]) {
            picture.transform = CGAffineTransform(translationX: 0, y: -MobileSheetLeave.leaveRise)
            picture.alpha = 0
            self.bar.pill.alpha = 1
        } completion: { _ in
            picture.removeFromSuperview()
        }
    }

    /// The screen goes to the canvas colour as the sheet leaves and stays so until `page` has drawn, so a dark site
    /// doesn't show white first; at most `MobileSheetLeave.coverLongestHold`.
    func coverUntilDrawn(_ page: WebPage) {
        liftCover()
        let cover = newPageCover
        cover.backgroundColor = .systemBackground
        cover.frame = view.bounds
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.isUserInteractionEnabled = false
        // For a UI test (`-CraTraceCover YES`): left out of what VoiceOver and other tests see otherwise.
        cover.isAccessibilityElement = LaunchOptions.value("CraTraceCover") == "YES"
        cover.accessibilityIdentifier = "new-page-cover"
        cover.alpha = 0
        // Over the page and the bar, under the sheet on its way out.
        view.insertSubview(cover, belowSubview: sheet)
        coveredPage = (page, CACurrentMediaTime(), nil)
        // The page itself stays out of sight until the cover comes off, under an opaque curtain right over it, and the
        // band behind the status bar with it: WebKit paints a new page white before its own colours come, which showed
        // through the cover as it faded in. The page stays in view underneath, so it has drawn when the curtain goes.
        cover.curtain.backgroundColor = .systemBackground
        cover.curtain.frame = pageContainer.bounds
        cover.curtain.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.curtain.isUserInteractionEnabled = false
        pageContainer.insertSubview(cover.curtain, aboveSubview: page.webView)
        cover.band = statusBand
        updateStatusBand()
        page.onDrawn = { [weak self, weak page] in
            guard let self, let page else { return }
            self.pageDrew(page)
        }
        UIView.animate(withDuration: MobileSheetLeave.leaveDuration, delay: 0, options: [.curveEaseInOut]) { cover.alpha = 1 }
        for delay in [MobileSheetLeave.leaveDuration, MobileSheetLeave.coverLongestHold] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.01) { [weak self] in self?.liftCoverIfDue() }
        }
    }

    func pageDrew(_ page: WebPage) {
        guard coveredPage?.page === page, coveredPage?.drawnAt == nil else { return }
        coveredPage?.drawnAt = CACurrentMediaTime()
        liftCoverIfDue()
        // The paint reaches the screen a frame or two after the page says it has drawn (`MobileSheetLeave.drawnSettle`).
        DispatchQueue.main.asyncAfter(deadline: .now() + MobileSheetLeave.drawnSettle + 0.01) { [weak self] in self?.liftCoverIfDue() }
    }

    func liftCoverIfDue() {
        guard let covered = coveredPage else { return }
        let now = CACurrentMediaTime()
        let sinceDrawn = covered.drawnAt.map { now - $0 }
        guard covered.page !== shownPage || MobileSheetLeave.liftsCover(elapsed: now - covered.since, sinceDrawn: sinceDrawn) else { return }
        liftCover()
    }

    /// Takes the cover off at once, as Arc Search's page appears; also when search, the tab row or another page
    /// comes up over it. The page shows again, and the band behind the status bar in the colour it has drawn.
    func liftCover() {
        guard let covered = coveredPage else { return }
        covered.page.onDrawn = nil
        coveredPage = nil
        newPageCover.layer.removeAllAnimations()
        newPageCover.removeFromSuperview()
        newPageCover.curtain.removeFromSuperview()
        updateStatusBand()
    }

    func searchSheet(_ sheet: SearchSheet, didMoveFavoriteFrom source: Int, to destination: Int) {
        favorites.move(from: source, to: destination)
    }

    func searchSheetDidAskForVoice(_ sheet: SearchSheet) {
        let incognito = incognitoSearch
        setSearching(false)
        beginVoiceSearch(handsFree: true)
        voiceIsIncognito = incognito
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

    /// The tab's page, following the app's site settings.
    func page(for tab: MobileTab) -> WebPage {
        let page = store.page(for: tab)
        page.siteOptions = { [weak self] host in self?.settings.value.options(for: host) ?? MobileSiteOptions() }
        page.appLinks = { [weak self] in self?.settings.value.openAppLinksIn ?? .nativeApp }
        return page
    }

    func show(_ tab: MobileTab) {
        let page = self.page(for: tab)
        guard page !== shownPage else { return }
        closeReader()
        dropBlockerNotices()
        shownPage?.webView.removeFromSuperview()
        shownPage?.delegate = nil
        shownPage = page
        liftCoverIfDue()
        page.delegate = self
        page.webView.allowsBackForwardNavigationGestures = false
        page.webView.frame = pageContainer.bounds
        pageContainer.insertSubview(page.webView, belowSubview: pageDim)
        page.restoresAtTop = false
        if page.webView.url == nil, !page.isBrowsing, !page.webKitOwnsInitialNavigation {
            if let query = MobileBrowseForMe.query(fromTabAddress: tab.url) {
                browse(for: query, in: page)
            } else if let history = store.history(for: tab) {
                // Where the tab was, scrolled as it was, with its back and forward list (#656).
                page.restoresAtTop = history.restoresAtTop
                page.webView.interactionState = history.state
                if page.webView.backForwardList.currentItem == nil { page.load(tab.url) }
            } else {
                page.load(tab.url)
            }
        }
        if let browseLoading {
            browseLoading.isHidden = browseLoading.tabID != page.tabID
            pageContainer.insertSubview(browseLoading, belowSubview: pageDim)
        }
        barCollapse.reveal()
        updateBrowseToggle()
        pageShownAt = CACurrentMediaTime()
    }

    func refreshTabStack() {
        // The button previews the tabs behind this page, never the page itself: the previous
        // tab on top, and the tab behind it underneath.
        let behind = store.tabsBehindCurrent
        let front = behind.first
        let back = behind.dropFirst().first
        bar.tabsButton.setSnapshots(front: front.flatMap { store.snapshot($0.id) }, back: back.flatMap { store.snapshot($0.id) })
    }

    func captureSnapshot() {
        guard let page = shownPage else { return }
        let id = page.tabID
        page.takeSnapshot { [weak self] image in self?.keepSnapshot(image, for: id) }
    }

    /// The page as a picture now, for its tab's preview, taken from the screen and returned.
    /// `captureSnapshot` is a `WKWebView` capture, which comes out black once the page is hidden;
    /// this one is made before the flick covers it, so a tab scrolled since its last capture keeps
    /// up to date, and the flick's card shows the same picture.
    @discardableResult
    func capturePageSnapshot() -> UIImage? {
        guard let page = shownPage, pageContainer.bounds.width > 1, !pageContainer.isHidden else { return nil }
        let bounds = pageContainer.bounds
        // What is on screen already, without making the app draw again first, and at 2× at most:
        // it is taken as a drag starts, and the preview is small, so it must cost next to nothing.
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = min(format.scale, 2)
        format.opaque = true
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
            pageContainer.drawHierarchy(in: bounds, afterScreenUpdates: false)
        }
        return keepSnapshot(image, for: page.tabID) ? image : nil
    }

    /// Keeps a capture as the tab's picture, unless it came back black: a web view caught between
    /// frames, or hidden, draws nothing, and that would be the tab's preview until the next one.
    @discardableResult
    private func keepSnapshot(_ image: UIImage?, for id: UUID) -> Bool {
        guard let image, !image.looksBlank else { return false }
        store.setSnapshot(image, for: id)
        refreshTabStack()
        return true
    }

    // MARK: Tab switcher

    @objc func showTabs() {
        guard switcher == nil, !isSearching else { return }
        dropBlockerNotices()
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
        liftCover()
        let switcher = TabSwitcherView(frame: view.bounds)
        switcher.delegate = self
        let tabs = store.switcherTabs
        let selected = store.selected?.id
        // The row opens focused on the card behind the page: the one to its left, which is the
        // tab the button's back card shows in the row's usual order. A first card focuses itself.
        let focus = store.switcherFocus?.id
        let onRow = store.selected.map { !$0.isIncognito } ?? false
        // On a private page the private tabs waiting unseen are cards too, marked with the eyes.
        switcher.setTabs(tabs, focus: focus, snapshot: store.snapshot,
                         favicon: { $0.isIncognito ? UIImage(systemName: "eyes")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal) : self.favicons.icon(for: $0.url) })
        // An incognito page has no card to shrink into; the row just appears.
        switcher.expandedID = onRow ? selected : nil
        switcher.expansion = onRow ? 1 : 0
        view.insertSubview(switcher, aboveSubview: pageContainer)
        switcher.layoutIfNeeded()
        self.switcher = switcher
        pageContainer.isHidden = true
        barCollapse.reveal()
        return switcher
    }

    func settleSwitcher(_ switcher: TabSwitcherView) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SyncedSidebar.readAhead()
        offerSyncCard(in: switcher)
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
        store.bringToFront(id)
        guard let tab = store.selected else { return }
        show(tab)
        closeSwitcher(switcher, growing: id)
    }

    /// A tap on the row's empty background goes back to the page that was on screen, not to the
    /// focused card beside it.
    func tabSwitcherDidTapOutside(_ switcher: TabSwitcherView) {
        guard let selected = store.selected else { return }
        closeSwitcher(switcher, growing: selected.id)
    }

    /// Grows `id`'s card back into the page and takes the row away.
    private func closeSwitcher(_ switcher: TabSwitcherView, growing id: UUID) {
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
        let model = OnboardingModel(canUseAI: BrowseForMe.isOffered, icon: MobileAppIcon(alternateName: UIApplication.shared.alternateIconName))
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
            open(BrowseForMe.isAvailable ? MobileBrowseForMe.tabAddress(query: query) : settings.value.search.searchURL(query))
        case .voiceSearch:
            setSearching(false)
            beginVoiceSearch(handsFree: true)
        case .spaces:
            setSearching(false)
            showSpaces()
        case .changeIcon:
            let picker = UINavigationController(rootViewController: UIHostingController(rootView: AppIconPicker()))
            picker.sheetPresentationController?.detents = appSettingsDetents()
            topPresenter.present(picker, animated: true)
        }
    }

    // MARK: Spaces

    /// The Mac's Spaces, from the tab row's left button. A tap on a tab there opens it here.
    @objc func showSpaces() {
        let model = SpacesModel()
        model.favicon = { [weak self] in self?.favicons.icon(for: $0) }
        model.fetchFavicon = { [weak self] in self?.favicons.fetchFromHomePage(for: $0) }
        model.close = { [weak self] in self?.dismiss(animated: true) }
        model.open = { [weak self] address in
            guard let self else { return }
            self.dismiss(animated: true)
            self.incognitoSearch = false
            self.open(address)
        }
        model.sharePromptSeen = { [weak self] in self?.settings.value.hasSeenSharePrompt ?? true }
        model.markSharePromptSeen = { [weak self] in self?.settings.update { $0.hasSeenSharePrompt = true } }
        model.showShareGuide = { [weak self] closed in self?.showShareGuide(closed: closed) }
        model.showLastRead()
        let sheet = UIHostingController(rootView: SpacesView(model: model))
        sheet.view.backgroundColor = .clear
        CardSheet.present(sheet, from: topPresenter)
    }

    /// Arc Search's "Save to Arc from any app" how-to, over the Spaces sheet; its button opens a
    /// share menu to find Cra in.
    func showShareGuide(closed: @escaping () -> Void) {
        weak var guide: UIViewController?
        let view = ShareGuideView(
            close: { guide?.dismiss(animated: true) },
            showShareMenu: { rect in
                guard let guide, let url = URL(string: "https://crabrowser.app") else { return }
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = guide.view
                share.popoverPresentationController?.sourceRect = guide.view.convert(rect, from: guide.view.window)
                guide.present(share, animated: true)
            })
        let controller = UIHostingController(rootView: view)
        guide = controller
        CardSheet.present(controller, from: topPresenter, style: .stacked, onDismiss: closed)
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
        let model = SettingsModel(store: settings, host: host, canSummarize: BrowseForMe.isOffered)
        model.done = { [weak self] in self?.dismiss(animated: true) }
        model.changed = { [weak self] in self?.view.setNeedsLayout() }
        model.showArchive = { [weak self] in self?.showArchive() }
        model.showOnboarding = { [weak self] in self?.showOnboarding() }
        model.showIconDock = { [weak self] in
            guard let self else { return }
            var dock: UIViewController?
            let sheet = UIHostingController(rootView: AppIconDock(done: { dock?.dismiss(animated: true) }))
            dock = sheet
            sheet.sheetPresentationController?.detents = [.custom { _ in 300 }]
            self.topPresenter.present(sheet, animated: true)
        }
        model.showWidgetGuide = { [weak self] in
            guard let self else { return }
            var guide: UIViewController?
            let view = WidgetGuideView(done: { guide?.dismiss(animated: true) })
            let sheet = UIHostingController(rootView: view)
            guide = sheet
            sheet.sheetPresentationController?.prefersGrabberVisible = true
            self.topPresenter.present(sheet, animated: true)
        }
        model.showDownloads = { [weak self] in self?.showDownloads() }
        model.showSpaces = { [weak self] in self?.showSpaces() }
        model.shareCra = { [weak self] rect in
            guard let self, let link = URL(string: "https://crabrowser.app") else { return }
            let share = UIActivityViewController(activityItems: [link], applicationActivities: nil)
            guard let source = self.topPresenter.view else { return }
            share.popoverPresentationController?.sourceView = source
            share.popoverPresentationController?.sourceRect = source.convert(rect, from: source.window)
            self.topPresenter.present(share, animated: true)
        }
        model.exportData = { [weak self] rect in
            guard let self else { return }
            let share = UIActivityViewController(activityItems: [self.store.document.exportText], applicationActivities: nil)
            guard let source = self.topPresenter.view else { return }
            share.popoverPresentationController?.sourceView = source
            share.popoverPresentationController?.sourceRect = source.convert(rect, from: source.window)
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
            sheet.sheetPresentationController?.detents = appSettingsDetents()
        }
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        sheet.view.backgroundColor = .clear
        topPresenter.present(sheet, animated: true)
    }

    private func appSettingsDetents() -> [UISheetPresentationController.Detent] {
        MobileSettingsSheet.appSettingsHeights(onPad: traitCollection.userInterfaceIdiom == .pad).map { ($0 == .medium ? UISheetPresentationController.Detent.medium : UISheetPresentationController.Detent.large)() }
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
        dropBlockTip()
        let menu = PageMenuView(state: menuState(for: page))
        menu.delegate = self
        let host = SheetHost(content: menu, cornerRadius: MobilePageMenu.cornerRadius) { [weak menu] safeBottom, width in
            MobilePageMenu.height(displayOptionsOpen: menu?.displayOptionsOpen ?? false, width: width, safeBottom: safeBottom)
        }
        host.onDismiss = { [weak self] in
            self?.menuHost = nil
            self?.menuView = nil
        }
        menuHost = host
        menuView = menu
        host.present(in: view)
    }

    func menuState(for page: WebPage) -> PageMenuState {
        let host = page.webView.url?.host.map(MobileSettings.siteKey) ?? ""
        return PageMenuState(host: host, canGoBack: page.webView.canGoBack, canGoForward: page.webView.canGoForward,
                             zoom: Double(page.webView.pageZoom), isDesktopSite: page.wantsDesktopSite,
                             canSummarize: BrowseForMe.isOffered, blockedCount: page.blockedCount,
                             isFavorite: page.webView.url.map { favorites.value.contains($0.absoluteString) } ?? false,
                             isTranslated: page.isTranslated, isReader: readerView != nil)
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
        menuHost?.dismiss()
    }

    func pageMenuGoBack() { shownPage?.webView.goBack() }
    func pageMenuGoForward() { shownPage?.webView.goForward() }
    func pageMenuReload() {
        shownPage?.webView.reload()
        menuHost?.dismiss()
    }
    func pageMenuCopyLink() { copyLink() }

    func pageMenuEditAddress() {
        guard let page = shownPage, let tab = store.tabs.first(where: { $0.id == page.tabID }) else { return }
        let text = MobileAddressEdit.text(tabAddress: tab.url, pageAddress: page.webView.url?.absoluteString)
        // The editable sheet takes the menu's place: its field sits where the address capsule
        // was, and the keyboard lifts it from there. The menu goes at once, so the panel never
        // visibly closes and another one rises from the bottom.
        let top = menuHost.map { $0.panel.convert($0.panel.bounds, to: view).minY }
        editAddress(of: page, text: text, replacingMenuAt: top)
        menuHost?.dismiss(animated: false)
    }

    /// Display Options opened or closed: the sheet follows the menu's new height.
    func pageMenuDidChangeHeight() {
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            self.menuHost?.setNeedsLayout()
            self.menuHost?.layoutIfNeeded()
        }
    }

    func pageMenuToggleFavorite() {
        guard let page = shownPage, let address = shareableAddress else { return }
        favorites.toggle(url: address, title: page.webView.title ?? "")
        refreshMenu()
    }

    func pageMenu(didPick tile: MobilePageMenu.Tile) {
        switch tile {
        case .findOnPage:
            guard let page = shownPage else { return }
            menuHost?.dismiss {
                page.webView.isFindInteractionEnabled = true
                page.webView.findInteraction?.presentFindNavigator(showingReplace: false)
            }
        case .pin:
            // Arc Search pins to a Space; on the phone Cra keeps it with "Favorite in App".
            pageMenuToggleFavorite()
        case .share:
            guard let address = shareableAddress, let url = URL(string: address) else { return }
            menuHost?.dismiss { [weak self] in
                guard let self else { return }
                let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                share.popoverPresentationController?.sourceView = self.bar.menuButton
                self.present(share, animated: true)
            }
        case .summarize:
            menuHost?.dismiss()
            guard appleIntelligenceIsReady() else { return }
            summarize()
        }
    }

    func pageMenu(didPick row: MobilePageMenu.Row) {
        guard let page = shownPage else { return }
        switch row {
        case .readerMode:
            menuHost?.dismiss()
            toggleReader()
        case .requestDesktopSite:
            page.wantsDesktopSite.toggle()
            page.webView.reload()
            menuHost?.dismiss()
        case .siteSettings:
            presentSettings(site: page.webView.url?.host.flatMap { $0.isEmpty ? nil : $0 }, startingAtSite: true)
        case .translate:
            menuHost?.dismiss()
            translate(page)
        case .pageZoom, .displayOptions:
            break
        }
    }

    func pageMenuZoom(up: Bool) {
        guard let page = shownPage else { return }
        page.webView.pageZoom = CGFloat(MobilePageMenu.zoom(Double(page.webView.pageZoom), stepping: up))
        refreshMenu()
    }

    func pageMenuResetZoom() {
        shownPage?.webView.pageZoom = 1
        refreshMenu()
    }

    func pageMenuReloadWithoutBlockers() {
        shownPage?.reloadWithoutBlockers()
        fixPending = shownPage?.tabID
        menuHost?.dismiss()
    }

    // MARK: WebPageDelegate

    func webPageDidChange(_ page: WebPage) {
        if page === shownPage {
            updateStatusBand()
            refreshMenu()
            // Reader belongs to the page it was opened on.
            if page.isLoading { closeReader() }
        }
        if page === shownPage { offerHandoff(for: page) }
        // A Browse for Me page has no address of its own: the tab keeps the one that names its query.
        let address = page.webView.url?.absoluteString
        store.update(page.tabID, url: address == "about:blank" ? nil : address, title: page.webView.title)
        if page === shownPage { updateBrowseToggle() }
        if page === shownPage { blockerNoticesFollow(page) }
        // A site whose Collapse Bottom Bar is off never has the bar away, even arriving by a link
        // from one that put it away (#505).
        if page === shownPage, !isSearching, barCollapse.pageChanged(collapses: settings.value.options(for: page.webView.url?.host).collapseBottomBar) {
            animateChrome(duration: 0.25, options: .curveEaseInOut)
        }
    }

    func webPage(_ page: WebPage, didFinishLoading success: Bool) {
        pageDrew(page)
        if success, store.tabs.first(where: { $0.id == page.tabID })?.isIncognito == false, let address = page.webView.url?.absoluteString {
            page.iconCandidates { [weak self] candidates in self?.favicons.fetch(for: address, candidates: candidates) }
        }
        guard page === shownPage else { return }
        if page.restoresAtTop {
            if success {
                let scroll = page.webView.scrollView
                let offset = scroll.contentOffset.y + scroll.adjustedContentInset.top
                if offset > 0.5, offset < CGFloat(PageHistory.restoreAtTopBelow) {
                    scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top),
                                            animated: false)
                }
            }
            page.restoresAtTop = false
        }
        if success { pageFinishedForBlockerNotices(page) }
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
        let collapses = settings.value.options(for: page.webView.url?.host).collapseBottomBar
        guard barCollapse.scrolled(by: delta, atTop: atTop, collapses: collapses) else { return }
        animateChrome(duration: 0.25, options: .curveEaseInOut)
    }

    /// A tap on the strip under the page brings the bar back, as scrolling up does.
    @objc func revealBar() {
        guard barCollapse.reveal() else { return }
        animateChrome(duration: 0.25, options: .curveEaseInOut)
    }

    /// The question capsule on a Browse for Me page: the same editing as the page menu's address,
    /// so the changed question is asked in this tab too.
    func webPage(_ page: WebPage, editQuery query: String) {
        editAddress(of: page, text: query)
    }

    /// "Open in Incognito" (#572): a new private tab with the link, shown.
    func webPage(_ page: WebPage, openInIncognito url: URL) {
        incognitoSearch = true
        open(url.absoluteString)
    }

    func webPage(_ page: WebPage, openInNewTab url: URL) {
        incognitoSearch = store.tabs.first(where: { $0.id == page.tabID })?.isIncognito ?? false
        open(url.absoluteString)
    }

    /// Arc Search's "Open in Background Tab": the link loads in a tab at the end of the row and
    /// the page stays on screen. From a private page it is private, and waits unseen in the
    /// private session (`MobileTabsDocument.addInBackground`).
    func webPage(_ page: WebPage, openInBackground url: URL) {
        let tab = store.addInBackground(url: url.absoluteString, incognito: page.isIncognito)
        let background = self.page(for: tab)
        // Its title and icon reach the row while it loads off screen.
        background.delegate = self
        background.load(url.absoluteString)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        refreshTabStack()
    }

    func webPage(_ page: WebPage, createPopupWith configuration: WKWebViewConfiguration, request: URLRequest) -> WKWebView? {
        captureSnapshot()
        guard let popup = store.openPopup(configuration: configuration, request: request, from: page),
              let tab = store.selected else { return nil }
        show(tab)
        // Opener callbacks can update its address/title while the popup is in front.
        page.delegate = self
        incognitoSearch = tab.isIncognito
        leaveSwitcherForPage()
        setSearching(false)
        refreshTabStack()
        return popup.webView
    }

    func webPageDidClose(_ page: WebPage) {
        let wasShown = page === shownPage
        if wasShown {
            page.webView.removeFromSuperview()
            shownPage = nil
        }
        page.delegate = nil
        store.close(page.tabID)
        if wasShown {
            if let tab = store.selected {
                show(tab)
                if let shownPage { webPageDidChange(shownPage) }
            } else {
                setSearching(true, incognito: false)
            }
        }
        refreshTabStack()
    }
}
