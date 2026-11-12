import Foundation
import CraCore
import Testing

/// Arc's "Reset Translated-site Prompts" (resetTranslateSettings: "resets any user preference to
/// automatically or never translate specific languages or sites"), on Chromium's translate
/// preferences. Names from Chromium 156's translate_prefs.h and translate_pref_names.h (CEF 156.0.27).
struct TranslateResetTests {
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/373"))
    func theSitesAndLanguagesYouChoseAreForgotten() {
        let names = TranslateReset.preferences
        // Never translate these sites (the dated list and the one older profiles hold).
        #expect(names.contains("translate_site_blocklist_with_time"))
        #expect(names.contains("translate_site_blacklist"))
        // Always translate these languages (and the list it was migrated from).
        #expect(names.contains("translate_allowlists"))
        #expect(names.contains("translate_whitelists"))
        // Never translate these languages: back to Chromium's default (the UI language), as
        // TranslatePrefs::ResetToDefaults does, not emptied.
        #expect(names.contains("translate_blocked_languages"))
        // The counts that turn offers into "always" or stop them.
        #expect(names.contains("translate_denied_count_for_language"))
        #expect(names.contains("translate_ignored_count_for_language"))
        #expect(names.contains("translate_accepted_count"))
        #expect(Set(names).count == names.count, "each once")
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/373"))
    func theOfferSwitchAndYourLanguagesStay() {
        // Not a choice about a site or a language: "Offer to translate" and the page languages.
        #expect(!TranslateReset.preferences.contains("translate.enabled"))
        #expect(!TranslateReset.preferences.contains("intl.accept_languages"))
    }

    /// A profile that hasn't loaded in this session: its Preferences file loses the choices, so each
    /// comes back as Chromium's default when the profile loads, as a reset of a loaded one does.
    @Test(.bug("https://github.com/VictorKildahl/cra/issues/373"))
    func aProfileThatIsNotLoadedHasItsFileReset() throws {
        let file = #"""
        {"browser":{"window_placement":{"left":10}},"intl":{"accept_languages":"en-US,da"},
         "translate":{"enabled":true},"translate_accepted_count":{"fr":2},
         "translate_allowlists":{"fr":"en"},"translate_blocked_languages":["en","da"],
         "translate_denied_count_for_language":{"de":3},"translate_recent_target":"en",
         "translate_site_blocklist_with_time":{"example.com":"13345678901234567"},
         "profile":{"name":"Work","exit_type":"Normal"}}
        """#
        let out = try #require(TranslateReset.resettingPreferencesFile(Data(file.utf8)))
        let dict = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        for name in TranslateReset.preferences { #expect(dict[name] == nil, "\(name)") }
        // Everything else is as it was.
        #expect((dict["profile"] as? [String: String]) == ["name": "Work", "exit_type": "Normal"])
        #expect((dict["intl"] as? [String: String]) == ["accept_languages": "en-US,da"])
        #expect((dict["translate"] as? [String: Bool]) == ["enabled": true])
        #expect(dict["translate_recent_target"] as? String == "en")
        #expect(((dict["browser"] as? [String: Any])?["window_placement"] as? [String: Int]) == ["left": 10])
        #expect(!String(decoding: out, as: UTF8.self).contains(#"\/"#))
    }

    @Test(.bug("https://github.com/VictorKildahl/cra/issues/373"))
    func aFileWithNothingToForgetIsLeftAlone() {
        #expect(TranslateReset.resettingPreferencesFile(Data(#"{"profile":{"name":"Work"}}"#.utf8)) == nil)
        #expect(TranslateReset.resettingPreferencesFile(Data("not json".utf8)) == nil)
        #expect(TranslateReset.resettingPreferencesFile(Data(#"["translate_allowlists"]"#.utf8)) == nil)
        #expect(TranslateReset.resettingPreferencesFile(Data()) == nil)
    }
}
