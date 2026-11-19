import AppKit
import CraCEF

/// Find in page for a Little Window or a Peek (#577): the browser window's bar (FindBarView in a
/// FindBarPanel), top trailing over this window's page, finding on that page. The browser window's
/// bar goes through its BrowserManager's tabs; this one has one page, so it keeps its own search
/// session (AskOnPage.FindState: results of an older search are dropped). Ask on Page stays with
/// browser windows: here the bar is always the plain one.
@MainActor
final class LittleFindBar {
    let overlay = OverlayState()
    private var session = AskOnPage.FindState()
    private var panel: FindBarPanel?
    /// The Little Window (or Peek) the bar hangs on.
    private let window: () -> NSWindow?
    /// Its page now.
    private let browser: () -> CraBrowser?
    /// The page's area and how much of its top the window's floating bar covers, on screen.
    private let page: () -> (rect: NSRect, cover: CGFloat)?

    init(window: @escaping () -> NSWindow?, browser: @escaping () -> CraBrowser?, page: @escaping () -> (rect: NSRect, cover: CGFloat)?) {
        self.window = window
        self.browser = browser
        self.page = page
        // Typing searches as it goes, as in the browser window.
        overlay.onFindQueryChange = { [weak self] query in
            guard let self, self.overlay.findVisible else { return }
            self.find(query, forward: true)
        }
    }

    var isShown: Bool { overlay.findVisible }

    /// Edit ▸ Find's commands on this window's page.
    func perform(_ command: FindCommand) {
        switch command.effect(barShown: overlay.findVisible) {
        case .showBar: show()
        case .search(let forward): find(overlay.findQuery, forward: forward)
        case .searchSelection: useSelection()
        }
    }

    func show(focus: Bool = true) {
        guard let window = window() else { return }
        let opening = !overlay.findVisible
        overlay.findVisible = true
        // Opening finds the last search again, from its first match.
        if opening {
            stop(clearSelection: false)
            if !overlay.findQuery.isEmpty { find(overlay.findQuery, forward: true) }
        }
        if focus { overlay.findFocusToken += 1 }
        let panel = self.panel ?? makePanel()
        if panel.parent !== window { window.addChildWindow(panel, ordered: .above) }
        refit()
        if focus { panel.makeKeyAndOrderFront(nil) } else { panel.orderFront(nil) }
    }

    /// `refocus`: the page takes the keys back if the bar had them (not while the window closes).
    func hide(refocus: Bool = true) {
        guard overlay.findVisible else { return }
        overlay.findVisible = false
        overlay.findMatchCount = nil
        stop(clearSelection: true)
        guard let panel else { return }
        let hadKeys = panel.isKeyWindow
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        // Typing goes back to the page, unless the keys had already gone elsewhere.
        if refocus, hadKeys, let window = window() {
            window.makeKey()
            if let b = browser() {
                if let host = b.hostWindow, host.parent === window { host.makeKey() }
                else if let render = EmbeddedPages.renderView(in: b.containerView) { window.makeFirstResponder(render) }
                b.setFocused(true)
            }
        }
    }

    /// The page moved or changed size, or the window's floating bar came out or went.
    func refit() {
        guard overlay.findVisible, let panel, let page = page() else { return }
        let frame = FindBarPlacement.frame(page: page.rect, size: CraMetrics.findBarSize, inset: CraMetrics.findBarInset,
                                           toolbarOverPage: page.cover)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// A new document started loading, or the window has a new page: matches of the old one are gone.
    func pageChanged() {
        session.clear()
        overlay.findMatchCount = nil
        overlay.findActiveMatch = 0
    }

    /// The window closes, or a Peek goes to wait on its tab.
    func close() {
        hide(refocus: false)
        panel = nil
    }

    func find(_ query: String, forward: Bool) {
        guard !query.replacingOccurrences(of: "\r", with: "").isEmpty else { stop(clearSelection: true); return }
        guard let b = browser() else { return }
        let request = session.begin(query)
        b.findText(query, forward: forward, matchCase: false, findNext: true, generation: request.id, quote: false)
    }

    /// The page's answer: only the current search's counts reach the bar.
    func accept(count: Int, activeMatch: Int, generation: UUID, quote: Bool, identifier: Int, finalUpdate: Bool) {
        guard session.accept(generation, quote: quote, identifier: identifier, count: count, activeMatch: activeMatch,
                             finalUpdate: finalUpdate), overlay.findVisible else { return }
        overlay.findMatchCount = session.count
        overlay.findActiveMatch = session.activeMatch
    }

    /// Use Selection for Find (⌘E): the selection goes on the find pasteboard, as macOS apps share
    /// it, and the bar searches it.
    private func useSelection() {
        guard let b = browser() else { return }
        b.sendDevToolsMethod("Runtime.evaluate", params: #"{"expression":"getSelection().toString()","returnByValue":true}"#) { [weak self, weak b] result, _ in
            MainActor.assumeIsolated {
                let o = result.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
                let text = ((o?["result"] as? [String: Any])?["value"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard let self, let b, self.browser() === b, !text.isEmpty else { return }
                let pb = NSPasteboard(name: .find)
                pb.clearContents()
                pb.setString(text, forType: .string)
                let same = self.overlay.findVisible && self.overlay.findQuery == text
                self.overlay.findQuery = text
                self.show()
                if same { self.find(text, forward: true) }
            }
        }
    }

    private func stop(clearSelection: Bool) {
        session.clear()
        browser()?.stopFinding(clearSelection)
    }

    private func makePanel() -> FindBarPanel {
        let panel = FindBarPanel()
        let view = FindBarView(overlay: overlay, onFind: { [weak self] q, forward in self?.find(q, forward: forward) },
                               onClose: { [weak self] in self?.hide() })
        view.frame = panel.contentView!.bounds
        view.autoresizingMask = [.width, .height]
        panel.contentView!.addSubview(view)
        // Little Arc's palette is dark whatever macOS uses; a Peek follows macOS.
        panel.appearance = window()?.appearance
        self.panel = panel
        return panel
    }

    /// For `cra://debug?littleFind=<label>`: whether the bar shows, where it sits on the page, what
    /// it searches and how many matches the page reported.
    func readout(_ label: String) -> String {
        guard overlay.findVisible, let panel, let page = page() else { return "little find \(label): visible=0" }
        let editor = panel.firstResponder as? NSTextView
        let focused = editor?.delegate is NSTextField
        let f = panel.frame
        return "little find \(label): visible=1 top=\(Int(page.rect.maxY - f.maxY)) trailing=\(Int(page.rect.maxX - f.maxX)) "
            + "child=\(panel.parent === window() ? 1 : 0) focused=\(focused ? 1 : 0) "
            + "count=\(overlay.findMatchCount.map(String.init) ?? "none") active=\(overlay.findActiveMatch) query=\(overlay.findQuery)"
    }

    /// For `cra://debug?key=…&target=littleFind`: the bar's panel, which has the keys while it is up.
    var debugPanel: NSWindow? { overlay.findVisible ? panel : nil }
}
