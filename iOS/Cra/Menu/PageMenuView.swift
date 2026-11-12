import CraCore
import UIKit

protocol PageMenuDelegate: AnyObject {
    func pageMenuGoBack()
    func pageMenuGoForward()
    func pageMenuReload()
    func pageMenuToggleFavorite()
    func pageMenu(didPick tile: MobilePageMenu.Tile)
    func pageMenu(didPick row: MobilePageMenu.Row)
    func pageMenuZoom(up: Bool)
    func pageMenuResetZoom()
    func pageMenuReloadWithoutBlockers()
}

/// What the page menu shows about the page it was opened on.
struct PageMenuState {
    var host: String
    var canGoBack: Bool
    var canGoForward: Bool
    var zoom: Double
    var isDesktopSite: Bool
    var canSummarize: Bool
    var blockedCount: Int
    var isFavorite = false
}

/// The page menu's content, laid out to `MobilePageMenu`.
final class PageMenuView: UIView {
    weak var delegate: PageMenuDelegate?
    private(set) var state: PageMenuState

    private let capsule = UIView()
    private let back = UIButton(type: .system)
    private let forward = UIButton(type: .system)
    private let hostLabel = UILabel()
    private let link = UIButton(type: .system)
    private let reload = UIButton(type: .system)
    private var tiles: [(MobilePageMenu.Tile, PageMenuTile)] = []
    private let rowsBox = UIView()
    private var rows: [(MobilePageMenu.Row, PageMenuRow)] = []
    private let problems = UILabel()
    private let withoutBlockers = UIButton(type: .custom)
    private let blocked = UILabel()

    init(state: PageMenuState) {
        self.state = state
        super.init(frame: .zero)

        capsule.backgroundColor = Palette.barControlFill
        capsule.layer.cornerCurve = .continuous
        capsule.layer.borderWidth = 0.5
        capsule.layer.borderColor = Palette.barControlBorder.cgColor
        addSubview(capsule)
        configure(back, symbol: "chevron.left", size: 15, weight: .bold, id: "menu-back", label: "Back", action: #selector(backTapped))
        configure(forward, symbol: "chevron.right", size: 15, weight: .bold, id: "menu-forward", label: "Forward", action: #selector(forwardTapped))
        configure(link, symbol: "pin", size: 14.5, weight: .regular, id: "menu-pin", label: "Pin", action: #selector(linkTapped))
        // The pin opens Arc Search's little menu; "Pin to Space:" joins it when the phone can write to the Mac's sidebar.
        link.showsMenuAsPrimaryAction = true
        configure(reload, symbol: "arrow.clockwise", size: 14.5, weight: .medium, id: "menu-reload", label: "Reload", action: #selector(reloadTapped))
        hostLabel.font = .systemFont(ofSize: 17, weight: .medium)
        hostLabel.textColor = Palette.primaryText
        hostLabel.textAlignment = .center
        hostLabel.lineBreakMode = .byTruncatingMiddle
        hostLabel.accessibilityIdentifier = "menu-host"
        capsule.addSubview(hostLabel)

        for tile in MobilePageMenu.tiles(canSummarize: state.canSummarize) {
            let view = PageMenuTile(tile: tile)
            view.addAction(UIAction { [weak self] _ in self?.delegate?.pageMenu(didPick: tile) }, for: .touchUpInside)
            tiles.append((tile, view))
            addSubview(view)
        }

        rowsBox.backgroundColor = Palette.barControlFill
        rowsBox.layer.cornerRadius = MobilePageMenu.rowCornerRadius
        rowsBox.layer.cornerCurve = .continuous
        rowsBox.clipsToBounds = true
        addSubview(rowsBox)
        for (index, row) in MobilePageMenu.rows.enumerated() {
            let view = PageMenuRow(row: row, showsSeparator: index > 0)
            view.addAction(UIAction { [weak self] _ in self?.delegate?.pageMenu(didPick: row) }, for: .touchUpInside)
            if row == .pageZoom {
                view.isUserInteractionEnabled = true
                view.onZoom = { [weak self] up in self?.delegate?.pageMenuZoom(up: up) }
                view.onResetZoom = { [weak self] in self?.delegate?.pageMenuResetZoom() }
            }
            rows.append((row, view))
            rowsBox.addSubview(view)
        }

        problems.text = "Problems?"
        problems.font = .systemFont(ofSize: 12, weight: .regular)
        problems.textColor = Palette.secondaryText
        addSubview(problems)
        withoutBlockers.setAttributedTitle(NSAttributedString(string: "Reload without ad blockers", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .regular), .foregroundColor: Palette.secondaryText,
        ]), for: .normal)
        withoutBlockers.backgroundColor = Palette.barControlFill
        withoutBlockers.accessibilityIdentifier = "menu-reload-without-blockers"
        withoutBlockers.addTarget(self, action: #selector(withoutBlockersTapped), for: .touchUpInside)
        addSubview(withoutBlockers)
        blocked.font = .systemFont(ofSize: 12, weight: .regular)
        blocked.textColor = Palette.secondaryText
        blocked.textAlignment = .center
        blocked.accessibilityIdentifier = "menu-blocked-count"
        addSubview(blocked)
        apply(state)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure(_ button: UIButton, symbol: String, size: CGFloat, weight: UIImage.SymbolWeight, id: String, label: String, action: Selector) {
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size, weight: weight)), for: .normal)
        button.tintColor = Palette.glyph
        button.accessibilityIdentifier = id
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        capsule.addSubview(button)
    }

    func apply(_ state: PageMenuState) {
        self.state = state
        hostLabel.text = state.host
        link.setImage(UIImage(systemName: state.isFavorite ? "pin.fill" : "pin", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14.5, weight: .regular)), for: .normal)
        link.menu = UIMenu(children: [
            UIAction(title: "Favorite in App", image: UIImage(systemName: "iphone"), state: state.isFavorite ? .on : .off) { [weak self] _ in
                self?.delegate?.pageMenuToggleFavorite()
            },
        ])
        back.isEnabled = state.canGoBack
        forward.isEnabled = state.canGoForward
        back.tintColor = state.canGoBack ? Palette.glyph : Palette.placeholder
        forward.tintColor = state.canGoForward ? Palette.glyph : Palette.placeholder
        for (row, view) in rows {
            switch row {
            case .pageZoom: view.setZoomLabel(MobilePageMenu.zoomLabel(state.zoom))
            case .requestDesktopSite: view.setTitle(state.isDesktopSite ? "Request Mobile Site" : row.label)
            default: break
            }
        }
        blocked.text = MobilePageMenu.blockedLabel(state.blockedCount)
        blocked.isHidden = blocked.text == nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = MobilePageMenu.inset
        capsule.frame = CGRect(x: inset, y: inset, width: bounds.width - 2 * inset, height: MobilePageMenu.capsuleHeight)
        capsule.layer.cornerRadius = capsule.bounds.height / 2
        // Glyph centres measured from the capsule's left edge: 22.5, 68.5, then 65 and 30 from the right.
        let mid = capsule.bounds.midY, width = capsule.bounds.width
        back.frame = CGRect(x: 22.5 - 22, y: mid - 22, width: 44, height: 44)
        forward.frame = CGRect(x: 68.5 - 22, y: mid - 22, width: 44, height: 44)
        link.frame = CGRect(x: width - 65 - 22, y: mid - 22, width: 44, height: 44)
        reload.frame = CGRect(x: width - 30 - 22, y: mid - 22, width: 44, height: 44)
        hostLabel.frame = CGRect(x: 96, y: 0, width: max(0, width - 192), height: capsule.bounds.height)

        let frames = MobilePageMenu.tileFrames(count: tiles.count, width: bounds.width)
        for (index, (_, tile)) in tiles.enumerated() { tile.frame = frames[index].insetBy(dx: -8, dy: 0).union(CGRect(x: frames[index].minX - 8, y: frames[index].maxY, width: frames[index].width + 16, height: 28)) }

        let rowsTop = inset + MobilePageMenu.capsuleHeight + MobilePageMenu.tilesGap + MobilePageMenu.tileSize.height + MobilePageMenu.rowsGap
        rowsBox.frame = CGRect(x: inset, y: rowsTop, width: bounds.width - 2 * inset, height: CGFloat(rows.count) * MobilePageMenu.rowHeight)
        for (index, (_, row)) in rows.enumerated() {
            row.frame = CGRect(x: 0, y: CGFloat(index) * MobilePageMenu.rowHeight, width: rowsBox.bounds.width, height: MobilePageMenu.rowHeight)
        }

        // Footer: "Problems?" and its capsule centred as a pair; the blocked count under it when there is one.
        let footerY = rowsBox.frame.maxY + MobilePageMenu.footerDrop
        let problemsSize = problems.intrinsicContentSize
        let buttonWidth = (withoutBlockers.titleLabel?.intrinsicContentSize.width ?? 150) + 20
        let total = problemsSize.width + 9 + buttonWidth
        let left = (bounds.width - total) / 2
        problems.frame = CGRect(x: left, y: footerY - problemsSize.height / 2, width: problemsSize.width, height: problemsSize.height)
        withoutBlockers.frame = CGRect(x: left + problemsSize.width + 9, y: footerY - 11, width: buttonWidth, height: 22)
        withoutBlockers.layer.cornerRadius = 11
        blocked.frame = CGRect(x: inset, y: footerY + 15, width: bounds.width - 2 * inset, height: 16)
    }

    @objc private func backTapped() { delegate?.pageMenuGoBack() }
    @objc private func forwardTapped() { delegate?.pageMenuGoForward() }
    @objc private func reloadTapped() { delegate?.pageMenuReload() }
    @objc private func linkTapped() {}
    @objc private func withoutBlockersTapped() { delegate?.pageMenuReloadWithoutBlockers() }
}

/// A square tile with its label underneath.
final class PageMenuTile: UIControl {
    private let box = UIView()
    private let icon = UIImageView()
    private let label = UILabel()

    init(tile: MobilePageMenu.Tile) {
        super.init(frame: .zero)
        box.backgroundColor = Palette.barControlFill
        box.layer.cornerRadius = MobilePageMenu.tileCornerRadius
        box.layer.cornerCurve = .continuous
        box.isUserInteractionEnabled = false
        addSubview(box)
        icon.image = Self.image(for: tile)
        icon.tintColor = Palette.glyph
        icon.contentMode = .center
        box.addSubview(icon)
        label.text = tile.label
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = Palette.secondaryText
        label.textAlignment = .center
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = tile.label
        accessibilityIdentifier = "menu-tile-\(tile.rawValue)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        box.frame = CGRect(x: 8, y: 0, width: bounds.width - 16, height: MobilePageMenu.tileSize.height)
        icon.frame = box.bounds
        label.frame = CGRect(x: 0, y: box.frame.maxY + MobilePageMenu.tileLabelDrop - 10, width: bounds.width, height: 18)
    }

    override var isHighlighted: Bool {
        didSet { box.alpha = isHighlighted ? 0.55 : 1 }
    }

    private static func image(for tile: MobilePageMenu.Tile) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
        switch tile {
        case .reader: return UIImage(systemName: "doc.plaintext", withConfiguration: configuration)
        case .copyLink: return UIImage(systemName: "link", withConfiguration: configuration)
        case .share: return UIImage(systemName: "paperplane", withConfiguration: configuration)
        case .summarize: return foldedPage()
        }
    }

    /// Arc Search's Summarize glyph: a page folded in three, as a zigzag of leaning panels.
    private static func foldedPage() -> UIImage {
        let size = CGSize(width: 26, height: 26)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            for (index, top) in [CGFloat(3.5), 10.1, 16.7].enumerated() {
                let lean: CGFloat = index % 2 == 0 ? 3 : -3
                path.move(to: CGPoint(x: 4.5 + max(0, lean), y: top))
                path.addLine(to: CGPoint(x: 21.5 + min(0, lean) + max(0, lean), y: top))
                path.addLine(to: CGPoint(x: 21.5 + min(0, -lean) + max(0, -lean), y: top + 6.6))
                path.addLine(to: CGPoint(x: 4.5 + max(0, -lean), y: top + 6.6))
                path.close()
            }
            path.lineWidth = 1.9
            path.lineJoinStyle = .round
            UIColor.black.setStroke()
            path.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }
}

/// One row of the menu's group: glyph, title, and for Page Zoom the stepper.
final class PageMenuRow: UIControl {
    private let icon = UIImageView()
    private let title = UILabel()
    private let separator = UIView()
    private let minus = UIButton(type: .system)
    private let plus = UIButton(type: .system)
    private let stepper = UIView()
    private let zoomValue = UIButton(type: .system)
    private let isZoom: Bool
    var onZoom: ((Bool) -> Void)?
    var onResetZoom: (() -> Void)?

    init(row: MobilePageMenu.Row, showsSeparator: Bool) {
        isZoom = row == .pageZoom
        super.init(frame: .zero)
        let symbol: String
        switch row {
        case .findOnPage: symbol = "doc.text.magnifyingglass"
        case .pageZoom: symbol = "textformat.size"
        case .requestDesktopSite: symbol = "macbook"
        case .translate: symbol = "translate"
        case .siteSettings: symbol = "gearshape"
        }
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .regular))
        icon.tintColor = Palette.glyph
        icon.contentMode = .center
        addSubview(icon)
        title.text = row.label
        title.font = .systemFont(ofSize: 17, weight: .medium)
        title.textColor = Palette.glyph
        addSubview(title)
        separator.backgroundColor = Palette.dynamic(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.12))
        separator.isHidden = !showsSeparator
        addSubview(separator)
        if isZoom {
            stepper.backgroundColor = Palette.barControlFill
            stepper.layer.cornerRadius = 8
            stepper.layer.cornerCurve = .continuous
            addSubview(stepper)
            for (button, symbol, up) in [(minus, "minus", false), (plus, "plus", true)] {
                button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium)), for: .normal)
                button.tintColor = Palette.glyph
                button.accessibilityIdentifier = up ? "menu-zoom-in" : "menu-zoom-out"
                button.accessibilityLabel = up ? "Zoom in" : "Zoom out"
                button.addAction(UIAction { [weak self] _ in self?.onZoom?(up) }, for: .touchUpInside)
                stepper.addSubview(button)
            }
            zoomValue.titleLabel?.font = .systemFont(ofSize: 15, weight: .regular)
            zoomValue.tintColor = Palette.secondaryText
            zoomValue.accessibilityIdentifier = "menu-zoom-value"
            zoomValue.addAction(UIAction { [weak self] _ in self?.onResetZoom?() }, for: .touchUpInside)
            addSubview(zoomValue)
        }
        isAccessibilityElement = !isZoom
        accessibilityTraits = .button
        accessibilityLabel = row.label
        accessibilityIdentifier = "menu-row-\(row.rawValue)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setTitle(_ text: String) {
        title.text = text
        accessibilityLabel = text
    }

    func setZoomLabel(_ text: String?) {
        zoomValue.setTitle(text, for: .normal)
        zoomValue.isHidden = text == nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Glyph centred 29 pt in, title from 53.5 pt (measured from the row's left edge).
        icon.frame = CGRect(x: 29 - 14, y: bounds.midY - 14, width: 28, height: 28)
        title.frame = CGRect(x: 53.5, y: 0, width: bounds.width - 53.5 - 16, height: bounds.height)
        separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1 / UIScreen.main.scale)
        guard isZoom else { return }
        stepper.frame = CGRect(x: bounds.width - 10 - 98, y: bounds.midY - 16, width: 98, height: 32)
        minus.frame = CGRect(x: 0, y: 0, width: 49, height: 32)
        plus.frame = CGRect(x: 49, y: 0, width: 49, height: 32)
        zoomValue.frame = CGRect(x: stepper.frame.minX - 62, y: 0, width: 56, height: bounds.height)
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted && !isZoom ? Palette.barControlFill : .clear }
    }
}
