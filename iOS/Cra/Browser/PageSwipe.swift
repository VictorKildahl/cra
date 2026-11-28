import CraCore
import UIKit
import WebKit

/// The shadow a page casts along its left edge on the page under it (`MobilePageSwipe.shadow`).
final class PageEdgeShadow: UIView {
    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        guard let gradient = layer as? CAGradientLayer else { return }
        let width = max(1, MobilePageSwipe.shadowWidth)
        // From the page's edge, on the right, out to the left.
        gradient.startPoint = CGPoint(x: 1, y: 0.5)
        gradient.endPoint = CGPoint(x: 0, y: 0.5)
        gradient.colors = MobilePageSwipe.shadow.map { UIColor(white: 0, alpha: $0.opacity).cgColor }
        gradient.locations = MobilePageSwipe.shadow.map { NSNumber(value: Double($0.distance / width)) }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// What a swipe across the page puts on screen while it goes (`MobilePageSwipe`, as Arc Search): the page it leads
/// to beside the page on screen, and once let go, that page's picture over the live one until it has drawn.
final class PageSwipeStage: NSObject {
    let reveal: MobilePageSwipe.Reveal
    /// The page the swipe leads to, as its picture: the page Back or Forward goes to, or the tab's card.
    let arriving = UIView()
    let picture = UIImageView()
    /// A closing tab's band under the status bar, over a picture of its web view only, or the strip of a picture of
    /// the whole page, cut off it, so it can squash while the card is out (`layOutCardPicture`).
    let band = UIView()
    let stripPicture = UIImageView()
    let shadow = PageEdgeShadow()
    /// The page on screen as a picture: from the start when the tab closes (it shrinks into its card), from letting
    /// go otherwise, so the live page underneath can already go where the swipe leads.
    var leaving: UIView?
    /// A closing tab's page in two: the strip under the status bar, which squashes as it goes into its card, and the
    /// page under it.
    var leavingStrip: UIView?
    var leavingBody: UIView?
    /// Over the live page while the closing tab's cards settle: the backdrop the cards were on, so the page they
    /// lead to is not seen around the card growing into it.
    var curtain: UIView?
    /// The tab shown once the swipe lets go, when a tab closes or comes back.
    var tab: MobileTab?
    /// The tab button's front card, which a closing tab's card comes out of, and whether its slot was emptied.
    var buttonCard: CGRect = .zero
    var emptiedButton = false
    /// The live page is hidden behind the closing tab's cards.
    var hidPage = false
    /// The finger's last distance across, and the page's, which the magnet holds back at first
    /// (`MobilePageSwipe.Magnet`); the tick it gives as it lets go.
    var translation: CGFloat = 0
    var pageTranslation: CGFloat = 0
    /// When the finger last moved, so a finger held still before lifting isn't taken for a flick.
    var movedAt = CACurrentMediaTime()
    lazy var magnet = MobilePageSwipe.magnet(for: reveal)
    var lastStep: CFTimeInterval = 0
    let letGoTick = UIImpactFeedbackGenerator(style: .medium)
    /// The closing tab's cards, out while the magnet doesn't hold the page (it let go, or a quick finger took the hold
    /// off) and back in while it does, each on its own spring: the page's, and the tab's, which overshoots.
    var cards = MobilePageSwipe.Cards.page
    var tabCards = MobilePageSwipe.Cards.tab
    var progress: CGFloat { cards.progress }
    var tabProgress: CGFloat { tabCards.progress }
    /// Whether the tab's card comes out over the bar, or from behind a bar that slid away.
    var cardOverBar = true
    private var link: CADisplayLink?
    private var onFrame: ((CFTimeInterval) -> Void)?
    var animators: [UIViewPropertyAnimator] = []
    /// Let go: when the page it leads to was asked for, the page's address then and the history item Back or Forward
    /// goes to, the page whose drawing is awaited, and when it said it had drawn.
    var navigatedAt: CFTimeInterval?
    var addressAtRelease: URL?
    weak var targetItem: WKBackForwardListItem?
    weak var awaited: WebPage?
    var drawnAt: CFTimeInterval?
    var settled = false

    init(reveal: MobilePageSwipe.Reveal) {
        self.reveal = reveal
        super.init()
        arriving.isUserInteractionEnabled = false
        arriving.clipsToBounds = true
        arriving.layer.cornerCurve = .continuous
        arriving.backgroundColor = .systemBackground
        picture.contentMode = .scaleAspectFill
        picture.clipsToBounds = true
        arriving.addSubview(picture)
        band.isHidden = true
        arriving.addSubview(band)
        stripPicture.isHidden = true
        stripPicture.contentMode = .scaleToFill
        arriving.addSubview(stripPicture)
    }

    /// 1 when the swipe leads by dragging right (Back, a tab closing), -1 when it leads by dragging left (Forward).
    var direction: CGFloat { MobilePageSwipe.arrivesOnTop(reveal) ? -1 : 1 }

    /// Calls `frame` once a display frame with the time that frame goes on screen, at the display's full rate: 120 Hz
    /// on a ProMotion iPhone, where a display link left alone runs at 60 and the cards' flight looked choppy.
    func startClock(_ frame: @escaping (CFTimeInterval) -> Void) {
        stopClock()
        onFrame = frame
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stopClock() {
        link?.invalidate()
        link = nil
        onFrame = nil
    }

    @objc private func tick(_ link: CADisplayLink) { onFrame?(link.targetTimestamp) }

    func removeViews() {
        stopClock()
        animators.forEach { $0.stopAnimation(true) }
        animators = []
        for view in [arriving, shadow, leaving, curtain] { view?.removeFromSuperview() }
        leaving = nil
        leavingStrip = nil
        leavingBody = nil
        curtain = nil
    }
}

// MARK: Across the page: back, forward, and the tab itself

extension BrowserViewController {
    private var canReopenSwipedTab: Bool {
        tabArchivedBySwipe.map { id in store.archived.contains { $0.id == id } } ?? false
    }

    @objc func pageSwiped(_ pan: UIPanGestureRecognizer) {
        guard let page = shownPage else { return }
        let width = view.bounds.width
        let x = pan.translation(in: view).x
        func outcome(_ translation: CGFloat, _ velocity: CGFloat) -> MobileSwipe.Navigation {
            MobileSwipe.navigation(translation: translation, velocity: velocity, width: width, canGoBack: page.webView.canGoBack,
                                   canGoForward: page.webView.canGoForward, hasOtherTab: store.tabs.count > 1,
                                   canReopenTab: canReopenSwipedTab)
        }
        switch pan.state {
        case .began:
            // What is left of the last swipe goes first, and a cover waiting for a page to draw: the page is in hand.
            endPageSwipe()
            liftCover()
            // The page as it is: its tab's preview, and its history item's picture, which Forward shows once the
            // swipe has gone Back. Nil when the capture failed, so a closing tab never takes an older page's picture.
            pageSwipeStartPicture = capturePageSnapshot()
            if let picture = pageSwipeStartPicture { page.keepPicture(picture) }
        case .changed:
            guard let reveal = MobilePageSwipe.reveal(for: outcome(x > 0 ? width : -width, 0)) else {
                // Nowhere to go that way: the page drags its feet, over a floor of its own colour.
                endPageSwipe()
                pageContainer.transform = CGAffineTransform(translationX: x / 4, y: 0)
                if pageContainer.transform != .identity { showSwapBackdrop(for: page) }
                return
            }
            let stage = pageSwipe.flatMap { $0.reveal == reveal ? $0 : nil } ?? startPageSwipe(reveal, on: page)
            // The finger's new place and speed, on the magnet's clock as it stands: time moves on with the display's
            // frames.
            if x != stage.translation { stage.movedAt = CACurrentMediaTime() }
            stage.translation = x
            stepPageSwipe(stage, at: stage.lastStep, speed: pan.velocity(in: view).x * stage.direction)
            placePageSwipe(stage)
        case .ended, .cancelled:
            let measured = pan.velocity(in: view).x
            guard let stage = pageSwipe else { return cancelPageSwipe(velocity: measured) }
            let velocity = MobilePageSwipe.liftVelocity(measured, stillFor: CACurrentMediaTime() - stage.movedAt)
            // Once the magnet has let the page go, letting go goes there; short of that, only a flick does.
            stepPageSwipe(stage, at: stage.lastStep)
            tracePageSwipe(String(format: "lifted with the finger at %.0f moving %.0f", x * stage.direction,
                                  velocity * stage.direction))
            let goes = pan.state == .ended
                && MobilePageSwipe.commits(letGo: stage.magnet.letGo, velocity: velocity * stage.direction,
                                           distance: x * stage.direction)
            let decided = goes ? outcome(stage.direction * width, 0) : .none
            guard MobilePageSwipe.reveal(for: decided) == stage.reveal else { return cancelPageSwipe(velocity: velocity) }
            commitPageSwipe(stage, decided, velocity: velocity)
        default: break
        }
    }

    // MARK: While the finger is down

    /// Puts up what the swipe leads to beside the page: the page Back or Forward goes to, or the tab shown once this
    /// one closes, coming out of the tab button.
    private func startPageSwipe(_ reveal: MobilePageSwipe.Reveal, on page: WebPage) -> PageSwipeStage {
        // The other way's stage, when the finger has turned back past where it started, or the floor under a page
        // that dragged its feet.
        endPageSwipe()
        hideSwapBackdrop()
        let stage = PageSwipeStage(reveal: reveal)
        let bounds = view.bounds
        let list = page.webView.backForwardList
        var image: UIImage?
        switch reveal {
        case .back: image = list.backItem.flatMap(page.historyPicture(for:))
        case .forward: image = list.forwardItem.flatMap(page.historyPicture(for:))
        case .closingTab:
            stage.tab = store.tabShownAfterArchiving(page.tabID)
            image = stage.tab.flatMap { store.snapshot($0.id) }
        case .reopeningTab:
            stage.tab = tabArchivedBySwipe.flatMap { id in store.archived.first { $0.id == id } }
            image = tabArchivedBySwipePicture
        }
        stage.picture.image = image
        // A page with no picture kept shows as a canvas until it draws.
        if image == nil, let canvas = page.webView.underPageBackgroundColor { stage.arriving.backgroundColor = canvas }
        stage.arriving.bounds = bounds
        stage.arriving.center = CGPoint(x: bounds.midX, y: bounds.midY)
        stage.picture.frame = bounds
        switch reveal {
        case .back:
            view.insertSubview(stage.arriving, belowSubview: pageContainer)
            view.insertSubview(stage.shadow, belowSubview: pageContainer)
        case .forward, .reopeningTab:
            view.insertSubview(stage.shadow, aboveSubview: pageContainer)
            view.insertSubview(stage.arriving, aboveSubview: stage.shadow)
        case .closingTab:
            startClosingTab(stage, picture: image)
        }
        pageSwipe = stage
        tracePageSwipe("\(reveal) picture \(image == nil ? "none" : "kept")", restart: true)
        if reveal == .closingTab { tracePageSwipe(stage.cardOverBar ? "card over the bar" : "card behind the bar") }
        // The magnet's own clock: the page catches up with a still finger too.
        stage.letGoTick.prepare()
        stage.lastStep = CACurrentMediaTime()
        stage.startClock { [weak self, weak stage] time in
            guard let self, let stage, self.pageSwipe === stage else { return }
            self.stepPageSwipe(stage, at: time)
            self.placePageSwipe(stage)
        }
        return stage
    }

    /// Moves the magnet on to now, the finger moving at `speed` the way the swipe leads: how far the page has come
    /// behind the finger. Each time it stops holding the page it ticks; while it holds the page no more, a closing
    /// tab's cards are on their way out, and while it holds it, back in.
    private func stepPageSwipe(_ stage: PageSwipeStage, at now: CFTimeInterval, speed: CGFloat = 0) {
        let wasQuick = stage.magnet.quick, held = stage.magnet.holds
        let dt = max(0, now - stage.lastStep)
        let step = stage.magnet.step(distance: stage.translation * stage.direction, dt: dt, speed: speed)
        stage.lastStep = max(stage.lastStep, now)
        stage.pageTranslation = step.page * stage.direction
        if stage.magnet.quick, !wasQuick {
            tracePageSwipe(String(format: "quick with the finger at %.0f moving %.0f", abs(stage.translation), speed))
        }
        if step.letGoNow { tracePageSwipe(String(format: "let go with the finger at %.0f", abs(stage.translation))) }
        if held, !stage.magnet.holds {
            stage.letGoTick.impactOccurred()
            stage.letGoTick.prepare()
        } else if !held, stage.magnet.holds {
            tracePageSwipe(String(format: "held again with the finger at %.0f", abs(stage.translation)))
        }
        if stage.reveal == .closingTab {
            _ = stage.cards.step(out: !stage.magnet.holds, dt: dt)
            _ = stage.tabCards.step(out: !stage.magnet.holds, dt: dt)
        }
    }

    /// The tab closing: the page on screen, as its picture, slides with the finger; once the magnet stops holding it
    /// (at once for a quick finger) it is cut down to the bar and shrinks into a card while the tab shown next lifts
    /// off the tab button's front card and grows into one beside it, both on their own clock (`stepPageSwipe`).
    private func startClosingTab(_ stage: PageSwipeStage, picture image: UIImage?) {
        let bounds = view.bounds
        let leaving = UIView()
        leaving.isUserInteractionEnabled = false
        leaving.clipsToBounds = true
        leaving.layer.cornerCurve = .continuous
        leaving.bounds = bounds
        leaving.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let strip = view.safeAreaInsets.top
        for (part, rect) in [(\PageSwipeStage.leavingStrip, CGRect(x: 0, y: 0, width: bounds.width, height: strip)),
                             (\PageSwipeStage.leavingBody, CGRect(x: 0, y: strip, width: bounds.width, height: bounds.height - strip))] {
            guard rect.height > 0,
                  let shot = pageContainer.resizableSnapshotView(from: rect, afterScreenUpdates: false, withCapInsets: .zero)
            else { continue }
            shot.frame = rect
            leaving.addSubview(shot)
            stage[keyPath: part] = shot
        }
        view.insertSubview(leaving, aboveSubview: pageContainer)
        pageContainer.isHidden = true
        stage.hidPage = true
        stage.leaving = leaving

        stage.buttonCard = bar.tabsButton.frontCard(in: view)
        stage.arriving.layer.borderWidth = 1 / max(1, view.traitCollection.displayScale)
        stage.arriving.layer.borderColor = UIColor(white: 0, alpha: 0.12).cgColor
        // Its band under the status bar, as the tab will look on screen, and its page's own background under a
        // picture shorter than the card.
        if let tab = stage.tab {
            stage.band.backgroundColor = bandColour(for: tab)
            stage.arriving.backgroundColor = pageBackground(for: tab.id)
        }
        splitCardPicture(stage)
        // Lifted off the button, so over the bar while it is there, and from behind a bar that has slid away; the slot
        // it left is empty while it is out.
        stage.cardOverBar = MobilePageSwipe.tabCardOverBar(barCollapse: barCollapse.progress)
        if stage.cardOverBar {
            view.insertSubview(stage.arriving, aboveSubview: bar)
        } else {
            view.insertSubview(stage.arriving, belowSubview: bar)
        }
        if let tab = stage.tab, tab.id == store.tabsBehindCurrent.first?.id {
            bar.tabsButton.setFrontEmpty(true)
            stage.emptiedButton = true
        }
    }

    private func placePageSwipe(_ stage: PageSwipeStage) {
        let width = view.bounds.width
        if stage.reveal == .closingTab {
            layOutClosingTab(stage, progress: stage.progress, tab: stage.tabProgress, translation: stage.pageTranslation)
            let card = stage.arriving.frame
            let leaving = stage.leaving.map { ($0.frame.height, $0.layer.cornerRadius * $0.transform.a) } ?? (0, 0)
            let strip = (stage.leavingStrip?.frame.height ?? 0) * (stage.leaving?.transform.a ?? 1)
            tracePageSwipe(String(format: "page %.0f card %.0f %.0f %.0f %.0f finger %.0f leaving %.0f rounded %.0f strip %.0f",
                                  stage.pageTranslation, card.minX, card.minY, card.width, card.height, stage.translation,
                                  leaving.0, leaving.1, strip))
        } else {
            let edge = MobilePageSwipe.topEdge(translation: stage.pageTranslation, width: width, reveal: stage.reveal)
            layOutPageSwipe(stage, edge: edge)
            tracePageSwipe(String(format: "edge %.1f under %.1f finger %.1f", edge,
                                  MobilePageSwipe.underOffset(edge: edge, width: width), stage.translation))
        }
    }

    /// Back or Forward with the top page's left edge at `edge`; also what the spring animates to once let go.
    private func layOutPageSwipe(_ stage: PageSwipeStage, edge: CGFloat) {
        let bounds = view.bounds
        let under = MobilePageSwipe.underOffset(edge: edge, width: bounds.width)
        let page: UIView = stage.leaving ?? pageContainer
        if MobilePageSwipe.arrivesOnTop(stage.reveal) {
            stage.arriving.transform = CGAffineTransform(translationX: edge, y: 0)
            page.transform = CGAffineTransform(translationX: under, y: 0)
        } else {
            page.transform = CGAffineTransform(translationX: edge, y: 0)
            stage.arriving.transform = CGAffineTransform(translationX: under, y: 0)
        }
        let shadow = MobilePageSwipe.shadowWidth
        stage.shadow.frame = CGRect(x: edge - shadow, y: 0, width: shadow, height: bounds.height)
    }

    /// The closing tab's two cards, the page's `progress` and the tab's `tab` of the way into cards, with the finger
    /// `translation` across. Out of a bar that has slid away, the tab's card comes out of nothing.
    private func layOutClosingTab(_ stage: PageSwipeStage, progress: CGFloat, tab: CGFloat, translation: CGFloat) {
        let width = view.bounds.width, barTop = tabArea.maxY
        let place = leavingPlace(progress: progress, translation: translation)
        placeLeaving(stage, place)
        let card = MobilePageSwipe.arrivingCard(progress: tab, from: stage.buttonCard, tilt: MobileMotion.frontCardTilt,
                                                buttonCorner: 5, leavingCenterX: place.center.x, width: width,
                                                band: view.safeAreaInsets.top, barTop: barTop)
        // Bounds and centre: a frame set through the lean would not be the card's size.
        stage.arriving.transform = CGAffineTransform(rotationAngle: card.angle)
        stage.arriving.bounds = CGRect(origin: .zero, size: card.size)
        stage.arriving.center = card.center
        stage.arriving.layer.cornerRadius = card.cornerRadius
        stage.arriving.alpha = MobilePageSwipe.tabCardAlpha(progress: tab, overBar: stage.cardOverBar)
        layOutCardPicture(stage, progress: tab, strip: card.strip)
    }

    /// The closing tab's page `progress` of the way into its card with the finger `translation` across.
    private func leavingPlace(progress: CGFloat, translation: CGFloat) -> MobilePageSwipe.LeavingPage {
        let bounds = view.bounds
        return MobilePageSwipe.leavingPage(progress: progress, translation: translation, width: bounds.width,
                                           height: bounds.height, band: view.safeAreaInsets.top, barTop: tabArea.maxY,
                                           displayCorner: UIScreen.main.displayCornerRadius)
    }

    /// Puts the closing tab's page at `place`: its strip squashed to the height `place` gives it, from the top, and
    /// the page under it below the strip, as tall as it was.
    private func placeLeaving(_ stage: PageSwipeStage, _ place: MobilePageSwipe.LeavingPage) {
        guard let leaving = stage.leaving else { return }
        leaving.transform = CGAffineTransform(scaleX: place.scale, y: place.scale)
        leaving.bounds = CGRect(origin: .zero, size: place.size)
        leaving.center = place.center
        leaving.layer.cornerRadius = place.cornerRadius / max(place.scale, 0.01)
        let width = place.size.width
        if let strip = stage.leavingStrip {
            let height = strip.bounds.height
            strip.transform = CGAffineTransform(scaleX: 1, y: max(0.001, place.band / max(height, 1)))
            strip.center = CGPoint(x: width / 2, y: place.band / 2)
        }
        if let body = stage.leavingBody {
            body.center = CGPoint(x: width / 2, y: place.band + body.bounds.height / 2)
        }
    }

    /// A tab's picture is either the whole page, band and all (`capturePageSnapshot`), or its web view only, which
    /// begins under the band (`WebPage.takeSnapshot`). The whole page's is cut in two here, its strip under the status
    /// bar and the page under it; the web view's gets the tab's band over it, as the tab row draws it. Either way the
    /// card has a strip to squash away while it is out.
    private func splitCardPicture(_ stage: PageSwipeStage) {
        guard let image = stage.picture.image, let cg = image.cgImage else { return }
        let screen = view.bounds.size
        let whole = image.size.height / max(image.size.width, 1) >= screen.height / max(screen.width, 1) - 0.02
        let strip = (CGFloat(cg.height) * view.safeAreaInsets.top / max(screen.height, 1)).rounded()
        guard whole, strip > 0, strip < CGFloat(cg.height),
              let top = cg.cropping(to: CGRect(x: 0, y: 0, width: CGFloat(cg.width), height: strip)),
              let rest = cg.cropping(to: CGRect(x: 0, y: strip, width: CGFloat(cg.width), height: CGFloat(cg.height) - strip))
        else { return }
        stage.stripPicture.image = UIImage(cgImage: top, scale: image.scale, orientation: image.imageOrientation)
        stage.picture.image = UIImage(cgImage: rest, scale: image.scale, orientation: image.imageOrientation)
    }

    /// The tab's picture in its card, the whole page across, under `strip` of its strip under the status bar: its
    /// middle showing in the button's little card as the button shows it, its top at the card's top once the card is
    /// a page.
    private func layOutCardPicture(_ stage: PageSwipeStage, progress: CGFloat, strip share: CGFloat) {
        let size = stage.arriving.bounds.size, screen = view.bounds.size
        let fit = size.width / max(screen.width, 1)
        let aspect = stage.picture.image.map { $0.size.height / max($0.size.width, 1) }
            ?? (screen.height - view.safeAreaInsets.top) / max(screen.width, 1)
        let strip = view.safeAreaInsets.top * fit * min(1, max(0, share))
        let pictureHeight = size.width * aspect
        let centred = (size.height - strip - pictureHeight) / 2
        let top = centred * (1 - min(1, max(0, progress)))
        let cut = stage.stripPicture.image != nil
        stage.stripPicture.isHidden = !cut
        stage.band.isHidden = cut || stage.band.backgroundColor == nil
        for view in [stage.band, stage.stripPicture] { view.frame = CGRect(x: 0, y: top, width: size.width, height: strip) }
        stage.picture.frame = CGRect(x: 0, y: top + strip, width: size.width, height: pictureHeight)
    }

    // MARK: Letting go

    /// Let go far enough: the live page goes where the swipe leads at once, under the picture of where it goes and
    /// the picture of the page it leaves, which settle on a spring from the finger's speed.
    private func commitPageSwipe(_ stage: PageSwipeStage, _ navigation: MobileSwipe.Navigation, velocity: CGFloat) {
        guard let page = shownPage else { return endPageSwipe() }
        stage.stopClock()
        if stage.reveal != .closingTab {
            // The page on screen as it is, in its place, so the live page can go on underneath.
            let leaving = pageContainer.snapshotView(afterScreenUpdates: false) ?? UIView()
            leaving.isUserInteractionEnabled = false
            leaving.bounds = pageContainer.bounds
            leaving.center = pageContainer.center
            leaving.transform = pageContainer.transform
            if MobilePageSwipe.arrivesOnTop(stage.reveal) {
                view.insertSubview(leaving, belowSubview: stage.shadow)
            } else {
                view.insertSubview(leaving, aboveSubview: pageContainer)
                view.insertSubview(pageContainer, belowSubview: stage.arriving)
            }
            stage.leaving = leaving
            pageContainer.transform = .identity
        }

        // The motion first, handed to the render server now: going where the swipe leads below can hold the main
        // thread for a frame or more (a tab's page put on screen, its history saved), and the release stuttered on it.
        if stage.reveal == .closingTab {
            settleClosingTab(stage, velocity: velocity)
        } else {
            let width = view.bounds.width
            let edge = MobilePageSwipe.topEdge(translation: stage.pageTranslation, width: width, reveal: stage.reveal)
            let target: CGFloat = MobilePageSwipe.arrivesOnTop(stage.reveal) ? 0 : width
            let speed = MobilePageSwipe.initialVelocity(velocity: velocity, from: edge, to: target)
            animatePageSwipe(stage, spring: MobilePageSwipe.settle, velocity: speed, {
                self.layOutPageSwipe(stage, edge: target)
            }, completion: { [weak self, weak stage] in
                guard let self, let stage, self.pageSwipe === stage else { return }
                stage.settled = true
                stage.leaving?.removeFromSuperview()
                stage.leaving = nil
                stage.shadow.removeFromSuperview()
                self.liftPageSwipePictureIfDue()
            })
        }
        CATransaction.flush()
        stage.addressAtRelease = page.webView.url
        switch stage.reveal {
        case .back: stage.targetItem = page.webView.backForwardList.backItem
        case .forward: stage.targetItem = page.webView.backForwardList.forwardItem
        case .closingTab, .reopeningTab: break
        }
        stage.navigatedAt = CACurrentMediaTime()
        DispatchQueue.main.async { [weak self, weak stage, weak page] in
            guard let self, let stage, let page, self.pageSwipe === stage, self.shownPage === page else { return }
            self.go(navigation, from: page, stage: stage)
        }
    }

    /// Takes the live page where the swipe leads, under the pictures settling over it.
    private func go(_ navigation: MobileSwipe.Navigation, from page: WebPage, stage: PageSwipeStage) {
        switch navigation {
        case .back: page.webView.goBack()
        case .forward: page.webView.goForward()
        case .archiveTab:
            let id = page.tabID
            tabArchivedBySwipePicture = pageSwipeStartPicture
            page.webView.removeFromSuperview()
            page.delegate = nil
            shownPage = nil
            store.archive(id)
            tabArchivedBySwipe = id
            // The card is the page now: the button shows the tabs behind it again.
            if stage.emptiedButton { bar.tabsButton.setFrontEmpty(false) }
            stage.emptiedButton = false
            // The live page goes on underneath at once, so it can draw while the cards settle, behind the backdrop
            // the cards are on.
            let curtain = backdrop.snapshotView(afterScreenUpdates: false) ?? UIView()
            curtain.frame = view.bounds
            curtain.backgroundColor = view.backgroundColor
            curtain.isUserInteractionEnabled = false
            if let leaving = stage.leaving {
                view.insertSubview(curtain, belowSubview: leaving)
            } else {
                view.insertSubview(curtain, belowSubview: stage.arriving)
            }
            stage.curtain = curtain
            if let tab = store.selected { show(tab) }
            refreshTabStack()
            pageContainer.isHidden = false
            stage.hidPage = false
        case .reopenTab:
            if let id = tabArchivedBySwipe {
                store.restore(id)
                tabArchivedBySwipe = nil
                tabArchivedBySwipePicture = nil
                if let tab = store.selected { show(tab) }
                refreshTabStack()
            }
        case .none: break
        }
        watchPageSwipeDrawn(stage)
        tracePageSwipe("went \(stage.reveal)")
        // Settled already, it comes off as soon as the page has drawn.
        liftPageSwipePictureIfDue()
    }

    /// The closing tab let go: its card springs off to the right, still a card, while the tab shown next grows from
    /// its card to the whole screen under the bar, over its live page until that has drawn.
    private func settleClosingTab(_ stage: PageSwipeStage, velocity: CGFloat) {
        guard let leaving = stage.leaving else { return }
        let bounds = view.bounds, width = bounds.width
        view.insertSubview(stage.arriving, belowSubview: bar)
        let goneX = MobilePageSwipe.leavingCardGoneX(width: width)
        let speed = MobilePageSwipe.initialVelocity(velocity: velocity, from: leaving.center.x, to: goneX)
        // A card by now, even when a quick release comes before the cards are all the way out, shrinking a little
        // further on its way off.
        var gone = leavingPlace(progress: 1, translation: 0)
        gone.scale = MobilePageSwipe.cardLeaveScale
        gone.center.x = goneX
        animatePageSwipe(stage, spring: MobilePageSwipe.cardLeave, velocity: speed, {
            self.placeLeaving(stage, gone)
        }, completion: { [weak stage] in
            stage?.leaving?.removeFromSuperview()
            stage?.leaving = nil
        })
        let display = UIScreen.main.displayCornerRadius
        animatePageSwipe(stage, spring: MobilePageSwipe.cardArrive, velocity: 0, {
            stage.arriving.transform = .identity
            stage.arriving.bounds = CGRect(origin: .zero, size: bounds.size)
            stage.arriving.center = CGPoint(x: bounds.midX, y: bounds.midY)
            stage.arriving.layer.cornerRadius = display
            stage.arriving.alpha = 1
            // Made the page, its strip under the status bar comes back.
            self.layOutCardPicture(stage, progress: 1, strip: 1)
        }, completion: { [weak self, weak stage] in
            guard let self, let stage, self.pageSwipe === stage else { return }
            stage.settled = true
            stage.arriving.layer.cornerRadius = 0
            stage.arriving.layer.borderWidth = 0
            self.liftPageSwipePictureIfDue()
        })
    }

    /// Short of going anywhere: everything goes back where it was.
    private func cancelPageSwipe(velocity: CGFloat) {
        guard let stage = pageSwipe else {
            // The page dragged its feet: back into place.
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: []) {
                self.pageContainer.transform = .identity
            } completion: { _ in
                self.hideSwapBackdrop()
            }
            return
        }
        tracePageSwipe("went nowhere")
        stage.stopClock()
        let finish = { [weak self, weak stage] in
            guard let self, let stage, self.pageSwipe === stage else { return }
            self.tracePageSwipe("back in place")
            self.endPageSwipe()
        }
        if stage.reveal == .closingTab {
            // Back the way they came, a frame at a time: the tab's card down the screen's edge into the button along the
            // path it came up, the page's card back to the page. A spring between the two layouts would take the card
            // there in a straight line.
            let progress = stage.progress, tab = stage.tabProgress, translation = stage.pageTranslation
            let start = CACurrentMediaTime()
            stage.startClock { [weak self, weak stage] time in
                guard let self, let stage, self.pageSwipe === stage else { return }
                let back = MobilePageSwipe.cardsReturn(after: time - start)
                let left = back.home ? 0 : 1 - back.share
                self.layOutClosingTab(stage, progress: progress * left, tab: tab * left, translation: translation * left)
                let card = stage.arriving.frame
                self.tracePageSwipe(String(format: "down %.3f card %.1f %.1f %.1f %.1f page %.1f", tab * left,
                                           card.minX, card.minY, card.width, card.height, translation * left))
                if back.home {
                    stage.stopClock()
                    finish()
                }
            }
            return
        }
        let width = view.bounds.width
        let edge = MobilePageSwipe.topEdge(translation: stage.pageTranslation, width: width, reveal: stage.reveal)
        let rest: CGFloat = MobilePageSwipe.arrivesOnTop(stage.reveal) ? width : 0
        let speed = MobilePageSwipe.initialVelocity(velocity: velocity, from: edge, to: rest)
        animatePageSwipe(stage, spring: MobilePageSwipe.settle, velocity: speed, {
            self.layOutPageSwipe(stage, edge: rest)
        }, completion: finish)
    }

    private func animatePageSwipe(_ stage: PageSwipeStage, spring: MobileMotion.Spring, velocity: CGFloat,
                                  _ animations: @escaping () -> Void, completion: @escaping () -> Void) {
        let timing = UISpringTimingParameters(mass: 1, stiffness: spring.stiffness, damping: spring.damping,
                                              initialVelocity: CGVector(dx: velocity, dy: velocity))
        let animator = UIViewPropertyAnimator(duration: 0, timingParameters: timing)
        animator.addAnimations(animations)
        animator.addCompletion { _ in completion() }
        stage.animators.append(animator)
        animator.startAnimation()
    }

    // MARK: The picture over the page it went to

    /// Notes when the page the swipe went to has drawn, and checks again at the times its picture may come off.
    private func watchPageSwipeDrawn(_ stage: PageSwipeStage) {
        guard let page = shownPage else { return }
        stage.awaited = page
        let drawn = { [weak self, weak stage, weak page] in
            guard let self, let stage, self.pageSwipe === stage, stage.drawnAt == nil else { return }
            // Going Back or Forward, the page being left may still say it has drawn, if it was loading: only the
            // page gone to counts, once the address or the history item has moved to it (two entries can share an
            // address, a page's own pushState).
            if stage.reveal == .back || stage.reveal == .forward, let page, !self.reachedTarget(stage, page) { return }
            stage.drawnAt = CACurrentMediaTime()
            DispatchQueue.main.asyncAfter(deadline: .now() + MobilePageSwipe.drawnSettle + 0.01) { [weak self] in
                self?.liftPageSwipePictureIfDue()
            }
        }
        page.onDrawn = { drawn() }
        if stage.reveal == .closingTab || stage.reveal == .reopeningTab, page.webView.url != nil, !page.webView.isLoading {
            // A tab whose page was there already only has to put it on screen.
            DispatchQueue.main.asyncAfter(deadline: .now() + MobileMotion.pageDrawDelay) { drawn() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MobilePageSwipe.longestHold + 0.01) { [weak self] in
            self?.liftPageSwipePictureIfDue()
        }
    }

    /// Whether Back or Forward has reached the page it went to: its address has moved, or the history's current entry
    /// is the one it went to.
    private func reachedTarget(_ stage: PageSwipeStage, _ page: WebPage) -> Bool {
        if page.webView.url != stage.addressAtRelease { return true }
        guard let target = stage.targetItem else { return false }
        return page.webView.backForwardList.currentItem === target
    }

    /// Takes the arriving page's picture off the live page once the pages have settled and the page has drawn.
    func liftPageSwipePictureIfDue() {
        guard let stage = pageSwipe, let navigatedAt = stage.navigatedAt else { return }
        let now = CACurrentMediaTime()
        // Back within one document draws no new page: once it has moved to the entry and nothing loads, it is there.
        if stage.drawnAt == nil, stage.reveal == .back || stage.reveal == .forward, let page = shownPage,
           reachedTarget(stage, page), !page.webView.isLoading {
            stage.drawnAt = now - MobilePageSwipe.drawnSettle
        }
        guard MobilePageSwipe.liftsPicture(settled: stage.settled, sinceNavigated: now - navigatedAt,
                                           sinceDrawn: stage.drawnAt.map { now - $0 }) else {
            if stage.settled, stage.drawnAt == nil {
                // No word from the page yet: look again shortly.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.liftPageSwipePictureIfDue() }
            }
            return
        }
        tracePageSwipe(String(format: "lifted after %.0f ms", (now - navigatedAt) * 1000))
        endPageSwipe()
    }

    /// Takes everything of the swipe off the screen and gives the page back its place.
    func endPageSwipe() {
        guard let stage = pageSwipe else { return }
        pageSwipe = nil
        stage.removeViews()
        if let page = stage.awaited, coveredPage?.page !== page { page.onDrawn = nil }
        if stage.hidPage { pageContainer.isHidden = false }
        if stage.emptiedButton { bar.tabsButton.setFrontEmpty(false) }
        // Still in the hand, the page is put back in place. Once let go it is in place already, under the pictures,
        // and what has the page since (the search sheet's push-back) keeps it.
        if stage.navigatedAt == nil { pageContainer.transform = .identity }
    }

    /// For UI tests (`-CraTracePageSwipe YES`): what the last swipe across the page showed, a line a frame.
    private func tracePageSwipe(_ line: String, restart: Bool = false) {
        guard pageSwipeTraceView.superview != nil else { return }
        let lines = restart ? [] : (pageSwipeTraceView.accessibilityValue ?? "").split(separator: "\n").map(String.init)
        pageSwipeTraceView.accessibilityValue = (lines + [line]).suffix(400).joined(separator: "\n")
    }
}

extension UIScreen {
    /// The display's own corner radius, for a card that grows to fill it. There is no public
    /// number for it; 47 pt is close to every phone with rounded corners, 0 fits the rest.
    var displayCornerRadius: CGFloat {
        let insets = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets }.first
        return (insets?.bottom ?? 0) > 0 ? 47 : 0
    }
}
