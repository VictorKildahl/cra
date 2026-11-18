import AppKit
import SwiftUI

/// Arc's "Create a Space" page in the sidebar (CraCore's SpaceCreationDraft, SpaceCreationLayout and
/// SpaceCreationAnimation; docs/arc-parity.md, "Create a Space"): a picture, a title, the name
/// field with its icon button, the Profile and Choose a Theme rows, and Create Space and Cancel
/// at the bottom. It edits the window's draft and makes nothing itself.
@MainActor
final class SpaceCreationView: NSView, NSTextFieldDelegate {
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
    private let create = SpaceCreationButton()
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private let card = NSView()
    private let cardIcon = EmojiLabel.sidebar(size: SpaceCreationAnimation.cardIcon)
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
        info.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About Profiles")
        info.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        info.toolTip = "You can use a Profile to give this Space its own logins, history, and browsing data."
        pill.onClick = { [weak self] in self?.showProfileMenu() }
        profileRow.addSubview(pill)
        profileRow.addSubview(info)
        profileRow.onClick = { [weak self] in self?.showProfileMenu() }
        themeRow.onClick = { [weak self] in
            guard let self, let window = self.window else { return }
            self.actions.chooseCreationTheme(window.convertToScreen(self.themeRow.convert(self.themeRow.bounds, to: nil)))
        }
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
        card.isHidden = true
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.opacity = 0
        layer?.addSublayer(glow)
        for v in [picture, title, subtitle, fieldBox, profileRow, themeRow, create, cancel, card] as [NSView] { addSubview(v) }
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
        pill.title = draft.profile.flatMap { id in store.profiles.first { $0.id == id }?.name } ?? "Default"
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
        for row in [profileRow, themeRow] { row.apply(colors: c, dark: dark) }
        pill.apply(colors: c, dark: dark)
        info.contentTintColor = c.textPrimary.withAlphaComponent(0.85)
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
        let f = SpaceCreationLayout.frames(in: bounds.size)
        picture.frame = f.picture
        title.frame = f.title
        subtitle.frame = f.subtitle
        fieldBox.frame = f.field
        iconButton.frame = f.icon.offsetBy(dx: -f.field.minX, dy: -f.field.minY)
        let x = SpaceCreationLayout.textInset
        name.frame = NSRect(x: x, y: (f.field.height - 18) / 2, width: f.field.width - x - 8, height: 18)
        profileRow.frame = f.profile
        themeRow.frame = f.theme
        let pillWidth = pill.fittingWidth
        pill.frame = NSRect(x: 78, y: (f.profile.height - SpaceCreationLayout.pillHeight) / 2, width: pillWidth, height: SpaceCreationLayout.pillHeight)
        let side = SpaceCreationLayout.infoSide + 4
        info.frame = NSRect(x: f.profile.width - SpaceCreationLayout.infoInset - side + 2, y: (f.profile.height - side) / 2, width: side, height: side)
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
        iconPopover = popover
        NotificationCenter.default.addObserver(forName: NSPopover.didCloseNotification, object: popover, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.iconPopover = nil }
        }
        popover.show(relativeTo: iconButton.bounds, of: iconButton, preferredEdge: .minY)
    }

    func closeIconPicker() { iconPopover?.performClose(nil) }

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
        menu.addItem(item("Default", nil))
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

    // MARK: Creating

    /// Arc's animation from Create Space to the space: the controls fade out from the bottom up, the
    /// picture tips over and comes back as a card with the space's icon, which drops to the middle
    /// with a glow of the theme, and fades. `done` runs when the sidebar is empty again.
    func playCreation(icon: SpaceIcon, done: @escaping () -> Void) {
        guard !creating else { return }
        creating = true
        window?.makeFirstResponder(nil)
        typealias A = SpaceCreationAnimation
        func fade(_ views: [NSView], _ span: A.Span) {
            for v in views {
                let a = CABasicAnimation(keyPath: "opacity")
                a.fromValue = 1
                a.toValue = 0
                a.beginTime = CACurrentMediaTime() + span.lowerBound
                a.duration = span.upperBound - span.lowerBound
                a.fillMode = .both
                a.isRemovedOnCompletion = false
                v.layer?.add(a, forKey: "creation")
            }
        }
        for v in subviews { v.wantsLayer = true }
        fade([create, cancel], A.buttonsFade)
        fade([themeRow, profileRow, fieldBox], A.rowsFade)
        fade([title, subtitle], A.headingFade)
        // The picture moves down as it tips, edge-on at the end.
        let rest = SpaceCreationAnimation.cardFrame(in: bounds.size)
        // A view's layer is anchored at its corner: a squash about its middle goes there and back.
        func aboutMiddle(_ t: CATransform3D, of size: CGSize) -> CATransform3D {
            let to = CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0)
            let back = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
            return CATransform3DConcat(CATransform3DConcat(to, t), back)
        }
        let now = CACurrentMediaTime()
        let total = A.cardFade.upperBound
        func at(_ t: Double) -> NSNumber { NSNumber(value: t / total) }
        // The picture tips until it is edge-on, a third of the way down to the card's place, and is gone.
        let way = rest.midY - picture.frame.midY
        if let l = picture.layer {
            let edgeOn = CATransform3DConcat(CATransform3DMakeScale(1, 0.03, 1), CATransform3DMakeTranslation(0, way * 0.4, 0))
            let tip = CAKeyframeAnimation(keyPath: "transform")
            tip.values = [CATransform3DIdentity, CATransform3DIdentity, aboutMiddle(edgeOn, of: picture.bounds.size)].map { NSValue(caTransform3D: $0) }
            tip.keyTimes = [0, at(A.tip.lowerBound), at(A.tip.upperBound)]
            tip.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeIn)]
            let gone = CAKeyframeAnimation(keyPath: "opacity")
            gone.values = [1, 1, 0]
            gone.keyTimes = [0, at(A.tip.upperBound - 0.02), at(A.tip.upperBound)]
            for a in [tip, gone] as [CAKeyframeAnimation] {
                a.beginTime = now
                a.duration = total
                a.fillMode = .forwards
                a.isRemovedOnCompletion = false
            }
            l.add(tip, forKey: "tip")
            l.add(gone, forKey: "gone")
        }
        // It comes back from edge-on as one card with the icon, down to the middle and up to its size,
        // and fades at the end.
        switch icon {
        case .emoji(let e): cardIcon.stringValue = e
        default: cardIcon.stringValue = ""
        }
        card.frame = rest
        cardIcon.frame = card.bounds.insetBy(dx: 0, dy: (card.bounds.height - 46) / 2)
        card.isHidden = false
        if let l = card.layer {
            l.opacity = 0
            let edgeOn = CATransform3DConcat(CATransform3DMakeScale(0.6, 0.03, 1), CATransform3DMakeTranslation(0, -way * 0.6, 0))
            let from = aboutMiddle(edgeOn, of: rest.size)
            let drop = CAKeyframeAnimation(keyPath: "transform")
            drop.values = [from, from, CATransform3DIdentity, CATransform3DIdentity].map { NSValue(caTransform3D: $0) }
            drop.keyTimes = [0, at(A.cardDrop.lowerBound), at(A.cardDrop.upperBound), 1]
            drop.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .linear)]
            let shown = CAKeyframeAnimation(keyPath: "opacity")
            shown.values = [0, 0, 1, 1, 0]
            shown.keyTimes = [0, at(A.cardDrop.lowerBound), at(A.cardDrop.lowerBound + 0.03), at(A.cardFade.lowerBound), 1]
            for a in [drop, shown] as [CAKeyframeAnimation] {
                a.beginTime = now
                a.duration = total
                a.fillMode = .forwards
                a.isRemovedOnCompletion = false
            }
            l.add(drop, forKey: "drop")
            l.add(shown, forKey: "shown")
        }
        let pulse = CAKeyframeAnimation(keyPath: "opacity")
        pulse.values = [0, 1, 0]
        pulse.keyTimes = [0, 0.5, 1]
        pulse.beginTime = CACurrentMediaTime() + A.glow.lowerBound
        pulse.duration = (A.glow.upperBound - A.glow.lowerBound) * 2
        glow.add(pulse, forKey: "pulse")
        DispatchQueue.main.asyncAfter(deadline: .now() + A.done) { done() }
    }

    // MARK: Scenarios

    /// What the page shows, for a scenario.
    var debugLine: String {
        func r(_ f: NSRect) -> String { "\(Int(f.minX.rounded())),\(Int(f.minY.rounded())),\(Int(f.width.rounded()))x\(Int(f.height.rounded()))" }
        return "name=\"\(name.stringValue)\" keys=\(nameHasKeys ? 1 : 0) icon=\(iconButton.label) profile=\(pill.title)"
            + " create=\(create.isOn ? "on" : "off") field=\(r(fieldBox.frame)) rows=\(r(profileRow.frame)),\(r(themeRow.frame)) button=\(r(create.frame))"
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

    init(symbol: String, label text: String) {
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = SpaceCreationLayout.cornerRadius
        layer?.cornerCurve = .continuous
        glyph.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        glyph.symbolConfiguration = .init(pointSize: 12, weight: .semibold)
        label.font = .systemFont(ofSize: SpaceCreationLayout.textFont, weight: .semibold)
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
        glyph.frame = NSRect(x: SpaceCreationLayout.rowGlyphInset, y: (bounds.height - 16) / 2, width: 16, height: 16)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: SpaceCreationLayout.rowLabelInset, y: (bounds.height - label.frame.height) / 2)
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
    var title = "Default" { didSet { label.stringValue = title; superview?.needsLayout = true } }
    private let label = NSTextField(labelWithString: "Default")
    private let chevron = NSImageView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        label.font = .systemFont(ofSize: 12, weight: .semibold)
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
        label.frame.origin = NSPoint(x: 10, y: (bounds.height - label.frame.height) / 2)
        chevron.frame = NSRect(x: label.frame.maxX + 5, y: (bounds.height - 10) / 2, width: 10, height: 10)
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
