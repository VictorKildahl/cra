import AppKit
import Observation

/// Uses the production native card/controller, overlay and guided service without constructing a window.
@MainActor
enum AskOnPageControllerTests {
    static func run() async {
        await nativeInputFocusAndCommands()
        await nativeCardOwnsOneService()
        hostedCardReleasesItsOwner()
    }

    // promise: #393
    private static func nativeInputFocusAndCommands() async {
        let overlay = OverlayState(), browsers = BrowserManager()
        let service = AskOnPageService(browsers: browsers, enabled: { true }, available: { true }, clock: ManualScheduler())
        let card = AskOnPageController(overlay: overlay, service: service)
        card.state.enabled = true; card.pageChanged(canAsk: true)
        overlay.findQuery = "Café 👩‍🔬"; overlay.findVisible = true
        let field = AskOnPageTextField(overlay: overlay, controller: card)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        field.frame = NSRect(x: 18, y: 12, width: 280, height: 24)
        window.contentView!.addSubview(field)
        AskOnPageInput(state: card.state, overlay: overlay, controller: card).update(field)
        func turn() async { await withCheckedContinuation { done in DispatchQueue.main.async { done.resume() } } }
        await turn()
        guard let editor = field.currentEditor() else { preconditionFailure("the offscreen native field must own its real field editor") }
        precondition(field.font?.pointSize == 16 && field.placeholderString == "Find or ask…", "initial input uses native medium 16 and the exact placeholder")
        let all = NSRange(location: 0, length: (overlay.findQuery as NSString).length)
        precondition(editor.selectedRange == all, "opening/Cmd-F selects the entire real field editor, including Unicode")
        editor.selectedRange = NSRange(location: 1, length: 0)
        AskOnPageInput(state: card.state, overlay: overlay, controller: card).update(field); await turn()
        precondition(editor.selectedRange == NSRange(location: 1, length: 0), "ordinary query/style updates cannot reselect or steal focus")
        overlay.findFocusToken += 1
        AskOnPageInput(state: card.state, overlay: overlay, controller: card).update(field); await turn()
        precondition(editor.selectedRange == all, "a new Cmd-F focus token selects all even when already editing")
        editor.selectedRange = NSRange(location: 2, length: 0)
        overlay.findFocusToken += 1; AskOnPageInput(state: card.state, overlay: overlay, controller: card).update(field); overlay.findVisible = false
        await turn()
        precondition(editor.selectedRange == NSRange(location: 2, length: 0), "a closed card rejects queued stale focus work")
        overlay.findVisible = true
        var searches: [(String, Bool)] = [], zero = false, closed = false
        card.canAskFromFind = { _, _ in zero }
        card.onFind = { searches.append(($0, $1)) }
        card.onClose = { closed = true; overlay.findVisible = false; card.reset() }
        let actions: [(Selector, NSEvent.ModifierFlags, Bool)] = [
            (#selector(NSResponder.moveDown(_:)), [], true), (#selector(NSResponder.moveUp(_:)), [], false),
            (#selector(NSResponder.insertNewline(_:)), [], true), (#selector(NSResponder.insertNewline(_:)), .shift, false),
            (#selector(NSResponder.insertLineBreak(_:)), .shift, false),
            (#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), .shift, false)]
        for (selector, flags, forward) in actions {
            let count = searches.count
            precondition(field.performCommand(selector, modifiers: flags), "the native editor must consume the supported command")
            precondition(searches.count == count + 1 && searches.last?.0 == overlay.findQuery && searches.last?.1 == forward,
                         "arrows/Return/Shift-Return route exactly once to the correct ordinary Find direction")
            precondition(service.current == nil, "pending Find keyboard commands must not invent an Ask turn")
        }
        overlay.findQuery = ""
        let blankCount = searches.count
        precondition(field.performCommand(#selector(NSResponder.insertNewline(_:)), modifiers: .shift)
                     && searches.count == blankCount + 1 && searches.last?.1 == false,
                     "Shift-Return takes the same previous-Find path as Up, including empty input")
        overlay.findQuery = "Café 👩‍🔬"
        precondition(!field.performCommand(#selector(NSResponder.insertTab(_:)), modifiers: [])
                     && !field.performCommand(#selector(NSResponder.insertNewline(_:)), modifiers: .command),
                     "unrelated editor commands retain native AppKit handling")
        field.stringValue = "An exact new query"
        overlay.findMatchCount = 0
        field.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
        precondition(overlay.findQuery == field.stringValue && overlay.findMatchCount == nil,
                     "native text changes synchronously invalidate old match authority through the real overlay")
        zero = true
        precondition(field.performCommand(#selector(NSResponder.insertNewline(_:)), modifiers: []), "Return is handled")
        precondition(service.current?.question == "An exact new query" && overlay.findQuery.isEmpty,
                     "only proven current zero allows native Return to start the existing service")
        AskOnPageInput(state: card.state, overlay: overlay, controller: card).update(field)
        precondition(field.font?.pointSize == 14 && field.placeholderString == "Ask a question…", "conversation input uses native medium 14 and the exact placeholder")
        precondition(field.performCommand(#selector(NSResponder.cancelOperation(_:)), modifiers: []), "Escape is handled")
        precondition(closed && service.current == nil && service.messages.isEmpty, "Escape uses existing close/reset ownership")
        precondition(!field.performCommand(#selector(NSResponder.moveDown(_:)), modifiers: []), "hidden input cannot issue Find")
        print("Ask native input: real offscreen editor, select-all/caret/stale focus, keyboard and service checks passed")
    }

    // promise: #393
    private static func nativeCardOwnsOneService() async {
        let browsers = BrowserManager(), overlay = OverlayState(), gate = Gate()
        let page = AskOnPagePrompt.Page(url: "https://example.test", title: "Fixture",
            text: "The museum opens at 09:30. A literal <excerpt> is visible & unchanged.")
        let service = AskOnPageService(browsers: browsers, enabled: { true }, available: { true },
            clock: ManualScheduler(), countTokens: { ($0.utf8.count + $1.utf8.count + 3) / 4 }, generate: gate.stream)
        let card = AskOnPageController(overlay: overlay, service: service)
        card.state.enabled = true
        card.pageChanged(canAsk: true)
        var provenZero = false
        card.canAskFromFind = { _, _ in provenZero }
        overlay.findQuery = "When does it open?"
        card.submit(shift: false)
        precondition(service.current == nil && !card.state.inConversation,
                     "Pending multiword Find cannot create an Ask turn")
        provenZero = true
        card.submit(shift: true)
        precondition(service.current == nil, "Shift-Return cannot ask, even with final zero")
        card.submit(shift: false)
        precondition(service.current?.question == "When does it open?" && overlay.findQuery.isEmpty && card.state.inConversation,
                     "The card must use its one service's current request and clear accepted input")
        overlay.findQuery = "A second question"
        card.ask(overlay.findQuery)
        precondition(service.current?.question == "When does it open?" && overlay.findQuery == "A second question",
                     "An overlapping submission cannot replace the service request or erase input")
        browsers.reply(page)
        await gate.started()
        gate.update?(.init(excerpts: ["The museum"], answer: "It opens"))
        precondition(service.current?.answer?.quotes.first?.state == .unverified && service.messages.isEmpty,
                     "The card observes native provisional fields rather than copied raw replies")
        gate.finish(.init(excerpts: ["The museum opens at 09:30."], answer: "It opens at 09:30.", keyAnswer: "09:30"))
        await settled(service)
        precondition(service.messages.count == 1 && service.current == nil && card.state.inConversation,
                     "A complete native answer is the same visible conversation owned by the service")
        let message = service.messages[0]
        card.findQuote(messageID: message.id, index: 0)
        precondition(browsers.quoteText == "The museum opens at 09:30." && overlay.findQuery == "A second question"
                     && service.messages.count == 1,
                     "Quote navigation preserves literal punctuation, ordinary input and conversation")
        precondition(card.readout("quote").contains("search=[loading]") && service.quoteNavigation?.request.matchCase == true,
                     "An accepted current quote has its own loading status before any native Find count")
        let completeQuote = browsers.quotePending!
        completeQuote(true)
        precondition(card.readout("quote").contains("search=[found]"), "Only the exact completed DOM operation marks a quote found")
        card.findQuote(messageID: message.id, index: 0)
        let retiredQuote = browsers.quotePending!
        card.findQuote(messageID: message.id, index: 0)
        retiredQuote(true)
        precondition(service.quoteNavigation?.status == .loading, "a retired same-text quote cannot complete a newer quote generation")
        browsers.quotePending?(false)
        precondition(card.readout("quote").contains("search=[notFound]"), "an exact completed not-found operation has its own status")
        card.reset()
        retiredQuote(true)
        precondition(service.quoteNavigation == nil && service.messages.isEmpty, "A retired quote completion cannot restore status or dialogue")
        // Reconstruct the original completed conversation for the remaining lifecycle checks.
        card.ask("What time does it open?")
        browsers.reply(page)
        await gate.started()
        gate.finish(.init(excerpts: ["The museum opens at 09:30."], answer: "It opens at 09:30."))
        await settled(service)
        card.findQuote(messageID: service.messages[0].id, index: -1)
        precondition(service.messages.count == 1, "An invalid quote action cannot replace native history")
        card.reset()
        precondition(service.messages.isEmpty && service.current == nil && !card.state.inConversation,
                     "The card reset must synchronously clear its service rather than a copied UI array")
        card.ask("A late request")
        browsers.reply(page)
        await gate.started()
        browsers.context = AskOnPageContext()
        card.pageChanged(canAsk: true)
        gate.finish(.init(excerpts: [], answer: "An obsolete answer"))
        await Task.yield()
        precondition(service.current == nil && service.messages.isEmpty && !card.state.inConversation,
                     "A page ownership change cannot revive a late guided answer in the reused card")
        print("Ask on Page controller: native current/history, pending/shift Return, quote and reset checks passed")
    }

    // promise: #393
    private static func hostedCardReleasesItsOwner() {
        weak var weakService: AskOnPageService?
        weak var weakCard: AskOnPageController?
        autoreleasepool {
            let browsers = BrowserManager()
            let service = AskOnPageService(browsers: browsers, enabled: { true }, available: { true })
            weakService = service
            var card: AskOnPageController? = AskOnPageController(overlay: OverlayState(), service: service)
            weakCard = card
            let hostedView = card!.view
            precondition(hostedView.subviews.count == 2, "The existing material and native hosting view remain in use")
            card = nil
            precondition(weakCard == nil, "The hosting tree cannot retain the window controller's conversation owner")
        }
        precondition(weakService == nil, "Discarding the card releases its service and page text")
    }

    private static func settled(_ service: AskOnPageService) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            @MainActor func track() {
                if !service.isLoading { done.resume(); return }
                withObservationTracking { _ = service.isLoading } onChange: { Task { @MainActor in track() } }
            }
            track()
        }
    }

    private final class Gate {
        var update: (@MainActor (AskOnPage.Draft) -> Void)?
        var completion: CheckedContinuation<AskOnPage.Draft, Error>?
        var waiting: CheckedContinuation<Void, Never>?
        func stream(_ fitted: AskOnPagePrompt.Fitted, update: @escaping @MainActor (AskOnPage.Draft) -> Void) async throws -> AskOnPage.Draft {
            self.update = update
            return try await withCheckedThrowingContinuation { done in
                completion = done
                waiting?.resume(); waiting = nil
            }
        }
        func started() async {
            if completion != nil { return }
            await withCheckedContinuation { waiting = $0 }
        }
        func finish(_ draft: AskOnPage.Draft) { let done = completion; completion = nil; done?.resume(returning: draft) }
    }
}
