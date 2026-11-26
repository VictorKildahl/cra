import CraCore
import UIKit

protocol SearchSheetDelegate: AnyObject {
    func searchSheet(_ sheet: SearchSheet, didChangeText text: String)
    /// The keyboard's Go key.
    func searchSheet(_ sheet: SearchSheet, didSubmit text: String)
    func searchSheet(_ sheet: SearchSheet, didPick row: MobileSuggestions.Row)
    func searchSheet(_ sheet: SearchSheet, didPickRecentTab row: MobileRecentTabs.Row)
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
    /// The mask itself: one set of eyes whose lids blink rather than two swapped pictures.
    private let incognitoEyes = IncognitoEyesView()
    /// The word beside the mask, clipped just left of it so it slides out and back cleanly.
    private let incognitoLabelClip = UIView()
    private let incognitoLabel = UILabel()
    /// Whether the mic is fading back in, so the layout leaves its alpha to that fade.
    private var micIsAppearing = false
    /// Which close the word's fade belongs to, so a faster reopen is not hidden by an older fade.
    private var incognitoLabelHide = 0
    /// Voice search from the field (Arc Search 1.19), left of the incognito eyes while it is empty.
    private let micButton = UIButton(type: .system)
    private let incognitoNote = UILabel()
    private var rowViews: [SuggestionRowView] = []
    /// The rows, scrolling up under the field (`MobileSuggestions.Scroll`).
    private let list = SuggestionListView()
    /// The suggestions' scroll view, which a drag down on the sheet takes over at its top (#623).
    var suggestionList: UIScrollView { list }
    /// What was typed: the query the rows are for, shown again when the list is back at the top.
    private var typedText = ""
    /// How many rows have gone under the field; the field shows the last of them.
    private var passedRows = 0
    /// Rows in view: four, fewer in landscape (`MobileSearchSheet.rowsInView`).
    var rowsInView = MobileSearchSheet.visibleRows {
        didSet { if rowsInView != oldValue { setNeedsLayout() } }
    }

    var sideInsets: (left: CGFloat, right: CGFloat) = (0, 0) { didSet { setNeedsLayout() } }
    /// The pill's frame in this view's coordinates, for the closed end of the morph.
    var collapsedFieldFrame: CGRect = .zero
    /// 0 when closed into the bar, 1 when open. Set inside an animation block, then lay out.
    var openness: CGFloat = 1 { didSet { setNeedsLayout() } }
    /// 0 with the pill closed into a plus, 1 with the field open. A drag up out of the pill keeps
    /// this at 0 until the drawer is let go, whatever `openness` (the drawer's own place) does.
    var fieldOpenness: CGFloat = 1 { didSet { setNeedsLayout() } }
    /// 0 with the suggestions and pinned tabs hidden, 1 with them in. The new tab drawer fades
    /// them in with its own open position; a sheet in place of the page menu follows the field.
    var listOpenness: CGFloat = 1 { didSet { setNeedsLayout() } }
    /// Whether the sheet draws its own surface. The new tab drawer, grown out of the bar, doesn't:
    /// the bar's material carries its background.
    var drawsSurface = true { didSet { setNeedsLayout() } }
    /// The bar under the drawer is a light page's: the closed plus pill takes its light-bar fill,
    /// rim and ink. The open address field keeps its own colour.
    var lightPlusChrome = false {
        didSet {
            guard lightPlusChrome != oldValue else { return }
            fieldBackground.lightPlusChrome = lightPlusChrome
        }
    }
    /// The address field's colour over the drawer: none in the page menu's sheet, a white lift over
    /// a light page, and a softer one over a dark page.
    enum FieldStyle: Equatable { case standard, lightPage, darkPage }

    /// How the open address field sits on the drawer.
    var fieldStyle: FieldStyle = .standard {
        didSet {
            guard fieldStyle != oldValue else { return }
            fieldBackground.fieldStyle = fieldStyle
            field.lightPageField = fieldStyle == .lightPage
            micButton.tintColor = fieldStyle == .lightPage ? Palette.fieldLightPageInk : Palette.placeholder
            incognitoNote.textColor = fieldStyle == .lightPage ? Palette.secondaryText : Palette.rgb(0xc9c8cd)
            applyIncognito()
        }
    }
    /// Whether "Browse for Me" is offered: only where the device's own model can answer.
    var offersBrowseForMe = false { didSet { rowViews.forEach { $0.showsBrowseForMe = offersBrowseForMe } } }
    var isIncognito = false {
        didSet {
            applyIncognito()
            // Snaps for a sheet being prepared; during the toggle the eyes have already moved.
            incognitoEyes.setClosed(isIncognito, animated: false)
        }
    }

    private(set) var rows: [MobileSuggestions.Row] = []
    /// A site row's icon, by its address.
    var siteIcon: (String) -> UIImage? = { _ in nil }
    /// The favorites shown under the field while it is empty, with their icons.
    private var favorites: [(MobileFavorites.Site, UIImage?)] = []
    private var recentTabs: [(MobileRecentTabs.Row, UIImage?)] = []
    /// Sample questions for someone new, in place of favorites while there are none.
    private var starters: [MobileSuggestions.Row] = []
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
        incognitoButton.addTarget(self, action: #selector(incognitoPressed), for: .touchDown)
        incognitoButton.addTarget(self, action: #selector(incognitoReleased),
                                  for: [.touchUpInside, .touchUpOutside, .touchCancel])
        incognitoButton.accessibilityLabel = "Incognito"
        incognitoButton.accessibilityIdentifier = "search-incognito"
        // The word sits in the field's own space, above the mic and under the mask, so it slides
        // over the mic and under the icon rather than following the toggle's width.
        incognitoLabelClip.clipsToBounds = true
        incognitoLabelClip.isUserInteractionEnabled = false
        incognitoLabelClip.isAccessibilityElement = false
        incognitoLabel.isHidden = true
        incognitoLabelClip.addSubview(incognitoLabel)
        incognitoButton.addSubview(incognitoEyes)

        micButton.setImage(UIImage(systemName: "mic", withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium)), for: .normal)
        micButton.tintColor = Palette.placeholder
        micButton.accessibilityLabel = "Voice Search"
        micButton.accessibilityIdentifier = "search-voice"
        micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        addSubview(micButton)

        addSubview(incognitoLabelClip)
        addSubview(incognitoButton)

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

    func refreshRows() { showRows() }

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

    func setRecentTabs(_ rows: [(MobileRecentTabs.Row, UIImage?)]) {
        recentTabs = rows
        showRows()
    }

    private var showsFavorites: Bool { text.isEmpty && !isIncognito }
    /// Starter questions stand where favorites go, when there are none.
    private var showsStarters: Bool { showsFavorites && favorites.isEmpty && !starters.isEmpty }

    /// Where the coach mark points: the top centre of the first starter question's Browse for Me
    /// chip, and the field's frame, in this view; nil when the coach mark has nothing to show.
    var coachTarget: (chipTop: CGPoint, field: CGRect)? {
        guard MobileCoachMark.shows(startersShown: showsStarters, offersBrowseForMe: offersBrowseForMe),
              let first = rowViews.first, !first.isHidden else { return nil }
        let chip = first.convert(first.chipFrame, to: self)
        return (CGPoint(x: chip.midX, y: chip.minY), fieldBackground.frame)
    }

    func setStarters(_ rows: [MobileSuggestions.Row]) {
        starters = rows
        showRows()
    }

    private func showRows() {
        let favoriteCount = min(favorites.count, rowsInView)
        let count = showsFavorites ? (showsStarters ? min(starters.count, rowsInView) : favoriteCount + recentTabs.count) : rows.count
        list.isScrollEnabled = showsFavorites ? !showsStarters && count > rowsInView : count > 1
        list.contentSize = CGSize(width: list.bounds.width, height: showsFavorites ? CGFloat(count) * MobileSearchSheet.rowHeight
            : MobileSuggestions.Scroll.contentHeight(count: count, rowHeight: MobileSearchSheet.rowHeight, visibleHeight: list.bounds.height))
        for (index, view) in rowViews.enumerated() {
            if showsStarters {
                if index < min(starters.count, rowsInView) {
                    view.configure(starters[index])
                    view.emphasizesChip = index == 0
                    view.isHidden = false
                } else {
                    view.isHidden = true
                }
                continue
            }
            view.emphasizesChip = false
            if showsFavorites, index < min(favorites.count, rowsInView) {
                view.configure(favorite: favorites[index].0, icon: favorites[index].1)
                view.isHidden = false
            } else if showsFavorites, index - favoriteCount < recentTabs.count {
                let recent = recentTabs[index - favoriteCount]
                view.configure(site: recent.0.title, icon: recent.1)
                view.isHidden = false
            } else if !showsFavorites, index < rows.count {
                if case .site(let url) = rows[index].kind {
                    view.configure(site: rows[index].text, icon: siteIcon(url), place: rows[index].place)
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
        if showsStarters {
            guard index < starters.count else { return }
            return delegate?.searchSheet(self, didPick: starters[index]) ?? ()
        }
        if showsFavorites {
            let favoriteCount = min(favorites.count, rowsInView)
            if index < favoriteCount { return delegate?.searchSheet(self, didPickFavorite: favorites[index].0) ?? () }
            let recentIndex = index - favoriteCount
            guard recentIndex < recentTabs.count else { return }
            return delegate?.searchSheet(self, didPickRecentTab: recentTabs[recentIndex].0) ?? ()
        }
        guard index < rows.count else { return }
        delegate?.searchSheet(self, didPick: rows[index])
    }

    private func browse(_ index: Int) {
        let list = showsStarters ? starters : rows
        guard index < list.count else { return }
        delegate?.searchSheet(self, didAskToBrowseFor: list[index])
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
        guard scrollView === list, !showsFavorites else { return }
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

    @objc private func incognitoPressed() {
        incognitoEyes.setPupilsDown(true)
    }

    @objc private func incognitoReleased() {
        incognitoEyes.setPupilsDown(false)
    }

    private func updateAccessories() {
        let empty = text.isEmpty
        clearButton.isHidden = empty
        incognitoButton.isHidden = !empty
        incognitoLabelClip.isHidden = !empty
        // On comes in a blink, so the mic goes at once. Off, it comes back with the word's slide.
        let micShown = empty && !isIncognito
        if micShown {
            if micButton.isHidden {
                // A beat after the word starts leaving, then from nothing: no opacity, a little
                // small, both coming in over the spring's scale.
                micIsAppearing = true
                DispatchQueue.main.asyncAfter(deadline: .now() + MobileSearchMotion.micReturnDelay) { [weak self] in
                    guard let self, self.micIsAppearing, self.micButton.isHidden,
                          !self.isIncognito, self.text.isEmpty else { return }
                    self.micButton.layer.removeAllAnimations()
                    self.micButton.alpha = 0
                    self.micButton.transform = CGAffineTransform(scaleX: 0.7, y: 0.7)
                    self.micButton.isHidden = false
                    UIView.animate(spring: MobileMotion.micAppear) {
                        self.micButton.transform = .identity
                    }
                    UIView.animate(withDuration: MobileSearchMotion.micFade, delay: 0,
                                   options: [.beginFromCurrentState, .allowUserInteraction]) {
                        self.micButton.alpha = 1
                    } completion: { _ in
                        self.micIsAppearing = false
                    }
                }
            }
        } else {
            micIsAppearing = false
            micButton.isHidden = true
            micButton.alpha = 0
            micButton.transform = .identity
        }
        incognitoNote.isHidden = !(empty && isIncognito)
        showRows()
    }

    /// Switches the sheet's incognito look. The look itself changes at once; the mask's lids
    /// and the word are what move, so the sheet is not crossfaded over the toggle.
    func setIncognito(_ on: Bool) {
        // On, the mic goes at once. Off, it comes back as the word goes, together.
        if on { micButton.isHidden = true }
        incognitoEyes.setClosed(on, animated: true)
        isIncognito = on
        // The word's place is settled before it starts to move.
        layoutIfNeeded()
        animateIncognitoLabel()
    }

    /// Fades the word out as the new tab drawer closes, with the bar's incognito tint, and leaves
    /// it hidden for the next, normal search. `animated: false` is for a word that has already
    /// finished its slide.
    func hideIncognitoLabel(animated: Bool = true) {
        incognitoLabelHide += 1
        let token = incognitoLabelHide
        incognitoLabel.layer.removeAnimation(forKey: "slide")
        incognitoLabel.layer.removeAnimation(forKey: "fade")
        guard !incognitoLabel.isHidden else {
            resetIncognitoLabel()
            return
        }
        guard animated else {
            resetIncognitoLabel()
            return
        }
        UIView.animate(withDuration: MobileSearchMotion.incognitoCloseFade, delay: 0,
                       options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut]) {
            self.incognitoLabel.alpha = 0
        } completion: { [weak self] _ in
            guard let self, self.incognitoLabelHide == token else { return }
            self.resetIncognitoLabel()
        }
    }

    /// Leaves the word at its resting place, out of sight.
    private func resetIncognitoLabel() {
        incognitoLabel.isHidden = true
        incognitoLabel.layer.transform = CATransform3DIdentity
        incognitoLabel.alpha = 1
    }

    /// One slide of the word, from `from` to `to`, on the label's own layer.
    private func slideIncognitoLabel(from: CATransform3D, to: CATransform3D,
                                    duration: TimeInterval, timing: CAMediaTimingFunction) {
        let slide = CABasicAnimation(keyPath: "transform")
        slide.fromValue = NSValue(caTransform3D: from)
        slide.toValue = NSValue(caTransform3D: to)
        slide.duration = duration
        slide.timingFunction = timing
        incognitoLabel.layer.add(slide, forKey: "slide")
    }

    /// Shows the word beside the mask, or slides it away: on, it slides out from under the mask;
    /// off, it slides back under it, fading only once most of the way there. The slide is on the
    /// label's layer, so a layout during it cannot take the word back to its place.
    private func animateIncognitoLabel() {
        incognitoLabelHide += 1
        let duration = MobileSearchMotion.incognitoLabelSlide
        let hidden = CATransform3DMakeTranslation(incognitoLabel.bounds.width + MobileSearchSheet.incognitoLabelGap, 0, 0)
        let visible = CATransform3DIdentity
        let timing = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
        incognitoLabel.layer.removeAnimation(forKey: "slide")
        incognitoLabel.layer.removeAnimation(forKey: "fade")
        guard !isHidden else {
            incognitoLabel.isHidden = !isIncognito
            incognitoLabel.layer.transform = isIncognito ? visible : hidden
            incognitoLabel.alpha = 1
            return
        }
        if isIncognito {
            incognitoLabel.isHidden = false
            incognitoLabel.alpha = 1
            incognitoLabel.layer.transform = visible
            slideIncognitoLabel(from: hidden, to: visible, duration: duration, timing: timing)
            return
        }
        incognitoLabel.alpha = 0
        incognitoLabel.layer.transform = hidden
        slideIncognitoLabel(from: visible, to: hidden, duration: duration, timing: timing)
        // The word stays solid to most of the way under the mask, then goes.
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 1
        fade.toValue = 0
        fade.beginTime = CACurrentMediaTime() + duration * 0.6
        fade.duration = duration * 0.4
        fade.fillMode = .backwards
        incognitoLabel.layer.add(fade, forKey: "fade")
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            guard let self, !self.isIncognito else { return }
            self.hideIncognitoLabel(animated: false)
        }
    }

    /// Incognito turns the sheet dark, names itself beside the mask, and brings the dark keyboard.
    private func applyIncognito() {
        overrideUserInterfaceStyle = isIncognito ? .dark : .unspecified
        incognitoEyes.lightPageField = fieldStyle == .lightPage
        incognitoLabel.attributedText = Self.incognitoTitle(lightPageField: fieldStyle == .lightPage)
        incognitoButton.accessibilityValue = isIncognito ? "On" : "Off"
        // A sheet being prepared is not the toggle's animated change: the word is just there or
        // not.
        if isHidden {
            incognitoLabelHide += 1
            incognitoLabel.isHidden = !isIncognito
            incognitoLabel.transform = .identity
            incognitoLabel.alpha = 1
        }
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

    /// The openness the last layout was for: where an animated move starts (`fade`).
    private var laidOutOpenness: CGFloat?
    /// The field's own openness the last layout was for; it moves on its own when a pull up keeps
    /// the plus closed until the drawer is let go.
    private var laidOutFieldOpenness: CGFloat?

    /// Sets `views`' alpha for openness `t`, faded over `span` of it. In an animated move from another openness the fade
    /// takes its own part of the move (`MobileSearchMotion.fadeWindow`): UIKit would otherwise run every alpha from
    /// start to end with the whole move, a solid surface's included.
    private func fade(_ views: [UIView], over span: ClosedRange<CGFloat>, from start: CGFloat, to t: CGFloat) {
        let alpha = MobileSearchMotion.opacity(openness: t, over: span)
        let duration = UIView.inheritedAnimationDuration
        guard duration > 0, start != t else {
            views.forEach { $0.alpha = alpha }
            return
        }
        let window = MobileSearchMotion.fadeWindow(from: start, to: t, over: span)
        UIView.animate(withDuration: duration * (window.upperBound - window.lowerBound), delay: duration * window.lowerBound,
                       options: [.overrideInheritedDuration, .overrideInheritedCurve, .curveLinear, .beginFromCurrentState]) {
            views.forEach { $0.alpha = alpha }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let t = openness
        let start = laidOutOpenness ?? t
        laidOutOpenness = t
        let morph = fieldOpenness
        let fieldStart = laidOutFieldOpenness ?? morph
        laidOutFieldOpenness = morph
        surface.frame = bounds
        if drawsSurface {
            fade([surface], over: MobileSearchMotion.surfaceSpan, from: start, to: t)
        } else {
            // The bar's material carries the background: the sheet's own surface stays out of it.
            surface.alpha = 0
        }
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

        let open = MobileSearchSheet.openFieldFrame(width: bounds.width, sideInsets: sideInsets)
        let closed = collapsedFieldFrame.isEmpty ? open : collapsedFieldFrame
        let frame = CGRect(x: closed.minX + (open.minX - closed.minX) * morph,
                           y: closed.minY + (open.minY - closed.minY) * morph,
                           width: closed.width + (open.width - closed.width) * morph,
                           height: closed.height + (open.height - closed.height) * morph)
        fieldBackground.frame = frame
        fieldBackground.layer.cornerRadius = frame.height / 2
        fieldBackground.openness = morph
        // The pill's plus keeps to the leading end as it grows, the placeholder coming in to its right (Arc Search).
        fieldBackground.plusCenter = MobileSearchMotion.plusCenter(closedWidth: closed.width, openness: morph)

        // Text starts 24.5 pt inside the open field; the accessory's centre is 29.5 pt from its right end.
        let textInset = MobileSearchMotion.textInset(closedWidth: closed.width, openness: morph)
        field.frame = CGRect(x: frame.minX + textInset, y: frame.minY, width: max(0, frame.width - textInset - 52), height: frame.height)
        field.alpha = morph
        let accessory = MobileSearchSheet.accessoryFrame(field: frame)
        clearButton.frame = accessory
        // Off or with its "Incognito" label, the toggle's glyph keeps one place (#654).
        incognitoButton.frame = MobileSearchSheet.incognitoToggleFrame(
            field: frame, labelledWidth: isIncognito ? MobileSearchSheet.incognitoLabelledWidth : nil)
        // The mask sits at the button's right edge. The word's window is the field's, anchored to
        // the mask's left edge rather than to the toggle's own width, so the toggle narrowing
        // behind it cannot move it.
        let mask = IncognitoEyesView.size
        incognitoEyes.frame = CGRect(x: incognitoButton.bounds.width - mask.width,
                                     y: incognitoButton.bounds.midY - mask.height / 2,
                                     width: mask.width, height: mask.height)
        let labelArea = MobileSearchSheet.incognitoLabelledWidth - mask.width
        // Anchored to the open field's right end and the mask's width, not to the toggle's frame
        // or the field's current morph: the word must not move as either changes.
        let fieldRight = MobileSearchSheet.openFieldFrame(width: bounds.width, sideInsets: sideInsets).maxX
        let iconLeft = fieldRight - MobileSearchSheet.incognitoTrailingInset - mask.width
        // The clip stops 2 pt left of the icon, so the word goes just up to it rather than under it.
        incognitoLabelClip.frame = CGRect(x: iconLeft - labelArea, y: incognitoButton.frame.minY,
                                          width: labelArea - 2, height: incognitoButton.frame.height)
        let labelSize = incognitoLabel.sizeThatFits(CGSize(width: 1000, height: incognitoLabelClip.bounds.height))
        // Bounds and centre, not frame: the label carries its slide as a transform, and a frame set
        // on a transformed layer shifts it by the transform, which made the word jump mid-slide.
        incognitoLabel.bounds = CGRect(origin: .zero, size: labelSize)
        incognitoLabel.center = CGPoint(x: labelArea - MobileSearchSheet.incognitoLabelGap - labelSize.width / 2,
                                        y: incognitoLabelClip.bounds.midY)
        micButton.frame = accessory.offsetBy(dx: -40, dy: 0)
        fade([clearButton, incognitoButton], over: MobileSearchMotion.accessorySpan, from: fieldStart, to: morph)
        if !micIsAppearing {
            fade([micButton], over: MobileSearchMotion.accessorySpan, from: fieldStart, to: morph)
        }
        // Arc Search's note sits 187 pt below the sheet's top edge.
        incognitoNote.frame = CGRect(x: 0, y: 187 - 12, width: bounds.width, height: 24)
        incognitoNote.alpha = morph

        let top = open.maxY + MobileSearchSheet.rowsTopGap
        let listFrame = CGRect(x: 0, y: top, width: bounds.width, height: CGFloat(rowsInView) * MobileSearchSheet.rowHeight)
        if list.frame != listFrame {
            list.frame = listFrame
            showRows()
        }
        list.alpha = listOpenness
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

    /// "Incognito" beside the mask while it is on: 13 pt grey (Victor's screenshot IMG_1905: the
    /// word 51.6 pt wide in #9C9B9D). Its gap to the mask is `incognitoLabelGap`.
    private static func incognitoTitle(lightPageField: Bool) -> NSAttributedString {
        let ink = lightPageField ? Palette.fieldLightPageInk : Palette.placeholder
        return NSAttributedString(string: "Incognito", attributes: [
            .font: UIFont.systemFont(ofSize: 13), .foregroundColor: ink,
        ])
    }
}

/// The incognito mask: two hollow eggs leaning in, a pupil in each, and eyelids that fill them.
/// Turning incognito on drops the lids over the eyes; turning it off lifts them away.
final class IncognitoEyesView: UIView {
    /// The drawing's own canvas.
    static let size = CGSize(width: 28, height: 17)
    /// Where each egg sits across the canvas, and how far it leans.
    private static let eggs: [(x: CGFloat, angle: CGFloat)] = [(7, 0.16), (21, -0.16)]
    private static let eggSize = CGSize(width: 11.8, height: 14.2)
    /// The pupils look a little to the left; closing moves them 1 pt right.
    private static let pupilLook = CGPoint(x: -2, y: 0)
    private static let pupilDiameter: CGFloat = 6
    /// How far the pupils dip while the toggle is held.
    private static let pupilNudge: CGFloat = 0.7
    /// With the eyes shut the pupils sit 1 pt right of their open look, a straight move.
    private static let pupilClosed = CGPoint(x: pupilLook.x + 1, y: pupilLook.y)
    /// The eye's rim.
    private static let rimWidth: CGFloat = 1.5

    private let outline = CAShapeLayer()
    private let pupils = CAShapeLayer()
    /// Each eye's filled egg over its pupil, revealed by its own mask. The right eye's lid waits
    /// a moment, so the blink rolls across the pair.
    private let lids = [CAShapeLayer(), CAShapeLayer()]
    private let lidMasks = [CALayer(), CALayer()]
    private var shapes: [CAShapeLayer] { [outline, pupils] + lids }
    /// Which blink the pending right lid belongs to: a new toggle cancels an older one's start,
    /// so repeated presses cannot stack the delay.
    private var blinkGeneration = 0
    private var pupilsDown = false
    /// Whether the lids are over the eyes.
    private(set) var closed = false

    /// The light-page field's lighter ink, rather than the microphone's grey.
    var lightPageField = false {
        didSet {
            guard lightPageField != oldValue else { return }
            applyInk()
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        for shape in shapes {
            shape.frame = bounds
            layer.addSublayer(shape)
        }
        outline.fillColor = UIColor.clear.cgColor
        outline.lineWidth = Self.rimWidth
        // The lids are the eggs filled in, each with a mask that comes down over it. Its height
        // is the lid's own state, set by `setClosed`; layout leaves it alone.
        for (lid, mask) in zip(lids, lidMasks) {
            mask.bounds = CGRect(x: 0, y: 0, width: Self.size.width, height: 0)
            mask.backgroundColor = UIColor.black.cgColor
            mask.anchorPoint = .zero
            lid.mask = mask
        }
        applyInk()
        // The eyes start looking to the lower left, not straight ahead.
        pupils.transform = CATransform3DMakeTranslation(Self.pupilLook.x, Self.pupilLook.y, 0)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: IncognitoEyesView, _) in view.applyInk() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let canvas = CGRect(origin: .zero, size: Self.size)
        // Bounds and position, not frame: the pupils carry their look as a transform, and a
        // layer's frame is its transformed bounds, which would undo that look.
        for shape in shapes {
            shape.bounds = CGRect(origin: .zero, size: canvas.size)
            shape.position = CGPoint(x: canvas.midX, y: canvas.midY)
        }
        outline.path = eggPath(Self.eggs, expandedBy: 0).cgPath
        pupils.path = pupilPath()
        for (index, lid) in lids.enumerated() {
            lid.path = eggPath([Self.eggs[index]], expandedBy: Self.rimWidth / 2).cgPath
        }
    }

    /// Drops the lids over the eyes, or lifts them away. The right eye starts a moment after the
    /// left one, and the pupils move 1 pt right as they close, with no dip from the press. A new
    /// toggle cancels a pending right lid, so the wait never stacks.
    func setClosed(_ closed: Bool, animated: Bool) {
        guard closed != self.closed else { return }
        self.closed = closed
        // The press is over: the close moves straight across, not from the dip.
        pupilsDown = false
        blinkGeneration += 1
        let generation = blinkGeneration
        movePupils(duration: MobileSearchMotion.incognitoBlink, animated: animated)
        let height = closed ? Self.size.height : 0
        moveLid(0, to: height, animated: animated, generation: generation)
        if animated {
            DispatchQueue.main.asyncAfter(deadline: .now() + MobileSearchMotion.incognitoBlinkStagger) { [weak self] in
                self?.moveLid(1, to: height, animated: true, generation: generation)
            }
        } else {
            moveLid(1, to: height, animated: false, generation: generation)
        }
    }

    /// A small dip of the pupils while the toggle is held.
    func setPupilsDown(_ down: Bool) {
        guard down != pupilsDown else { return }
        pupilsDown = down
        movePupils(duration: 0.1, animated: true)
    }

    private func moveLid(_ index: Int, to height: CGFloat, animated: Bool, generation: Int) {
        guard generation == blinkGeneration else { return }
        let mask = lidMasks[index]
        let from = mask.presentation()?.bounds.height ?? mask.bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.bounds = CGRect(x: 0, y: 0, width: Self.size.width, height: height)
        CATransaction.commit()
        guard animated, window != nil else { return }
        let animation = CABasicAnimation(keyPath: "bounds.size.height")
        animation.fromValue = from
        animation.toValue = height
        animation.duration = MobileSearchMotion.incognitoBlink
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.15, 1)
        mask.add(animation, forKey: "blink")
    }

    /// In the middles when the eyes close, looking to the lower left while they are open; a held
    /// button dips them.
    /// The pupils look a little left with the eyes open; they move 1 pt right as the eyes
    /// shut and back as they open. A held button dips them.
    private func movePupils(duration: TimeInterval, animated: Bool) {
        let rest = closed ? Self.pupilClosed : Self.pupilLook
        let target = CATransform3DMakeTranslation(rest.x, rest.y + (pupilsDown ? Self.pupilNudge : 0), 0)
        let from = pupils.presentation()?.transform ?? pupils.transform
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pupils.transform = target
        CATransaction.commit()
        guard animated, window != nil else { return }
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: from)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.15, 1)
        pupils.add(animation, forKey: "pupils")
    }

    private func applyInk() {
        let ink = (lightPageField ? Palette.fieldLightPageInk : Palette.placeholder)
            .resolvedColor(with: traitCollection)
        outline.strokeColor = ink.cgColor
        pupils.fillColor = ink.cgColor
        for lid in lids { lid.fillColor = ink.cgColor }
    }

    /// The eggs, each leaning in from its middle; `grow` covers the rim's own width.
    private func eggPath(_ eggs: [(x: CGFloat, angle: CGFloat)], expandedBy grow: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        for egg in eggs {
            let rect = CGRect(x: -Self.eggSize.width / 2 - grow, y: -Self.eggSize.height / 2 - grow,
                              width: Self.eggSize.width + grow * 2, height: Self.eggSize.height + grow * 2)
            let oval = UIBezierPath(ovalIn: rect)
            oval.apply(CGAffineTransform(translationX: egg.x, y: bounds.midY).rotated(by: egg.angle))
            path.append(oval)
        }
        return path
    }

    private func pupilPath() -> CGPath {
        let path = UIBezierPath()
        for egg in Self.eggs {
            let rect = CGRect(x: -Self.pupilDiameter / 2, y: -Self.pupilDiameter / 2,
                              width: Self.pupilDiameter, height: Self.pupilDiameter)
            let pupil = UIBezierPath(ovalIn: rect)
            // The pupil's place in the eye is its layer's; the path is the middle.
            pupil.apply(CGAffineTransform(translationX: egg.x, y: bounds.midY).rotated(by: egg.angle))
            path.append(pupil)
        }
        return path.cgPath
    }
}

/// The search field itself: no border of its own, Arc Search's type and caret.
final class SearchField: UITextField {
    /// The light-page address field: the placeholder and icons take its light ink, while the
    /// typed text stays darker for reading.
    var lightPageField = false { didSet { if lightPageField != oldValue { applyInk() } } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        // Follows the phone's text size up to a point the 48 pt field still holds (1.22.2).
        font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 20, weight: .medium), maximumPointSize: 26)
        adjustsFontForContentSizeCategory = true
        tintColor = Palette.accent
        applyInk()
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

    private func applyInk() {
        textColor = lightPageField ? Palette.fieldLightPageText : Palette.primaryText
        attributedPlaceholder = NSAttributedString(string: "Search...", attributes: [
            .foregroundColor: lightPageField ? Palette.fieldLightPageInk : Palette.placeholder,
            .font: UIFont.systemFont(ofSize: 20, weight: .regular),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

/// The field's fill: lavender to pink with a hairline edge when open, the bar pill's fill when
/// closed, so the pill can grow into the field.
final class FieldBackgroundView: UIView {
    private let gradient = CAGradientLayer()
    private let pill = UIView()
    private let plus = UIImageView(image: UIImage(systemName: "plus", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .semibold)))

    var openness: CGFloat = 1 {
        didSet {
            gradient.opacity = Float(openness)
            pill.alpha = 1 - openness
            plus.alpha = 1 - openness
            applyBorder()
        }
    }
    /// The plus's centre, from the left end (`MobileSearchMotion.plusCenter`).
    var plusCenter: CGFloat = 0 { didSet { if plusCenter != oldValue { setNeedsLayout() } } }
    /// The bar behind the drawer is a light page's: the closed plus pill takes the light bar's fill,
    /// rim and ink.
    var lightPlusChrome = false { didSet { if lightPlusChrome != oldValue { applyColors(animated: true) } } }
    /// The address field's colour over the drawer: none in the page menu's sheet, a white lift
    /// over a light page, and a softer one over a dark page.
    var fieldStyle: SearchSheet.FieldStyle = .standard {
        didSet { if fieldStyle != oldValue { applyColors(animated: true) } }
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
        pill.layer.borderWidth = 0.5
        pill.layer.cornerCurve = .continuous
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
        pill.layer.cornerRadius = layer.cornerRadius
        plus.frame = CGRect(x: plusCenter - bounds.height / 2, y: 0, width: bounds.height, height: bounds.height)
    }

    /// A style change comes in with the drawer's own material fade, so the plus and field change
    /// over without a snap.
    private func applyColors(animated: Bool) {
        guard animated else {
            applyColors()
            return
        }
        UIView.transition(with: self, duration: MobileSearchMotion.drawerMaterialFade,
                          options: [.transitionCrossDissolve, .allowUserInteraction]) {
            self.applyColors()
        }
    }

    private func applyColors() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let lift: CGFloat?
        switch fieldStyle {
        case .standard: lift = nil
        case .lightPage: lift = MobileBottomBar.fieldLightPageWhite
        case .darkPage: lift = MobileBottomBar.fieldDarkPageWhite
        }
        if let lift {
            // Over the drawer, a little white makes the field a shade lighter than the surface
            // behind it rather than a fixed colour.
            let white = UIColor.white.withAlphaComponent(lift)
            gradient.colors = [white.cgColor, white.cgColor]
        } else {
            gradient.colors = [Palette.fieldLeading.resolvedColor(with: traitCollection).cgColor,
                               Palette.fieldTrailing.resolvedColor(with: traitCollection).cgColor]
        }
        pill.backgroundColor = lightPlusChrome ? Palette.lightBarControlFill : Palette.barControlFill
        pill.layer.borderColor = (lightPlusChrome ? Palette.lightBarBorder : Palette.barControlBorder)
            .resolvedColor(with: traitCollection).cgColor
        plus.tintColor = lightPlusChrome ? Palette.lightBarGlyph : Palette.glyph
        applyBorder()
        CATransaction.commit()
    }

    /// The field's hairline edge belongs to the open field. It goes as soon as the field starts
    /// back into the pill, so shrinking into the bar leaves no dark rim.
    private func applyBorder() {
        let alpha = max(0, min(1, (openness - 0.98) / 0.02))
        layer.borderColor = Palette.raisedHairline
            .withAlphaComponent(Palette.raisedHairlineOpacity * alpha).cgColor
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
    /// The first starter question's chip is filled blue, as in Arc Search's first-run picture.
    var emphasizesChip = false {
        didSet {
            guard emphasizesChip != oldValue else { return }
            chip.backgroundColor = emphasizesChip ? Palette.accent : Palette.chipFill
            chip.setAttributedTitle(NSAttributedString(string: "Browse for Me", attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: emphasizesChip ? UIColor.white : Palette.primaryText,
            ]), for: .normal)
        }
    }

    private let icon = UIImageView()
    private let label = UILabel()
    private let placeLabel = UILabel()
    private let chip = UIButton(type: .custom)
    var chipFrame: CGRect { chip.frame }
    private let pin = UIImageView(image: UIImage(systemName: "pin.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .regular)))
    /// Shows a site's icon (20 pt) in place of a search glyph.
    private var isSite = false
    /// 17 pt, following the phone's text size up to what two lines in a 56 pt row hold.
    static var textFont: UIFont {
        UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 17, weight: .medium), maximumPointSize: 21)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        icon.tintColor = Palette.glyph
        icon.contentMode = .center
        addSubview(icon)
        label.lineBreakMode = .byTruncatingTail
        label.isUserInteractionEnabled = false
        addSubview(label)
        addSubview(placeLabel)
        placeLabel.isHidden = true
        placeLabel.lineBreakMode = .byTruncatingTail

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
    func configure(site title: String, icon image: UIImage?, place: MobileSuggestions.Place? = nil) {
        icon.image = image ?? UIImage(systemName: "globe", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular))
        icon.contentMode = image == nil ? .center : .scaleAspectFit
        icon.layer.cornerRadius = 4
        icon.clipsToBounds = true
        isSite = true
        label.numberOfLines = 1
        label.attributedText = NSAttributedString(string: title, attributes: [
            .font: SuggestionRowView.textFont, .foregroundColor: Palette.primaryText,
        ])
        label.accessibilityLabel = title
        placeLabel.isHidden = place == nil
        if let place {
            let font = UIFontMetrics(forTextStyle: .caption1).scaledFont(for: .systemFont(ofSize: 13), maximumPointSize: 16)
            let line = NSMutableAttributedString(string: place.prefix, attributes: [.font: font, .foregroundColor: Palette.secondaryText])
            line.append(NSAttributedString(string: place.space, attributes: [.font: font, .foregroundColor: Palette.primaryText]))
            placeLabel.attributedText = line
            placeLabel.accessibilityLabel = place.prefix + place.space
        }
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
        placeLabel.isHidden = true
        pin.isHidden = true
        // A long suggestion wraps to a second line, as in Arc Search, and is cut after that.
        label.numberOfLines = 2
        let font = SuggestionRowView.textFont
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
        let width = max(0, right - 48.2)
        if placeLabel.isHidden {
            label.frame = CGRect(x: 48.2, y: 0, width: width, height: bounds.height)
        } else {
            let titleHeight = SuggestionRowView.textFont.lineHeight
            let placeHeight = placeLabel.attributedText?.attribute(.font, at: 0, effectiveRange: nil).flatMap { ($0 as? UIFont)?.lineHeight } ?? 16
            let top = (bounds.height - titleHeight - placeHeight) / 2
            label.frame = CGRect(x: 48.2, y: top, width: width, height: titleHeight)
            placeLabel.frame = CGRect(x: 48.2, y: top + titleHeight, width: width, height: placeHeight)
        }
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? Palette.barControlFill : .clear }
    }

    @objc private func tapped() { onPick?() }
    @objc private func browseTapped() { onBrowseForMe?() }
}
