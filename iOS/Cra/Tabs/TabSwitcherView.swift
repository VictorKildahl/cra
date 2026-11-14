import CraCore
import UIKit

protocol TabSwitcherDelegate: AnyObject {
    func tabSwitcher(_ switcher: TabSwitcherView, didSelect id: UUID)
    func tabSwitcher(_ switcher: TabSwitcherView, didClose id: UUID)
}

/// The tab switcher: every open tab as a card in one row (`MobileTabCarousel` places them).
/// Drag sideways to move along the row, tap a card to open it, throw one upwards to close it.
/// `expansion` runs from 0 (the row) to 1 (the card in focus fills the screen), which is how the
/// switcher grows out of a page and back into one.
final class TabSwitcherView: UIView, UIGestureRecognizerDelegate {
    weak var delegate: TabSwitcherDelegate?

    private let background = CAGradientLayer()
    private var cards: [TabCardView] = []
    private(set) var position: CGFloat = 0
    private var dragStart: CGFloat = 0
    private var draggedCard: TabCardView?
    private var draggedOffset: CGFloat = 0

    var expansion: CGFloat = 0 { didSet { setNeedsLayout() } }
    /// The card that fills the screen at `expansion` 1.
    var expandedID: UUID?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        background.startPoint = CGPoint(x: 0, y: 0)
        background.endPoint = CGPoint(x: 1, y: 1)
        layer.addSublayer(background)
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TabSwitcherView, _) in view.applyColors() }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned(_:)))
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
        background.colors = dark ? [Palette.rgb(0x1f1e2b).cgColor, Palette.rgb(0x241d26).cgColor]
                                 : [Palette.rgb(0xefeefd).cgColor, Palette.rgb(0xf8eefb).cgColor]
        CATransaction.commit()
    }

    // MARK: Content

    var focusedIndex: Int { min(max(0, Int(position.rounded())), max(0, cards.count - 1)) }
    var focusedID: UUID? { cards.indices.contains(focusedIndex) ? cards[focusedIndex].tabID : nil }
    var isEmpty: Bool { cards.isEmpty }

    /// Shows `tabs`, oldest first, focused on `focus`.
    func setTabs(_ tabs: [MobileTab], focus: UUID?, snapshot: (UUID) -> UIImage?, favicon: (MobileTab) -> UIImage?) {
        cards.forEach { $0.removeFromSuperview() }
        cards = tabs.enumerated().map { index, tab in
            let card = TabCardView(tabID: tab.id)
            card.configure(title: tab.displayTitle, snapshot: snapshot(tab.id), favicon: favicon(tab), incognito: tab.isIncognito)
            card.accessibilityIdentifier = "tab-card-\(index)"
            addSubview(card)
            return card
        }
        position = CGFloat(tabs.firstIndex { $0.id == focus } ?? max(0, tabs.count - 1))
        setNeedsLayout()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        background.frame = bounds
        CATransaction.commit()
        layoutCards()
    }

    private func layoutCards() {
        let screen = bounds.size
        guard screen.width > 0 else { return }
        let expandedIndex = cards.firstIndex { $0.tabID == expandedID }
        for (index, card) in cards.enumerated() {
            let relative = CGFloat(index) - position
            let placement = MobileTabCarousel.placement(relative: relative, in: screen)
            var frame = placement.frame
            frame = frame.insetBy(dx: frame.width * (1 - placement.scale) / 2, dy: frame.height * (1 - placement.scale) / 2)
            if card === draggedCard { frame.origin.y += draggedOffset }
            var fill: CGFloat = 0
            if let expandedIndex, expansion > 0 {
                if index == expandedIndex {
                    fill = expansion
                } else {
                    // The others make way: off to their own side.
                    frame.origin.x += (index < expandedIndex ? -1 : 1) * expansion * screen.width * 0.7
                }
            }
            card.layout(frame: frame, screen: screen, fill: fill, dim: placement.dim * (1 - expansion),
                        headerAlpha: 1 - min(1, expansion * 2), scale: placement.scale)
        }
    }

    // MARK: Gestures

    private func card(at point: CGPoint) -> TabCardView? {
        // Newer cards are on top.
        cards.reversed().first { $0.cardFrame.contains(point) }
    }

    @objc private func tapped(_ tap: UITapGestureRecognizer) {
        guard let card = card(at: tap.location(in: self)) else { return }
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
            case .changed:
                draggedOffset = min(0, translation.y)
                layoutCards()
            case .ended, .cancelled:
                let closes = pan.state == .ended && MobileTabCarousel.closes(translation: translation.y, velocity: velocity.y)
                if closes { throwAway(card, velocity: velocity.y) } else { settleDraggedCard() }
            default: break
            }
            return
        }
        switch pan.state {
        case .began:
            dragStart = position
        case .changed:
            position = MobileTabCarousel.position(start: dragStart, translation: translation.x, count: cards.count, in: bounds.size)
            layoutCards()
        case .ended, .cancelled:
            let target = MobileTabCarousel.restingIndex(position: position, velocity: velocity.x, count: cards.count, in: bounds.size)
            UIView.animate(spring: MobileMotion.tabRowSettle) {
                self.position = CGFloat(target)
                self.layoutCards()
            }
        default: break
        }
    }

    private func settleDraggedCard() {
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.draggedOffset = 0
            self.layoutCards()
        } completion: { _ in self.draggedCard = nil }
    }

    private func throwAway(_ card: TabCardView, velocity: CGFloat) {
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        let id = card.tabID
        let distance = bounds.height
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn, .beginFromCurrentState]) {
            self.draggedOffset = -distance
            self.layoutCards()
            card.alpha = 0
        } completion: { _ in
            card.removeFromSuperview()
            self.cards.remove(at: index)
            self.draggedCard = nil
            self.draggedOffset = 0
            // The row closes the gap. A card thrown from behind the focus leaves the focus where
            // it was; throwing the focused card hands the focus to the one after it.
            var target = self.position.rounded()
            if CGFloat(index) < target {
                target -= 1
                self.position -= 1
            }
            target = min(max(0, target), CGFloat(max(0, self.cards.count - 1)))
            UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0,
                           options: [.allowUserInteraction]) {
                self.position = target
                self.layoutCards()
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
    private let picture = UIImageView()
    private let dimmer = UIView()
    private let icon = UIImageView()
    private let title = UILabel()
    private(set) var cardFrame: CGRect = .zero

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
        dimmer.backgroundColor = Palette.rgb(0x1a1a3a)
        dimmer.alpha = 0
        clip.addSubview(dimmer)
        icon.layer.cornerRadius = 4
        icon.layer.cornerCurve = .continuous
        icon.clipsToBounds = true
        icon.contentMode = .scaleAspectFit
        addSubview(icon)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = Palette.primaryText
        title.lineBreakMode = .byTruncatingTail
        addSubview(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // The view covers the screen so the card can grow to fill it; VoiceOver and the UI tests
    // get the card's own frame.
    override var isAccessibilityElement: Bool { get { true } set {} }
    override var accessibilityTraits: UIAccessibilityTraits { get { .button } set {} }
    override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(cardFrame.intersection(bounds), in: self) }
        set {}
    }

    func configure(title text: String, snapshot: UIImage?, favicon: UIImage?, incognito: Bool) {
        title.text = text
        picture.image = snapshot
        icon.image = favicon
        icon.backgroundColor = favicon == nil ? Palette.barControlFill : .clear
        accessibilityLabel = text
    }

    /// Places the card. `frame` is its place in the row; `fill` (0…1) grows it to the whole
    /// `screen`, where the picture shows from its very top instead of from under the status bar.
    func layout(frame row: CGRect, screen: CGSize, fill: CGFloat, dim: CGFloat, headerAlpha: CGFloat, scale: CGFloat) {
        let full = CGRect(origin: .zero, size: screen)
        let frame = CGRect(x: row.minX + (full.minX - row.minX) * fill, y: row.minY + (full.minY - row.minY) * fill,
                           width: row.width + (full.width - row.width) * fill, height: row.height + (full.height - row.height) * fill)
        cardFrame = frame
        self.frame = full
        clip.frame = frame
        // The card is cut from the bottom of the page picture: the strip under the status bar
        // stays out of the row and slides in as the card grows.
        let pictureHeight = frame.width * screen.height / max(1, screen.width)
        picture.frame = CGRect(x: 0, y: frame.height - pictureHeight, width: frame.width, height: pictureHeight)
        dimmer.frame = clip.bounds
        dimmer.alpha = dim
        let radius = MobileTabCarousel.cornerRadius + (UIScreen.main.displayCornerRadius - MobileTabCarousel.cornerRadius) * fill
        clip.layer.cornerRadius = radius
        shadow.frame = frame
        shadow.layer.shadowPath = UIBezierPath(roundedRect: shadow.bounds, cornerRadius: radius).cgPath
        shadow.alpha = 1 - fill

        let side = MobileTabCarousel.headerIconSide * scale
        let headerY = frame.minY - MobileTabCarousel.headerGap * scale - side
        icon.frame = CGRect(x: frame.minX + MobileTabCarousel.headerInset * scale, y: headerY, width: side, height: side)
        title.frame = CGRect(x: icon.frame.maxX + 7.5, y: headerY - 1, width: max(0, frame.maxX - icon.frame.maxX - 16), height: side + 2)
        icon.alpha = headerAlpha
        title.alpha = headerAlpha
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
