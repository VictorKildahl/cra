import AppKit

/// Exact production MWC selection/query/open/find bodies are compiled by the service harness.
/// Only window effects, browser delivery and the find pasteboard are replaced.
@MainActor
enum AskOnPageSelectionTests {
    private static var checks = 0

    static func run() {
        selectionFindsOnceThroughEveryPanelPath()
        staleSelectionCannotChangeTheNewOwner()
        narrowAskPanelFitsFocusedPage()
        print("Use Selection to Find: \(checks) production-boundary checks passed")
    }

    private static func expect(_ condition: Bool, _ message: String) {
        checks += 1
        if !condition { FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8)); exit(1) }
    }

    // promise: #393
    private static func selectionFindsOnceThroughEveryPanelPath() {
        // First case is the review's frozen-R1 failure. The remaining cases guard duplicate searches.
        for conversation in [true, false] {
            for visible in [true, false] {
                for repeated in [false, true] {
                    let window = SelectionWindow()
                    window.askOnPage.state.enabled = true
                    window.askOnPage.pageChanged(canAsk: true)
                    if conversation { window.askOnPage.ask("A pending conversation") }
                    let conversationID = window.askOnPage.service.current?.id
                    window.overlay.findVisible = visible
                    window.overlay.findQuery = repeated ? "selected <literal> & exact." : "before"
                    window.wireProductionQueryCallback()
                    window.useSelectionForFind()
                    window.currentBrowser?.replySelection("  selected <literal> & exact.  ")
                    let label = "conversation=\(conversation), visible=\(visible), repeated=\(repeated)"
                    expect(window.browsers.selectionFinds.count == 1,
                        "Use Selection must issue exactly one native Find (\(label)); got \(window.browsers.selectionFinds.count)")
                    expect(window.overlay.findQuery == "selected <literal> & exact." && window.overlay.findVisible,
                        "The real overlay must keep the selected ordinary input and open panel (\(label))")
                    expect(window.browsers.selectionFindState.request?.query == window.overlay.findQuery
                        && window.browsers.selectionFindState.request?.purpose == .ordinary,
                        "The command must use the ordinary correlated request for the selected text (\(label))")
                    expect(window.askOnPage.service.current?.id == conversationID,
                        "Use Selection must preserve the existing conversation rather than submit or reset it (\(label))")
                    expect(window.savedFindSelection == window.overlay.findQuery && window.overlay.findFocusToken == 1,
                        "The command must update its local pasteboard seam and refocus once (\(label))")
                    window.askOnPage.reset()
                }
            }
        }
    }

    // promise: #393
    private static func narrowAskPanelFitsFocusedPage() {
        let owner = SelectionWindow()
        owner.askOnPage.state.enabled = true
        owner.askOnPage.heightChanged(600)
        let page = NSRect(x: 100, y: 200, width: 240, height: 160)
        let panel = owner.measuredFindPanelFrame(page: page)
        expect(page.contains(panel), "The actual Ask panel must remain inside a narrow focused page, including its total height")
    }

    // promise: #393
    private static func staleSelectionCannotChangeTheNewOwner() {
        let window = SelectionWindow()
        window.overlay.findQuery = "unchanged"
        window.wireProductionQueryCallback()
        window.useSelectionForFind()
        let saved = window.savedFindSelection
        window.browsers.context = AskOnPageContext()
        window.currentBrowser?.replySelection("obsolete selection")
        expect(window.overlay.findQuery == "unchanged" && !window.overlay.findVisible,
            "A stale selected-text callback cannot change or open the new owner's overlay")
        expect(window.browsers.selectionFinds.isEmpty && window.savedFindSelection == saved,
            "A stale callback cannot issue native Find or change even the local pasteboard seam")
    }
}

@MainActor
final class SelectionWindow {
    let overlay = OverlayState()
    let browsers = BrowserManager()
    lazy var askOnPage = AskOnPageController(overlay: overlay,
        service: AskOnPageService(browsers: browsers, enabled: { true }, available: { true }, clock: ManualScheduler()))
    let currentBrowser: SelectionBrowser? = SelectionBrowser()
    let shell = SelectionShell()
    let window: NSWindow? = nil
    let findPanel: FindBarPanel? = nil
    var lastFindPage: NSRect?
    var savedFindSelection: String? { NSPasteboard.saved }
    func syncAskOnPage() { askOnPage.pageChanged(canAsk: true) }
    func refitFindPanel() {}

    // Nested shadow of the imported AppKit type. The exact production command never reaches a real clipboard.
    final class NSPasteboard {
        enum Name { case find }
        enum PasteboardType { case string }
        static var saved: String?
        init(name: Name) {}
        func clearContents() { Self.saved = nil }
        func setString(_ text: String, forType: PasteboardType) { Self.saved = text }
    }
}

@MainActor
final class SelectionShell {
    var findVisible = false
    func layoutContentChildren() {}
}

@MainActor
final class SelectionBrowser {
    private var selectionReply: ((String?, String?) -> Void)?
    func sendDevToolsMethod(_ method: String, params: String, completion: @escaping (String?, String?) -> Void) {
        selectionReply = completion
    }
    func replySelection(_ text: String) {
        let result = try! JSONSerialization.data(withJSONObject: ["result": ["value": text]])
        let reply = selectionReply
        selectionReply = nil
        reply?(String(data: result, encoding: .utf8), nil)
    }
}
