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
    /// The empty home screen: Cra's logo, which spins when flicked, with dots a finger stirs under it
    /// (`MobileEmptyHome`) and "Tap to search" over the pill.
    let logo = FidgetLogoView(image: UIImage(named: "LaunchMark"))
    let dotField = DotFieldView()
    let searchHint = SearchHintView()
    let pageContainer = PassthroughView()
    /// A solid page-coloured floor under a page while it slides across: a gap or a fade must show
    /// the page's own colour, not the app's backdrop, through the bar's material.
    private let swapBackdrop = UIView()
    /// Darkens the page while it sits pushed back behind the search sheet.
    let pageDim = UIView()
    /// The band behind the status bar over a page (updateStatusBand), and the colour it shows.
    let statusBand = UIView()
    /// Darkens the status band with the page behind the search sheet's dim.
    let statusBandDim = UIView()
    private var statusBandFill: String?
    /// How far the page is pulled below its top, so the status band can grow behind it; nil when
    /// the page is not being pulled.
    var pagePull: CGFloat?
    /// The last pull sample and its speed, for the ring's bump at the line.
    private var pullSample: (pull: CGFloat, at: CFTimeInterval)?
    private var pullSpeed: CGFloat = 0
    /// The pull's ring: an arc that fills as the page comes down, fixed in the status band.
    let pullArc = PullArcView()
    /// For UI tests (`-CraTracePull YES`): the last pull's distance, band height and page top,
    /// kept after the page springs back.
    let pullTraceView = UIView()
    private var pullTraceMax: CGFloat = 0
    /// For UI tests (`-CraTraceViewport YES`): how many times the page's visible viewport has
    /// moved with the bar, the most its bottom was ever apart from the bar's top, and the bar's
    /// range WebKit was given.
    let viewportTraceView = UIView()
    /// For UI tests (`-CraTraceNewTabDrawer YES`): the settled new tab drawer's rise, field morph
    /// and material, and the last frame of a drag before the finger lets go.
    let newTabDrawerTraceView = UIView()
    let newTabDrawerDragTraceView = UIView()
    /// For UI tests (`-CraTraceTabOpen YES`): what the last tab opened from the tab row came in
    /// with: its live page ("live"), the page under its fading picture ("live under picture") or
    /// its picture alone ("picture"); "swiped along the bar" for one a bar swipe brought.
    let tabOpenTraceView = UIView()
    /// The bar as a picked card started to grow: light or dark, whether that swap crossfaded, and
    /// whether its slab is fading in ("light at once, slab fading in").
    let growTraceView = UIView()
    private var viewportChanges = 0
    private var viewportMismatch: CGFloat = 0
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
    /// A tab's page put in the window under the tab row as a finger comes down on its card
    /// (`tabSwitcher(_:mayPick:)`).
    var warmPage: WebPage?
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
    /// The previous tab's card in the hand during a flick up from the tab button.
    var flickCard: UIImageView?
    var flick = FlickState()
    /// When the page on screen was last swapped in: its web view takes a moment to draw, and a
    /// picture taken before then is black.
    var pageShownAt: CFTimeInterval = 0

    /// The bar's top edge with the bar `progress` of the way down its travel: its open place, a
    /// bar above the safe area, at 0, and the safe area's own line at 1, where only the strip
    /// along the home indicator is left on screen. Dragged, this is the page's bottom edge. It
    /// keeps to the display's pixel grid, so a step too small to show moves nothing.
    private func barTopEdge(progress: CGFloat) -> CGFloat {
        MobileBottomBar.top(in: view.bounds.size, safeBottom: view.safeAreaInsets.bottom, progress: progress,
                            scale: view.traitCollection.displayScale)
    }

    /// The page's view height: the shape a tab's picture is taken in, and what a card that opens
    /// becomes. With the page running under the bar it is the screen's edge, not the bar's top,
    /// so a tab comes in with the page's whole bottom and gains nothing on landing.
    var pageViewHeight: CGFloat { pageViewFrame(top: view.safeAreaInsets.top, barProgress: 1, underBar: true).height }

    /// The page's view at rest with the bar open: from the status band down to the screen's edge
    /// under the bar, to the bar's top before iOS 26.
    var restingPageViewFrame: CGRect { pageViewFrame(top: view.safeAreaInsets.top, barProgress: 0, underBar: true) }

    /// The page's view bottom with the bar open (`restingPageViewFrame`).
    var pageViewBottom: CGFloat { restingPageViewFrame.maxY }

    /// Whether the page's view can run on under the bar while WebKit lays its content out clear of
    /// it: iOS 26's obscured content insets shrink the layout viewport without shrinking the view,
    /// so the bar's material has the page behind it and a sticky bottom sits on the bar's top.
    /// Before that the view itself ends at the bar's top.
    private static var pageRunsUnderBar: Bool {
        if #available(iOS 26.0, *) { return true }
        return false
    }

    /// The web view's frame, its bottom at the screen's edge (the page under the bar, down past the
    /// home indicator) or at the bar's top (before iOS 26, or a page the bar never leaves:
    /// `underBar` false). `top` carries a pull or the search sheet's push-back; the height stays
    /// the resting one, so the view moves rather than reflows.
    private func pageViewFrame(top: CGFloat, barProgress: CGFloat, underBar: Bool) -> CGRect {
        let safeTop = view.safeAreaInsets.top
        let bottom = Self.pageRunsUnderBar && underBar ? view.bounds.height : barTopEdge(progress: barProgress)
        return CGRect(x: 0, y: top, width: view.bounds.width, height: max(0, bottom - safeTop))
    }

    /// Whether `page`'s view runs on under the bar now (`MobileBarCollapse.pageRunsUnder`): on
    /// iOS 26, unless the bar never leaves the page, whose view then ends at the bar's top so a
    /// page sized to the screen with `100vh` keeps its bottom above the bar (Excel's sheet tabs).
    private func runsUnderBar(_ page: WebPage) -> Bool {
        Self.pageRunsUnderBar
            && barCollapse.pageRunsUnder(collapses: collapsesBar(page), scrolls: scrolls(page), loaded: !page.isLoading)
    }

    /// How much of the bar lies over the page's view now: from the bar's top (`barTopEdge`, on
    /// the same pixel grid) to the screen's edge, so the page's visible bottom is exactly the
    /// bar's top. None when the view itself ends at the bar's top (`runsUnderBar`).
    private func barOverlap(_ page: WebPage) -> CGFloat {
        guard runsUnderBar(page) else { return 0 }
        return MobileBottomBar.covered(in: view.bounds.size, safeBottom: view.safeAreaInsets.bottom,
                                       progress: barCollapse.progress, scale: view.traitCollection.displayScale)
    }

    /// Whether the shown page's view is laid out by the chrome: not while a page is being put in
    /// or taken out of the card, or a flicked-in tab is landing, which place it themselves.
    private var pageFollowsChrome: Bool { !pageClosing && !pageOpening && !flick.incoming }

    /// Puts a page's view where the bar and the chrome say, with its insets: the shown page, or a
    /// tab's page about to ride in a swipe's card. One already riding there is the card's to place.
    func layoutPageView(_ page: WebPage) {
        if ridesInSwipeCard(page) { return }
        // On iOS 26 the frame holds still as the bar moves; setting it again anyway makes
        // WebKit work out what it shows again, on every frame of the bar's travel.
        let frame = pageViewFrame(top: webViewTop(), barProgress: barCollapse.progress, underBar: runsUnderBar(page))
        if page.webView.frame != frame { page.webView.frame = frame }
        updatePageInsets(page)
    }

    /// The shown page's height, its load or its site's switch changed: its view runs under the
    /// bar or ends at its top accordingly (`runsUnderBar`). Under an open bar, so the change
    /// doesn't show.
    private func fitPageToBar(_ page: WebPage) {
        guard page === shownPage, pageFollowsChrome else { return }
        layoutPageView(page)
    }

    /// The page's insets for where the bar is now. On iOS 26 WebKit lays the
    /// page out above the bar's top while the bar's own height of it shows under the bar's
    /// material, following the bar frame by frame, so sticky or fixed bottom elements stay on
    /// the bar's top as it moves, never under it. It is told the bar's whole range first
    /// (`MobileBarCollapse.viewportInsets`), so the page's `svh` and `lvh` hold still and only its
    /// visible viewport follows the bar. The covered strip is scroll room too, and the notch's
    /// sides keep the content clear of it in landscape. A view that ends at the bar's top has
    /// nothing covered: its whole frame is the page's every viewport.
    private func updatePageInsets(_ page: WebPage) {
        let underBar = runsUnderBar(page)
        let covered = barOverlap(page)
        if #available(iOS 26.0, *) {
            let range = underBar ? MobileBarCollapse.viewportInsets(safeBottom: view.safeAreaInsets.bottom) : (least: 0, most: 0)
            let least = UIEdgeInsets(top: 0, left: 0, bottom: range.least, right: 0)
            let most = UIEdgeInsets(top: 0, left: 0, bottom: range.most, right: 0)
            if page.webView.minimumViewportInset != least || page.webView.maximumViewportInset != most {
                page.webView.setMinimumViewportInset(least, maximumViewportInset: most)
            }
            var insets = page.webView.obscuredContentInsets
            if insets.bottom != covered {
                insets.bottom = covered
                page.webView.obscuredContentInsets = insets
                if page === shownPage { viewportChanges += 1 }
            }
        }
        // Without the covered strip as scroll room the last of the page lines up with the safe
        // area's edge, under the bar, and cannot be scrolled above it.
        let scroll = page.webView.scrollView
        let safe = view.safeAreaInsets
        let content = UIEdgeInsets(top: 0, left: safe.left, bottom: covered, right: safe.right)
        if scroll.contentInset != content {
            scroll.contentInset = content
        }
    }

    /// Whether `page` has more to scroll than the tallest its screen lets it be, with the bar
    /// closed: a page that fits there can never need the bar out of the way.
    private func scrolls(_ page: WebPage) -> Bool {
        MobileBarCollapse.scrolls(contentHeight: page.webView.scrollView.contentSize.height,
                                  pageHeight: pageViewHeight)
    }

    /// The tab's visible area: under the iOS status bar and above the app's bottom bar, open.
    var tabArea: CGRect {
        let top = view.safeAreaInsets.top
        return CGRect(x: 0, y: top, width: view.bounds.width, height: max(0, barTopEdge(progress: 0) - top))
    }

    var tabArchivedBySwipe: UUID?
    /// The page of the tab a swipe put in the archive, as it was when the swipe started: what the opposite swipe
    /// brings back in.
    var tabArchivedBySwipePicture: UIImage?
    /// The swipe across the page under way, or its picture still over the page it went to (PageSwipe.swift).
    var pageSwipe: PageSwipeStage?
    /// The page as the last swipe across it started.
    var pageSwipeStartPicture: UIImage?
    /// For UI tests (`-CraTracePageSwipe YES`): what the last swipe across the page showed.
    let pageSwipeTraceView = UIView()
    /// What the finger was on when the swipe across the page started (#627).
    weak var pageSwipeTouchView: UIView?
    /// Where the bar swipe's finger came down, in the bar's coordinates (#537): the pan begins
    /// only after a few points of travel, so its location at `.began` is not the start.
    var barSwipeStart: CGPoint?
    /// Where the bar swipe in hand touched down, in the bar.
    var barSwipeStartedAt: CGPoint = .zero
    var barSwipeOpensRow = false
    var barSwipePullsSearch = false
    /// How far up the search sheet is being pulled out of the pill, while it is (#623).
    var searchPull: CGFloat?
    /// A pulled sheet let go: where it stays, and how open its field is, until the keyboard comes (#623).
    var pulledSheetHold: (top: CGFloat, openness: CGFloat)?
    /// The new tab drawer grown out of the bar, while it is out; a fresh one once it has sunk back.
    var drawer = MobileNewTabDrawer()
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
    /// Whether the switch is offered on this page, as the chrome's last layout worked out.
    var browseToggleOffered = false
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
    /// Scrolling drags the bar away where Collapse Bottom Bar is on (`MobileBarCollapse`).
    var barCollapse = MobileBarCollapse()
    /// The bar's own motion, frame by frame: following the finger's drag, or settling to an end
    /// after it lets go. Laying the page out here, once a display frame and outside the scroll
    /// view's own callbacks, keeps the bar and the page's bottom edge together and leaves the
    /// scroll's own work alone.
    private var barLink: CADisplayLink?
    private var barMotion: BarMotion?
    /// Where a follow last laid the bar out: a display frame with the finger still leaves it.
    private var barLaidOutAt: CGFloat?

    /// Where the bar is going: with the finger, or to an end over `MobileMotion.barSnap`.
    private enum BarMotion {
        case following
        case settling(closed: Bool, from: CGFloat, startedAt: CFTimeInterval)
    }

    private var barIsFollowing: Bool {
        if case .following = barMotion { return true }
        return false
    }

    init(store: TabStore, settings: MobileSettingsStore) {
        self.store = store
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    deinit {
        barLink?.invalidate()
    }

    // MARK: Life cycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(backdrop)
        view.addSubview(dotField)
        view.addSubview(logo)
        view.addSubview(searchHint)
        view.addSubview(pageContainer)
        swapBackdrop.isHidden = true
        swapBackdrop.isUserInteractionEnabled = false
        view.insertSubview(swapBackdrop, belowSubview: pageContainer)
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
        pageContainer.addSubview(pullArc)
        pageContainer.layer.cornerCurve = .continuous
        pageContainer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]

        dismissArea.addTarget(self, action: #selector(dismissSearch), for: .touchUpInside)
        dismissArea.isHidden = true
        dismissArea.accessibilityIdentifier = "search-dismiss"
        view.addSubview(dismissArea)
        installTrace(sheetDragTraceView, flag: "CraTraceSheetDrag", id: "sheet-drag-trace")
        installTrace(pullTraceView, flag: "CraTracePull", id: "pull-trace", label: "Pull", value: "pull 0 band 0 page 0")
        installTrace(viewportTraceView, flag: "CraTraceViewport", id: "viewport-trace", label: "Viewport",
                     value: "changes 0 apart 0 range 0")
        installTrace(newTabDrawerTraceView, flag: "CraTraceNewTabDrawer", id: "new-tab-drawer-trace",
                     label: "New Tab Drawer")
        installTrace(newTabDrawerDragTraceView, flag: "CraTraceNewTabDrawer", id: "new-tab-drawer-drag-trace",
                     label: "New Tab Drawer Drag")
        installTrace(pageSwipeTraceView, flag: "CraTracePageSwipe", id: "page-swipe-trace")
        installTrace(tabOpenTraceView, flag: "CraTraceTabOpen", id: "tab-open-trace", label: "Tab Open", value: "none")
        installTrace(growTraceView, flag: "CraTraceTabOpen", id: "grow-trace", label: "Grow", value: "none")
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
        view.addSubview(bar)
        // The strip is the bar's own visible part when it is closed: it has to catch taps over it.
        view.addSubview(barReveal)

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
        // The new tab drawer over the pushed-back page takes white status bar text while it is up.
        if isSearching, drawer.growsFromBar { return .lightContent }
        guard let fill = statusBarFill else { return .default }
        return MobileStatusBand.lightContent(fill: fill) ? .lightContent : .darkContent
    }

    /// The band the status bar's text sits on, as hex; nil when there is none showing. While a
    /// tab is flying in, the bar over it is that tab's, not the page still behind; it keeps it
    /// until that page's own band is known, so the bar does not flash on landing.
    private var statusBarFill: String? {
        flick.statusFill ?? growingFill ?? shownBandFill ?? (statusBand.isHidden ? nil : statusBandFill)
    }

    /// The band a card picked in the tab row brings with it while it grows: the status band is
    /// hidden until the row has gone, and the bar and the status bar's text must not fall back to
    /// the app's own light or dark meanwhile.
    private var growingFill: String?

    /// The band the tab being shown brings with it, as hex, until its page reports its own: the
    /// top of its picture for a page that has not loaded. The bar and the status bar's text take
    /// it the moment the tab is picked, not when its page loads.
    private var shownBandFill: String?

    /// The solid band behind the status bar over a page, in the page's colour, as in Arc Search (#657).
    func updateStatusBand() {
        let page = shownPage
        let pageFill = page.flatMap(bandFill(for:))
        // The page that was picked now knows its own band: it takes over from the tab's picture.
        // With no page (the home screen) there is no tab to carry a band.
        if page == nil || pageFill != nil { shownBandFill = nil }
        let fill = pageFill ?? shownBandFill
        // The page the flick brought now knows its band: it takes the bar back from the estimate.
        if let id = flick.statusPage, page?.tabID == id, pageFill != nil {
            flick.statusPage = nil
            flick.statusFill = nil
            setNeedsStatusBarAppearanceUpdate()
        }
        // The band is the page's top: it shrinks from the status bar to nothing as the page is
        // pushed back, its bottom staying at the card's top edge.
        let shown = MobileStatusBand.shown(hasPage: fill != nil, switching: switcher != nil, covered: coveredPage != nil)
        let safeTop = view.safeAreaInsets.top
        let pageScale = MobilePageBehindSearch.transform(in: pageContainer.bounds.size, safeTop: safeTop,
                                                         progress: drawerProgress).scale
        // A pull grows the band down with the page: its bottom stays on the page's visible top.
        // Its height keeps following the page while the tab row is up, so this band comes back
        // full when the row closes; only its visibility goes.
        let pulled = pagePull ?? 0
        let bandHeight = fill != nil ? safeTop * (1 - drawerProgress) / max(pageScale, 0.001) + pulled : 0
        statusBand.frame = CGRect(x: 0, y: 0, width: pageContainer.bounds.width, height: bandHeight)
        statusBandDim.frame = statusBand.frame
        statusBandDim.alpha = shown ? MobilePageBehindSearch.dim * drawerProgress : 0
        if let color = fill.flatMap(Palette.color(hex:)) {
            statusBand.backgroundColor = color
        }
        if statusBand.isHidden == shown || statusBandFill != fill {
            statusBand.isHidden = !shown
            statusBandFill = fill
            setNeedsStatusBarAppearanceUpdate()
        }
        // The bar's white overlay follows the status bar's own text: dark ink means a light page.
        bar.pageIsLight = MobileBottomBar.pageIsLight(statusBarFill: statusBarFill,
                                                      darkMode: traitCollection.userInterfaceStyle == .dark)
        applyDrawerChrome()
    }

    /// The band's colour for a page, as hex: its theme-color, else its own background.
    private func bandFill(for page: WebPage) -> String? {
        MobileStatusBand.fill(themeColor: Palette.hex(page.webView.themeColor, traits: traitCollection),
                              underPage: Palette.hex(page.webView.underPageBackgroundColor, traits: traitCollection))
    }

    /// The band's bottom edge stays on the page's visible top as the pull grows it; the ring sits
    /// in the band and turns whole at the line.
    func updatePagePull(_ pull: CGFloat) {
        pullTraceMax = max(pullTraceMax, pull)
        // Under half a point is the page still at its top: no band, no ring.
        pagePull = pull > 0.5 ? pull : nil
        // The page's frame moves down from the band's bottom; its content stays pinned inside it.
        shownPage?.webView.frame.origin.y = webViewTop()
        updateStatusBand()
        updatePullArc()
        tracePull()
    }

    /// Places the pull's ring in the middle of the status band, where it stays as the page comes
    /// down, and fills it through the pull.
    func updatePullArc() {
        guard !pullArc.isLeaving else { return }
        let safeTop = view.safeAreaInsets.top
        // Below the Dynamic Island or notch and low enough that the whole ring shows: the page
        // comes down under it, and the ring stays put as it fills.
        let side = MobilePullRing.side(safeTop: safeTop)
        let size = CGSize(width: side, height: side)
        if pullArc.bounds.size != size {
            pullArc.bounds = CGRect(origin: .zero, size: size)
        }
        pullArc.center = MobilePullRing.center(safeTop: safeTop, screenWidth: view.bounds.width)
        let ink = MobilePullRing.ink(statusBarFill: statusBarFill, darkMode: traitCollection.userInterfaceStyle == .dark)
        if let color = Palette.color(hex: ink) {
            pullArc.color = color
        }
        pullArc.speed = pullSpeed
        pullArc.progress = MobilePullRing.progress(pull: pagePull ?? 0)
    }

    /// Records the pull's last live numbers for a UI test, after layout put the frames there.
    /// The page springs back afterwards, so the trace keeps how far it and the band went.
    func tracePull() {
        guard pullTraceView.superview != nil, let page = shownPage else { return }
        // The page's visible top in the view's coordinates: its frame, less its scroll.
        let top = page.webView.frame.minY - page.webView.scrollView.contentOffset.y
        pullTraceView.accessibilityValue = "pull \(Int(pullTraceMax)) band \(Int(statusBand.frame.height)) page \(Int(top))"
    }

    // MARK: Layout

    /// The web view's top in the page: at the status band's bottom, raised inside the card as the
    /// search sheet pushes the page back, and lowered by a pull to refresh.
    private func webViewTop() -> CGFloat {
        let safeTop = view.safeAreaInsets.top
        var top = safeTop + (pagePull ?? 0)
        if drawerProgress > 0.001 {
            let scale = MobilePageBehindSearch.transform(in: view.bounds.size, safeTop: safeTop,
                                                         progress: drawerProgress).scale
            top += safeTop * ((1 - drawerProgress) / max(scale, 0.001) - 1)
        }
        return top
    }

    /// Lays out what the bar's own travel changes: the page's bottom edge, the bar and its
    /// controls, the strip that brings it back, and the switch above it. The rest of the chrome
    /// waits for the bar's end (`layoutChrome`), so a frame of dragging costs little.
    /// `everyFrame` is the display link's own tick: what the bar's travel cannot change (the
    /// strip's frame, whether the switch above the bar is offered) waits for the chrome's layout.
    private func layoutBarAndPage(everyFrame: Bool = false) {
        let bounds = view.bounds
        let safeBottom = view.safeAreaInsets.bottom
        // The page's view runs on under the bar on iOS 26 (its content laid out above it), and
        // ends at the bar's top before; in both, its visible bottom is the bar's top.
        if let page = shownPage, pageFollowsChrome { layoutPageView(page) }
        // The bar's top is the page's bottom: it rides between its open place and the safe
        // area's line, and the finger's drag decides where, not the page's scroll. The keyboard
        // covers the bar; it steps out of the way, and the page keeps its frame.
        let barY = keyboardHeight > safeBottom && !isSearching ? bounds.height : barTopEdge(progress: barCollapse.progress)
        bar.frame = CGRect(x: 0, y: barY, width: bounds.width, height: MobileBottomBar.height + safeBottom)
        traceViewport()
        // Its controls fade out as it slides away, and are live only while it is all there.
        bar.collapseProgress = barCollapse.progress
        if !everyFrame { barReveal.frame = MobileBottomBar.revealStrip(in: bounds.size, safeBottom: safeBottom) }
        barReveal.isHidden = !barCollapse.isClosed || isSearching || switcher != nil || shownPage == nil
        // The tip and the pill over the bar go with it too.
        placeBlockerNotices()
        layoutBrowseToggle(barTop: barY, recheck: !everyFrame)
    }

    /// Puts a UI test's hidden readout on screen when its launch flag (`-<flag> YES`) asks for it.
    private func installTrace(_ trace: UIView, flag: String, id: String, label: String? = nil, value: String? = nil) {
        guard LaunchOptions.value(flag) == "YES" else { return }
        trace.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        trace.isAccessibilityElement = true
        trace.accessibilityIdentifier = id
        trace.accessibilityLabel = label
        trace.accessibilityValue = value
        trace.isUserInteractionEnabled = false
        view.addSubview(trace)
    }

    /// Where `page` shows its bottom: its view's bottom less what the bar covers of it.
    func visibleBottom(of page: WebPage) -> CGFloat {
        guard #available(iOS 26.0, *) else { return page.webView.frame.maxY }
        return page.webView.frame.maxY - page.webView.obscuredContentInsets.bottom
    }

    /// Records, for a UI test, the most the page's visible bottom (its view's bottom less what the
    /// bar covers) has ever been apart from the bar's top, frame by frame as the bar moves.
    private func traceViewport() {
        guard viewportTraceView.superview != nil, let page = shownPage, pageFollowsChrome,
              keyboardHeight <= view.safeAreaInsets.bottom else { return }
        if #available(iOS 26.0, *) {
            viewportMismatch = max(viewportMismatch, abs(visibleBottom(of: page) - bar.frame.minY))
            viewportTraceView.accessibilityValue = "changes \(viewportChanges) apart \(Int(viewportMismatch.rounded(.up)))"
                + " range \(Int(page.webView.maximumViewportInset.bottom))"
        }
    }

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
        if let switcher {
            if switcher.bandHeight != safeTop { switcher.bandHeight = safeTop }
            // The card that opens fills the page's view, under the bar too: the page it becomes
            // has its bottom there, from the first frame.
            if switcher.pageBottom != pageViewBottom { switcher.pageBottom = pageViewBottom }
        }
        // The bar and the page it covers are one layout, shared with the drag's own frames.
        layoutBarAndPage()
        // The page's own background fills the container around and under the web view, which now
        // runs to the safe area's edge: the bar's blur and a page's picture keep the page's colour
        // there.
        let pageBackground = shownPage?.webView.underPageBackgroundColor
        if pageContainer.backgroundColor != pageBackground {
            pageContainer.backgroundColor = pageBackground
        }
        pageDim.frame = pageContainer.bounds
        dotField.frame = bounds
        updateStatusBand()
        updatePullArc()
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

        let pull = isSearching ? nil : searchPull
        let emptyHome = MobileEmptyHome(home: showsEmptyHome, searching: isSearching,
                                        incognitoSearch: incognitoSearch, pulling: pull != nil)
        // With no tabs the bar is the empty tab row's: Spaces, the plus and Settings. The tab row sets its own
        // while it is up, and a page gets the tab stack and its menu back.
        if emptyHome.barShowsTabRow { bar.mode = .tabs } else if switcher == nil { bar.mode = .page }
        // On the empty home the bar has no slab: its buttons float on the dots.
        bar.overBackdrop = emptyHome.barFloats
        searchHint.place(centerX: bounds.midX, pillTop: frames.pill.minY + bar.frame.minY - frames.bar.minY)
        // Pulled out of the pill (#623), the sheet's top follows the finger and its field grows
        // from the pill on the way up.
        let pulled = pull.map { MobileSwipe.searchPullProgress(dragUp: $0) }
        bar.controlsVisibility = isSearching ? 0 : 1 - (pulled ?? 0)
        placeCoachMark()

        sheet.rowsInView = MobileSearchSheet.rowsInView(screenHeight: bounds.height, keyboardHeight: keyboard, safeTop: safeTop)
        let top = isSearching ? currentTop : bar.frame.minY - max(0, pull ?? 0)
        sheet.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(MobileSearchSheet.height(rows: sheet.rowsInView) + keyboard, bounds.height - top))
        sheet.collapsedFieldFrame = bar.pillFrame
        sheet.openness = isSearching ? pulledSheetHold?.openness ?? 1 : pulled ?? 0
        // Grown out of the pill, the bar itself carries the drawer: its material and colour reach
        // the drawer's top edge, and its tabs, menu and plus ride that edge.
        bar.drawerRise = drawer.growsFromBar ? max(0, bar.frame.minY - sheet.frame.minY) : 0
        // Square at the bar, the sheet's radius only once the drawer is fully open.
        bar.drawerOpenness = drawer.growsFromBar ? drawerProgress : 0
        let fieldOpenness = drawer.fieldOpenness(isSearching: isSearching, pulled: pulled)
        sheet.fieldOpenness = fieldOpenness
        sheet.listOpenness = drawer.listOpenness(fieldOpenness: fieldOpenness, drawerProgress: drawerProgress)
        if newTabDrawerTraceView.superview != nil {
            newTabDrawerTraceView.accessibilityValue = newTabDrawerTrace()
        }
        dismissArea.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, top))
        logo.alpha = emptyHome.showsLogo ? 1 : 0
        dotField.alpha = emptyHome.showsDots ? 1 : 0
        searchHint.alpha = emptyHome.showsSearchHint ? 1 : 0
    }

    /// Lays a page-coloured floor under a page that is sliding across, so the bar's material has
    /// the page behind it in the gap rather than the app's own backdrop.
    func showSwapBackdrop(for page: WebPage?) {
        swapBackdrop.frame = view.bounds
        swapBackdrop.backgroundColor = pageBackground(of: page)
        swapBackdrop.isHidden = false
    }

    func hideSwapBackdrop() {
        swapBackdrop.isHidden = true
    }

    /// Walks the bar to its closed or open end from wherever it is, moving the page's bottom edge
    /// with it. A release after a drag usually plays this; so does a tap on the strip the bar
    /// leaves.
    private func snapBar(toClosed closed: Bool) {
        // Already settling to that end: a resize during it can ask again, and restarting would
        // never finish.
        if case .settling(let going, _, _) = barMotion, going == closed { return }
        let from = barCollapse.progress
        stopBarLink()
        guard from != (closed ? 1 : 0) else { return finishBarSnap(closed: closed) }
        barMotion = .settling(closed: closed, from: from, startedAt: CACurrentMediaTime())
        startBarLink()
    }

    /// The bar is at its end: it rests there, and the rest of the chrome catches up.
    private func finishBarSnap(closed: Bool) {
        barCollapse.settle(atClosed: closed)
        stopBarLink()
        layoutChrome()
    }

    private func startBarLink() {
        guard barLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(barLinkTick(_:)))
        // The page's scroll runs at ProMotion's rate; the bar and the page's bottom keep up.
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        barLink = link
    }

    private func stopBarLink() {
        barLaidOutAt = nil
        barLink?.invalidate()
        barLink = nil
        barMotion = nil
    }

    @objc private func barLinkTick(_ link: CADisplayLink) {
        guard let motion = barMotion else { return stopBarLink() }
        switch motion {
        case .settling(let closed, let from, let startedAt):
            let t = (CACurrentMediaTime() - startedAt) / MobileMotion.barSnap
            guard t < 1 else { return finishBarSnap(closed: closed) }
            let to: CGFloat = closed ? 1 : 0
            barCollapse.setProgress(from + (to - from) * MobileMotion.easeOut(CGFloat(t)))
            layoutBarAndPage(everyFrame: true)
        case .following:
            // A touch can be taken from the page (a system gesture, a call) without its end
            // reaching us. Without a finger the bar settles by the direction it last went in,
            // rather than sit between its ends for ever.
            if let pan = shownPage?.webView.scrollView.panGestureRecognizer,
               pan.state != .began, pan.state != .changed {
                snapBar(toClosed: barCollapse.heading)
                return
            }
            // The finger moves the bar; this only puts the frames where it got to, and a frame
            // where it stood still lays nothing out.
            guard barCollapse.progress != barLaidOutAt else { return }
            barLaidOutAt = barCollapse.progress
            layoutBarAndPage(everyFrame: true)
        }
    }

    /// The bar is back where it belongs with no animation of its own: another tab, the tab row,
    /// the search sheet. A snap or a follow that was playing is dropped.
    private func showBarAtOnce() {
        stopBarLink()
        barCollapse.reveal()
    }

    func animateChrome(duration: TimeInterval, options: UIView.AnimationOptions) {
        chromeMoves.began()
        UIView.animate(withDuration: duration, delay: 0, options: options.union([.beginFromCurrentState, .allowUserInteraction])) {
            self.layOutChromeForMove()
        } completion: { _ in
            self.chromeMoveEnded()
        }
    }

    /// A chrome move on one of the app's springs, for a drawer let go to settle rather than a
    /// fixed curve.
    func animateChrome(spring: MobileMotion.Spring, initialVelocity: CGFloat = 0) {
        chromeMoves.began()
        UIView.animate(spring: spring, initialVelocity: CGVector(dx: initialVelocity, dy: initialVelocity), animations: {
            self.layOutChromeForMove()
        }, completion: {
            self.chromeMoveEnded()
        })
    }

    /// Only once every move has ended: one that moved nothing (a second keyboard notice) ends at once.
    private func chromeMoveEnded() {
        guard chromeMoves.ended() else { return }
        chromeSettled()
    }

    /// What every chrome move lays out: the page and the sheet, inside the animation's block.
    private func layOutChromeForMove() {
        pageOpening = false
        pageClosing = false
        layoutChrome()
        bar.layoutIfNeeded()
        sheet.layoutIfNeeded()
    }

    func chromeSettled() {
        guard !isSearching, searchPull == nil else { return }
        sheet.isHidden = true
        sheet.hideIncognitoLabel(animated: false)
        // The drawer's incognito is only for the search: back to the shown tab's own state.
        restoreBarIncognito()
        bar.pillVisibility = 1
        // The drawer is gone with the sheet: the bar is only the bar again.
        bar.drawerAppearance = 0
        bar.drawerRise = 0
        bar.drawerOpenness = 0
        bar.drawerActive = false
        bar.drawerLetGo = false
        drawer = MobileNewTabDrawer()
        applyDrawerChrome()
        // The settled bar, for `-CraTraceNewTabDrawer`: no layout follows to write it.
        if newTabDrawerTraceView.superview != nil {
            newTabDrawerTraceView.accessibilityValue = newTabDrawerTrace()
        }
    }

    /// The bar's material takes the new tab drawer's colour as soon as the drawer starts, over a
    /// fixed move of its own: the finger's distance does not decide when the colour changes.
    func setDrawerMaterial(_ showing: Bool) {
        // A light page in a dark app gives a light bar but a dark drawer; the plus switches to the
        // dark appearance's own fill as the drawer colour comes in (or back on close).
        drawer.showsMaterial = showing
        applyDrawerChrome()
        if showing { bar.drawerActive = true }
        bar.drawerLetGo = !showing
        UIView.animate(withDuration: MobileNewTabDrawer.materialFade, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.bar.drawerAppearance = showing ? 1 : 0
        }
    }

    /// The sheet's plus takes the bar's chrome, or the dark drawer's once its colour is in; the
    /// open field follows the page under the bar.
    private func applyDrawerChrome() {
        sheet.lightPlusChrome = MobileBottomBar.lightChrome(
            darkMode: traitCollection.userInterfaceStyle == .dark, pageIsLight: bar.pageIsLight,
            incognito: bar.isIncognito, floats: false, overDrawer: drawer.showsMaterial)
        sheet.fieldStyle = drawer.fieldStyle(pageIsLight: bar.pageIsLight)
        sheet.fieldOverTabRow = bar.mode == .tabs
    }

    /// The bar turns incognito's black for an incognito tab or search, and the sheet's plus
    /// follows it.
    func setBarIncognito(_ incognito: Bool) {
        bar.isIncognito = incognito
        applyDrawerChrome()
    }

    /// For the new tab drawer's UI test: where the bar has grown to, whether the plus has become
    /// the field, and whether the drawer's colour is over the bar's material.
    func newTabDrawerTrace() -> String {
        String(format: "rise %.0f field %.2f material %.2f base %.2f list %.2f word %.2f tabs %@ sheet %.2f",
               bar.drawerRise, sheet.fieldOpenness, bar.drawerAppearance, bar.materialAlpha,
               sheet.listOpenness, sheet.incognitoWordOpacity,
               bar.tabsButton.isUserInteractionEnabled ? "live" : "off", sheet.alpha)
    }

    /// Keeps a drag's last frame for `-CraTraceNewTabDrawer`: the release overwrites the settled
    /// trace, this one keeps what the pull was doing. Nothing to do without the trace element.
    func traceNewTabDrawerDrag() {
        guard newTabDrawerDragTraceView.superview != nil else { return }
        newTabDrawerDragTraceView.accessibilityValue = newTabDrawerTrace()
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
        if isSearching, drawer.opensFromPull, height > 0 {
            // A pulled-up drawer's rise springs into place instead of following the keyboard's
            // own curve; the keyboard still moves in underneath it.
            animateChrome(spring: MobileNewTabDrawer.bounce)
        } else if duration > 0 {
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
    /// backdrop, the logo over the dots, "Tap to search" and the bar.
    @objc func dismissSearch() {
        setSearching(false)
    }

    /// `keepingPull`: closing, the sheet stays this far above the bar under the finger (a drag down on it, #655)
    /// instead of going into the pill; the drag moves it on from there.
    /// `replacingMenuAt`: the sheet takes the page menu's place: its top starts where the menu's
    /// panel was, its field already full size, so the address turns editable in place.
    /// `editingAddress`: the sheet edits the page on screen; the page behind stays where it is
    /// instead of being pushed back, as only a search from the + button does.
    /// `deferDrawerMaterial`: a drag down has begun; the drawer keeps its own colour until the
    /// finger lets go and the close actually starts.
    /// `releaseVelocity`: a drawer pulled out of the bar was let go at this vertical speed (pt/s,
    /// down positive); its spring carries it on (`MobileNewTabDrawer.releaseVelocity`).
    func setSearching(_ searching: Bool, incognito: Bool? = nil, keepingPull: CGFloat? = nil,
                      replacingMenuAt replacingTop: CGFloat? = nil, editingAddress: Bool = false,
                      deferDrawerMaterial: Bool = false, releaseVelocity: CGFloat = 0) {
        guard searching != isSearching else { return }
        // Closing from a tap or the keyboard: the word goes as the close starts. A drag keeps it
        // until the finger is released (the gesture hides it then).
        if !searching, keepingPull == nil {
            sheet.hideIncognitoLabel()
            restoreBarIncognito()
        }
        // A search from + (or a launch that types) grows out of the bar; the page menu's address
        // editor takes the menu's place and keeps the sheet's own surface.
        if searching {
            drawer.growsFromBar = !editingAddress && replacingTop == nil
            if !drawer.growsFromBar {
                drawer.showsMaterial = false
                applyDrawerChrome()
            }
        }
        // Opening lets go of either hold; closing keeps a drag down's open field until it lets go.
        if searching || drawer.fieldHold == .closed { drawer.fieldHold = .none }
        if drawer.growsFromBar, searching || !deferDrawerMaterial {
            setDrawerMaterial(searching)
        }
        // The sheet grows out of the pill, so the bar is all there when a search starts. Whatever a page swipe
        // still has over the page goes with the cover: the sheet comes over both.
        if searching {
            liftCover()
            showBarAtOnce()
            endPageSwipe()
        }
        // A sheet pulled out of the pill is already laid out under the finger: it goes on from there.
        let pulled = searchPull != nil
        if searching { drawer.opensFromPull = pulled }
        let replacing = searching ? replacingTop : nil
        // A drawer pulled out of the bar and let go carries straight on to its open place instead
        // of waiting where the finger left it for the keyboard: that wait froze a flick.
        let springsFromPull = searching && pulled && drawer.growsFromBar
        searchPull = searching ? nil : keepingPull
        var springVelocity: CGFloat = 0
        if springsFromPull {
            let top = MobileSearchSheet.releasedTop(
                screenHeight: view.bounds.height, expectedKeyboard: max(lastKeyboardHeight, view.safeAreaInsets.bottom),
                keyboardSeen: lastKeyboardHeight > 0, safeTop: view.safeAreaInsets.top, releasedAt: sheet.frame.minY)
            springVelocity = MobileNewTabDrawer.releaseVelocity(fingerVelocity: releaseVelocity,
                                                                releasedAt: sheet.frame.minY, target: top)
            pulledSheetHold = (top, 1)
        } else {
            pulledSheetHold = searching && (pulled || replacing != nil)
                ? (replacing ?? sheet.frame.minY, replacing != nil ? 1 : sheet.openness)
                : nil
        }
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
        setNeedsStatusBarAppearanceUpdate()
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
        } else if springsFromPull {
            animateChrome(spring: MobileNewTabDrawer.bounce, initialVelocity: springVelocity)
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
            if springsFromPull {
                // The keyboard takes tens of milliseconds of the main thread to come up, and UIKit
                // holds the next frame until the touch's whole update is done, flush or not: asked
                // for inside the release, it froze the spring's first frames. Asked for on the
                // next turn, after the release has gone to the screen, it only delays itself.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isSearching else { return }
                    self.sheet.field.becomeFirstResponder()
                }
            } else {
                sheet.field.becomeFirstResponder()
            }
        } else {
            sheet.field.resignFirstResponder()
        }
        // No software keyboard (a hardware one is attached): move the chrome ourselves. A pulled
        // sheet waits a moment for the keyboard, whose animation takes it up (#623).
        if !keyboardDroveLayout {
            if pulledSheetHold != nil {
                // The page behind sits back now; the sheet stays where it was let go (a drawer let
                // go out of the bar is already on its way).
                if !springsFromPull {
                    animateChrome(duration: MobileSearchMotion.settleDuration, options: .curveEaseInOut)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self, self.isSearching, self.pulledSheetHold != nil else { return }
                    self.pulledSheetHold = nil
                    if self.drawer.opensFromPull {
                        // Pulled up and let go with no keyboard to carry it: the drawer springs
                        // into place.
                        self.animateChrome(spring: MobileNewTabDrawer.bounce)
                    } else {
                        self.animateChrome(duration: MobileSearchMotion.settleDuration, options: .curveEaseInOut)
                    }
                }
            } else if !leads {
                animateChrome(duration: MobileSearchMotion.settleDuration, options: .curveEaseInOut)
            }
        }
    }

    /// Fills the sheet for a new search and puts it in place of the pill, still closed.
    func prepareSearchSheet(incognito: Bool? = nil) {
        dropBlockerNotices()
        editsShownTab = false
        sheet.forgetAccessories()
        if let incognito { incognitoSearch = incognito }
        sheet.isIncognito = incognitoSearch
        // The bar carries the drawer's colour, so it turns incognito's dark with the sheet.
        setBarIncognito(incognitoSearch)
        // Grown out of the bar, the drawer sits on the bar's material; the sheet's own surface is
        // for the menu's address editor, whose drawer is not the bar.
        sheet.drawsSurface = !drawer.growsFromBar
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
        bar.pillVisibility = 0
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
        // The bar's plus comes back under the rising picture, fading rather than popping in.
        bar.revealPill(over: MobileSheetLeave.leaveDuration)
        UIView.animate(withDuration: MobileSheetLeave.leaveDuration, delay: 0, options: [.curveEaseInOut]) {
            picture.transform = CGAffineTransform(translationX: 0, y: -MobileSheetLeave.leaveRise)
            picture.alpha = 0
        } completion: { _ in
            picture.removeFromSuperview()
        }
    }

    /// The screen goes to the canvas colour as the sheet leaves and stays so until `page` has drawn, so a dark site
    /// doesn't show white first; at most `MobileSheetLeave.coverLongestHold`.
    func coverUntilDrawn(_ page: WebPage) {
        liftCover()
        endPageSwipe()
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

    /// The bar's incognito follows the tab on screen, not an incognito search that was closed.
    func restoreBarIncognito() {
        setBarIncognito(store.selected?.isIncognito ?? false)
    }

    func searchSheetDidToggleIncognito(_ sheet: SearchSheet) {
        incognitoSearch.toggle()
        setBarIncognito(incognitoSearch)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        // Only the new tab panel darkens: the sheet's own look and the bar's material. The
        // page (or home) behind it keeps its colours.
        sheet.setIncognito(incognitoSearch)
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

    /// Starts a page with nothing in it yet on its tab's content: Browse for Me's answer, where
    /// the tab was (#656), or its address.
    func startContent(of page: WebPage, for tab: MobileTab) {
        guard page.webView.url == nil, !page.isBrowsing, !page.webKitOwnsInitialNavigation else { return }
        page.restoresAtTop = false
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

    /// The band colour a tab brings with it: its page's theme-color or own background, or the top
    /// of its picture before that page knows one. A tab with no page yet has only its picture, and
    /// asking must not make the page: the tab row asks about every tab in it.
    func bandColour(for tab: MobileTab) -> UIColor? {
        let picture = store.snapshot(tab.id)
        guard let page = store.existingPage(tab.id) else { return picture?.topBandColor() }
        let fill = MobileStatusBand.tabFill(pageFill: bandFill(for: page),
                                            pictureTop: Palette.hex(picture?.topBandColor(), traits: traitCollection),
                                            loaded: page.webView.url != nil)
        return fill.flatMap(Palette.color(hex:))
    }

    func show(_ tab: MobileTab) {
        let page = self.page(for: tab)
        guard page !== shownPage else { return }
        closeReader()
        dropBlockerNotices()
        shownPage?.webView.removeFromSuperview()
        shownPage?.delegate = nil
        shownPage = page
        setBarIncognito(tab.isIncognito)
        liftCoverIfDue()
        pagePull = nil
        page.delegate = self
        page.webView.allowsBackForwardNavigationGestures = false
        // The tab brings its band with it: the status bar's text takes its colour the moment it
        // is picked, before its page has loaded and reported its own.
        shownBandFill = bandColour(for: tab).flatMap { Palette.hex($0, traits: traitCollection) }
        // The page's own background goes behind the chrome at once, so a page that slides or
        // fades in does not leave the bar looking through to the app's background.
        pageContainer.backgroundColor = page.webView.underPageBackgroundColor
        // Every tab shows with its bar: the page's frame is the open one.
        showBarAtOnce()
        // The page's container starts at the status band's bottom; it never sits under the band,
        // and the page's view runs on under the bar where WebKit can lay it out clear of it.
        layoutPageView(page)
        // A page riding in a swipe's card stays there until the card has become the page.
        if !ridesInSwipeCard(page) { pageContainer.insertSubview(page.webView, belowSubview: pageDim) }
        page.restoresAtTop = false
        startContent(of: page, for: tab)
        if let browseLoading {
            browseLoading.isHidden = browseLoading.tabID != page.tabID
            pageContainer.insertSubview(browseLoading, belowSubview: pageDim)
        }
        updateBrowseToggle()
        pageShownAt = CACurrentMediaTime()
    }

    func refreshTabStack() {
        // The button previews the two tabs to this page's left in the switcher, never the page
        // itself: the nearest on top, and the one before it underneath.
        let preview = store.buttonPreview
        let front = preview.first
        let back = preview.dropFirst().first
        bar.tabsButton.setSnapshots(front: front.flatMap { store.snapshot($0.id) }, back: back.flatMap { store.snapshot($0.id) })
    }

    func captureSnapshot() {
        guard let page = shownPage else { return }
        let id = page.tabID
        page.takeSnapshot(height: pageViewHeight) { [weak self] image in self?.keepSnapshot(image, for: id) }
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

    /// No tab is open: the empty home, which is the tab row with no cards, so the tab button has no row to open.
    var showsEmptyHome: Bool {
        MobileEmptyHome.isHome(tabOnScreen: store.selected != nil, rowTabs: store.switcherTabs.count)
    }

    @objc func showTabs() {
        guard switcher == nil, !isSearching, !showsEmptyHome else { return }
        dropBlockerNotices()
        guard let page = shownPage else { return settleSwitcher(prepareSwitcher()) }
        let id = page.tabID
        page.takeSnapshot(height: pageViewHeight) { [weak self] image in
            guard let self, self.switcher == nil else { return }
            if let image { self.store.setSnapshot(image, for: id) }
            self.settleSwitcher(self.prepareSwitcher())
        }
    }

    /// A tab's page background, for whatever stands in for its page under the bar (the floor
    /// while the tab row closes, a neighbour's card in a swipe): the page's own colour, or the
    /// app's when it has none.
    func pageBackground(for id: UUID) -> UIColor {
        pageBackground(of: store.existingPage(id))
    }

    func pageBackground(of page: WebPage?) -> UIColor {
        page?.webView.underPageBackgroundColor ?? .systemBackground
    }

    /// Puts the tab row up looking exactly like the page: the focused card fills the screen.
    /// From there it settles into the row (`settleSwitcher`) or follows a finger first.
    func prepareSwitcher() -> TabSwitcherView {
        // The row goes in right over the page: a page swipe's picture still over the page would cover it.
        liftCover()
        endPageSwipe()
        let switcher = TabSwitcherView(frame: view.bounds)
        switcher.delegate = self
        switcher.bandHeight = view.safeAreaInsets.top
        switcher.pageBottom = pageViewBottom
        let tabs = store.switcherTabs
        let selected = store.selected?.id
        // The row opens focused on the card behind the page: the one to its left, which is the
        // tab the button's back card shows in the row's usual order. A first card focuses itself.
        let focus = store.switcherFocus?.id
        let onRow = store.selected.map { !$0.isIncognito } ?? false
        // On a private page the private tabs waiting unseen are cards too, marked with the eyes.
        switcher.setTabs(
            tabs, focus: focus,
            snapshot: store.snapshot,
            favicon: { tab in
                tab.isIncognito
                    ? UIImage(systemName: "eyes")?.withTintColor(.secondaryLabel, renderingMode: .alwaysOriginal)
                    : self.favicons.icon(for: tab.url)
            },
            band: { self.bandColour(for: $0) })
        // An incognito page has no card to shrink into; the row just appears.
        switcher.expandedID = onRow ? selected : nil
        switcher.expansion = onRow ? 1 : 0
        switcher.setBottomFill(selected.map(pageBackground(for:)) ?? .systemBackground, alpha: 1)
        view.insertSubview(switcher, aboveSubview: pageContainer)
        switcher.layoutIfNeeded()
        self.switcher = switcher
        // The page and its status band stay behind the row: the switcher starts at the band's
        // bottom, so the row's cards never cover or move the band.
        showBarAtOnce()
        return switcher
    }

    func settleSwitcher(_ switcher: TabSwitcherView) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SyncedSidebar.readAhead()
        offerSyncCard(in: switcher)
        UIView.animate(spring: MobileMotion.tabRowSettle) {
            switcher.expansion = 0
            switcher.setBottomFill(nil, alpha: 0)
            switcher.layoutIfNeeded()
            self.bar.mode = .tabs
            self.layoutChrome()
            self.bar.layoutIfNeeded()
        }
    }

    /// Back from a row that was only peeked at: the card grows into its page again.
    func cancelSwitcher(_ switcher: TabSwitcherView) {
        if let selected = store.selected?.id {
            switcher.setBottomFill(pageBackground(for: selected), alpha: 1)
        }
        UIView.animate(spring: MobileMotion.tabOpen) {
            switcher.expansion = 1
            switcher.layoutIfNeeded()
            self.layoutChrome()
        } completion: {
            self.pageContainer.isHidden = false
            switcher.removeFromSuperview()
            if self.switcher === switcher { self.switcher = nil }
            self.dropWarmPage()
            self.updateStatusBand()
        }
    }

    /// A page put back in the window draws a frame or two later. The tab under the finger gets
    /// its page back in the window now, at the bottom of the page's container under the row, so
    /// a pick only moves it within the container and it shows from the grow's first frame.
    func tabSwitcher(_ switcher: TabSwitcherView, mayPick id: UUID) {
        guard let page = store.existingPage(id), page !== shownPage, page !== warmPage else { return }
        dropWarmPage()
        guard page.webView.superview == nil else { return }
        layoutPageView(page)
        pageContainer.insertSubview(page.webView, at: 0)
        warmPage = page
    }

    /// The page put in the window for a pick that didn't come (`mayPick`) leaves it again.
    private func dropWarmPage() {
        if let page = warmPage, page !== shownPage, page.webView.superview === pageContainer {
            page.webView.removeFromSuperview()
        }
        warmPage = nil
    }

    func tabSwitcher(_ switcher: TabSwitcherView, didSelect id: UUID) {
        // A page already in memory has its content to show; a new one may be blank for a moment,
        // so it grows under its picture (`MobileTabCarousel.growth`).
        let inMemory = store.existingPage(id) != nil
        store.bringToFront(id)
        guard let tab = store.selected else { return }
        show(tab)
        warmPage = nil
        closeSwitcher(switcher, growing: id, pageInMemory: inMemory)
    }

    /// A tap on the row's empty background goes back to the page that was on screen, not to the
    /// focused card beside it.
    func tabSwitcherDidTapOutside(_ switcher: TabSwitcherView) {
        guard let selected = store.selected else { return }
        closeSwitcher(switcher, growing: selected.id, pageInMemory: true)
    }

    /// Grows `id`'s card back into the page, with the real page in it (`livePage`), and takes
    /// the row away.
    private func closeSwitcher(_ switcher: TabSwitcherView, growing id: UUID, pageInMemory: Bool) {
        switcher.expandedID = id
        switcher.isUserInteractionEnabled = false
        let live = livePage(in: switcher, for: id, pageInMemory: pageInMemory)
        let fadeAndGrow = DispatchGroup()
        if live != nil { fadeAndGrow.enter(); fadeAndGrow.enter() }
        // The bar and the status bar take the page's colours as it starts to grow, not once it
        // has landed.
        growingFill = store.tabs.first { $0.id == id }.flatMap(bandColour(for:))
            .flatMap { Palette.hex($0, traits: traitCollection) }
        updateStatusBand()
        UIView.animate(withDuration: MobileBottomBar.materialFade) { self.setNeedsStatusBarAppearanceUpdate() }
        let card = switcher.cardFrame(for: id) ?? .zero
        let page = CGRect(x: 0, y: 0, width: view.bounds.width, height: pageViewBottom)
        let travel = max(abs(card.minX - page.minX), abs(card.minY - page.minY),
                         abs(card.maxX - page.maxX), abs(card.maxY - page.maxY))
        // On its page to under half a point: the page is handed back now, not once the spring has
        // settled to UIKit's far finer tolerance.
        let handOver = MobileTabCarousel.handOverTime(spring: MobileMotion.tabOpen, travel: travel)
        bar.slabFadesIn = true
        let grow = UIView.animate(spring: MobileMotion.tabOpen) {
            switcher.expansion = 1
            switcher.layoutIfNeeded()
            self.bar.mode = .page
            self.layoutChrome()
            self.bar.layoutIfNeeded()
        } completion: {
            if let live {
                live.card.end()
                fadeAndGrow.leave()
            }
            self.pageContainer.isHidden = false
            switcher.removeFromSuperview()
            if self.switcher === switcher { self.switcher = nil }
            self.dropWarmPage()
            self.growingFill = nil
            self.updateStatusBand()
            self.refreshTabStack()
        }
        // The bar's slab comes in at the grow's start (`MobileTabCarousel.slabFade`), over the
        // row's backdrop down to the screen's edge: the strip below the page stays out of it
        // (`setBottomFill`), as solid page colour it showed light under the home indicator
        // through a slab still coming in. The page is under the bar once the card lands.
        bar.fadeSlabIn(over: MobileTabCarousel.slabFade(handOver: handOver))
        growTraceView.accessibilityValue = (bar.pageIsLight ? "light" : "dark") + (bar.materialFaded ? " faded" : " at once")
            + (bar.slabFading && !switcher.bottomFillShows ? ", slab fading in" : ", slab whole")
        if let live {
            live.card.fadePicture(over: MobileTabCarousel.pictureFade(live.growth, handOver: handOver)) { fadeAndGrow.leave() }
            // The layer over the page goes once both the grow and the picture's fade are done.
            fadeAndGrow.notify(queue: .main) { live.front.removeFromSuperview() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + handOver) {
            guard grow.state == .active else { return }
            grow.stopAnimation(false)
            grow.finishAnimation(at: .end)
        }
    }

    /// Grows `id`'s card with the live page (`LivePageCard`): the row goes under the page's
    /// container, which takes the card's place and shape, and the cards over this one move to a
    /// layer above it. The page view never leaves its container, so it shows and takes touches
    /// all the way. Nil when Browse for Me's loading covers the page: the card grows with its
    /// picture alone.
    private func livePage(in switcher: TabSwitcherView, for id: UUID,
                          pageInMemory: Bool) -> (card: LivePageCard, front: UIView, growth: MobileTabCarousel.Growth)? {
        guard let page = shownPage, page.tabID == id else {
            tabOpenTraceView.accessibilityValue = "picture"
            return nil
        }
        let growth = MobileTabCarousel.growth(pageInMemory: pageInMemory, hasAddress: page.webView.url != nil,
                                              covered: browseLoadingCovers(id))
        switch growth {
        case .picture: tabOpenTraceView.accessibilityValue = "picture"; return nil
        case .live: tabOpenTraceView.accessibilityValue = "live"
        case .liveUnderPicture: tabOpenTraceView.accessibilityValue = "live under picture"
        }
        // The shape the tab's picture is taken in (`showTabs`), from the status band's bottom.
        let shape = CGRect(x: 0, y: view.safeAreaInsets.top, width: view.bounds.width, height: pageViewHeight)
        let card = LivePageCard(container: pageContainer, page: shape)
        let front = UIView(frame: view.bounds)
        front.isUserInteractionEnabled = false
        // The row moves, not the page: moving the page's view would blank it for a frame.
        view.insertSubview(switcher, belowSubview: pageContainer)
        view.insertSubview(front, aboveSubview: pageContainer)
        pageContainer.isHidden = false
        switcher.growLive(card, for: id, front: front)
        UIView.performWithoutAnimation { switcher.layoutIfNeeded() }
        return (card, front, growth)
    }

    func tabSwitcher(_ switcher: TabSwitcherView, didClose id: UUID) {
        if warmPage?.tabID == id { dropWarmPage() }
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
        // Full height on iPad and on the open iPhone Duo, which is treated like a small iPad (#866).
        let screen = MobileScreenClass.of(size: view.window?.bounds.size ?? view.bounds.size, isPad: traitCollection.userInterfaceIdiom == .pad)
        return MobileSettingsSheet.appSettingsHeights(onPad: screen.opensSheetsFull).map { ($0 == .medium ? UISheetPresentationController.Detent.medium : UISheetPresentationController.Detent.large)() }
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
        // from one that put it away (#505). It comes back with its page's bottom edge.
        if page === shownPage, !isSearching,
           barCollapse.pageChanged(collapses: collapsesBar(page)) {
            snapBar(toClosed: false)
        }
        // A load starting or ending, or another site's switch, can move the page's bottom between
        // the bar's top and the safe area's edge.
        fitPageToBar(page)
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
                    page.restoresAtTop = false
                } else if offset >= CGFloat(PageHistory.restoreAtTopBelow) {
                    // Saved further down than the threshold: it keeps its place.
                    page.restoresAtTop = false
                }
                // At the top already, or not there yet: the page's own scroll reports the saved
                // place (`WebPage.scrollViewDidScroll`), and a finger ends the wait.
            } else {
                page.restoresAtTop = false
            }
        }
        if success { pageFinishedForBlockerNotices(page) }
        // Its content is laid out now: a page that fits its screen brings back a bar that was
        // away (one still loading lays out empty first, so it was left alone until now), and is
        // laid out above the bar.
        returnBarIfThePageFits(page)
        fitPageToBar(page)
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

    func webPage(_ page: WebPage, didDragBy drag: CGFloat) {
        guard page === shownPage, !isSearching else { return }
        guard barCollapse.dragged(by: drag, collapses: collapsesBar(page), scrolls: scrolls(page)) else { return }
        // The bar and the page are laid out on the next display frame, together, outside the
        // scroll view's callbacks: the page is never resized while the scroll handles the finger.
        barMotion = .following
        startBarLink()
    }

    /// A finger on the page: the bar's travel is this touch's own, closing from its first point
    /// and opening past the dead zone (`MobileBarCollapse.touchBegan`). A settle already playing
    /// is not stopped here, so a touch that never moves the bar cannot leave it half way; the
    /// first travel (`webPage(_:didDragBy:)`) takes it over.
    func webPageDidBeginDrag(_ page: WebPage) {
        guard page === shownPage else { return }
        barCollapse.touchBegan()
    }

    /// The page's content changed height. A page that now fits its screen has nothing behind
    /// the bar to hide, so a bar that was away comes back. A page still loading lays out empty
    /// first, so only a finished page decides (`webPage(_:didFinishLoading:)` checks then).
    func webPageDidResizeContent(_ page: WebPage) {
        guard !page.isLoading else { return }
        returnBarIfThePageFits(page)
        fitPageToBar(page)
    }

    /// A bar that is away comes back when the page on screen no longer scrolls.
    private func returnBarIfThePageFits(_ page: WebPage) {
        // Most content changes find the bar open: nothing to work out then.
        guard page === shownPage, !isSearching, !barCollapse.isOpen else { return }
        if barCollapse.contentChanged(scrolls: scrolls(page)) { snapBar(toClosed: false) }
    }

    /// The finger let go: `MobileBarCollapse.ended` picks the end (a quick flick's, else the way
    /// the bar was going), and the bar and the page's bottom edge are walked there together. A
    /// touch that had nothing to do with the bar leaves a settle already going to finish it.
    func webPageDidEndDrag(_ page: WebPage, velocity: CGFloat) {
        guard page === shownPage, !isSearching else { return stopBarLink() }
        if let closed = barCollapse.ended(velocity: velocity, collapses: collapsesBar(page), scrolls: scrolls(page),
                                          following: barIsFollowing) {
            snapBar(toClosed: closed)
        }
    }

    /// The site's Collapse Bottom Bar switch for `page`.
    private func collapsesBar(_ page: WebPage) -> Bool {
        settings.value.options(for: page.webView.url?.host).collapseBottomBar
    }

    /// The page's top always has its bar, however the page got there (a tap on the status bar
    /// scrolls a page up with no finger on it).
    func webPageDidReachTop(_ page: WebPage) {
        guard page === shownPage, !isSearching, !barCollapse.isOpen else { return }
        snapBar(toClosed: false)
    }

    /// The page below its top: the status band grows edge to edge down to its visible top.
    func webPage(_ page: WebPage, didPull pull: CGFloat) {
        guard page === shownPage, !isSearching else { return }
        let now = CACurrentMediaTime()
        if pagePull == nil {
            // A new pull starts a new deepest point and a fresh speed for the line's bump.
            pullTraceMax = 0
            pullSpeed = 0
            pullSample = nil
        } else if let sample = pullSample, now > sample.at, pull > sample.pull {
            pullSpeed = (pull - sample.pull) / (now - sample.at)
        }
        pullSample = (pull, now)
        updatePagePull(pull)
    }

    /// The finger let go: the band goes back to the status bar, and the ring eases away. A pull
    /// that reached the line lets the whole ring turn clockwise as it fades.
    func webPageDidEndPull(_ page: WebPage, full: Bool) {
        guard page === shownPage else { return }
        pullSample = nil
        pullSpeed = 0
        if full { pullArc.fulfilled() } else { pullArc.dismiss() }
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.pagePull = nil
            self.shownPage?.webView.frame.origin.y = self.webViewTop()
            self.updateStatusBand()
        }
    }

    /// A tap on the strip under the page brings the bar back, as scrolling up does.
    @objc func revealBar() {
        snapBar(toClosed: false)
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
