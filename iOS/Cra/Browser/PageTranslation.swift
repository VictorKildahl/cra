import CraCore
import NaturalLanguage
import SwiftUI
import Translation
import UIKit

/// Translate in the page menu: the page's text into the phone's language, on the phone, with
/// Apple's Translation framework (`MobileTranslate` has the scripts and the batching). The first
/// time a language pair is used the system asks to download it, as Arc Search asks before it
/// sends a page to Google. "Show Original" puts the page's own words back.
extension BrowserViewController {
    func translate(_ page: WebPage) {
        if page.isTranslated {
            page.webView.evaluateJavaScript(MobileTranslate.restoreScript) { [weak self] _, _ in
                page.isTranslated = false
                self?.refreshMenu()
            }
            return
        }
        page.webView.evaluateJavaScript(MobileTranslate.collectScript) { [weak self] result, _ in
            guard let self else { return }
            let texts = (result as? [String]) ?? []
            guard !texts.isEmpty else { return self.announce("Nothing to translate on this page", symbol: "translate", id: "translate-toast") }
            if LaunchOptions.value("CraFakeTranslate") == "YES" {
                // Tests: capitals stand in for another language, no model needed.
                return self.finishTranslation(page, texts.map { $0.uppercased() })
            }
            let target = Locale.Language(identifier: AnswerLanguage.code)
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(MobileTranslate.languageSample(texts))
            guard let detected = recognizer.dominantLanguage else {
                return self.announce("Couldn't tell the page's language", symbol: "translate", id: "translate-toast")
            }
            let source = Locale.Language(identifier: detected.rawValue)
            if source.languageCode == target.languageCode {
                return self.announce("This page is already in \(Locale.current.localizedString(forLanguageCode: detected.rawValue) ?? detected.rawValue)",
                                     symbol: "translate", id: "translate-toast")
            }
            guard #available(iOS 18.0, *) else {
                return self.announce("Translate needs iOS 18", symbol: "translate", id: "translate-toast")
            }
            self.announce("Translating…", symbol: "translate", id: "translate-toast")
            TranslationRunner.run(texts: texts, from: source, to: target, in: self) { [weak self] translations in
                guard let self else { return }
                guard let translations else {
                    return self.announce("Couldn't translate this page", symbol: "exclamationmark.triangle", id: "translate-toast")
                }
                self.finishTranslation(page, translations)
            }
        }
    }

    private func finishTranslation(_ page: WebPage, _ translations: [String]) {
        page.webView.evaluateJavaScript(MobileTranslate.applyScript(translations)) { [weak self] _, _ in
            page.isTranslated = true
            self?.refreshMenu()
        }
    }
}

/// Runs a translation session from a hidden SwiftUI view: the framework hands sessions out only
/// through `.translationTask`, which also shows the system's download prompt when a language is missing.
@available(iOS 18.0, *)
@MainActor
enum TranslationRunner {
    static func run(texts: [String], from source: Locale.Language, to target: Locale.Language,
                    in controller: UIViewController, done: @escaping ([String]?) -> Void) {
        var host: UIHostingController<TranslationTaskView>?
        let finish: ([String]?) -> Void = { result in
            host?.willMove(toParent: nil)
            host?.view.removeFromSuperview()
            host?.removeFromParent()
            host = nil
            done(result)
        }
        let view = TranslationTaskView(configuration: .init(source: source, target: target)) { session in
            do {
                try await session.prepareTranslation()
                var out = texts
                for batch in MobileTranslate.batches(texts) {
                    let requests = batch.map { TranslationSession.Request(sourceText: texts[$0], clientIdentifier: String($0)) }
                    for response in try await session.translations(from: requests) {
                        if let id = response.clientIdentifier, let index = Int(id) { out[index] = response.targetText }
                    }
                }
                finish(out)
            } catch {
                finish(nil)
            }
        }
        let hosting = UIHostingController(rootView: view)
        hosting.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        hosting.view.isUserInteractionEnabled = false
        hosting.view.backgroundColor = .clear
        controller.addChild(hosting)
        controller.view.addSubview(hosting.view)
        hosting.didMove(toParent: controller)
        host = hosting
    }
}

@available(iOS 18.0, *)
struct TranslationTaskView: View {
    let configuration: TranslationSession.Configuration
    let work: (TranslationSession) async -> Void

    var body: some View {
        Color.clear.translationTask(configuration) { session in await work(session) }
    }
}
