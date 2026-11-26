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
    let shadow = PageEdgeShadow()
    /// The page on screen as a picture: from the start when the tab closes (it shrinks into its card), from letting
    /// go otherwise, so the live page underneath can already go where the swipe leads.
    var leaving: UIView?
    /// Over the live page while the closing tab's cards settle: the backdrop the cards were on, so the page they
    /// lead to is not seen around the card growing into it.
    var curtain: UIView?
    /// The tab shown once the swipe lets go, when a tab closes or comes back.
    var tab: MobileTab?
    /// The tab button's front card, which a closing tab's card comes out of, and whether its slot was emptied.
    var buttonCard: CGRect = .zero
    /// How far down its document the page Back or Forward goes to was when it was left.
    var arrivingScrollTop: CGFloat?
    var emptiedButton = false
    /// The live page is hidden behind the closing tab's cards.
    var hidPage = false
    /// The finger's last distance across, and the page's, which the magnet holds back at first
    /// (`MobilePageSwipe.Magnet`); the tick it gives as it lets go.
    var translation: CGFloat = 0
    var pageTranslation: CGFloat = 0
    lazy var magnet = MobilePageSwipe.magnet(for: reveal)
    var lastStep: CFTimeInterval = 0
    let letGoTick = UIImpactFeedbackGenerator(style: .medium)
    /// The closing tab's cards' own clock: from the moment the magnet lets go.
    var cardsAt: CFTimeInterval?
    var progress: CGFloat = 0
    private var link: CADisplayLink?
    private var onFrame: ((CFTimeInterval) -> Void)?
    var animators: [UIViewPropertyAnimator] = []
    /// Let go: when the page it leads to was asked for, the page's address then, the page whose drawing is awaited,
    /// and when it said it had drawn.
    var navigatedAt: CFTimeInterval?
    var addressAtRelease: URL?
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
            // The finger's new place, on the magnet's clock as it stands: time moves on with the display's frames.
            stage.translation = x
            stepPageSwipe(stage, at: stage.lastStep)
            placePageSwipe(stage)
        case .ended, .cancelled:
            let velocity = pan.velocity(in: view).x
            guard let stage = pageSwipe else { return cancelPageSwipe(velocity: velocity) }
            // Once the magnet has let the page go, letting go goes there; held, only a flick does.
            stepPageSwipe(stage, at: stage.lastStep)
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
        case .back:
            image = list.backItem.flatMap(page.historyPicture(for:))
            stage.arrivingScrollTop = list.backItem.flatMap(page.historyScrollTop(for:))
        case .forward:
            image = list.forwardItem.flatMap(page.historyPicture(for:))
            stage.arrivingScrollTop = list.forwardItem.flatMap(page.historyScrollTop(for:))
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

    /// Moves the magnet on to now: how far the page has come behind the finger. As it lets the page go it ticks, and
    /// a closing tab's cards set off.
    private func stepPageSwipe(_ stage: PageSwipeStage, at now: CFTimeInterval) {
        let step = stage.magnet.step(distance: stage.translation * stage.direction, dt: max(0, now - stage.lastStep))
        stage.lastStep = max(stage.lastStep, now)
        stage.pageTranslation = step.page * stage.direction
        if step.letGoNow {
            stage.letGoTick.impactOccurred()
            if stage.reveal == .closingTab, stage.cardsAt == nil { stage.cardsAt = now }
            tracePageSwipe(String(format: "let go with the finger at %.0f", abs(stage.translation)))
        }
        if let at = stage.cardsAt { stage.progress = MobilePageSwipe.cardProgress(after: now - at) }
    }

    /// The tab closing: the page on screen, as its picture down to the bar, slides with the finger; once the magnet
    /// lets it go it shrinks into a card while the tab shown next lifts off the tab button's front card and grows into
    /// one beside it, both on their own clock (`stepPageSwipe`).
    private func startClosingTab(_ stage: PageSwipeStage, picture image: UIImage?) {
        let bounds = view.bounds, barTop = tabArea.maxY
        let leaving = UIView()
        leaving.isUserInteractionEnabled = false
        leaving.clipsToBounds = true
        leaving.layer.cornerCurve = .continuous
        leaving.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: barTop)
        leaving.center = CGPoint(x: bounds.midX, y: barTop / 2)
        if let shot = pageContainer.snapshotView(afterScreenUpdates: false) {
            shot.frame = bounds
            leaving.addSubview(shot)
        }
        view.insertSubview(leaving, aboveSubview: pageContainer)
        pageContainer.isHidden = true
        stage.hidPage = true
        stage.leaving = leaving

        stage.buttonCard = bar.tabsButton.frontCard(in: view)
        stage.arriving.layer.borderWidth = 1 / max(1, view.traitCollection.displayScale)
        stage.arriving.layer.borderColor = UIColor(white: 0, alpha: 0.12).cgColor
        // Its band under the status bar, as the tab will look on screen, scaled with the picture.
        if let tab = stage.tab, let colour = bandColour(for: tab) {
            let band = UIView()
            band.backgroundColor = colour
            band.frame = CGRect(x: 0, y: 0, width: bounds.width, height: view.safeAreaInsets.top)
            band.autoresizingMask = [.flexibleWidth, .flexibleHeight, .flexibleBottomMargin]
            stage.picture.addSubview(band)
        }
        // Lifted off the button, so over the bar while it is there; the slot it left is empty while it is out.
        view.insertSubview(stage.arriving, aboveSubview: bar)
        if let tab = stage.tab, tab.id == store.tabsBehindCurrent.first?.id {
            bar.tabsButton.setFrontEmpty(true)
            stage.emptiedButton = true
        }
    }

    private func placePageSwipe(_ stage: PageSwipeStage) {
        let width = view.bounds.width
        if stage.reveal == .closingTab {
            layOutClosingTab(stage, progress: stage.progress, translation: stage.pageTranslation)
            let card = stage.arriving.frame
            tracePageSwipe(String(format: "page %.0f card %.0f %.0f %.0f %.0f finger %.0f", stage.pageTranslation, card.minX,
                                  card.minY, card.width, card.height, stage.translation))
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

    /// The closing tab's two cards, `progress` of the way into cards with the finger `translation` across.
    private func layOutClosingTab(_ stage: PageSwipeStage, progress: CGFloat, translation: CGFloat) {
        guard let leaving = stage.leaving else { return }
        let width = view.bounds.width, barTop = tabArea.maxY
        let place = MobilePageSwipe.leavingPage(progress: progress, translation: translation, width: width, barTop: barTop)
        leaving.transform = CGAffineTransform(scaleX: place.scale, y: place.scale)
        leaving.center = place.center
        leaving.layer.cornerRadius = MobilePageSwipe.cardCornerRadius / max(place.scale, 0.01)
        let card = MobilePageSwipe.arrivingCard(progress: progress, from: stage.buttonCard, tilt: MobileMotion.frontCardTilt,
                                                buttonCorner: 5, leavingCenterX: place.center.x, width: width, barTop: barTop)
        // Bounds and centre: a frame set through the lean would not be the card's size.
        stage.arriving.transform = CGAffineTransform(rotationAngle: card.angle)
        stage.arriving.bounds = CGRect(origin: .zero, size: card.size)
        stage.arriving.center = card.center
        stage.arriving.layer.cornerRadius = card.cornerRadius
        layOutCardPicture(stage, progress: progress)
    }

    /// The tab's picture in its card: the whole page across, its middle showing in the button's little card as the
    /// button shows it, its top at the card's top once the card is a page.
    private func layOutCardPicture(_ stage: PageSwipeStage, progress: CGFloat) {
        let size = stage.arriving.bounds.size, screen = view.bounds.size
        let height = size.width * screen.height / max(screen.width, 1)
        let centred = (size.height - height) / 2
        stage.picture.frame = CGRect(x: 0, y: centred * (1 - min(1, max(0, progress))), width: size.width, height: height)
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
        let bounds = view.bounds, width = bounds.width, barTop = tabArea.maxY
        view.insertSubview(stage.arriving, belowSubview: bar)
        let card = MobilePageSwipe.cardFrame(width: width, barTop: barTop)
        let goneX = MobilePageSwipe.leavingCardGoneX(width: width)
        let speed = MobilePageSwipe.initialVelocity(velocity: velocity, from: leaving.center.x, to: goneX)
        animatePageSwipe(stage, spring: MobilePageSwipe.cardLeave, velocity: speed, {
            let scale = MobilePageSwipe.cardLeaveScale
            leaving.transform = CGAffineTransform(scaleX: scale, y: scale)
            leaving.center = CGPoint(x: goneX, y: card.midY)
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
            self.layOutCardPicture(stage, progress: 1)
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
            self.endPageSwipe()
        }
        if stage.reveal == .closingTab {
            // The card goes back into the button and the page back to its place, as the flick's does.
            animatePageSwipe(stage, spring: MobileMotion.tabOpen, velocity: 0, {
                self.layOutClosingTab(stage, progress: 0, translation: 0)
            }, completion: finish)
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
            // page gone to counts, once the address has moved to it.
            if stage.reveal == .back || stage.reveal == .forward, page?.webView.url == stage.addressAtRelease { return }
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

    /// Takes the arriving page's picture off the live page once the pages have settled and the page has drawn.
    func liftPageSwipePictureIfDue() {
        guard let stage = pageSwipe, let navigatedAt = stage.navigatedAt else { return }
        let now = CACurrentMediaTime()
        // Back within one document draws no new page: once the address has moved and nothing loads, it is there.
        if stage.drawnAt == nil, stage.reveal == .back || stage.reveal == .forward, let page = shownPage,
           page.webView.url != stage.addressAtRelease, !page.webView.isLoading {
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
        putBackScroll(stage)
        tracePageSwipe(String(format: "lifted after %.0f ms", (now - navigatedAt) * 1000))
        endPageSwipe()
    }

    /// WebKit puts the page Back or Forward went to back without the insets the app sets itself
    /// (`updatePageInsets`), a status bar higher than it was left: under its picture, it goes back where the picture
    /// shows it, so nothing jumps as the picture comes off.
    private func putBackScroll(_ stage: PageSwipeStage) {
        guard let top = stage.arrivingScrollTop, let scroll = shownPage?.webView.scrollView else { return }
        let offset = MobilePageSwipe.restoredOffset(scrollTop: top, insetTop: scroll.contentInset.top,
                                                    insetBottom: scroll.contentInset.bottom,
                                                    contentHeight: scroll.contentSize.height, viewHeight: scroll.bounds.height)
        guard abs(scroll.contentOffset.y - offset) > 1 else { return }
        tracePageSwipe(String(format: "scroll put back from %.0f to %.0f", scroll.contentOffset.y, offset))
        scroll.contentOffset.y = offset
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
