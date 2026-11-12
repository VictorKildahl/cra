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
    /// The space whose palette colours the selected row and the info badge (CraCore CommandBarTones).
    var theme: SpaceTheme?
    var focusedSpaceID: UUID?
    /// The space "Switch to" leaves out when it isn't the focused one: a Little Window's (#316).
    var spaceShown: UUID?
    var spaceName: (UUID) -> String = { _ in "" }
    /// Arc's scoped search: Tab on "youtube" scopes the bar to YouTube, on "%" to the space's open
    /// tabs, on the empty field to the browser's actions (a pill before the field) until Backspace
    /// on an empty field or Escape.
    private(set) var scope: CommandBarScope?
    /// What was typed when Tab entered the scope; Backspace puts it back.
    private var scopeTyped = ""
    /// The URL ⌘L opened with (the page's), nil for ⌘T.
    private(set) var openedPrefill: String?
    /// Rows that open or change under a still pointer don't take the selection from the top row (#382).
    @ObservationIgnored private var hoverGate = HoverGate()

    unowned let engine: SuggestionEngine
    unowned let store: SidebarStore
    var onCommit: (Suggestion?, String, CommandBarMode) -> Void = { _, _, _ in }
    /// Opens the row in a background tab; false when it has no page to open there.
    var onOpenInBackground: (Suggestion?, String) -> Bool = { _, _ in false }
    /// Opens the row as a split pane beside the current tab; false when it can't go there.
    var onOpenInSplit: (Suggestion?, String) -> Bool = { _, _ in false }
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
        result = listed(engine.suggestions(for: query, mode: mode, currentTabID: store.selectedTabID, spaceShown: spaceShown))
        isOpen = true
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
        result = listed(engine.suggestions(for: newQuery, mode: mode, currentTabID: store.selectedTabID, spaceShown: spaceShown))
        if !allowCompletion { result.inlineCompletion = nil }
        selectedIndex = 0
        previewText = nil
    }

    /// The search engine answered: list again, keeping the selected row where it still is.
    private func relist() {
        guard scope == nil else { return }
        let selectedID = result.items.indices.contains(selectedIndex) ? result.items[selectedIndex].id : nil
        result = listed(engine.suggestions(for: query, mode: mode, currentTabID: store.selectedTabID, spaceShown: spaceShown))
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
        case .search, .command, .switchSpace, .moveToSpace, .moveToFolder:
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
    var rowPlaces: Int { SearchSuggestionsNotice.rowPlaces(rows: result.items.count, banner: showsNoticeBanner) }

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

    /// The pointer is over row `index`: it selects the row once the pointer has moved since the
    /// rows last changed (CraCore HoverGate, #382).
    func hover(row index: Int) {
        guard hoverGate.isHover(pointerAt: NSEvent.mouseLocation), selectedIndex != index else { return }
        selectedIndex = index
    }

    /// What the engine listed, less the last row while the banner has its place.
    private func listed(_ r: SuggestionResult) -> SuggestionResult {
        hoverGate.listChanged(pointerAt: NSEvent.mouseLocation)
        var r = r
        let n = SearchSuggestionsNotice.rowsListed(r.items.count, maxRows: SuggestionEngine.maxRows, banner: showsNoticeBanner)
        if n < r.items.count { r.items.removeLast(r.items.count - n) }
        return r
    }

    func close() {
        guard isOpen else { return }
        isOpen = false
        scope = nil
        engine.resetIndex()
        onClose()
    }
}

/// Borderless floating panel that can take keyboard focus.
final class CommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

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
