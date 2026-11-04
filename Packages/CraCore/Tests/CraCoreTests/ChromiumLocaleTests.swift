import CraCore
import Testing

/// Chromium's application locale follows macOS the way Chrome's and Arc's do (#167).
struct ChromiumLocaleTests {
    /// The folder names in CEF 156's Resources: one per locale plus gendered variants.
    static let cef: [String] = {
        let locales = ["af", "am", "ar", "bg", "bn", "ca", "cs", "da", "de", "el", "en", "en_GB", "es", "es_419",
                       "et", "fa", "fi", "fil", "fr", "gu", "he", "hi", "hr", "hu", "id", "it", "ja", "kn", "ko",
                       "lt", "lv", "ml", "mr", "ms", "nb", "nl", "pl", "pt_BR", "pt_PT", "ro", "ru", "sk", "sl",
                       "sr", "sv", "sw", "ta", "te", "th", "tr", "uk", "ur", "vi", "zh_CN", "zh_TW"]
        return locales.flatMap { [$0, $0 + "_FEMININE", $0 + "_MASCULINE", $0 + "_NEUTER"] }
    }()

    // Each expectation is what Arc 1.171's bundle resolves for the same macOS languages.
    // Typed up front: as an untyped literal in @Test(arguments:) the type checker timed out
    // on Xcode 27.2 (reported in #179).
    static let languages: [([String], String)] = [
        (["zh-Hans-CN"], "zh-CN"),
        (["zh-Hans"], "zh-CN"),
        (["zh-Hant-TW"], "zh-TW"),
        (["zh-Hant-HK"], "zh-TW"),
        (["en-US"], "en-US"),
        (["en"], "en-US"),
        (["en-DK", "da-DK"], "en-GB"),
        (["en-AU"], "en-GB"),
        (["da-DK"], "da"),
        (["pt-PT"], "pt-PT"),
        (["es-MX"], "es-419"),
        (["nb-NO"], "nb"),
        // A language Chromium has no translation for falls through to the next one.
        (["is-IS", "de-DE"], "de"),
        (["is-IS"], "en-US"),
    ]

    @Test(arguments: languages)
    func followsMacOS(preferred: [String], locale: String) {
        #expect(ChromiumLocale.pick(available: Self.cef, preferredLanguages: preferred) == locale)
    }

    @Test func noLocalesLeavesCEFsDefault() {
        #expect(ChromiumLocale.pick(available: [], preferredLanguages: ["zh-Hans-CN"]) == nil)
        #expect(ChromiumLocale.pick(available: ["Base"], preferredLanguages: ["zh-Hans-CN"]) == nil)
    }
}
