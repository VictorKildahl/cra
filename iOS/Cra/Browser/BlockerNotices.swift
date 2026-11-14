import CraCore
import UIKit

/// Arc Search's one-time tip over the bottom bar: "Cra just blocked 14 trackers / See more and
/// change block settings in the ⌃ menu", a small "TIP" tab above it and a close button
/// (`MobileBlockerNotices`). The bar rings its menu button while the tip is up.
final class BlockTipView: UIView {
    private let tab = UILabel()
    private let card = UIView()
    private let title = UILabel()
    private let detail = UILabel()
    let close = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "block-tip"
        let fill = Palette.rgb(0x222125, alpha: 0.96)
        tab.text = MobileBlockerNotices.tipTab
        tab.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        tab.textColor = UIColor(white: 1, alpha: 0.75)
        tab.textAlignment = .center
        tab.backgroundColor = fill
        tab.layer.cornerRadius = MobileBlockerNotices.tipTabSize.height / 2
        tab.layer.masksToBounds = true
        addSubview(tab)
        card.backgroundColor = fill
        card.layer.cornerRadius = MobileBlockerNotices.tipCornerRadius
        card.layer.cornerCurve = .continuous
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.25
        card.layer.shadowRadius = 16
        card.layer.shadowOffset = CGSize(width: 0, height: 6)
        addSubview(card)
        title.accessibilityIdentifier = "block-tip-title"
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.7
        card.addSubview(title)
        detail.attributedText = Self.detailText()
        detail.adjustsFontSizeToFitWidth = true
        detail.minimumScaleFactor = 0.8
        card.addSubview(detail)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)), for: .normal)
        close.tintColor = UIColor(white: 1, alpha: 0.6)
        close.accessibilityIdentifier = "block-tip-close"
        close.accessibilityLabel = "Close"
        card.addSubview(close)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The count as it stands; it can still grow while the tip is up.
    func setCount(_ count: Int) {
        let (text, number) = MobileBlockerNotices.tipTitle(count)
        let font = UIFont.systemFont(ofSize: 24, weight: .bold)
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: UIColor.white])
        if let range = text.range(of: " \(number) ") {
            let start = text.distance(from: text.startIndex, to: range.lowerBound) + 1
            attributed.addAttribute(.foregroundColor, value: Palette.rgb(0x5b6cff), range: NSRange(location: start, length: number.count))
        }
        title.attributedText = attributed
        title.accessibilityLabel = text
    }

    /// "… in the ⌃ menu", the chevron drawn as the bar's own glyph.
    private static func detailText() -> NSAttributedString {
        let font = UIFont.systemFont(ofSize: 14, weight: .regular)
        let color = UIColor(white: 1, alpha: 0.6)
        let text = NSMutableAttributedString(string: MobileBlockerNotices.tipDetail.before + " ", attributes: [.font: font, .foregroundColor: color])
        let chevron = NSTextAttachment()
        chevron.image = UIImage(systemName: "chevron.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))?
            .withTintColor(color, renderingMode: .alwaysOriginal)
        text.append(NSAttributedString(attachment: chevron))
        text.append(NSAttributedString(string: " " + MobileBlockerNotices.tipDetail.after, attributes: [.font: font, .foregroundColor: color]))
        return text
    }

    /// The whole view: the tab above the card.
    static var height: CGFloat { MobileBlockerNotices.tipTabSize.height + MobileBlockerNotices.tipTabGap + MobileBlockerNotices.tipHeight }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = MobileBlockerNotices.tipTabSize
        tab.frame = CGRect(x: 4, y: 0, width: size.width, height: size.height)
        card.frame = CGRect(x: 0, y: size.height + MobileBlockerNotices.tipTabGap, width: bounds.width, height: MobileBlockerNotices.tipHeight)
        let inset: CGFloat = 20
        close.frame = CGRect(x: card.bounds.width - 44, y: 6, width: 40, height: 40)
        title.frame = CGRect(x: inset, y: 18, width: card.bounds.width - inset - 48, height: 32)
        detail.frame = CGRect(x: inset, y: 56, width: card.bounds.width - 2 * inset, height: 20)
    }
}

/// The blue pill over the bar's + after "Problems? Tap to restore original page": "Did it fix the
/// issue?" with a thumbs up and down. A thumbs-up turns into "Blockers disabled for <site>".
final class FixQuestionPill: UIView {
    private let gradient = CAGradientLayer()
    private let label = UILabel()
    let yes = UIButton(type: .system)
    let no = UIButton(type: .system)
    private(set) var answered = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "fix-question"
        gradient.colors = [Palette.rgb(MobileBlockerNotices.pillTop).cgColor, Palette.rgb(MobileBlockerNotices.pillBottom).cgColor]
        gradient.cornerRadius = MobileBlockerNotices.pillCornerRadius
        gradient.cornerCurve = .continuous
        layer.addSublayer(gradient)
        layer.cornerRadius = MobileBlockerNotices.pillCornerRadius
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        layer.shadowColor = Palette.rgb(MobileBlockerNotices.pillBottom).cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
        label.text = MobileBlockerNotices.fixQuestion
        label.font = .systemFont(ofSize: 17, weight: .medium)
        label.textColor = .white
        label.accessibilityIdentifier = "fix-question-label"
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.75
        addSubview(label)
        for (button, symbol, id, name) in [(yes, "hand.thumbsup.fill", "fix-yes", "Yes"), (no, "hand.thumbsdown.fill", "fix-no", "No")] {
            button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
            button.tintColor = .white
            button.backgroundColor = UIColor(white: 1, alpha: 0.16)
            button.layer.cornerRadius = 7
            button.layer.cornerCurve = .continuous
            button.accessibilityIdentifier = id
            button.accessibilityLabel = name
            addSubview(button)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The width the content asks for.
    var preferredWidth: CGFloat {
        let text = label.intrinsicContentSize.width
        // Measured: 16 pt before the text, 13 pt to the thumbs, 8 pt after them; 16 pt each side once answered.
        return answered ? text + 32 : 16 + text + 13 + 2 * MobileBlockerNotices.thumbSize + MobileBlockerNotices.thumbSpacing + 8
    }

    /// The thumbs-up's answer, in place of the question.
    func showDisabled(site: String) {
        answered = true
        label.text = MobileBlockerNotices.disabledLabel(site: site)
        yes.isHidden = true
        no.isHidden = true
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        let side = MobileBlockerNotices.thumbSize
        if answered {
            label.frame = bounds.insetBy(dx: 16, dy: 0)
            label.textAlignment = .center
        } else {
            no.frame = CGRect(x: bounds.width - 8 - side, y: (bounds.height - side) / 2, width: side, height: side)
            yes.frame = no.frame.offsetBy(dx: -(side + MobileBlockerNotices.thumbSpacing), dy: 0)
            label.frame = CGRect(x: 16, y: 0, width: yes.frame.minX - 16 - 13, height: bounds.height)
        }
    }
}

extension BrowserViewController {
    /// After a page finished loading: the tip the first time something was stopped, and the
    /// question once a page restored without blockers has loaded.
    func pageFinishedForBlockerNotices(_ page: WebPage) {
        let incognito = store.tabs.first { $0.id == page.tabID }?.isIncognito ?? false
        if fixPending == page.tabID, let site = page.unblockedSite {
            fixPending = nil
            showFixQuestion(site: site)
        } else {
            considerBlockTip(page, incognito: incognito)
        }
    }

    /// Stopped requests are reported by the page's script and can come in after WebKit says the
    /// page finished, so the tip is also considered at every change of a loaded page.
    private func considerBlockTip(_ page: WebPage, incognito: Bool) {
        guard blockTip == nil, fixPill == nil, menuHost == nil, !isSearching, switcher == nil, !page.isLoading,
              MobileBlockerNotices.showsTip(blocked: page.blockedCount, alreadyShown: settings.value.hasSeenBlockTip, isIncognito: incognito)
        else { return }
        settings.update { $0.hasSeenBlockTip = true }
        showBlockTip(count: page.blockedCount)
    }

    /// Keeps the tip's count current, and puts the question away once the tab left the site.
    func blockerNoticesFollow(_ page: WebPage) {
        if let blockTip, page.blockedCount > 0 { blockTip.setCount(page.blockedCount) }
        if let fixPill, !fixPill.answered, page.unblockedSite == nil { dropFixQuestion() }
        if blockTip == nil, !settings.value.hasSeenBlockTip {
            considerBlockTip(page, incognito: store.tabs.first { $0.id == page.tabID }?.isIncognito ?? false)
        }
    }

    private func showBlockTip(count: Int) {
        let tip = BlockTipView()
        tip.setCount(count)
        tip.close.addAction(UIAction { [weak self] _ in self?.dropBlockTip() }, for: .touchUpInside)
        tip.alpha = 0
        view.insertSubview(tip, aboveSubview: bar)
        blockTip = tip
        placeBlockerNotices()
        tip.transform = CGAffineTransform(translationX: 0, y: 16)
        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
            tip.alpha = 1
            tip.transform = .identity
            self.bar.ringsMenu = true
        }
    }

    func dropBlockTip() {
        guard let tip = blockTip else { return }
        blockTip = nil
        UIView.animate(withDuration: 0.2) {
            tip.alpha = 0
            self.bar.ringsMenu = false
        } completion: { _ in tip.removeFromSuperview() }
    }

    private func showFixQuestion(site: String) {
        dropFixQuestion()
        let pill = FixQuestionPill()
        pill.yes.addAction(UIAction { [weak self, weak pill] _ in
            guard let self, let pill else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.settings.update { $0.disableBlockers(for: site) }
            UIView.animate(withDuration: 0.25) {
                pill.showDisabled(site: site)
                self.placeBlockerNotices()
                pill.layoutIfNeeded()
            }
            // Gone by a timer, like the other toasts, so VoiceOver can read it meanwhile.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self, weak pill] in
                guard let pill, self?.fixPill === pill else { return }
                self?.dropFixQuestion()
            }
        }, for: .touchUpInside)
        pill.no.addAction(UIAction { [weak self] _ in self?.dropFixQuestion() }, for: .touchUpInside)
        pill.alpha = 0
        view.insertSubview(pill, aboveSubview: bar)
        fixPill = pill
        placeBlockerNotices()
        pill.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
            pill.alpha = 1
            pill.transform = .identity
        }
    }

    func dropFixQuestion() {
        guard let pill = fixPill else { return }
        fixPill = nil
        UIView.animate(withDuration: 0.2) { pill.alpha = 0 } completion: { _ in pill.removeFromSuperview() }
    }

    func dropBlockerNotices() {
        dropBlockTip()
        dropFixQuestion()
        fixPending = nil
    }

    /// The tip sits over the bar's top edge, 20 pt in from the sides (no wider than a phone on
    /// iPad); the pill is centred on the + button.
    func placeBlockerNotices() {
        let bounds = view.bounds
        if let tip = blockTip {
            let width = min(bounds.width - 2 * MobileBlockerNotices.tipInset, 400)
            let bottom = bar.frame.minY + MobileBlockerNotices.tipOverlap
            tip.bounds = CGRect(x: 0, y: 0, width: width, height: BlockTipView.height)
            tip.center = CGPoint(x: bounds.midX, y: bottom - BlockTipView.height / 2)
        }
        if let pill = fixPill {
            let centre = bar.convert(CGPoint(x: bar.pillFrame.midX, y: bar.pillFrame.midY), to: view)
            // Short of the menu button, over the tab stack's edge if it must (Arc Search's pill runs
            // from 80 to 360 pt of 440); a longer site name shrinks the text.
            let menu = bar.convert(bar.menuButton.frame, to: view)
            let width = min(pill.preferredWidth, 2 * (menu.minX - 6 - centre.x))
            pill.bounds = CGRect(x: 0, y: 0, width: width, height: MobileBlockerNotices.pillHeight)
            pill.center = centre
        }
    }
}
