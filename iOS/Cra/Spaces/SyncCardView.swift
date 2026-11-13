import CraCore
import UIKit

/// Arc Search's "Every tab, anywhere. / Sync with Arc Desktop" callout over the tab row's Spaces
/// button (Victor's recording, 3:30), in Cra's words (`MobileSyncIntro`). Measured: 288 × 55 pt,
/// 18 pt from the left, its point 7 pt tall over the button's centre, 10 pt above it.
final class SyncCardView: UIView {
    private let bubble = CAShapeLayer()
    private let logo = UIImageView(image: UIImage(named: "LaunchMark"))
    private let title = UILabel()
    private let detail = UILabel()
    /// The card itself: a button, so the tab row's own tap doesn't take its touches.
    let open = UIButton(type: .custom)
    let close = UIButton(type: .system)
    /// The tip's x in this view.
    var tipX: CGFloat = 40 { didSet { setNeedsLayout() } }

    static let size = CGSize(width: 288, height: 55)
    static let tipHeight: CGFloat = 7

    override init(frame: CGRect) {
        super.init(frame: frame)
        bubble.fillColor = Palette.rgb(0xeceefb).cgColor
        bubble.shadowColor = UIColor.black.cgColor
        bubble.shadowOpacity = 0.2
        bubble.shadowRadius = 10
        bubble.shadowOffset = CGSize(width: 0, height: 4)
        layer.addSublayer(bubble)
        logo.isUserInteractionEnabled = false
        addSubview(logo)
        title.text = MobileSyncIntro.cardTitle
        title.font = .systemFont(ofSize: 17, weight: .bold)
        title.textColor = Palette.rgb(0x16153d)
        detail.text = MobileSyncIntro.cardDetail
        detail.font = .systemFont(ofSize: 15)
        detail.textColor = Palette.rgb(0x8d8daa)
        [title, detail].forEach { $0.isUserInteractionEnabled = false; $0.adjustsFontSizeToFitWidth = true; $0.minimumScaleFactor = 0.8; addSubview($0) }
        open.accessibilityLabel = MobileSyncIntro.cardTitle + " " + MobileSyncIntro.cardDetail
        open.accessibilityIdentifier = "sync-card-open"
        addSubview(open)
        close.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)), for: .normal)
        close.tintColor = .white
        close.backgroundColor = Palette.rgb(0xb9b9cc)
        close.layer.cornerRadius = 12
        close.accessibilityLabel = "Close"
        close.accessibilityIdentifier = "sync-card-close"
        addSubview(close)
        title.isAccessibilityElement = false
        detail.isAccessibilityElement = false
        accessibilityIdentifier = "sync-card"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let body = CGRect(x: 0, y: 0, width: bounds.width, height: Self.size.height)
        let path = UIBezierPath(roundedRect: body, cornerRadius: 18)
        let tip = min(max(tipX, 24), bounds.width - 24)
        path.move(to: CGPoint(x: tip - 8, y: body.maxY))
        path.addLine(to: CGPoint(x: tip, y: body.maxY + Self.tipHeight))
        path.addLine(to: CGPoint(x: tip + 8, y: body.maxY))
        path.close()
        bubble.frame = bounds
        bubble.path = path.cgPath
        bubble.shadowPath = path.cgPath
        open.frame = body
        logo.frame = CGRect(x: 14, y: (body.height - 30) / 2, width: 30, height: 30)
        close.frame = CGRect(x: body.width - 14 - 24, y: (body.height - 24) / 2, width: 24, height: 24)
        let textX = logo.frame.maxX + 12
        let textWidth = close.frame.minX - 10 - textX
        title.frame = CGRect(x: textX, y: 8, width: textWidth, height: 21)
        detail.frame = CGRect(x: textX, y: 29, width: textWidth, height: 18)
    }

}

extension BrowserViewController {
    /// Puts the card over the Spaces button once the tab row has settled, unless it was closed
    /// or the Mac's Spaces are already here.
    func offerSyncCard(in switcher: TabSwitcherView) {
        guard !settings.value.hasDismissedSyncCard, switcher.viewWithTag(SyncCardView.tag) == nil else { return }
        SyncedSidebar.hasSpaces { [weak self, weak switcher] hasSpaces in
            guard let self, let switcher, self.switcher === switcher,
                  MobileSyncIntro.showsCard(hasSpaces: hasSpaces, dismissed: self.settings.value.hasDismissedSyncCard) else { return }
            let card = SyncCardView()
            card.tag = SyncCardView.tag
            let button = self.bar.convert(self.bar.spacesButton.frame, to: switcher)
            let size = CGSize(width: min(SyncCardView.size.width, switcher.bounds.width - 36), height: SyncCardView.size.height + SyncCardView.tipHeight)
            card.frame = CGRect(x: 18, y: button.minY - 10 - size.height, width: size.width, height: size.height)
            card.tipX = button.midX - card.frame.minX
            // A tap anywhere but the close button opens the Spaces sheet.
            card.open.addAction(UIAction { [weak self] _ in self?.showSpaces() }, for: .touchUpInside)
            card.close.addAction(UIAction { [weak self, weak card] _ in
                self?.settings.update { $0.hasDismissedSyncCard = true }
                UIView.animate(withDuration: 0.2) { card?.alpha = 0 } completion: { _ in card?.removeFromSuperview() }
            }, for: .touchUpInside)
            card.alpha = 0
            card.transform = CGAffineTransform(translationX: 0, y: 8)
            switcher.addSubview(card)
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0) {
                card.alpha = 1
                card.transform = .identity
            }
        }
    }
}

extension SyncCardView {
    static let tag = 0x5c4d
}
