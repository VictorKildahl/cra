import AppKit

/// The whole left column in AppKit, laid out like Arc: traffic lights + sidebar toggle with the
/// nav buttons at the right of the top row, the space pager (favorites, header, tab list), the
/// update banner and the dock. The Library takes the column over while it is open.
@MainActor
final class SidebarView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let favicons: FaviconCache
    private let tabs = FlippedView()
    private let topBar: SidebarTopBarView
    private let pager: SpacePagerView
    private let trayHost: DownloadsTrayView
    private let trayMask = CAGradientLayer()
    private let bannerHost = UpdateBannerView()
    private let dock: SpaceDockView
    private var libraryHost: LibraryView?
    private var palette: SpacePalette
    private var lastSpaceID: UUID?
    private var shownLibrary: LibraryPage?

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        palette = store.focusedSpace(window: ui.windowID).theme.palette
        topBar = SidebarTopBarView(store: store, ui: ui, actions: actions)
        pager = SpacePagerView(store: store, ui: ui, actions: actions, favicons: favicons)
        trayHost = DownloadsTrayView(ui: ui)
        dock = SpaceDockView(store: store, ui: ui, actions: actions)
        super.init(frame: .zero)
        wantsLayer = true
        pager.wantsLayer = true
        trayMask.startPoint = CGPoint(x: 0.5, y: 0)
        trayMask.endPoint = CGPoint(x: 0.5, y: 1)
        for v in [topBar, pager, trayHost, bannerHost, dock] as [NSView] { tabs.addSubview(v) }
        addSubview(tabs)
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func observe() {
        var bannerHeight: CGFloat = 0
        let (space, library, trayOpen, recentCount) = withObservationTracking {
            let space = store.focusedSpace(window: ui.windowID)
            bannerHeight = UpdateBannerView.isShown ? 60 : 0
            return (space, ui.libraryPage, ui.downloadsListOpen, DownloadHistory.shared.recent.count)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        let paletteChanged = lastSpaceID == nil || space.theme != store.space(lastSpaceID ?? space.id)?.theme || space.id != lastSpaceID
        if space.id != lastSpaceID {
            if lastSpaceID != nil { ui.clearPicks() }
            lastSpaceID = space.id
        }
        if paletteChanged || palette.isDark != space.theme.palette.isDark {
            palette = space.theme.palette
            let colors = SidebarColors(palette)
            trayHost.colors = colors
            bannerHost.colors = colors
            libraryHost?.palette = palette
        }
        self.bannerHeight = bannerHeight
        updateTrayMask(open: trayOpen, rows: recentCount)
        showLibrary(library)
        needsLayout = true
    }

    private var bannerHeight: CGFloat = 0

    /// DownloadsTrayMask: the tab list is hidden from 3 pt above the downloads list's first row
    /// and fades back in over the 170 pt above that.
    private func updateTrayMask(open: Bool, rows: Int) {
        let h = max(pager.bounds.height, 1)
        let clearTop = max(0, h - DownloadsTrayMetrics.listHeight(rows: rows) - 1)
        let fadeTop = max(0, clearTop - DownloadsTrayMetrics.fade)
        CATransaction.begin()
        CATransaction.setAnimationDuration(open ? 0.18 : 0.13)
        if !open { CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut)) }
        trayMask.frame = pager.bounds
        trayMask.locations = [0, NSNumber(value: Double(fadeTop / h)), NSNumber(value: Double(clearTop / h)), 1]
        let opaque = NSColor.black.cgColor, clear = NSColor.clear.cgColor
        trayMask.colors = open ? [opaque, opaque, clear, clear] : [opaque, opaque, opaque, opaque]
        CATransaction.commit()
        if pager.layer?.mask !== trayMask { pager.layer?.mask = trayMask }
        trayHost.isHidden = rows == 0
    }

    /// The Library takes over the column: in from a little to the left, out to the left past its
    /// rail while the tab list fades back in.
    private func showLibrary(_ page: LibraryPage?) {
        guard page != shownLibrary else { return }
        let opening = shownLibrary == nil && page != nil
        shownLibrary = page
        if let page {
            let host = libraryHost ?? {
                let h = LibraryView(page: page, palette: palette, store: store, actions: actions, favicons: favicons)
                addSubview(h)
                libraryHost = h
                return h
            }()
            host.page = page
            host.frame = bounds
            if opening {
                host.alphaValue = 0
                host.frame = bounds.offsetBy(dx: -24, dy: 0)
            }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.05
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                host.animator().alphaValue = 1
                host.animator().frame = bounds
                tabs.animator().alphaValue = 0
            }
        } else if let host = libraryHost {
            libraryHost = nil
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.1
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                host.animator().alphaValue = 0
                host.animator().frame = bounds.offsetBy(dx: -LibraryMetrics.rail, dy: 0)
                tabs.animator().alphaValue = 1
            } completionHandler: {
                host.removeFromSuperview()
            }
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let host = libraryHost {
            // `point` is in the superview's space; the host sits in this (flipped) view's.
            let p = convert(point, from: superview)
            return host.hitTest(p) ?? (bounds.contains(p) ? self : nil)
        }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()
        let b = bounds
        tabs.frame = b
        libraryHost?.frame = b
        let th = topBar.preferredHeight
        topBar.frame = NSRect(x: 0, y: 0, width: b.width, height: th)
        // Arc's list viewport ends 50 pt above the window bottom; the dock sits centred in that band.
        let dockH: CGFloat = 36
        dock.frame = NSRect(x: 10, y: b.height - 6 - dockH, width: b.width - 20, height: dockH)
        let bannerTop = b.height - 6 - dockH - 8 - bannerHeight
        bannerHost.frame = NSRect(x: 0, y: bannerTop, width: b.width, height: bannerHeight)
        pager.frame = NSRect(x: 0, y: th, width: b.width, height: max(0, bannerTop - th))
        let rows = DownloadHistory.shared.recent.count
        let trayH = DownloadsTrayMetrics.listHeight(rows: rows) + 4
        trayHost.frame = NSRect(x: 0, y: pager.frame.maxY - trayH, width: b.width, height: trayH)
        updateTrayMask(open: ui.downloadsListOpen, rows: rows)
    }
}

/// A container that lays its subviews out from the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - Top bar

/// Row 1: traffic lights, the sidebar toggle right after them, nav buttons right-aligned. When
/// the toolbar is hidden the URL pill moves into the sidebar on a second row.
///
/// Toolbar hidden, measured on Arc 1.170 (window capture and AX tree, 26 Oct): toggle and
/// ← → ↻ are 32 pt buttons centred 1 pt above the traffic lights, the nav buttons 2 pt apart
/// and 6 pt from the sidebar edge, no ⌄ menu. The URL pill spans the sidebar 8 pt in from each
/// side, 36 pt tall, 2 pt under the title area, radius 10, the bare host in 13 pt at 12 pt in.
/// Its accessories (pinned extensions, copy link, site controls) show while the header is hovered.
final class SidebarTopBarView: NSView {
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private var colors = SidebarColors()
    private var compact = false
    private var devNav = false
    private var buttons: [String: SidebarGlyphButton] = [:]
    private var rowButtons: [SidebarGlyphButton] = []
    private var chevron: NSView?
    private let pill = SidebarURLPill()
    private var hoverHeader = false { didSet { if hoverHeader != oldValue { pill.showAccessories = hoverHeader } } }
    private var syncQueued = false

    var preferredHeight: CGFloat { CraMetrics.titleAreaHeight + (compact ? 2 + 36 + 8 : 0) }

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions) {
        self.store = store
        self.ui = ui
        self.actions = actions
        super.init(frame: .zero)
        pill.actions = actions
        addSubview(pill)
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func sync() {
        syncQueued = false
        withObservationTracking { apply() } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.syncQueued else { return }
                self.syncQueued = true
                self.sync()
            }
        }
    }

    private func button(_ key: String, symbol: String, help: String, size: CGFloat, height: CGFloat, iconSize: CGFloat,
                        weight: NSFont.Weight = .regular, active: Bool?, enabled: Bool = true, animated: Bool = false,
                        action: @escaping () -> Void) -> SidebarGlyphButton {
        let b = buttons[key] ?? {
            let b = SidebarGlyphButton(symbol: symbol, size: size, height: height, iconSize: iconSize, weight: weight, help: help, colors: colors, action: action)
            buttons[key] = b
            addSubview(b)
            return b
        }()
        b.setSymbol(symbol, iconSize: iconSize, weight: weight, help: help, animated: animated)
        b.colors = colors
        b.active = active
        b.enabled = enabled
        b.action = action
        return b
    }

    private func apply() {
        let wasCompact = compact
        compact = !store.settings.showToolbar
        colors = SidebarColors(store.focusedSpace(window: ui.windowID).theme.palette)
        let tab = store.selectedTab(window: ui.windowID)
        devNav = !compact && (tab?.tab.map { store.settings.isDeveloperMode(url: $0.url) } ?? false)
        let active = ui.appActive
        let reloadSymbol = ui.isLoading ? "xmark" : "arrow.clockwise"
        var shown: [SidebarGlyphButton] = []
        if compact {
            // The toolbar carries the sidebar toggle; this one only stands in while the toolbar is hidden.
            shown.append(button("toggle", symbol: "sidebar.left", help: "Hide Sidebar (⌘S)", size: 32, height: 32, iconSize: 15.5, active: active) { [weak self] in self?.actions.toggleSidebar() })
            shown.append(button("back", symbol: "arrow.left", help: "Go Back (⌘[)", size: 32, height: 32, iconSize: 15, active: active, enabled: ui.canGoBack) { [weak self] in self?.actions.goBack() })
            shown.append(button("forward", symbol: "arrow.right", help: "Go Forward (⌘])", size: 32, height: 32, iconSize: 15, active: active, enabled: ui.canGoForward) { [weak self] in self?.actions.goForward() })
            shown.append(button("reload", symbol: reloadSymbol, help: "Refresh (⌘R)", size: 32, height: 32, iconSize: 15, active: active, animated: true) { [weak self] in self?.actions.reload() })
        } else if devNav {
            shown.append(button("dback", symbol: "arrow.left", help: "Go Back (⌘[)", size: 34, height: 28, iconSize: 15, active: nil, enabled: ui.canGoBack) { [weak self] in self?.actions.goBack() })
            shown.append(button("dforward", symbol: "arrow.right", help: "Go Forward (⌘])", size: 34, height: 28, iconSize: 15, active: nil, enabled: ui.canGoForward) { [weak self] in self?.actions.goForward() })
            shown.append(button("dreload", symbol: reloadSymbol, help: "Refresh (⌘R)", size: 24, height: 24, iconSize: 15, active: nil, animated: true) { [weak self] in self?.actions.reload() })
        }
        for (k, b) in buttons where !shown.contains(where: { $0 === b }) {
            b.removeFromSuperview()
            buttons[k] = nil
        }
        rowButtons = shown
        if devNav, chevron == nil {
            let c = DevMenuChevron(actions: actions)
            addSubview(c)
            chevron = c
        } else if !devNav, let c = chevron {
            c.removeFromSuperview()
            chevron = nil
        }
        (chevron as? DevMenuChevron)?.tint = colors.textTertiary
        pill.isHidden = !compact
        if compact {
            let url = tab?.tab?.url ?? ""
            let host = URL(string: url)?.host ?? ""
            let text = tab == nil ? "Search or Enter URL…" : (host.isEmpty ? SuggestionEngine.humanURL(url) : host.replacingOccurrences(of: "www.", with: ""))
            let ext = ExtensionStore.shared
            let entries = ext.entries(inProfile: tab.map { store.profileDirectoryName(item: $0.id) }
                                      ?? store.profileDirectoryName(space: store.focusedSpaceID(window: ui.windowID)))
            let pinned = ext.pinnedIDs.compactMap { id in entries.first { $0.extensionID == id }.map { (id, $0.name, ext.toolbarIcon(for: $0)) } }
            pill.show(text: text, url: url, hasTab: tab != nil, status: ui.toolbarStatus, colors: colors, active: active,
                      pinned: pinned, hasExtensions: !entries.isEmpty)
        }
        needsLayout = true
        if wasCompact != compact { superview?.superview?.needsLayout = true }
    }

    override func layout() {
        super.layout()
        let w = bounds.width
        if compact {
            // Row 1: 71 pt for the traffic lights, the toggle, then ← → ↻ 2 pt apart, 6 pt from the edge.
            let y = CraMetrics.titleRowCenter - 17
            if let t = rowButtons.first { t.frame = NSRect(x: 6 + 71 + 2, y: y, width: 32, height: 32) }
            var x = w - 6
            for b in rowButtons.dropFirst().reversed() {
                x -= 32
                b.frame = NSRect(x: x, y: y, width: 32, height: 32)
                x -= 2
            }
            pill.frame = NSRect(x: 8, y: CraMetrics.titleAreaHeight + 2, width: w - 16, height: 36)
        } else if devNav {
            let y = CraMetrics.titleRowCenter - 14
            var x = w - 6
            if let c = chevron {
                x -= 12
                c.frame = NSRect(x: x, y: y, width: 12, height: 28)
            }
            for b in rowButtons.reversed() {
                x -= b.size.width
                b.frame = NSRect(x: x, y: y + (28 - b.size.height) / 2, width: b.size.width, height: b.size.height)
            }
        }
    }

    // A double click on the empty strip does the title bar's double-click action; a drag moves
    // the window (from the floating sidebar too, without tearing its panel off).
    override var mouseDownCanMoveWindow: Bool { false }
    private var press = WindowDragGesture()
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2, convert(event.locationInWindow, from: nil).y < CraMetrics.titleAreaHeight {
            _ = press.finish()
            actions.titleBarDoubleClick()
            return
        }
        press.begin(event)
    }
    override func mouseDragged(with event: NSEvent) { press.drag(event) }
    override func mouseUp(with event: NSEvent) { _ = press.finish() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hoverHeader = true }
    override func mouseExited(with event: NSEvent) { hoverHeader = false }
}

/// The ⌄ after the developer-mode nav buttons: page actions in a menu.
private final class DevMenuChevron: NSView {
    private let actions: SidebarActions
    private let image = NSImageView()
    var tint: NSColor = .tertiaryLabelColor { didSet { image.contentTintColor = tint } }

    init(actions: SidebarActions) {
        self.actions = actions
        super.init(frame: .zero)
        image.image = SidebarSymbols.image("chevron.down", size: 8, weight: .bold)
        image.imageScaling = .scaleNone
        image.autoresizingMask = [.width, .height]
        addSubview(image)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }
    override func layout() {
        super.layout()
        image.frame = bounds
    }

    override func mouseDown(with event: NSEvent) {
        let m = NSMenu()
        m.autoenablesItems = false
        let a = actions
        MenuItems.add(m, "Refresh the Page") { a.performAction("reload") }
        MenuItems.add(m, "Force Refresh the Page") { a.performAction("hardReload") }
        m.addItem(.separator())
        MenuItems.add(m, "View Source") { a.performAction("viewSource") }
        MenuItems.add(m, "Developer Tools") { a.performAction("devTools") }
        m.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: self)
    }
}

/// The URL pill on the sidebar's second row while the toolbar is hidden.
final class SidebarURLPill: NSView {
    var actions: SidebarActions?
    var showAccessories = false { didSet { if showAccessories != oldValue { refreshAccessories(animated: true) } } }
    private let label = NSTextField.sidebarLabel(size: 13)
    private let statusIcon = NSImageView()
    private let tip: ArcTooltipAnchorView
    private var accessories: [NSView] = []
    private var hovering = false { didSet { if hovering != oldValue { refreshFill() } } }
    private var colors = SidebarColors()
    private var hasTab = false
    private var model: (pinned: [(String, String, NSImage?)], hasExtensions: Bool, active: Bool)?

    override init(frame: NSRect) {
        tip = ArcTooltipAnchorView(frame: .zero)
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        label.lineBreakMode = .byTruncatingMiddle
        statusIcon.imageScaling = .scaleNone
        addSubview(statusIcon)
        addSubview(label)
        tip.followsCursor = true
        tip.autoresizingMask = [.width, .height]
        addSubview(tip)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    func show(text: String, url: String, hasTab: Bool, status: ToolbarStatus?, colors: SidebarColors, active: Bool,
              pinned: [(String, String, NSImage?)], hasExtensions: Bool) {
        self.colors = colors
        self.hasTab = hasTab
        tip.text = url
        if let status {
            statusIcon.isHidden = false
            statusIcon.image = SidebarSymbols.image(status.symbol, size: 10, weight: .semibold)
            statusIcon.contentTintColor = colors.textSecondary
            label.stringValue = status.text
            label.textColor = colors.textSecondary
        } else {
            statusIcon.isHidden = true
            label.stringValue = text
            label.textColor = hasTab ? colors.textPrimary : colors.textTertiary
        }
        model = (pinned, hasExtensions, active)
        refreshAccessories(animated: false)
        refreshFill()
        needsLayout = true
    }

    private func refreshFill() {
        layer?.backgroundColor = (hovering ? colors.selectedFill : colors.pillFill).cgColor
    }

    /// Arc's URL-bar accessories: pinned extensions, Copy Link, then the site controls.
    private func refreshAccessories(animated: Bool) {
        accessories.forEach { $0.removeFromSuperview() }
        accessories = []
        guard showAccessories, hasTab, let m = model, let actions else { needsLayout = true; return }
        for (id, name, icon) in m.pinned {
            let b = ToolbarGlyphButton()
            b.configure(symbol: nil, image: icon, help: name, enabled: true, width: 28, iconSize: 16, tint: colors.textSecondary)
            b.action = { actions.runExtension(id) }
            b.menuProvider = { ExtensionStore.shared.entries.first { $0.extensionID == id }.map(ExtensionsMenu.iconMenu) }
            accessories.append(b)
        }
        let copy = SidebarGlyphButton(symbol: "link", size: 28, height: 28, iconSize: 14, weight: .regular, help: "Copy URL (⇧⌘C)", colors: colors) { actions.performAction("copyURL") }
        copy.active = m.active
        accessories.append(copy)
        if m.hasExtensions {
            let e = SidebarGlyphButton(symbol: "slider.horizontal.2.square", size: 28, height: 28, iconSize: 15, weight: .regular, help: "Extensions", colors: colors) { actions.showExtensionsMenu() }
            e.active = m.active
            accessories.append(e)
        }
        for v in accessories {
            addSubview(v)
            if animated {
                v.alphaValue = 0
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.15
                    v.animator().alphaValue = 1
                }
            }
        }
        needsLayout = true
    }

    /// The accessories' hover fill is the sidebar's, not the toolbar's.
    override func layout() {
        super.layout()
        let h = bounds.height
        var right = bounds.width - 5
        for v in accessories.reversed() {
            right -= 28
            v.frame = NSRect(x: right, y: (h - 28) / 2, width: 28, height: 28)
            right -= 1
        }
        var x: CGFloat = 12
        if !statusIcon.isHidden {
            statusIcon.frame = NSRect(x: x, y: 0, width: 12, height: h)
            x += 12 + 6
        }
        let lh = label.intrinsicContentSize.height
        label.frame = NSRect(x: x - SidebarText.inset, y: (h - lh) / 2, width: max(0, right - x) + 2 * SidebarText.inset, height: lh)
        tip.frame = NSRect(x: 0, y: 0, width: right, height: h)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        actions?.openCommandBar(hasTab ? .editURL : .newTab)
    }
}

// MARK: - Dock

/// Bottom row like Arc's: the Library at the left, tiny space icons in the middle (inactive ones
/// dimmed), "+" at the right. Arc 1.170 (SidebarDock, an NSCollectionView): 34×32 pt cells side
/// by side with no gap, so a press anywhere between two icons still lands on a space.
final class SpaceDockView: NSView {
    static let cell = CGSize(width: 34, height: 32)
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let library: LibraryButtonView
    private let plus: SidebarGlyphButton
    private var cells: [UUID: SpaceCellView] = [:]
    private var order: [UUID] = []
    private var focused: UUID?
    private var incognito = false
    private var colors = SidebarColors()
    private var hovered: UUID? { didSet { if hovered != oldValue { refreshCells() } } }
    private var reorder: (id: UUID, from: Int, to: Int, start: NSPoint, moved: Bool)?
    private var syncQueued = false

    init(store: SidebarStore, ui: SidebarUIState, actions: SidebarActions) {
        self.store = store
        self.ui = ui
        self.actions = actions
        library = LibraryButtonView(ui: ui, actions: actions)
        plus = SidebarGlyphButton(symbol: "plus", size: 28, iconSize: 13, help: "New Space", colors: SidebarColors()) { actions.editSpace(nil) }
        super.init(frame: .zero)
        addSubview(library)
        addSubview(plus)
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func sync() {
        syncQueued = false
        var spaces: [Space] = []
        withObservationTracking {
            colors = SidebarColors(store.focusedSpace(window: ui.windowID).theme.palette)
            incognito = store.window(ui.windowID).isIncognito
            let f = store.focusedSpaceID(window: ui.windowID)
            focused = f
            // Arc's single-space mode drops the lone space icon along with the header.
            spaces = incognito || store.hidesSpaceHeader(f) ? [] : store.orderedSpaces
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.syncQueued else { return }
                self.syncQueued = true
                self.sync()
            }
        }
        library.colors = colors
        plus.colors = colors
        plus.isHidden = incognito
        let ids = spaces.map(\.id)
        for (id, c) in cells where !ids.contains(id) {
            c.removeFromSuperview()
            cells[id] = nil
        }
        for s in spaces {
            let c = cells[s.id] ?? {
                let c = SpaceCellView(spaceID: s.id, store: store, ui: ui)
                cells[s.id] = c
                addSubview(c)
                return c
            }()
            c.show(emoji: s.emoji, title: s.title)
        }
        order = ids
        refreshCells()
        needsLayout = true
    }

    private func refreshCells() {
        for (id, c) in cells {
            c.setState(selected: id == focused, hovered: hovered == id && reorder == nil, pressed: reorder?.id == id, colors: colors)
        }
    }

    private var stripX: CGFloat { (bounds.width - CGFloat(order.count) * Self.cell.width) / 2 }

    override func layout() {
        super.layout()
        let h = bounds.height
        library.frame = NSRect(x: 0, y: (h - 28) / 2, width: 28, height: 28)
        plus.frame = NSRect(x: bounds.width - 28, y: (h - 28) / 2, width: 28, height: 28)
        placeCells(animated: false)
    }

    /// The dragged space follows the pointer; the ones it passes slide a cell the other way, like
    /// the gap Arc's collection view opens at the proposed drop index.
    private func placeCells(animated: Bool, dragX: CGFloat = 0) {
        let w = Self.cell.width
        let y = (bounds.height - Self.cell.height) / 2
        for (i, id) in order.enumerated() {
            guard let c = cells[id] else { continue }
            var x = stripX + CGFloat(i) * w
            if let r = reorder {
                if r.id == id { x += dragX } else if r.from < i && i <= r.to { x -= w } else if r.to <= i && i < r.from { x += w }
            }
            let f = NSRect(x: x, y: y, width: w, height: Self.cell.height)
            if animated && reorder?.id != id { c.animator().frame = f } else { c.frame = f }
        }
        if let r = reorder, let c = cells[r.id] { c.removeFromSuperview(); addSubview(c) }
    }

    private func index(at p: NSPoint) -> Int? {
        let i = Int(floor((p.x - stripX) / Self.cell.width))
        guard p.y >= 0, p.y <= bounds.height, i >= 0, i < order.count, p.x >= stripX else { return nil }
        return i
    }

    // Arc's dock items take the mouse themselves (SidebarDockItemView overrides mouseDown:/mouseUp:):
    // a press never moves the window, and every click counts.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if index(at: p) != nil { return self }
        return super.hitTest(point)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    private func point(_ e: NSEvent) -> NSPoint { convert(e.locationInWindow, from: nil) }

    override func mouseMoved(with event: NSEvent) {
        guard reorder == nil else { return }
        let i = index(at: point(event))
        hovered = i.map { order[$0] }
        for (j, id) in order.enumerated() { if let c = cells[id] { j == i ? ArcTooltipController.shared.mouseMoved(in: c) : ArcTooltipController.shared.mouseExited(c) } }
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        if reorder == nil { hovered = nil }
        for c in cells.values { ArcTooltipController.shared.mouseExited(c) }
    }

    override func mouseDown(with event: NSEvent) {
        let p = point(event)
        guard let i = index(at: p) else { return }
        reorder = (order[i], i, i, p, false)
        refreshCells()
    }

    override func mouseDragged(with event: NSEvent) {
        guard var r = reorder else { return }
        let p = point(event)
        let dx = p.x - r.start.x
        if !r.moved && abs(dx) < 3 && abs(p.y - r.start.y) < 3 { return }
        r.moved = true
        let w = Self.cell.width
        let clamped = min(max(dx, -CGFloat(r.from) * w), CGFloat(order.count - 1 - r.from) * w)
        let to = min(max(r.from + Int((clamped / w).rounded()), 0), order.count - 1)
        let changed = to != r.to
        r.to = to
        reorder = r
        if changed {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                placeCells(animated: true, dragX: clamped)
            }
        } else {
            placeCells(animated: false, dragX: clamped)
        }
    }

    /// A release inside the pressed cell that didn't move the space switches to it, so a shaky
    /// click still counts; a moved space slides into its cell and the order is saved.
    override func mouseUp(with event: NSEvent) {
        guard let r = reorder else { return }
        let p = point(event)
        guard r.to != r.from else {
            reorder = nil
            if index(at: p) == r.from { store.focusSpace(r.id, window: ui.windowID) }
            hovered = index(at: p).map { order[$0] }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                placeCells(animated: true)
            }
            refreshCells()
            return
        }
        // `moveSpace` indexes the full space order; land next to the space now in that cell.
        let target = store.spaceOrder.firstIndex(of: order[r.to]) ?? r.to
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            placeCells(animated: true, dragX: CGFloat(r.to - r.from) * Self.cell.width)
            cells[r.id]?.animator().frame.origin.x = stripX + CGFloat(r.to) * Self.cell.width
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.reorder = nil
                self.store.moveSpace(r.id, to: target)
                self.refreshCells()
            }
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let i = index(at: point(event)), let space = store.space(order[i]) else { return nil }
        let store = self.store, ui = self.ui, actions = self.actions
        let m = NSMenu()
        m.autoenablesItems = false
        MenuItems.add(m, "Edit Space…") { actions.editSpace(space) }
        m.addItem(.separator())
        MenuItems.add(m, "Move Left") { if let i = store.spaceOrder.firstIndex(of: space.id) { store.moveSpace(space.id, to: max(0, i - 1)) } }
        MenuItems.add(m, "Move Right") { if let i = store.spaceOrder.firstIndex(of: space.id) { store.moveSpace(space.id, to: i + 1) } }
        m.addItem(.separator())
        MenuItems.add(m, "Delete Space…") {
            store.focusSpace(space.id, window: ui.windowID)
            actions.performAction("deleteSpace")
        }
        return m
    }
}

/// One space in the dock: its emoji, dimmed and desaturated unless selected, hovered or pressed.
/// A tab dragged onto it moves there; held over it, Arc switches to that space so the tab can be
/// carried into its list.
final class SpaceCellView: NSView, ArcTooltipTarget {
    private let spaceID: UUID
    private let store: SidebarStore
    private let ui: SidebarUIState
    private let emoji = NSTextField.sidebarLabel(size: 13)
    private let emojiHolder = NSView()
    private var title = ""
    private var selected = false
    private var colors = SidebarColors()
    private var state: (Bool, Bool, Bool)?
    private var targeted = false { didSet { if targeted != oldValue { refreshFill() } } }
    private var lit = false

    init(spaceID: UUID, store: SidebarStore, ui: SidebarUIState) {
        self.spaceID = spaceID
        self.store = store
        self.ui = ui
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        emojiHolder.wantsLayer = true
        emojiHolder.layerUsesCoreImageFilters = true
        emoji.alignment = .center
        emojiHolder.addSubview(emoji)
        addSubview(emojiHolder)
        registerForDraggedTypes([.craSidebarItem])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func show(emoji text: String, title: String) {
        emoji.stringValue = text
        self.title = title
        setAccessibilityLabel(title)
        needsLayout = true
    }

    func setState(selected: Bool, hovered: Bool, pressed: Bool, colors: SidebarColors) {
        self.selected = selected
        self.colors = colors
        lit = selected || hovered || pressed
        emojiHolder.alphaValue = lit ? 1 : 0.45
        emojiHolder.layer?.filters = lit ? nil : [CIFilter(name: "CIColorControls", parameters: ["inputSaturation": 0.2])!]
        refreshFill(hovered || pressed)
    }

    /// Arc's hovered/pressed cell on a dark space: white at ~7.8%, 6 pt corners.
    private func refreshFill(_ on: Bool? = nil) {
        let fill = colors.isDark ? NSColor.white.withAlphaComponent(0.078) : NSColor.black.withAlphaComponent(0.05)
        let show = targeted || (on ?? (lit && !selected))
        layer?.backgroundColor = (show ? fill : .clear).cgColor
    }

    override func layout() {
        super.layout()
        emojiHolder.frame = bounds
        let h = emoji.intrinsicContentSize.height
        emoji.frame = NSRect(x: 0, y: (bounds.height - h) / 2, width: bounds.width, height: h)
    }

    override func accessibilityPerformPress() -> Bool {
        store.focusSpace(spaceID, window: ui.windowID)
        return true
    }

    private func draggedID(_ info: NSDraggingInfo) -> UUID? {
        guard let data = info.draggingPasteboard.data(forType: .craSidebarItem),
              let d = try? JSONDecoder().decode(SidebarDragItem.self, from: data) else { return nil }
        return d.id
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard draggedID(sender) != nil else { return [] }
        targeted = true
        if !selected {
            let id = spaceID
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self, self.targeted else { return }
                self.store.focusSpace(id, window: self.ui.windowID)
            }
        }
        return sender.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggedID(sender) == nil ? [] : (sender.draggingSourceOperationMask.contains(.move) ? .move : .copy)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { targeted = false }
    override func draggingEnded(_ sender: NSDraggingInfo) { targeted = false }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        targeted = false
        guard let id = draggedID(sender) else { return false }
        store.moveTab(id, toSpace: spaceID)
        return true
    }

    var text: String { title }
    var keys: [String] { [] }
    var followsCursor: Bool { false }
    var subtitle: String? { nil }
    var optionText: String? { nil }
    var onShow: (() -> Void)? { nil }
    var screenFrame: NSRect { window?.convertToScreen(convert(bounds, to: nil)) ?? .zero }
    var hostWindow: NSWindow? { window }
}

/// Arc's Library button (a box with a confetti puff, drawn by LibraryGlyph) and, over it, the
/// latest download's "bin" (DownloadsUI.DownloadToLibrary): the file's thumbnail, 32 pt with
/// 8 pt corners, up and to the right of the glyph. It drops in from 6 pt above, overshoots 12 pt
/// below and settles (Arc 1.170 at 60 fps), and is faint while the window is in the background.
final class LibraryButtonView: NSView {
    private let ui: SidebarUIState
    private let actions: SidebarActions
    private let glyph = NSImageView()
    private let tip: ArcTooltipAnchorView
    private let bin = NSView()
    private let binImage = CALayer()
    private let binTip: ArcTooltipAnchorView
    private var shownDownload: UInt32?
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }
    var colors = SidebarColors() { didSet { if colors != oldValue { glyph.image = LibraryGlyph.image(dark: colors.isDark); refresh() } } }
    static let binOffset = CGSize(width: 9, height: -12)

    init(ui: SidebarUIState, actions: SidebarActions) {
        self.ui = ui
        self.actions = actions
        tip = ArcTooltipAnchorView(frame: .zero)
        binTip = ArcTooltipAnchorView(frame: .zero)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 7
        layer?.cornerCurve = .continuous
        glyph.imageScaling = .scaleNone
        glyph.image = LibraryGlyph.image(dark: false)
        addSubview(glyph)
        (tip.text, tip.keys) = ArcTooltipLabel.split("Library (⇧⌘L)")
        addSubview(tip)
        bin.wantsLayer = true
        binImage.cornerRadius = 8
        binImage.cornerCurve = .continuous
        binImage.masksToBounds = true
        binImage.contentsGravity = .resizeAspectFill
        bin.layer?.addSublayer(binImage)
        bin.addSubview(binTip)
        bin.isHidden = true
        addSubview(bin)
        ui.libraryAnchor = self
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    private func observe() {
        let (download, active) = withObservationTracking { (ui.recentDownload, ui.appActive) } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        guard let download else { bin.isHidden = true; shownDownload = nil; return }
        bin.isHidden = false
        binImage.contents = download.image
        bin.alphaValue = active ? 1 : 0.4
        binTip.text = (download.path as NSString).lastPathComponent
        if shownDownload != download.id {
            shownDownload = download.id
            drop()
        }
    }

    private func drop() {
        let y = CAKeyframeAnimation(keyPath: "transform.translation.y")
        // Flipped view: positive y is down on screen.
        y.values = [-6, 12, 12, -2, 0].map { NSNumber(value: Double($0) * (bin.layer?.isGeometryFlipped == true ? 1 : -1)) }
        y.keyTimes = [0, 0.15, 0.2, 0.33, 0.4].map { NSNumber(value: $0 / 0.4) }
        y.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .linear),
                             CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        y.duration = 0.4
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.05
        bin.layer?.add(y, forKey: "drop")
        bin.layer?.add(fade, forKey: "fade")
    }

    private func refresh() {
        layer?.backgroundColor = (hovering ? colors.hoverFill : .clear).cgColor
    }

    override func layout() {
        super.layout()
        glyph.frame = bounds
        tip.frame = bounds
        let c = NSPoint(x: bounds.midX + Self.binOffset.width, y: bounds.midY + Self.binOffset.height)
        bin.frame = NSRect(x: c.x - 16, y: c.y - 16, width: 32, height: 32)
        binImage.frame = bin.bounds
        binTip.frame = bin.bounds
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        if !bin.isHidden, bin.frame.contains(p) { return self }
        return bounds.contains(p) ? self : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true; ui.libraryHovered = true; ui.downloadsHoverChanged() }
    override func mouseExited(with event: NSEvent) { hovering = false; ui.libraryHovered = false; ui.downloadsHoverChanged() }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if !bin.isHidden, bin.frame.contains(p), let path = ui.recentDownload?.path {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        } else if bounds.contains(p) {
            actions.toggleLibrary()
        }
    }
}
