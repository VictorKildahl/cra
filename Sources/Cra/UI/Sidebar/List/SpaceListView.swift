import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    static let craSidebarItem = NSPasteboard.PasteboardType(UTType.craSidebarItem.identifier)
}

/// A space's pinned and Today list, drawn by AppKit like Arc's sidebar (an AppKit list of
/// cells), not SwiftUI. Scrolling moves one clip view; nothing is laid out or diffed per frame.
/// The list reads the store inside an observation scope, rebuilds its flat row models when
/// anything it read changes (once per run loop turn), and hands each row view a new model only
/// when it differs. Hover is one tracking area for the whole list, so scrolling under a resting
/// pointer costs a lookup, not a tracking-area pass over every row.
@MainActor
final class SpaceListView: NSView, NSDraggingSource {
    enum RowKey: Hashable {
        case item(UUID)
        case liveStatus(UUID)
        case placeholder
        case divider
        case newTab
    }

    enum Content: Equatable {
        case tab(TabRowModel)
        case folder(FolderRowModel)
        case split(SplitRowModel)
        case liveStatus(LiveStatusModel)
        case placeholder(active: Bool)
        case divider(hasToday: Bool)
        case newTab
    }

    struct Row {
        let key: RowKey
        var content: Content
        var decor = DropDecor()
        /// Item rows: where the item sits, for drops.
        var itemID: UUID?
        var parent: UUID?
        var index = 0
        var depth = 0
        var frame = CGRect.zero
    }

    let spaceID: UUID
    let store: SidebarStore
    let ui: SidebarUIState
    let actions: SidebarActions
    let favicons: FaviconCache
    private(set) var palette: SpacePalette
    private let scrollView = SpaceListScrollView()
    private let document = SpaceListDocument()
    private(set) var rows: [Row] = []
    /// Rows before the divider (pinned and its placeholder).
    private var pinnedCount = 0
    private var views: [RowKey: SidebarRowView] = [:]
    private var colors = SidebarColors()
    private var pinnedFrame = CGRect.zero
    private var todayFrame = CGRect.zero
    /// Bottom of the last row; the list keeps Arc's ~121 pt of empty space after it.
    private var contentBottom: CGFloat = 0
    private var highlightPinned = false
    private var highlightToday = false
    private var dropLineSpec: SidebarListDrop.Line?
    private let topHairline = NSView()
    private let bottomHairline = NSView()
    private var hairlineState = (top: false, bottom: false)
    private let pinnedHighlight = CALayer()
    private let todayHighlight = CALayer()
    private let dropLine = CALayer()
    private let jumpPill = SidebarJumpPill()
    private var syncQueued = false
    private var synced = false
    private var laidOutWidth: CGFloat = -1
    private weak var hovered: SidebarRowView?
    private weak var tipTarget: (any ArcTooltipTarget)?
    /// While the list scrolls, rows slide under the pointer: no tips until it has rested.
    private var scrolling = false
    private var scrollRest: Task<Void, Never>?
    private var lastRenaming: UUID?
    let autoscroller = DragAutoscroller()
    private static let all = NSHashTable<SpaceListView>.weakObjects()

    /// A swipe slides the lists under a resting pointer: their hover ends until it settles.
    static func endHover(for ui: SidebarUIState) {
        for l in all.allObjects where l.ui === ui { l.hoverAt(nil) }
    }

    static func refreshHover(for ui: SidebarUIState) {
        for l in all.allObjects where l.ui === ui { l.refreshHover() }
    }

    init(spaceID: UUID, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.spaceID = spaceID
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        palette = (store.space(spaceID) ?? store.focusedSpace(window: ui.windowID)).theme.palette
        super.init(frame: .zero)
        wantsLayer = true
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.verticalScroller = SidebarScroller()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.hasHorizontalScroller = false
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .allowed
        scrollView.automaticallyAdjustsContentInsets = false
        document.list = self
        document.wantsLayer = true
        scrollView.documentView = document
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        addSubview(scrollView)
        for h in [topHairline, bottomHairline] {
            h.wantsLayer = true
            h.alphaValue = 0
            addSubview(h)
        }
        jumpPill.onClick = { [weak self] in self?.scrollToSelected() }
        addSubview(jumpPill)
        for l in [pinnedHighlight, todayHighlight] {
            l.cornerRadius = 10
            l.zPosition = -1
            l.opacity = 0
            document.layer?.addSublayer(l)
        }
        dropLine.cornerRadius = 1
        dropLine.zPosition = 5
        dropLine.opacity = 0
        document.layer?.addSublayer(dropLine)
        document.registerForDraggedTypes([.craSidebarItem])
        autoscroller.anchor = document
        Self.all.add(self)
        sync()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        topHairline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1)
        bottomHairline.frame = NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1)
        if bounds.width != laidOutWidth {
            laidOutWidth = bounds.width
            layoutRows()
            placeViews(animated: false, fresh: [], gone: [])
            materialize()
        }
        updateHairlines(animated: false)
        updateJumpPill(animated: false)
    }

    // MARK: Model

    private func scheduleSync() {
        guard !syncQueued else { return }
        syncQueued = true
        DispatchQueue.main.async { [weak self] in self?.sync() }
    }

    private func sync() {
        syncQueued = false
        let built = withObservationTracking { build() } onChange: { [weak self] in
            Task { @MainActor in self?.scheduleSync() }
        }
        if let built { apply(built) }
    }

    private struct Built {
        var rows: [Row]
        var pinnedCount: Int
        var palette: SpacePalette
        var highlightPinned: Bool
        var highlightToday: Bool
        var line: SidebarListDrop.Line?
    }

    private func build() -> Built? {
        guard let space = store.space(spaceID) else { return nil }
        let palette = space.theme.palette
        let window = ui.windowID
        let drop = ui.listDrop
        let picks = ui.multiSelection
        let renaming = ui.renamingID
        let focusID = ui.keyboardFocusID
        let capturing = ui.capturingTabIDs
        let audible = ui.audibleTabIDs
        let refreshing = LiveFolderManager.shared.refreshing
        var out: [Row] = []

        func icon(_ key: String?) -> (NSImage?, Bool) {
            guard let img = favicons.image(forKey: key) else { return (nil, false) }
            return (img, favicons.glyphIsDark(forKey: key) == palette.isDark)
        }

        func decor(_ id: UUID) -> DropDecor {
            guard let drop else { return DropDecor() }
            var d = DropDecor()
            d.nudge = drop.rowAbove == id ? -SidebarListMetrics.nudge : (drop.rowBelow == id ? SidebarListMetrics.nudge : 0)
            d.dimmed = drop.draggedID == id || (picks.count > 1 && picks.contains(drop.draggedID) && picks.contains(id))
            switch drop.target {
            case .into(let t)? where t == id:
                d.badge = store.item(id)?.isFolder == true ? .init(symbol: "folder", label: "Move to Folder") : .init(symbol: "rectangle.split.3x1", label: "Add to Split")
            case .split(let t, let leading)? where t == id:
                d.combine = .split(leading: leading)
                d.combineDragged = drop.draggedID
            case .newFolder(let t)? where t == id:
                d.combine = .folder
                d.combineDragged = drop.draggedID
            default: break
            }
            return d
        }

        func add(_ item: SidebarItem, depth: Int, pinned: Bool, parent: UUID, index: Int) {
            var row = Row(key: .item(item.id), content: .newTab, decor: decor(item.id), itemID: item.id, parent: parent, index: index, depth: depth)
            if item.isFolder {
                let expanded = store.isExpanded(item.id)
                let glyph = palette.folderColors(item.folderIcon)
                row.content = .folder(FolderRowModel(
                    id: item.id, depth: depth, title: item.title ?? "Folder", renameText: item.title ?? "",
                    editing: renaming == item.id, expanded: expanded, live: item.isLiveFolder,
                    tint: NSColor(glyph.tint), fill: NSColor(glyph.fill),
                    tabCount: expanded ? 0 : store.tabs(under: item.id).count,
                    liveBusy: refreshing.contains(item.id), liveError: item.liveFolder.flatMap(LiveFolderText.warning)?.help,
                    liveSignInURL: item.liveFolder.flatMap(LiveFolderText.warning)?.signInURL,
                    liveHelp: LiveFolderText.refreshHelp(item.liveFolder)))
                out.append(row)
                guard expanded else { return }
                let kids = item.children
                for c in store.children(of: item.id) {
                    add(c, depth: depth + 1, pinned: pinned, parent: item.id, index: kids.firstIndex(of: c.id) ?? 0)
                }
                if item.isLiveFolder, let m = Self.liveStatus(item) {
                    out.append(Row(key: .liveStatus(item.id), content: .liveStatus(LiveStatusModel(text: m.text, url: m.url, depth: depth + 1))))
                }
            } else if let tab = item.tab {
                let selected = store.isSelected(item.id, window: window)
                let navigatedAway = pinned && tab.url != tab.savedURL && !tab.savedURL.isEmpty
                let (img, flip) = icon(tab.iconKey)
                row.content = .tab(TabRowModel(
                    id: item.id, depth: depth, pinned: pinned, title: item.displayTitle, customTitle: item.title != nil,
                    renameText: item.title ?? item.displayTitle, subtitle: Self.subtitle(tab, navigatedAway: navigatedAway),
                    icon: img, flipIcon: flip, githubMark: tab.liveItemURL != nil && tab.customIconKey == nil,
                    editing: renaming == item.id, selected: selected,
                    highlighted: picks.isEmpty ? selected : picks.contains(item.id),
                    capturing: capturing.contains(item.id), audible: audible.contains(item.id), muted: tab.muted, unread: item.isUnread,
                    navigatedAway: navigatedAway,
                    closeGroup: picks.contains(item.id) && picks.count > 1 ? picks.count : 1,
                    focusRing: focusID == item.id))
                out.append(row)
            } else if item.isSplit {
                let children = store.children(of: item.id).filter(\.isTab)
                let cells = children.map { c -> SplitRowModel.Cell in
                    let (img, flip) = icon(c.tab?.iconKey)
                    return .init(id: c.id, title: c.displayTitle, icon: img, flipIcon: flip)
                }
                row.content = .split(SplitRowModel(
                    id: item.id, depth: depth, today: !pinned,
                    selected: children.contains { store.isSelected($0.id, window: window) },
                    focusRing: focusID.map { f in children.contains { $0.id == f } } ?? false,
                    cells: cells))
                out.append(row)
            }
        }

        let pinnedKids = store.item(space.pinnedContainerID)?.children ?? []
        let pinnedItems = store.listedPinnedItems(in: space, window: window)
        for item in pinnedItems {
            add(item, depth: 0, pinned: true, parent: space.pinnedContainerID, index: pinnedKids.firstIndex(of: item.id) ?? 0)
        }
        let section = dropSection(drop)
        // With nothing pinned the list takes no room; a drag opens a real target. Not when
        // collapsed: the placeholder would claim an empty list and open under the pointer,
        // taking drops meant for the top of Today.
        if pinnedKids.isEmpty && drop != nil {
            out.append(Row(key: .placeholder, content: .placeholder(active: section == .pinned)))
        }
        let pinnedCount = out.count
        let todayKids = store.item(space.todayContainerID)?.children ?? []
        out.append(Row(key: .divider, content: .divider(hasToday: !todayKids.isEmpty)))
        let atTop = store.settings.newTabButtonAtTop
        if atTop { out.append(Row(key: .newTab, content: .newTab)) }
        for item in store.children(of: space.todayContainerID) {
            add(item, depth: 0, pinned: false, parent: space.todayContainerID, index: todayKids.firstIndex(of: item.id) ?? 0)
        }
        if !atTop { out.append(Row(key: .newTab, content: .newTab)) }
        return Built(rows: out, pinnedCount: pinnedCount, palette: palette,
                     highlightPinned: section == .pinned && !pinnedItems.isEmpty, highlightToday: section == .today,
                     line: drop?.line)
    }

    /// Arc shows the host under a pinned tab only when it has left the pinned site (navigating
    /// within the same host shows nothing); a live folder's pull request shows its author.
    private static func subtitle(_ tab: TabData, navigatedAway: Bool) -> String? {
        if let author = tab.liveSubtitle, URL(string: tab.url)?.host == "github.com" { return author }
        guard navigatedAway, let host = URL(string: tab.url)?.host, let saved = URL(string: tab.savedURL)?.host,
              host.replacingOccurrences(of: "www.", with: "") != saved.replacingOccurrences(of: "www.", with: "") else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// A line inside the open live folder when there are no pull requests to show, or GitHub
    /// can't be read (Arc: "Sign back in to GitHub.", "Login with SSO to unlock this folder").
    private static func liveStatus(_ item: SidebarItem) -> (text: String, url: String?)? {
        guard let live = item.liveFolder, item.children.isEmpty else { return nil }
        switch live.lastError {
        case .notSignedIn?: return ("Sign back in to GitHub.", live.signInURL)
        case .some: return ("We’re having trouble connecting to GitHub; click here to see your Pull Requests.", "https://github.com/pulls")
        case nil:
            if let org = live.ssoOrganizations.first { return ("Login with SSO to unlock this folder", "https://github.com/orgs/\(org)/sso") }
            if live.lastFetch == nil { return nil }
            return ("Pull requests from you and your team will show up here automatically", nil)
        }
    }

    /// Which list a drop lands in, when that pins or unpins the dragged item; that list
    /// lights up while the drag hovers.
    private func dropSection(_ drop: SidebarListDrop?) -> SidebarSection? {
        guard let drop, let target = drop.target else { return nil }
        let lands: SidebarSection
        switch target {
        case .insert(let parent, _): lands = isPinnedList(parent) ? .pinned : .today
        case .into(let id): lands = isPinnedList(id) ? .pinned : .today
        case .newFolder: lands = .pinned
        case .split: lands = .today
        }
        return lands == (isPinnedList(drop.draggedID) ? .pinned : .today) ? nil : lands
    }

    private func isPinnedList(_ id: UUID) -> Bool {
        if case .pinned? = store.rootContainer(of: id) { return true }
        return false
    }

    private func apply(_ b: Built) {
        palette = b.palette
        (scrollView.verticalScroller as? SidebarScroller)?.isDarkTheme = b.palette.isDark
        let newColors = SidebarColors(b.palette)
        let recolor = newColors != colors
        colors = newColors
        let oldFrames = Dictionary(rows.map { ($0.key, $0.frame) }, uniquingKeysWith: { a, _ in a })
        rows = b.rows
        pinnedCount = b.pinnedCount
        highlightPinned = b.highlightPinned
        highlightToday = b.highlightToday
        dropLineSpec = b.line
        layoutRows()

        var fresh: [SidebarRowView] = []
        var keep = Set<RowKey>()
        let range = wantedRange()
        for row in rows where Self.inRange(placed(row), range) {
            keep.insert(row.key)
            var view = views[row.key]
            if let v = view, !Self.fits(v, row.content) {
                retire(v)
                view = nil
            }
            if view == nil {
                let v = makeView(row)
                views[row.key] = v
                document.addSubview(v)
                fresh.append(v)
                view = v
            }
            guard let view else { continue }
            if recolor { view.setColors(colors) }
            configure(view, row.content)
        }
        var gone: [SidebarRowView] = []
        for (k, v) in views where !keep.contains(k) {
            views[k] = nil
            gone.append(v)
        }
        let moved = rows.contains { row in oldFrames[row.key].map { $0 != row.frame } ?? false }
        let animate = synced && window != nil && ui.spaceSwipe == 0 && (!fresh.isEmpty || !gone.isEmpty || moved)
        for row in rows { views[row.key]?.applyDecor(row.decor, animated: synced) }
        placeViews(animated: animate, fresh: fresh, gone: gone)
        materializedAt = scrollView.contentView.bounds.minY
        updateDropChrome()
        synced = true
        if let h = hovered, h.superview == nil || gone.contains(h) { hovered = nil }
        refreshHover()
        scrollToRenaming()
        updateJumpPill(animated: synced)
    }

    private static func fits(_ v: SidebarRowView, _ c: Content) -> Bool {
        switch c {
        case .tab: return v is TabRowView
        case .folder: return v is FolderRowView
        case .split: return v is SplitRowView
        case .liveStatus: return v is LiveStatusRowView
        case .placeholder: return v is PinPlaceholderRowView
        case .divider: return v is DividerRowView
        case .newTab: return v is NewTabRowView
        }
    }

    private func makeView(_ row: Row) -> SidebarRowView {
        switch row.content {
        case .tab: return TabRowView(key: row.key, list: self, colors: colors)
        case .folder: return FolderRowView(key: row.key, list: self, colors: colors)
        case .split: return SplitRowView(key: row.key, list: self, colors: colors)
        case .liveStatus: return LiveStatusRowView(key: row.key, list: self, colors: colors)
        case .placeholder: return PinPlaceholderRowView(key: row.key, list: self, colors: colors)
        case .divider: return DividerRowView(key: row.key, list: self, colors: colors)
        case .newTab: return NewTabRowView(key: row.key, list: self, colors: colors)
        }
    }

    private func configure(_ v: SidebarRowView, _ c: Content) {
        switch c {
        case .tab(let m): (v as? TabRowView)?.apply(m)
        case .folder(let m): (v as? FolderRowView)?.apply(m)
        case .split(let m): (v as? SplitRowView)?.apply(m)
        case .liveStatus(let m): (v as? LiveStatusRowView)?.apply(m)
        case .placeholder(let active): (v as? PinPlaceholderRowView)?.apply(active: active)
        case .divider(let hasToday): (v as? DividerRowView)?.apply(hasToday: hasToday)
        case .newTab: break
        }
    }

    // MARK: Rows near the screen

    /// Rows get views only within a screen or so of what shows, like NSTableView's cells: on
    /// every frame of a scroll AppKit walks every view in the list to update tracking areas.
    private var materializedAt: CGFloat = 0

    private func wantedRange() -> (CGFloat, CGFloat) {
        let clip = scrollView.contentView.bounds
        let margin = max(400, clip.height)
        return (clip.minY - margin, clip.maxY + margin)
    }

    private static func inRange(_ f: CGRect, _ r: (CGFloat, CGFloat)) -> Bool { f.maxY >= r.0 && f.minY <= r.1 }

    private func materialize() {
        materializedAt = scrollView.contentView.bounds.minY
        let range = wantedRange()
        for row in rows {
            let inside = Self.inRange(placed(row), range)
            if inside, views[row.key] == nil {
                let v = makeView(row)
                views[row.key] = v
                document.addSubview(v)
                configure(v, row.content)
                v.applyDecor(row.decor, animated: false)
                v.frame = placed(row)
            } else if !inside, let v = views[row.key] {
                views[row.key] = nil
                retire(v)
            }
        }
    }

    private func retire(_ v: SidebarRowView) {
        if hovered === v { hovered = nil }
        v.removeFromSuperview()
    }

    func depth(of key: RowKey) -> Int { rows.first { $0.key == key }?.depth ?? 0 }

    // MARK: Layout

    /// SpaceSectionView's stacks: 3 pt on top, pinned rows, the 18 pt divider, then Today; rows
    /// 1 pt apart and 10 pt in from the sides. Arc 1.171 (31 Oct): every pinned row takes 41 pt,
    /// the first one too, so the first sits 1 pt lower than Today's; nothing pinned takes none.
    private func layoutRows() {
        let width = bounds.width
        let inner = max(0, width - 20)
        var y: CGFloat = 3
        let pinnedTop = y
        for i in 0..<rows.count {
            let isDivider = rows[i].key == .divider
            if i == pinnedCount {
                pinnedFrame = NSRect(x: 10, y: pinnedTop, width: inner, height: y - pinnedTop)
            }
            if isDivider {
                rows[i].frame = NSRect(x: 0, y: y, width: width, height: 18)
                y += 18
                continue
            }
            if i != pinnedCount + 1 { y += CraMetrics.rowSpacing }
            let h: CGFloat
            if case .liveStatus(let m) = rows[i].content { h = LiveStatusRowView.height(m, width: inner) } else { h = CraMetrics.rowHeight }
            rows[i].frame = NSRect(x: 10, y: y, width: inner, height: h)
            y += h
        }
        let todayTop = rows.indices.contains(pinnedCount) ? rows[pinnedCount].frame.maxY : y
        todayFrame = NSRect(x: 10, y: todayTop, width: inner, height: max(0, y - todayTop))
        contentBottom = y
        let height = max(y + 121, scrollView.contentView.bounds.height)
        if document.frame.size != NSSize(width: width, height: height) {
            document.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
    }

    private func placed(_ row: Row) -> NSRect { row.frame.offsetBy(dx: 0, dy: row.decor.nudge) }

    private func placeViews(animated: Bool, fresh: [SidebarRowView], gone: [SidebarRowView]) {
        guard animated else {
            for row in rows { views[row.key]?.frame = placed(row) }
            gone.forEach { $0.removeFromSuperview() }
            return
        }
        let freshSet = Set(fresh.map(ObjectIdentifier.init))
        for row in rows {
            guard let v = views[row.key], freshSet.contains(ObjectIdentifier(v)) else { continue }
            // Rows opening inside a folder drop in from just above; others fade in place.
            v.frame = placed(row).offsetBy(dx: 0, dy: row.depth > 0 ? -6 : 0)
            v.alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = SidebarListMetrics.duration
            ctx.timingFunction = SidebarListMetrics.timing
            ctx.allowsImplicitAnimation = true
            for row in rows {
                guard let v = views[row.key] else { continue }
                if v.frame != placed(row) { v.animator().frame = placed(row) }
                if freshSet.contains(ObjectIdentifier(v)) { v.animator().alphaValue = 1 }
            }
            for v in gone { v.animator().alphaValue = 0 }
        } completionHandler: {
            gone.forEach { $0.removeFromSuperview() }
        }
    }

    private func updateDropChrome() {
        let fill = colors.hoverFill.cgColor
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        pinnedHighlight.backgroundColor = fill
        todayHighlight.backgroundColor = fill
        pinnedHighlight.frame = pinnedFrame.insetBy(dx: -2, dy: 0)
        todayHighlight.frame = todayFrame.insetBy(dx: -2, dy: 0)
        pinnedHighlight.opacity = highlightPinned ? 1 : 0
        todayHighlight.opacity = highlightToday ? 1 : 0
        if let line = dropLineSpec {
            dropLine.backgroundColor = colors.textPrimary.withAlphaComponent(0.5).cgColor
            if dropLine.opacity == 0 {
                CATransaction.setDisableActions(true)
                dropLine.frame = NSRect(x: line.minX, y: line.y - 1, width: max(0, line.maxX - line.minX), height: 2)
                CATransaction.setDisableActions(false)
            } else {
                dropLine.frame = NSRect(x: line.minX, y: line.y - 1, width: max(0, line.maxX - line.minX), height: 2)
            }
            dropLine.opacity = 1
        } else {
            dropLine.opacity = 0
        }
        CATransaction.commit()
    }

    // MARK: Scrolling

    @objc private func scrolled() {
        if abs(scrollView.contentView.bounds.minY - materializedAt) > 120 { materialize() }
        if !scrolling {
            scrolling = true
            if let t = tipTarget { ArcTooltipController.shared.mouseExited(t) }
            tipTarget = nil
            ArcTooltipController.shared.paused = true
        }
        scrollRest?.cancel()
        scrollRest = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            ArcTooltipController.shared.paused = false
            self?.scrolling = false
            self?.refreshHover()
        }
        updateHairlines(animated: true)
        updateJumpPill(animated: true)
        refreshHover()
    }

    // MARK: Jump to the open tab (Dia)

    /// The selected tab's row (a split row when the tab is in one) and the item IDs whose
    /// favicons stand for it. A tab in a closed folder has no row: the folder stands in for it.
    private func selectedRow() -> (row: Row, tabs: [UUID])? {
        for row in rows {
            switch row.content {
            case .tab(let m) where m.selected: return (row, [m.id])
            case .split(let m) where m.selected: return (row, m.cells.map(\.id))
            default: continue
            }
        }
        guard let id = store.selectedTabID(in: spaceID, window: ui.windowID) else { return nil }
        var parent = store.item(id)?.parentID
        while let p = parent {
            if let row = rows.first(where: { $0.key == .item(p) }) { return (row, [id]) }
            parent = store.item(p)?.parentID
        }
        return nil
    }

    /// Dia's TabOverflowGeometryTracker: the pill shows while the selected row is wholly
    /// past an edge of the visible list, at that edge.
    private func updateJumpPill(animated: Bool) {
        let visible = scrollView.contentView.bounds
        var edge: SidebarJumpPill.Edge?
        var tabs: [UUID] = []
        if let (row, ids) = selectedRow(), visible.height > 0 {
            let f = placed(row)
            if f.maxY <= visible.minY { edge = .top } else if f.minY >= visible.maxY { edge = .bottom }
            tabs = ids
        }
        let icons = tabs.map { id -> (image: NSImage?, flip: Bool, key: String?) in
            let key = store.item(id)?.tab?.iconKey
            return (favicons.image(forKey: key), favicons.glyphIsDark(forKey: key) == true, key)
        }
        jumpPill.show(edge: edge, icons: icons, animated: animated && window != nil)
        guard let edge else { return }
        let size = SidebarJumpPill.size(icons: min(3, icons.count))
        let y = edge == .top ? SidebarJumpPill.inset : bounds.height - SidebarJumpPill.inset - size.height
        let frame = NSRect(x: ((bounds.width - size.width) / 2).rounded(), y: y, width: size.width, height: size.height)
        if jumpPill.frame != frame { jumpPill.frame = frame }
    }

    /// Testing: the jump pill's click on the focused space's list.
    static func jumpToSelected(for ui: SidebarUIState, space: UUID) {
        for l in all.allObjects where l.ui === ui && l.spaceID == space { l.scrollToSelected() }
    }

    /// Tests without the pointer (cra://debug?folderPreview=<id>): the folder's preview as if hovered.
    static func debugFolderPreview(_ folderID: UUID, ui: SidebarUIState) {
        for l in all.allObjects where l.ui === ui {
            guard let row = l.views[.item(folderID)] as? FolderRowView else { continue }
            FolderPreviewController.shared.debugOpen(folderID, row: row, list: l)
        }
    }

    /// Scrolls the selected tab to the middle of the list (as far as the list allows).
    private func scrollToSelected() {
        guard let (row, _) = selectedRow() else { return }
        let clip = scrollView.contentView
        let visible = clip.bounds
        let f = placed(row)
        let y = min(max(0, f.midY - visible.height / 2), max(0, document.frame.height - visible.height))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.45
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.3, 0, 0.2, 1)
            clip.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.scrollView.reflectScrolledClipView(clip) }
        }
    }

    /// Arc 1.170 draws a full-width 1 pt hairline (~5% black over the light theme) at an edge of
    /// the list only while rows are hidden past it, fading over ~0.25 s.
    private func updateHairlines(animated: Bool) {
        let clip = scrollView.contentView.bounds
        let state = (top: clip.minY > 0.5, bottom: contentBottom - clip.minY > clip.height + 0.5)
        let color = (colors.isDark ? NSColor.white.withAlphaComponent(0.07) : NSColor.black.withAlphaComponent(0.05)).cgColor
        topHairline.layer?.backgroundColor = color
        bottomHairline.layer?.backgroundColor = color
        guard state != hairlineState || !animated else { return }
        hairlineState = state
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? 0.25 : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            topHairline.animator().alphaValue = state.top ? 1 : 0
            bottomHairline.animator().alphaValue = state.bottom ? 1 : 0
        }
    }

    /// A new folder starts renaming at the top of pinned, maybe scrolled away.
    private func scrollToRenaming() {
        let id = ui.renamingID
        defer { lastRenaming = id }
        guard let id, id != lastRenaming, let row = rows.first(where: { $0.key == .item(id) }) else { return }
        let clip = scrollView.contentView
        let visible = clip.bounds
        guard row.frame.minY < visible.minY || row.frame.maxY > visible.maxY else { return }
        let y = min(max(0, row.frame.midY - visible.height / 2), max(0, document.frame.height - visible.height))
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = SidebarListMetrics.timing
            clip.animator().setBoundsOrigin(NSPoint(x: 0, y: y))
        }
    }

    // MARK: Hover

    func pointerMoved(_ event: NSEvent?) {
        hoverAt(event?.locationInWindow)
    }

    private func refreshHover() {
        guard let w = window else { return }
        let p = w.mouseLocationOutsideOfEventStream
        let inside = document.visibleRect.contains(document.convert(p, from: nil)) && w.isVisible
        hoverAt(inside && document.isMouseInside ? p : nil)
    }

    private func hoverAt(_ windowPoint: NSPoint?) {
        var target: SidebarRowView?
        var local = NSPoint.zero
        // A swipe slides the strip under the pointer: no hover until it settles.
        if let wp = windowPoint, ui.spaceSwipe == 0, ui.libraryPage == nil {
            let p = document.convert(wp, from: nil)
            if document.visibleRect.contains(p), let row = rows.first(where: { placed($0).contains(p) }), let v = views[row.key] {
                target = v
                local = v.convert(wp, from: nil)
            }
        }
        if hovered !== target {
            hovered?.isHovered = false
            hovered = target
            target?.isHovered = true
            if let t = target as? TabRowView, let id = t.model?.id {
                if ui.hoveredTabID != id { ui.hoveredTabID = id }
            } else if let h = ui.hoveredTabID, views[.item(h)] != nil {
                ui.hoveredTabID = nil
            }
            FolderPreviewController.shared.hover(target, in: self)
        }
        target?.hoverMoved(to: local)
        let tip = scrolling ? nil : target?.tooltipTarget(at: local)
        if let old = tipTarget, old !== tip { ArcTooltipController.shared.mouseExited(old) }
        tipTarget = tip
        if let tip { ArcTooltipController.shared.mouseMoved(in: tip) }
    }

    // MARK: Clicks

    func clickTab(_ id: UUID, event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .shift])
        if !flags.isEmpty {
            ui.pick(id, range: flags.contains(.shift), in: store)
        } else if event.clickCount == 2 {
            ui.renamingID = id
        } else {
            ui.clearPicks(anchor: id)
            if ui.keyboardFocusID != nil { ui.keyboardFocusID = nil }
            store.selectTab(id, window: ui.windowID)
        }
    }

    /// Close acts on every picked tab when this row is one of them.
    func closeGroup(for id: UUID) -> [UUID] {
        ui.multiSelection.contains(id) && ui.multiSelection.count > 1 ? Array(ui.multiSelection) : [id]
    }

    func closeTabs(_ ids: [UUID]) {
        // The open tab goes last so closing it doesn't hop through tabs about to close.
        let open = store.selectedTabID(window: ui.windowID)
        let ordered = ids.filter { $0 != open } + ids.filter { $0 == open }
        for id in ordered { actions.closeTab(id) }
        ui.multiSelection.subtract(ids)
    }

    func listMenu() -> NSMenu? { SidebarMenus.spaceList(self) }

    // MARK: Drag source

    func beginDrag(_ id: UUID, from row: SidebarRowView, event: NSEvent) {
        hoverAt(nil)
        ui.draggingID = id
        let pb = NSPasteboardItem()
        if let data = try? JSONEncoder().encode(SidebarDragItem(id: id)) { pb.setData(data, forType: .craSidebarItem) }
        let item = NSDraggingItem(pasteboardWriter: pb)
        item.setDraggingFrame(row.bounds, contents: dragImage(of: row))
        row.beginDraggingSession(with: [item], event: event, source: self)
    }

    /// The row as it looks at rest, on a rounded card.
    private func dragImage(of row: SidebarRowView) -> NSImage {
        let size = row.bounds.size
        let rep = row.bitmapImageRepForCachingDisplay(in: row.bounds)
        if let rep { row.cacheDisplay(in: row.bounds, to: rep) }
        let fill = colors.isDark ? NSColor(white: 0.18, alpha: 0.92) : NSColor(white: 1, alpha: 0.92)
        return NSImage(size: size, flipped: false) { r in
            fill.setFill()
            NSBezierPath(roundedRect: r, xRadius: CraMetrics.rowCorner, yRadius: CraMetrics.rowCorner).fill()
            rep?.draw(in: r)
            return true
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? [.move, .copy, .generic, .private] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        autoscroller.stop()
        ui.draggingID = nil
        if ui.listDrop != nil { ui.listDrop = nil }
    }

    // MARK: Drop target

    func dragUpdated(_ info: NSDraggingInfo, entered: Bool) -> NSDragOperation {
        // Rows here set draggingID when the drag starts; a drag from another window only says
        // what it carries through the pasteboard.
        if entered, let data = info.draggingPasteboard.data(forType: .craSidebarItem),
           let d = try? JSONDecoder().decode(SidebarDragItem.self, from: data), ui.draggingID != d.id {
            ui.draggingID = d.id
        }
        autoscroller.update()
        guard let id = ui.draggingID, store.item(id) != nil else { return [] }
        let drop = resolve(dragged: id, at: document.convert(info.draggingLocation, from: nil))
        if drop != ui.listDrop {
            ui.listDrop = drop
            // A tick when a row starts offering to combine, so the change of meaning is felt as well as seen.
            switch drop.target {
            case .split?, .newFolder?:
                if store.settings.hapticFeedbackOnReorder { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
            default: break
            }
            // Spring-loaded folders: hovering a closed folder opens it.
            if case .into(let f)? = drop.target, store.item(f)?.isFolder == true, !store.isExpanded(f) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [ui, store] in
                    guard ui.listDrop?.target == .into(f) else { return }
                    store.setExpanded(f, true)
                }
            }
        }
        return info.draggingSourceOperationMask.contains(.move) ? .move : .copy
    }

    func dragExited() {
        autoscroller.stop()
        if ui.listDrop != nil { ui.listDrop = nil }
    }

    func performDrop(_ info: NSDraggingInfo) -> Bool {
        autoscroller.stop()
        guard let id = ui.draggingID, store.item(id) != nil else { return false }
        let point = document.convert(info.draggingLocation, from: nil)
        let drop = ui.listDrop ?? resolve(dragged: id, at: point)
        ui.listDrop = nil
        applyDrop(drop)
        // A click whose pointer slipped 3 pt became a drag; let go on its own row it is still a
        // click, so the tab opens (GitHub #7: "a single click on a tab sometimes did nothing").
        if drop.target == nil, store.item(id)?.isTab == true, ui.multiSelection.count <= 1,
           rows.first(where: { $0.itemID == id })?.frame.contains(point) == true {
            ui.clearPicks(anchor: id)
            store.selectTab(id, window: ui.windowID)
        }
        // Dia: Tabs ▸ "Haptic feedback when reordering tabs".
        if drop.target != nil, store.settings.hapticFeedbackOnReorder {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
        }
        ui.draggingID = nil
        return true
    }

    private func applyDrop(_ drop: SidebarListDrop) {
        let id = drop.draggedID
        // A picked tab carries the other picks along (a split still takes one pane).
        let group = ui.group(for: id, in: store)
        switch drop.target {
        case .insert(let parent, let index)?:
            store.moveItems(group, to: parent, index: index)
        case .newFolder(let tab)?:
            if let folder = store.createFolder(combining: tab, with: group) { ui.renamingID = folder.id }
        case .split(let tab, let leading)?:
            store.createSplit(with: leading ? [id, tab] : [tab, id], at: tab)
        case .into(let target)?:
            if store.item(target)?.isFolder == true {
                store.moveItems(group, to: target, index: nil)
                store.setExpanded(target, true)
            } else {
                store.moveItem(id, to: target, index: nil)
            }
        case nil:
            break
        }
    }

    private func isInside(_ id: UUID, _ ancestor: UUID) -> Bool {
        var cur = store.item(id)?.parentID
        var hops = 0
        while let c = cur, hops < 64 {
            if c == ancestor { return true }
            cur = store.item(c)?.parentID
            hops += 1
        }
        return false
    }

    /// Top and bottom quarters of a row insert before/after it; the middle combines: a folder
    /// takes the item, a Today tab makes a split (the dragged tab goes on the side of the row
    /// it hovers), a pinned tab makes a new folder, a split row takes a pane.
    func resolve(dragged id: UUID, at p: CGPoint) -> SidebarListDrop {
        guard let space = store.space(spaceID) else { return SidebarListDrop(draggedID: id) }
        let items = rows.filter { $0.itemID != nil }
        let group = ui.group(for: id, in: store)
        let isTab = store.item(id)?.isTab == true
        let half = CraMetrics.rowSpacing / 2
        var target: SidebarListDrop.Target?

        if let r = items.first(where: { p.y >= $0.frame.minY - half && p.y < $0.frame.maxY + half }),
           let rid = r.itemID, let parent = r.parent, let item = store.item(rid) {
            let f = (p.y - r.frame.minY) / max(1, r.frame.height)
            let middle = (0.25..<0.75).contains(f)
            let before = SidebarListDrop.Target.insert(parent: parent, index: r.index)
            let after = SidebarListDrop.Target.insert(parent: parent, index: r.index + 1)
            if group.contains(rid) || isInside(rid, id) {
                target = nil
            } else if item.isFolder {
                if f < 0.25 { target = before }
                else if f >= 0.75 { target = store.isExpanded(rid) ? .insert(parent: rid, index: 0) : after }
                else { target = .into(rid) }
            } else if middle && isTab && item.isTab {
                target = isInside(rid, space.todayContainerID)
                    ? .split(with: rid, leading: p.x < r.frame.midX)
                    : .newFolder(with: rid)
            } else if middle && isTab && item.isSplit {
                target = .into(rid)
            } else {
                target = f < 0.5 ? before : after
            }
        } else {
            // Between sections or past the last row: the divider splits pinned from today.
            if p.y < (pinnedFrame.maxY + todayFrame.minY) / 2 {
                target = .insert(parent: space.pinnedContainerID, index: p.y < pinnedFrame.minY ? 0 : store.children(of: space.pinnedContainerID).count)
            } else {
                // The New Tab row may lead Today, so its first tab, not the section, marks the top.
                let firstToday = items.first { $0.parent == space.todayContainerID }?.frame.minY ?? todayFrame.minY
                target = .insert(parent: space.todayContainerID, index: p.y < firstToday ? 0 : store.children(of: space.todayContainerID).count)
            }
        }

        // Dropping next to itself, or a folder into itself, changes nothing.
        if case .insert(let parent, let index)? = target {
            if parent == id || isInside(parent, id) {
                target = nil
            } else if group.count == 1, store.item(id)?.parentID == parent, let old = store.item(parent)?.children.firstIndex(of: id), index == old || index == old + 1 {
                target = nil
            }
        }

        // A live folder fills itself: nothing goes into it from outside, and its tabs make no new folders.
        switch target {
        case .into(let f)? where store.item(f)?.isLiveFolder == true: target = nil
        case .insert(let parent, _)? where store.item(parent)?.isLiveFolder == true && store.item(id)?.parentID != parent: target = nil
        case .newFolder(let tab)? where store.item(store.item(tab)?.parentID ?? tab)?.isLiveFolder == true: target = nil
        default: break
        }

        var drop = SidebarListDrop(draggedID: id, target: target)
        guard case .insert(let parent, let index)? = target else { return drop }
        let kids = store.item(parent)?.children ?? []
        var y: CGFloat?
        if index < kids.count, let f = items.first(where: { $0.itemID == kids[index] })?.frame {
            y = f.minY - half
        } else if index > 0, let r = items.last(where: { $0.itemID == kids[index - 1] || ($0.itemID.map { isInside($0, kids[index - 1]) } ?? false) }) {
            y = r.frame.maxY + half
        } else if store.item(parent)?.isFolder == true, let f = items.first(where: { $0.itemID == parent })?.frame {
            y = f.maxY + half
        }
        // An empty pinned list shows its own placeholder instead of a line.
        guard let y else { return drop }
        let depth = items.first { $0.itemID == parent }.map { $0.depth + 1 } ?? 0
        drop.line = .init(y: y, minX: todayFrame.minX + 8 + CGFloat(depth) * CraMetrics.indent, maxX: todayFrame.maxX - 6)
        drop.rowAbove = items.last { $0.frame.maxY <= y + 1 }?.itemID
        drop.rowBelow = items.first { $0.frame.minY >= y - 1 }?.itemID
        return drop
    }
}

enum SidebarListMetrics {
    /// Rows either side of the insertion line ease this far apart.
    static let nudge: CGFloat = 3
    /// SwiftUI's .snappy(duration: 0.22, extraBounce: 0), which the list's changes used.
    static let duration: TimeInterval = 0.22
    static let timing = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
}

/// The list's scroll view. Space swipes are read by the window controller's scroll monitor,
/// which has to see every event of a gesture: responsive scrolling takes a gesture's events
/// off that path once it starts over the list, and a horizontal gesture never scrolls a list.
final class SpaceListScrollView: NSScrollView {
    override class var isCompatibleWithResponsiveScrolling: Bool { false }

    /// Always overlay, also with "Show scroll bars: Always": rows are laid out over the full width.
    override var scrollerStyle: NSScroller.Style {
        get { .overlay }
        set { super.scrollerStyle = .overlay }
    }

    override func scrollWheel(with event: NSEvent) {
        if event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { return }
        super.scrollWheel(with: event)
    }
}

/// Arc 1.171's list scroller (31 Oct 2026, issue #31): AppKit's overlay scroller, shown while
/// scrolling and faded out after, with no track and a 4 pt knob 3 pt in from the sidebar's
/// edge, white at 49 % on dark themes. It is only as wide as the 10 pt gutter right of the rows,
/// so it never covers a row's trailing buttons.
final class SidebarScroller: NSScroller {
    var isDarkTheme = true { didSet { if isDarkTheme != oldValue { needsDisplay = true } } }

    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override class func scrollerWidth(for controlSize: NSControl.ControlSize, scrollerStyle: NSScroller.Style) -> CGFloat { 10 }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.height > 0 else { return }
        let r = NSRect(x: bounds.maxX - 7, y: knob.minY + 2, width: 4, height: max(0, knob.height - 4))
        (isDarkTheme ? NSColor.white.withAlphaComponent(0.49) : NSColor.black.withAlphaComponent(0.3)).setFill()
        NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2).fill()
    }
}

/// The list's document: rows sit on it, it takes drops, hovers and the list's own menu.
final class SpaceListDocument: NSView {
    weak var list: SpaceListView?
    private(set) var isMouseInside = false

    override var isFlipped: Bool { true }
    override class var isCompatibleWithResponsiveScrolling: Bool { false }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        // activeAlways: the key window is often a page, not the sidebar's.
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { isMouseInside = true; list?.pointerMoved(event) }
    override func mouseMoved(with event: NSEvent) { isMouseInside = true; list?.pointerMoved(event) }
    override func mouseExited(with event: NSEvent) { isMouseInside = false; list?.pointerMoved(nil) }

    // Right-click on empty list space; rows have their own menus.
    override func menu(for event: NSEvent) -> NSMenu? { list?.listMenu() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { list?.dragUpdated(sender, entered: true) ?? [] }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { list?.dragUpdated(sender, entered: false) ?? [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { list?.dragExited() }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { list?.performDrop(sender) ?? false }
    override func draggingEnded(_ sender: NSDraggingInfo) { list?.dragExited() }
}
