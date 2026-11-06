import Foundation

/// The languages a profile asks websites for, most wanted first (GitHub #209): Chromium's
/// `intl.accept_languages`, which becomes the Accept-Language header and `navigator.languages`.
/// It is not Cra's interface language, which stays English (#34).
///
/// Arc has no control of its own for it. Its Translate bubble's "Language Settings" item and
/// Settings ▸ Advanced ▸ More Settings open Chromium's page, arc://settings/languages, which is
/// per profile (Arc 1.171's binary: `chrome://settings/languages`, `settings/languages`). Cra
/// lists each profile's languages under Settings ▸ Profiles and opens that page in the profile.
/// The page edits `intl.selected_languages` and Chromium derives `intl.accept_languages` from it.
/// Open pages pick a change up at once, so no reload is needed (checked in
/// Tests/Scenarios/accept-languages.scenario).
public enum BrowserLanguages {
    public static let settingsPage = "chrome://settings/languages"
    /// language::prefs::kAcceptLanguages.
    public static let pref = "intl.accept_languages"

    /// The codes in a pref value, in order: "da,en-GB" or its JSON form "\"da,en-GB\"", which is
    /// how CraCEFRuntime.preference returns it. Empty for anything else.
    public static func codes(_ value: String) -> [String] {
        var list = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if list.hasPrefix("\"") {
            guard let data = list.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(String.self, from: data) else { return [] }
            list = decoded
        }
        var seen = Set<String>()
        return list.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" } }
            .filter { seen.insert($0.lowercased()).inserted }
    }

    /// The codes saved in a profile's Preferences file, for a profile Chromium hasn't loaded in
    /// this session. Nil when the file doesn't hold the pref (a profile never opened).
    public static func codes(preferencesFile data: Data) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = (root["intl"] as? [String: Any])?["accept_languages"] as? String else { return nil }
        let list = codes(value)
        return list.isEmpty ? nil : list
    }

    /// A code's English name, as Cra's interface is English: "da" is "Danish", "en-GB" "English
    /// (United Kingdom)". A code Foundation doesn't know stays as it is.
    public static func name(_ code: String) -> String {
        Locale(identifier: "en_US").localizedString(forIdentifier: code) ?? code
    }

    /// The row's summary: "Danish, English (United Kingdom), English".
    public static func summary(_ codes: [String]) -> String {
        codes.map(name).joined(separator: ", ")
    }
}
