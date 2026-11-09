import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The Library's pages Cra has, in the order of Arc's rail (which also lists Easels and Boosts).
enum LibraryPage: String, CaseIterable {
    case media, downloads, easels, spaces, boosts, archive

    var title: String {
        switch self {
        case .media: "Media"
        case .downloads: "Downloads"
        case .easels: "Easels"
        case .spaces: "Spaces"
        case .boosts: "Boosts"
        case .archive: "Archived Tabs"
        }
    }
    var symbol: String {
        switch self {
        case .media: "photo.on.rectangle"
        case .downloads: "arrow.down.circle"
        case .easels: "pencil.and.scribble"
        case .spaces: "square.on.square"
        case .boosts: "paintbrush.pointed"
        case .archive: "archivebox"
        }
    }
    var selectedSymbol: String {
        switch self {
        case .media: "photo.fill.on.rectangle.fill"
        case .easels: symbol
        case .boosts: "paintbrush.pointed.fill"
        default: symbol + ".fill"
        }
    }
    var searchPrompt: String {
        switch self {
        case .media: "Search Media…"
        case .downloads: "Search Downloads…"
        case .easels: "Search Easels…"
        case .boosts: "Search Boosts…"
        default: "Search Archive…"
        }
    }
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
        rail.pageMenu = { [store, weak self] p in LibraryListView.pageMenu(p, store: store, profile: (self?.window?.windowController as? MainWindowController)?.profileDirectoryName) }
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
                v.accent = accent
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

    /// The space's accent pair (Arc 1.172.1): on a light theme the folder's tinted light with its
    /// shaded dark on it; on a dark one near-white with dark.
    private var accent: (fill: NSColor, ink: NSColor) {
        palette.isDark ? (NSColor.white.withAlphaComponent(0.88), NSColor.black.withAlphaComponent(0.8))
                       : (NSColor(palette.folderFill), NSColor(palette.folderTint))
    }

    private func apply() {
        rail.accent = accent
        spaces?.accent = accent
        rail.colors = SidebarColors(palette)
        // Light themes: Arc's switch is the folder's shaded dark with a tinted-light knob.
        list.switchTint = palette.isDark ? NSColor.white.withAlphaComponent(0.85) : NSColor(palette.folderTint)
        list.switchKnob = palette.isDark ? NSColor(white: 0.15, alpha: 1) : NSColor(palette.folderFill)
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
    /// Arc's "Show media" folders, on a right-click of the Media button.
    var pageMenu: (LibraryPage) -> NSMenu? = { _ in nil }
    var onBack: () -> Void = {}
    var colors = SidebarColors() { didSet { refresh() } }
    /// The selected page's glyph: the space's accent pair, not the Mac's accent colour (Arc).
    var accent: (fill: NSColor, ink: NSColor) = (.controlAccentColor, .white) { didSet { refresh() } }
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
            b.menuProvider = { [weak self] in self?.pageMenu(p) }
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
        for b in buttons { b.show(selected: b.page == page, ink: ink, accent: accent) }
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
    var menuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?() }
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

    private var accent: (fill: NSColor, ink: NSColor) = (.controlAccentColor, .white)

    func show(selected: Bool, ink: NSColor, accent: (fill: NSColor, ink: NSColor)) {
        self.selected = selected
        self.ink = ink
        self.accent = accent
        refresh()
    }

    private func refresh() {
        let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        if selected {
            // The filled glyph in palette mode: the space's dark mark on its light tint (Arc 1.172.1).
            glyph.image = NSImage(systemSymbolName: page.selectedSymbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(config.applying(.init(paletteColors: [accent.ink, accent.fill])))
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
        case media([MediaLibrary.File])
        case easels([EaselEntry])
        case boost(Boost)
        case download(DownloadHistory.Listed)
        case archived(ArchivedItem)
    }

    private let store: SidebarStore
    private let actions: SidebarActions
    private let favicons: FaviconCache
    var onEscape: () -> Void = {}
    var page: LibraryPage { didSet { if page != oldValue { field.stringValue = ""; query = ""; field.placeholderString = page.searchPrompt; if filtering { filtering = false }; reload(); needsLayout = true } } }
    var colors = SidebarColors() { didSet { if colors != oldValue { refresh(); table.reloadData() } } }
    /// A boost's switch (Arc: the theme's dark shade, a light knob).
    var switchTint = NSColor.controlAccentColor
    var switchKnob = NSColor.white
    private var query = ""
    private var rows: [Row] = []
    private var mediaHiddenObserver: NSObjectProtocol?
    /// The width the grid rows were last sized for.
    private var gridWidth: CGFloat = 0
    private let searchBox = NSView()
    private let searchGlyph = NSImageView()
    private let field = NSTextField()
    private let menuButton = NSView()
    private let menuGlyph = NSImageView()
    private let filterLabel = NSTextField.sidebarLabel(size: 14, weight: .medium)
    private let scroll = SidebarListScrollView()
    private let table = LibraryTable()
    private let empty = LibraryEmptyView()
    private var mediaCard: NSHostingView<MediaOptInCard>?

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
        // Arc's Filter button: a line.3 circle and "Filter", 73 × 36 pt.
        menuGlyph.image = SidebarSymbols.image("line.3.horizontal.decrease.circle", size: 14, weight: .medium)
        menuGlyph.imageScaling = .scaleNone
        menuGlyph.frame = NSRect(x: 9, y: 0, width: 18, height: 36)
        menuButton.addSubview(menuGlyph)
        filterLabel.font = .systemFont(ofSize: 14, weight: .medium)
        filterLabel.stringValue = "Filter"
        menuButton.addSubview(filterLabel)
        menuButton.setAccessibilityElement(true)
        menuButton.setAccessibilityRole(.button)
        menuButton.setAccessibilityLabel("Filter")
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
            _ = DownloadHistory.shared.live
            _ = DownloadHistory.shared.thumbnails.count
            _ = MediaScanner.shared.files
            _ = BoostStore.shared.boosts
            _ = store.settings.mediaLibraryEnabled
            _ = store.settings.mediaFolders
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        reload()
    }

    private var needle: String { query.lowercased().trimmingCharacters(in: .whitespaces) }

    private func reload() {
        var out: [Row] = []
        mediaCard?.isHidden = true
        switch page {
        case .media:
            guard store.settings.mediaLibraryEnabled else {
                showMediaCard()
                empty.show(symbol: "photo.on.rectangle", title: "", detail: nil)
                break
            }
            // Read again whenever the page shows, a search changes or the folders change; the scan is
            // cheap, off the main thread, and reads only the folders ticked.
            MediaScanner.shared.rescan(store.settings.mediaFolders)
            if mediaHiddenObserver == nil {
                mediaHiddenObserver = NotificationCenter.default.addObserver(forName: MediaPreviewController.hidden, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { if self?.page == .media { self?.reload() } }
                }
            }
            let all = MediaScanner.shared.files
            let shown = MediaLibrary.shown(all, query: query, hidden: Set(store.settings.mediaHidden))
            out = MediaLibrary.rows(shown).map { .media($0) }
            empty.show(symbol: "photo.on.rectangle", title: all.isEmpty ? "Nothing here yet!" : "No matches",
                       detail: all.isEmpty ? "Screenshots, pictures and videos in the folders you show appear here." : nil)
        case .downloads:
            // Running, failed and cancelled downloads too, as in the tray (#245).
            let all = DownloadHistory.shared.library(query: "")
            let shown = (needle.isEmpty ? all : DownloadHistory.shared.library(query: query)).filter {
                guard case .finished(let e) = $0 else { return downloadFilter.isEmpty }
                return downloadFilter.shows(profile: e.profile ?? "Default")
            }
            for (label, entries) in Self.grouped(shown, date: \.date) {
                out.append(.header(label))
                out += entries.map { .download($0) }
            }
            // Arc's words.
            empty.show(symbol: "arrow.down.circle", title: all.isEmpty ? "Nothing here yet!" : "No matches",
                       detail: all.isEmpty ? "Come back after you’ve found some cool stuff to save." : nil)
        case .easels:
            let all = EaselFiles.all()
            let shown = needle.isEmpty ? all : all.filter { $0.title.lowercased().contains(needle) }
            // Arc: one grid, newest edit first, two to a row, no day headers.
            let entries = shown.map { EaselEntry(id: $0.id, title: $0.title, edited: $0.edited) }
            out = stride(from: 0, to: entries.count, by: 2).map { .easels(Array(entries[$0..<min($0 + 2, entries.count)])) }
            // Arc's empty Easels page: "Out of ideas!"
            empty.show(symbol: "pencil.and.scribble", title: all.isEmpty ? "Out of ideas!" : "No matches",
                       detail: all.isEmpty ? "Choose File ▸ New Easel to create a new Easel." : nil)
        case .boosts:
            let all = BoostStore.shared.boosts
            let shown = needle.isEmpty ? all : all.filter { $0.name.lowercased().contains(needle) || $0.host.contains(needle) }
            out = shown.sorted { $0.host < $1.host }.map { .boost($0) }
            // Arc's empty Boosts page.
            empty.show(symbol: "paintbrush.pointed", title: all.isEmpty ? "Nothing Boosted Yet!" : "No matches",
                       detail: all.isEmpty ? "Type “New Boost” in the command bar on any site to make your own." : nil)
        case .spaces:
            break
        case .archive:
            let filter = archiveFilter
            let shown = (needle.isEmpty ? store.archive : store.archive.filter {
                $0.item.displayTitle.lowercased().contains(needle) || ($0.item.tab?.url.lowercased().contains(needle) ?? false)
            }).filter(filter.shows)
            for (label, entries) in Self.grouped(shown, date: \.archivedAt) {
                out.append(.header(label))
                out += entries.map { .archived($0) }
            }
            empty.show(symbol: "archivebox", title: store.archive.isEmpty ? "Nothing here yet!" : "No matches",
                       detail: store.archive.isEmpty ? "Tabs you close end up here." : nil)
        }
        rows = out
        needsLayout = true
        empty.isHidden = !out.isEmpty || (page == .media && !store.settings.mediaLibraryEnabled)
        scroll.isHidden = out.isEmpty
        table.reloadData()
        refresh()
    }

    private func refresh() {
        let ink: NSColor = colors.isDark ? .white : .black
        searchBox.layer?.backgroundColor = ink.withAlphaComponent(0.08).cgColor
        searchGlyph.contentTintColor = ink.withAlphaComponent(0.5)
        field.textColor = colors.textPrimary
        // Picked chips show on the button: Arc's dark pill.
        menuButton.layer?.backgroundColor = (filterActive ? ink.withAlphaComponent(colors.isDark ? 0.85 : 0.68) : ink.withAlphaComponent(0.08)).cgColor
        let label = filterActive ? (colors.isDark ? NSColor.black : NSColor.white) : ink.withAlphaComponent(0.7)
        menuGlyph.contentTintColor = label
        filterLabel.textColor = label
        empty.ink = ink
    }

    /// Arc's opt-in card, over the page until Show Media is pressed.
    private func showMediaCard() {
        let card = MediaOptInCard(dark: colors.isDark) { [store] in store.settings.mediaLibraryEnabled = true }
        if let mediaCard { mediaCard.rootView = card } else {
            let host = NSHostingView(rootView: card)
            addSubview(host)
            mediaCard = host
        }
        mediaCard?.isHidden = false
        needsLayout = true
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
        // HStack(spacing: 4) 10 pt down, 7 pt in, 8 pt from the right: the field, the ⋯ button
        // (Media and Boosts: the field alone, as in Arc).
        let w = bounds.width
        menuButton.isHidden = !hasFilter || filtering
        searchBox.isHidden = filtering
        let fw: CGFloat = 73
        searchBox.frame = NSRect(x: 7, y: 10, width: max(0, w - 7 - 8 - (hasFilter ? 7 + fw : 0)), height: 36)
        menuButton.frame = NSRect(x: w - 8 - fw, y: 10, width: fw, height: 36)
        filterLabel.frame = NSRect(x: 31, y: (36 - 18) / 2, width: fw - 33, height: 18)
        let gw = searchGlyph.image?.size.width ?? 14
        searchGlyph.frame = NSRect(x: 12, y: 0, width: gw, height: 36)
        let fh = ceil(field.intrinsicContentSize.height)
        let fx = 12 + gw + 10
        field.frame = NSRect(x: fx - SidebarText.inset, y: (36 - fh) / 2, width: max(0, searchBox.bounds.width - fx - 12) + 2 * SidebarText.inset, height: fh)
        // Arc leaves room between the search and the first item (Arc 1.172.1, 8 Nov 2026, 2x stills):
        // 10.5 pt to a boost's card, 15 pt to the first media tile's; a day header brings its own.
        let gap: CGFloat
        switch rows.first {
        case .media?, .easels?: gap = 15
        case .header?, nil: gap = 0
        default: gap = 10
        }
        var top: CGFloat = 46
        if let host = filterHost {
            if host.rootView.width != w { host.rootView = filterPanel() }
            let h = host.fittingSize.height
            host.frame = NSRect(x: 0, y: 0, width: w, height: h)
            top = h + 4
        }
        scroll.frame = NSRect(x: 0, y: top + gap, width: w, height: max(0, bounds.height - top - gap))
        table.tableColumns.first?.width = w
        if w != gridWidth {
            gridWidth = w
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<rows.count))
        }
        empty.frame = scroll.frame
        if let card = mediaCard {
            let size = card.fittingSize
            card.frame = NSRect(x: ((w - size.width) / 2).rounded(), y: max(56, ((bounds.height - size.height) / 2).rounded()),
                                width: size.width, height: size.height)
        }
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

    /// Arc's "Show media" folders (its Library button's right-click menu; Cra's Media button).
    static func mediaFoldersMenu(_ store: SidebarStore) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: "Show media", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for f in MediaLibrary.Folder.allCases {
            let on = store.settings.mediaFolders.contains(f)
            MenuItems.add(menu, f.title, on: on) {
                if on { store.settings.mediaFolders.removeAll { $0 == f } } else { store.settings.mediaFolders.append(f) }
            }
        }
        if store.settings.mediaLibraryEnabled {
            menu.addItem(.separator())
            MenuItems.add(menu, "Hide Media") { store.settings.mediaLibraryEnabled = false }
        }
        return menu
    }

    /// A rail button's right-click: Media's folders (Arc's Library button menu), and what Cra's ⋯
    /// held before Arc's Filter took its place (Open Downloads Folder, Clear Archive).
    static func pageMenu(_ page: LibraryPage, store: SidebarStore, profile: String?) -> NSMenu? {
        switch page {
        case .media: return mediaFoldersMenu(store)
        case .downloads:
            let m = NSMenu()
            MenuItems.add(m, "Open Downloads Folder") {
                NSWorkspace.shared.open(DownloadDestinations.folder(profileID: DownloadDestinations.profileID(profilePath: profile)))
            }
            return m
        case .archive:
            let m = NSMenu()
            m.autoenablesItems = false
            MenuItems.add(m, "Clear Archive", enabled: !store.archive.isEmpty) { store.clearArchive() }
            return m
        default: return nil
        }
    }

    // MARK: Filter (Arc's, on Archived Tabs and Downloads)

    private var archiveFilter = ArchiveFilter()
    private var downloadFilter = DownloadFilter()
    private var filtering = false { didSet { showFilterPanel() } }
    private var filterHost: NSHostingView<LibraryFilterPanel>?

    private var hasFilter: Bool { page == .archive || page == .downloads }
    private var filterActive: Bool { page == .archive ? !archiveFilter.isEmpty : page == .downloads ? !downloadFilter.isEmpty : false }

    private func filterPanel() -> LibraryFilterPanel {
        typealias Chip = LibraryFilterPanel.Chip
        var sections: [LibraryFilterPanel.Section] = []
        if page == .archive {
            let f = archiveFilter
            sections.append(.init(title: "How was the tab closed?", chips: [
                Chip(id: "auto", label: "Auto-Closed", on: f.closed.contains(.auto)),
                Chip(id: "manual", label: "Manually Closed", on: f.closed.contains(.manual)),
            ]))
            var places = [Chip(id: "little", label: "Little Window", on: f.places.contains(.littleWindow))]
            for id in store.spaceOrder {
                guard let sp = store.space(id) else { continue }
                places.append(Chip(id: "space:" + id.uuidString, label: sp.title, icon: sp.emoji.isEmpty ? nil : sp.emoji,
                                   on: f.places.contains(.space(id))))
            }
            sections.append(.init(title: "Where was the tab?", chips: places))
        } else {
            var chips = [Chip(id: "Default", label: "Default", on: downloadFilter.profiles.contains("Default"))]
            for p in store.profiles { chips.append(Chip(id: p.directoryName, label: p.name, on: downloadFilter.profiles.contains(p.directoryName))) }
            sections.append(.init(title: "Profiles", chips: chips))
        }
        return LibraryFilterPanel(title: page == .archive ? "Filter Archived Tabs" : "Filter Downloads…", sections: sections, width: max(200, bounds.width),
                                  dark: colors.isDark, toggle: { [weak self] id in self?.toggleChip(id) },
                                  done: { [weak self] in self?.filtering = false })
    }

    private func toggleChip(_ id: String) {
        func flip<T: Hashable>(_ set: inout Set<T>, _ v: T) { if set.contains(v) { set.remove(v) } else { set.insert(v) } }
        if page == .archive {
            switch id {
            case "auto": flip(&archiveFilter.closed, .auto)
            case "manual": flip(&archiveFilter.closed, .manual)
            case "little": flip(&archiveFilter.places, .littleWindow)
            default: if let u = UUID(uuidString: String(id.dropFirst(6))) { flip(&archiveFilter.places, .space(u)) }
            }
        } else {
            flip(&downloadFilter.profiles, id)
        }
        filterHost?.rootView = filterPanel()
        reload()
    }

    private func showFilterPanel() {
        if filtering, hasFilter {
            let host = filterHost ?? NSHostingView(rootView: filterPanel())
            // The window's title bar is no inset here: the panel takes the search row's place.
            host.safeAreaRegions = []
            host.rootView = filterPanel()
            if filterHost == nil { addSubview(host); filterHost = host }
        } else {
            filterHost?.removeFromSuperview()
            filterHost = nil
            window?.makeFirstResponder(field)
        }
        searchBox.isHidden = filtering
        menuButton.isHidden = filtering || !hasFilter
        refresh()
        needsLayout = true
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard hasFilter, !filtering, menuButton.frame.contains(p) else { return super.mouseDown(with: event) }
        filtering = true
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if case .header = rows[row] { return 40 }
        // The list's own width: the table may not have its width yet when this is first asked.
        if case .media = rows[row] { return MediaGridMetrics.rowHeight(width: bounds.width) }
        if case .easels = rows[row] { return MediaGridMetrics.rowHeight(width: bounds.width) }
        return 56
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        switch rows[row] {
        case .header(let label):
            let v = tableView.makeView(withIdentifier: .init("header"), owner: nil) as? LibraryHeaderCell ?? LibraryHeaderCell()
            v.identifier = .init("header")
            v.show(label, ink: colors.isDark ? .white : .black)
            return v
        case .boost(let b):
            let v = tableView.makeView(withIdentifier: .init("boost"), owner: nil) as? BoostRowCell ?? BoostRowCell()
            v.identifier = .init("boost")
            v.show(b, icon: boostIcon(b), ink: colors.isDark ? .white : .black,
                   hoverFill: colors.hoverFill, tint: switchTint, knob: switchKnob)
            v.open = { [store, actions] in
                // Opens the site, where the boost shows.
                _ = store.createTab(url: "https://\(b.host)/", select: true)
                actions.closeLibrary()
            }
            return v
        case .easels(let entries):
            let v = tableView.makeView(withIdentifier: .init("easels"), owner: nil) as? EaselRowCell ?? EaselRowCell()
            v.identifier = .init("easels")
            v.open = { [weak self] e in
                // Arc opens an easel picked here in Peek (its ⤢ makes it a tab); the Library stays.
                guard let self, let main = self.window?.windowController as? MainWindowController,
                      let app = NSApp.delegate as? AppDelegate else { return }
                app.openPeek(url: Easel(id: e.id).url, over: main)
                CraLog.note("easel opens in Peek")
            }
            v.delete = { [weak self] e in self?.deleteEasel(e) }
            v.show(entries, ink: colors.isDark ? .white : .black)
            return v
        case .media(let files):
            let v = tableView.makeView(withIdentifier: .init("media"), owner: nil) as? MediaRowCell ?? MediaRowCell()
            v.identifier = .init("media")
            v.open = { [weak self, weak v] file, thumbnail in
                // Arc previews the pick over the dimmed window; the Library and the space stay as they were.
                guard let self, let window = v?.window else { return }
                let files = self.rows.flatMap { row -> [MediaLibrary.File] in if case .media(let f) = row { return f } else { return [] } }
                MediaPreviewController.shared.show(files, at: files.firstIndex(of: file) ?? 0, from: thumbnail, over: window)
            }
            v.fileMenu = { [weak self, store] file in MediaMenu.make(for: file, store: store) { if $0 == .hide { self?.reload() } } }
            v.show(files, ink: colors.isDark ? .white : .black)
            return v
        case .download(let e):
            let v = tableView.makeView(withIdentifier: .init("item"), owner: nil) as? LibraryItemCell ?? LibraryItemCell()
            v.identifier = .init("item")
            v.showDownload(e, colors: colors)
            return v
        case .archived(let e):
            let v = tableView.makeView(withIdentifier: .init("item"), owner: nil) as? LibraryItemCell ?? LibraryItemCell()
            v.identifier = .init("item")
            v.showArchived(e, icon: favicons.image(forKey: e.item.tab?.faviconKey), colors: colors,
                           restore: { [actions] in actions.restoreArchived(e.id) },
                           remove: { [store] in store.removeFromArchive(e.id) })
            return v
        }
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { false }

    /// Library ▸ Easels ▸ Delete: asked first (its drawing and pictures go), its tabs close.
    private func deleteEasel(_ e: EaselEntry) {
        guard let window = window ?? AppDialog.parentWindow else { return }
        let dialog = AppDialog.easelDeletion()
        dialog.present(over: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            let url = Easel(id: e.id).url
            EaselFiles.deleted.insert(e.id)
            for tab in self.store.allTabs() where tab.tab?.url == url { self.actions.closeTab(tab.id) }
            EaselFiles.delete(e.id)
            CraLog.note("easel deleted")
            self.reload()
        }
    }

    /// The boost's site icon: the site's own, else that of a tab on it (icons are kept per page).
    private func boostIcon(_ b: Boost) -> NSImage? {
        if let i = favicons.image(for: "https://\(b.host)/") { return i }
        let key = store.allTabs().lazy.compactMap { $0.tab }.first { t in
            guard let host = URL(string: t.url)?.host?.lowercased() else { return false }
            return host == b.host || host.hasSuffix("." + b.host)
        }?.faviconKey
        if let i = favicons.image(forKey: key) { return i }
        // Never shown in a tab here: fetch the site's own icon, then draw the row again.
        SiteIconLoader.shared.load(host: b.host, into: favicons) { [weak self] in self?.table.reloadData() }
        return nil
    }
}

extension LibraryListView: NSMenuDelegate {
    /// The row's context menu, built for the row under the pointer.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let row = table.menuRow
        guard rows.indices.contains(row) else { return }
        switch rows[row] {
        case .header, .media, .easels: break
        case .boost(let b):
            // Arc 1.172.1: Rename (in place) and Delete.
            let cell = table.view(atColumn: 0, row: row, makeIfNecessary: false) as? BoostRowCell
            MenuItems.add(menu, "Rename") { cell?.beginRename() }
            MenuItems.add(menu, "Delete") { BoostStore.shared.delete(b.id) }
        case .archived(let e):
            let actions = actions, store = store
            MenuItems.add(menu, "Restore") { actions.restoreArchived(e.id) }
            MenuItems.add(menu, "Copy Link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(e.item.tab?.url ?? "", forType: .string)
            }
            menu.addItem(.separator())
            MenuItems.add(menu, "Remove from Archive") { store.removeFromArchive(e.id) }
        case .download(let d):
            // Arc's Download Context Menu, the tray's too (#272).
            DownloadRowMenu.fill(menu, for: d)
        }
    }
}

/// Arc draws no ring round the row a right-click is on: the table hands out the row's menu itself
/// (NSTableView's own path outlines the clicked row).
private final class LibraryTable: NSTableView {
    private(set) var menuRow = -1
    override func menu(for event: NSEvent) -> NSMenu? {
        menuRow = row(at: convert(event.locationInWindow, from: nil))
        guard let m = menu else { return nil }
        m.delegate?.menuNeedsUpdate?(m)
        return m.items.isEmpty ? nil : m
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
    /// A finished download's file: opened by a click, dragged out.
    private var download: DownloadHistory.Entry?
    private var isDownloadRow = false
    private var restore: (() -> Void)?
    /// An archived tab's hover buttons (Arc 1.172.1): the bin removes it from the archive, the
    /// curved arrow brings it back.
    private var remove: (() -> Void)?
    private let binButton = NSImageView()
    private let restoreButton = NSImageView()
    private var downAt: NSPoint?
    private var hovering = false { didSet { if hovering != oldValue { refreshHover(); needsLayout = true } } }

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
        for (b, symbol, label) in [(binButton, "trash", "Delete"), (restoreButton, "arrow.uturn.backward", "Restore")] {
            b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
            b.imageScaling = .scaleNone
            b.isHidden = true
            b.setAccessibilityElement(true)
            b.setAccessibilityRole(.button)
            b.setAccessibilityLabel(label)
            card.addSubview(b)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func showArchived(_ e: ArchivedItem, icon image: NSImage?, colors: SidebarColors, restore: @escaping () -> Void, remove: @escaping () -> Void) {
        self.colors = colors
        download = nil
        isDownloadRow = false
        self.restore = restore
        self.remove = remove
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

    /// A download on Library ▸ Downloads: a finished file (thumbnail, name, age) or one still
    /// running, failed or cancelled (its type's icon, name, progress or what went wrong; #245).
    func showDownload(_ listed: DownloadHistory.Listed, colors: SidebarColors) {
        self.colors = colors
        isDownloadRow = true
        restore = nil
        remove = nil
        let ink: NSColor = colors.isDark ? .white : .black
        icon.isHidden = true
        let image: NSImage?
        switch listed {
        case .finished(let e):
            download = e
            image = DownloadHistory.shared.thumbnail(for: e.path)
            detail.stringValue = Self.age.localizedString(for: min(e.date, Date()), relativeTo: Date())
        case .live(let l):
            download = nil
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: (l.name as NSString).pathExtension) ?? .data)
            detail.stringValue = DownloadRow.subtitle(l.row, now: Date())
        }
        if let image {
            var rect = NSRect(x: 0, y: 0, width: 32, height: 32)
            let scale = window?.backingScaleFactor ?? 2
            tile.layer?.contents = image.cgImage(forProposedRect: &rect, context: nil, hints: [.ctm: AffineTransform(scale: scale)])
            tile.layer?.contentsScale = scale
            tile.layer?.backgroundColor = nil
        } else {
            tile.layer?.contents = nil
            tile.layer?.backgroundColor = ink.withAlphaComponent(0.04).cgColor
        }
        title.stringValue = listed.name
        title.lineBreakMode = .byTruncatingMiddle
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
        let isDownload = isDownloadRow
        let t: CGFloat = isDownload ? 32 : 24
        let x: CGFloat = isDownload ? 5 : 9
        tile.frame = NSRect(x: x, y: (h - t) / 2, width: t, height: t)
        icon.frame = NSRect(x: (t - 16) / 2, y: (t - 16) / 2, width: 16, height: 16)
        // Arc's archived row on hover: the bin and the restore arrow 34 pt apart, 14 pt from the right.
        let showsButtons = hovering && remove != nil && !isDownloadRow
        binButton.isHidden = !showsButtons
        restoreButton.isHidden = !showsButtons
        let ink: NSColor = colors.isDark ? .white : .black
        binButton.contentTintColor = ink.withAlphaComponent(0.6)
        restoreButton.contentTintColor = ink.withAlphaComponent(0.6)
        restoreButton.frame = NSRect(x: card.bounds.width - 14 - 24, y: (h - 24) / 2, width: 24, height: 24)
        binButton.frame = restoreButton.frame.offsetBy(dx: -34, dy: 0)
        // HStack(spacing: 10) ends in a Spacer, so the text stops 10 + 8 pt short of the edge.
        let tx = x + t + 10, tw = max(0, (showsButtons ? binButton.frame.minX - 8 : card.bounds.width - 18) - tx)
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
        let p = card.convert(event.locationInWindow, from: nil)
        if !binButton.isHidden, binButton.frame.insetBy(dx: -4, dy: -4).contains(p) { remove?(); return }
        if let download { NSWorkspace.shared.open(URL(fileURLWithPath: download.path)) } else if !isDownloadRow { restore?() }
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
