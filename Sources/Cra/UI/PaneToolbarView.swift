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
    /// Between Arc's 32 pt right-hand boxes: a 36 pt pitch.
    static let rightGap: CGFloat = 4
    /// Split view: the pane's tab (nil = the window's selected tab).
    var paneTabID: UUID? { didSet { if paneTabID != oldValue { sync() } } }
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions

    private struct Model: Equatable {
        typealias Kind = ToolbarComposition.Kind
        struct Ext: Equatable { let id: String; let name: String; let icon: NSImage?; let badge: ExtensionBadge? }
        var kind = Kind.noTab
        var inSplit = false
        var focusedPane = true
        /// The pointer is over the bar: an unfocused pane shows its controls (Arc's onHover blueprint).
        var hovered = false
        var canGoBack = false
        var canGoForward = false
        var isLoading = false
        var url = ""
        var host = ""
        var path = ""
        var sidebarVisible = true
        var pinned: [Ext] = []
        /// A WebKit page's service: its extension buttons dim (none run there).
        var protectedMedia: String?
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
    /// Arc's rule between the developer buttons and the extensions.
    private let devTrailingDivider = NSView()
    private let stripes = DeveloperStripesView()
    /// Arc lifts the whole developer bar ~9% toward white while its address field is edited.
    private let editVeil = NSView()
    private var press = WindowDragGesture()
    /// Not store state: the tracking area sets it and syncs.
    private var hovered = false {
        didSet { if hovered != oldValue { sync() } }
    }
    private var hoverArea: NSTrackingArea?

    init(paneTabID: UUID?, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions) {
        self.paneTabID = paneTabID
        self.store = store
        self.ui = ui
        self.actions = actions
        super.init(frame: .zero)
        wantsLayer = true
        hairline.wantsLayer = true
        devDivider.wantsLayer = true
        devTrailingDivider.wantsLayer = true
        stripes.isHidden = true
        addSubview(stripes)
        placeholderLabel.stringValue = "Search or Enter URL…"
        urlButton.action = { [weak self] in self?.editURL() }
        urlButton.onCopy = { [weak self] in self?.copyURL() }
        urlButton.menuProvider = { [weak self] in self?.addressMenu() }
        urlButton.onCommit = { [weak self] in self?.actions.loadTyped($0) }
        urlButton.onEditingChange = { [weak self] in self?.editVeil.isHidden = !$0 }
        editVeil.wantsLayer = true
        editVeil.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        for v in [hairline, editVeil, devDivider, devTrailingDivider, urlButton, placeholderLabel] as [NSView] {
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

    // Arc reveals an unfocused pane's controls while the pointer is over its bar (its
    // ContentToolbarInteractionTracker hover session). Active always: the key window is often
    // a page's.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        hoverArea = area
        if let window {
            let inside = !isHiddenOrHasHiddenAncestor && bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
            if inside != hovered { hovered = inside }
        }
    }

    override func mouseEntered(with event: NSEvent) { hovered = true }
    override func mouseExited(with event: NSEvent) { hovered = false }

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
        m.hovered = m.inSplit && hovered
        let nav = paneTabID.map { ui.navState(for: $0) }
            ?? TabNavState(canGoBack: ui.canGoBack, canGoForward: ui.canGoForward, isLoading: ui.isLoading, themeColor: ui.pageThemeColor)
        m.canGoBack = nav.canGoBack
        m.canGoForward = nav.canGoForward
        m.isLoading = nav.isLoading
        m.sidebarVisible = store.window(ui.windowID).sidebarVisible
        if let item, item.isEmptyTab {
            m.kind = .emptyPane
        } else if let item, let t = item.tab {
            m.tabID = item.id
            m.kind = !m.inSplit && store.settings.isDeveloperMode(url: t.url) ? .developer : .normal
            m.url = t.url
            let human = SuggestionEngine.humanURL(t.url)
            m.host = AppSettings.siteKey(for: t.url) ?? human
            // Arc shows the host only unless "Show Full URL" is on (#88).
            m.path = store.settings.toolbarShowsFullURL && human.hasPrefix(m.host) ? String(human.dropFirst(m.host.count)) : ""
            // An easel's bar shows its name (Arc 1.172.1).
            if Easel.id(fromURL: t.url) != nil { m.host = item.displayTitle; m.path = "" }
        }
        m.protectedMedia = m.tabID.flatMap { ui.navState(for: $0).protectedMedia }
        let extensions = ExtensionStore.shared
        let profile = item.map { store.profileDirectoryName(item: $0.id) }
            ?? store.profileDirectoryName(space: store.focusedSpaceID(window: ui.windowID))
        let entries = extensions.entries(inProfile: profile)
        m.pinned = extensions.pinnedIDs(inProfile: profile).compactMap { id in
            entries.first { $0.extensionID == id }.map {
                Model.Ext(id: id, name: $0.name, icon: extensions.toolbarIcon(for: $0, profile: profile, tab: m.tabID),
                          badge: extensions.badge(for: $0, profile: profile, tab: m.tabID))
            }
        }
        // Arc's toolbar colour (ToolbarColor): the page's report, else the tab's last colour, else
        // white (MainWindowController.toolbarColors uses the same rule for the card behind the bar).
        // The tab's own colour counts until its page is live: retarget builds this before it is.
        let onCard = m.kind == .normal || m.kind == .developer
        let cardHex = ToolbarColor.hex(reported: nav.themeColor, remembered: item?.tab?.themeColor)
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
    func extensionButtonFrameOnScreen(_ id: String) -> NSRect? { buttonFrameOnScreen("ext:" + id) }

    /// The sliders button (screen rect), for the Site Control Center opened from elsewhere (a toast's Why?).
    func siteControlsButtonFrameOnScreen() -> NSRect? { buttonFrameOnScreen("extensions") }

    private func buttonFrameOnScreen(_ key: String) -> NSRect? {
        guard let b = buttons[key], !b.isHiddenOrHasHiddenAncestor, b.frame.width > 0, let window else { return nil }
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
        // A tab's bar fades to the colour its page reports, like Arc's (white to the page's colour over
        // 14-16 frames at 100 fps, ease in and out, measured for GitHub #84). A tab switch is instant.
        if m.kind == .normal, old.kind == .normal, m.tabID != nil, m.tabID == old.tabID, m.fill != old.fill, let layer {
            let fade = CABasicAnimation(keyPath: "backgroundColor")
            fade.fromValue = layer.presentation()?.backgroundColor ?? old.fill.cgColor
            fade.duration = 0.18
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "barFade")
        } else {
            layer?.removeAnimation(forKey: "barFade")
        }
        layer?.backgroundColor = m.fill.cgColor
        stripes.isHidden = !m.stripes
        // The card under the bar takes its colour and height (Arc's developer bar is 40 pt, 32 otherwise).
        (superview as? PaneCardView)?.developerBar = m.kind == .developer ? m.fill : nil
        hairline.isHidden = m.hairline == nil
        hairline.layer?.backgroundColor = m.hairline?.cgColor
        let bar = ToolbarComposition(kind: m.kind, inSplit: m.inSplit, sidebarVisible: m.sidebarVisible, focusedPane: m.focusedPane,
                                     hovered: m.hovered, canGoBack: m.canGoBack, canGoForward: m.canGoForward, isLoading: m.isLoading,
                                     pinnedExtensions: m.pinned.map(\.id))
        // The no-tab bar and an empty pane show navigation that does nothing (Arc greys it out).
        let wide = m.kind == .noTab || m.kind == .emptyPane
        // Arc's right-hand boxes: 32 pt, 4 pt apart (layout); 28 pt edge to edge on the developer bar.
        let rightBox: CGFloat = m.kind == .developer ? 28 : 32
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
            case .console:
                return glyph("console", "terminal", help: "Toggle Console (⌥⌘J)", width: 28) { $0.actions.performAction("jsConsole") }
            case .network:
                return glyph("network", "globe", help: "Toggle Network Panel", width: 28) { $0.actions.performAction("networkPanel") }
            case .inspect:
                return glyph("inspect", "scope", help: "Inspect Element (⌥⌘C)", width: 28) { $0.actions.performAction("inspectElement") }
            case .pinnedExtension(let id):
                let e = m.pinned.first { $0.id == id }
                let b = button("ext:" + id) { ToolbarGlyphButton() }
                // Arc: the 16 pt action icon with its badge, and no tooltip (Arc 1.171, #106). On a WebKit
                // page it dims and says why (docs/protected-media.md).
                b.configure(symbol: nil, image: ExtensionStore.shared.badged(e?.icon, e?.badge, tint: m.fgDim),
                            help: m.protectedMedia.map(ExtensionStore.offOnProtectedMedia) ?? "", enabled: m.protectedMedia == nil,
                            width: rightBox, iconSize: 16, tint: m.fgDim, hover: m.hover)
                let pane = paneTabID
                b.action = { [weak self] in
                    if let pane { self?.actions.paneRunExtension(pane, id) } else { self?.actions.runExtension(id) }
                }
                b.menuProvider = { ExtensionStore.shared.entries.first { $0.extensionID == id }.map(ExtensionsMenu.iconMenu) }
                return b
            case .extensions:
                return glyph("extensions", "slider.horizontal.2.square", help: "Extensions", width: rightBox, iconSize: 16) {
                    if let pane = $0.paneTabID { $0.actions.paneExtensionsMenu(pane) } else { $0.actions.showExtensionsMenu() }
                }
            case .addSplit:
                return glyph("split", "square.split.2x1", help: "Add Split View (⌃⇧=)", width: rightBox, iconSize: 16) { $0.actions.performAction("addSplitView") }
            case .splitOptions:
                return glyph("splitOptions", "rectangle.split.2x1", help: "Split View Options", width: rightBox) { $0.showSplitMenu(from: $0.buttons["splitOptions"]) }
            case .closePane:
                let id = paneTabID
                return glyph("close", "xmark", help: "Close this Split Pane (⌃⇧-)", width: rightBox, iconSize: 14, tint: m.closeTint) {
                    if let id { $0.actions.closePane(id) }
                }
            }
        }
        let l = bar.left.compactMap { view($0) as? ToolbarGlyphButton }
        let r = bar.right.map(view)
        devDivider.layer?.backgroundColor = m.dividerColor.cgColor
        devTrailingDivider.layer?.backgroundColor = m.dividerColor.cgColor
        let used = Set((l as [NSView] + r).map(ObjectIdentifier.init))
        for (k, b) in buttons where !used.contains(ObjectIdentifier(b)) {
            b.removeFromSuperview()
            buttons[k] = nil
        }
        devDivider.isHidden = !r.contains { $0 === devDivider }
        devTrailingDivider.isHidden = devDivider.isHidden || r.last === buttons["inspect"]
        left = l
        right = r

        if m.kind != .developer || m.tabID != old.tabID { urlButton.endEditing(commit: false) }
        switch m.kind {
        case .normal, .developer:
            urlButton.isHidden = false
            placeholderLabel.isHidden = true
            // Arc's developer URL has no hover fill (it edits in place on a click).
            let urlHover = m.kind == .developer ? NSColor.clear : NSColor.white.withAlphaComponent(0.08)
            urlButton.show(host: m.host, path: m.path, url: m.url, developer: m.kind == .developer,
                           fg: m.fg, fgDim: m.fgDim, hover: urlHover, copyHover: m.hover)
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
        // Right group, from the trailing edge, 5 pt in (Arc 1.171, captures and AX reads 8 Nov 2026):
        // pinned extensions … Split View as 32 pt boxes 4 pt apart (a 36 pt pitch), the last centred
        // 21 pt from the card edge like the left group's first icon. A split pane ends in options and
        // close, edge to edge, 4 pt after the sliders. The developer bar: Extensions, pins, Split View
        // as 28 pt boxes edge to edge, after copy | Console, Network, Inspect | spaced as in #88.
        var rx = w - (right.isEmpty ? 0 : 5)
        var trailing = right
        var devGroup: [NSView] = []
        if m.kind == .developer, let i = trailing.firstIndex(where: { $0 === devDivider }),
           let end = trailing.firstIndex(where: { $0 === buttons["inspect"] }) {
            devGroup = Array(trailing[(i - 1)...end])
            trailing.removeSubrange((i - 1)...end)
        }
        // A narrow bar keeps the address (ToolbarRoom, Arc's …HasRoom): the pins go from the front,
        // then ↻, then the sliders. The Extensions menu still has the pins; ⌘R still reloads.
        let widthOf = { (v: NSView) in (v as? ToolbarGlyphButton)?.width ?? 26 }
        let pins = trailing.filter { v in m.pinned.contains { buttons["ext:" + $0.id] === v } }
        let reload = left.first { $0 === buttons["reload"] }
        let settings = trailing.first { $0 === buttons["extensions"] }
        // The gap after a box (to its right) when the next one along is a box too.
        let isBox = { (v: NSView) in
            m.kind != .developer && (pins.contains { $0 === v } || v === settings || v === self.buttons["split"] || v === self.buttons["splitOptions"])
        }
        let gapAfter = { (items: [NSView], i: Int) -> CGFloat in
            i + 1 < items.count && isBox(items[i]) && isBox(items[i + 1]) ? PaneToolbarView.rightGap : 0
        }
        // The copy glyph goes in every pane at the width where a focused pane loses its sliders
        // (Arc, 3-pane split): judged on that pane's full set, so all panes of a width agree.
        var showsCopy = true
        if m.kind == .normal {
            let fullLeft: CGFloat = 2.5 + 3 * 37 + 6
            let fullRight: CGFloat = (m.inSplit ? 5 + 32 + 32 + 4 : 5 + 32 + 4) + 32 + 6
            let fullRoom = w - fullLeft - fullRight - 2 * (8 + 6)
            showsCopy = !ToolbarRoom.plan(pins: [], reload: 37, settings: 32 + PaneToolbarView.rightGap, needed: urlButton.idealWidth(withCopy: true),
                                          room: fullRoom).hidesSettings
        }
        urlButton.showsCopy = showsCopy
        var plan = ToolbarRoom.Plan()
        if m.kind == .normal {
            let start: CGFloat = 2.5
            let leftEnd = left.isEmpty ? 0 : start + left.reduce(0) { $0 + widthOf($1) }
            // Broken into sub-expressions: newer Swift type-checkers time out on the one-liner.
            let trailingWidth: CGFloat = trailing.indices.reduce(0) { $0 + widthOf(trailing[$1]) + gapAfter(trailing, $1) }
            let leftWidth: CGFloat = leftEnd + (left.isEmpty ? 0 : 6)
            let room = rx - trailingWidth - 6 - leftWidth - 2 * (8 + 6)
            // Each hidden box frees its width and the gap after it.
            let slot = { (v: NSView) -> CGFloat in
                let i = trailing.firstIndex { $0 === v }!
                return widthOf(v) + gapAfter(trailing, i)
            }
            plan = ToolbarRoom.plan(pins: pins.map(slot), reload: reload.map(widthOf), settings: settings.map(slot),
                                    needed: urlButton.idealWidth, room: room)
        }
        for (i, v) in pins.enumerated() { v.isHidden = i < plan.hiddenPins }
        reload?.isHidden = plan.hidesReload
        settings?.isHidden = plan.hidesSettings
        let dropped: [NSView] = Array(pins.prefix(plan.hiddenPins)) + (plan.hidesSettings ? settings.map { [$0] } ?? [] : [])
        trailing.removeAll { v in dropped.contains { $0 === v } }
        // Left group: icons edge to edge, the first (toggle or ←) centred 21 pt from the card edge (Arc 1.171).
        var x: CGFloat = m.kind == .emptyPane ? 1 : 2.5
        let shownLeft = left.filter { !(plan.hidesReload && $0 === reload) }
        for b in shownLeft {
            b.frame = NSRect(x: x, y: (h - bh) / 2, width: b.width, height: bh)
            x += b.width
        }
        let leftEnd = shownLeft.isEmpty ? 0 : x
        for (i, v) in trailing.enumerated().reversed() {
            let bw = (v as? ToolbarGlyphButton)?.width ?? 26
            rx -= gapAfter(trailing, i) + bw
            v.frame = NSRect(x: rx, y: (h - bh) / 2, width: bw, height: bh)
        }
        if !devGroup.isEmpty {
            // Arc: Inspect, 7 pt, a rule, 8 pt, Extensions; copy, 14 pt, a rule, 13 pt, then the
            // next group (Arc's Capture buttons, which Cra doesn't have).
            if !trailing.isEmpty {
                rx -= 8 + 1
                devTrailingDivider.frame = NSRect(x: rx, y: (h - 14) / 2, width: 1, height: 14)
                rx -= 7
            }
            for v in devGroup.reversed() {
                if v === devDivider {
                    rx -= 13 + 1
                    v.frame = NSRect(x: rx, y: (h - 14) / 2, width: 1, height: 14)
                    rx -= 14
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
            // Arc's address field (contentPanelTextField) runs from its 8 pt lead to 7 pt before
            // Copy Link (Arc 1.170, #88); it has no hover, so only clicks and long URLs see its width.
            let start = a + 8
            urlButton.frame = NSRect(x: start, y: (h - 28) / 2, width: max(0, rightStart - 7 - start), height: 28)
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

    private func copyURL() {
        if let id = paneTabID { actions.focusPane(id) }
        actions.performAction("copyURL")
    }

    /// Arc's menu on the toolbar address (Arc 1.172.1): Copy URL, Capture…, Capture Full Page,
    /// Manage Extensions…, then Show Full URL / Hide Full URL for the normal bar (the developer
    /// bar always shows it) and Hide Toolbar. Arc's Share ▸ is in the Site Control Center here, and
    /// Shared Quotes go through arc.net, so neither is listed.
    private func addressMenu() -> NSMenu? {
        guard model.kind == .normal || model.kind == .developer else { return nil }
        let menu = NSMenu()
        let focus = { [weak self] in if let id = self?.paneTabID { self?.actions.focusPane(id) } }
        menu.addItem(ToolbarMenuAction.item("Copy URL", shortcut: "copyURL", { [weak self] in self?.copyURL() }))
        menu.addItem(ToolbarMenuAction.item("Capture…", shortcut: "capturePage", { [weak self] in focus(); self?.actions.performAction("capturePage") }))
        menu.addItem(ToolbarMenuAction.item("Capture Full Page", shortcut: "captureFullPage", { [weak self] in focus(); self?.actions.performAction("captureFullPage") }))
        menu.addItem(.separator())
        menu.addItem(ToolbarMenuAction.item("Manage Extensions…", { [weak self] in self?.actions.performAction("manageExtensions") }))
        menu.addItem(.separator())
        if model.kind == .normal {
            let full = store.settings.toolbarShowsFullURL
            menu.addItem(ToolbarMenuAction.item(full ? "Hide Full URL" : "Show Full URL", { [weak self] in
                self?.store.settings.toolbarShowsFullURL.toggle()
            }))
        }
        menu.addItem(ToolbarMenuAction.item("Hide Toolbar", shortcut: "toggleToolbar", { [weak self] in self?.store.settings.showToolbar = false }))
        return menu
    }

    private func showSplitMenu(from view: NSView?) {
        guard let id = paneTabID, let view else { return }
        // A hovered pane's options act on that pane: Copy Link and Flip read the focused one.
        actions.focusPane(id)
        let menu = NSMenu()
        let items: [(String, String, () -> Void)?] = [
            ("Separate Tab from Split", "separateFromSplit", { [weak self] in self?.actions.separatePane(id) }),
            ("Flip Split View Orientation", "flipSplitOrientation", { [weak self] in self?.actions.performAction("flipSplitOrientation") }),
            nil,
            ("Copy Link", "copyURL", { [weak self] in self?.actions.performAction("copyURL") }),
            nil,
            ("Close this Split Pane", "closeSplitPane", { [weak self] in self?.actions.closePane(id) }),
        ]
        for entry in items {
            guard let (title, shortcut, run) = entry else { menu.addItem(.separator()); continue }
            menu.addItem(ToolbarMenuAction.item(title, shortcut: shortcut, run))
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }

    // Arc 1.170 opens the command bar from the address only (ToolbarURLButton) or the no-tab
    // placeholder; a click on the bar's empty space just focuses its pane (GitHub #88), and a
    // drag moves the window.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { takesClickFromChildWindow }
    override func mouseDown(with event: NSEvent) { press.begin(event) }
    override func mouseDragged(with event: NSEvent) { press.drag(event) }
    override func mouseUp(with event: NSEvent) {
        guard press.finish() else { return }
        if !placeholderLabel.isHidden, placeholderLabel.frame.contains(convert(event.locationInWindow, from: nil)) {
            editURL()
        } else if let id = paneTabID {
            actions.focusPane(id)
        }
    }
}

private final class ToolbarMenuAction: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func fire() { run() }

    /// `shortcut` names the KeyBindings command whose keys the row shows (#89).
    @MainActor static func item(_ title: String, shortcut: String? = nil, _ run: @escaping () -> Void) -> NSMenuItem {
        let a = ToolbarMenuAction(run)
        let item = NSMenuItem(title: title, action: #selector(fire), keyEquivalent: "")
        item.target = a
        item.representedObject = a
        if let shortcut { item.showShortcut(of: shortcut) }
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
    /// The fill while not hovered (the sidebar's pinned extension grid draws its cells like tiles).
    var restFill: NSColor = .clear { didSet { refreshFill() } }
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
            // An icon in its own colours can't be tinted grey: a disabled one fades instead.
            imageView.alphaValue = symbol == nil && !enabled ? 0.35 : 1
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
        imageView.frame = iconBox.map { NSRect(x: (bounds.width - $0.width) / 2, y: (iconRowHeight - $0.height) / 2, width: $0.width, height: $0.height) }
            ?? NSRect(x: 0, y: 0, width: width, height: h)
    }

    private func refreshFill() {
        layer?.backgroundColor = (hovering && enabled ? hover : restFill).cgColor
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

/// The URL in the middle of the bar: Arc's Copy Current URL glyph and the host (the dimmer path
/// after it with Show Full URL; the full URL in monospace after a lock in developer mode).
final class ToolbarURLButton: NSView, NSTextFieldDelegate {
    var action: () -> Void = {}
    /// The link glyph's own click (Copy Current URL) and the address's right-click menu.
    var onCopy: () -> Void = {}
    var menuProvider: (() -> NSMenu?)?
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
    private var contextClick = false
    private let content = NSView()
    private let icon = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 13)
    private let tip: ArcTooltipAnchorView
    private let copyTip: ArcTooltipAnchorView
    private var developer = false
    private var hover = NSColor.white.withAlphaComponent(0.08)
    private var copyHover = NSColor.white.withAlphaComponent(0.1)
    /// Arc's normal bar (1.171, #88): the glyph is a 24 pt button of its own and the host has its
    /// own pill, 24 pt tall, starting 20 pt in with the text 7 pt inside it. Each has its own hover;
    /// the pointer picks one where they meet. The developer bar is one piece.
    private var split = false
    /// Arc drops the copy glyph in a narrow pane, at the width where the sliders go (GitHub #178).
    var showsCopy = true {
        didSet {
            guard showsCopy != oldValue else { return }
            for v in [icon, copyFill, copyTip] as [NSView] { v.isHidden = !showsCopy || (v === copyTip && !split) }
            needsLayout = true
        }
    }
    private var lead: CGFloat { showsCopy ? Self.pillStart : 0 }
    private enum Region { case none, copy, address }
    private var region = Region.none { didSet { if region != oldValue { refreshFill() } } }
    private let copyFill = NSView()
    private let addressFill = NSView()
    private static let copyBox: CGFloat = 24, pillStart: CGFloat = 20, textStart: CGFloat = 27, pillPad: CGFloat = 7

    override init(frame: NSRect) {
        tip = ArcTooltipAnchorView(frame: .zero)
        copyTip = ArcTooltipAnchorView(frame: .zero)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        for f in [copyFill, addressFill] {
            f.wantsLayer = true
            f.layer?.cornerRadius = 7
            f.layer?.cornerCurve = .continuous
            addSubview(f)
        }
        icon.imageScaling = .scaleNone
        content.wantsLayer = true
        content.addSubview(icon)
        content.addSubview(label)
        addSubview(content)
        tip.followsCursor = true
        addSubview(tip)
        (copyTip.text, copyTip.keys) = ArcTooltipLabel.split("Copy URL (⇧⌘C)")
        addSubview(copyTip)
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
    var idealWidth: CGFloat { idealWidth(withCopy: showsCopy) }

    func idealWidth(withCopy: Bool) -> CGFloat {
        let text = label.attributedStringValue.size().width
        let start = Self.textStart - (withCopy ? 0 : Self.pillStart)
        return ceil(split ? start + text + Self.pillPad : 10 + iconWidth + 7 + text + 10)
    }

    /// The glyph's own width, as SwiftUI lays an Image out; developer mode boxes it at 14 pt.
    private var iconWidth: CGFloat { developer ? 14 : ceil(icon.image?.size.width ?? 12) }

    func show(host: String, path: String, url: String, developer: Bool, fg: NSColor, fgDim: NSColor, hover: NSColor,
              copyHover: NSColor) {
        self.developer = developer
        self.hover = hover
        self.copyHover = copyHover
        split = !developer
        copyTip.isHidden = !split || !showsCopy
        self.url = url
        ink = fg
        field?.textColor = fg
        refreshFill()
        tip.text = url
        if developer {
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
        if split {
            let box = Self.copyBox, y = (h - box) / 2
            copyFill.frame = NSRect(x: 0, y: y, width: box, height: box)
            addressFill.frame = NSRect(x: lead, y: y, width: max(0, bounds.width - lead), height: box)
            icon.frame = NSRect(x: 0, y: 0, width: box, height: h)
            let lh = label.intrinsicContentSize.height
            let textStart = lead + Self.textStart - Self.pillStart
            label.frame = NSRect(x: textStart - SidebarText.inset, y: (h - lh) / 2,
                                 width: max(0, bounds.width - textStart - Self.pillPad) + 2 * SidebarText.inset, height: lh)
            copyTip.frame = NSRect(x: 0, y: 0, width: lead, height: h)
            tip.frame = NSRect(x: lead, y: 0, width: max(0, bounds.width - lead), height: h)
            return
        }
        tip.frame = bounds
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
        layer?.backgroundColor = (!split && region != .none ? hover : .clear).cgColor
        copyFill.layer?.backgroundColor = (split && region == .copy ? copyHover : .clear).cgColor
        addressFill.layer?.backgroundColor = (split && region == .address ? hover : .clear).cgColor
    }

    private func region(at event: NSEvent) -> Region {
        let p = convert(event.locationInWindow, from: nil)
        guard bounds.contains(p) else { return .none }
        return split && p.x < lead ? .copy : .address
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { region = region(at: event) }
    override func mouseMoved(with event: NSEvent) { region = region(at: event) }
    override func mouseExited(with event: NSEvent) { region = .none }
    // Part of the bar: a click edits the URL (or copies it from the glyph), a drag moves the window
    // like the rest of it.
    override func mouseDown(with event: NSEvent) {
        contextClick = event.modifierFlags.contains(.control)
        if contextClick { if let menu = menu(for: event) { NSMenu.popUpContextMenu(menu, with: event, for: self) }; return }
        press.begin(event)
    }
    override func mouseDragged(with event: NSEvent) { if !contextClick { press.drag(event) } }
    override func mouseUp(with event: NSEvent) {
        guard !contextClick, press.finish() else { return }
        switch region(at: event) {
        case .copy: onCopy()
        case .address: action()
        case .none: break
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? { field == nil ? menuProvider?() : nil }
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
