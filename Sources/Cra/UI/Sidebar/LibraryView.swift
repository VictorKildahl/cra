import AppKit

/// The Library's pages Cra has, in the order of Arc's rail (which also lists Media, Easels and Boosts).
enum LibraryPage: String, CaseIterable {
    case downloads, spaces, archive

    var title: String {
        switch self {
        case .downloads: "Downloads"
        case .spaces: "Spaces"
        case .archive: "Archived Tabs"
        }
    }
    var symbol: String {
        switch self {
        case .downloads: "arrow.down.circle"
        case .spaces: "square.on.square"
        case .archive: "archivebox"
        }
    }
    var selectedSymbol: String { symbol + ".fill" }
    var searchPrompt: String { self == .downloads ? "Search Downloads…" : "Search Archive…" }
}

/// Arc's Library: not a window but a mode of the sidebar (WindowState+Library, HomeButton/*),
/// so it never ends up behind the browser. Measured on Arc 1.170 (window captures + AX tree,
/// 1728×1084 window, 27 Oct 2026):
/// - The sidebar widens from 347 to 417 pt: a 113 pt rail (a faint white wash brightening
///   toward its right edge, ending in a 1 pt hairline) and the page's list.
/// - Rail buttons 97×80 at x 8, 100 pt apart, the group centred vertically: an 18 pt glyph
///   22 pt from the top, the 12 pt semibold label under it (white 60 %). The page shown gets
///   a white 7 % fill and its glyph filled in the space's accent.
/// - The list column: a 36 pt search field ("Search Archive…") from x 120 and a Filter button
///   at the top, 10 pt from the window top; day headers ("Today", 13 pt semibold); rows 56 pt
///   apart with a 24 pt icon at x 130, the title at x 164 (14 pt) and the URL under it (12 pt).
/// - A back arrow (32×32 at x 8, 8 pt above the bottom) leaves the Library.
/// - Arc leaves it by the shortcut, Escape, that arrow or a swipe (LibraryCloseSource), never by
///   clicking elsewhere, and reopens it on the page last shown.
/// - Opening takes 2–3 frames (the Library slides in from a little to the left); closing slides
///   it left over ~0.1 s while the tab list fades back in.
enum LibraryMetrics {
    static let rail: CGFloat = 113
    /// Arc's Library sidebar was 70 pt wider than the 347 pt tab sidebar.
    static let extraWidth: CGFloat = 70
}

/// The Library column: the page rail on the left, the page's search and list on the right.
@MainActor
final class LibraryView: NSView {
    private let store: SidebarStore
    private let actions: SidebarActions
    private let favicons: FaviconCache
    private let rail = LibraryRailView()
    private let list: LibraryListView
    private let ui: SidebarUIState
    /// The Spaces page (Manage Spaces…) shows every space instead of a list.
    private var spaces: SpacesManagerView?
    var page: LibraryPage { didSet { if page != oldValue { pageChanged() } } }
    var palette: SpacePalette { didSet { apply() } }

    init(page: LibraryPage, palette: SpacePalette, store: SidebarStore, ui: SidebarUIState, actions: SidebarActions, favicons: FaviconCache) {
        self.page = page
        self.palette = palette
        self.store = store
        self.ui = ui
        self.actions = actions
        self.favicons = favicons
        list = LibraryListView(page: page, store: store, actions: actions, favicons: favicons)
        super.init(frame: .zero)
        rail.onPick = { actions.showLibrary($0) }
        rail.onBack = { actions.closeLibrary() }
        list.onEscape = { actions.closeLibrary() }
        addSubview(rail)
        addSubview(list)
        apply()
        pageChanged()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func pageChanged() {
        rail.show(page: page)
        if page == .spaces {
            if spaces == nil {
                let v = SpacesManagerView(store: store, ui: ui, actions: actions, favicons: favicons)
                addSubview(v)
                spaces = v
            }
        } else {
            list.page = page
        }
        list.isHidden = page == .spaces
        spaces?.isHidden = page != .spaces
        needsLayout = true
    }

    private func apply() {
        rail.colors = SidebarColors(palette)
        list.colors = SidebarColors(palette)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A swipe brings the Library in under the fingers; its search takes the keys once it lands.
        if ui.libraryReveal == nil { list.focusSearch() }
    }

    func focusSearch() { list.focusSearch() }

    override func cancelOperation(_ sender: Any?) { actions.closeLibrary() }

    override func layout() {
        super.layout()
        rail.frame = NSRect(x: 0, y: 0, width: LibraryMetrics.rail, height: bounds.height)
        list.frame = NSRect(x: LibraryMetrics.rail, y: 0, width: max(0, bounds.width - LibraryMetrics.rail), height: bounds.height)
        spaces?.frame = list.frame
    }
}

/// The rail: a faint wash brightening to the right, ending in a hairline; the page buttons
/// centred; the back arrow at the bottom.
private final class LibraryRailView: NSView {
    var onPick: (LibraryPage) -> Void = { _ in }
    var onBack: () -> Void = {}
    var colors = SidebarColors() { didSet { refresh() } }
    private let wash = CAGradientLayer()
    private let hairline = CALayer()
    private var buttons: [LibraryRailButton] = []
    private var back: SidebarGlyphButton?
    private var page: LibraryPage = .downloads

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        wash.startPoint = CGPoint(x: 0, y: 0.5)
        wash.endPoint = CGPoint(x: 1, y: 0.5)
        layer?.addSublayer(wash)
        layer?.addSublayer(hairline)
        for p in LibraryPage.allCases {
            let b = LibraryRailButton(page: p)
            b.onPress = { [weak self] in self?.onPick(p) }
            buttons.append(b)
            addSubview(b)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(page: LibraryPage) {
        self.page = page
        refresh()
    }

    private func refresh() {
        let ink: NSColor = colors.isDark ? .white : .black
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.colors = [ink.withAlphaComponent(0.02).cgColor, ink.withAlphaComponent(0.045).cgColor]
        hairline.backgroundColor = ink.withAlphaComponent(0.09).cgColor
        CATransaction.commit()
        for b in buttons { b.show(selected: b.page == page, ink: ink) }
        if back == nil {
            let b = SidebarGlyphButton(symbol: "arrow.left", size: 32, height: 32, iconSize: 15, weight: .regular,
                                       help: "Exit the Library (Esc)", colors: colors) { [weak self] in self?.onBack() }
            addSubview(b)
            back = b
        }
        back?.colors = colors
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let w = LibraryMetrics.rail - 1, h = bounds.height
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = NSRect(x: 0, y: 0, width: w, height: h)
        hairline.frame = NSRect(x: w, y: 0, width: 1, height: h)
        CATransaction.commit()
        // Spacer(minLength: title area), the buttons 20 apart, Spacer, the back arrow 8 pt in.
        let group = CGFloat(buttons.count) * 80 + CGFloat(max(0, buttons.count - 1)) * 20
        let free = max(0, h - group - 40)
        let top = max(CraMetrics.titleAreaHeight, free / 2)
        for (i, b) in buttons.enumerated() {
            b.frame = NSRect(x: (w - 97) / 2, y: top + CGFloat(i) * 100, width: 97, height: 80)
        }
        back?.frame = NSRect(x: 8, y: h - 8 - 32, width: 32, height: 32)
    }
}

private final class LibraryRailButton: NSView {
    let page: LibraryPage
    var onPress: () -> Void = {}
    private let glyph = NSImageView()
    private let label = NSTextField.sidebarLabel(size: 12, weight: .semibold)
    private var selected = false
    private var ink = NSColor.white
    private var hovering = false { didSet { if hovering != oldValue { refresh() } } }

    init(page: LibraryPage) {
        self.page = page
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        glyph.imageScaling = .scaleNone
        addSubview(glyph)
        label.stringValue = page.title
        label.alignment = .center
        addSubview(label)
        setAccessibilityLabel(page.title)
        setAccessibilityRole(.button)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(selected: Bool, ink: NSColor) {
        self.selected = selected
        self.ink = ink
        refresh()
    }

    private func refresh() {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        if selected {
            // The filled glyph in palette mode: white mark on the accent colour.
            glyph.image = NSImage(systemSymbolName: page.selectedSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config.applying(.init(paletteColors: [.white, .controlAccentColor])))
            glyph.contentTintColor = nil
        } else {
            glyph.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            glyph.contentTintColor = ink.withAlphaComponent(0.6)
        }
        label.textColor = ink.withAlphaComponent(selected ? 0.82 : 0.6)
        layer?.backgroundColor = ink.withAlphaComponent(selected ? 0.07 : (hovering ? 0.04 : 0)).cgColor
    }

    override func layout() {
        super.layout()
        // The glyph in a 20 pt band 21 pt down, the label 9 pt under it.
        glyph.frame = NSRect(x: 0, y: 21, width: bounds.width, height: 20)
        label.frame = NSRect(x: 0, y: 50, width: bounds.width, height: 15)
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
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress() }
    }
}

/// The page's list column: search, then the downloads or the archived tabs by day.
private final class LibraryListView: NSView, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    enum Row {
        case header(String)
        case download(DownloadHistory.Entry)
        case archived(ArchivedItem)
    }

    private let store: SidebarStore
    private let actions: SidebarActions
    private let favicons: FaviconCache
    var onEscape: () -> Void = {}
    var page: LibraryPage { didSet { if page != oldValue { field.stringValue = ""; query = ""; field.placeholderString = page.searchPrompt; reload() } } }
    var colors = SidebarColors() { didSet { if colors != oldValue { refresh(); table.reloadData() } } }
    private var query = ""
    private var rows: [Row] = []
    private let searchBox = NSView()
    private let searchGlyph = NSImageView()
    private let field = NSTextField()
    private let menuButton = NSView()
    private let menuGlyph = NSImageView()
    private let scroll = NSScrollView()
    private let table = NSTableView()
    private let empty = LibraryEmptyView()

    init(page: LibraryPage, store: SidebarStore, actions: SidebarActions, favicons: FaviconCache) {
        self.page = page
        self.store = store
        self.actions = actions
        self.favicons = favicons
        super.init(frame: .zero)
        searchBox.wantsLayer = true
        searchBox.layer?.cornerRadius = 12
        searchBox.layer?.cornerCurve = .continuous
        addSubview(searchBox)
        searchGlyph.image = SidebarSymbols.image("magnifyingglass", size: 14)
        searchGlyph.imageScaling = .scaleNone
        searchBox.addSubview(searchGlyph)
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.placeholderString = page.searchPrompt
        field.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.delegate = self
        searchBox.addSubview(field)
        menuButton.wantsLayer = true
        menuButton.layer?.cornerRadius = 12
        menuButton.layer?.cornerCurve = .continuous
        menuGlyph.image = SidebarSymbols.image("ellipsis", size: 14, weight: .medium)
        menuGlyph.imageScaling = .scaleNone
        menuGlyph.frame = NSRect(x: 0, y: 0, width: 36, height: 36)
        menuButton.addSubview(menuGlyph)
        addSubview(menuButton)
        let column = NSTableColumn(identifier: .init("row"))
        table.addTableColumn(column)
        table.headerView = nil
        table.backgroundColor = .clear
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .none
        table.style = .plain
        table.usesAutomaticRowHeights = false
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.menu = NSMenu()
        table.menu?.delegate = self
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        scroll.automaticallyAdjustsContentInsets = false
        addSubview(scroll)
        addSubview(empty)
        observe()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func focusSearch() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            w.makeFirstResponder(self.field)
        }
    }

    private func observe() {
        withObservationTracking {
            _ = store.archive
            _ = DownloadHistory.shared.entries
            _ = DownloadHistory.shared.thumbnails.count
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        reload()
    }

    private var needle: String { query.lowercased().trimmingCharacters(in: .whitespaces) }

    private func reload() {
        var out: [Row] = []
        switch page {
        case .downloads:
            let all = DownloadHistory.shared.entries.reversed().filter { FileManager.default.fileExists(atPath: $0.path) }
            let shown = needle.isEmpty ? all : all.filter { ($0.path as NSString).lastPathComponent.lowercased().contains(needle) }
            for (label, entries) in Self.grouped(shown, date: \.date) {
                out.append(.header(label))
                out += entries.map { .download($0) }
            }
            empty.show(symbol: "arrow.down.circle", title: all.isEmpty ? "Nothing here yet!" : "No matches",
                       detail: all.isEmpty ? "Files you download show up here." : nil)
        case .spaces:
            break
        case .archive:
            let shown = needle.isEmpty ? store.archive : store.archive.filter {
                $0.item.displayTitle.lowercased().contains(needle) || ($0.item.tab?.url.lowercased().contains(needle) ?? false)
            }
            for (label, entries) in Self.grouped(shown, date: \.archivedAt) {
                out.append(.header(label))
                out += entries.map { .archived($0) }
            }
            empty.show(symbol: "archivebox", title: store.archive.isEmpty ? "Nothing here yet!" : "No matches",
                       detail: store.archive.isEmpty ? "Tabs you close end up here." : nil)
        }
        rows = out
        empty.isHidden = !out.isEmpty
        scroll.isHidden = out.isEmpty
        table.reloadData()
        refresh()
    }

    private func refresh() {
        let ink: NSColor = colors.isDark ? .white : .black
        searchBox.layer?.backgroundColor = ink.withAlphaComponent(0.08).cgColor
        searchGlyph.contentTintColor = ink.withAlphaComponent(0.5)
        field.textColor = colors.textPrimary
        menuButton.layer?.backgroundColor = ink.withAlphaComponent(0.05).cgColor
        menuGlyph.contentTintColor = ink.withAlphaComponent(0.7)
        empty.ink = ink
    }

    private static func grouped<T>(_ items: [T], date: KeyPath<T, Date>) -> [(String, [T])] {
        let cal = Calendar.current
        let df = DateFormatter()
        df.dateStyle = .medium
        var order: [String] = []
        var groups: [String: [T]] = [:]
        for e in items {
            let d = e[keyPath: date]
            let label = cal.isDateInToday(d) ? "Today" : (cal.isDateInYesterday(d) ? "Yesterday" : df.string(from: d))
            if groups[label] == nil { order.append(label) }
            groups[label, default: []].append(e)
        }
        return order.map { ($0, groups[$0]!) }
    }

    override func layout() {
        super.layout()
        // HStack(spacing: 4) 10 pt down, 7 pt in, 8 pt from the right: the field, the ⋯ button.
        let w = bounds.width
        searchBox.frame = NSRect(x: 7, y: 10, width: max(0, w - 7 - 8 - 4 - 36), height: 36)
        menuButton.frame = NSRect(x: w - 8 - 36, y: 10, width: 36, height: 36)
        let gw = searchGlyph.image?.size.width ?? 14
        searchGlyph.frame = NSRect(x: 12, y: 0, width: gw, height: 36)
        let fh = ceil(field.intrinsicContentSize.height)
        let fx = 12 + gw + 10
        field.frame = NSRect(x: fx - SidebarText.inset, y: (36 - fh) / 2, width: max(0, searchBox.bounds.width - fx - 12) + 2 * SidebarText.inset, height: fh)
        scroll.frame = NSRect(x: 0, y: 46, width: w, height: max(0, bounds.height - 46))
        table.tableColumns.first?.width = w
        empty.frame = scroll.frame
    }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) {
        query = field.stringValue
        reload()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) { onEscape(); return true }
        return false
    }

    // MARK: ⋯ menu (Arc's Filter button; Cra's holds the page's actions)

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard menuButton.frame.contains(p) else { return super.mouseDown(with: event) }
        let menu = NSMenu()
        menu.autoenablesItems = false
        switch page {
        case .downloads:
            // The folder the window's profile downloads to (#190).
            let profile = (window?.windowController as? MainWindowController)?.profileDirectoryName
            MenuItems.add(menu, "Open Downloads Folder") {
                NSWorkspace.shared.open(DownloadDestinations.folder(profileID: DownloadDestinations.profileID(profilePath: profile)))
            }
        case .archive:
            let store = store
            MenuItems.add(menu, "Clear Archive", enabled: !store.archive.isEmpty) { store.clearArchive() }
        case .spaces:
            return
        }
        menu.popUp(positioning: nil, at: NSPoint(x: menuButton.frame.minX, y: menuButton.frame.maxY + 4), in: self)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return 40 }
        return 56
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let label):
            let v = tableView.makeView(withIdentifier: .init("header"), owner: nil) as? LibraryHeaderCell ?? LibraryHeaderCell()
            v.identifier = .init("header")
            v.show(label, ink: colors.isDark ? .white : .black)
            return v
        case .download(let e):
            let v = tableView.makeView(withIdentifier: .init("item"), owner: nil) as? LibraryItemCell ?? LibraryItemCell()
            v.identifier = .init("item")
            v.showDownload(e, colors: colors)
            return v
        case .archived(let e):
            let v = tableView.makeView(withIdentifier: .init("item"), owner: nil) as? LibraryItemCell ?? LibraryItemCell()
            v.identifier = .init("item")
            v.showArchived(e, icon: favicons.image(forKey: e.item.tab?.faviconKey), colors: colors) { [actions] in actions.restoreArchived(e.id) }
            return v
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }
}

extension LibraryListView: NSMenuDelegate {
    /// The row's context menu, built for the row under the pointer.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.clickedRow
        guard rows.indices.contains(row) else { return }
        switch rows[row] {
        case .header: break
        case .archived(let e):
            let actions = actions, store = store
            MenuItems.add(menu, "Restore") { actions.restoreArchived(e.id) }
            MenuItems.add(menu, "Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(e.item.tab?.url ?? "", forType: .string)
            }
            menu.addItem(.separator())
            MenuItems.add(menu, "Remove from Archive") { store.removeFromArchive(e.id) }
        case .download(let e):
            let url = URL(fileURLWithPath: e.path)
            MenuItems.add(menu, "Open") { NSWorkspace.shared.open(url) }
            MenuItems.add(menu, "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            menu.addItem(.separator())
            MenuItems.add(menu, "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([url as NSURL])
            }
        }
    }
}

private final class LibraryHeaderCell: NSView {
    private let label = NSTextField.sidebarLabel(size: 13, weight: .semibold)

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(_ text: String, ink: NSColor) {
        label.stringValue = text
        label.textColor = ink.withAlphaComponent(0.6)
    }

    override func layout() {
        super.layout()
        // 11 pt in, 18 pt above, 6 pt below.
        label.frame = NSRect(x: 11 - SidebarText.inset, y: 18, width: bounds.width - 11, height: 16)
    }
}

/// An archived tab (24 pt icon tile, title over URL) or a download (32 pt thumbnail, name over
/// age): 52 pt tall inside 4 × 2 pt of padding, the space's hover fill under the pointer.
private final class LibraryItemCell: NSView, NSDraggingSource {
    private let card = FlippedView()
    private let tile = NSView()
    private let icon = NSImageView()
    private let title = NSTextField.sidebarLabel(size: 14)
    private let detail = NSTextField.sidebarLabel(size: 12)
    private var tip: ArcTooltipAnchorView?
    private var colors = SidebarColors()
    private var download: DownloadHistory.Entry?
    private var restore: (() -> Void)?
    private var downAt: NSPoint?
    private var hovering = false { didSet { if hovering != oldValue { refreshHover() } } }

    private static let age: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.cornerCurve = .continuous
        addSubview(card)
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 6
        tile.layer?.cornerCurve = .continuous
        tile.layer?.masksToBounds = true
        tile.layer?.contentsGravity = .resizeAspectFill
        card.addSubview(tile)
        icon.imageScaling = .scaleProportionallyUpOrDown
        tile.addSubview(icon)
        card.addSubview(title)
        card.addSubview(detail)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func showArchived(_ e: ArchivedItem, icon image: NSImage?, colors: SidebarColors, restore: @escaping () -> Void) {
        self.colors = colors
        download = nil
        self.restore = restore
        let ink: NSColor = colors.isDark ? .white : .black
        tile.layer?.contents = nil
        tile.layer?.backgroundColor = ink.withAlphaComponent(0.04).cgColor
        icon.isHidden = image == nil
        icon.image = image
        title.stringValue = e.item.displayTitle
        title.lineBreakMode = .byTruncatingTail
        detail.stringValue = SuggestionEngine.humanURL(e.item.tab?.url ?? "")
        let url = e.item.tab?.url ?? ""
        if let tip { (tip.text, tip.keys) = (url, []) } else if !url.isEmpty { tip = ArcTooltipAnchorView.attach(to: self, help: url) }
        tip?.text = url
        apply(ink: ink)
    }

    func showDownload(_ e: DownloadHistory.Entry, colors: SidebarColors) {
        self.colors = colors
        download = e
        restore = nil
        let ink: NSColor = colors.isDark ? .white : .black
        icon.isHidden = true
        if let image = DownloadHistory.shared.thumbnail(for: e.path) {
            var rect = NSRect(x: 0, y: 0, width: 32, height: 32)
            let scale = window?.backingScaleFactor ?? 2
            tile.layer?.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
            tile.layer?.contentsScale = scale
            tile.layer?.backgroundColor = nil
        } else {
            tile.layer?.contents = nil
            tile.layer?.backgroundColor = ink.withAlphaComponent(0.04).cgColor
        }
        title.stringValue = (e.path as NSString).lastPathComponent
        title.lineBreakMode = .byTruncatingMiddle
        detail.stringValue = Self.age.localizedString(for: min(e.date, Date()), relativeTo: Date())
        tip?.text = ""
        apply(ink: ink)
    }

    private func apply(ink: NSColor) {
        title.textColor = ink.withAlphaComponent(0.82)
        detail.textColor = ink.withAlphaComponent(0.55)
        refreshHover()
        needsLayout = true
    }

    private func refreshHover() {
        card.layer?.backgroundColor = (hovering ? colors.hoverFill : .clear).cgColor
    }

    override func layout() {
        super.layout()
        card.frame = bounds.insetBy(dx: 4, dy: 2)
        let h = card.bounds.height
        // Archived: 24 pt tile 9 pt in; download: 32 pt thumbnail 5 pt in; the text 10 pt after.
        let isDownload = download != nil
        let t: CGFloat = isDownload ? 32 : 24
        let x: CGFloat = isDownload ? 5 : 9
        tile.frame = NSRect(x: x, y: (h - t) / 2, width: t, height: t)
        icon.frame = NSRect(x: (t - 16) / 2, y: (t - 16) / 2, width: 16, height: 16)
        // HStack(spacing: 10) ends in a Spacer, so the text stops 10 + 8 pt short of the edge.
        let tx = x + t + 10, tw = max(0, card.bounds.width - tx - 18)
        // VStack(spacing: 1) of 17 + 15, centred.
        let top = (h - 33) / 2
        title.frame = NSRect(x: tx - SidebarText.inset, y: top, width: tw + 2 * SidebarText.inset, height: 17)
        detail.frame = NSRect(x: tx - SidebarText.inset, y: top + 18, width: tw + 2 * SidebarText.inset, height: 15)
    }

    // MARK: Pointer

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas where t.owner === self { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func mouseDown(with event: NSEvent) { downAt = event.locationInWindow }

    override func mouseDragged(with event: NSEvent) {
        guard let start = downAt, let download else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) > 3 else { return }
        downAt = nil
        let item = NSDraggingItem(pasteboardWriter: URL(fileURLWithPath: download.path) as NSURL)
        item.setDraggingFrame(convert(tile.frame, from: card), contents: DownloadHistory.shared.thumbnail(for: download.path) ?? NSWorkspace.shared.icon(forFile: download.path))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        defer { downAt = nil }
        guard downAt != nil, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        if let download { NSWorkspace.shared.open(URL(fileURLWithPath: download.path)) } else { restore?() }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .generic] : .copy
    }
}

private final class LibraryEmptyView: NSView {
    var ink = NSColor.white { didSet { refresh() } }
    private let glyph = NSImageView()
    private let title = NSTextField.sidebarLabel(size: 17, weight: .semibold)
    private let detail = NSTextField(wrappingLabelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        glyph.imageScaling = .scaleNone
        addSubview(glyph)
        title.alignment = .center
        addSubview(title)
        detail.font = .systemFont(ofSize: 14)
        detail.alignment = .center
        addSubview(detail)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func show(symbol: String, title text: String, detail d: String?) {
        glyph.image = SidebarSymbols.image(symbol, size: 30, weight: .light)
        title.stringValue = text
        detail.stringValue = d ?? ""
        detail.isHidden = d == nil
        refresh()
    }

    private func refresh() {
        glyph.contentTintColor = ink.withAlphaComponent(0.45)
        title.textColor = ink.withAlphaComponent(0.9)
        detail.textColor = ink.withAlphaComponent(0.7)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // 260 pt down, 16 pt in: the glyph (+4), 8, the title, 8, the detail.
        let w = max(0, bounds.width - 32)
        let gh = glyph.image?.size.height ?? 30
        var y: CGFloat = 260 - 46
        glyph.frame = NSRect(x: 16, y: y, width: w, height: gh)
        y += gh + 4 + 8
        title.frame = NSRect(x: 16, y: y, width: w, height: 21)
        y += 21 + 8
        let dh = detail.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: w, height: 200)).height ?? 17
        detail.frame = NSRect(x: 16, y: y, width: w, height: ceil(dh))
    }
}
