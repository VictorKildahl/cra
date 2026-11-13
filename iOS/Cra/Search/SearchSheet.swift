import CraCore
import UIKit

protocol SearchSheetDelegate: AnyObject {
    func searchSheet(_ sheet: SearchSheet, didChangeText text: String)
    /// The keyboard's Go key.
    func searchSheet(_ sheet: SearchSheet, didSubmit text: String)
    func searchSheet(_ sheet: SearchSheet, didPick row: MobileSuggestions.Row)
    func searchSheet(_ sheet: SearchSheet, didPickFavorite site: MobileFavorites.Site)
    func searchSheet(_ sheet: SearchSheet, didAskToBrowseFor row: MobileSuggestions.Row)
    func searchSheetDidToggleIncognito(_ sheet: SearchSheet)
    /// The mic in the empty field: voice search.
    func searchSheetDidAskForVoice(_ sheet: SearchSheet)
    /// A favorite dragged to another place under the empty field.
    func searchSheet(_ sheet: SearchSheet, didMoveFavoriteFrom source: Int, to destination: Int)
}

/// The sheet that rises with the keyboard: the search field and four suggestions under it.
/// Laid out to `MobileSearchSheet`. While it opens and closes, the field grows out of the bottom
/// bar's pill: `collapsedFieldFrame` is where that pill is, and `openness` runs 0…1.
final class SearchSheet: UIView, UITextFieldDelegate, UIScrollViewDelegate {
    weak var delegate: SearchSheetDelegate?

    let field = SearchField()
    private let surface = UIView()
    /// The 2025 sheet warms a shade toward the keyboard (`Palette.sheetBottom`).
    private let surfaceTint = CAGradientLayer()
    private let surfaceGlow = CAGradientLayer()
    private let fieldBackground = FieldBackgroundView()
    private let clearButton = UIButton(type: .custom)
    private let incognitoButton = UIButton(type: .custom)
    /// Voice search from the field (Arc Search 1.19), left of the incognito eyes while it is empty.
    private let micButton = UIButton(type: .system)
    private let incognitoNote = UILabel()
    private var rowViews: [SuggestionRowView] = []
    /// The rows, scrolling up under the field (`MobileSuggestions.Scroll`).
    private let list = SuggestionListView()
    /// What was typed: the query the rows are for, shown again when the list is back at the top.
    private var typedText = ""
    /// How many rows have gone under the field; the field shows the last of them.
    private var passedRows = 0
    /// Rows in view: four, fewer in landscape (`MobileSearchSheet.rowsInView`).
    var rowsInView = MobileSearchSheet.visibleRows {
        didSet { if rowsInView != oldValue { setNeedsLayout() } }
    }

    /// The pill's frame in this view's coordinates, for the closed end of the morph.
    var collapsedFieldFrame: CGRect = .zero
    /// 0 when closed into the bar, 1 when open. Set inside an animation block, then lay out.
    var openness: CGFloat = 1 { didSet { setNeedsLayout() } }
    /// Whether "Browse for Me" is offered: only where the device's own model can answer.
    var offersBrowseForMe = false { didSet { rowViews.forEach { $0.showsBrowseForMe = offersBrowseForMe } } }
    var isIncognito = false { didSet { applyIncognito() } }

    private(set) var rows: [MobileSuggestions.Row] = []
    /// A site row's icon, by its address.
    var siteIcon: (String) -> UIImage? = { _ in nil }
    /// The favorites shown under the field while it is empty, with their icons.
    private var favorites: [(MobileFavorites.Site, UIImage?)] = []
    /// A favorite being dragged to a new place (TapSmart: favorites can be dragged to reorder):
    /// its picture follows the finger while the rows make room.
    private var dragged: (picture: UIView, from: Int, at: Int, grab: CGFloat)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        surface.backgroundColor = Palette.sheet
        surface.layer.addSublayer(surfaceTint)
        surfaceGlow.type = .radial
        surfaceGlow.startPoint = CGPoint(x: 0.5, y: 0.5)
        surfaceGlow.endPoint = CGPoint(x: 1.05, y: 1.05)
        surface.layer.addSublayer(surfaceGlow)
        surface.layer.masksToBounds = true
        surface.layer.cornerRadius = MobileSearchSheet.cornerRadius
        surface.layer.cornerCurve = .continuous
        surface.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(surface)
        addSubview(fieldBackground)

        field.delegate = self
        field.addTarget(self, action: #selector(textChanged), for: .editingChanged)
        field.accessibilityIdentifier = "search-field"
        addSubview(field)

        clearButton.setImage(Self.clearImage(), for: .normal)
        clearButton.addTarget(self, action: #selector(clearText), for: .touchUpInside)
        clearButton.accessibilityLabel = "Clear text"
        clearButton.accessibilityIdentifier = "search-clear"
        addSubview(clearButton)

        incognitoButton.addTarget(self, action: #selector(toggleIncognito), for: .touchUpInside)
        incognitoButton.accessibilityLabel = "Incognito"
        incognitoButton.accessibilityIdentifier = "search-incognito"
        incognitoButton.semanticContentAttribute = .forceRightToLeft
        incognitoButton.contentHorizontalAlignment = .right
        addSubview(incognitoButton)

        micButton.setImage(UIImage(systemName: "mic", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
        micButton.tintColor = Palette.placeholder
        micButton.accessibilityLabel = "Voice Search"
        micButton.accessibilityIdentifier = "search-voice"
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        addSubview(micButton)

        incognitoNote.text = "You're browsing Incognito"
        incognitoNote.font = .systemFont(ofSize: 17, weight: .medium)
        incognitoNote.textColor = Palette.rgb(0xc9c8cd)
        incognitoNote.textAlignment = .center
        incognitoNote.accessibilityIdentifier = "incognito-note"
        incognitoNote.isHidden = true
        addSubview(incognitoNote)

        list.delegate = self
        list.showsVerticalScrollIndicator = false
        list.alwaysBounceVertical = false
        list.decelerationRate = .fast
        list.clipsToBounds = true
        list.delaysContentTouches = false
        list.accessibilityIdentifier = "suggestion-list"
        addSubview(list)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(favoriteHeld(_:)))
        hold.minimumPressDuration = 0.4
        list.addGestureRecognizer(hold)
        for index in 0..<MobileSearchSheet.listedRows {
            let row = SuggestionRowView()
            row.isHidden = true
            row.accessibilityIdentifier = "suggestion-\(index)"
            row.onPick = { [weak self] in self?.pick(index) }
            row.onBrowseForMe = { [weak self] in self?.browse(index) }
            rowViews.append(row)
            list.addSubview(row)
        }
        applyIncognito()
        updateAccessories()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: Content

    var text: String {
        get { field.text ?? "" }
        set {
            field.text = newValue
            typedText = newValue
            resetScroll()
            updateAccessories()
        }
    }

    func setRows(_ rows: [MobileSuggestions.Row]) {
        self.rows = rows
        resetScroll()
        showRows()
    }

    /// Back to the top, with what was typed in the field.
    private func resetScroll() {
        list.setContentOffset(.zero, animated: false)
        if passedRows > 0 {
            passedRows = 0
            field.text = typedText
        }
    }

    /// The sites kept with "Favorite in App": they fill the rows while nothing is typed.
    func setFavorites(_ favorites: [(MobileFavorites.Site, UIImage?)]) {
        self.favorites = favorites
        showRows()
    }

    private var showsFavorites: Bool { text.isEmpty && !isIncognito }

    private func showRows() {
        let count = showsFavorites ? min(favorites.count, rowsInView) : rows.count
        list.isScrollEnabled = !showsFavorites && count > 1
        list.contentSize = CGSize(width: list.bounds.width, height: showsFavorites ? CGFloat(count) * MobileSearchSheet.rowHeight
            : MobileSuggestions.Scroll.contentHeight(count: count, rowHeight: MobileSearchSheet.rowHeight, visibleHeight: list.bounds.height))
        for (index, view) in rowViews.enumerated() {
            if showsFavorites, index < min(favorites.count, rowsInView) {
                view.configure(favorite: favorites[index].0, icon: favorites[index].1)
                view.isHidden = false
            } else if !showsFavorites, index < rows.count {
                if case .site(let url) = rows[index].kind {
                    view.configure(site: rows[index].text, icon: siteIcon(url))
                } else {
                    view.configure(rows[index])
                }
                view.isHidden = false
            } else {
                view.isHidden = true
            }
        }
    }

    private func pick(_ index: Int) {
        if showsFavorites {
            guard index < favorites.count else { return }
            return delegate?.searchSheet(self, didPickFavorite: favorites[index].0) ?? ()
        }
        guard index < rows.count else { return }
        delegate?.searchSheet(self, didPick: rows[index])
    }

    private func browse(_ index: Int) {
        guard index < rows.count else { return }
        delegate?.searchSheet(self, didAskToBrowseFor: rows[index])
    }

    @objc private func textChanged() {
        typedText = text
        passedRows = 0
        list.setContentOffset(.zero, animated: false)
        updateAccessories()
        delegate?.searchSheet(self, didChangeText: text)
    }

    // MARK: Reordering favorites

    @objc private func favoriteHeld(_ hold: UILongPressGestureRecognizer) {
        let count = min(favorites.count, rowsInView)
        let y = hold.location(in: list).y
        let slot = min(max(0, Int(y / MobileSearchSheet.rowHeight)), max(0, count - 1))
        switch hold.state {
        case .began:
            guard showsFavorites, count > 1, y < CGFloat(count) * MobileSearchSheet.rowHeight else { return }
            let row = rowViews[slot]
            guard let picture = row.snapshotView(afterScreenUpdates: false) else { return }
            picture.frame = row.frame
            picture.layer.shadowColor = UIColor.black.cgColor
            picture.layer.shadowOpacity = 0.18
            picture.layer.shadowRadius = 10
            picture.backgroundColor = Palette.sheet
            list.addSubview(picture)
            row.alpha = 0
            dragged = (picture, slot, slot, y - row.frame.minY)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            UIView.animate(withDuration: 0.15) { picture.transform = CGAffineTransform(scaleX: 1.03, y: 1.03) }
        case .changed:
            guard var drag = dragged else { return }
            drag.picture.frame.origin.y = min(max(0, y - drag.grab), CGFloat(count - 1) * MobileSearchSheet.rowHeight)
            if slot != drag.at {
                favorites.insert(favorites.remove(at: drag.at), at: slot)
                drag.at = slot
                dragged = drag
                showRows()
                for (index, row) in rowViews.enumerated() { row.alpha = index == slot ? 0 : 1 }
                UISelectionFeedbackGenerator().selectionChanged()
            }
        case .ended, .cancelled, .failed:
            guard let drag = dragged else { return }
            dragged = nil
            let target = rowViews[drag.at]
            UIView.animate(withDuration: 0.2) {
                drag.picture.transform = .identity
                drag.picture.frame = target.frame
            } completion: { _ in
                drag.picture.removeFromSuperview()
                target.alpha = 1
            }
            if drag.at != drag.from { delegate?.searchSheet(self, didMoveFavoriteFrom: drag.from, to: drag.at) }
        default: break
        }
    }

    // MARK: Scrolling through the suggestions

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === list, !showsFavorites || passedRows > 0 else { return }
        let passed = MobileSuggestions.Scroll.passedRows(offset: scrollView.contentOffset.y, rowHeight: MobileSearchSheet.rowHeight, count: rows.count)
        guard passed != passedRows else { return }
        passedRows = passed
        // The field takes the row's text with a quick crossfade (Arc Search morphs the changing part).
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.15
        field.layer.add(fade, forKey: "scroll-text")
        field.text = MobileSuggestions.Scroll.fieldText(typed: typedText, rows: rows, offset: scrollView.contentOffset.y, rowHeight: MobileSearchSheet.rowHeight)
        UISelectionFeedbackGenerator().selectionChanged()
        updateAccessories()
    }

    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        guard scrollView === list else { return }
        targetContentOffset.pointee.y = MobileSuggestions.Scroll.restingOffset(targetContentOffset.pointee.y, rowHeight: MobileSearchSheet.rowHeight, count: rows.count)
    }

    @objc private func clearText() {
        text = ""
        setRows([])
        delegate?.searchSheet(self, didChangeText: "")
    }

    @objc private func micTapped() {
        delegate?.searchSheetDidAskForVoice(self)
    }

    @objc private func toggleIncognito() {
        delegate?.searchSheetDidToggleIncognito(self)
    }

    private func updateAccessories() {
        let empty = text.isEmpty
        clearButton.isHidden = empty
        incognitoButton.isHidden = !empty
        micButton.isHidden = !empty || isIncognito
        incognitoNote.isHidden = !(empty && isIncognito)
        showRows()
    }

    /// Incognito turns the sheet dark, names itself beside the mask, and brings the dark keyboard.
    private func applyIncognito() {
        overrideUserInterfaceStyle = isIncognito ? .dark : .unspecified
        incognitoButton.setImage(Self.incognitoImage(on: isIncognito), for: .normal)
        incognitoButton.setAttributedTitle(isIncognito ? NSAttributedString(string: "Incognito    ", attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: Palette.rgb(0xd0d0d4),
        ]) : nil, for: .normal)
        incognitoButton.accessibilityValue = isIncognito ? "On" : "Off"
        let appearance: UIKeyboardAppearance = isIncognito ? .dark : .default
        if field.keyboardAppearance != appearance {
            field.keyboardAppearance = appearance
            field.reloadInputViews()
        }
        updateAccessories()
        setNeedsLayout()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        delegate?.searchSheet(self, didSubmit: text)
        return false
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let t = openness
        surface.frame = bounds
        surface.alpha = t
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surfaceTint.frame = CGRect(x: 0, y: 0, width: bounds.width, height: MobileSearchSheet.height)
        surfaceTint.colors = [Palette.sheet.resolvedColor(with: traitCollection).cgColor,
                              Palette.sheetBottom.resolvedColor(with: traitCollection).cgColor]
        let glow = Palette.sheetGlow.resolvedColor(with: traitCollection)
        surfaceGlow.colors = [glow.cgColor, glow.withAlphaComponent(0).cgColor]
        surfaceGlow.frame = CGRect(x: bounds.width * 0.1, y: MobileSearchSheet.topInset + MobileSearchSheet.fieldHeight,
                                   width: bounds.width * 0.8, height: MobileSearchSheet.height * 0.75)
        CATransaction.commit()

        let open = CGRect(x: MobileSearchSheet.fieldSideInset, y: MobileSearchSheet.topInset,
                          width: bounds.width - 2 * MobileSearchSheet.fieldSideInset, height: MobileSearchSheet.fieldHeight)
        let closed = collapsedFieldFrame.isEmpty ? open : collapsedFieldFrame
        let frame = CGRect(x: closed.minX + (open.minX - closed.minX) * t, y: closed.minY + (open.minY - closed.minY) * t,
                           width: closed.width + (open.width - closed.width) * t,
                           height: closed.height + (open.height - closed.height) * t)
        fieldBackground.frame = frame
        fieldBackground.layer.cornerRadius = frame.height / 2 + (SearchField.cornerRadius - frame.height / 2) * t
        fieldBackground.openness = t

        // Text starts 24.5 pt inside the field; the accessory's centre is 29.5 pt from its right end.
        field.frame = CGRect(x: frame.minX + 24.5, y: frame.minY, width: max(0, frame.width - 24.5 - 52), height: frame.height)
        field.alpha = t
        let accessory = CGRect(x: frame.maxX - 29.5 - 22, y: frame.midY - 22, width: 44, height: 44)
        clearButton.frame = accessory
        // With its "Incognito" label the toggle reaches left from the same right edge.
        incognitoButton.frame = isIncognito ? CGRect(x: accessory.maxX - 11 - 130, y: accessory.minY, width: 130, height: 44) : accessory
        clearButton.alpha = t
        incognitoButton.alpha = t
        micButton.frame = accessory.offsetBy(dx: -38, dy: 0)
        micButton.alpha = t
        // Arc Search's note sits 187 pt below the sheet's top edge.
        incognitoNote.frame = CGRect(x: 0, y: 187 - 12, width: bounds.width, height: 24)
        incognitoNote.alpha = t

        let top = open.maxY + MobileSearchSheet.rowsTopGap
        let listFrame = CGRect(x: 0, y: top, width: bounds.width, height: CGFloat(rowsInView) * MobileSearchSheet.rowHeight)
        if list.frame != listFrame {
            list.frame = listFrame
            showRows()
        }
        list.alpha = t
        for (index, row) in rowViews.enumerated() {
            row.frame = CGRect(x: 0, y: CGFloat(index) * MobileSearchSheet.rowHeight,
                               width: bounds.width, height: MobileSearchSheet.rowHeight)
        }
    }

    // MARK: Glyphs

    /// Arc Search's clear button: an 18 pt tinted disc with a white cross.
    private static func clearImage() -> UIImage {
        let size = CGSize(width: 18, height: 18)
        return UIGraphicsImageRenderer(size: size).image { context in
            Palette.clearFill.setFill()
            context.cgContext.fillEllipse(in: CGRect(origin: .zero, size: size))
            let cross = UIBezierPath()
            cross.move(to: CGPoint(x: 6, y: 6)); cross.addLine(to: CGPoint(x: 12, y: 12))
            cross.move(to: CGPoint(x: 12, y: 6)); cross.addLine(to: CGPoint(x: 6, y: 12))
            cross.lineWidth = 1.7
            cross.lineCapStyle = .round
            Palette.clearCross.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).setStroke()
            cross.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }

    /// The incognito mask: two leaning ovals.
    private static func incognitoImage(on: Bool) -> UIImage {
        let size = CGSize(width: 22, height: 14)
        return UIGraphicsImageRenderer(size: size).image { context in
            let cg = context.cgContext
            (on ? Palette.rgb(0xd8d8dc) : Palette.incognitoOff).setFill()
            for (x, angle) in [(CGFloat(5.5), CGFloat(0.16)), (16.5, -0.16)] {
                cg.saveGState()
                cg.translateBy(x: x, y: 7)
                cg.rotate(by: angle)
                cg.fillEllipse(in: CGRect(x: -4.2, y: -6, width: 8.4, height: 12))
                cg.restoreGState()
            }
        }.withRenderingMode(.alwaysOriginal)
    }
}

/// The search field itself: no border of its own, Arc Search's type and caret.
final class SearchField: UITextField {
    /// The field's corners when open.
    static let cornerRadius: CGFloat = 22

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .systemFont(ofSize: 20, weight: .medium)
        textColor = Palette.primaryText
        tintColor = Palette.accent
        attributedPlaceholder = NSAttributedString(string: "Search...", attributes: [
            .foregroundColor: Palette.placeholder, .font: UIFont.systemFont(ofSize: 20, weight: .regular),
        ])
        keyboardType = .webSearch
        returnKeyType = .go
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartQuotesType = .no
        smartDashesType = .no
        enablesReturnKeyAutomatically = true
        clearButtonMode = .never
        borderStyle = .none
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The field's fill: lavender to pink with a hairline edge when open, the bar pill's fill when
/// closed, so the pill can grow into the field.
final class FieldBackgroundView: UIView {
    private let gradient = CAGradientLayer()
    private let pill = UIView()
    private let plus = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold)))

    var openness: CGFloat = 1 {
        didSet {
            gradient.opacity = Float(openness)
            pill.alpha = 1 - openness
            plus.alpha = 1 - openness
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerCurve = .continuous
        layer.borderWidth = 0.5
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        layer.addSublayer(gradient)
        pill.backgroundColor = Palette.barControlFill
        addSubview(pill)
        plus.tintColor = Palette.glyph
        plus.contentMode = .center
        addSubview(plus)
        applyColors()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FieldBackgroundView, _) in view.applyColors() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradient.frame = bounds
        pill.frame = bounds
        plus.frame = bounds
    }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = [Palette.fieldLeading.resolvedColor(with: traitCollection).cgColor,
                           Palette.fieldTrailing.resolvedColor(with: traitCollection).cgColor]
        layer.borderColor = Palette.fieldBorder.resolvedColor(with: traitCollection).cgColor
        CATransaction.commit()
    }
}

/// The suggestions' scroll view: a drag that starts on a row scrolls instead of picking it
/// (a scroll view leaves controls' touches alone unless told otherwise).
final class SuggestionListView: UIScrollView {
    override func touchesShouldCancel(in view: UIView) -> Bool { true }
}

/// One suggestion: a magnifier, the text with its typed part in grey, and "Browse for Me".
final class SuggestionRowView: UIControl {
    var onPick: (() -> Void)?
    var onBrowseForMe: (() -> Void)?
    var showsBrowseForMe = false { didSet { chip.isHidden = !showsBrowseForMe; setNeedsLayout() } }

    private let icon = UIImageView()
    private let label = UILabel()
    private let chip = UIButton(type: .custom)
    private let pin = UIImageView(image: UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)))
    /// Shows a site's icon (20 pt) in place of a search glyph.
    private var isSite = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.tintColor = Palette.glyph
        icon.contentMode = .center
        addSubview(icon)
        label.lineBreakMode = .byTruncatingTail
        label.isUserInteractionEnabled = false
        addSubview(label)

        chip.setAttributedTitle(NSAttributedString(string: "Browse for Me", attributes: [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: Palette.primaryText,
        ]), for: .normal)
        chip.titleLabel?.lineBreakMode = .byClipping
        chip.backgroundColor = Palette.chipFill
        chip.layer.cornerRadius = 9.5
        chip.layer.cornerCurve = .continuous
        chip.layer.borderWidth = 0.5
        chip.layer.borderColor = Palette.chipBorder.cgColor
        chip.accessibilityIdentifier = "browse-for-me"
        chip.isHidden = true
        chip.addTarget(self, action: #selector(browseTapped), for: .touchUpInside)
        addSubview(chip)

        pin.tintColor = Palette.placeholder
        pin.contentMode = .center
        pin.isHidden = true
        addSubview(pin)

        addTarget(self, action: #selector(tapped), for: .touchUpInside)
        isAccessibilityElement = false
    }

    /// A favorite: its site icon, its title, and the pin at the right.
    func configure(favorite: MobileFavorites.Site, icon image: UIImage?) {
        configure(site: favorite.title, icon: image)
        pin.isHidden = false
    }

    /// A page the phone knows: its site icon and title, one line, no "Browse for Me".
    func configure(site title: String, icon image: UIImage?) {
        icon.image = image ?? UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        icon.contentMode = image == nil ? .center : .scaleAspectFit
        icon.layer.cornerRadius = 4
        icon.clipsToBounds = true
        isSite = true
        label.numberOfLines = 1
        label.attributedText = NSAttributedString(string: title, attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .medium), .foregroundColor: Palette.primaryText,
        ])
        label.accessibilityLabel = title
        chip.isHidden = true
        pin.isHidden = true
        setNeedsLayout()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(_ row: MobileSuggestions.Row) {
        let symbol = row.kind == .address ? "globe" : "magnifyingglass"
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .medium))
        icon.contentMode = .center
        icon.layer.cornerRadius = 0
        isSite = false
        pin.isHidden = true
        // A long suggestion wraps to a second line, as in Arc Search, and is cut after that.
        label.numberOfLines = 2
        let font = UIFont.systemFont(ofSize: 17, weight: .medium)
        let text = NSMutableAttributedString(string: row.text, attributes: [.font: font, .foregroundColor: Palette.primaryText])
        if row.typedPrefixLength > 0 {
            let typed = NSRange(row.text.startIndex..<row.text.index(row.text.startIndex, offsetBy: min(row.typedPrefixLength, row.text.count)), in: row.text)
            text.addAttribute(.foregroundColor, value: Palette.secondaryText, range: typed)
        }
        label.attributedText = text
        label.accessibilityLabel = row.text
        chip.isHidden = !(showsBrowseForMe && row.kind == .search)
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A favorite's site icon is 20 pt; a search row's glyph is centred in the same place.
        icon.frame = isSite ? CGRect(x: 28.8 - 10, y: bounds.midY - 10, width: 20, height: 20)
                            : CGRect(x: 28.8 - 14, y: bounds.midY - 14, width: 28, height: 28)
        pin.frame = CGRect(x: bounds.width - 46, y: bounds.midY - 12, width: 24, height: 24)
        let chipSize = CGSize(width: 100.5, height: 29.5)
        chip.frame = CGRect(x: bounds.width - 17.7 - chipSize.width, y: bounds.midY - chipSize.height / 2,
                            width: chipSize.width, height: chipSize.height)
        let right = !pin.isHidden ? pin.frame.minX - 8 : chip.isHidden ? bounds.width - 18 : chip.frame.minX - 10
        label.frame = CGRect(x: 48.2, y: 0, width: max(0, right - 48.2), height: bounds.height)
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? Palette.barControlFill : .clear }
    }

    @objc private func tapped() { onPick?() }
    @objc private func browseTapped() { onBrowseForMe?() }
}
