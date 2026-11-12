import Foundation

/// Arc's Settings ▸ Advanced ▸ "Reset Translated-site Prompts": "resets any user preference to
/// automatically or never translate specific languages or sites" (resetTranslateSettings). In Cra
/// those choices are Chromium's translate preferences, per profile.
public enum TranslateReset {
    /// The preferences that remember a translate choice or count (Chromium 156, CEF 156.0.27):
    /// the sites "Never Translate This Site" put on the list (the dated list, and the two older
    /// ones a profile may still hold), the "always translate" pairs and the counters that stop the offers.
    /// `translate_blocked_languages` stays: Chromium keeps the user's own languages in it, so
    /// emptying it would offer to translate the pages they read in their own language.
    public static let preferences: [String] = [
        "translate_site_blocklist_with_time", "translate_site_blocklist", "translate_site_blacklist",
        "translate_allowlists", "translate_whitelists",
        "translate_denied_count_for_language", "translate_ignored_count_for_language", "translate_accepted_count",
    ]

    /// What to write over a preference holding `json`: `{}` over a dictionary, `[]` over a list, and nothing
    /// (nil) when it is empty already or is neither, so only what changes is written.
    public static func emptied(_ json: String) -> String? {
        guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]) else { return nil }
        if let d = value as? [String: Any], !d.isEmpty { return "{}" }
        if let a = value as? [Any], !a.isEmpty { return "[]" }
        return nil
    }
}
