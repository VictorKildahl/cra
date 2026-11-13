import AppKit
import CraCEF
import UniformTypeIdentifiers

/// Captured browser ownership, not a URL cache key. Reloading the same address changes the revision.
struct AskOnPageContext: Equatable {
    let tabID: UUID
    let spaceID: UUID
    let runtime: ObjectIdentifier
    let navigationRevision: UInt
    let focusRevision: UInt
    let url: String
    let profilePath: String?
    let incognito: Bool
}

extension BrowserManager {
    func askOnPageContext() -> AskOnPageContext? {
        guard let rt = visibleRuntime, !rt.browser.isLoading, let context = findPageContext(),
              let document = askOnPageDocument, document.context == context,
              let url = URL(string: context.url),
              AskOnPagePolicy.canAsk(page: url, incognito: context.incognito,
                                    documentKind: AskOnPageDocument.kind(url: url, mimeType: document.mimeType)) else { return nil }
        return context
    }

    /// Resolve actual document type before enabling Ask, without reading any body/title/input text.
    func refreshAskOnPageDocument() {
        guard let rt = visibleRuntime, !rt.browser.isLoading, let context = findPageContext(),
              AskOnPagePolicy.canAsk(page: URL(string: context.url), incognito: context.incognito, documentKind: .unknown) else {
            invalidateAskOnPageDocument()
            return
        }
        if askOnPageDocument?.context == context || askOnPageDocumentRead?.context == context { return }
        invalidateAskOnPageDocument()
        let id = UUID()
        askOnPageDocumentRead = (id, context)
        let params = String(data: try! JSONSerialization.data(withJSONObject: [
            "expression": "(() => ({url: document.URL.slice(0, 8192), contentType: (document.contentType || '').slice(0, 128)}))()",
            "returnByValue": true]), encoding: .utf8)!
        rt.browser.evaluate(inIsolatedWorld: PageScript.world, params: params) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, self.askOnPageDocumentRead?.id == id else { return }
                self.askOnPageDocumentRead = nil
                guard self.findPageContext() == context, self.visibleRuntime?.browser.isLoading == false,
                      error == nil, let result, result.utf8.count <= 20_000,
                      let data = result.data(using: .utf8),
                      let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      response["exceptionDetails"] == nil,
                      let value = (response["result"] as? [String: Any])?["value"] as? [String: Any],
                      value["url"] as? String == context.url,
                      let mime = value["contentType"] as? String, !mime.isEmpty, mime.utf8.count <= 128 else { return }
                self.askOnPageDocument = AskOnPageDocumentSnapshot(context: context, mimeType: mime)
                self.delegate?.browserManagerDidUpdate(context.tabID)
            }
        }
    }

    func invalidateAskOnPageDocument(for tab: UUID? = nil) {
        guard tab == nil || askOnPageDocument?.context.tabID == tab || askOnPageDocumentRead?.context.tabID == tab else { return }
        askOnPageDocument = nil
        askOnPageDocumentRead = nil
    }

    /// Revoke quote-purpose Find authority without disturbing ordinary Find when Ask is cleared.
    func clearAskOnPageQuote() {
        if findState.request?.purpose == .quote { stopFinding(false) }
    }

    /// Ordinary Find also works in documents that the model cannot read, including PDF.
    func findPageContext() -> AskOnPageContext? {
        guard let rt = visibleRuntime, rt.browser.isCreated, !rt.browser.isClosed, !rt.discarded,
              rt.browser.isIncognito == store.isIncognito(item: rt.tabID),
              rt.browser.isIncognito || rt.browser.profilePath == store.profilePath(item: rt.tabID) else { return nil }
        return AskOnPageContext(tabID: rt.tabID, spaceID: store.focusedSpaceID(window: windowID), runtime: ObjectIdentifier(rt), navigationRevision: rt.navigationRevision,
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

struct AskOnPageDocumentSnapshot {
    let context: AskOnPageContext
    let mimeType: String
}

/// App-side UTType resolution; Core receives only the classification. No remote resource lookup.
enum AskOnPageDocument {
    static func kind(url: URL, mimeType: String? = nil) -> AskOnPagePolicy.DocumentKind {
        let mime = mimeType?.split(separator: ";", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Real document MIME takes priority over a misleading filename when that evidence is available.
        let type = mime.flatMap { UTType(mimeType: $0) }
            ?? (url.isFileURL ? (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType) : nil)
            ?? UTType(filenameExtension: url.pathExtension)
        guard let type else { return .unknown }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .movie }
        if type.conforms(to: .html) { return .html }
        return .other
    }
}
