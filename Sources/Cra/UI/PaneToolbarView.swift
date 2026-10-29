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
        enum Kind: Equatable { case noTab, emptyPane, normal, developer }
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
    private var placeholderDrag = WindowDragGesture()

    init(paneTabID: UUID?, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions) {
        self.paneTabID = paneTabID
        self.store = store
        self.ui = ui
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        hairline.wantsLayer = true
        devDivider.wantsLayer = true
        placeholderLabel.stringValue = "Search or Enter URL…"
        urlButton.action = { [weak self] in self?.editURL() }
        for v in [hairline, devDivider, urlButton, placeholderLabel] as [NSView] {
            v.isHidden = true
            addSubview(v)
        }
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

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
        } else if let t = item?.tab {
            m.kind = !m.inSplit && store.settings.isDeveloperMode(url: t.url) ? .developer : .normal
            m.url = t.url
            let human = SuggestionEngine.humanURL(t.url)
            m.host = AppSettings.siteKey(for: t.url) ?? human
            m.path = human.hasPrefix(m.host) ? String(human.dropFirst(m.host.count)) : ""
        }
        let extensions = ExtensionStore.shared
        m.hasExtensions = !extensions.entries.isEmpty
        m.pinned = extensions.pinnedIDs.compactMap { id in
            extensions.entries.first { $0.extensionID == id }.map { Model.Ext(id: id, name: $0.name, icon: extensions.toolbarIcon(for: $0)) }
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
        return m
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
                       tint: NSColor? = nil, action: @escaping (PaneToolbarView) -> Void) -> ToolbarGlyphButton {
        let b = button(key) { ToolbarGlyphButton() }
        b.configure(symbol: symbol, image: nil, help: help, enabled: enabled, width: width, iconSize: iconSize, tint: tint ?? model.fgDim)
        b.action = { [weak self] in if let self { action(self) } }
        return b
    }

    private func apply(old: Model) {
        let m = model
        layer?.backgroundColor = m.fill.cgColor
        hairline.isHidden = m.hairline == nil
        hairline.layer?.backgroundColor = m.hairline?.cgColor
        var l: [ToolbarGlyphButton] = []
        var r: [NSView] = []
        let toggle = { self.glyph("toggle", "sidebar.left", help: m.sidebarVisible ? "Hide Sidebar (⌘S)" : "Show Sidebar (⌘S)",
                                  width: 37, iconSize: 15.5) { $0.actions.toggleSidebar() } }
        switch m.kind {
        case .noTab:
            l = [toggle(),
                 glyph("back", "arrow.left", help: "", enabled: false, width: 37, iconSize: 15) { _ in },
                 glyph("forward", "arrow.right", help: "", enabled: false, width: 37, iconSize: 15) { _ in },
                 glyph("reload", "arrow.clockwise", help: "", enabled: false, width: 37, iconSize: 15) { _ in }]
        case .emptyPane:
            l = [glyph("back", "arrow.left", help: "", enabled: false, width: 37, iconSize: 15) { _ in },
                 glyph("forward", "arrow.right", help: "", enabled: false, width: 37, iconSize: 15) { _ in }]
        case .normal:
            // Toggle first, centred 30 pt from the card edge (Arc, sidebar hidden), then ← → ↻ at 37 pt
            // pitch. Split panes drop the toggle and refresh (Arc 1.170: only ← → in a pane).
            if !m.inSplit { l.append(toggle()) }
            l.append(glyph("back", "arrow.left", help: "Go Back (⌘[)", enabled: m.canGoBack, width: 37, iconSize: 15) { $0.navigate("goBack") })
            l.append(glyph("forward", "arrow.right", help: "Go Forward (⌘])", enabled: m.canGoForward, width: 37, iconSize: 15) { $0.navigate("goForward") })
            if !m.inSplit {
                l.append(glyph("reload", m.isLoading ? "xmark" : "arrow.clockwise", help: "Refresh (⌘R)", width: 37, iconSize: 15) { $0.navigate("reload") })
            }
        case .developer:
            if !m.inSplit { l.append(toggle()) }
            r.append(glyph("copy", "link", help: "Copy URL (⇧⌘C)") { $0.actions.performAction("copyURL") })
            r.append(devDivider)
            r.append(glyph("devtools", "terminal", help: "Developer Tools (⌥⌘I)") { $0.actions.performAction("devTools") })
        }
        // Arc's right end of the bar: pinned extensions, the Extensions button, then Split View;
        // also on the no-tab bar. A split pane has its options (focused pane only) and close.
        if !m.inSplit, m.kind != .emptyPane {
            for e in m.pinned {
                let b = button("ext:" + e.id) { ToolbarGlyphButton() }
                b.configure(symbol: nil, image: e.icon, help: e.name, enabled: true, width: 34, iconSize: 18, tint: m.fgDim)
                let id = e.id
                b.action = { [weak self] in self?.actions.runExtension(id) }
                b.menuProvider = { ExtensionStore.shared.entries.first { $0.extensionID == id }.map(ExtensionsMenu.iconMenu) }
                r.append(b)
            }
            if m.hasExtensions {
                r.append(glyph("extensions", "slider.horizontal.2.square", help: "Extensions", width: 34, iconSize: 16) { $0.actions.showExtensionsMenu() })
            }
            r.append(glyph("split", "square.split.2x1", help: "Add Split View (⌃⇧=)", width: 34, iconSize: 16) { $0.actions.performAction("addSplitView") })
        }
        if m.inSplit, let id = paneTabID {
            if m.focusedPane, m.kind != .emptyPane {
                r.append(glyph("splitOptions", "rectangle.split.2x1", help: "Split View Options") { $0.showSplitMenu(from: $0.buttons["splitOptions"]) })
            }
            r.append(glyph("close", "xmark", help: "Close this Split Pane (⌃⇧-)", width: 30, iconSize: 14, tint: m.closeTint) { $0.actions.closePane(id) })
        }
        devDivider.layer?.backgroundColor = m.dividerColor.cgColor
        let used = Set((l as [NSView] + r).map(ObjectIdentifier.init))
        for (k, b) in buttons where !used.contains(ObjectIdentifier(b)) {
            b.removeFromSuperview()
            buttons[k] = nil
        }
        devDivider.isHidden = !r.contains { $0 === devDivider }
        left = l
        right = r

        switch m.kind {
        case .normal, .developer:
            urlButton.isHidden = false
            placeholderLabel.isHidden = true
            urlButton.show(host: m.host, path: m.path, url: m.url, developer: m.kind == .developer, status: m.status,
                           fg: m.fg, fgDim: m.fgDim, animated: old.status?.id != m.status?.id && window != nil)
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
        // Left group: icons edge to edge.
        var x: CGFloat = m.kind == .emptyPane ? 1 : (m.inSplit ? 2.5 : 11.5)
        for b in left {
            b.frame = NSRect(x: x, y: (h - 26) / 2, width: b.width, height: 26)
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
            v.frame = NSRect(x: rx, y: (h - 26) / 2, width: bw, height: 26)
        }
        if !devGroup.isEmpty {
            if !trailing.isEmpty { rx -= 6 }
            for v in devGroup.reversed() {
                if v === devDivider {
                    rx -= 6 + 5 + 1
                    v.frame = NSRect(x: rx, y: (h - 14) / 2, width: 1, height: 14)
                    rx -= 5 + 6
                } else {
                    rx -= 26
                    v.frame = NSRect(x: rx, y: (h - 26) / 2, width: 26, height: 26)
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

    private func editURL() {
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

    // Empty toolbar space is a title bar. Starting the system drag on mouse-down keeps
    // this broad area usable even when the pointer moves quickly; the URL has its own
    // click-versus-drag handling below.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        _ = placeholderDrag.finish()
        if !placeholderLabel.isHidden,
           placeholderLabel.frame.contains(convert(event.locationInWindow, from: nil)) {
            placeholderDrag.begin(with: event)
            return
        }
        guard let window = NativeWindowDrag.target(for: window) else { return }
        if event.clickCount == 2 { (window as? CraWindow)?.performTitleDoubleClickAction() }
        else { NativeWindowDrag.start(with: event, in: window) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let press = placeholderDrag.dragEvent(for: event) else { return }
        NativeWindowDrag.start(with: press, in: window)
    }
    override func mouseUp(with event: NSEvent) {
        if placeholderDrag.finish(), placeholderLabel.frame.contains(convert(event.locationInWindow, from: nil)) { editURL() }
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
    private var hovering = false { didSet { if hovering != oldValue { refreshFill() } } }
    private var shown: (String?, NSImage?, CGFloat, NSColor, Bool)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        imageView.imageScaling = .scaleNone
        addSubview(imageView)
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(symbol: String?, image: NSImage?, help: String, enabled: Bool, width: CGFloat, iconSize: CGFloat, tint: NSColor) {
        self.width = width
        self.enabled = enabled
        if shown == nil || shown!.0 != symbol || shown!.1 !== image || shown!.2 != iconSize || shown!.3 != tint || shown!.4 != enabled {
            shown = (symbol, image, iconSize, tint, enabled)
            if let symbol {
                imageView.imageScaling = .scaleNone
                imageView.image = SidebarSymbols.image(symbol, size: iconSize)
                imageView.contentTintColor = enabled ? tint : tint.withAlphaComponent(tint.alphaComponent * 0.4)
            } else {
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.image = image ?? SidebarSymbols.image("puzzlepiece.extension", size: iconSize)
                // A monochrome extension icon (ExtensionStore.toolbarIcon) is a template: the bar's ink.
                imageView.contentTintColor = image == nil || image?.isTemplate == true ? tint : nil
            }
        }
        let iconBox = symbol == nil ? NSSize(width: iconSize, height: iconSize) : nil
        imageView.frame = iconBox.map { NSRect(x: (width - $0.width) / 2, y: (26 - $0.height) / 2, width: $0.width, height: $0.height) }
            ?? NSRect(x: 0, y: 0, width: width, height: 26)
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

    private func refreshFill() {
        layer?.backgroundColor = (hovering && enabled ? NSColor.white.withAlphaComponent(0.1) : .clear).cgColor
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if enabled, bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
}

/// The URL in the middle of the bar: link glyph, host bright and path dimmer (the full URL in
/// monospace after a lock in developer mode), or the nav-bar status in its place.
final class ToolbarURLButton: NSView {
    var action: () -> Void = {}
    private var windowDrag = WindowDragGesture()
    private let content = NSView()
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 13)
    private let tip: ArcTooltipAnchorView
    private var developer = false
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

    /// The text's natural width plus padding; the bar centres and clips the button to it.
    var idealWidth: CGFloat {
        ceil(10 + iconWidth + 7 + label.attributedStringValue.size().width + 10)
    }

    /// The glyph's own width, as SwiftUI lays an Image out; developer mode boxes it at 14 pt.
    private var iconWidth: CGFloat { developer ? 14 : ceil(icon.image?.size.width ?? 12) }

    func show(host: String, path: String, url: String, developer: Bool, status: ToolbarStatus?, fg: NSColor, fgDim: NSColor, animated: Bool) {
        self.developer = developer
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
    }

    private func refreshFill() {
        layer?.backgroundColor = (hovering ? NSColor.white.withAlphaComponent(0.08) : .clear).cgColor
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { windowDrag.begin(with: event) }
    override func mouseDragged(with event: NSEvent) {
        guard let press = windowDrag.dragEvent(for: event) else { return }
        NativeWindowDrag.start(with: press, in: window)
    }
    override func mouseUp(with event: NSEvent) {
        if windowDrag.finish(), bounds.contains(convert(event.locationInWindow, from: nil)) { action() }
    }
}
