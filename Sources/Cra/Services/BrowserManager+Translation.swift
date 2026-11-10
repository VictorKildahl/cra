import AppKit
import CraCEF

/// Page translation (#310): Chromium detects and translates; Cra keeps its state per page for
/// Arc's translate button and popover, and runs their actions through Cra.* methods
/// (scripts/cef-patches/translate-ui.patch, freezing-vote.patch).
extension BrowserManager {
    func browser(_ browser: CraBrowser, didChangeTranslateState state: String) {
        guard let id = tabID(of: browser), let rt = runtimes[id], let t = PageTranslation(json: state) else { return }
        // Cra.getTranslateState's languages stay: the pushed state doesn't carry them.
        var next = t
        if next.languages.isEmpty { next.languages = rt.translation?.languages ?? [] }
        let old = rt.translation
        rt.translation = next
        if old?.offersTranslation != next.offersTranslation || next.step != nil {
            CraLog.note("page \(browser.isIncognito ? "(incognito)" : CraLog.host(next.url)) translate: \(next.step?.rawValue ?? "state") "
                        + "\(next.source)→\(next.translated ? next.current : next.translateTarget)\(next.offersTranslation ? "" : ", none")")
        }
        if let toast = next.toast { delegate?.browserManagerTranslationToast(id, text: toast) }
        delegate?.browserManagerDidUpdate(id)
    }

    /// The page's state with the languages Chromium translates to, for the popover's menu.
    func refreshTranslation(_ id: UUID, then done: (() -> Void)? = nil) {
        runTranslation(id, "Cra.getTranslateState", params: "{}", then: done)
    }

    /// Translates the page to `target`, or to the language Chromium picks (the popover's Translate).
    func translatePage(_ id: UUID, to target: String? = nil) {
        let params = target.map { #"{"target":"\#($0)"}"# } ?? "{}"
        runTranslation(id, "Cra.translatePage", params: params)
    }

    /// Arc's Show Original.
    func revertTranslation(_ id: UUID) {
        guard let source = runtimes[id]?.translation, source.translated else { return }
        runTranslation(id, "Cra.revertTranslation", params: "{}") { [weak self] in
            self?.delegate?.browserManagerTranslationToast(id, text: source.revertedToast)
        }
    }

    /// Arc's Never Translate This Site: the host goes on the profile's never-translate list.
    func neverTranslateSite(_ id: UUID, _ never: Bool = true) {
        runTranslation(id, "Cra.neverTranslateSite", params: #"{"never":\#(never)}"#)
    }

    private func runTranslation(_ id: UUID, _ method: String, params: String, then done: (() -> Void)? = nil) {
        guard let rt = runtimes[id] else { return }
        rt.browser.sendDevToolsMethod(method, params: params) { [weak self, weak rt] result, error in
            DispatchQueue.main.async {
                guard let self, let rt, self.runtimes[id] === rt else { return }
                if let error { CraLog.note("\(method) failed: \(error)") }
                if let result, var t = PageTranslation(json: result) {
                    if t.languages.isEmpty { t.languages = rt.translation?.languages ?? [] }
                    rt.translation = t
                    self.delegate?.browserManagerDidUpdate(id)
                }
                done?()
            }
        }
    }
}
