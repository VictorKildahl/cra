import AppKit
import CraCEF

/// Captured browser ownership, not a URL cache key. Reloading the same address changes the revision.
struct AskOnPageContext: Equatable {
    let tabID: UUID
    let runtime: ObjectIdentifier
    let navigationRevision: UInt
    let focusRevision: UInt
    let url: String
    let profilePath: String?
    let incognito: Bool
}

extension BrowserManager {
    func askOnPageContext() -> AskOnPageContext? {
        guard let rt = visibleRuntime, !rt.browser.isLoading,
              AskOnPageContent.supportsURL(rt.browser.currentURL) else { return nil }
        return findPageContext()
    }

    /// Ordinary Find also works in documents that the model cannot read, including PDF.
    func findPageContext() -> AskOnPageContext? {
        guard let rt = visibleRuntime, rt.browser.isCreated, !rt.browser.isClosed, !rt.discarded,
              rt.browser.isIncognito == store.isIncognito(item: rt.tabID),
              rt.browser.isIncognito || rt.browser.profilePath == store.profilePath(item: rt.tabID) else { return nil }
        return AskOnPageContext(tabID: rt.tabID, runtime: ObjectIdentifier(rt), navigationRevision: rt.navigationRevision,
                                focusRevision: askOnPageFocusRevision, url: rt.browser.currentURL,
                                profilePath: store.profilePath(item: rt.tabID), incognito: rt.browser.isIncognito)
    }

    func isCurrentAskOnPage(_ context: AskOnPageContext) -> Bool { askOnPageContext() == context }

    /// An obsolete reply completes with nil; only a still-owned visible document returns text.
    func askOnPageSnapshot(_ context: AskOnPageContext, completion: @escaping (AskOnPagePrompt.Page?) -> Void) {
        guard isCurrentAskOnPage(context), let rt = runtimes[context.tabID] else { completion(nil); return }
        let params = String(data: try! JSONSerialization.data(withJSONObject: [
            "expression": AskOnPageContent.script, "returnByValue": true]), encoding: .utf8)!
        rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, error == nil, self.isCurrentAskOnPage(context) else { completion(nil); return }
                completion(AskOnPageContent.page(evaluation: result, expectedURL: context.url))
            }
        }
    }
}
