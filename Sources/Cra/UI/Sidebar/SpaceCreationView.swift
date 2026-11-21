import AppKit
import SwiftUI

/// Arc's "Create a Space" page in the sidebar (CraCore's SpaceCreationDraft, SpaceCreationLayout and
/// SpaceCreationAnimation; docs/arc-parity.md, "Create a Space"): a picture, a title, the name
/// field with its icon button, the Profile and Choose a Theme rows, Cra's own Search Engine row
/// (#306), and Create Space and Cancel at the bottom. It edits the window's draft and makes
/// nothing itself.
@MainActor
final class SpaceCreationView: NSView, NSTextFieldDelegate, NSPopoverDelegate {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let picture = SpaceCreationPicture()
    private let title = NSTextField(labelWithString: "Create a Space")
    private let subtitle = NSTextField(wrappingLabelWithString: "Separate your tabs for life,\nwork, projects, and more.")
    private let fieldBox = NSView()
    private let iconButton = SpaceCreationIconButton()
    private let name = NSTextField()
    private let profileRow = SpaceCreationRow(symbol: "face.smiling", label: "Profile")
    private let pill = SpaceCreationPill()
    private let info = NSImageView()
    private let themeRow = SpaceCreationRow(symbol: "paintbrush.fill", label: "Choose a Theme")
    /// Cra's own row (#306): the command bar's search engine in this space.
    private let searchRow = SpaceCreationRow(symbol: "magnifyingglass", label: "Search Engine")
    private let enginePill = SpaceCreationPill()
    private let searchInfo = NSImageView()
    /// What the sheet said under each choice, in Arc's own tip on the row's (i).
    static let profileNote = "Profiles make your Spaces truly separate with their own logins, cookies and site data. Spaces with the same Profile share them."
    static let searchNote = "Searches from the command bar in this space go here. Default follows Settings."
    private let create = SpaceCreationButton()
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let card = NSView()
    private let cardIcon = EmojiLabel.sidebar(size: SpaceCreationAnimation.cardIcon)
    /// A symbol or picture icon on the card, where an emoji goes in `cardIcon`.
    private let cardImage = CALayer()
    private let glow = CAGradientLayer()
    private var iconPopover: NSPopover?
    private var creating = false
    var palette: SpacePalette { didSet { applyColors() } }

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, palette: SpacePalette) {
        self.store = store
        self.ui = ui
        self.actions = actions
        self.palette = palette
        super.init(frame: .zero)
        wantsLayer = true
        title.font = .systemFont(ofSize: SpaceCreationLayout.titleFont, weight: .bold)
        title.alignment = .center
        subtitle.font = .systemFont(ofSize: SpaceCreationLayout.textFont)
        subtitle.alignment = .center
        subtitle.maximumNumberOfLines = 2
        fieldBox.wantsLayer = true
        fieldBox.layer?.cornerRadius = SpaceCreationLayout.cornerRadius
        fieldBox.layer?.cornerCurve = .continuous
        name.isBordered = false
        name.drawsBackground = false
        name.focusRingType = .none
        name.font = .systemFont(ofSize: SpaceCreationLayout.textFont, weight: .semibold)
        name.placeholderString = "Space name..."
        name.delegate = self
        name.lineBreakMode = .byTruncatingTail
        name.cell?.usesSingleLineMode = true
        name.cell?.isScrollable = true
        iconButton.onClick = { [weak self] in self?.showIconPicker() }
        fieldBox.addSubview(iconButton)
        fieldBox.addSubview(name)
        // Arc's (i) shows its tip as the pointer arrives, in its own bubble; the words are the sheet's.
        for (view, note, label) in [(info, Self.profileNote, "About Profiles"), (searchInfo, Self.searchNote, "About the search engine")] {
            view.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: label)
            view.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
            let tip = ArcTooltipAnchorView(frame: view.bounds)
            tip.autoresizingMask = [.width, .height]
            tip.text = note
            tip.delay = 0.05
            view.addSubview(tip)
        }
        pill.onClick = { [weak self] in self?.showProfileMenu() }
        profileRow.addSubview(pill)
        profileRow.addSubview(info)
        profileRow.onClick = { [weak self] in self?.showProfileMenu() }
        themeRow.onClick = { [weak self] in
            guard let self, let window = self.window else { return }
            self.actions.chooseCreationTheme(window.convertToScreen(self.themeRow.convert(self.themeRow.bounds, to: nil)))
        }
        enginePill.onClick = { [weak self] in self?.showEngineMenu() }
        searchRow.addSubview(enginePill)
        searchRow.addSubview(searchInfo)
        searchRow.onClick = { [weak self] in self?.showEngineMenu() }
        create.title = "Create Space"
        create.onClick = { [weak self] in self?.actions.commitSpaceCreation() }
        cancel.isBordered = false
        cancel.font = .systemFont(ofSize: SpaceCreationLayout.textFont, weight: .medium)
        cancel.target = self
        cancel.action = #selector(cancelPressed)
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.white.cgColor
        card.layer?.cornerRadius = SpaceCreationAnimation.cardRadius
        card.layer?.cornerCurve = .continuous
        card.layer?.shadowOpacity = 0.18
        card.layer?.shadowRadius = 6
        card.layer?.shadowOffset = CGSize(width: 0, height: -2)
        cardIcon.alignment = .center
        card.addSubview(cardIcon)
        cardImage.contentsGravity = .resizeAspect
        card.layer?.addSublayer(cardImage)
        card.isHidden = true
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.opacity = 0
        layer?.addSublayer(glow)
        for v in [picture, title, subtitle, fieldBox, profileRow, themeRow, searchRow, create, cancel, card] as [NSView] { addSubview(v) }
        applyColors()
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    // A click on the page's empty part takes the keyboard off nothing and closes what the page opened.
    override func mouseDown(with event: NSEvent) { actions.closeCreationPanels() }

    /// Follows the window's draft: the name's button, the icon, the profile's name.
    private func observe() {
        observeChanges(of: { [ui] in ui.spaceCreation }) { [weak self] draft in self?.show(draft) }
    }

    private func show(_ draft: SpaceCreationDraft?) {
        guard let draft else { return }
        if name.stringValue != draft.title, name.currentEditor() == nil { name.stringValue = draft.title }
        iconButton.icon = draft.icon
        create.isOn = draft.canCreate
        pill.title = store.profileName(draft.profile)
        let engines = engineChoices(for: draft)
        enginePill.title = draft.searchEngine.flatMap { k in engines.choices.first { $0.keyword == k }?.name } ?? "Default (\(engines.defaultName))"
        needsLayout = true
    }

    private func applyColors() {
        let c = SidebarColors(palette)
        let dark = palette.isDark
        title.textColor = c.textPrimary
        subtitle.textColor = c.textPrimary.withAlphaComponent(0.92)
        // Arc's field is white at 6 % on a dark sidebar and at 60 % on a light one; its rows are
        // white at 8 %, or black at 5.5 %.
        fieldBox.layer?.backgroundColor = NSColor.white.withAlphaComponent(dark ? 0.06 : 0.6).cgColor
        name.textColor = dark ? c.textPrimary : NSColor.black.withAlphaComponent(0.85)
        let placeholder = (dark ? NSColor.white : NSColor.black).withAlphaComponent(dark ? 0.55 : 0.4)
        name.placeholderAttributedString = NSAttributedString(string: "Space name...", attributes: [
            .foregroundColor: placeholder, .font: NSFont.systemFont(ofSize: SpaceCreationLayout.textFont, weight: .semibold)])
        iconButton.ink = placeholder
        for row in [profileRow, themeRow, searchRow] { row.apply(colors: c, dark: dark) }
        pill.apply(colors: c, dark: dark)
        enginePill.apply(colors: c, dark: dark)
        info.contentTintColor = c.textPrimary.withAlphaComponent(0.85)
        searchInfo.contentTintColor = info.contentTintColor
        cancel.contentTintColor = c.textPrimary.withAlphaComponent(0.6)
        cancel.attributedTitle = NSAttributedString(string: "Cancel", attributes: [
            .foregroundColor: c.textPrimary.withAlphaComponent(0.6), .font: NSFont.systemFont(ofSize: SpaceCreationLayout.textFont, weight: .medium)])
        create.fill = Self.buttonColor(palette)
        let tint = NSColor(palette.gradientColors.first ?? .white)
        glow.colors = [tint.withAlphaComponent(0.9).cgColor, tint.withAlphaComponent(0).cgColor]
    }

    /// Create Space is a deep, full shade of the theme (Arc: #A3164B on a pink #B8718A sidebar,
    /// #1C25FF on its dark navy).
    static func buttonColor(_ palette: SpacePalette) -> NSColor {
        let base = NSColor(palette.gradientColors.first ?? .gray).usingColorSpace(.sRGB) ?? .gray
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        guard s > 0.08 else { return NSColor(white: palette.isDark ? 0.92 : 0.12, alpha: 1) }
        return NSColor(hue: h, saturation: min(1, s * 1.6 + 0.2), brightness: b < 0.4 ? 0.9 : 0.62, alpha: 1)
    }

    override func layout() {
        super.layout()
        // Arc's three layouts by the sidebar's width (SpaceCreationLayout.Density).
        let density = SpaceCreationLayout.Density(sidebarWidth: bounds.width)
        if subtitle.stringValue != density.subtitle { subtitle.stringValue = density.subtitle }
        subtitle.maximumNumberOfLines = density == .narrow ? 4 : 2
        let room = NSRect(x: 0, y: 0, width: max(0, bounds.width - 2 * SpaceCreationLayout.inset), height: 400)
        let tall = subtitle.cell?.cellSize(forBounds: room).height ?? 2 * SpaceCreationLayout.subtitleLine
        let lines = max(1, min(4, Int((tall / SpaceCreationLayout.subtitleLine).rounded())))
        // Cra's Search Engine names are long: its pill goes under the label when it has no room beside it.
        let rowWidth = max(0, bounds.width - 2 * SpaceCreationLayout.inset)
        let infoSide = SpaceCreationLayout.infoSide + 4
        let infoRoom = SpaceCreationLayout.infoInset + infoSide + 4
        let searchStacked = density.stacksPills || !SpaceCreationLayout.pillFits(
            rowWidth: rowWidth, labelEnd: density.rowLabelInset + searchRow.labelWidth, fits: enginePill.fittingWidth, trailing: infoRoom)
        let f = SpaceCreationLayout.frames(in: bounds.size, subtitleLines: lines, searchStacked: searchStacked)
        picture.frame = f.picture
        title.frame = f.title
        subtitle.frame = f.subtitle
        for row in [profileRow, themeRow, searchRow] {
            row.showsGlyph = density.showsRowGlyphs
            row.labelInset = density.rowLabelInset
        }
        profileRow.labelCentre = density.stacksPills ? SpaceCreationLayout.stackedLabelCentre : nil
        searchRow.labelCentre = searchStacked ? SpaceCreationLayout.stackedLabelCentre : nil
        fieldBox.frame = f.field
        iconButton.frame = f.icon.offsetBy(dx: -f.field.minX, dy: -f.field.minY)
        let x = SpaceCreationLayout.textInset
        name.frame = NSRect(x: x, y: (f.field.height - 18) / 2, width: f.field.width - x - 8, height: 18)
        profileRow.frame = f.profile
        themeRow.frame = f.theme
        let side = SpaceCreationLayout.infoSide + 4
        profileRow.layoutSubtreeIfNeeded()
        // The (i) ends the row, or follows the label when the pill is under it.
        let infoX = density.stacksPills ? profileRow.labelEnd + 5 : f.profile.width - SpaceCreationLayout.infoInset - side + 2
        let infoY = (density.stacksPills ? SpaceCreationLayout.stackedLabelCentre : f.profile.height / 2) - side / 2
        info.frame = NSRect(x: infoX, y: infoY, width: side, height: side)
        pill.fills = density.stacksPills
        pill.frame = SpaceCreationLayout.pillFrame(row: f.profile.size, labelEnd: profileRow.labelEnd, fits: pill.fittingWidth,
                                                   trailing: SpaceCreationLayout.infoInset + side + 4, stacked: density.stacksPills)
        searchRow.frame = f.search
        searchRow.layoutSubtreeIfNeeded()
        // Its (i) ends the row, or follows the label when the pill is under it, like the Profile row's.
        let searchInfoX = searchStacked ? searchRow.labelEnd + 5 : f.search.width - SpaceCreationLayout.infoInset - infoSide + 2
        let searchInfoY = (searchStacked ? SpaceCreationLayout.stackedLabelCentre : f.search.height / 2) - infoSide / 2
        searchInfo.frame = NSRect(x: searchInfoX, y: searchInfoY, width: infoSide, height: infoSide)
        enginePill.fills = searchStacked
        enginePill.frame = SpaceCreationLayout.pillFrame(row: f.search.size, labelEnd: searchRow.labelEnd, fits: enginePill.fittingWidth,
                                                         trailing: infoRoom, stacked: searchStacked)
        create.frame = f.create
        cancel.frame = f.cancel
        if !creating {
            card.frame = SpaceCreationAnimation.cardFrame(in: bounds.size)
            cardIcon.frame = card.bounds.insetBy(dx: 0, dy: (card.bounds.height - 46) / 2)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = SpaceCreationAnimation.cardFrame(in: bounds.size).insetBy(dx: -60, dy: -52)
        CATransaction.commit()
    }

    // MARK: The name

    /// The name takes the keyboard, in the floating sidebar's panel too (its fields make it key, #424).
    func focusName() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window, !self.creating else { return }
            w.makeKey()
            w.makeFirstResponder(self.name)
        }
    }

    /// Whether the name is being typed in: a page that loads late leaves the keyboard here.
    var nameHasKeys: Bool { name.currentEditor() != nil }

    func controlTextDidChange(_ obj: Notification) {
        ui.spaceCreation?.title = name.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { actions.commitSpaceCreation(); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { actions.cancelSpaceCreation(); return true }
        return false
    }

    @objc private func cancelPressed() { actions.cancelSpaceCreation() }

    // MARK: The icon

    /// Arc's picker in a popover under the dashed "+", as for a space's own icon.
    private func showIconPicker() {
        guard iconPopover == nil, let draft = ui.spaceCreation else { return }
        actions.closeCreationPanels()
        let popover = NSPopover()
        popover.behavior = .transient
        let set: (SpaceIcon) -> Void = { [weak self, weak popover] icon in
            self?.ui.spaceCreation?.icon = icon
            popover?.performClose(nil)
            self?.focusName()
        }
        let picker = SpaceIconPicker(current: draft.icon.emoji, currentSymbol: draft.icon.symbol, currentImage: draft.icon.image,
                                     onPick: { set(.emoji($0)) }, onPickSymbol: { set(.symbol($0)) },
                                     onPickImage: { set(.image($0)) }, onRemove: { set(.none) })
        let host = NSHostingController(rootView: picker)
        host.sizingOptions = []
        host.preferredContentSize = NSSize(width: 272, height: 272)
        popover.contentViewController = host
        popover.contentSize = NSSize(width: 272, height: 272)
        popover.delegate = self
        iconPopover = popover
        popover.show(relativeTo: iconButton.bounds, of: iconButton, preferredEdge: .minY)
    }

    func closeIconPicker() { iconPopover?.performClose(nil) }

    func popoverDidClose(_ notification: Notification) { iconPopover = nil }

    // MARK: The profile

    /// Arc's rows for a space's profile: Default, the profiles, a line, New Profile….
    private func showProfileMenu() {
        actions.closeCreationPanels()
        let menu = NSMenu()
        let current = ui.spaceCreation?.profile
        func item(_ title: String, _ id: UUID?) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: #selector(pickProfile(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = id
            i.state = id == current ? .on : .off
            return i
        }
        menu.addItem(item(store.profileName(nil), nil))
        for p in store.profiles { menu.addItem(item(p.name, p.id)) }
        menu.addItem(.separator())
        let new = NSMenuItem(title: "New Profile…", action: #selector(newProfile), keyEquivalent: "")
        new.target = self
        menu.addItem(new)
        menu.popUp(positioning: nil, at: NSPoint(x: pill.frame.minX, y: pill.frame.maxY + 4), in: profileRow)
    }

    @objc private func pickProfile(_ sender: NSMenuItem) {
        ui.spaceCreation?.profile = sender.representedObject as? UUID
    }

    @objc private func newProfile() { actions.newProfileForCreation() }

    // MARK: The search engine (Cra's own, #306)

    /// The engines the draft's profile knows, and the name of the one Settings uses.
    private func engineChoices(for draft: SpaceCreationDraft) -> (choices: [ChromiumSearchEngine], defaultName: String) {
        let path = store.profilePath(profile: draft.profile)
        let name = SearchEngines.shared.defaultEngine(profilePath: path, legacy: store.settings.searchEngine).name
        return (ChromiumSearchEngine.spaceChoices(among: SearchEngines.shared.keywords(profilePath: path)), name)
    }

    /// The rows of the sheet's picker: Default (the one Settings uses), a line, the engines.
    private func showEngineMenu() {
        guard let draft = ui.spaceCreation else { return }
        actions.closeCreationPanels()
        let engines = engineChoices(for: draft)
        let menu = NSMenu()
        func item(_ title: String, _ keyword: String?) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: #selector(pickEngine(_:)), keyEquivalent: "")
            i.target = self
            i.representedObject = keyword
            i.state = keyword == draft.searchEngine ? .on : .off
            return i
        }
        menu.addItem(item("Default (\(engines.defaultName))", nil))
        menu.addItem(.separator())
        for e in engines.choices { menu.addItem(item(e.name, e.keyword)) }
        menu.popUp(positioning: nil, at: NSPoint(x: enginePill.frame.minX, y: enginePill.frame.maxY + 4), in: searchRow)
    }

    @objc private func pickEngine(_ sender: NSMenuItem) {
        ui.spaceCreation?.searchEngine = sender.representedObject as? String
    }

    // MARK: Creating

    /// Arc's animation from Create Space to the space: the controls fade out from the bottom up, the
    /// picture tips over and comes back as a card with the space's icon, which drops to the middle
    /// with a glow of the theme, and fades. `done` runs when the sidebar is empty again.
    func playCreation(icon: SpaceIcon, done: @escaping () -> Void) {
        guard !creating else { return }
        creating = true
        window?.makeFirstResponder(nil)
        typealias A = SpaceCreationAnimation
        let now = CACurrentMediaTime()
        for v in subviews { v.wantsLayer = true }
        /// Fades from `start`, sliding down as it does (Arc's 80 pt, slow at both ends).
        func leave(_ views: [NSView], from start: Double, slides: Bool = true) {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = slides ? A.partFade : A.buttonsFade.upperBound
            let move = CABasicAnimation(keyPath: "transform.translation.y")
            move.fromValue = 0
            move.toValue = A.partSlide
            move.duration = A.partSlideTime
            for a in [fade, move] {
                a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                a.beginTime = now + start
                a.fillMode = .both
                a.isRemovedOnCompletion = false
            }
            for v in views {
                v.layer?.add(fade, forKey: "creationFade")
                if slides { v.layer?.add(move, forKey: "creationSlide") }
            }
        }
        leave([create, cancel], from: A.buttonsFade.lowerBound, slides: false)
        leave([searchRow, themeRow], from: A.themeRowStart)
        leave([profileRow], from: A.profileRowStart)
        leave([fieldBox], from: A.fieldStart)
        leave([subtitle], from: A.subtitleStart)
        leave([title], from: A.titleStart)

        // The picture and the card are the two faces of one thing: it drops to the card's place on a
        // spring and turns over on the way, the picture's top edge going away first.
        let rest = A.cardFrame(in: bounds.size)
        let way = rest.midY - picture.frame.midY
        let side = A.cardIcon
        var image: NSImage?
        cardIcon.stringValue = ""
        switch icon {
        case .emoji(let e): cardIcon.stringValue = e
        case .symbol(let s):
            image = NSImage(systemSymbolName: s, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: side * 0.8, weight: .medium).applying(.init(hierarchicalColor: .black)))
        case .image(let d): image = NSImage(data: d)
        case .none: break
        }
        card.frame = rest
        cardIcon.frame = card.bounds.insetBy(dx: 0, dy: (card.bounds.height - 46) / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let scale = window?.backingScaleFactor ?? 2
        cardImage.contentsScale = scale
        cardImage.contents = image?.layerContents(forContentsScale: scale)
        cardImage.frame = CGRect(x: ((rest.width - side) / 2).rounded(), y: ((rest.height - side) / 2).rounded(), width: side, height: side)
        CATransaction.commit()
        card.isHidden = false
        card.layer?.opacity = 0
        /// A view's layer is anchored at its corner: this stretches it to `height` and turns it about
        /// its middle, seen from `perspective` points away, `down` points lower.
        func placed(_ size: CGSize, height: CGFloat, turn: Double, down: CGFloat) -> CATransform3D {
            var t = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
            t = CATransform3DConcat(t, CATransform3DMakeScale(1, height / max(1, size.height), 1))
            t = CATransform3DConcat(t, CATransform3DMakeRotation(CGFloat(turn), 1, 0, 0))
            var eye = CATransform3DIdentity
            eye.m34 = -1 / A.perspective
            t = CATransform3DConcat(t, eye)
            return CATransform3DConcat(t, CATransform3DMakeTranslation(size.width / 2, size.height / 2 + down, 0))
        }
        // A spring and half a turn aren't a curve between two values: each frame is its own.
        let rate = 120.0
        let frames = Int((A.cardFade.upperBound * rate).rounded())
        func run(_ layer: CALayer?, _ key: String, _ value: (Double) -> Any) {
            let a = CAKeyframeAnimation(keyPath: key)
            a.values = (0...frames).map { value(Double($0) / rate) }
            a.calculationMode = .linear
            a.beginTime = now
            a.duration = Double(frames) / rate
            a.fillMode = .forwards
            a.isRemovedOnCompletion = false
            layer?.add(a, forKey: "creation-" + key)
        }
        // The picture's drawing fills its view, which is as tall as Arc's picture.
        let pictureSize = picture.bounds.size, pictureGrows = pictureSize.height / A.pictureHeight
        run(picture.layer, "transform") { t in
            let p = A.drop(at: t)
            return NSValue(caTransform3D: placed(pictureSize, height: A.height(at: p) * pictureGrows, turn: A.turn(at: t), down: way * CGFloat(p)))
        }
        run(picture.layer, "opacity") { A.pictureOpacity(at: $0) }
        // Its other face: in front of the picture all the way, so it shows through it before the turn.
        card.layer?.zPosition = 400
        run(card.layer, "transform") { t in
            let p = A.drop(at: t)
            return NSValue(caTransform3D: placed(rest.size, height: A.height(at: p), turn: A.turn(at: t) - .pi, down: -way * CGFloat(1 - p)))
        }
        run(card.layer, "opacity") { A.cardOpacity(at: $0) }

        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0, 1, 0]
        pulse.keyTimes = [0, 0.5, 1]
        pulse.beginTime = now + A.glow.lowerBound
        pulse.duration = (A.glow.upperBound - A.glow.lowerBound) * 2
        glow.add(pulse, forKey: "pulse")
        let face: String
        switch icon {
        case .emoji(let e): face = e
        case .symbol(let s): face = image == nil ? "empty" : s
        case .image: face = image == nil ? "empty" : "image"
        case .none: face = "empty"
        }
        CraLog.note("space creation plays: the cards drop \(Int(way.rounded())) pt and turn over, \(frames + 1) frames, card=\(face)")
        DispatchQueue.main.asyncAfter(deadline: .now() + A.done) { done() }
    }

    // MARK: Scenarios

    /// What the page shows, for a scenario.
    var debugLine: String {
        func r(_ f: NSRect) -> String { "\(Int(f.minX.rounded())),\(Int(f.minY.rounded())),\(Int(f.width.rounded()))x\(Int(f.height.rounded()))" }
        return "name=\"\(name.stringValue)\" keys=\(nameHasKeys ? 1 : 0) icon=\(iconButton.label) profile=\(pill.title) engine=\(enginePill.title)"
            + " layout=\(SpaceCreationLayout.Density(sidebarWidth: bounds.width)) searchGlyph=\(searchRow.debugGlyph) create=\(create.isOn ? "on" : "off") field=\(r(fieldBox.frame)) rows=\(r(profileRow.frame)),\(r(themeRow.frame)) button=\(r(create.frame))"
    }

    /// The tip of a row's (i), shown as the pointer would: its words, its wait, and its size.
    func debugTip(_ row: String) -> String {
        let view = row == "search" ? searchInfo : info
        guard let tip = view.subviews.compactMap({ $0 as? ArcTooltipAnchorView }).first else { return "none" }
        let size = ArcTooltipController.shared.debugShow(for: tip)
        return "\"\(tip.text)\" wait=\(tip.idleDelay) bubble=\(Int(size.width.rounded()))x\(Int(size.height.rounded())) native=\((view.toolTip ?? searchRow.toolTip ?? profileRow.toolTip) == nil ? 0 : 1)"
    }

    /// Typed into the name as the keyboard would.
    func debugType(_ text: String) {
        name.stringValue = text
        ui.spaceCreation?.title = text
    }
}

/// The dashed "+" at the start of the name, or the icon once one is picked.
@MainActor
final class SpaceCreationIconButton: NSView {
    var onClick: () -> Void = {}
    var ink: NSColor = .secondaryLabelColor { didSet { needsDisplay = true } }
    var icon: SpaceIcon = .none { didSet { if icon != oldValue { refresh() } } }
    private let emoji = EmojiLabel.sidebar(size: 14)
    private let symbol = NSImageView()
    private var hovered = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        emoji.alignment = .center
        addSubview(emoji)
        addSubview(symbol)
        refresh()
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Choose Icon")
    }

    required init?(coder: NSCoder) { fatalError() }

    var label: String {
        switch icon {
        case .emoji(let e): return e
        case .symbol(let s): return s
        case .image: return "image"
        case .none: return "plus"
        }
    }

    private func refresh() {
        emoji.isHidden = true
        symbol.isHidden = true
        switch icon {
        case .emoji(let e):
            emoji.stringValue = e
            emoji.isHidden = false
        case .symbol(let s):
            symbol.image = NSImage(systemSymbolName: s, accessibilityDescription: nil)
            symbol.isHidden = false
        case .image(let d):
            symbol.image = NSImage(data: d)
            symbol.isHidden = false
        case .none: break
        }
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        emoji.frame = bounds.insetBy(dx: -3, dy: -2)
        symbol.frame = bounds.insetBy(dx: 1, dy: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard icon == .none else { return }
        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        if hovered {
            ink.withAlphaComponent(0.18).setFill()
            box.fill()
        }
        ink.setStroke()
        box.lineWidth = 1
        box.setLineDash([2.5, 2], count: 2, phase: 0)
        box.stroke()
        let plus = NSBezierPath()
        let m = bounds.midX, n = bounds.midY
        plus.move(to: NSPoint(x: m - 4.5, y: n)); plus.line(to: NSPoint(x: m + 4.5, y: n))
        plus.move(to: NSPoint(x: m, y: n - 4.5)); plus.line(to: NSPoint(x: m, y: n + 4.5))
        plus.lineWidth = 1.5
        plus.lineCapStyle = .round
        plus.stroke()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

/// A row of the page: a glyph and a label on a faint fill that lightens under the pointer.
@MainActor
final class SpaceCreationRow: NSView {
    var onClick: () -> Void = {}
    private let glyph = NSImageView()
    private let label: NSTextField
    private var rest = NSColor.clear, hover = NSColor.clear
    private var hovered = false { didSet { refresh() } }
    private var pressed = false { didSet { refresh() } }
    /// Arc drops the glyph and starts the label 16 pt in once the sidebar is 227 pt or narrower.
    var showsGlyph = true { didSet { if showsGlyph != oldValue { glyph.isHidden = !showsGlyph; needsLayout = true } } }
    var labelInset: CGFloat = SpaceCreationLayout.rowLabelInset { didSet { if labelInset != oldValue { needsLayout = true } } }
    /// The label's centre from the row's top when a pill stands under it; nil centres it in the row.
    var labelCentre: CGFloat? { didSet { if labelCentre != oldValue { needsLayout = true } } }
    /// The glyph's centre from the row's top, or `none` when the row has none, for a scenario.
    var debugGlyph: String { showsGlyph ? "\(Int(glyph.frame.midY.rounded()))" : "none" }
    /// Where the label ends, for what follows it, and how wide it is when nothing cuts it.
    var labelEnd: CGFloat { label.frame.maxX }
    var labelWidth: CGFloat { label.fittingSize.width }

    init(symbol: String, label text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = SpaceCreationLayout.cornerRadius
        layer?.cornerCurve = .continuous
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        label.font = .systemFont(ofSize: SpaceCreationLayout.textFont, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        addSubview(glyph)
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(text)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func apply(colors: SidebarColors, dark: Bool) {
        // Arc: white 8 % on a dark sidebar (12 % under the pointer), black 5.5 % on a light one.
        rest = dark ? NSColor.white.withAlphaComponent(0.08) : NSColor.black.withAlphaComponent(0.055)
        hover = dark ? NSColor.white.withAlphaComponent(0.12) : NSColor.black.withAlphaComponent(0.09)
        glyph.contentTintColor = colors.textPrimary.withAlphaComponent(0.55)
        label.textColor = colors.textPrimary
        refresh()
    }

    private func refresh() {
        layer?.backgroundColor = (hovered && !pressed ? hover : rest).cgColor
        alphaValue = pressed ? 0.7 : 1
    }

    override func layout() {
        super.layout()
        // The glyph keeps to the label's line, also when a pill stands under it.
        glyph.frame = NSRect(x: SpaceCreationLayout.rowGlyphInset, y: (labelCentre ?? bounds.height / 2) - 8, width: 16, height: 16)
        label.sizeToFit()
        let width = min(label.frame.width, max(0, bounds.width - labelInset - 6))
        label.frame = NSRect(x: labelInset, y: (labelCentre ?? bounds.height / 2) - label.frame.height / 2, width: width, height: label.frame.height)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

/// The Profile row's pill: the profile's name and a chevron.
@MainActor
final class SpaceCreationPill: NSView {
    var onClick: () -> Void = {}
    var title = "Default" { didSet { label.stringValue = title; superview?.superview?.needsLayout = true } }
    /// As wide as its row, under the label: the chevron goes to its end (Arc at 190 pt and under).
    var fills = false { didSet { if fills != oldValue { needsLayout = true } } }
    private let label = NSTextField(labelWithString: "Default")
    private let chevron = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.lineBreakMode = .byTruncatingTail
        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: 9, weight: .bold)
        addSubview(label)
        addSubview(chevron)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    var fittingWidth: CGFloat {
        label.sizeToFit()
        return 10 + label.frame.width + 5 + 10 + 9
    }

    func apply(colors: SidebarColors, dark: Bool) {
        layer?.backgroundColor = (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.09)).cgColor
        label.textColor = colors.textPrimary
        chevron.contentTintColor = colors.textPrimary
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        label.sizeToFit()
        // A name longer than the pill is cut short; the chevron keeps its place at the end.
        let width = min(label.frame.width, max(0, bounds.width - 10 - 5 - 10 - 9))
        label.frame = NSRect(x: 10, y: (bounds.height - label.frame.height) / 2, width: width, height: label.frame.height)
        chevron.frame = NSRect(x: fills ? bounds.width - 9 - 10 : label.frame.maxX + 5, y: (bounds.height - 10) / 2, width: 10, height: 10)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { onClick() }
}

/// Create Space: a filled button that is dim until the space has a name.
@MainActor
final class SpaceCreationButton: NSView {
    var onClick: () -> Void = {}
    var title = "" { didSet { label.stringValue = title } }
    var fill: NSColor = .controlAccentColor { didSet { refresh() } }
    var isOn = false { didSet { refresh() } }
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 6.5
        layer?.cornerCurve = .continuous
        label.font = .systemFont(ofSize: SpaceCreationLayout.textFont, weight: .semibold)
        label.alignment = .center
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Create Space")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func refresh() {
        // Arc's button off is the same shade at under half strength, its words dimmed with it.
        layer?.backgroundColor = fill.withAlphaComponent(isOn ? 1 : 0.42).cgColor
        label.textColor = NSColor.white.withAlphaComponent(isOn ? 1 : 0.45)
    }

    override func layout() {
        super.layout()
        label.frame = NSRect(x: 0, y: (bounds.height - 17) / 2, width: bounds.width, height: 17)
    }

    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if isOn, bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

/// The page's picture: three tilted cards, Cra's own drawing of the idea (a palm, a laptop, books).
@MainActor
final class SpaceCreationPicture: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        let emoji = ["🌴", "💻", "📚"]
        let angles: [CGFloat] = [-0.24, 0, 0.24]
        let offsets: [CGFloat] = [-17, 0, 17]
        for i in [0, 2, 1] {
            let card = CALayer()
            card.bounds = CGRect(x: 0, y: 0, width: 28, height: 36)
            card.backgroundColor = NSColor.white.cgColor
            card.cornerRadius = 4
            card.shadowOpacity = 0.2
            card.shadowRadius = 2
            card.shadowOffset = CGSize(width: 0, height: -1)
            card.position = CGPoint(x: 32 + offsets[i], y: 20.5 + (i == 1 ? 1.5 : 0))
            card.setAffineTransform(CGAffineTransform(rotationAngle: -angles[i]))
            card.zPosition = i == 1 ? 1 : 0
            let text = CATextLayer()
            text.string = emoji[i]
            text.fontSize = 18
            text.alignmentMode = .center
            text.contentsScale = 2
            text.frame = CGRect(x: 0, y: 6, width: 28, height: 24)
            card.addSublayer(text)
            layer?.addSublayer(card)
        }
    }

    required init?(coder: NSCoder) { fatalError() }
}
