import CraCore
import UIKit

protocol TabSwitcherDelegate: AnyObject {
    /// A finger came down on `id`'s card: it may be picked when the finger lifts.
    func tabSwitcher(_ switcher: TabSwitcherView, mayPick id: UUID)
    func tabSwitcher(_ switcher: TabSwitcherView, didSelect id: UUID)
    func tabSwitcher(_ switcher: TabSwitcherView, didClose id: UUID)
    /// A tap on the row's background, away from the cards.
    func tabSwitcherDidTapOutside(_ switcher: TabSwitcherView)
}

/// The tab switcher: every open tab as a card in one row (`MobileTabCarousel` places them).
/// Drag sideways to move along the row, tap a card to open it, throw one upwards to close it.
/// `expansion` runs from 0 (the row) to 1 (the card in focus fills the screen), which is how the
/// switcher grows out of a page and back into one.
final class TabSwitcherView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: TabSwitcherDelegate?

    private let background = CAGradientLayer()
    /// The cards in order, and which are flying off (`MobileTabRow`).
    private var row = MobileTabRow(cards: [])
    private var views: [UUID: TabCardView] = [:]
    private var cards: [TabCardView] { row.cards.compactMap { views[$0] } }
    /// The strip between the page's bottom and the screen's edge (the bar's own band), in the
    /// page's own colour while a card fills the screen: the bar's material must not show the row's
    /// backdrop there mid-transition.
    private let bottomFill = UIView()
    private(set) var position: CGFloat = 0
    private var dragStart: CGFloat = 0
    private var draggedCard: TabCardView?
    private var draggedOffset: CGFloat = 0
    /// The row coming to rest after a drag, one `position` a frame, so every frame is the
    /// row's own layout and a finger can catch it on the way.
    private var settle: MobileTabCarousel.Settle?
    private var settleStart: CFTimeInterval = 0
    private var settleLink: CADisplayLink?
    /// The card the row was settling on when a card was taken up from it.
    private var heldTarget: UUID?
    private let pan = UIPanGestureRecognizer()
    /// Whether the row is under a finger or settling.
    private var rowMoves: Bool { settle != nil || (draggedCard == nil && [.began, .changed].contains(pan.state)) }

    private var sideInsets: (left: CGFloat, right: CGFloat) {
        // On the open iPhone Duo the row is laid out as on the widest iPhone, in the middle (#866).
        let screen = MobileScreenClass.of(size: bounds.size, isPad: traitCollection.userInterfaceIdiom == .pad)
        return screen.carouselInsets(size: bounds.size, insets: MobileSideInsets.applied(size: bounds.size, safeLeft: safeAreaInsets.left, safeRight: safeAreaInsets.right))
    }
    var expansion: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// The card that fills the screen at `expansion` 1.
    var expandedID: UUID?
    /// The status band's height at full size: each card's own band is that, scaled with the card.
    var bandHeight: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// The page's view bottom at full size: the safe area's edge under the bar (the bar's top
    /// before iOS 26). A card that fills the screen stops there, under the bar too, so the page it
    /// becomes is exactly where the card was.
    var pageBottom: CGFloat? { didSet { setNeedsLayout() } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        background.startPoint = CGPoint(x: 0, y: 0)
        background.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(background)
        bottomFill.isUserInteractionEnabled = false
        bottomFill.alpha = 0
        addSubview(bottomFill)
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TabSwitcherView, _) in view.applyColors() }

        pan.addTarget(self, action: #selector(panned(_:)))
        pan.delegate = self
        addGestureRecognizer(pan)
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped(_:))))
        accessibilityIdentifier = "tab-switcher"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func applyColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Dark: Victor's screenshots IMG_1896 and IMG_1905 (13 Nov), #1C1B2F at the top, #1F1F30 low down.
        background.colors = dark ? [Palette.rgb(0x1c1b2f).cgColor, Palette.rgb(0x1f1f30).cgColor]
                                 : [Palette.rgb(0xefeefd).cgColor, Palette.rgb(0xf8eefb).cgColor]
        CATransaction.commit()
    }

    // MARK: Content

    var focusedIndex: Int { min(max(0, Int(position.rounded())), max(0, cards.count - 1)) }
    var focusedID: UUID? { cards.indices.contains(focusedIndex) ? cards[focusedIndex].tabID : nil }
    var isEmpty: Bool { cards.isEmpty }

    /// Shows `tabs`, oldest first, focused on `focus`.
    func setTabs(_ tabs: [MobileTab], focus: UUID?, snapshot: (UUID) -> UIImage?, favicon: (MobileTab) -> UIImage?,
                 band: (MobileTab) -> UIColor?) {
        stopSettling()
        views.values.forEach { $0.removeFromSuperview() }
        views = [:]
        for (index, tab) in tabs.enumerated() {
            let card = TabCardView(tabID: tab.id)
            card.configure(title: tab.displayTitle, snapshot: snapshot(tab.id), favicon: favicon(tab),
                           incognito: tab.isIncognito, band: band(tab))
            card.accessibilityIdentifier = "tab-card-\(index)"
            addSubview(card)
            views[tab.id] = card
        }
        row = MobileTabRow(cards: tabs.map(\.id))
        position = CGFloat(tabs.firstIndex { $0.id == focus } ?? max(0, tabs.count - 1))
        setNeedsLayout()
    }

    /// Grows `id`'s card with the live page (`LivePageCard`): the page's container, above the
    /// row, takes the card's place and shape. The cards that lie over this one in the row move to
    /// `front`, a layer above the page, after the card's own overlay; they are still laid out here.
    func growLive(_ live: LivePageCard, for id: UUID, front: UIView) {
        guard let card = views[id], let index = cards.firstIndex(where: { $0 === card }) else { return }
        card.live = live
        live.overlayPicture.image = card.pictureImage
        front.addSubview(live.overlay)
        for later in cards[(index + 1)...] { front.addSubview(later) }
        setNeedsLayout()
    }

    /// Where `id`'s card is on screen now.
    func cardFrame(for id: UUID) -> CGRect? { views[id]?.cardFrame }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.frame = bounds
        CATransaction.commit()
        layoutCards()
        let bottom = pageBottom ?? bounds.height
        bottomFill.frame = CGRect(x: 0, y: bottom, width: bounds.width, height: max(0, bounds.height - bottom))
    }

    /// The strip below the page takes `colour` while a card fills the screen; hidden (`alpha` 0)
    /// with the row, so the bar's own slab and this strip come and go together.
    func setBottomFill(_ colour: UIColor?, alpha: CGFloat) {
        bottomFill.backgroundColor = colour
        bottomFill.alpha = alpha
    }

    /// For the tab row's UI test: whether the strip below the page shows, or is on its way to.
    var bottomFillShows: Bool { bottomFill.alpha > 0 }

    private func layoutCards() {
        let screen = bounds.size
        guard screen.width > 0 else { return }
        let bottom = pageBottom ?? screen.height
        let expandedIndex = cards.firstIndex { $0.tabID == expandedID }
        let centring = MobileTabCarousel.endCentring(position: position, count: cards.count)
        var frames: [(frame: CGRect, placement: MobileTabCarousel.Placement)] = []
        var fills: [CGFloat] = []
        for (index, card) in cards.enumerated() {
            let relative = CGFloat(index) - position
            let placement = MobileTabCarousel.placement(relative: relative, in: screen, sideInsets: sideInsets,
                                                        alone: cards.count == 1, centring: centring)
            var frame = placement.frame
            frame = frame.insetBy(dx: frame.width * (1 - placement.scale) / 2, dy: frame.height * (1 - placement.scale) / 2)
            if row.isThrown(card.tabID) {
                frame.origin.y -= screen.height
            } else if card === draggedCard {
                frame.origin.y += draggedOffset
            }
            var fill: CGFloat = 0
            if let expandedIndex, expansion > 0 {
                if index == expandedIndex {
                    fill = expansion
                } else {
                    // The others make way: off to their own side.
                    frame.origin.x += (index < expandedIndex ? -1 : 1) * expansion * screen.width * 0.7
                }
            }
            frames.append((frame, placement))
            fills.append(fill)
        }
        for (index, card) in cards.enumerated() {
            let (frame, placement) = frames[index]
            // The card in front covers this one's right part: the title stops before it (#816).
            let next = index + 1 < cards.count && !row.isThrown(cards[index + 1].tabID) ? frames[index + 1].frame.minX : nil
            card.layout(frame: frame, screen: screen, bottom: bottom, bandHeight: bandHeight, fill: fills[index],
                        dim: placement.dim * (1 - expansion), headerAlpha: 1 - min(1, expansion * 2),
                        titleAlpha: MobileTabCarousel.titleAlpha(relative: CGFloat(index) - position),
                        nextCardLeft: next, scale: placement.scale, moving: rowMoves)
        }
    }

    // MARK: Gestures

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard isUserInteractionEnabled, let touch = touches.first, let card = card(at: touch.location(in: self)) else { return }
        delegate?.tabSwitcher(self, mayPick: card.tabID)
    }

    private func card(at point: CGPoint) -> TabCardView? {
        // Newer cards are on top. One flying off is out of reach.
        cards.reversed().first { row.canTake($0.tabID) && ($0.cardFrame.contains(point) || $0.headerFrame.contains(point)) }
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        guard let card = card(at: tap.location(in: self)) else {
            delegate?.tabSwitcherDidTapOutside(self)
            return
        }
        delegate?.tabSwitcher(self, didSelect: card.tabID)
    }

    override func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard let pan = gesture as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: self)
        if abs(velocity.y) > abs(velocity.x) {
            // A vertical drag takes hold of the card under the finger, and only upwards.
            draggedCard = velocity.y < 0 ? card(at: pan.location(in: self)) : nil
            return draggedCard != nil
        }
        draggedCard = nil
        return true
    }

    @objc private func panned(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: self), velocity = pan.velocity(in: self)
        if let card = draggedCard {
            switch pan.state {
            case .began:
                // The row holds still under a card being taken up, and settles on where it was
                // going once the card is let go.
                heldTarget = settle.flatMap { cards.indices.contains(Int($0.target)) ? cards[Int($0.target)].tabID : nil }
                stopSettling()
            case .changed:
                draggedOffset = min(0, translation.y)
                layoutCards()
            case .ended, .cancelled:
                let closes = pan.state == .ended && MobileTabCarousel.closes(translation: translation.y, velocity: velocity.y)
                // The finger lets go of the card now, not when it lands: the next flick can come
                // before that.
                draggedCard = nil
                draggedOffset = 0
                if let target = heldTarget { startSettling(to: row.resumeIndex(heading: target, position: position), velocity: 0) }
                heldTarget = nil
                if closes, row.startThrow(card.tabID) { throwAway(card) } else { settleCards() }
            default: break
            }
            return
        }
        switch pan.state {
        case .began:
            // A row still settling is caught where it is.
            stopSettling()
            dragStart = MobileTabCarousel.dragStart(caughtAt: position, count: cards.count)
        case .changed:
            position = MobileTabCarousel.position(start: dragStart, translation: translation.x, count: cards.count, in: bounds.size, sideInsets: sideInsets)
            layoutCards()
        case .ended, .cancelled:
            let target = MobileTabCarousel.restingIndex(position: position, velocity: velocity.x, start: dragStart, count: cards.count, in: bounds.size, sideInsets: sideInsets)
            let speed = MobileTabCarousel.velocity(velocity.x, at: position, count: cards.count, in: bounds.size, sideInsets: sideInsets)
            startSettling(to: target, velocity: speed)
        default: break
        }
    }

    /// Lets the row come to rest on card `target`, moving `velocity` cards a second as it starts.
    private func startSettling(to target: Int, velocity: CGFloat) {
        settle = MobileTabCarousel.Settle(from: position, velocity: velocity, target: CGFloat(target))
        settleStart = CACurrentMediaTime()
        guard settleLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(settleStep(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        settleLink = link
    }

    @objc private func settleStep(_ link: CADisplayLink) {
        guard let settle else { return stopSettling() }
        let time = link.targetTimestamp - settleStart
        if settle.isDone(after: time) {
            position = settle.target
            stopSettling()
        } else {
            position = settle.position(after: time)
        }
        layoutCards()
    }

    private func stopSettling() {
        settleLink?.invalidate()
        settleLink = nil
        settle = nil
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        // The link holds the view; off screen there is nothing to settle.
        if newWindow == nil, let settle {
            position = settle.target
            stopSettling()
        }
    }

    /// A card let go without being thrown springs back into the row.
    private func settleCards() {
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.layoutCards()
        }
    }

    /// Flies a card thrown in `row` off the top, then takes it out of the row by its id: other
    /// cards thrown meanwhile may have landed first and moved it.
    private func throwAway(_ card: TabCardView) {
        UISelectionFeedbackGenerator().selectionChanged()
        let id = card.tabID
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.layoutCards()
            card.alpha = 0
        } completion: { _ in
            // A row settling after a flick keeps its card and its speed across the gap.
            let heading = self.settle.flatMap { self.row.cards.indices.contains(Int($0.target)) ? self.row.cards[Int($0.target)] : nil }
            let speed = self.settle?.velocity(after: CACurrentMediaTime() - self.settleStart) ?? 0
            card.removeFromSuperview()
            if self.views[id] === card { self.views[id] = nil }
            guard let gap = self.row.finishThrow(id, position: self.position, heading: heading) else { return }
            self.stopSettling()
            self.position = gap.position
            if heading != nil {
                self.startSettling(to: gap.settle, velocity: speed)
            } else {
                UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0,
                               options: [.allowUserInteraction]) {
                    self.position = CGFloat(gap.settle)
                    self.layoutCards()
                }
            }
            self.delegate?.tabSwitcher(self, didClose: id)
        }
    }
}

/// One tab in the switcher: its page picture in a rounded card with a shadow, and its favicon
/// and title above.
final class TabCardView: UIView {
    let tabID: UUID
    private let shadow = UIView()
    private let clip = UIView()
    private let band = UIView()
    private let picture = UIImageView()
    private let dimmer = UIView()
    private let icon = UIImageView()
    private let title = UILabel()
    /// What dims a card further back in the row, over its picture or its live page.
    static let dimColour = Palette.rgb(0x1a1a3a)
    /// The live page that takes this card's place as it grows (`TabSwitcherView.growLive`).
    var live: LivePageCard?
    var pictureImage: UIImage? { picture.image }
    private(set) var cardFrame: CGRect = .zero
    /// The favicon and title above the card, which belong to it for a tap or a throw.
    private(set) var headerFrame: CGRect = .zero
    /// What the shadow's path was last drawn for (`layoutShadow`).
    private var shadowShape: (size: CGSize, radius: CGFloat)?

    init(tabID: UUID) {
        self.tabID = tabID
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        shadow.layer.shadowColor = UIColor.black.cgColor
        shadow.layer.shadowOpacity = 0.18
        shadow.layer.shadowRadius = 14
        shadow.layer.shadowOffset = CGSize(width: 0, height: 4)
        addSubview(shadow)
        clip.clipsToBounds = true
        clip.layer.cornerCurve = .continuous
        clip.backgroundColor = Palette.dynamic(light: .white, dark: Palette.rgb(0x2a2a2e))
        addSubview(clip)
        picture.contentMode = .scaleToFill
        clip.addSubview(picture)
        dimmer.backgroundColor = Self.dimColour
        dimmer.alpha = 0
        clip.addSubview(dimmer)
        band.isHidden = true
        clip.insertSubview(band, belowSubview: dimmer)
        // The favicon keeps its own shape, round or see-through, unclipped; the corners round
        // only the plain square that stands in while there is none.
        icon.layer.cornerRadius = 4
        icon.layer.cornerCurve = .continuous
        icon.contentMode = .scaleAspectFit
        icon.tintColor = Palette.primaryText
        addSubview(icon)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = Palette.primaryText
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // The view covers the page's content area so the card can grow to fill it; VoiceOver and the
    // UI tests get the card's own frame.
    override var isAccessibilityElement: Bool { get { true } set {} }
    override var accessibilityTraits: UIAccessibilityTraits { get { .button } set {} }
    override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(cardFrame.intersection(bounds), in: self) }
        set {}
    }

    func configure(title text: String, snapshot: UIImage?, favicon: UIImage?, incognito: Bool, band colour: UIColor?) {
        title.text = text
        picture.image = snapshot
        // A dark colourless mark (GitHub's octocat) would vanish on the dark row: it takes the
        // title's colour instead (`MobileFavicons.drawsAsMark`), as in the Spaces sheet.
        if let favicon, !favicon.isSymbolImage, FaviconStore.isMark(favicon) {
            icon.image = favicon.withRenderingMode(.alwaysTemplate)
        } else {
            icon.image = favicon
        }
        icon.backgroundColor = favicon == nil ? Palette.barControlFill : .clear
        band.backgroundColor = colour
        band.isHidden = colour == nil
        accessibilityLabel = text
    }

    /// Places the card. `frame` is its place in the row; `fill` (0…1) grows it to the whole
    /// `screen` down to `bottom`, where its band takes the status bar's strip and its picture the
    /// page's own area.
    func layout(frame row: CGRect, screen: CGSize, bottom: CGFloat, bandHeight: CGFloat, fill: CGFloat, dim: CGFloat,
                headerAlpha: CGFloat, titleAlpha: CGFloat, nextCardLeft: CGFloat?, scale: CGFloat, moving: Bool) {
        let full = CGRect(x: 0, y: 0, width: screen.width, height: bottom)
        let frame = CGRect(x: row.minX + (full.minX - row.minX) * fill, y: row.minY + (full.minY - row.minY) * fill,
                           width: row.width + (full.width - row.width) * fill, height: row.height + (full.height - row.height) * fill)
        cardFrame = frame
        self.frame = full
        clip.frame = frame
        // The card is the page: its own band at the top, then the content. The band belongs to
        // the page only, so it shrinks to nothing as the tab settles into the row; choosing a
        // tab grows its band back with it.
        let cardBand = bandHeight * frame.width / max(1, screen.width) * fill
        band.frame = CGRect(x: 0, y: 0, width: frame.width, height: cardBand)
        let area = CGRect(x: 0, y: cardBand, width: frame.width, height: max(0, frame.height - cardBand))
        picture.frame = MobileTabCarousel.pictureFrame(image: picture.image?.size ?? .zero, in: area)
        live?.layout(card: frame, area: area, picture: picture.frame, radius: MobileTabCarousel.cornerRadius * (1 - fill),
                     screen: screen, dim: dim)
        dimmer.frame = clip.bounds
        dimmer.alpha = dim
        // Rounded in the row, square where it meets the page's content at the band's bottom.
        let radius = MobileTabCarousel.cornerRadius * (1 - fill)
        clip.layer.cornerRadius = radius
        layoutShadow(frame: frame, radius: radius, scale: scale)
        shadow.alpha = 1 - fill

        let side = MobileTabCarousel.headerIconSide * scale
        let headerY = frame.minY - MobileTabCarousel.headerGap * scale - side
        headerFrame = CGRect(x: frame.minX, y: headerY - 1, width: frame.width, height: side + 2)
        icon.frame = CGRect(x: frame.minX + MobileTabCarousel.headerInset * scale, y: headerY, width: side, height: side)
        let titleLeft = icon.frame.maxX + 7.5
        // Only the card in focus is titled, and its title stops before the card in front (#816).
        let titleWidth = MobileTabCarousel.titleWidth(titleLeft: titleLeft, cardRight: frame.maxX, nextCardLeft: nextCardLeft)
        title.frame = CGRect(x: titleLeft, y: headerY - 1, width: titleWidth, height: side + 2)
        icon.alpha = headerAlpha
        title.alpha = headerAlpha * titleAlpha
        if Self.readsTitles {
            accessibilityValue = (title.alpha > 0.01 && titleWidth > 0 ? "title to \(Int(title.frame.maxX.rounded()))" : "favicon alone")
                + (moving ? ", moving" : "")
        }
    }

    /// The shadow is the card at scale 1, drawn larger or smaller by a transform, so its path only
    /// changes with the card's size or corners: a moving row doesn't rebuild it every frame
    /// (docs/reviewing.md). Its corners scale with it, within 2 % of the card's under the blur.
    private func layoutShadow(frame: CGRect, radius: CGFloat, scale: CGFloat) {
        let size = CGSize(width: (frame.width / scale).rounded(), height: (frame.height / scale).rounded())
        shadow.transform = CGAffineTransform(scaleX: scale, y: scale)
        shadow.bounds = CGRect(origin: .zero, size: size)
        shadow.center = CGPoint(x: frame.midX, y: frame.midY)
        if shadowShape?.size != size || shadowShape?.radius != radius {
            shadowShape = (size, radius)
            shadow.layer.shadowPath = UIBezierPath(roundedRect: shadow.bounds, cornerRadius: radius).cgPath
        }
    }

    /// `-CraReadCardTitles YES`: each card says in its accessibility value whether its title shows
    /// and where it ends, for the UI tests (#816), and ", moving" while the row is dragged or settles.
    private static let readsTitles = LaunchOptions.value("CraReadCardTitles") == "YES"
}

/// A picked card's live page as it grows: the page's own container, never moved out of its place
/// in the view tree (moving a web view blanks it for a frame and drops its touches), is scaled
/// and moved so its page view sits exactly where the card's picture does, and masked to the
/// card's page area, under the card's band. The page takes touches all the way. `overlay`, in the
/// layer above the page, carries the card's dimming and its picture, which fades off the page
/// (`fadePicture`).
final class LivePageCard {
    let container: UIView
    /// The page view's frame in the container: the shape the tab's picture is taken in.
    let page: CGRect
    let overlay = UIView()
    let overlayPicture = UIImageView()
    private let overlayDim = UIView()
    private let mask = UIView()
    private let maskCard = UIView()
    private let maskArea = UIView()

    init(container: UIView, page: CGRect) {
        self.container = container
        self.page = page
        overlay.isUserInteractionEnabled = false
        overlay.clipsToBounds = true
        overlay.layer.cornerCurve = .continuous
        overlayPicture.contentMode = .scaleToFill
        overlay.addSubview(overlayPicture)
        overlayDim.backgroundColor = TabCardView.dimColour
        overlay.addSubview(overlayDim)
        maskCard.clipsToBounds = true
        maskCard.layer.cornerCurve = .continuous
        maskArea.backgroundColor = .black
        maskCard.addSubview(maskArea)
        mask.addSubview(maskCard)
        container.mask = mask
    }

    /// `card` is the card's frame on screen; `area` and `picture` are its page area and picture
    /// in the card.
    func layout(card: CGRect, area: CGRect, picture: CGRect, radius: CGFloat, screen: CGSize, dim: CGFloat) {
        let placed = MobileTabCarousel.livePage(page: page, screen: screen, area: area.offsetBy(dx: card.minX, dy: card.minY))
        container.transform = CGAffineTransform(translationX: placed.center.x - screen.width / 2, y: placed.center.y - screen.height / 2)
            .scaledBy(x: placed.scale, y: placed.scale)
        mask.frame = CGRect(origin: .zero, size: screen)
        maskCard.frame = MobileTabCarousel.containerRect(card, placed: placed, screen: screen)
        maskCard.layer.cornerRadius = radius / max(placed.scale, 0.001)
        maskArea.frame = CGRect(x: area.minX / placed.scale, y: area.minY / placed.scale,
                                width: area.width / placed.scale, height: area.height / placed.scale)
        overlay.frame = card
        overlay.layer.cornerRadius = radius
        overlayPicture.frame = picture
        overlayDim.frame = area
        overlayDim.alpha = dim
    }

    /// Fades the picture off the page over `duration`, eased in (`MobileTabCarousel.pictureFade`).
    /// It may run on past the grow; `done` follows it.
    func fadePicture(over duration: TimeInterval, done: @escaping () -> Void) {
        overlayPicture.fadeOut(over: duration) {
            self.overlay.removeFromSuperview()
            done()
        }
    }

    /// The page is in place: its container is itself again. A picture still fading over it stays
    /// until its fade is done.
    func end() {
        container.transform = .identity
        container.mask = nil
    }
}
