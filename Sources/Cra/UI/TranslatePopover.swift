import AppKit

/// What Arc's translate popover can do for the page (#310).
struct TranslateActions {
    var translate: (_ target: String?) -> Void = { _ in }
    var showOriginal: () -> Void = {}
    var neverTranslateSite: () -> Void = {}
    var languageSettings: () -> Void = {}
}

/// Arc's translate popover (Translation/TranslateBubblePopoverView, Arc 1.17x, measured 10 Nov in
/// an offline Arc, dark mode, 1x): an NSPopover hung under the translate button, 236 × 102 pt of
/// content with 10 pt insets. A 32 pt badge (`textformat.alt`) 11 pt from the top, the question in
/// 14 pt from 50 pt in, centred on it, and two 104 × 32 pt buttons 7 pt apart: Options, flat (a
/// menu: Choose Another Language ▸, Never Translate This Site | Language Settings), and Translate,
/// raised (Show Original on a translated page). Arc opens it only from its button.
@MainActor
final class TranslatePopover: NSObject, NSPopoverDelegate {
    private var popover: NSPopover?
    var isShown: Bool { popover?.isShown == true }
    /// The shown popover's buttons, for scenarios (cra://debug?translate=…).
    private(set) weak var content: TranslatePopoverView?

    /// When a click outside closed the popover (event time): the same click on the button leaves
    /// it closed instead of opening it again.
    private var closingClick: TimeInterval?

    func toggle(relativeTo rect: NSRect, of view: NSView, state: PageTranslation, actions: TranslateActions) {
        if let p = popover, p.isShown { p.performClose(nil); return }
        if let t = closingClick, let now = NSApp.currentEvent?.timestamp, now - t < 1, NSApp.currentEvent?.type == .leftMouseUp {
            closingClick = nil
            return
        }
        closingClick = nil
        let p = NSPopover()
        p.behavior = .transient
        p.animates = true
        p.delegate = self
        p.appearance = NSAppearance(named: SystemAppearance.shared.isDark ? .darkAqua : .aqua)
        var acts = actions
        func closing(_ f: @escaping () -> Void) -> () -> Void { { [weak p] in p?.performClose(nil); f() } }
        acts.translate = { [weak p] target in p?.performClose(nil); actions.translate(target) }
        acts.showOriginal = closing(actions.showOriginal)
        acts.neverTranslateSite = closing(actions.neverTranslateSite)
        acts.languageSettings = closing(actions.languageSettings)
        let v = TranslatePopoverView(state: state, actions: acts)
        let host = NSViewController()
        host.view = v
        host.preferredContentSize = v.frame.size
        p.contentViewController = host
        popover = p
        content = v
        p.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }

    func close() { popover?.performClose(nil) }

    func popoverWillClose(_ notification: Notification) {
        if let e = NSApp.currentEvent, e.type == .leftMouseDown { closingClick = e.timestamp }
    }

    func popoverDidClose(_ notification: Notification) {
        popover = nil
        content = nil
    }
}

final class TranslatePopoverView: NSView {
    static let size = NSSize(width: 236, height: 102)
    private let state: PageTranslation
    private let actions: TranslateActions
    private let badge = NSView()
    private let glyph = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    var prompt: String { label.stringValue }
    let options: TranslatePopoverButton
    let primary: TranslatePopoverButton

    init(state: PageTranslation, actions: TranslateActions) {
        self.state = state
        self.actions = actions
        options = TranslatePopoverButton(title: "Options", prominent: false)
        primary = TranslatePopoverButton(title: state.translated ? "Show Original" : "Translate", prominent: true)
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        wantsLayer = true
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 16
        glyph.image = NSImage(systemSymbolName: "textformat.alt", accessibilityDescription: "Text Formatting")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        badge.addSubview(glyph)
        label.stringValue = state.prompt
        label.font = .systemFont(ofSize: 14)
        label.maximumNumberOfLines = 2
        for v in [badge, label, options, primary] as [NSView] { addSubview(v) }
        options.action = { [weak self] in self?.showOptions() }
        primary.action = { [weak self] in
            guard let self else { return }
            if self.state.translated { self.actions.showOriginal() } else { self.actions.translate(nil) }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// The popover's own appearance (it follows macOS, as Arc's does), not the app's.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        let ink = TranslatePopoverButton.ink(for: self)
        // Arc's material (an SDK-15 popover): grey 110 over a white page in dark mode, with the
        // window's tint coming through. SDK 26's glass is far lighter, so the body is filled the
        // way the Site Control Center's is, translucent like Arc's.
        let dark = ink == .white
        layer?.backgroundColor = (dark ? NSColor(srgbRed: 0.23, green: 0.23, blue: 0.24, alpha: 0.86)
                                       : NSColor(srgbRed: 0.96, green: 0.96, blue: 0.965, alpha: 0.86)).cgColor
        // Arc's ink over the material: 209 on 110 in dark mode; the badge 118.
        badge.layer?.backgroundColor = ink.withAlphaComponent(0.06).cgColor
        glyph.contentTintColor = ink.withAlphaComponent(0.82)
        label.textColor = ink.withAlphaComponent(0.8)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        viewDidChangeEffectiveAppearance()
    }

    override func layout() {
        super.layout()
        let top: CGFloat = 0
        let inset: CGFloat = 10
        let buttonsTop: CGFloat = top + 60
        // The question wraps beside the badge and centres on it, 16 pt above the buttons.
        let textX: CGFloat = 50
        let size = label.sizeThatFits(NSSize(width: bounds.width - inset - textX, height: 40))
        let rowMid: CGFloat = top + 11 + 16
        badge.frame = NSRect(x: inset, y: rowMid - 16, width: 32, height: 32)
        glyph.frame = badge.bounds
        label.frame = NSRect(x: textX, y: rowMid - size.height / 2, width: size.width, height: size.height)
        let w = (bounds.width - 2 * inset - 7) / 2
        options.frame = NSRect(x: inset, y: buttonsTop, width: w, height: 32)
        primary.frame = NSRect(x: inset + w + 7, y: buttonsTop, width: w, height: 32)
    }

    /// Arc's Options menu, under the button.
    func optionsMenu() -> NSMenu {
        let m = NSMenu()
        m.autoenablesItems = false
        let choose = NSMenuItem(title: "Choose Another Language", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for code in state.otherLanguages {
            let item = BlockMenuItem(title: PageTranslation.name(of: code)) { [actions] in actions.translate(code) }
            sub.addItem(item)
        }
        choose.submenu = sub
        choose.isEnabled = !sub.items.isEmpty
        m.addItem(choose)
        m.addItem(BlockMenuItem(title: "Never Translate This Site") { [actions] in actions.neverTranslateSite() })
        m.addItem(.separator())
        m.addItem(BlockMenuItem(title: "Language Settings") { [actions] in actions.languageSettings() })
        return m
    }

    private func showOptions() {
        let m = optionsMenu()
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: options.bounds.height + 4), in: options)
    }
}

/// The popover's buttons (Arc): Options a flat fill with a 4 pt radius, Translate a raised bezel
/// (lighter fill, hairline border, 5.5 pt radius); 14 pt semibold labels.
final class TranslatePopoverButton: NSView {
    var action: () -> Void = {}
    private let label = NSTextField(labelWithString: "")
    private let prominent: Bool
    private var hovering = false { didSet { refresh() } }
    private var pressed = false { didSet { refresh() } }

    init(title: String, prominent: Bool) {
        self.prominent = prominent
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = prominent ? 5.5 : 4
        layer?.cornerCurve = .continuous
        label.stringValue = title
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        label.alignment = .center
        addSubview(label)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        refresh()
    }

    required init?(coder: NSCoder) { fatalError() }

    var title: String { label.stringValue }

    /// White on the dark material, black on the light one.
    static func ink(for view: NSView) -> NSColor {
        view.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .white : .black
    }

    private func refresh() {
        let ink = Self.ink(for: self)
        label.textColor = ink.withAlphaComponent(prominent ? 0.88 : 0.82)
        // Over the popover's material: 118 on 110 (Options) and 148 on 110 (Translate) in dark mode.
        let base: CGFloat = prominent ? 0.3 : 0.06
        layer?.backgroundColor = ink.withAlphaComponent(base + (pressed ? 0.08 : hovering ? 0.04 : 0)).cgColor
        layer?.borderColor = NSColor.black.withAlphaComponent(0.3).cgColor
        layer?.borderWidth = prominent ? 1 : 0
    }

    override func layout() {
        super.layout()
        let h = label.intrinsicContentSize.height
        label.frame = NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refresh()
    }
    override func accessibilityPerformPress() -> Bool { action(); return true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { pressed = true }
    override func mouseUp(with event: NSEvent) {
        pressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}
