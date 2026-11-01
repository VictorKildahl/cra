import AppKit
import SwiftUI

/// Arc's toolbar above the page, in AppKit: nav buttons, the friendly URL (or the full URL in
/// developer mode), extensions and Split View. With no tab it carries the nav buttons and a
/// centred "Search or Enter URL…" placeholder; an empty split pane shows only that.
///
/// One bar per pane card. A tab switch points the same bar at another tab; the bar reads the
/// store inside an observation scope and changes only the views whose state changed, so a
/// button under the pointer keeps its hover.
@MainActor
final class PaneToolbarView: NSView {
    /// Split view: the pane's tab (nil = the window's selected tab).
    var paneTabID: UUID? { didSet { if paneTabID != oldValue { sync() } } }
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions

    private struct Model: Equatable {
        typealias Kind = ToolbarComposition.Kind
        struct Ext: Equatable { let id: String; let name: String; let icon: NSImage? }
        var kind = Kind.noTab
        var inSplit = false
        var focusedPane = true
        var canGoBack = false
        var canGoForward = false
        var isLoading = false
        var url = ""
        var host = ""
        var path = ""
        var status: ToolbarStatus?
        var sidebarVisible = true
        var pinned: [Ext] = []
        var hasExtensions = false
        var fill = NSColor.clear
        var fg = NSColor.labelColor
        var fgDim = NSColor.secondaryLabelColor
        var placeholder = NSColor.tertiaryLabelColor
        var closeTint = NSColor.secondaryLabelColor
        var hairline: NSColor?
        var dividerColor = NSColor.clear
        /// Icon hover fill. White everywhere, as in Arc, where it doesn't show on a white bar either;
        /// the developer bar is no longer white (GitHub #42).
        var hover = NSColor.white.withAlphaComponent(0.1)
        /// Arc's diagonal stripes behind the developer bar.
        var stripes = false
        /// The developer address field's selected text.
        var selection = NSColor.selectedTextBackgroundColor
        var tabID: UUID?
    }

    private var model = Model()
    private var syncQueued = false
    private var buttons: [String: ToolbarGlyphButton] = [:]
    /// Left group, then trailing items, as laid out.
    private var left: [ToolbarGlyphButton] = []
    private var right: [NSView] = []
    private let urlButton = ToolbarURLButton()
    private let placeholderLabel = NSTextField.sidebarLabel(size: 13)
    private let hairline = NSView()
    private let devDivider = NSView()
    private let stripes = DeveloperStripesView()
    /// Arc lifts the whole developer bar ~9% toward white while its address field is edited.
    private let editVeil = NSView()
    private var press = WindowDragGesture()

    init(paneTabID: UUID?, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions) {
        self.paneTabID = paneTabID
        self.store = store
        self.ui = ui
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        hairline.wantsLayer = true
        devDivider.wantsLayer = true
        stripes.isHidden = true
        addSubview(stripes)
        placeholderLabel.stringValue = "Search or Enter URL…"
        urlButton.action = { [weak self] in self?.editURL() }
        urlButton.onCommit = { [weak self] in self?.actions.loadTyped($0) }
        urlButton.onEditingChange = { [weak self] in self?.editVeil.isHidden = !$0 }
        editVeil.wantsLayer = true
        editVeil.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        for v in [hairline, editVeil, devDivider, urlButton, placeholderLabel] as [NSView] {
            v.isHidden = true
            addSubview(v)
        }
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        (superview as? PaneCardView)?.developerBar = model.kind == .developer ? model.fill : nil
    }

    // MARK: Model

    private func scheduleSync() {
        guard !syncQueued else { return }
        syncQueued = true
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    private func sync() {
        syncQueued = false
        let m = withObservationTracking { build() } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleSync() }
        }
        guard m != model else { return }
        let old = model
        model = m
        apply(old: old)
    }

    private func build() -> Model {
        var m = Model()
        let palette = store.focusedSpace(window: ui.windowID).theme.palette
        let item = paneTabID.flatMap { store.item($0) } ?? (paneTabID == nil ? store.selectedTab(window: ui.windowID) : nil)
        m.inSplit = paneTabID != nil && ui.splitPaneIDs.count > 1
        m.focusedPane = paneTabID == nil || store.selectedTabID(window: ui.windowID) == paneTabID
        let nav = paneTabID.map { ui.navState(for: $0) }
            ?? TabNavState(canGoBack: ui.canGoBack, canGoForward: ui.canGoForward, isLoading: ui.isLoading, themeColor: ui.pageThemeColor)
        m.canGoBack = nav.canGoBack
        m.canGoForward = nav.canGoForward
        m.isLoading = nav.isLoading
        m.status = m.focusedPane ? ui.toolbarStatus : nil
        m.sidebarVisible = store.window(ui.windowID).sidebarVisible
        if let item, item.isEmptyTab {
            m.kind = .emptyPane
        } else if let item, let t = item.tab {
            m.tabID = item.id
            m.kind = !m.inSplit && store.settings.isDeveloperMode(url: t.url) ? .developer : .normal
            m.url = t.url
            let human = SuggestionEngine.humanURL(t.url)
            m.host = AppSettings.siteKey(for: t.url) ?? human
            m.path = human.hasPrefix(m.host) ? String(human.dropFirst(m.host.count)) : ""
        }
        let extensions = ExtensionStore.shared
        let entries = extensions.entries(inProfile: item.map { store.profileDirectoryName(item: $0.id) }
                                         ?? store.profileDirectoryName(space: store.focusedSpaceID(window: ui.windowID)))
        m.hasExtensions = !entries.isEmpty
        m.pinned = extensions.pinnedIDs.compactMap { id in
            entries.first { $0.extensionID == id }.map { Model.Ext(id: id, name: $0.name, icon: extensions.toolbarIcon(for: $0)) }
        }
        // Arc's toolbar colour: the page's theme-color when it declares one, else white until the
        // page reports one (MainWindowController.browserManagerDidUpdate uses the same rule).
        let onCard = m.kind == .normal || m.kind == .developer
        let theme = nav.themeColor
        let cardHex = theme != "none" && !theme.isEmpty && HexColor.components(theme) != nil ? theme : nil
        let light = (cardHex.flatMap(HexColor.luminance) ?? 1) > 0.6
        if onCard {
            m.fill = cardHex.map { NSColor(hex: $0) } ?? .white
            m.fg = light ? NSColor.black.withAlphaComponent(0.8) : NSColor(hex: "#E4E0D4")
            m.fgDim = light ? NSColor.black.withAlphaComponent(0.6) : NSColor(hex: "#F0E6CC").withAlphaComponent(0.9)
        } else {
            m.fill = m.kind == .emptyPane ? .clear : (palette.isDark ? NSColor.white.withAlphaComponent(0.025) : NSColor.black.withAlphaComponent(0.03))
            m.fg = NSColor(palette.textSecondary)
            m.fgDim = NSColor(palette.textTertiary)
            // No hairline under the bar on the card: the bar and the page read as one surface (Arc draws one).
            if m.kind != .emptyPane { m.hairline = palette.isDark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.07) }
        }
        m.placeholder = NSColor(palette.textTertiary)
        m.closeTint = m.kind == .emptyPane ? NSColor(palette.textSecondary) : m.fgDim
        m.dividerColor = light ? NSColor.black.withAlphaComponent(0.15) : NSColor.white.withAlphaComponent(0.22)
        if m.kind == .developer {
            // Arc's developer bar (GitHub #42): the space's colour under faint stripes, whatever the
            // page's theme-color, with near-white ink (Arc's foregroundPrimary, JYSK 236/237/254),
            // a white 10% rule along the bottom and a white 8% hover.
            let theme = store.focusedSpace(window: ui.windowID).theme
            m.fill = theme.developerBarColor
            let ink = NSColor.white.blended(withFraction: 0.07, of: m.fill) ?? .white
            m.fg = ink
            m.fgDim = ink
            m.hairline = NSColor.white.withAlphaComponent(0.1)
            m.dividerColor = theme.developerSecondaryColor.withAlphaComponent(0.45)
            m.selection = theme.developerSecondaryColor.withAlphaComponent(0.6)
            m.hover = NSColor.white.withAlphaComponent(0.08)
            m.stripes = true
        }
        return m
    }

    /// A pinned extension's button (screen rect), for popups opened from the menu bar or a shortcut.
    func extensionButtonFrameOnScreen(_ id: String) -> NSRect? {
        guard let b = buttons["ext:" + id], !b.isHiddenOrHasHiddenAncestor, let window else { return nil }
        return window.convertToScreen(b.convert(b.bounds, to: nil))
    }

    // MARK: Views

    private func button(_ key: String, _ make: () -> ToolbarGlyphButton) -> ToolbarGlyphButton {
        if let b = buttons[key] { return b }
        let b = make()
        buttons[key] = b
        addSubview(b)
        return b
    }

    private func glyph(_ key: String, _ symbol: String, help: String, enabled: Bool = true, width: CGFloat = 26, iconSize: CGFloat = 13,
                       tint: NSColor? = nil, animated: Bool = false, action: @escaping (PaneToolbarView) -> Void) -> ToolbarGlyphButton {
        let b = button(key) { ToolbarGlyphButton() }
        b.configure(symbol: symbol, image: nil, help: help, enabled: enabled, width: width, iconSize: iconSize, tint: tint ?? model.fgDim,
                    hover: model.hover, animated: animated)
        b.action = { [weak self] in if let self { action(self) } }
        return b
    }

    private func apply(old: Model) {
        let m = model
        layer?.backgroundColor = m.fill.cgColor
        stripes.isHidden = !m.stripes
        // The card under the bar takes its colour and height (Arc's developer bar is 40 pt, 32 otherwise).
        (superview as? PaneCardView)?.developerBar = m.kind == .developer ? m.fill : nil
        hairline.isHidden = m.hairline == nil
        hairline.layer?.backgroundColor = m.hairline?.cgColor
        let bar = ToolbarComposition(kind: m.kind, inSplit: m.inSplit, focusedPane: m.focusedPane, canGoBack: m.canGoBack,
                                     canGoForward: m.canGoForward, isLoading: m.isLoading, pinnedExtensions: m.pinned.map(\.id),
                                     hasExtensions: m.hasExtensions)
        // The no-tab bar and an empty pane show navigation that does nothing (Arc greys it out).
        let wide = m.kind == .noTab || m.kind == .emptyPane
        func view(_ item: ToolbarComposition.Item) -> NSView {
            switch item {
            case .toggleSidebar:
                return glyph("toggle", "sidebar.left", help: m.sidebarVisible ? "Hide Sidebar (⌘S)" : "Show Sidebar (⌘S)",
                             width: 37, iconSize: 15.5) { $0.actions.toggleSidebar() }
            case .back(let enabled):
                return glyph("back", "arrow.left", help: wide ? "" : "Go Back (⌘[)", enabled: enabled, width: 37, iconSize: 15) { if !wide { $0.navigate("goBack") } }
            case .forward(let enabled):
                return glyph("forward", "arrow.right", help: wide ? "" : "Go Forward (⌘])", enabled: enabled, width: 37, iconSize: 15) { if !wide { $0.navigate("goForward") } }
            case .reload(let loading, let enabled):
                return glyph("reload", loading ? "xmark" : "arrow.clockwise", help: enabled ? "Refresh (⌘R)" : "", enabled: enabled, width: 37,
                             iconSize: 15, animated: enabled) { if !wide { $0.navigate("reload") } }
            case .copyURL:
                return glyph("copy", "link", help: "Copy URL (⇧⌘C)", width: 28) { $0.actions.performAction("copyURL") }
            case .divider:
                return devDivider
            case .devTools:
                return glyph("devtools", "terminal", help: "Developer Tools (⌥⌘I)", width: 28) { $0.actions.performAction("devTools") }
            case .pinnedExtension(let id):
                let e = m.pinned.first { $0.id == id }
                let b = button("ext:" + id) { ToolbarGlyphButton() }
                b.configure(symbol: nil, image: e?.icon, help: e?.name ?? "", enabled: true, width: 34, iconSize: 18, tint: m.fgDim, hover: m.hover)
                b.action = { [weak self] in self?.actions.runExtension(id) }
                b.menuProvider = { ExtensionStore.shared.entries.first { $0.extensionID == id }.map(ExtensionsMenu.iconMenu) }
                return b
            case .extensions:
                return glyph("extensions", "slider.horizontal.2.square", help: "Extensions", width: 34, iconSize: 16) { $0.actions.showExtensionsMenu() }
            case .addSplit:
                return glyph("split", "square.split.2x1", help: "Add Split View (⌃⇧=)", width: 34, iconSize: 16) { $0.actions.performAction("addSplitView") }
            case .splitOptions:
                return glyph("splitOptions", "rectangle.split.2x1", help: "Split View Options") { $0.showSplitMenu(from: $0.buttons["splitOptions"]) }
            case .closePane:
                let id = paneTabID
                return glyph("close", "xmark", help: "Close this Split Pane (⌃⇧-)", width: 30, iconSize: 14, tint: m.closeTint) {
                    if let id { $0.actions.closePane(id) }
                }
            }
        }
        let l = bar.left.compactMap { view($0) as? ToolbarGlyphButton }
        let r = bar.right.map(view)
        devDivider.layer?.backgroundColor = m.dividerColor.cgColor
        let used = Set((l as [NSView] + r).map(ObjectIdentifier.init))
        for (k, b) in buttons where !used.contains(ObjectIdentifier(b)) {
            b.removeFromSuperview()
            buttons[k] = nil
        }
        devDivider.isHidden = !r.contains { $0 === devDivider }
        left = l
        right = r

        if m.kind != .developer || m.tabID != old.tabID { urlButton.endEditing(commit: false) }
        switch m.kind {
        case .normal, .developer:
            urlButton.isHidden = false
            placeholderLabel.isHidden = true
            // Arc's developer URL has no hover fill (it edits in place on a click).
            let urlHover = m.kind == .developer ? NSColor.clear : NSColor.white.withAlphaComponent(0.08)
            urlButton.show(host: m.host, path: m.path, url: m.url, developer: m.kind == .developer, status: m.status,
                           fg: m.fg, fgDim: m.fgDim, hover: urlHover, animated: old.status?.id != m.status?.id && window != nil)
            urlButton.selection = m.selection
        case .noTab, .emptyPane:
            urlButton.isHidden = true
            placeholderLabel.isHidden = false
            placeholderLabel.textColor = m.placeholder
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let h = bounds.height, w = bounds.width
        let m = model
        hairline.frame = NSRect(x: 0, y: h - 1, width: w, height: 1)
        stripes.frame = bounds
        editVeil.frame = bounds
        // Buttons are 26 pt boxes on the 32 pt bar, 28 pt on the 40 pt developer bar (Arc).
        let bh: CGFloat = m.kind == .developer ? 28 : 26
        for b in buttons.values {
            b.cornerRadius = m.kind == .developer ? 6 : 7
            b.iconRowHeight = bh
        }
        // Left group: icons edge to edge.
        var x: CGFloat = m.kind == .emptyPane ? 1 : (m.inSplit ? 2.5 : 11.5)
        for b in left {
            b.frame = NSRect(x: x, y: (h - bh) / 2, width: b.width, height: bh)
            x += b.width
        }
        let leftEnd = left.isEmpty ? 0 : x
        // Right group, from the trailing edge: pinned extensions … Split View 6 pt in; a split pane's
        // close 4 pt in; developer copy · divider · DevTools spaced like the HStack around them.
        var rx = w - (m.inSplit ? 4 : (right.isEmpty ? 0 : 6))
        var trailing = right
        var devGroup: [NSView] = []
        if m.kind == .developer, let i = trailing.firstIndex(where: { $0 === devDivider }) {
            devGroup = Array(trailing[(i - 1)...(i + 1)])
            trailing.removeSubrange((i - 1)...(i + 1))
        }
        for v in trailing.reversed() {
            let bw = (v as? ToolbarGlyphButton)?.width ?? 26
            rx -= bw
            v.frame = NSRect(x: rx, y: (h - bh) / 2, width: bw, height: bh)
        }
        if !devGroup.isEmpty {
            if !trailing.isEmpty { rx -= 6 }
            for v in devGroup.reversed() {
                if v === devDivider {
                    rx -= 6 + 5 + 1
                    v.frame = NSRect(x: rx, y: (h - 14) / 2, width: 1, height: 14)
                    rx -= 5 + 6
                } else {
                    let bw = (v as? ToolbarGlyphButton)?.width ?? 26
                    rx -= bw
                    v.frame = NSRect(x: rx, y: (h - bh) / 2, width: bw, height: bh)
                }
            }
        }
        let rightStart = rx
        // The middle, between the groups with the HStack's 6 pt spacing around it.
        let a = leftEnd + (left.isEmpty ? 0 : 6), b = rightStart - (right.isEmpty ? 0 : 6)
        switch m.kind {
        case .normal:
            // Spacer(min 8) either side, the URL centred between them.
            let room = max(0, b - a - 2 * (8 + 6))
            let uw = min(urlButton.idealWidth, room)
            let ux = a + (b - a - uw) / 2
            urlButton.frame = NSRect(x: ux, y: (h - 28) / 2, width: uw, height: 28)
        case .developer:
            // The URL fills half the room after its 8 pt lead; a Spacer(min 8) takes the rest.
            let start = a + 8
            let room = max(0, b - start - 6 - 8)
            urlButton.frame = NSRect(x: start, y: (h - 28) / 2, width: room / 2 + 8, height: 28)
        case .noTab, .emptyPane:
            let s = placeholderLabel.intrinsicContentSize
            let pw = min(ceil(placeholderLabel.attributedStringValue.size().width), max(0, b - a))
            placeholderLabel.frame = NSRect(x: a + (b - a - pw) / 2 - SidebarText.inset, y: (h - s.height) / 2,
                                            width: pw + 2 * SidebarText.inset, height: s.height)
        }
    }

    // MARK: Actions

    private func navigate(_ what: String) {
        if let id = paneTabID { actions.paneNavigate(id, what); return }
        switch what {
        case "goBack": actions.goBack()
        case "goForward": actions.goForward()
        default: actions.reload()
        }
    }

    /// Arc: the developer bar edits its full URL in place (ContentPanelTextField, GitHub #42); every
    /// other bar opens the command bar.
    private func editURL() {
        if model.kind == .developer, !urlButton.isHidden { urlButton.beginEditing(); return }
        if let id = paneTabID { actions.editPaneURL(id) } else { actions.openCommandBar(model.kind == .noTab ? .newTab : .editURL) }
    }

    private func showSplitMenu(from view: NSView?) {
        guard let id = paneTabID, let view else { return }
        let menu = NSMenu()
        let items: [(String, () -> Void)?] = [
            ("Separate Tab from Split", { [weak self] in self?.actions.separatePane(id) }),
            ("Flip Split View Orientation", { [weak self] in self?.actions.performAction("flipSplitOrientation") }),
            nil,
            ("Copy Link", { [weak self] in self?.actions.performAction("copyURL") }),
            nil,
            ("Close this Split Pane", { [weak self] in self?.actions.closePane(id) }),
        ]
        for entry in items {
            guard let (title, run) = entry else { menu.addItem(.separator()); continue }
            menu.addItem(ToolbarMenuAction.item(title, run))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    // A click anywhere on the bar edits the URL (a pane's click also focuses it); a drag moves
    // the window, as on Arc's toolbar.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { takesClickFromChildWindow }
    override func mouseDown(with event: NSEvent) { press.begin(event) }
    override func mouseDragged(with event: NSEvent) { press.drag(event) }
    override func mouseUp(with event: NSEvent) {
        if press.finish() { editURL() }
    }
}

private final class ToolbarMenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }

    static func item(_ title: String, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = ToolbarMenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        item.target = a
        item.representedObject = a
        return item
    }
}

/// ToolbarIcon / ToolbarImageButton: a glyph (or an extension's icon) with a rounded hover fill.
final class ToolbarGlyphButton: NSView {
    var action: () -> Void = {}
    /// Right-click menu (a pinned extension's icon options).
    var menuProvider: (() -> NSMenu?)?
    private(set) var width: CGFloat = 26
    private let imageView = NSImageView()
    private var tip: ArcTooltipAnchorView?
    private var enabled = true
    private var contextClick = false
    /// Arc turns the refresh arrow while it is pressed (NSImageView.pressTurn).
    private var turnsOnPress = false
    private var hovering = false { didSet { if hovering != oldValue { refreshFill() } } }
    private var shown: (String?, NSImage?, CGFloat, NSColor, Bool)?
    private var hover = NSColor.white.withAlphaComponent(0.1)
    private var iconBox: NSSize?
    var cornerRadius: CGFloat = 7 { didSet { layer?.cornerRadius = cornerRadius } }
    /// The height an extension icon is centred in, from the bottom (the toolbar sets its button height;
    /// the sidebar pill keeps the 26 pt it was laid out with).
    var iconRowHeight: CGFloat = 26 { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError() }

    /// `animated` swaps another symbol in the way Arc swaps refresh and stop.
    func configure(symbol: String?, image: NSImage?, help: String, enabled: Bool, width: CGFloat, iconSize: CGFloat, tint: NSColor,
                   hover: NSColor = .white.withAlphaComponent(0.1), animated: Bool = false) {
        self.width = width
        self.enabled = enabled
        self.hover = hover
        if shown == nil || shown!.0 != symbol || shown!.1 !== image || shown!.2 != iconSize || shown!.3 != tint || shown!.4 != enabled {
            let was = shown?.0
            shown = (symbol, image, iconSize, tint, enabled)
            if let symbol {
                imageView.imageScaling = .scaleNone
                let glyph = SidebarSymbols.image(symbol, size: iconSize)
                if animated, was != nil, was != symbol { imageView.swapSymbol(glyph) } else { imageView.image = glyph }
                turnsOnPress = animated && symbol == "arrow.clockwise"
                imageView.contentTintColor = enabled ? tint : tint.withAlphaComponent(tint.alphaComponent * 0.4)
            } else {
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.image = image ?? SidebarSymbols.image("puzzlepiece.extension", size: iconSize)
                // A monochrome extension icon (ExtensionStore.toolbarIcon) is a template: the bar's ink.
                imageView.contentTintColor = image == nil || image?.isTemplate == true ? tint : nil
            }
        }
        iconBox = symbol == nil ? NSSize(width: iconSize, height: iconSize) : nil
        needsLayout = true
        if help.isEmpty {
            tip?.removeFromSuperview()
            tip = nil
        } else if let tip {
            (tip.text, tip.keys) = ArcTooltipLabel.split(help)
        } else {
            tip = ArcTooltipAnchorView.attach(to: self, help: help)
        }
        refreshFill()
    }

    override func layout() {
        super.layout()
        let h = bounds.height
        imageView.frame = iconBox.map { NSRect(x: (width - $0.width) / 2, y: (iconRowHeight - $0.height) / 2, width: $0.width, height: $0.height) }
            ?? NSRect(x: 0, y: 0, width: width, height: h)
    }

    private func refreshFill() {
        layer?.backgroundColor = (hovering && enabled ? hover : .clear).cgColor
    }

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { takesClickFromChildWindow }
    /// The button takes its clicks itself: AppKit asks the hit view about the first click, and
    /// that was the glyph's image view.
    override func hitTest(_ point: NSPoint) -> NSView? { frame.contains(point) ? self : nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {
        contextClick = event.modifierFlags.contains(.control) && menuProvider != nil
        if contextClick, let menu = menuProvider?() { NSMenu.popUpContextMenu(menu, with: event, for: self) }
        if !contextClick, turnsOnPress, enabled { imageView.pressTurn(true) }
    }
    override func mouseDragged(with event: NSEvent) {
        if !contextClick, turnsOnPress, enabled { imageView.pressTurn(bounds.contains(convert(event.locationInWindow, from: nil))) }
    }
    override func mouseUp(with event: NSEvent) {
        if turnsOnPress { imageView.pressTurn(false) }
        if !contextClick, enabled, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
}

/// The URL in the middle of the bar: link glyph, host bright and path dimmer (the full URL in
/// monospace after a lock in developer mode), or the nav-bar status in its place.
final class ToolbarURLButton: NSView, NSTextFieldDelegate {
    var action: () -> Void = {}
    /// Developer mode's in-place address field: the text Return submits, and editing starting/ending.
    var onCommit: (String) -> Void = { _ in }
    var onEditingChange: (Bool) -> Void = { _ in }
    var selection = NSColor.selectedTextBackgroundColor
    private var field: NSTextField?
    private var savedSelectionAttributes: [NSAttributedString.Key: Any]?
    private var resignObserver: NSObjectProtocol?
    private var url = ""
    private var ink = NSColor.white
    private var press = WindowDragGesture()
    private let content = NSView()
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 13)
    private let tip: ArcTooltipAnchorView
    private var developer = false
    private var hover = NSColor.white.withAlphaComponent(0.08)
    private var hovering = false { didSet { refreshFill() } }

    override init(frame: NSRect) {
        tip = ArcTooltipAnchorView(frame: .zero)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        icon.imageScaling = .scaleNone
        content.wantsLayer = true
        content.addSubview(icon)
        content.addSubview(label)
        addSubview(content)
        tip.followsCursor = true
        tip.frame = bounds
        tip.autoresizingMask = [.width, .height]
        addSubview(tip)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { takesClickFromChildWindow }
    /// Clicks land on the button, not its label (AppKit asks the hit view about the first click);
    /// the address field takes its own while editing.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard frame.contains(point) else { return nil }
        return field == nil ? self : super.hitTest(point)
    }

    /// The text's natural width plus padding; the bar centres and clips the button to it.
    var idealWidth: CGFloat {
        ceil(10 + iconWidth + 7 + label.attributedStringValue.size().width + 10)
    }

    /// The glyph's own width, as SwiftUI lays an Image out; developer mode boxes it at 14 pt.
    private var iconWidth: CGFloat { developer ? 14 : ceil(icon.image?.size.width ?? 12) }

    func show(host: String, path: String, url: String, developer: Bool, status: ToolbarStatus?, fg: NSColor, fgDim: NSColor, hover: NSColor,
              animated: Bool) {
        self.developer = developer
        self.hover = hover
        self.url = url
        ink = fg
        field?.textColor = fg
        refreshFill()
        tip.text = url
        if animated {
            // SwiftUI's .transition(.opacity) on the status swap.
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.15
            content.layer?.add(fade, forKey: "fade")
        }
        if let status {
            icon.image = SidebarSymbols.image(status.symbol, size: 12, weight: .medium)
            icon.contentTintColor = fgDim
            label.attributedStringValue = NSAttributedString(string: status.text, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: fgDim])
        } else if developer {
            icon.image = SidebarSymbols.image(url.hasPrefix("https://") ? "lock.fill" : "globe", size: 11, weight: .semibold)
            icon.contentTintColor = fgDim
            label.attributedStringValue = NSAttributedString(string: url, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: fg])
        } else {
            icon.image = SidebarSymbols.image("link", size: 12, weight: .medium)
            icon.contentTintColor = fgDim
            let s = NSMutableAttributedString(string: host, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: fg])
            s.append(NSAttributedString(string: path, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: fgDim]))
            label.attributedStringValue = s
        }
        label.lineBreakMode = .byTruncatingTail
        layer?.cornerRadius = developer ? 6 : 7
        needsLayout = true
    }

    override func layout() {
        super.layout()
        content.frame = bounds
        let h = bounds.height
        let pad: CGFloat = developer ? 6 : 10
        let iconW = iconWidth
        let gap: CGFloat = developer ? 12 : 7
        icon.frame = NSRect(x: pad, y: 0, width: iconW, height: h)
        let lh = label.intrinsicContentSize.height
        let lx = pad + iconW + gap
        label.frame = NSRect(x: lx - SidebarText.inset, y: (h - lh) / 2, width: max(0, bounds.width - lx - pad) + 2 * SidebarText.inset, height: lh)
        field?.frame = label.frame
    }

    var isEditing: Bool { field != nil }

    /// The full URL becomes editable where it is drawn, all of it selected, in Arc's selection tint.
    func beginEditing() {
        guard field == nil, let window else { return }
        let f = NSTextField(string: url)
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        f.textColor = ink
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.delegate = self
        f.frame = label.frame
        content.addSubview(f)
        field = f
        label.isHidden = true
        tip.isHidden = true
        window.makeKey()
        window.makeFirstResponder(f)
        if let editor = f.currentEditor() as? NSTextView {
            // The window's field editor is shared: put its selection colours back afterwards.
            savedSelectionAttributes = editor.selectedTextAttributes
            editor.selectedTextAttributes = [.backgroundColor: selection, .foregroundColor: ink]
            editor.insertionPointColor = ink
            editor.selectAll(nil)
        }
        // A click into the page (its own window) ends the edit, like a click elsewhere on the bar.
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endEditing(commit: false) }
        }
        onEditingChange(true)
    }

    /// Return loads what was typed; anything else puts the URL back.
    func endEditing(commit: Bool) {
        guard let f = field else { return }
        field = nil
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        resignObserver = nil
        let text = f.stringValue
        if let editor = f.currentEditor() as? NSTextView, let saved = savedSelectionAttributes { editor.selectedTextAttributes = saved }
        savedSelectionAttributes = nil
        if f.currentEditor() != nil { f.window?.makeFirstResponder(nil) }
        f.removeFromSuperview()
        label.isHidden = false
        tip.isHidden = false
        onEditingChange(false)
        if commit { onCommit(text) }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)): endEditing(commit: true)
        // A field editor reads Esc as complete: (word completion), ⌘. as cancelOperation:.
        case #selector(NSResponder.cancelOperation(_:)), #selector(NSResponder.complete(_:)): endEditing(commit: false)
        default: return false
        }
        return true
    }

    func controlTextDidEndEditing(_ obj: Notification) { endEditing(commit: false) }

    private func refreshFill() {
        layer?.backgroundColor = (hovering ? hover : .clear).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    // Part of the bar: a click edits the URL, a drag moves the window like the rest of it.
    override func mouseDown(with event: NSEvent) { press.begin(event) }
    override func mouseDragged(with event: NSEvent) { press.drag(event) }
    override func mouseUp(with event: NSEvent) {
        if press.finish(), bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}

/// Arc's developer-bar stripes (GitHub #42), measured on Arc 1.170 at 2x: white 2% bands at 45°
/// running down to the right, 21 pt wide along the bar every 45 pt, the first band starting
/// 14.5 pt from the bar's left edge at its top.
final class DeveloperStripesView: NSView {
    private static let pitch: CGFloat = 45, band: CGFloat = 21, phase: CGFloat = 14.5

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let h = bounds.height, w = bounds.width
        let path = NSBezierPath()
        var x = Self.phase - (floor((Self.phase + h) / Self.pitch) + 1) * Self.pitch
        while x < w {
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x + Self.band, y: 0))
            path.line(to: NSPoint(x: x + Self.band + h, y: h))
            path.line(to: NSPoint(x: x + h, y: h))
            path.close()
            x += Self.pitch
        }
        NSColor.white.withAlphaComponent(0.02).setFill()
        path.fill()
    }
}
