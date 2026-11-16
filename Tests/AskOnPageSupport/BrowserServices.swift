import Foundation

// Only the existing browser/availability boundaries are replaced; the production service and SDK adapter compile unchanged.
struct AskOnPageContext: Equatable {
    let id = UUID()
    let tabID: UUID
    let spaceID: UUID
    init(tabID: UUID = UUID(), spaceID: UUID = UUID()) { self.tabID = tabID; self.spaceID = spaceID }
}
@MainActor final class BrowserManager {
    var context: AskOnPageContext? = AskOnPageContext()
    var quotePending: ((Bool?) -> Void)?
    var quoteText: String?
    var quoteIsCurrent: (() -> Bool)?
    var pending: ((AskOnPagePrompt.Page?) -> Void)?
    private(set) var selectionFindState = AskOnPage.FindState()
    private(set) var selectionFinds: [AskOnPage.FindRequest] = []
    func findPageContext() -> AskOnPageContext? { context }
    @discardableResult func prepareFind(_ query: String, matchCase: Bool = false, purpose: AskOnPage.FindPurpose = .ordinary) -> AskOnPage.FindRequest? {
        selectionFindState.begin(query, matchCase: matchCase, purpose: purpose)
    }
    func find(_ query: String, forward: Bool) {
        selectionFinds.append(prepareFind(query)!)
    }
    func stopFinding(_ clearSelection: Bool) { selectionFindState.clear() }
    func prepareQuote(_ text: String) { selectionFindState.begin(text, purpose: .quote) }
    func findAskOnPageQuote(_ text: String, in context: AskOnPageContext, request: AskOnPage.FindRequest,
                            isCurrent: @escaping () -> Bool, completion: @escaping (Bool?) -> Void) {
        quoteText = text; quoteIsCurrent = isCurrent; quotePending = completion
    }
    func clearAskOnPageQuote() {
        let done = quotePending; quotePending = nil; quoteIsCurrent = nil
        done?(nil)
        if selectionFindState.request?.purpose == .quote { selectionFindState.clear() }
    }
    func askOnPageContext() -> AskOnPageContext? { context }
    func isCurrentAskOnPage(_ context: AskOnPageContext) -> Bool { self.context == context }
    func askOnPageSnapshot(_ context: AskOnPageContext, completion: @escaping (AskOnPagePrompt.Page?) -> Void) { pending = completion }
    func reply(_ page: AskOnPagePrompt.Page?) { let done = pending; pending = nil; done?(page) }
}
