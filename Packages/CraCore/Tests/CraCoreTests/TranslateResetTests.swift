import Foundation
import CraCore
import Testing

/// Arc's "Reset Translated-site Prompts" (resetTranslateSettings: "resets any user preference to
/// automatically or never translate specific languages or sites"), on Chromium's translate
/// preferences. Names read from the Chromium 156 build Cra ships (CEF 156.0.27).
struct TranslateResetTests {
    @Test func theSitesYouNeverTranslateAndTheLanguagesYouAlwaysDoAreForgotten() {
        let names = TranslateReset.preferences
        #expect(names.contains("translate_site_blocklist_with_time"))
        #expect(names.contains("translate_site_blocklist"))
        #expect(names.contains("translate_allowlists"))
        #expect(names.contains("translate_denied_count_for_language"))
        #expect(names.contains("translate_ignored_count_for_language"))
        #expect(Set(names).count == names.count, "each once")
    }

    @Test func theLanguagesYouReadStayBecauseChromiumKeepsThemWithTheAcceptedOnes() {
        // translate_blocked_languages holds the user's own languages: emptying it would offer to
        // translate the page they are reading in their own language.
        #expect(!TranslateReset.preferences.contains("translate_blocked_languages"))
        #expect(!TranslateReset.preferences.contains("intl.accept_languages"))
    }

    @Test func aPreferenceIsEmptiedToItsOwnKindOfNothing() {
        #expect(TranslateReset.emptied(#"{"example.com":1700000000}"#) == "{}")
        #expect(TranslateReset.emptied(#"["example.com"]"#) == #"[]"#)
        #expect(TranslateReset.emptied("{}") == nil, "already empty: nothing to write")
        #expect(TranslateReset.emptied("[]") == nil)
        #expect(TranslateReset.emptied("3") == nil, "a number or a string is left alone")
        #expect(TranslateReset.emptied(#""x""#) == nil)
        #expect(TranslateReset.emptied("not json") == nil)
    }
}
