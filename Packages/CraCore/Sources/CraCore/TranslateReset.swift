import Foundation

/// Arc's Settings ▸ Advanced ▸ "Reset Translated-site Prompts": "resets any user preference to
/// automatically or never translate specific languages or sites" (resetTranslateSettings,
/// translateNeverHosts and translateSourceLanguagesAlwaysOrNever). In Cra those choices are Chromium's
/// translate preferences, one set per profile.
public enum TranslateReset {
    /// The preferences that hold a translate choice, each put back to Chromium's default as
    /// TranslatePrefs::ResetToDefaults does (Chromium 156: translate_prefs.h, translate_pref_names.h):
    /// the sites never to translate (the dated list and the older one), the languages always to
    /// translate (and the list they were migrated from), the languages never to translate, and the
    /// counts that turn offers into "always" or stop them. `translate_blocked_languages` goes back to its
    /// default (the UI language), not to empty, so Chromium still doesn't offer to translate the language
    /// you read. "Offer to translate" (`translate.enabled`) and the last target language are not a choice
    /// about a site or a language, and stay.
    public static let preferences: [String] = [
        "translate_site_blocklist_with_time", "translate_site_blacklist",
        "translate_allowlists", "translate_whitelists",
        "translate_blocked_languages",
        "translate_denied_count_for_language", "translate_ignored_count_for_language", "translate_accepted_count",
    ]

    /// A profile's Preferences file (Chromium's JSON) without those preferences, for a profile that isn't
    /// loaded: a preference missing from the file loads as its default, as one cleared in a loaded
    /// profile is. nil when the file holds none of them or isn't a JSON object, so it stays untouched.
    public static func resettingPreferencesFile(_ data: Data) -> Data? {
        guard var prefs = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let held = preferences.filter { prefs[$0] != nil }
        guard !held.isEmpty else { return nil }
        for name in held { prefs[name] = nil }
        return try? JSONSerialization.data(withJSONObject: prefs, options: [.withoutEscapingSlashes])
    }
}
