import AppKit

/// Arc's folder preview (Arc 1.171: Previews.FolderPreviewState / FolderPreviewItem /
/// FolderPreviewAction, Arc.FolderPreviewView, setting `folderPreviewEnabled`). Resting the
/// pointer on a closed folder lists every tab in it, nested folders included, most recently used
/// first, each with how long ago it was used, under a "Search <folder>…" field that already has
/// the keys. ↑↓ and ↩ pick a tab, Escape, leaving or a click elsewhere closes it; a row's menu has
/// Copy Link, Open in Split View, Duplicate and Archive (FolderPreviewAction.ContextMenuAction).
/// Timing and geometry: docs/arc-reverse-engineering.md, "Folder previews".
@MainActor
final class FolderPreviewController {
    static let shared = FolderPreviewController()

    private var panel: FolderPreviewPanel?
    private weak var list: SpaceListView?
    private weak var anchor: FolderRowView?
    private(set) var folderID: UUID?
    private var showWork: DispatchWorkItem?
    private var closeWork: DispatchWorkItem?
    private weak var returnKeyWindow: NSWindow?
    private var clickMonitor: Any?
    private var resignObserver: Any?
    /// Typing or arrowing keeps the preview open after the pointer leaves; then only Escape, a
    /// pick or a click elsewhere closes it.
    var extended = false

    var isOpen: Bool { panel?.isVisible == true && folderID != nil }

    /// The list's hovered row changed (nil: the pointer left the rows).
    func hover(_ row: SidebarRowView?, in list: SpaceListView) {
        let folder = (row as? FolderRowView).flatMap { r -> (FolderRowView, UUID)? in
            guard let m = r.model, !m.expanded, !m.editing, m.tabCount > 0 else { return nil }
            return (r, m.id)
        }
        showWork?.cancel()
        showWork = nil
        if let (row, id) = folder, id == folderID, isOpen {
            anchor = row
            closeWork?.cancel()
            return
        }
        if isOpen, !panelHovered { scheduleClose() }
        guard let (row, id) = folder, list.store.settings.folderPreviews, list.ui.draggingID == nil,
              NSEvent.pressedMouseButtons == 0 else { return }
        let work = DispatchWorkItem { [weak self, weak row, weak list] in
            MainActor.assumeIsolated {
                guard let self, let row, let list, row.isHovered, row.model?.id == id else { return }
                self.open(id, row: row, list: list)
            }
        }
        showWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + FolderPreviewMetrics.openDelay, execute: work)
    }

    private var panelHovered: Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    func pointerEnteredPanel() { closeWork?.cancel() }

    func pointerLeftPanel() {
        if anchor?.isHovered == true { return }
        scheduleClose()
    }

    private func scheduleClose() {
        guard !extended else { return }
        closeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.panelHovered, self.anchor?.isHovered != true, !self.extended else { return }
                self.close()
            }
        }
        closeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + FolderPreviewMetrics.closeGrace, execute: work)
    }

    private func open(_ id: UUID, row: FolderRowView, list: SpaceListView) {
        guard let host = row.window, let folder = list.store.item(id) else { return }
        let items = Self.items(in: id, store: list.store, favicons: list.favicons)
        guard !items.isEmpty else { return }
        let wasOpen = isOpen
        closeWork?.cancel()
        self.list = list
        anchor = row
        folderID = id
        extended = false
        let panel = self.panel ?? FolderPreviewPanel()
        self.panel = panel
        panel.preview.show(title: folder.title ?? "Folder", items: items)
        // Right of the sidebar, centred on the folder, kept 18 pt inside the window.
        let size = NSSize(width: FolderPreviewMetrics.width, height: FolderPreviewMetrics.height(rows: items.count))
        let rowRect = host.convertToScreen(row.convert(row.bounds, to: nil))
        let sidebarRect = host.convertToScreen(list.convert(list.bounds, to: nil))
        let inset = FolderPreviewMetrics.windowInset
        var origin = NSPoint(x: sidebarRect.maxX + FolderPreviewMetrics.gapFromSidebar, y: rowRect.midY - size.height / 2)
        let bounds = host.parent?.frame ?? host.frame
        origin.y = max(min(origin.y, bounds.maxY - inset - size.height), bounds.minY + inset)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if panel.parent !== host {
            panel.parent?.removeChildWindow(panel)
            host.addChildWindow(panel, ordered: .above)
        }
        if !wasOpen { returnKeyWindow = NSApp.keyWindow === panel ? returnKeyWindow : NSApp.keyWindow }
        panel.present()
        // The field takes the keys at once, as in Arc (its caret blinks as the preview opens).
        panel.makeKey()
        panel.preview.focusSearch()
        installMonitors()
    }

    func debugOpen(_ id: UUID, row: FolderRowView, list: SpaceListView) {
        open(id, row: row, list: list)
        extended = true
    }

    func close(restoreFocus: Bool = true) {
        showWork?.cancel()
        closeWork?.cancel()
        guard let panel, isOpen else { folderID = nil; return }
        let wasKey = panel.isKeyWindow
        folderID = nil
        extended = false
        removeMonitors()
        panel.dismiss()
        if restoreFocus, wasKey, let w = returnKeyWindow, w.isVisible { w.makeKey() }
        returnKeyWindow = nil
    }

    private func installMonitors() {
        if clickMonitor == nil {
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] e in
                MainActor.assumeIsolated {
                    guard let self, let panel = self.panel, e.window !== panel else { return }
                    // A click on the folder itself opens it; the preview just goes.
                    self.close(restoreFocus: false)
                }
                return e
            }
        }
        if resignObserver == nil {
            resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close(restoreFocus: false) }
            }
        }
    }

    private func removeMonitors() {
        if let m = clickMonitor { NSEvent.removeMonitor(m) }
        clickMonitor = nil
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        resignObserver = nil
    }

    /// Every tab under the folder (nested folders and splits included), most recently used first
    /// (FolderPreviewState.allPossibleChildren, sorted by lastVisitDate).
    static func items(in folderID: UUID, store: SidebarStore, favicons: FaviconCache) -> [FolderPreviewItem] {
        store.tabs(under: folderID).map { t in
            let key = t.tab?.iconKey
            let icon = favicons.image(forKey: key)
            return FolderPreviewItem(id: t.id, title: t.displayTitle, url: t.tab?.url ?? "", icon: icon,
                                     glyphDark: icon == nil ? nil : favicons.glyphIsDark(forKey: key),
                                     lastVisit: t.tab?.timeLastActiveAt ?? t.createdAt, badged: t.isUnread)
        }
        .sorted { $0.lastVisit > $1.lastVisit }
    }

    // MARK: Actions

    func pick(_ id: UUID) {
        guard let list else { return }
        close()
        list.ui.keyboardFocusID = nil
        list.store.selectTab(id, window: list.ui.windowID)
    }

    func openInSplitView(_ id: UUID) {
        guard let list else { return }
        let store = list.store
        close()
        guard let current = store.selectedTabID(window: list.ui.windowID), current != id else {
            store.selectTab(id, window: list.ui.windowID)
            return
        }
        let split: SidebarItem?
        if let s = store.splitContaining(current) {
            store.addToSplit(s.id, tabID: id, at: nil)
            split = store.item(s.id)
        } else {
            split = store.createSplit(with: [current, id], at: current)
        }
        let pane = split.flatMap { store.paneID(for: id, in: $0) } ?? id
        store.selectTab(pane, window: list.ui.windowID)
    }

    func duplicate(_ id: UUID) {
        guard let list else { return }
        close()
        if let copy = list.store.duplicateTab(id) { list.store.selectTab(copy.id, window: list.ui.windowID) }
    }

    func archive(_ id: UUID) {
        guard let list else { return }
        list.store.archiveTab(id, reason: .manual)
        guard let folderID, list.store.item(folderID) != nil else { return close() }
        let items = Self.items(in: folderID, store: list.store, favicons: list.favicons)
        if items.isEmpty { close() } else { panel?.preview.replaceItems(items) }
    }
}

struct FolderPreviewItem: Equatable {
    var id: UUID
    var title: String
    var url: String
    var icon: NSImage?
    var glyphDark: Bool?
    var lastVisit: Date
    /// Unread (FolderPreviewItem.isBadged).
    var badged: Bool
}

/// Measured on Arc 1.171 (2x window captures and 120 fps recordings, 31 Oct 2026).
enum FolderPreviewMetrics {
    static let width: CGFloat = 240
    static let maxHeight: CGFloat = 320
    static let corner: CGFloat = 10
    static let searchHeight: CGFloat = 48
    /// From the hairline under the search field to the first row.
    static let listInset: CGFloat = 4
    static let rowPitch: CGFloat = 45
    static let rowFill: CGFloat = 44
    static let rowCorner: CGFloat = 4
    static let sideInset: CGFloat = 4
    /// Favicon and magnifier centre, and where the text starts, from the panel's left edge.
    static let iconCenter: CGFloat = 20
    static let textX: CGFloat = 36
    static let gapFromSidebar: CGFloat = 4
    static let windowInset: CGFloat = 18
    /// The row turns hovered, 0.45 s later the preview fades in (90 ms, scaling up from 0.85 at
    /// the middle of its left edge); it fades out over 80 ms as soon as the pointer is elsewhere.
    static let openDelay: TimeInterval = 0.45
    static let fadeIn: TimeInterval = 0.09
    static let fadeOut: TimeInterval = 0.08
    static let startScale: CGFloat = 0.85
    /// Crossing from the folder to the preview leaves both for a moment.
    static let closeGrace: TimeInterval = 0.06

    /// One row is 98 pt; six and more stop at 320 and scroll. Filtering keeps the size.
    static func height(rows n: Int) -> CGFloat {
        min(searchHeight + 1 + listInset + CGFloat(max(n, 1)) * rowPitch, maxHeight)
    }

    /// "15 hours ago", "1 week ago", as Arc words lastVisitDate.
    static func age(of date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 60 { return "Just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        f.dateTimeStyle = .numeric
        return f.localizedString(for: date, relativeTo: now)
    }

    // Arc draws it dark whatever the space's theme: a blur that lets ~12 % of the backdrop
    // through (23 over a dark page, 45/44/36 over a light yellow one), white text at 85 % / 58 %.
    static let title = NSColor(white: 1, alpha: 0.83)
    static let secondary = NSColor(white: 1, alpha: 0.55)
    static let rowFillColor = NSColor(white: 1, alpha: 0.078)
    static let hairline = NSColor(white: 1, alpha: 0.13)
}

/// A borderless panel that can take the search field's keys without activating anything else.
final class FolderPreviewPanel: NSPanel {
    let preview = FolderPreviewView()
    private let container = NSView()

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: FolderPreviewMetrics.width, height: 200),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = false
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        container.wantsLayer = true
        preview.autoresizingMask = [.width, .height]
        container.addSubview(preview)
        contentView = container
    }

    override func cancelOperation(_ sender: Any?) { FolderPreviewController.shared.close() }

    func present() {
        preview.frame = container.bounds
        let w = frame.width, s = FolderPreviewMetrics.startScale
        // Scale about the middle of the left edge (sublayerTransform works from the layer's centre).
        let start = CATransform3DConcat(CATransform3DMakeScale(s, s, 1), CATransform3DMakeTranslation(-w / 2 * (1 - s), 0, 0))
        alphaValue = 0
        orderFront(nil)
        invalidateShadow()
        if let layer = container.layer {
            let a = CABasicAnimation(keyPath: "sublayerTransform")
            a.fromValue = start
            a.toValue = CATransform3DIdentity
            a.duration = FolderPreviewMetrics.fadeIn
            a.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(a, forKey: "present")
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = FolderPreviewMetrics.fadeIn
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = FolderPreviewMetrics.fadeOut
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Opened again while it faded: leave it up.
                guard let self, FolderPreviewController.shared.folderID == nil else { return }
                self.parent?.removeChildWindow(self)
                self.orderOut(nil)
            }
        })
    }
}

/// The preview's content: the search field, a hairline, then the rows (scrolling past six).
@MainActor
final class FolderPreviewView: NSView, NSTextFieldDelegate {
    private let blur = NSVisualEffectView()
    private let shade = NSView()
    private let outline = CAShapeLayer()
    private let highlight = CAShapeLayer()
    private let searchIcon = NSImageView()
    private let field = NSTextField()
    private let line = NSView()
    private let scroll = NSScrollView()
    private let rowsView = FlippedRowsView()
    private let empty = NSTextField(wrappingLabelWithString: "")
    private var rows: [FolderPreviewRowView] = []
    private var items: [FolderPreviewItem] = []
    private var shown: [FolderPreviewItem] = []
    private var selected = 0

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: FolderPreviewMetrics.width, height: 200))
        appearance = NSAppearance(named: .darkAqua)
        wantsLayer = true
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.maskImage = Self.mask(radius: FolderPreviewMetrics.corner)
        addSubview(blur)
        // Over hudWindow (27 + 0.52 × backdrop) this leaves ≈ 19 + 0.12 × backdrop, as Arc.
        shade.wantsLayer = true
        shade.layer?.backgroundColor = NSColor(white: 17 / 255, alpha: 0.77).cgColor
        shade.layer?.cornerRadius = FolderPreviewMetrics.corner
        shade.layer?.cornerCurve = .circular
        addSubview(shade)
        searchIcon.image = SidebarSymbols.image("magnifyingglass", size: 12, weight: .semibold)
        searchIcon.contentTintColor = FolderPreviewMetrics.secondary
        addSubview(searchIcon)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = FolderPreviewMetrics.title
        field.delegate = self
        field.cell?.isScrollable = true
        field.cell?.usesSingleLineMode = true
        addSubview(field)
        line.wantsLayer = true
        line.layer?.backgroundColor = FolderPreviewMetrics.hairline.cgColor
        addSubview(line)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = rowsView
        addSubview(scroll)
        // Arc: "No tabs matching that search 🤔", wrapping the emoji onto a second line.
        empty.stringValue = "No tabs matching that search 🤔"
        empty.font = .systemFont(ofSize: 13)
        empty.textColor = FolderPreviewMetrics.secondary
        empty.alignment = .center
        empty.isHidden = true
        addSubview(empty)
        // Two half-point rims: a grey outline, a faint light line inside it.
        for (l, c) in [(outline, NSColor(white: 0.23, alpha: 1)), (highlight, NSColor(white: 1, alpha: 0.2))] {
            l.fillColor = nil
            l.strokeColor = c.cgColor
            l.lineWidth = 0.5
            l.zPosition = 20
            layer?.addSublayer(l)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private static func mask(radius r: CGFloat) -> NSImage {
        let size = NSSize(width: r * 2 + 1, height: r * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }

    func show(title: String, items: [FolderPreviewItem]) {
        field.placeholderAttributedString = NSAttributedString(string: "Search \(title)…", attributes: [
            .foregroundColor: FolderPreviewMetrics.secondary, .font: NSFont.systemFont(ofSize: 13),
        ])
        field.stringValue = ""
        self.items = items
        filter()
        scroll.contentView.scroll(to: .zero)
    }

    func replaceItems(_ items: [FolderPreviewItem]) {
        self.items = items
        filter(keepSelection: true)
    }

    func focusSearch() { window?.makeFirstResponder(field) }

    // MARK: Filtering

    private func filter(keepSelection: Bool = false) {
        let words = field.stringValue.lowercased().split(separator: " ").map(String.init)
        let previous = shown.indices.contains(selected) ? shown[selected].id : nil
        shown = words.isEmpty ? items : items.filter { item in
            let hay = (item.title + " " + item.url).lowercased()
            return words.allSatisfy(hay.contains)
        }
        selected = keepSelection ? (shown.firstIndex { $0.id == previous } ?? min(selected, max(0, shown.count - 1))) : 0
        while rows.count < shown.count {
            let r = FolderPreviewRowView(preview: self)
            rows.append(r)
            rowsView.addSubview(r)
        }
        while rows.count > shown.count { rows.removeLast().removeFromSuperview() }
        let now = Date()
        for (i, (r, item)) in zip(rows, shown).enumerated() { r.show(item, now: now, selected: i == selected) }
        empty.isHidden = !shown.isEmpty
        needsLayout = true
    }

    func controlTextDidChange(_ obj: Notification) {
        FolderPreviewController.shared.extended = true
        filter()
        scroll.contentView.scroll(to: .zero)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
        switch sel {
        case #selector(NSResponder.moveDown(_:)): move(by: 1)
        case #selector(NSResponder.moveUp(_:)): move(by: -1)
        case #selector(NSResponder.insertNewline(_:)):
            if shown.indices.contains(selected) { FolderPreviewController.shared.pick(shown[selected].id) }
        case #selector(NSResponder.cancelOperation(_:)): FolderPreviewController.shared.close()
        default: return false
        }
        return true
    }

    private func move(by delta: Int) {
        guard !shown.isEmpty else { return }
        FolderPreviewController.shared.extended = true
        let i = min(max(0, selected + delta), shown.count - 1)
        selected = i
        for (j, r) in rows.enumerated() { r.isSelected = j == i }
        rowsView.scrollToVisible(rows[i].frame.insetBy(dx: 0, dy: -FolderPreviewMetrics.listInset))
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        let w = bounds.width
        let m = FolderPreviewMetrics.self
        blur.frame = bounds
        shade.frame = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let r = m.corner
        outline.path = CGPath(roundedRect: bounds.insetBy(dx: 0.25, dy: 0.25), cornerWidth: r - 0.25, cornerHeight: r - 0.25, transform: nil)
        highlight.path = CGPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), cornerWidth: r - 0.75, cornerHeight: r - 0.75, transform: nil)
        CATransaction.commit()
        let sh = m.searchHeight
        searchIcon.frame = NSRect(x: m.iconCenter - 8, y: (sh - 16) / 2, width: 16, height: 16)
        let fh = field.intrinsicContentSize.height
        // The caret sits at 36 pt; NSTextField draws its text 1 pt inside its frame.
        field.frame = NSRect(x: m.textX - 1, y: (sh - fh) / 2, width: w - m.textX - 12, height: fh)
        line.frame = NSRect(x: 0, y: sh, width: w, height: 1)
        let top = sh + 1
        scroll.frame = NSRect(x: 0, y: top, width: w, height: bounds.height - top)
        rowsView.frame = NSRect(x: 0, y: 0, width: w, height: m.listInset + CGFloat(rows.count) * m.rowPitch)
        for (i, row) in rows.enumerated() {
            row.frame = NSRect(x: 0, y: m.listInset + CGFloat(i) * m.rowPitch, width: w, height: m.rowPitch)
        }
        let ew: CGFloat = 192
        let eh = empty.sizeThatFits(NSSize(width: ew, height: 200)).height
        empty.frame = NSRect(x: (w - ew) / 2, y: top + (bounds.height - top - eh) / 2, width: ew, height: eh)
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { FolderPreviewController.shared.pointerEnteredPanel() }
    override func mouseExited(with event: NSEvent) { FolderPreviewController.shared.pointerLeftPanel() }

    fileprivate func menu(for row: FolderPreviewRowView) -> NSMenu? {
        guard let i = rows.firstIndex(where: { $0 === row }), shown.indices.contains(i) else { return nil }
        let item = shown[i]
        let c = FolderPreviewController.shared
        let m = NSMenu()
        m.autoenablesItems = false
        c.extended = true
        MenuItems.add(m, "Copy Link") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.url, forType: .string)
        }
        MenuItems.add(m, "Open in Split View") { c.openInSplitView(item.id) }
        MenuItems.add(m, "Duplicate") { c.duplicate(item.id) }
        m.addItem(.separator())
        MenuItems.add(m, "Archive") { c.archive(item.id) }
        return m
    }
}

private final class FlippedRowsView: NSView {
    override var isFlipped: Bool { true }
}

/// One tab in the preview: favicon, title and "15 hours ago". The pointer draws its own highlight
/// beside the keyboard's (Arc shows both at once, in the same fill).
final class FolderPreviewRowView: NSView {
    private weak var preview: FolderPreviewView?
    private let fill = CALayer()
    private let favicon = SidebarFaviconView(size: 16)
    private let title = NSTextField.sidebarLabel(size: 13)
    private let age = NSTextField.sidebarLabel(size: 11)
    private let badge = CALayer()
    private var itemID: UUID?
    var isSelected = false { didSet { if isSelected != oldValue { refresh() } } }
    private var isHovered = false { didSet { if isHovered != oldValue { refresh() } } }

    init(preview: FolderPreviewView) {
        self.preview = preview
        super.init(frame: .zero)
        wantsLayer = true
        fill.cornerRadius = FolderPreviewMetrics.rowCorner
        fill.actions = ["backgroundColor": NSNull()]
        layer?.addSublayer(fill)
        addSubview(favicon)
        title.lineBreakMode = .byTruncatingTail
        title.textColor = FolderPreviewMetrics.title
        addSubview(title)
        age.textColor = FolderPreviewMetrics.secondary
        addSubview(age)
        badge.cornerRadius = 3
        badge.backgroundColor = FolderPreviewMetrics.title.cgColor
        layer?.addSublayer(badge)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ item: FolderPreviewItem, now: Date, selected: Bool) {
        itemID = item.id
        var colors = SidebarColors()
        colors.isDark = true
        favicon.show(item.icon, flip: item.icon != nil && item.glyphDark == true, colors: colors)
        title.stringValue = item.title
        age.stringValue = FolderPreviewMetrics.age(of: item.lastVisit, now: now)
        badge.isHidden = !item.badged
        isSelected = selected
        refresh()
        needsLayout = true
    }

    private func refresh() {
        fill.backgroundColor = (isSelected || isHovered ? FolderPreviewMetrics.rowFillColor : .clear).cgColor
    }

    override func layout() {
        super.layout()
        let m = FolderPreviewMetrics.self
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = CGRect(x: m.sideInset, y: 0, width: bounds.width - 2 * m.sideInset, height: m.rowFill)
        badge.frame = CGRect(x: bounds.width - m.sideInset - 12 - 6, y: (m.rowFill - 6) / 2, width: 6, height: 6)
        CATransaction.commit()
        favicon.frame = NSRect(x: m.iconCenter - 8, y: (m.rowFill - 16) / 2, width: 16, height: 16)
        let right = bounds.width - m.sideInset - (badge.isHidden ? 10 : 24)
        let th = title.intrinsicContentSize.height, ah = age.intrinsicContentSize.height
        // Arc: the title's caps start 8 pt into the row, the age line ends 35.5 pt in.
        let top = (m.rowFill - th - ah) / 2
        title.frame = NSRect(x: m.textX - SidebarText.inset, y: top, width: right - m.textX + 2 * SidebarText.inset, height: th)
        age.frame = NSRect(x: m.textX - SidebarText.inset, y: top + th, width: right - m.textX + 2 * SidebarText.inset, height: ah)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func mouseUp(with event: NSEvent) {
        guard let id = itemID, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        FolderPreviewController.shared.pick(id)
    }

    override func mouseDown(with event: NSEvent) {}

    override func menu(for event: NSEvent) -> NSMenu? { preview?.menu(for: self) }
}
