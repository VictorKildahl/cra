import CraCore
import Testing

/// Arc's translate UI on Chromium's translate state (#310).
struct PageTranslationTests {
    static let offer = #"{"url":"https://lenta.ru/","source":"ru","current":"ru","target":"en","available":true,"translated":false,"pending":false,"neverSite":false,"step":"offer","error":0,"userGesture":false}"#

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/310"))
    func decodesChromiumsState() throws {
        let s = try #require(PageTranslation(json: Self.offer))
        #expect(s == PageTranslation(url: "https://lenta.ru/", source: "ru", current: "ru", target: "en", available: true, step: .offer))
        #expect(s.offersTranslation)
        #expect(s.prompt == "Translate this page to English?")
        #expect(s.toast == nil)
    }

    /// A page with no translate client replies {}; that isn't a state.
    @Test func emptyReplyIsNoState() {
        #expect(PageTranslation(json: "{}") == nil)
        #expect(PageTranslation(json: "not json") == nil)
    }

    /// The button stays once the offer is gone (the page in Chromium's same-language run, where it
    /// shows no bubble) and while the page is translated, so the original is a click away.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/310"))
    func buttonOutlivesTheAutomaticOffer() {
        #expect(PageTranslation(available: true).offersTranslation)
        #expect(PageTranslation(translated: true).offersTranslation)
        #expect(PageTranslation(pending: true).offersTranslation)
        // Chromium's offer comes a moment before it marks the page translatable.
        #expect(PageTranslation(source: "ru", step: .offer).offersTranslation)
        #expect(!PageTranslation(source: "en", current: "en").offersTranslation)
        // Never Translate This Site takes the button away, unless the page is translated.
        #expect(!PageTranslation(available: true, neverSite: true).offersTranslation)
        #expect(PageTranslation(available: true, translated: true, neverSite: true).offersTranslation)
    }

    @Test func translatedPageSaysWhereFrom() {
        let s = PageTranslation(source: "de", current: "en", target: "en", available: true, translated: true, step: .translated)
        #expect(s.prompt == "Translated from German.")
        #expect(s.toast == "Translated to English")
        #expect(s.revertedToast == "Translated back to German")
    }

    @Test func errorToastNamesTheError() {
        #expect(PageTranslation(step: .error, error: 1).toast == "Translation error (network)")
        #expect(PageTranslation(step: .error, error: 42).toast == "Translation error (unknown)")
    }

    @Test func noTargetFallsBackToEnglish() {
        #expect(PageTranslation(source: "fr").translateTarget == "en")
    }

    @Test(arguments: [("ru", "Russian"), ("zh-CN", "Chinese (Simplified)"), ("zh-TW", "Chinese (Traditional)"),
                      ("iw", "Hebrew"), ("und", "Unknown"), ("pt", "Portuguese")])
    func languageNames(code: String, name: String) {
        #expect(PageTranslation.name(of: code) == name)
    }

    @Test func otherLanguagesLeaveOutTheShownOne() {
        let s = PageTranslation(current: "en", languages: ["en", "de", "da", "und", "zh-CN"])
        #expect(s.otherLanguages == ["zh-CN", "da", "de"])
    }
}
