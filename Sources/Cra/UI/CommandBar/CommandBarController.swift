import AppKit
import Observation
import SwiftUI

/// State + behaviour of the ⌘T / ⌘L bar. The panel and SwiftUI view read
/// from here; MainWindowController owns commits.
@MainActor
@Observable
final class CommandBarController {
    var isOpen = false
    var mode: CommandBarMode = .newTab
    var query = ""
    var result = SuggestionResult()
    var selectedIndex = 0
    /// Text pushed into the field from outside (prefill); bump version to apply.
    var fieldText = ""
    var fieldTextVersion = 0
    /// Pushed text arrives selected (a prefill); false puts the caret after it.
    var fieldTextSelected = true
    var allowCompletion = true
    /// Text shown in the field while arrowing through rows (Chrome/Arc fill the
    /// field with the selected row); nil shows what was typed. Bump version to apply.
    var previewText: String?
    var previewVersion = 0
    /// Layout hints set by the window controller before opening.
    var panelWidth: CGFloat = CraMetrics.commandBarWidth
    var attached = false
    /// Arc's address panel (#663): opened by a click on the sidebar's address, it hangs from that
    /// field, sized to the address (CraCore SidebarAddressPanel), not centred in the window.
    var compact = false
    /// Arc's ⌘L on a page with the developer bar (#663 follow-up): the bar's address edited in place, the panel over the
    /// bar and across the card (CraCore DeveloperBarPanel). nil for every other bar.
    var developer: CommandBarDeveloperInput?
    /// The space whose palette colours the selected row and the info badge (CraCore CommandBarTones).
    var theme: SpaceTheme?
    var focusedSpaceID: UUID?
    /// The space "Switch to" leaves out when it isn't the focused one: a Little Window's (#316).
    var spaceShown: UUID?
    /// The window the bar belongs to. A Little Window's lists open tabs and archived pages as pages
    /// to load in it, not tabs to switch to in the browser window (CraCore LittleBarRows, #599).
    var window: CommandBarOpening.Window = .browser
    var spaceName: (UUID) -> String = { _ in "" }
    /// Arc's scoped search: Tab on "youtube" scopes the bar to YouTube, on "%" to the space's open
    /// tabs, on the empty field to the browser's actions (a pill before the field) until Backspace
    /// on an empty field or Escape.
    private(set) var scope: CommandBarScope?
    /// Settings ▸ Advanced ▸ Command bar (#457, not in Arc): a site search fills the bar with the
    /// site's colour (CraCore ScopedSearchFill).
    var fillsSiteScope: Bool { store.settings.commandBarSiteColor }
    /// What was typed when Tab entered the scope; Backspace puts it back.
    private var scopeTyped = ""
    /// The URL ⌘L opened with (the page's), nil for ⌘T.
    private(set) var openedPrefill: String?
    /// Rows that open or change under a still pointer don't take the selection from the top row (#382).
    @ObservationIgnored private var hoverGate = HoverGate()
    @ObservationIgnored private var searchEngineWatcher: DispatchSourceFileSystemObject?

    unowned let engine: SuggestionEngine
    unowned let store: SidebarStore
    var onCommit: (Suggestion?, String, CommandBarMode) -> Void = { _, _, _ in }
    /// Opens the row in a background tab; false when it has no page to open there.
    var onOpenInBackground: (Suggestion?, String) -> Bool = { _, _ in false }
    /// Opens the row as a split pane beside the current tab; false when it can't go there.
    var onOpenInSplit: (Suggestion?, String) -> Bool = { _, _ in false }
    /// Shift-Return on a search (Instant Links, #407): the phrase and the engine the bar searched with.
    /// Nil where the host has no space to open results in (a Little Window).
    var onInstantLinks: ((String, ChromiumSearchEngine) -> Void)?
    var onClose: () -> Void = {}
    /// Arc's search-suggestions notice (CraCore SearchSuggestionsNotice, #314): the (i) at the field's end
    /// opens a banner in the bottom row's place for this ⌘T.
    private(set) var noticePressed = false
    /// The banner's Search Settings… and its "here" (Cra's privacy page).
    var onNoticeSettings: () -> Void = {}
    var onNoticeLearnMore: () -> Void = {}

    init(engine: SuggestionEngine, store: SidebarStore) {
        self.engine = engine
        self.store = store
    }

    var placeholder: String {
        if scope != nil { return "Search…" }
        switch mode {
        case .newTab: return "Search or Enter URL…"
        case .editURL: return "Edit URL or search…"
        }
    }

    func open(mode: CommandBarMode, prefill: String?) {
        engine.resetIndex()
        // Its keys are built off the main thread while the bar comes up (#617).
        engine.prepareIndex()
        searchEngineWatcher?.cancel()
        searchEngineWatcher = engine.watchSearchEngines { [weak self] in self?.relist() }
        self.mode = mode
        scope = nil
        openedPrefill = prefill
        query = prefill ?? ""
        fieldText = query
        fieldTextSelected = true
        fieldTextVersion += 1
        allowCompletion = false
        selectedIndex = 0
        previewText = nil
        noticePressed = false
        result = listed(engine.suggestions(for: query, mode: mode, currentTabID: store.selectedTabID, spaceShown: spaceShown, folderSpace: window == .browser ? focusedSpaceID : nil))
        isOpen = true
        if onInstantLinks != nil { InstantLinksService.shared.prewarm(store) }
    }

    /// The window's space changed under the open bar: its tab list follows, as Arc's does (#721).
    /// "Only this space's tabs" and the other-space labels both read the space when the bar lists.
    func follow(space: UUID) {
        guard isOpen, focusedSpaceID != space else { return }
        focusedSpaceID = space
        engine.spaceChanged()
        if scope == .tabs { update(query: query, allowCompletion: allowCompletion) } else { relist() }
    }

    /// Replace the typed text (scripting / tests).
    func setQuery(_ text: String) {
        fieldText = text
        fieldTextSelected = true
        fieldTextVersion += 1
        update(query: text, allowCompletion: true)
    }

    func update(query newQuery: String, allowCompletion: Bool) {
        query = newQuery
        self.allowCompletion = allowCompletion
        if let scope {
            switch scope {
            case .site(let site):
                result = listed(engine.suggestions(for: newQuery, in: site))
            case .tabs:
                result = listed(engine.suggestions(for: newQuery, inTabsOf: focusedSpaceID ?? store.focusedSpaceID, currentTabID: store.selectedTabID))
            case .actions:
                result = listed(engine.suggestions(forActionsMatching: newQuery, currentTabID: store.selectedTabID, spaceShown: spaceShown))
            }
            selectedIndex = 0
            previewText = nil
            return
        }
        // Asked first: while the answer loads, the previous one keeps its rows.
        let typed = newQuery
        engine.fetchSearchSuggestions(for: typed) { [weak self] in
            guard let self, self.isOpen, self.query == typed else { return }
            self.relist()
        }
        engine.fetchHistory(for: typed, spaceShown: spaceShown) { [weak self] in
            guard let self, self.isOpen, self.query == typed else { return }
            self.relist()
        }
        result = listed(engine.suggestions(for: newQuery, mode: mode, currentTabID: store.selectedTabID, spaceShown: spaceShown, folderSpace: window == .browser ? focusedSpaceID : nil))
        if !allowCompletion { result.inlineCompletion = nil }
        selectedIndex = 0
        previewText = nil
    }

    /// Search suggestions or engines changed: list again, keeping the selected row where it still is.
    private func relist() {
        guard scope == nil else { return }
        let selectedID = result.items.indices.contains(selectedIndex) ? result.items[selectedIndex].id : nil
        result = listed(engine.suggestions(for: query, mode: mode, currentTabID: store.selectedTabID, spaceShown: spaceShown, folderSpace: window == .browser ? focusedSpaceID : nil))
        if !allowCompletion { result.inlineCompletion = nil }
        if let i = result.items.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = i
        } else {
            selectedIndex = 0
            if previewText != nil {
                previewText = nil
                previewVersion += 1
            }
        }
    }

    func moveSelection(by delta: Int) {
        guard !result.items.isEmpty else { return }
        let n = result.items.count
        selectedIndex = ((selectedIndex + delta) % n + n) % n
        // The top row is what was typed (plus its inline completion).
        previewText = selectedIndex == 0 ? nil : fillText(for: result.items[selectedIndex])
        previewVersion += 1
    }

    /// What the field shows for a selected row: the address for pages, the
    /// query for searches, the name for commands.
    private func fillText(for s: Suggestion) -> String {
        if s.id == "typed" { return query }
        switch s.kind {
        case .search, .command, .switchSpace, .moveToSpace, .moveToFolder, .revealFolder:
            return s.title
        case .switchToTab, .archived, .history, .navigate, .topDomain:
            guard let url = s.url else { return s.title }
            var t = url
            for p in ["https://www.", "http://www.", "https://", "http://"] where t.hasPrefix(p) { t = String(t.dropFirst(p.count)); break }
            if t.hasSuffix("/") { t.removeLast() }
            return t
        }
    }

    /// Tab on text that starts a site search's host, on "%", or on the empty field: scope the bar to it.
    func enterScope() -> Bool {
        guard scope == nil, previewText == nil, let offered = result.scope else { return false }
        scopeTyped = query
        scope = offered
        pushFieldText("")
        return true
    }

    /// Backspace on the empty scoped field: back to what was typed, the hint showing again.
    func leaveScope() {
        guard scope != nil else { return }
        scope = nil
        pushFieldText(scopeTyped)
    }

    /// Escape in a scope goes back to how the bar opened rather than closing it (Arc).
    func cancelScope() {
        guard scope != nil else { return }
        open(mode: mode, prefill: openedPrefill)
    }

    private func pushFieldText(_ text: String) {
        fieldText = text
        fieldTextSelected = false
        fieldTextVersion += 1
        update(query: text, allowCompletion: false)
    }

    /// Accept the inline completion (Tab / →).
    func acceptCompletion() -> Bool {
        guard let c = result.inlineCompletion else { return false }
        fieldText = c
        fieldTextSelected = true
        fieldTextVersion += 1
        update(query: c, allowCompletion: false)
        return true
    }

    func commit() {
        guard let (selected, typed) = committed() else { return }
        close()
        onCommit(selected, typed, mode)
    }

    /// Shift-Return (Instant Links): on a search row, with the feature on and Apple Intelligence able,
    /// the bar closes and the model plans what was typed. Anything else is Return.
    func commitInstantLinks() {
        guard let (selected, typed) = committed() else { return }
        if let onInstantLinks, InstantLinksService.shared.isAvailable(store), let phrase = instantLinksPhrase(selected) {
            // Before close(): the row needs to know whether the New Tab row is the open one.
            onInstantLinks(phrase, engine.searchEngine)
            close()
            return
        }
        close()
        onCommit(selected, typed, mode)
    }

    /// What Shift-Return searches: what was typed (never the inline completion Return would take), or a
    /// search suggestion's text; nil for any other row.
    private func instantLinksPhrase(_ selected: Suggestion?) -> String? {
        guard scope == nil else { return nil }
        let text: String
        if let selected {
            guard selected.kind == .search else { return nil }
            text = selected.id == "typed" ? query : selected.title
        } else {
            guard !SuggestionEngine.looksLikeURL(query) else { return nil }
            text = query
        }
        let phrase = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return phrase.isEmpty ? nil : phrase
    }

    /// ⌘Return (Arc): the row's page opens in a new background tab and the bar stays open with
    /// what was typed, so the next ⌘Return opens another. Rows that open no page, and hosts with
    /// no tabs to open (a Little Window), take it as Return.
    func commitInBackground() {
        guard let (selected, typed) = committed() else { return }
        if onOpenInBackground(selected, typed) { return }
        close()
        onCommit(selected, typed, mode)
    }

    /// ⌥Return: the row opens in Split View with the current tab. Rows that open no page, and
    /// hosts with no split to make (a Little Window, an empty tab), take it as Return.
    func commitInSplit() {
        guard let (selected, typed) = committed() else { return }
        close()
        if !onOpenInSplit(selected, typed) { onCommit(selected, typed, mode) }
    }

    private func committed() -> (Suggestion?, String)? {
        let selected = result.items.indices.contains(selectedIndex) ? result.items[selectedIndex] : nil
        // No tab or action matched: Return has nowhere to go, and neither scope searches the web.
        if scope == .tabs || scope == .actions, selected == nil { return nil }
        var typed = query
        // Enter on the typed row with an inline completion goes to the completion.
        if selectedIndex == 0, let c = result.inlineCompletion, selected?.id == "typed" { typed = c }
        return (selected, typed)
    }

    func commit(_ suggestion: Suggestion) {
        close()
        onCommit(suggestion, query, mode)
    }

    private var suggestionsOn: Bool { store.settings.searchSuggestions }
    private var noticeDismissed: Bool { store.prefs.searchSuggestionsNoticeDismissed }

    var showsNoticeBadge: Bool {
        let offersSite = scope == nil && previewText == nil && result.scope != nil && result.scope != .actions
        return SearchSuggestionsNotice.showsBadge(suggestionsOn: suggestionsOn, dismissed: noticeDismissed, bannerShown: noticePressed,
                                                  scoped: scope != nil, offersSite: offersSite)
    }

    var showsNoticeBanner: Bool {
        SearchSuggestionsNotice.showsBanner(suggestionsOn: suggestionsOn, dismissed: noticeDismissed, bannerShown: noticePressed)
    }

    /// Row places the panel is sized for: the rows and the banner.
    /// The places the bar is sized for: the rows in view (Arc's five; more scroll behind them, #805) and the banner's.
    var rowPlaces: Int {
        SearchSuggestionsNotice.rowPlaces(rows: CommandBarRowWindow.shown(count: result.items.count, banner: showsNoticeBanner), banner: showsNoticeBanner)
    }

    /// The (i): the banner takes the last row's place.
    func showNotice() {
        guard showsNoticeBadge else { return }
        noticePressed = true
        result = listed(result)
        if selectedIndex >= result.items.count { selectedIndex = max(0, result.items.count - 1) }
    }

    /// Dismiss: the banner and the badge go for good, and the last row comes back.
    func dismissNotice() {
        store.prefs.searchSuggestionsNoticeDismissed = true
        noticePressed = false
        relist()
    }

    func openNoticeSettings() {
        close()
        onNoticeSettings()
    }

    func openNoticeLearnMore() {
        close()
        onNoticeLearnMore()
    }

    /// Whether row `index` is a visited page's, which Arc's ✕ and ⌥⌘⌫ delete (#779).
    func canDelete(row index: Int) -> Bool {
        guard scope == nil, result.items.indices.contains(index), !store.window().isIncognito else { return false }
        return SuggestionDeletion.page(rowID: result.items[index].id) != nil
    }

    /// Arc's Delete Suggestion (#779): row `index` (the ✕ clicked) or the selected row (⌥⌘⌫) leaves the bar's
    /// profile's history and the list; the selection stays on its line. false when the row isn't a visited page's.
    @discardableResult
    func delete(row index: Int? = nil) -> Bool {
        let i = index ?? selectedIndex
        guard canDelete(row: i), engine.delete(result.items[i]) else { return false }
        let selectedID = i == selectedIndex ? nil : result.items.indices.contains(selectedIndex) ? result.items[selectedIndex].id : nil
        result = listed(engine.suggestions(for: query, mode: mode, currentTabID: store.selectedTabID, spaceShown: spaceShown))
        if !allowCompletion { result.inlineCompletion = nil }
        selectedIndex = result.items.firstIndex { $0.id == selectedID }
            ?? SuggestionDeletion.selection(afterDeleting: i, count: result.items.count)
        previewText = selectedIndex == 0 ? nil : result.items.indices.contains(selectedIndex) ? fillText(for: result.items[selectedIndex]) : nil
        previewVersion += 1
        return true
    }

    /// The pointer is over row `index`: it selects the row once the pointer has moved since the
    /// rows last changed (CraCore HoverGate, #382).
    func hover(row index: Int) {
        guard hoverGate.isHover(pointerAt: NSEvent.mouseLocation), selectedIndex != index else { return }
        selectedIndex = index
    }

    /// What the engine listed, as this window lists it. All of it: the rows past the ones in view
    /// scroll into it (#805); the banner takes a place in view, not a row.
    private func listed(_ r: SuggestionResult) -> SuggestionResult {
        hoverGate.listChanged(pointerAt: NSEvent.mouseLocation)
        var r = r
        r.items = r.items.map(inWindow)
        return r
    }

    /// The list scrolled under a resting pointer (#805): the row now under it isn't hovered.
    func listScrolled() {
        hoverGate.listChanged(pointerAt: NSEvent.mouseLocation)
    }

    /// An open tab's or an archived page's row as this window's bar lists it: in a Little Window, a
    /// page to load there, listed like a history row (no "Switch to Tab" or "Restore").
    private func inWindow(_ s: Suggestion) -> Suggestion {
        let row: LittleBarRows.Row
        switch s.kind {
        case .switchToTab: row = .openTab
        case .archived: row = .archivedPage
        default: return s
        }
        var tabsScope = false
        if case .tabs = scope { tabsScope = true }
        guard LittleBarRows.action(for: row, in: window, tabsScope: tabsScope) == .loadInWindow, let url = s.url, !url.isEmpty else { return s }
        return Suggestion(id: s.id, kind: .history, title: s.title, subtitle: SuggestionEngine.humanURL(url), url: url,
                          faviconKey: s.faviconKey, symbol: s.symbol, trailing: nil, score: s.score, loose: s.loose)
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        scope = nil
        searchEngineWatcher?.cancel()
        searchEngineWatcher = nil
        engine.resetIndex()
        onClose()
    }
}

/// Borderless floating panel that can take keyboard focus.
final class CommandBarPanel: NSPanel {
    /// The panel lost the keys: tells `finish` which window holds them, which decides whether the bar
    /// closes (#551) and where the keys go (#429). A click says at once, so a click on the bar's own
    /// window still closes the bar and focuses its page before the click lands; anything else (⌘`, the Window menu) is read once AppKit has handed the keys over.
    /// `owns` is true for the bar's window and the windows that belong to it (its page, its Peek).
    @MainActor
    func keysWent(owns: @escaping (NSWindow) -> Bool, finish: @escaping (CommandBarClosing.KeyHolder) -> Void) {
        func holder(_ w: NSWindow?) -> CommandBarClosing.KeyHolder {
            guard let w, w !== self else { return .none }
            var x: NSWindow? = w
            while let c = x {
                if owns(c) { return .barsWindow }
                x = c.parent
            }
            return .otherWindow
        }
        let event = NSApp.currentEvent
        if let event, [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type), let clicked = event.window {
            finish(holder(clicked))
            return
        }
        DispatchQueue.main.async {
            finish(NSApp.isActive ? holder(NSApp.keyWindow) : .none)
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// ⌥⌘⌫ deletes the selected visited page, as Arc's Delete Suggestion (#779). The field editor never turns it into a
    /// command (⌘⌫ and ⌥⌫ are its own), so the panel takes it as it arrives; on any other row it does nothing.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, SuggestionDeletion.isShortcut(keyCode: event.keyCode, modifiers: event.modifierFlags.rawValue),
           let bar = contentView as? CommandBarView {
            bar.deleteSelectedSuggestion()
            return
        }
        super.sendEvent(event)
    }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 680, height: 60),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
    }
}
