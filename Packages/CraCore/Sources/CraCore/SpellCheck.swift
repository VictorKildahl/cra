import Foundation

/// Spell checking in a profile's text fields (GitHub #715): Chromium's browser.enable_spellchecking,
/// on by default, which chrome://settings/languages ▸ Spell check sets. Settings ▸ Profiles has it
/// as "Check spelling while typing", beside the website languages, per profile as Chromium keeps it.
public enum SpellCheck {
    public static let pref = "browser.enable_spellchecking"

    /// From the pref as Chromium holds it (JSON); nil (not loaded, never set) is Chromium's default, on.
    public static func isOn(prefJSON: String?) -> Bool { prefJSON != "false" }

    /// From a profile's Preferences file, for a profile no page has loaded since launch.
    public static func isOn(preferencesFile data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let browser = root["browser"] as? [String: Any], let on = browser["enable_spellchecking"] as? Bool else { return true }
        return on
    }

    public static func json(on: Bool) -> String { on ? "true" : "false" }
}
