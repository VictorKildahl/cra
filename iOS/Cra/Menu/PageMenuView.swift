import CraCore
import UIKit

protocol PageMenuDelegate: AnyObject {
    func pageMenuGoBack()
    func pageMenuGoForward()
    func pageMenuReload()
    func pageMenuCopyLink()
    func pageMenu(didPick tile: MobilePageMenu.Tile)
    func pageMenu(didPick row: MobilePageMenu.Row)
    func pageMenuZoom(up: Bool)
    func pageMenuResetZoom()
    func pageMenuReloadWithoutBlockers()
    /// Display Options opened or closed: the sheet changes height.
    func pageMenuDidChangeHeight()
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
    var isTranslated = false
    var isReader = false
}

/// The page menu's content, laid out to `MobilePageMenu` (Arc Search 1.49, Victor's recording).
final class PageMenuView: UIView {
    weak var delegate: PageMenuDelegate?
    private(set) var state: PageMenuState
    /// Display Options is open.
    private(set) var displayOptionsOpen = false

    private let capsule = UIView()
    private let back = UIButton(type: .system)
    private let forward = UIButton(type: .system)
    private let hostLabel = UILabel()
    private let link = UIButton(type: .system)
    private let reload = UIButton(type: .system)
    private var tiles: [(MobilePageMenu.Tile, PageMenuTile)] = []
    private let optionsBox = UIView()
    private let optionsHeader: PageMenuRow
    private var options: [(MobilePageMenu.Row, PageMenuRow)] = []
    private let siteBox = UIView()
    private let siteRow: PageMenuRow
    private let footer = UIControl()
    private let scrubbed = UILabel()
    private let restore = UILabel()

    init(state: PageMenuState) {
        self.state = state
        optionsHeader = PageMenuRow(row: .displayOptions, showsSeparator: false)
        siteRow = PageMenuRow(row: .siteSettings, showsSeparator: false)
        super.init(frame: .zero)

        capsule.backgroundColor = Palette.barControlFill
        capsule.layer.cornerCurve = .continuous
        capsule.layer.borderWidth = 0.5
        capsule.layer.borderColor = Palette.barControlBorder.cgColor
        addSubview(capsule)
        configure(back, symbol: "chevron.left", size: 17, weight: .semibold, id: "menu-back", label: "Back", action: #selector(backTapped))
        configure(forward, symbol: "chevron.right", size: 17, weight: .semibold, id: "menu-forward", label: "Forward", action: #selector(forwardTapped))
        configure(link, symbol: "link", size: 17, weight: .medium, id: "menu-copy-link", label: "Copy Link", action: #selector(linkTapped))
        configure(reload, symbol: "arrow.clockwise", size: 17, weight: .medium, id: "menu-reload", label: "Reload", action: #selector(reloadTapped))
        hostLabel.font = .systemFont(ofSize: 18, weight: .regular)
        hostLabel.textColor = Palette.primaryText
        hostLabel.textAlignment = .center
        hostLabel.lineBreakMode = .byTruncatingTail
        hostLabel.accessibilityIdentifier = "menu-host"
        capsule.addSubview(hostLabel)

        for tile in MobilePageMenu.tiles(canSummarize: state.canSummarize) {
            let view = PageMenuTile(tile: tile)
            view.addAction(UIAction { [weak self] _ in self?.delegate?.pageMenu(didPick: tile) }, for: .touchUpInside)
            tiles.append((tile, view))
            addSubview(view)
        }

        for box in [optionsBox, siteBox] {
            box.backgroundColor = Palette.barControlFill
            box.layer.cornerRadius = MobilePageMenu.rowCornerRadius
            box.layer.cornerCurve = .continuous
            box.clipsToBounds = true
            addSubview(box)
        }
        optionsHeader.addAction(UIAction { [weak self] _ in self?.toggleDisplayOptions() }, for: .touchUpInside)
        optionsBox.addSubview(optionsHeader)
        for row in MobilePageMenu.displayOptions {
            let view = PageMenuRow(row: row, showsSeparator: true)
            view.addAction(UIAction { [weak self] _ in self?.delegate?.pageMenu(didPick: row) }, for: .touchUpInside)
            if row == .pageZoom {
                view.onZoom = { [weak self] up in self?.delegate?.pageMenuZoom(up: up) }
                view.onResetZoom = { [weak self] in self?.delegate?.pageMenuResetZoom() }
            }
            view.alpha = 0
            options.append((row, view))
            optionsBox.addSubview(view)
        }
        siteRow.addAction(UIAction { [weak self] _ in self?.delegate?.pageMenu(didPick: .siteSettings) }, for: .touchUpInside)
        siteBox.addSubview(siteRow)

        // "Arc scrubbed 22 trackers / Problems? Tap to restore original page": the whole card reloads
        // the page without blockers.
        footer.backgroundColor = Palette.barControlFill
        footer.layer.cornerRadius = MobilePageMenu.rowCornerRadius
        footer.layer.cornerCurve = .continuous
        footer.accessibilityIdentifier = "menu-reload-without-blockers"
        footer.addTarget(self, action: #selector(withoutBlockersTapped), for: .touchUpInside)
        addSubview(footer)
        scrubbed.accessibilityIdentifier = "menu-blocked-count"
        scrubbed.isUserInteractionEnabled = false
        footer.addSubview(scrubbed)
        restore.text = MobilePageMenu.restoreHint
        restore.font = .systemFont(ofSize: 15, weight: .regular)
        restore.textColor = Palette.secondaryText
        restore.isUserInteractionEnabled = false
        footer.addSubview(restore)
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
        back.isEnabled = state.canGoBack
        forward.isEnabled = state.canGoForward
        back.tintColor = state.canGoBack ? Palette.glyph : Palette.placeholder
        forward.tintColor = state.canGoForward ? Palette.glyph : Palette.placeholder
        for (tile, view) in tiles where tile == .pin {
            view.setPinned(state.isFavorite)
        }
        for (row, view) in options {
            switch row {
            case .pageZoom: view.setZoomLabel(MobilePageMenu.zoomLabel(state.zoom))
            case .requestDesktopSite: view.setTitle(state.isDesktopSite ? "Request Mobile Site" : row.label)
            case .translate: view.setTitle(state.isTranslated ? "Show Original" : row.label)
            case .readerMode: view.setTitle(state.isReader ? "Exit Reader Mode" : row.label)
            default: break
            }
        }
        if let label = MobilePageMenu.scrubbedLabel(state.blockedCount) {
            let text = NSMutableAttributedString(string: label.text, attributes: [
                .font: UIFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: Palette.primaryText,
            ])
            if let range = label.text.range(of: label.number) {
                text.addAttribute(.font, value: UIFont.systemFont(ofSize: 17, weight: .bold), range: NSRange(range, in: label.text))
            }
            scrubbed.attributedText = text
            scrubbed.accessibilityLabel = label.text
            scrubbed.isHidden = false
        } else {
            scrubbed.isHidden = true
        }
        setNeedsLayout()
    }

    private func toggleDisplayOptions() {
        displayOptionsOpen.toggle()
        optionsHeader.setOpen(displayOptionsOpen)
        UISelectionFeedbackGenerator().selectionChanged()
        delegate?.pageMenuDidChangeHeight()
        UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.9, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            for (_, view) in self.options { view.alpha = self.displayOptionsOpen ? 1 : 0 }
            self.setNeedsLayout()
            self.layoutIfNeeded()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset = MobilePageMenu.inset
        capsule.frame = CGRect(x: inset, y: inset, width: bounds.width - 2 * inset, height: MobilePageMenu.capsuleHeight)
        capsule.layer.cornerRadius = capsule.bounds.height / 2
        // Glyph centres from the recording: 25 and 65 pt from the capsule's left, 65 and 27 from its right.
        let mid = capsule.bounds.midY, width = capsule.bounds.width
        back.frame = CGRect(x: 25 - 22, y: mid - 22, width: 44, height: 44)
        forward.frame = CGRect(x: 65 - 22, y: mid - 22, width: 44, height: 44)
        link.frame = CGRect(x: width - 65 - 22, y: mid - 22, width: 44, height: 44)
        reload.frame = CGRect(x: width - 27 - 22, y: mid - 22, width: 44, height: 44)
        hostLabel.frame = CGRect(x: 92, y: 0, width: max(0, width - 184), height: capsule.bounds.height)

        let frames = MobilePageMenu.tileFrames(count: tiles.count, width: bounds.width)
        for (index, (_, tile)) in tiles.enumerated() {
            let box = frames[index]
            tile.frame = CGRect(x: box.minX - 6, y: box.minY, width: box.width + 12, height: box.height + MobilePageMenu.tileLabelDrop + 12)
        }

        let rowWidth = bounds.width - 2 * inset
        let groupTop = inset + MobilePageMenu.capsuleHeight + MobilePageMenu.tilesGap + MobilePageMenu.tileHeight + MobilePageMenu.rowsGap
        let open = displayOptionsOpen
        optionsBox.frame = CGRect(x: inset, y: groupTop, width: rowWidth,
                                  height: CGFloat(open ? 1 + options.count : 1) * MobilePageMenu.rowHeight)
        optionsHeader.frame = CGRect(x: 0, y: 0, width: rowWidth, height: MobilePageMenu.rowHeight)
        for (index, (_, row)) in options.enumerated() {
            row.frame = CGRect(x: 0, y: CGFloat(index + 1) * MobilePageMenu.rowHeight, width: rowWidth, height: MobilePageMenu.rowHeight)
        }
        siteBox.frame = CGRect(x: inset, y: optionsBox.frame.maxY + MobilePageMenu.groupGap, width: rowWidth, height: MobilePageMenu.rowHeight)
        siteRow.frame = siteBox.bounds
        footer.frame = CGRect(x: inset, y: siteBox.frame.maxY + MobilePageMenu.groupGap, width: rowWidth, height: MobilePageMenu.footerHeight)
        // The two lines start 20.7 pt in; with nothing scrubbed the hint sits alone in the middle.
        if scrubbed.isHidden {
            restore.frame = CGRect(x: 20.7, y: 0, width: rowWidth - 41.4, height: footer.bounds.height)
        } else {
            scrubbed.frame = CGRect(x: 20.7, y: 8, width: rowWidth - 41.4, height: 21)
            restore.frame = CGRect(x: 20.7, y: 29, width: rowWidth - 41.4, height: 19)
        }
    }

    @objc private func backTapped() { delegate?.pageMenuGoBack() }
    @objc private func forwardTapped() { delegate?.pageMenuGoForward() }
    @objc private func reloadTapped() { delegate?.pageMenuReload() }
    @objc private func linkTapped() { delegate?.pageMenuCopyLink() }
    @objc private func withoutBlockersTapped() { delegate?.pageMenuReloadWithoutBlockers() }
}

/// A square tile with its label underneath.
final class PageMenuTile: UIControl {
    private let box = UIView()
    private let icon = UIImageView()
    private let label = UILabel()
    private let tile: MobilePageMenu.Tile

    init(tile: MobilePageMenu.Tile) {
        self.tile = tile
        super.init(frame: .zero)
        box.backgroundColor = Palette.barControlFill
        box.layer.cornerRadius = MobilePageMenu.tileCornerRadius
        box.layer.cornerCurve = .continuous
        box.isUserInteractionEnabled = false
        addSubview(box)
        icon.image = Self.image(for: tile, pinned: false)
        icon.tintColor = Palette.glyph
        icon.contentMode = .center
        box.addSubview(icon)
        label.text = tile.label
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = Palette.primaryText
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = tile.label
        accessibilityIdentifier = "menu-tile-\(tile.rawValue)"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Pin shows whether the page is a favorite ("Pinned").
    func setPinned(_ pinned: Bool) {
        icon.image = Self.image(for: tile, pinned: pinned)
        label.text = pinned ? "Pinned" : tile.label
        accessibilityLabel = label.text
        accessibilityTraits = pinned ? [.button, .selected] : .button
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        box.frame = CGRect(x: 6, y: 0, width: bounds.width - 12, height: MobilePageMenu.tileHeight)
        icon.frame = box.bounds
        label.frame = CGRect(x: 0, y: box.frame.maxY + MobilePageMenu.tileLabelDrop - 10, width: bounds.width, height: 20)
    }

    override var isHighlighted: Bool {
        didSet { box.alpha = isHighlighted ? 0.55 : 1 }
    }

    private static func image(for tile: MobilePageMenu.Tile, pinned: Bool) -> UIImage? {
        let configuration = UIImage.SymbolConfiguration(pointSize: 26, weight: .regular)
        switch tile {
        case .findOnPage: return UIImage(systemName: "doc.text.magnifyingglass", withConfiguration: configuration)
        case .pin: return UIImage(systemName: pinned ? "pin.fill" : "pin", withConfiguration: configuration)
        case .share: return UIImage(systemName: "square.and.arrow.up", withConfiguration: configuration)
        case .summarize: return foldedPage()
        }
    }

    /// Arc Search's Summarize glyph: a page folded in three, as a zigzag of leaning panels.
    private static func foldedPage() -> UIImage {
        let size = CGSize(width: 30, height: 30)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let path = UIBezierPath()
            for (index, top) in [CGFloat(4), 11.6, 19.2].enumerated() {
                let lean: CGFloat = index % 2 == 0 ? 3.5 : -3.5
                path.move(to: CGPoint(x: 5 + max(0, lean), y: top))
                path.addLine(to: CGPoint(x: 25 + min(0, lean) + max(0, lean), y: top))
                path.addLine(to: CGPoint(x: 25 + min(0, -lean) + max(0, -lean), y: top + 7.6))
                path.addLine(to: CGPoint(x: 5 + max(0, -lean), y: top + 7.6))
                path.close()
            }
            path.lineWidth = 2
            path.lineJoinStyle = .round
            UIColor.black.setStroke()
            path.stroke()
        }.withRenderingMode(.alwaysTemplate)
    }
}

/// One row of the menu: glyph and title, a chevron for Display Options, the stepper for Page Zoom.
final class PageMenuRow: UIControl {
    private let icon = UIImageView()
    private let title = UILabel()
    private let separator = UIView()
    private let chevron = UIImageView()
    private let minus = UIButton(type: .system)
    private let plus = UIButton(type: .system)
    private let stepper = UIView()
    private let stepperLine = UIView()
    private let zoomValue = UIButton(type: .system)
    private let isZoom: Bool
    private let opens: Bool
    var onZoom: ((Bool) -> Void)?
    var onResetZoom: (() -> Void)?

    init(row: MobilePageMenu.Row, showsSeparator: Bool) {
        isZoom = row == .pageZoom
        opens = row == .displayOptions
        super.init(frame: .zero)
        let symbol: String
        switch row {
        case .displayOptions: symbol = "doc.richtext"
        case .translate: symbol = "globe.americas.fill"
        case .readerMode: symbol = "doc.plaintext"
        case .pageZoom: symbol = "textformat.size"
        case .requestDesktopSite: symbol = "laptopcomputer"
        case .siteSettings: symbol = "gearshape"
        }
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular))
        icon.tintColor = Palette.glyph
        icon.contentMode = .center
        addSubview(icon)
        title.text = row.label
        title.font = .systemFont(ofSize: 18, weight: .regular)
        title.textColor = Palette.primaryText
        addSubview(title)
        separator.backgroundColor = Palette.dynamic(light: UIColor(white: 0, alpha: 0.10), dark: UIColor(white: 1, alpha: 0.12))
        separator.isHidden = !showsSeparator
        addSubview(separator)
        if opens {
            chevron.image = UIImage(systemName: "chevron.right", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
            chevron.tintColor = Palette.secondaryText
            chevron.contentMode = .center
            addSubview(chevron)
        }
        if isZoom {
            stepper.backgroundColor = Palette.barControlFill
            stepper.layer.cornerRadius = 9
            stepper.layer.cornerCurve = .continuous
            addSubview(stepper)
            stepperLine.backgroundColor = Palette.dynamic(light: UIColor(white: 0, alpha: 0.12), dark: UIColor(white: 1, alpha: 0.14))
            stepper.addSubview(stepperLine)
            for (button, symbol, up) in [(minus, "minus", false), (plus, "plus", true)] {
                button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)), for: .normal)
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

    /// Display Options' chevron turns down while it is open.
    func setOpen(_ open: Bool) {
        UIView.animate(withDuration: 0.25) {
            self.chevron.transform = open ? CGAffineTransform(rotationAngle: .pi / 2) : .identity
        }
        accessibilityValue = open ? "Open" : nil
    }

    func setZoomLabel(_ text: String?) {
        zoomValue.setTitle(text, for: .normal)
        zoomValue.isHidden = text == nil
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Glyph centred 30 pt in, title from 52.7 pt, chevron 26 pt from the right (recording).
        icon.frame = CGRect(x: 30 - 15, y: bounds.midY - 15, width: 30, height: 30)
        title.frame = CGRect(x: 52.7, y: 0, width: bounds.width - 52.7 - 40, height: bounds.height)
        separator.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1 / UIScreen.main.scale)
        chevron.frame = CGRect(x: bounds.width - 26 - 10, y: bounds.midY - 10, width: 20, height: 20)
        guard isZoom else { return }
        // The stepper: 89 × 31 pt, its right edge 10 pt in, a hairline between − and +.
        stepper.frame = CGRect(x: bounds.width - 10 - 89, y: bounds.midY - 15.5, width: 89, height: 31)
        minus.frame = CGRect(x: 0, y: 0, width: 44.5, height: 31)
        plus.frame = CGRect(x: 44.5, y: 0, width: 44.5, height: 31)
        stepperLine.frame = CGRect(x: 44, y: 7, width: 1, height: 17)
        zoomValue.frame = CGRect(x: stepper.frame.minX - 62, y: 0, width: 56, height: bounds.height)
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted && !isZoom ? Palette.barControlFill : .clear }
    }
}
