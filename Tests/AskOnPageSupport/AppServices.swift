import Foundation
import Observation

// Only the existing browser/availability boundaries are replaced; the production service and SDK adapter compile unchanged.
struct AskOnPageContext: Equatable { let id = UUID() }
@MainActor final class BrowserManager {
    var context: AskOnPageContext? = AskOnPageContext()
    var pending: ((AskOnPagePrompt.Page?) -> Void)?
    private(set) var selectionFindState = AskOnPage.FindState()
    private(set) var selectionFinds: [AskOnPage.FindRequest] = []
    func findPageContext() -> AskOnPageContext? { context }
    @discardableResult func prepareFind(_ query: String) -> AskOnPage.FindRequest {
        selectionFindState.begin(query)
    }
    func find(_ query: String, forward: Bool) {
        selectionFinds.append(prepareFind(query))
    }
    func stopFinding(_ clearSelection: Bool) { selectionFindState.clear() }
    func askOnPageContext() -> AskOnPageContext? { context }
    func isCurrentAskOnPage(_ context: AskOnPageContext) -> Bool { self.context == context }
    func askOnPageSnapshot(_ context: AskOnPageContext, completion: @escaping (AskOnPagePrompt.Page?) -> Void) { pending = completion }
    func reply(_ page: AskOnPagePrompt.Page?) { let done = pending; pending = nil; done?(page) }
}
@MainActor @Observable final class TidyTabsService {
    static let shared = TidyTabsService()
    static let fakeModel = ProcessInfo.processInfo.environment["CRA_TIDY_FAKE_MODEL"] == "1"
    var modelAvailable = true
}
