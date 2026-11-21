import Foundation

/// What every profile is called (GitHub #666). Arc renames all of its profiles, the default one too
/// (its Settings ▸ Profiles), and keeps the name in Chromium's own profile list: Victor's Arc has
/// `profile.info_cache.Default.name` "Victor" with `is_using_default_name` false in Local State, so
/// chrome:// pages and extensions see the name Arc shows. Cra kept no name for Default ("Default",
/// not renameable) and never told Chromium, which called its profiles "Your Chromium" or "Person n".
public enum ProfileNames {
    /// The default profile's name until it is renamed.
    public static let defaultName = "Default"

    /// The name shown for profile `id` (nil: Default).
    public static func name(of id: UUID?, profiles: [BrowserProfile], defaultProfileName: String?) -> String {
        guard let id else { return cleaned(defaultProfileName ?? "") ?? defaultName }
        return profiles.first { $0.id == id }?.name ?? defaultName
    }

    /// A typed name as it is kept: trimmed, nil when nothing is left (the rename does nothing).
    public static func cleaned(_ typed: String) -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// The default profile's name as `sidebar.json` keeps it: nil while it is the default one, so a
    /// file never renamed stays as it was.
    public static func stored(defaultProfileName typed: String) -> String? {
        cleaned(typed).flatMap { $0 == defaultName ? nil : $0 }
    }

    /// The prefs that give a Chromium profile its name, as JSON: Chromium's ProfileImpl copies them
    /// into Local State's profile list (UpdateNameInStorage), as a rename on chrome://settings does.
    public static func chromiumPrefs(name: String) -> [(pref: String, json: String)] {
        let data = (try? JSONSerialization.data(withJSONObject: [name], options: [])) ?? Data("[\"\"]".utf8)
        let quoted = String(decoding: data, as: UTF8.self).dropFirst().dropLast()
        return [("profile.name", String(quoted)), ("profile.using_default_name", "false")]
    }
}
